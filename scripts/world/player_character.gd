class_name PlayerCharacter
extends CharacterBody3D
## A crew member, played in first person: walk, run, jump, dive and tackle,
## look with the mouse, and press machines with your hands.
## World-side only: it emits requests as signals and calls press() on what you
## look at; it never touches chips, Heat, IDs or outfits.
##
## Local player: a CameraRig head at eye height (mouse look, head bob, landing
## dip, dive / tackle / tumble lunges, the carried view) with FirstPersonHands
## under its camera. Its own CharacterModel body still animates (and syncs)
## but sits on FpTuning.SELF_BODY_LAYER, which its camera leaves out, so the
## crew sees it and you don't. Non-local players have the body and no camera,
## hands or input.
##
## Pressing: every physics frame a ray from the camera centre (FpTuning.REACH
## m, physics layer 5, bodies and areas) finds what you look at. A
## "pressable" is any node with press(pid) (duck typed: hint, enabled,
## hold_seconds, get_hint(), set_hovered(), press(), hold_complete()); a
## legacy Interactable (Area3D) also counts, and when the ray finds nothing
## the nearest enabled Interactable in the old sensor in front of the view is
## the fallback. LMB (or E) presses it; a target with hold_seconds > 0 must
## be held (hold_progress, then hold_complete(pid) / interact_held; a quick
## tap is a press). A legacy Interactable press emits interact_pressed (the
## director's interact() calls use()); with nothing connected the player calls
## target.use(self) itself. begin_capture(capturer) routes LMB / E to it
## (primary_pressed / primary_released, and capturer.on_primary_pressed(pid) /
## on_primary_released(pid) if it has them) instead of pressing pressables.
##
## ID card: Tab raises the IdCard3D (set_id_card) in the left hand; while it is
## up the mouse wheel emits id_cycle(+1 / -1) for the director to swap IDs.
##
## Emote (T): standing still and free, plays the next of `emotes` (the
## player's unlocked emotes) for EMOTE_SECONDS on the body (the crew sees it;
## the hands wave). Moving cancels it.
##
## Co-op: the owning peer moves its own player and publishes net_* every
## physics frame; enable_net_sync() adds the MultiplayerSynchronizer that
## carries them. On every other peer the player is a `puppet`: no physics and
## no input, it eases toward the synced position, facing and look pitch and
## copies the synced pose and state.

## Legacy Interactable pressed with LMB / E (the director's interact flow).
signal interact_pressed(target: Interactable)
## Interact held for target.hold_seconds (a tap on a hold interactable is a press).
signal interact_held(target: Interactable)
## F, or a dive, reached a node in group &"guards" within TACKLE_RANGE in front.
signal tackle_requested(target: Node3D)
## Ran into a guard (once per contact).
signal bumped(guard: Node3D)
signal throw_chips_requested(position: Vector3)
signal knock_over_requested(target: Interactable)
## Jump pressed while carried.
signal struggled()
signal pause_requested()
## The legacy Interactable you would use changed (null = none).
signal focus_changed(target: Interactable)
## Jump pressed while seated: the director can stand the player up.
signal stand_requested()
## Give-chips pressed (H) with a teammate within GIVE_RANGE.
signal give_chips_requested(target: PlayerCharacter)
## An emote started (the emote key or play_emote()).
signal emoted(emote_id: StringName)
## What you look at changed: a pressable, a legacy Interactable or null, with
## its hint text (get_hint() / prompt). Re-emitted when the hint text changes.
signal hover_changed(target: Node, hint: String)
## LMB / E went down / up (always, captured or not; never while input is off).
signal primary_pressed()
signal primary_released()
## This player called press(pid) / hold_complete(pid) on a pressable.
signal target_pressed(target: Node)
signal target_held(target: Node)
## 0..1 while holding LMB on a hold target; 0 when the hold ends or stops.
signal hold_progress(ratio: float)
## begin_capture(capturer) / end_capture(): the capturer, or null when released.
signal capture_changed(capturer: Object)
## Tab raised or lowered the ID card.
signal id_card_toggled(raised: bool)
## Mouse wheel while the ID card is up: +1 next card, -1 previous.
signal id_cycle(direction: int)
## A footstep of the local player (for sounds).
signal footstep(running: bool)
## Touched down after a fall of `speed` m/s.
signal landed(speed: float)

const STATE_FREE := &"free"
const STATE_SEATED := &"seated"
const STATE_CARRIED := &"carried"
const STATE_HIDDEN := &"hidden"

const ACTION_NONE := &""
const ACTION_DIVE := &"dive"
const ACTION_TACKLE := &"tackle"
const ACTION_PRONE := &"prone"
const ACTION_TUMBLE := &"tumble"

const GUARD_GROUP := &"guards"
const GROUP := &"players"
## A teammate this close (flat metres) can be handed chips (H).
const GIVE_RANGE := 2.5
## Seconds between position syncs to the other peers.
const NET_SYNC_INTERVAL := 1.0 / 30.0
## A puppet further than this from its synced position snaps to it.
const PUPPET_SNAP_DISTANCE := 4.0
## How fast a puppet closes the gap to its synced position (1/s).
const PUPPET_SHARPNESS := 16.0
const NAMEPLATE_HEIGHT := 2.3
## How long one press of the emote key plays an emote.
const EMOTE_SECONDS := 3.0
const PLAYER_LAYER := 2
## World + guard + patron.
const BODY_MASK := 1 | 4 | 8
const INTERACTABLE_MASK := 16
## What the hands keep clear of (world, guards, patrons).
const CLEARANCE_MASK := 1 | 4 | 8

var pid: int = 1
var is_local: bool = true
var model: CharacterModel
## The first-person head (only on local players).
var camera_rig: CameraRig
## The first-person hands under the camera (only on local players).
var hands: FirstPersonHands
## The ID card the hands raise (local players, created on first use).
var id_card: IdCard3D
## One of the STATE_* names (read-only; use sit_at, set_carried, set_hidden...).
var state: StringName = STATE_FREE
## One of the ACTION_* names while free (read-only).
var action: StringName = ACTION_NONE
## Body yaw in radians; 0 faces -Z. The look heading while free, a dive's
## direction mid-dive, the seat's or the carrier's heading.
var facing: float = 0.0
## Look pitch (radians, > 0 up): the camera's on the owner, synced to puppets.
var look_pitch: float = 0.0
## How far the look ray reaches (m).
var reach: float = FpTuning.REACH
## Co-op: another peer's player, driven by the synced net_* values.
var puppet: bool = false
## Name over a teammate's head (co-op), or null.
var nameplate: Label3D
# Synced from the owner to the other peers (see enable_net_sync()).
var net_position: Vector3 = Vector3.ZERO
var net_facing: float = 0.0
var net_pitch: float = 0.0
var net_velocity: Vector3 = Vector3.ZERO
var net_pose: StringName = &"idle"
var net_state: StringName = STATE_FREE
var net_running: bool = false
## Emotes the emote key cycles through (unlocked emote ids, CharacterModel
## poses), in order. Starts with the starter emote.
var emotes: Array[StringName] = [&"wave"]

var _shape: CollisionShape3D
var _front: Node3D
var _sensor: Area3D
var _input_enabled := true
var _focus: Interactable
var _target: Node
var _target_point := Vector3.ZERO
var _hint := ""
var _hold_target: Node
var _hold_time := 0.0
var _hold_done := false
var _primary_down := false
var _swallow_click := false
var _capture: Object
var _id_raised := false
var _carrier: Node3D
var _seat := Transform3D.IDENTITY
var _playing := false
var _emote: StringName = &""
var _emote_left := 0.0
var _action_time := 0.0
var _action_hit := false
var _action_dir := Vector3.FORWARD
var _running := false
var _jumped := false
var _air_time := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _bump_contacts: Dictionary = {}
var _net_sync: bool = false
var _next_emote: int = 0
var _time := 0.0
var _self_layered := false


func _init() -> void:
	add_to_group(GROUP)
	collision_layer = PLAYER_LAYER
	collision_mask = BODY_MASK
	floor_snap_length = 0.25
	_shape = CollisionShape3D.new()
	_shape.name = "Capsule"
	var capsule := CapsuleShape3D.new()
	capsule.radius = Tuning.PLAYER_RADIUS
	capsule.height = Tuning.PLAYER_HEIGHT
	_shape.shape = capsule
	_shape.position = Vector3(0, Tuning.PLAYER_HEIGHT * 0.5, 0)
	add_child(_shape)
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	_front = Node3D.new()
	_front.name = "Front"
	add_child(_front)
	# Legacy fallback: Interactables in front of the view when the ray finds nothing.
	_sensor = Area3D.new()
	_sensor.name = "InteractSensor"
	_sensor.collision_layer = 0
	_sensor.collision_mask = INTERACTABLE_MASK
	_sensor.monitorable = false
	var sensor_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Tuning.PLAYER_INTERACT_RADIUS
	sensor_shape.shape = sphere
	_sensor.add_child(sensor_shape)
	_sensor.position = Vector3(0, CharacterModel.HIP_Y, -Tuning.PLAYER_INTERACT_REACH)
	_front.add_child(_sensor)


## pid seeds the body. Local players get the first-person head, the hands and
## read input; others drop them.
func setup(player_id: int, local: bool, outfit: Outfit) -> void:
	pid = player_id
	is_local = local
	model.appearance_seed = player_id
	set_outfit(outfit)
	if is_local:
		InputSetup.ensure_actions()
		if camera_rig == null:
			camera_rig = CameraRig.new()
			add_child(camera_rig)
			camera_rig.setup(self)
			camera_rig.yaw = facing
			camera_rig.set_look_enabled(_input_enabled)
			hands = FirstPersonHands.new()
			camera_rig.camera.add_child(hands)
			camera_rig.hands = hands
			camera_rig.looked.connect(hands.add_look_sway)
			camera_rig.footstep.connect(_on_footstep)
			if is_inside_tree() and _input_enabled:
				camera_rig.set_mouse_captured(true)
		hands.set_skin(_skin_color())
		if is_inside_tree():
			hands.drop_parent = get_parent()
	else:
		if camera_rig != null:
			camera_rig.queue_free()
			camera_rig = null
			hands = null
	_apply_body_layers()
	if is_inside_tree():
		_watch_body(is_local)


func _ready() -> void:
	if is_local and camera_rig != null and _input_enabled:
		camera_rig.set_mouse_captured(true)
	if hands != null:
		hands.drop_parent = get_parent()
	_apply_body_layers()


func _enter_tree() -> void:
	_watch_body(is_local)


func _exit_tree() -> void:
	_watch_body(false)


# --- Public API ---------------------------------------------------------------

## Holding run and moving (free, not mid-dive). Drives running_in_view.
func is_running() -> bool:
	if puppet:
		return net_running
	return _running and state == STATE_FREE and action == ACTION_NONE


## Adds the MultiplayerSynchronizer that sends net_* from the owner (the
## peer with this node's multiplayer authority) to the others.
func enable_net_sync() -> void:
	_net_sync = true
	_publish()
	NetSync.attach(self, [&"net_position", &"net_facing", &"net_pitch", &"net_velocity"], [&"net_pose", &"net_state", &"net_running"], NET_SYNC_INTERVAL)


## Makes this another peer's player (see `puppet`), placed at `pos`.
func make_puppet(pos: Vector3) -> void:
	puppet = true
	_reset_motion()
	net_position = pos
	_place(pos)


## A name label over the head (co-op teammates); "" removes it.
func set_nameplate(text: String, color: Color = Color.WHITE) -> void:
	if text == "":
		if nameplate != null:
			nameplate.queue_free()
			nameplate = null
		return
	if nameplate == null:
		nameplate = Primitives.label(text, 0.007)
		nameplate.name = "Nameplate"
		nameplate.font_size = 48
		nameplate.outline_size = 12
		# Over walls and door frames, like the guards' icons.
		nameplate.no_depth_test = true
		nameplate.position = Vector3(0, NAMEPLATE_HEIGHT, 0)
		add_child(nameplate)
	nameplate.text = text
	nameplate.modulate = color


## The legacy Interactable a press would use (looked at, or the fallback in
## front), or null. See current_target() for pressables too.
func current_interactable() -> Interactable:
	if _focus != null and not is_instance_valid(_focus):
		_focus = null
	return _focus


## What a press would press right now (a pressable or an Interactable), or null.
func current_target() -> Node:
	if _target != null and not is_instance_valid(_target):
		_target = null
	return _target


## Hint text of current_target() ("" for none).
func current_hint() -> String:
	return _hint if current_target() != null else ""


## Where the look ray hit the current target (world space).
func target_point() -> Vector3:
	return _target_point


## 0..1 progress of a hold in progress (0 when none).
func interact_hold_progress() -> float:
	if _hold_target == null or not is_instance_valid(_hold_target):
		return 0.0
	var need := _hold_seconds_of(_hold_target)
	if need <= 0.0:
		return 0.0
	return clampf(_hold_time / need, 0.0, 1.0)


## Routes LMB / E to `capturer` (a machine taking raw input, e.g. a dice
## throw) until end_capture(): primary_pressed / primary_released fire and
## capturer.on_primary_pressed(pid) / on_primary_released(pid) are called if
## it has them; nothing gets pressed. Being carried or hidden ends it.
func begin_capture(capturer: Object) -> void:
	if capturer == null:
		end_capture()
		return
	_capture = capturer
	_cancel_hold()
	_set_target(null)
	capture_changed.emit(capturer)


## Ends the capture (only `capturer`'s, unless null).
func end_capture(capturer: Object = null) -> void:
	if _capture == null:
		return
	if capturer != null and capturer != _capture:
		return
	_capture = null
	capture_changed.emit(null)


func is_captured() -> bool:
	if _capture != null and not is_instance_valid(_capture):
		_capture = null
	return _capture != null


func capture_owner() -> Object:
	return _capture if is_captured() else null


## Puts this ID (FakeId.to_dict()) on the card the hands raise, with the
## outfit's colours as its photo; `index` / `count` show "2/3" on it.
func set_id_card(id_dict: Dictionary, outfit_dict: Dictionary = {}, index: int = 0, count: int = 1) -> void:
	var card := _ensure_card()
	card.set_id(id_dict, outfit_dict, _skin_color())
	card.set_index(index, count)


## Raises (true) or lowers the ID card in the left hand (Tab toggles it).
func raise_id_card(raised: bool) -> void:
	if hands == null:
		_id_raised = false
		return
	if raised == _id_raised:
		return
	_id_raised = raised
	if raised:
		hands.show_id_card(_ensure_card())
	else:
		hands.hide_id_card()
	id_card_toggled.emit(raised)


func is_id_raised() -> bool:
	return _id_raised


## Points the view (and a free body) at a world point.
func look_toward(point: Vector3) -> void:
	if camera_rig == null:
		var to := point - global_position
		to.y = 0.0
		if to.length_squared() > 0.0001:
			facing = _yaw_of(to)
			_apply_facing()
		return
	camera_rig.look_toward(point)
	look_pitch = camera_rig.pitch
	if state == STATE_FREE and action == ACTION_NONE:
		facing = camera_rig.view_yaw()
		_apply_facing()


## The eye in world space.
func eye_position() -> Vector3:
	if camera_rig != null and camera_rig.is_inside_tree():
		return camera_rig.eye_position()
	return camera_focus()


## Where the view looks (world, unit).
func look_direction() -> Vector3:
	if camera_rig != null:
		return camera_rig.look_direction()
	return Basis.from_euler(Vector3(look_pitch, facing, 0.0)) * Vector3.FORWARD


## Snaps onto a seat (origin at floor level under the seat, facing its -Z):
## collision and movement off, sit pose, the view turned to the table.
func sit_at(seat: Transform3D) -> void:
	_reset_motion()
	_carrier = null
	_seat = seat
	state = STATE_SEATED
	_playing = false
	_set_collision(false)
	model.visible = true
	_place(seat.origin)
	var forward := -seat.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		facing = _yaw_of(forward)
	_apply_facing()
	model.set_pose(&"sit")
	if camera_rig != null:
		camera_rig.clear_follow()
		camera_rig.yaw = facing
		camera_rig.add_look(0.0, deg_to_rad(-25.0) - camera_rig.pitch)


## Leaves the seat, stepping back away from the table.
func stand_up() -> void:
	if state != STATE_SEATED:
		return
	var back := _seat.basis.z
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK
	_enter_free()
	_place(_seat.origin + back * Tuning.PLAYER_STAND_UP_STEP)
	# Look up from the table.
	if camera_rig != null and camera_rig.pitch < -0.3:
		camera_rig.add_look(0.0, -0.12 - camera_rig.pitch)


## While seated: the "play" pose (a round in progress) instead of "sit".
func set_playing(playing: bool) -> void:
	_playing = playing


## Plays a pose (e.g. &"celebrate") for a few seconds while standing still.
func emote(pose: StringName, seconds: float) -> void:
	_emote = pose
	_emote_left = seconds
	_hands_emote(pose)


## Sets the emotes the emote key plays (unknown poses are dropped); the next
## press starts from the first.
func set_emotes(ids: Array) -> void:
	emotes.clear()
	for id: Variant in ids:
		var e := StringName(str(id))
		if CharacterModel.EMOTES.has(e) and not emotes.has(e):
			emotes.append(e)
	_next_emote = 0


## Plays an emote pose for EMOTE_SECONDS. Only while free and not mid-action
## (dive, tackle, tumble); false otherwise or for an unknown emote.
func play_emote(emote_id: StringName) -> bool:
	if not CharacterModel.EMOTES.has(emote_id) or state != STATE_FREE or action != ACTION_NONE:
		return false
	emote(emote_id, EMOTE_SECONDS)
	model.set_pose(emote_id)
	emoted.emit(emote_id)
	return true


## The emote key: plays the next of `emotes` (cycling). Returns its id, or
## &"" if none played.
func play_next_emote() -> StringName:
	if emotes.is_empty():
		return &""
	var id: StringName = emotes[_next_emote % emotes.size()]
	if not play_emote(id):
		return &""
	_next_emote = (_next_emote + 1) % emotes.size()
	return id


## Follows carrier.get_carry_point() with the carrier's facing until release().
## null releases on the spot. The view rides the shoulder looking back.
func set_carried(carrier: Node3D) -> void:
	if carrier == null:
		release(global_position)
		return
	_reset_motion()
	end_capture()
	raise_id_card(false)
	_carrier = carrier
	state = STATE_CARRIED
	_set_collision(false)
	model.visible = true
	if is_inside_tree() and carrier.is_inside_tree():
		_follow_carrier()
	model.set_pose(&"carried")
	if camera_rig != null:
		camera_rig.set_follow(facing + PI)
		camera_rig.add_look(0.0, deg_to_rad(FpTuning.CARRIED_PITCH_DEGREES) - camera_rig.pitch)
	if hands != null:
		hands.set_flail(true)


func release(at: Vector3) -> void:
	_carrier = null
	if state == STATE_CARRIED:
		_enter_free()
	teleport(at)


func is_carried() -> bool:
	return state == STATE_CARRIED


func teleport(pos: Vector3) -> void:
	if state == STATE_SEATED or state == STATE_CARRIED:
		_carrier = null
		_enter_free()
	_place(pos)
	velocity = Vector3.ZERO
	_bump_contacts.clear()
	_was_on_floor = true
	if camera_rig != null:
		_update_head(0.0)


func set_outfit(outfit: Outfit) -> void:
	model.apply_outfit(outfit)
	if hands != null:
		hands.set_skin(_skin_color())
	_apply_body_layers()


## Off while a UI panel is open: no movement, actions, presses or look, mouse
## freed, nothing hovered.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_cancel_hold()
		_release_primary()
		_set_target(null)
	if camera_rig != null:
		camera_rig.set_look_enabled(enabled)
		camera_rig.set_mouse_captured(enabled)


func is_input_enabled() -> bool:
	return _input_enabled


## Detained / on the curb: invisible, no collision, no movement.
func set_hidden(hidden: bool) -> void:
	if hidden:
		_reset_motion()
		_carrier = null
		end_capture()
		raise_id_card(false)
		state = STATE_HIDDEN
		_set_collision(false)
		model.visible = false
		_set_target(null)
		if camera_rig != null:
			camera_rig.clear_follow()
		if hands != null:
			hands.set_flail(false)
			hands.visible = false
	elif state == STATE_HIDDEN:
		_enter_free()
		model.visible = true


func is_hidden() -> bool:
	return state == STATE_HIDDEN


## Knocked over: falls on its back, lies dazed, gets up. Only while free.
func tumble() -> void:
	if state != STATE_FREE:
		return
	_start_action(ACTION_TUMBLE)
	_emote = &""
	model.set_pose(&"idle")
	model.set_pose(&"tumble")


## Where the eye is in every state (world space, without bob or effects).
func camera_focus() -> Vector3:
	match state:
		STATE_CARRIED:
			return global_position + Vector3.UP * FpTuning.CARRIED_UP - front_direction() * FpTuning.CARRIED_BACK
		STATE_SEATED:
			return global_position + Vector3.UP * FpTuning.SEATED_EYE_HEIGHT
	return global_position + Vector3.UP * FpTuning.EYE_HEIGHT


## Unit vector the body faces, on the floor plane (where you look while free).
func front_direction() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


# --- Frame update -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or not _input_enabled:
		return
	if event.is_action_pressed(&"pause"):
		if camera_rig != null:
			camera_rig.set_mouse_captured(false)
		pause_requested.emit()
		get_viewport().set_input_as_handled()
	elif _id_raised and event.is_action_pressed(&"id_next"):
		_cycle_id(1)
		get_viewport().set_input_as_handled()
	elif _id_raised and event.is_action_pressed(&"id_prev"):
		_cycle_id(-1)
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	_time += delta
	if puppet:
		_physics_puppet(delta)
		return
	match state:
		STATE_FREE:
			_physics_free(delta)
		STATE_SEATED:
			velocity = Vector3.ZERO
			if _input_ready() and Input.is_action_just_pressed(&"jump"):
				stand_requested.emit()
			if _input_ready() and Input.is_action_just_pressed(&"throw_chips"):
				_throw_chips()
		STATE_CARRIED:
			if _carrier == null or not is_instance_valid(_carrier) or not _carrier.is_inside_tree():
				release(global_position)
			else:
				_follow_carrier()
				if _input_ready() and Input.is_action_just_pressed(&"jump"):
					struggled.emit()
	if camera_rig != null:
		look_pitch = camera_rig.pitch
		_update_head(delta)
	_update_hover()
	_update_press(delta)
	_update_pose(delta)
	if _input_ready() and Input.is_action_just_pressed(&"show_id") and (state == STATE_FREE or state == STATE_SEATED):
		raise_id_card(not _id_raised)
	if _input_ready() and Input.is_action_just_pressed(&"give_chips") and (state == STATE_FREE or state == STATE_SEATED):
		var mate := _nearest_teammate()
		if mate != null:
			give_chips_requested.emit(mate)
	if _input_ready() and Input.is_action_just_pressed(&"emote"):
		play_next_emote()
	if _net_sync:
		_publish()


func _publish() -> void:
	net_position = global_position if is_inside_tree() else position
	net_facing = facing
	net_pitch = look_pitch
	net_velocity = velocity
	net_pose = model.pose
	net_state = state
	net_running = is_running()


## Another peer's player: ease toward the synced position, copy pose and state.
func _physics_puppet(delta: float) -> void:
	var k: float = 1.0 - exp(-PUPPET_SHARPNESS * delta)
	if global_position.distance_to(net_position) > PUPPET_SNAP_DISTANCE:
		global_position = net_position
	else:
		global_position = global_position.lerp(net_position, k)
	facing = lerp_angle(facing, net_facing, k)
	look_pitch = lerpf(look_pitch, net_pitch, k)
	_apply_facing()
	if model.has_method(&"set_look_pitch"):
		model.call(&"set_look_pitch", look_pitch)
	velocity = net_velocity
	if net_state != state:
		state = net_state
		_set_collision(state == STATE_FREE)
		model.visible = state != STATE_HIDDEN
		if nameplate != null:
			nameplate.visible = state != STATE_HIDDEN
	model.set_pose(net_pose)
	model.set_move_speed(Vector2(net_velocity.x, net_velocity.z).length())


## The closest other player within GIVE_RANGE that isn't hidden, or null.
func _nearest_teammate() -> PlayerCharacter:
	if not is_inside_tree():
		return null
	var best: PlayerCharacter = null
	var best_d := GIVE_RANGE * GIVE_RANGE
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var other := node as PlayerCharacter
		if other == null or other == self or other.state == STATE_HIDDEN:
			continue
		var d := _flat_distance_sq(other.global_position)
		if d <= best_d:
			best = other
			best_d = d
	return best


func _physics_free(delta: float) -> void:
	var on_floor := is_on_floor()
	var move := _move_input()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_action_time += delta
	_running = false
	if on_floor:
		_coyote = Tuning.PLAYER_COYOTE_SECONDS
		_air_time = 0.0
		if velocity.y <= 0.0:
			_jumped = false
	else:
		_coyote -= delta
		_air_time += delta
	_jump_buffer -= delta

	match action:
		ACTION_NONE:
			var run_held := _input_ready() and Input.is_action_pressed(&"run")
			var target := move * (Tuning.PLAYER_RUN_SPEED if run_held else Tuning.PLAYER_WALK_SPEED)
			var rate := Tuning.PLAYER_ACCELERATION if move != Vector3.ZERO else Tuning.PLAYER_BRAKING
			if not on_floor:
				rate *= Tuning.PLAYER_AIR_CONTROL
			horizontal = horizontal.move_toward(target, rate * delta)
			if is_local:
				_running = run_held and move.length() > 0.1
			else:
				_running = horizontal.length() > Tuning.PLAYER_WALK_SPEED + 0.5
			# First person: the body faces where you look.
			if camera_rig != null:
				facing = camera_rig.view_yaw()
				_apply_facing()
			if _input_ready():
				if Input.is_action_just_pressed(&"jump"):
					_jump_buffer = Tuning.PLAYER_JUMP_BUFFER_SECONDS
				if _jump_buffer > 0.0 and _coyote > 0.0:
					velocity.y = Tuning.PLAYER_JUMP_VELOCITY
					_jump_buffer = 0.0
					_coyote = 0.0
					_jumped = true
					on_floor = false
				if Input.is_action_just_pressed(&"dive"):
					horizontal = _start_dive(move, on_floor)
				elif Input.is_action_just_pressed(&"tackle"):
					horizontal = _start_tackle()
				if Input.is_action_just_pressed(&"throw_chips"):
					_throw_chips()
				if Input.is_action_just_pressed(&"knock_over"):
					var tray := _nearest_tray()
					if tray != null:
						if hands != null:
							hands.play(&"shove")
						knock_over_requested.emit(tray)
		ACTION_DIVE:
			_check_action_hit()
			if _action_time >= Tuning.PLAYER_DIVE_SECONDS and on_floor:
				_start_action(ACTION_PRONE)
		ACTION_TACKLE:
			_check_action_hit()
			if _action_time >= Tuning.PLAYER_TACKLE_SECONDS:
				_start_action(ACTION_PRONE)
		ACTION_PRONE:
			horizontal = horizontal.move_toward(Vector3.ZERO, Tuning.PLAYER_DIVE_SLIDE_BRAKING * delta)
			if _action_time >= Tuning.PLAYER_DIVE_RECOVER_SECONDS:
				_start_action(ACTION_NONE)
		ACTION_TUMBLE:
			horizontal = horizontal.move_toward(Vector3.ZERO, Tuning.PLAYER_BRAKING * delta)
			if _action_time >= Tuning.CHARACTER_TUMBLE_SECONDS:
				_start_action(ACTION_NONE)

	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if not on_floor:
		var gravity := get_gravity()
		if velocity.y < 0.0:
			gravity *= Tuning.PLAYER_FALL_GRAVITY_MULT
		velocity += gravity * delta
	var falling := velocity.y
	move_and_slide()
	var now_on_floor := is_on_floor()
	if now_on_floor and not _was_on_floor and _air_time > 0.05:
		_on_landed(-falling)
	_was_on_floor = now_on_floor
	_check_bumps(delta)


func _on_landed(speed: float) -> void:
	if camera_rig != null:
		camera_rig.land(speed)
	landed.emit(speed)


func _start_dive(move: Vector3, on_floor: bool) -> Vector3:
	var dir := move.normalized() if move.length() > 0.1 else front_direction()
	_action_dir = dir
	facing = _yaw_of(dir)
	_apply_facing()
	_start_action(ACTION_DIVE)
	if on_floor:
		velocity.y = maxf(velocity.y, Tuning.PLAYER_DIVE_HOP_VELOCITY)
	_check_action_hit()
	if hands != null and not hands.is_holding():
		hands.play(&"shove")
	return dir * Tuning.PLAYER_DIVE_SPEED


func _start_tackle() -> Vector3:
	_action_dir = front_direction()
	_start_action(ACTION_TACKLE)
	_check_action_hit()
	if hands != null:
		hands.play(&"shove")
	return front_direction() * Tuning.PLAYER_TACKLE_LUNGE_SPEED


func _throw_chips() -> void:
	if hands != null and not hands.is_holding():
		hands.play(&"throw")
	throw_chips_requested.emit(global_position + front_direction() * Tuning.PLAYER_THROW_DISTANCE)


## Emits tackle_requested once per dive / tackle for the first guard in reach.
func _check_action_hit() -> void:
	if _action_hit:
		return
	var guard := _guard_in_front()
	if guard == null:
		return
	_action_hit = true
	var to := guard.global_position - global_position
	to.y = 0.0
	if to.length_squared() > 0.0001:
		facing = _yaw_of(to)
		_apply_facing()
	tackle_requested.emit(guard)


func _guard_in_front() -> Node3D:
	if not is_inside_tree():
		return null
	var best: Node3D = null
	var best_d := Tuning.TACKLE_RANGE
	var front := front_direction()
	var min_dot := cos(deg_to_rad(Tuning.PLAYER_TACKLE_CONE_DEGREES) * 0.5)
	for node: Node in get_tree().get_nodes_in_group(GUARD_GROUP):
		var guard := node as Node3D
		if guard == null or guard == self or not guard.is_visible_in_tree():
			continue
		var to := guard.global_position - global_position
		if absf(to.y) > Tuning.PLAYER_HEIGHT:
			continue
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > Tuning.PLAYER_RADIUS * 2.0 and front.dot(to / d) < min_dot:
			continue
		best = guard
		best_d = d
	return best


func _check_bumps(delta: float) -> void:
	for id: int in _bump_contacts.keys():
		_bump_contacts[id] += delta
		if _bump_contacts[id] > Tuning.PLAYER_BUMP_CONTACT_SECONDS:
			_bump_contacts.erase(id)
	for i in get_slide_collision_count():
		var other := get_slide_collision(i).get_collider() as Node3D
		if other == null or not other.is_in_group(GUARD_GROUP):
			continue
		var id := other.get_instance_id()
		var fresh := not _bump_contacts.has(id)
		_bump_contacts[id] = 0.0
		if fresh and is_running():
			bumped.emit(other)


func _follow_carrier() -> void:
	if _carrier.has_method(&"get_carry_point"):
		global_position = _carrier.call(&"get_carry_point")
	else:
		global_position = _carrier.global_position + Vector3.UP * (CharacterModel.HIP_Y + CharacterModel.SPINE_Y + CharacterModel.TORSO_SIZE.y)
	# The carrier's body may not turn (its model does): prefer its model's facing.
	var source := _carrier
	var carrier_model: Variant = _carrier.get(&"model")
	if carrier_model is Node3D:
		source = carrier_model
	var forward := -source.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		facing = _yaw_of(forward)
	velocity = Vector3.ZERO
	_apply_facing()


# --- Head -----------------------------------------------------------------------

## Feeds the head its eye position, bob and action effects for this frame.
func _update_head(delta: float) -> void:
	var rig := camera_rig
	var head := Vector3(0.0, FpTuning.EYE_HEIGHT, 0.0)
	var offset := Vector3.ZERO
	var fx_pitch := 0.0
	var fx_roll := 0.0
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor() if is_inside_tree() else true
	match state:
		STATE_SEATED:
			head.y = FpTuning.SEATED_EYE_HEIGHT
			speed = 0.0
		STATE_CARRIED:
			rig.set_follow(facing + PI)
			head = Vector3.UP * FpTuning.CARRIED_UP - front_direction() * FpTuning.CARRIED_BACK
			var wob := deg_to_rad(FpTuning.CARRIED_WOBBLE_DEGREES)
			fx_roll = sin(_time * 6.3) * wob
			fx_pitch = sin(_time * 4.1) * wob * 0.5
			offset = Vector3(0.0, absf(sin(_time * 6.3)) * 0.035, 0.0)
			speed = 0.0
		STATE_FREE:
			match action:
				ACTION_DIVE:
					head = Vector3(0.0, FpTuning.DIVE_EYE, 0.0) + _action_dir * FpTuning.DIVE_LUNGE
					fx_pitch = deg_to_rad(FpTuning.DIVE_PITCH_DEGREES)
					fx_roll = deg_to_rad(FpTuning.DIVE_ROLL_DEGREES)
					speed = 0.0
				ACTION_PRONE:
					head = Vector3(0.0, FpTuning.PRONE_EYE, 0.0) + _action_dir * FpTuning.DIVE_LUNGE
					fx_pitch = deg_to_rad(FpTuning.DIVE_PITCH_DEGREES * 0.4)
					fx_roll = deg_to_rad(FpTuning.DIVE_ROLL_DEGREES * 0.5)
					speed = 0.0
				ACTION_TACKLE:
					head = Vector3(0.0, FpTuning.EYE_HEIGHT - FpTuning.TACKLE_DIP, 0.0) + _action_dir * FpTuning.TACKLE_LUNGE
					fx_pitch = deg_to_rad(-6.0)
					speed = 0.0
				ACTION_TUMBLE:
					var u := clampf(_action_time / Tuning.CHARACTER_TUMBLE_SECONDS, 0.0, 1.0)
					var down := 1.0 if u < 0.75 else 1.0 - smoothstep(0.75, 1.0, u)
					down *= smoothstep(0.0, 0.18, u)
					head = Vector3(0.0, lerpf(FpTuning.EYE_HEIGHT, FpTuning.TUMBLE_EYE, down), 0.0) - front_direction() * 0.3 * down
					fx_pitch = deg_to_rad(FpTuning.TUMBLE_PITCH_DEGREES) * down
					fx_roll = deg_to_rad(FpTuning.TUMBLE_ROLL_DEGREES) * down
					speed = 0.0
					if hands != null:
						# Arms flail on the way down.
						hands.set_flail(u < 0.3)
	if state != STATE_CARRIED and rig.is_following():
		rig.clear_follow()
	rig.head_target = head
	rig.set_effect(offset, fx_pitch, fx_roll)
	rig.set_motion(speed, grounded, is_running())
	if hands != null:
		hands.visible = state != STATE_HIDDEN
		hands.set_clearance(_clearance())
	if delta <= 0.0:
		rig.snap()


## Distance from the eye to the nearest wall / body straight ahead.
func _clearance() -> float:
	if camera_rig == null or not is_inside_tree() or not camera_rig.is_inside_tree():
		return INF
	var from := camera_rig.eye_position()
	var dir := camera_rig.look_direction()
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * FpTuning.HANDS_CLEARANCE, CLEARANCE_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return INF
	return from.distance_to(hit["position"])


# --- Looking at and pressing things -------------------------------------------------

func _update_hover() -> void:
	if not is_local or puppet:
		return
	var can := _input_ready() and not is_captured() and (state == STATE_FREE or state == STATE_SEATED) and action == ACTION_NONE
	if not can:
		if _hold_target == null:
			_set_target(null)
		return
	var hit := _look_ray()
	if hit.is_empty():
		var it := _sensor_interactable()
		if it != null:
			hit = {"node": it, "point": it.global_position}
	if hit.is_empty():
		_set_target(null)
	else:
		_set_target(hit["node"], hit["point"])


## {node, point} for the first pressable on the look ray (a legacy
## Interactable on the way is kept as the fallback), or {}.
func _look_ray() -> Dictionary:
	if camera_rig == null or not is_inside_tree() or not camera_rig.is_inside_tree():
		return {}
	var space := get_world_3d().direct_space_state
	var from := camera_rig.eye_position()
	var to := from + camera_rig.look_direction() * reach
	var exclude: Array[RID] = [get_rid()]
	var legacy := {}
	for hop in FpTuning.RAY_MAX_HOPS:
		var q := PhysicsRayQueryParameters3D.create(from, to, FpTuning.PRESS_MASK, exclude)
		q.collide_with_areas = true
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var collider: Object = hit["collider"]
		var pressable := _pressable_of(collider)
		if pressable != null:
			if _is_enabled(pressable):
				return {"node": pressable, "point": hit["position"]}
			# A disabled key still blocks what is behind it.
			return legacy
		var it := collider as Interactable
		if it != null and it.enabled and legacy.is_empty():
			legacy = {"node": it, "point": hit["position"]}
		exclude.append(hit["rid"])
	return legacy


## The nearest enabled Interactable in the sensor in front of the view.
func _sensor_interactable() -> Interactable:
	var best: Interactable = null
	var best_d := INF
	for area: Area3D in _sensor.get_overlapping_areas():
		var it := area as Interactable
		if it == null or not it.enabled:
			continue
		var d := _flat_distance_sq(it.global_position)
		if d < best_d:
			best = it
			best_d = d
	return best


func _set_target(target: Node, point: Vector3 = Vector3.ZERO) -> void:
	if _target != null and not is_instance_valid(_target):
		_target = null
	_target_point = point
	if target == _target:
		if target != null:
			var hint := _hint_of(target)
			if hint != _hint:
				_hint = hint
				hover_changed.emit(target, hint)
		return
	if _target != null and _target.has_method(&"set_hovered"):
		_target.call(&"set_hovered", false)
	_target = target
	if target != null and target.has_method(&"set_hovered"):
		target.call(&"set_hovered", true)
	_hint = _hint_of(target)
	if hands != null:
		hands.set_ready_to_press(target != null and _pressable_of(target) != null)
	if _hold_target != null and _hold_target != target:
		_cancel_hold()
	_set_focus(target as Interactable)
	hover_changed.emit(target, _hint)


func _set_focus(target: Interactable) -> void:
	if _focus != null and not is_instance_valid(_focus):
		_focus = null
	if target == _focus:
		return
	_focus = target
	focus_changed.emit(target)


func _update_press(delta: float) -> void:
	if not is_local or puppet:
		return
	if not _input_ready():
		_release_primary()
		return
	var down := Input.is_action_pressed(&"primary") or Input.is_action_pressed(&"interact")
	var tapped := Input.is_action_just_pressed(&"primary") or Input.is_action_just_pressed(&"interact")
	var just := (down or tapped) and not _primary_down
	var released := (_primary_down or just) and not down
	if just and camera_rig != null and camera_rig.consume_swallowed_click():
		# This click only took the mouse back.
		_swallow_click = true
	if _swallow_click:
		_primary_down = down
		if not down:
			_swallow_click = false
		return
	if just:
		_primary_down = true
		primary_pressed.emit()
		if is_captured():
			_call_capture(&"on_primary_pressed")
		else:
			_begin_press()
	if is_captured():
		_cancel_hold()
	elif _hold_target != null:
		_continue_hold(delta, down)
	if released:
		_primary_down = false
		primary_released.emit()
		if is_captured():
			_call_capture(&"on_primary_released")


func _begin_press() -> void:
	var can := (state == STATE_FREE or state == STATE_SEATED) and action == ACTION_NONE
	var target := current_target()
	if not can or target == null:
		if can and hands != null and not hands.is_holding():
			hands.play(&"press")
		return
	if _hold_seconds_of(target) <= 0.0:
		_cancel_hold()
		_press(target)
	else:
		_hold_target = target
		_hold_time = 0.0
		_hold_done = false
		hold_progress.emit(0.0)
		if hands != null:
			hands.play(&"press", _target_point, true)


func _continue_hold(delta: float, down: bool) -> void:
	if not is_instance_valid(_hold_target) or _hold_target != current_target() or action != ACTION_NONE:
		_cancel_hold()
		return
	if down:
		if not _hold_done:
			_hold_time += delta
			var need := _hold_seconds_of(_hold_target)
			hold_progress.emit(clampf(_hold_time / need, 0.0, 1.0))
			if _hold_time >= need:
				_hold_done = true
				_complete_hold(_hold_target)
		return
	if not _hold_done and _hold_time <= Tuning.PLAYER_INTERACT_TAP_SECONDS:
		_press(_hold_target)
	_cancel_hold()


func _press(target: Node) -> void:
	if target.has_method(&"press"):
		if hands != null:
			hands.play(_hand_anim_of(target, &"press"), _target_point)
		target.call(&"press", pid)
		target_pressed.emit(target)
		return
	var it := target as Interactable
	if it == null:
		return
	if hands != null:
		hands.play(&"press", _target_point)
	if interact_pressed.get_connections().is_empty():
		it.use(self)
	interact_pressed.emit(it)


func _complete_hold(target: Node) -> void:
	if hands != null:
		hands.release_sustain()
		hands.play(_hand_anim_of(target, &"grab"), _target_point)
	if target.has_method(&"hold_complete"):
		target.call(&"hold_complete", pid)
		target_held.emit(target)
		return
	var it := target as Interactable
	if it != null:
		interact_held.emit(it)


func _cancel_hold() -> void:
	var was := _hold_target != null
	_hold_target = null
	_hold_time = 0.0
	_hold_done = false
	if was:
		hold_progress.emit(0.0)
		if hands != null:
			hands.release_sustain()


## LMB / E let go without a release event (input off, panel opened).
func _release_primary() -> void:
	if not _primary_down:
		return
	_primary_down = false
	_swallow_click = false
	primary_released.emit()
	if is_captured():
		_call_capture(&"on_primary_released")


func _call_capture(method: StringName) -> void:
	var capturer := capture_owner()
	if capturer != null and capturer.has_method(method):
		capturer.call(method, pid)


## The pressable for a ray hit: the collider, or its parent, if it has press().
static func _pressable_of(collider: Object) -> Node:
	var node := collider as Node
	if node == null:
		return null
	if node.has_method(&"press"):
		return node
	var parent := node.get_parent()
	if parent != null and parent.has_method(&"press") and not (node is Interactable):
		return parent
	return null


static func _is_enabled(node: Object) -> bool:
	var e: Variant = node.get(&"enabled")
	return e == null or bool(e)


static func _hold_seconds_of(node: Object) -> float:
	var h: Variant = node.get(&"hold_seconds")
	return float(h) if h is float or h is int else 0.0


static func _hint_of(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method(&"get_hint"):
		return str(node.call(&"get_hint"))
	var it := node as Interactable
	if it != null:
		return it.prompt
	var h: Variant = node.get(&"hint")
	return str(h) if h != null else ""


## A pressable may name the hand animation it wants (`hand_anim`, e.g. &"pull"
## for a lever).
static func _hand_anim_of(node: Object, fallback: StringName) -> StringName:
	var a: Variant = node.get(&"hand_anim")
	if a is StringName and FirstPersonHands.ANIM_SECONDS.has(a):
		return a
	if a is String and FirstPersonHands.ANIM_SECONDS.has(StringName(a)):
		return StringName(a)
	return fallback


func _nearest_tray() -> Interactable:
	var focus := current_interactable()
	if focus != null and focus.kind == &"tray":
		return focus
	var best: Interactable = null
	var best_d := INF
	for area: Area3D in _sensor.get_overlapping_areas():
		var it := area as Interactable
		if it == null or not it.enabled or it.kind != &"tray":
			continue
		var d := _flat_distance_sq(it.global_position)
		if d < best_d:
			best = it
			best_d = d
	return best


# --- ID card ----------------------------------------------------------------------

func _ensure_card() -> IdCard3D:
	if id_card == null:
		id_card = IdCard3D.new()
		id_card.visible = false
	return id_card


func _cycle_id(direction: int) -> void:
	if hands != null:
		hands.play(&"flip_card")
	id_cycle.emit(direction)


# --- Pose and helpers ---------------------------------------------------------

func _update_pose(delta: float) -> void:
	_emote_left -= delta
	if _emote_left <= 0.0:
		_emote = &""
	var speed := Vector2(velocity.x, velocity.z).length()
	match state:
		STATE_SEATED:
			if _emote != &"":
				model.set_pose(_emote)
			else:
				model.set_pose(&"play" if _playing else &"sit")
		STATE_CARRIED:
			model.set_pose(&"carried")
		STATE_HIDDEN:
			model.set_pose(&"idle")
		STATE_FREE:
			match action:
				ACTION_DIVE, ACTION_PRONE:
					model.set_pose(&"dive")
				ACTION_TACKLE:
					model.set_pose(&"tackle")
				ACTION_TUMBLE:
					pass
				_:
					if not is_on_floor() and (_jumped or _air_time > 0.15):
						model.set_pose(&"jump")
					elif speed > 0.3:
						model.set_pose(&"run" if speed > Tuning.PLAYER_WALK_SPEED + 0.4 else &"walk")
						_emote = &""
					elif _emote != &"":
						model.set_pose(_emote)
					else:
						model.set_pose(&"idle")
	model.set_move_speed(speed)


func _hands_emote(pose: StringName) -> void:
	if hands == null or hands.is_holding():
		return
	match pose:
		&"celebrate", &"dance":
			hands.play(&"celebrate")
		&"chip_flip":
			hands.play(&"throw")
		_:
			hands.play(&"wave")


func _on_footstep(running: bool) -> void:
	footstep.emit(running)


func _move_input() -> Vector3:
	if not _input_ready():
		return Vector3.ZERO
	var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var frame := camera_rig.flat_basis() if camera_rig != null else Basis.IDENTITY
	return frame * Vector3(v.x, 0.0, v.y)


func _input_ready() -> bool:
	return is_local and _input_enabled


func _apply_facing() -> void:
	model.rotation = Vector3(0.0, facing, 0.0)
	_front.rotation = Vector3(0.0, facing, 0.0)


func _start_action(next: StringName) -> void:
	action = next
	_action_time = 0.0
	_action_hit = false


func _reset_motion() -> void:
	_start_action(ACTION_NONE)
	_cancel_hold()
	velocity = Vector3.ZERO
	_running = false
	_jumped = false
	_jump_buffer = 0.0
	_emote = &""
	_bump_contacts.clear()


func _enter_free() -> void:
	_reset_motion()
	state = STATE_FREE
	_playing = false
	_set_collision(true)
	model.visible = true
	if camera_rig != null and camera_rig.is_following():
		camera_rig.clear_follow()
		camera_rig.add_look(0.0, -camera_rig.pitch)
	if hands != null:
		hands.set_flail(false)
		hands.visible = true


func _set_collision(on: bool) -> void:
	collision_layer = PLAYER_LAYER if on else 0
	collision_mask = BODY_MASK if on else 0


func _place(pos: Vector3) -> void:
	if is_inside_tree():
		global_position = pos
	else:
		position = pos


func _flat_distance_sq(point: Vector3) -> float:
	var d := point - global_position
	d.y = 0.0
	return d.length_squared()


func _skin_color() -> Color:
	var c: Variant = model.get(&"skin_color")
	return c if c is Color else FirstPersonHands.DEFAULT_SKIN


## The local player's own body goes on SELF_BODY_LAYER (its camera skips
## it); a body that stops being local goes back to layer 1. Other bodies keep
## whatever layers the model gave them.
func _apply_body_layers() -> void:
	if is_local:
		_set_layers(model, FpTuning.SELF_BODY_LAYER)
		_self_layered = true
	elif _self_layered:
		_set_layers(model, 1)
		_self_layered = false


func _set_layers(node: Node, layer: int) -> void:
	var vi := node as VisualInstance3D
	if vi != null:
		vi.layers = layer
	for child: Node in node.get_children():
		_set_layers(child, layer)


## Local player: meshes the body adds later (a new hat) join the self-body layer.
func _watch_body(on: bool) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if on and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	elif not on and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if is_local and node is VisualInstance3D and model != null and model.is_ancestor_of(node):
		(node as VisualInstance3D).layers = FpTuning.SELF_BODY_LAYER


static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
