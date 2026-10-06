class_name PlayerCharacter
extends CharacterBody3D
## A crew member: walk, run, jump, dive and tackle with a camera-relative
## third-person camera (local players only), an interaction sensor in front,
## and the seated / carried / hidden states the director puts it in.
## World-side only: it emits requests as signals and never touches chips,
## Heat, IDs or outfits. Non-local players (phase 2) ignore input and have no
## camera; the network will drive them.

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
## The nearest enabled Interactable in reach changed (null = none): the HUD prompt.
signal focus_changed(target: Interactable)
## Jump pressed while seated: the director can stand the player up.
signal stand_requested()

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
const PLAYER_LAYER := 2
## World + guard + patron.
const BODY_MASK := 1 | 4 | 8
const INTERACTABLE_MASK := 16

var pid: int = 1
var is_local: bool = true
var model: CharacterModel
## Only on local players.
var camera_rig: CameraRig
## One of the STATE_* names (read-only; use sit_at, set_carried, set_hidden...).
var state: StringName = STATE_FREE
## One of the ACTION_* names while free (read-only).
var action: StringName = ACTION_NONE
## Model yaw in radians; 0 faces -Z.
var facing: float = 0.0

var _shape: CollisionShape3D
var _front: Node3D
var _sensor: Area3D
var _input_enabled := true
var _focus: Interactable
var _hold_target: Interactable
var _hold_time := 0.0
var _hold_done := false
var _carrier: Node3D
var _seat := Transform3D.IDENTITY
var _playing := false
var _emote: StringName = &""
var _emote_left := 0.0
var _action_time := 0.0
var _action_hit := false
var _running := false
var _jumped := false
var _air_time := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _bump_contacts: Dictionary = {}


func _init() -> void:
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


## pid seeds the face and hair. Local players get the camera rig and read input.
func setup(player_id: int, local: bool, outfit: Outfit) -> void:
	pid = player_id
	is_local = local
	model.appearance_seed = player_id
	set_outfit(outfit)
	if is_local:
		InputSetup.ensure_actions()
		if camera_rig == null:
			camera_rig = CameraRig.new()
			camera_rig.name = "CameraRig"
			add_child(camera_rig)
			camera_rig.setup(self)
			camera_rig.set_look_enabled(_input_enabled)
			if is_inside_tree() and _input_enabled:
				camera_rig.set_mouse_captured(true)
	elif camera_rig != null:
		camera_rig.queue_free()
		camera_rig = null


func _ready() -> void:
	if is_local and camera_rig != null and _input_enabled:
		camera_rig.set_mouse_captured(true)


# --- Public API ---------------------------------------------------------------

## Holding run and moving (free, not mid-dive). Drives running_in_view.
func is_running() -> bool:
	return _running and state == STATE_FREE and action == ACTION_NONE


## The interactable an interact press would use, or null.
func current_interactable() -> Interactable:
	if _focus != null and not is_instance_valid(_focus):
		_focus = null
	return _focus


## 0..1 progress of a hold-interaction in progress (0 when none).
func interact_hold_progress() -> float:
	if _hold_target == null or not is_instance_valid(_hold_target) or _hold_target.hold_seconds <= 0.0:
		return 0.0
	return clampf(_hold_time / _hold_target.hold_seconds, 0.0, 1.0)


## Snaps onto a seat (origin at floor level under the seat, facing its -Z):
## collision and movement off, sit pose.
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


## Leaves the seat, stepping back away from the table.
func stand_up() -> void:
	if state != STATE_SEATED:
		return
	var back := _seat.basis.z
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK
	_enter_free()
	_place(_seat.origin + back * Tuning.PLAYER_STAND_UP_STEP)


## While seated: the "play" pose (a round in progress) instead of "sit".
func set_playing(playing: bool) -> void:
	_playing = playing


## Plays a pose (e.g. &"celebrate") for a few seconds while standing still.
func emote(pose: StringName, seconds: float) -> void:
	_emote = pose
	_emote_left = seconds


## Follows carrier.get_carry_point() with the carrier's facing until release().
## null releases on the spot.
func set_carried(carrier: Node3D) -> void:
	if carrier == null:
		release(global_position)
		return
	_reset_motion()
	_carrier = carrier
	state = STATE_CARRIED
	_set_collision(false)
	model.visible = true
	if is_inside_tree() and carrier.is_inside_tree():
		_follow_carrier()
	model.set_pose(&"carried")


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
	if camera_rig != null:
		camera_rig.snap()


func set_outfit(outfit: Outfit) -> void:
	model.apply_outfit(outfit)


## Off while a UI panel is open: no movement, actions or camera look, mouse freed.
func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		_cancel_hold()
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
		state = STATE_HIDDEN
		_set_collision(false)
		model.visible = false
		_set_focus(null)
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


## Where the camera looks: about head height in every state.
func camera_focus() -> Vector3:
	match state:
		STATE_CARRIED:
			var shoulder := CharacterModel.HIP_Y + CharacterModel.SPINE_Y + CharacterModel.TORSO_SIZE.y
			return global_position + Vector3.UP * (Tuning.PLAYER_CAMERA_HEIGHT - shoulder)
		STATE_SEATED:
			return global_position + Vector3.UP * (Tuning.PLAYER_CAMERA_HEIGHT - (CharacterModel.HIP_Y - CharacterModel.SIT_HIP_Y))
	return global_position + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT


## Unit vector the model faces, on the floor plane.
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


func _physics_process(delta: float) -> void:
	match state:
		STATE_FREE:
			_physics_free(delta)
		STATE_SEATED:
			velocity = Vector3.ZERO
			if _input_ready() and Input.is_action_just_pressed(&"jump"):
				stand_requested.emit()
			if _input_ready() and Input.is_action_just_pressed(&"throw_chips"):
				throw_chips_requested.emit(global_position + front_direction() * Tuning.PLAYER_THROW_DISTANCE)
		STATE_CARRIED:
			if _carrier == null or not is_instance_valid(_carrier) or not _carrier.is_inside_tree():
				release(global_position)
			else:
				_follow_carrier()
				if _input_ready() and Input.is_action_just_pressed(&"jump"):
					struggled.emit()
	_update_focus()
	_update_interact(delta)
	_update_pose(delta)


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
			if move.length() > 0.1:
				_turn_toward(move, delta)
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
					throw_chips_requested.emit(global_position + front_direction() * Tuning.PLAYER_THROW_DISTANCE)
				if Input.is_action_just_pressed(&"knock_over"):
					var tray := _nearest_tray()
					if tray != null:
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
	move_and_slide()
	_check_bumps(delta)


func _start_dive(move: Vector3, on_floor: bool) -> Vector3:
	var dir := move.normalized() if move.length() > 0.1 else front_direction()
	facing = _yaw_of(dir)
	_apply_facing()
	_start_action(ACTION_DIVE)
	if on_floor:
		velocity.y = maxf(velocity.y, Tuning.PLAYER_DIVE_HOP_VELOCITY)
	_check_action_hit()
	return dir * Tuning.PLAYER_DIVE_SPEED


func _start_tackle() -> Vector3:
	_start_action(ACTION_TACKLE)
	_check_action_hit()
	return front_direction() * Tuning.PLAYER_TACKLE_LUNGE_SPEED


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


# --- Interaction --------------------------------------------------------------

func _update_focus() -> void:
	var best: Interactable = null
	if state == STATE_FREE or state == STATE_SEATED:
		var best_d := INF
		for area: Area3D in _sensor.get_overlapping_areas():
			var it := area as Interactable
			if it == null or not it.enabled:
				continue
			var d := _flat_distance_sq(it.global_position)
			if d < best_d:
				best = it
				best_d = d
	_set_focus(best)


func _set_focus(target: Interactable) -> void:
	if _focus != null and not is_instance_valid(_focus):
		_focus = null
	if target == _focus:
		return
	_focus = target
	if _hold_target != target:
		_cancel_hold()
	focus_changed.emit(target)


func _update_interact(delta: float) -> void:
	var can := _input_ready() and (state == STATE_FREE or state == STATE_SEATED) and action == ACTION_NONE
	if not can:
		_cancel_hold()
		return
	var target := current_interactable()
	if Input.is_action_just_pressed(&"interact") and target != null:
		if target.hold_seconds <= 0.0:
			_cancel_hold()
			interact_pressed.emit(target)
		else:
			_hold_target = target
			_hold_time = 0.0
			_hold_done = false
		return
	if _hold_target == null:
		return
	if not is_instance_valid(_hold_target) or _hold_target != target:
		_cancel_hold()
	elif Input.is_action_pressed(&"interact"):
		if not _hold_done:
			_hold_time += delta
			if _hold_time >= _hold_target.hold_seconds:
				_hold_done = true
				interact_held.emit(_hold_target)
	else:
		if not _hold_done and _hold_time <= Tuning.PLAYER_INTERACT_TAP_SECONDS:
			interact_pressed.emit(_hold_target)
		_cancel_hold()


func _cancel_hold() -> void:
	_hold_target = null
	_hold_time = 0.0
	_hold_done = false


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


func _move_input() -> Vector3:
	if not _input_ready():
		return Vector3.ZERO
	var v := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var frame := camera_rig.flat_basis() if camera_rig != null else Basis.IDENTITY
	return frame * Vector3(v.x, 0.0, v.y)


func _input_ready() -> bool:
	return is_local and _input_enabled


func _turn_toward(dir: Vector3, delta: float) -> void:
	facing = lerp_angle(facing, _yaw_of(dir), 1.0 - exp(-Tuning.PLAYER_TURN_SHARPNESS * delta))
	_apply_facing()


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


static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
