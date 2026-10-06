class_name GuardNPC
extends CharacterBody3D
## A security NPC on the floor. Each physics frame it looks for players
## (Perception.in_vision_cone from eye height, then a world-layer raycast to
## the chest), feeds what it saw and heard to its GuardBrain, and carries out
## the intent: walk the navmesh, turn, and turn brain actions into signals.
## It never touches chips, Heat, IDs or outfits; the director wires the
## signals to SimHost requests (see docs/ARCHITECTURE.md, World layer).
##
## Security types: FLOOR_GUARD (navy uniform), HEAD_OF_SECURITY (bigger, the
## brain makes it faster), UNDERCOVER (a random patron outfit; its cone and
## icon only show once it chases), PIT_BOSS (stays within PIT_BOSS_POST_RADIUS
## of its post, never asks for ID or grabs; it watches, drives pit_boss_view
## through sees_pid() and radios Suspected+ players).

## Each physics frame a player is in view.
signal saw_player(guard: GuardNPC, pid: int, running: bool)
## The brain wants to ask `pid` for ID: start the quiz, then call set_id_check_result().
signal id_check_requested(guard: GuardNPC, pid: int)
signal grabbed(guard: GuardNPC, pid: int)
## Reached the back room carrying `pid`.
signal delivered(guard: GuardNPC, pid: int)
## Let go of `pid` by itself (stunned, fire alarm). Emitted on the guard's next
## physics frame after stun(), and not at all if the player was freed first.
signal released(guard: GuardNPC, pid: int)
signal state_changed(guard: GuardNPC, old_state: int, new_state: int)
## Pit boss only: a Suspected+ player at `position` (per player at most every PIT_BOSS_RADIO_COOLDOWN).
signal radioed(guard: GuardNPC, pid: int, position: Vector3)

const GROUP := &"guards"
## Layer 3 (guard); collides with world, players and patrons.
const GUARD_LAYER := 4
const BODY_MASK := 1 | 2 | 8
const WORLD_MASK := 1
## How often the navmesh height under the guard is re-measured.
const PATH_HEIGHT_RESYNC_SECONDS := 1.0
## A pit boss shows "!" this long after a radio call.
const RADIO_ICON_SECONDS := 1.0

const CONE_GREEN := Color(0.3, 0.95, 0.4, 0.18)
const CONE_YELLOW := Color(1.0, 0.86, 0.2, 0.2)
const CONE_ORANGE := Color(1.0, 0.5, 0.1, 0.24)
const CONE_RED := Color(1.0, 0.12, 0.08, 0.28)
const CONE_GREY := Color(0.6, 0.62, 0.7, 0.12)

## HR.GuardState -> [icon text, color].
const ICONS := {
	HR.GuardState.INVESTIGATE: ["?", Color(1.0, 0.86, 0.2)],
	HR.GuardState.SEARCH: ["?", Color(1.0, 0.86, 0.2)],
	HR.GuardState.CHECK_ID: ["ID", Color(1.0, 0.55, 0.1)],
	HR.GuardState.CHASE: ["!", Color(1.0, 0.15, 0.1)],
	HR.GuardState.CARRY: ["!", Color(1.0, 0.15, 0.1)],
	HR.GuardState.STUNNED: ["...", Color(0.8, 0.82, 0.9)],
}

var guard_id: int = -1
## HR.SecurityType.
var security_type: int = HR.SecurityType.FLOOR_GUARD
var brain: GuardBrain
var model: CharacterModel
var nav_agent: NavigationAgent3D
var vision_cone: VisionCone
var icon: Label3D
var back_room: Vector3 = Vector3.ZERO
## Pit boss post (the first patrol point).
var post: Vector3 = Vector3.ZERO
## Model yaw in radians; 0 faces -Z.
var facing: float = 0.0
## True while the fire alarm sends guards off the floor.
var fire_alarm: bool = false
## The intent the brain returned last frame (debug).
var last_intent: Dictionary = {}

var _players_provider: Callable
var _shape: CollisionShape3D
var _visible: Dictionary = {}
var _last_seen: Dictionary = {}
var _noises: Array[Dictionary] = []
var _alerts: Array[Dictionary] = []
var _id_pid: int = -1
var _id_result: int = GuardBrain.ID_PENDING
var _id_asked_at := 0.0
var _stun_pending := false
var _carrying: int = -1
var _carry_confirmed := false
var _carry_started := 0.0
var _struggle_mult := 1.0
var _radio_cooldowns: Dictionary = {}
var _radio_flash := 0.0
var _time := 0.0
var _nav_target: Variant = null
var _dest: Variant = null
var _vy := 0.0
var _desired := Vector3.ZERO
var _avoid_pending := false
var _cone_timer := 0.0
var _look_base := 0.0
var _height_synced := false
var _height_timer := 0.0


func _init() -> void:
	collision_layer = GUARD_LAYER
	collision_mask = BODY_MASK
	floor_snap_length = 0.3
	add_to_group(GROUP)
	_shape = CollisionShape3D.new()
	_shape.name = "Capsule"
	var capsule := CapsuleShape3D.new()
	capsule.radius = Tuning.GUARD_RADIUS
	capsule.height = Tuning.GUARD_HEIGHT
	_shape.shape = capsule
	_shape.position = Vector3(0, Tuning.GUARD_HEIGHT * 0.5, 0)
	add_child(_shape)
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	nav_agent.path_desired_distance = Tuning.GUARD_PATH_DESIRED_DISTANCE
	nav_agent.target_desired_distance = Tuning.GUARD_TARGET_DESIRED_DISTANCE
	nav_agent.height = Tuning.GUARD_HEIGHT
	nav_agent.radius = Tuning.GUARD_AVOIDANCE_RADIUS
	nav_agent.avoidance_enabled = true
	nav_agent.neighbor_distance = 6.0
	nav_agent.max_neighbors = 8
	nav_agent.time_horizon_agents = 0.8
	nav_agent.max_speed = Tuning.HEAD_OF_SECURITY_RUN_SPEED
	nav_agent.velocity_computed.connect(_on_velocity_computed)
	add_child(nav_agent)
	vision_cone = VisionCone.new(Tuning.VISION_RANGE, Tuning.VISION_FOV_DEGREES, CONE_GREEN)
	vision_cone.position = Vector3(0, Tuning.VISION_CONE_HEIGHT, 0)
	add_child(vision_cone)
	icon = Primitives.label("", 0.009)
	icon.name = "Icon"
	icon.font_size = 64
	icon.outline_size = 12
	icon.no_depth_test = true
	icon.visible = false
	add_child(icon)
	var none: Array[Vector3] = []
	brain = GuardBrain.new(none)
	_dress()


## `patrol` is the looped route (a pit boss uses patrol[0] as its post).
## `players_provider.call()` returns an Array of {pid, node: Node3D, heat,
## matches_poster, staff_uniform, available}.
func setup(id: int, guard_type: int, patrol: Array[Vector3], back_room_point: Vector3, players_provider: Callable) -> void:
	guard_id = id
	security_type = guard_type
	back_room = back_room_point
	_players_provider = players_provider
	var points: Array[Vector3] = []
	points.assign(patrol)
	if security_type == HR.SecurityType.PIT_BOSS:
		post = points[0] if not points.is_empty() else _current_position()
		points = [post]
	if brain != null and brain.state_changed.is_connected(_on_brain_state_changed):
		brain.state_changed.disconnect(_on_brain_state_changed)
	brain = GuardBrain.new(points, security_type, back_room)
	brain.state_changed.connect(_on_brain_state_changed)
	_look_base = facing
	_dress()
	_update_visuals(0.0)


# --- Public API ---------------------------------------------------------------

## A noise event {position, radius, kind}; heard on the next frame if in range.
func hear(noise: Dictionary) -> void:
	var pos: Variant = noise.get("position")
	if not (pos is Vector3):
		return
	var radius := float(noise.get("radius", 0.0))
	if not Perception.can_hear(_current_position(), pos, radius):
		return
	_noises.append({"position": pos, "radius": radius, "kind": noise.get("kind", &"")})


## The quiz started by id_check_requested ended. With no answer at all the
## guard lets the player go after the quiz time (plus a grace).
func set_id_check_result(pid: int, passed: bool) -> void:
	if pid != _id_pid or pid < 0:
		return
	_id_result = GuardBrain.ID_PASSED if passed else GuardBrain.ID_FAILED


## Bumped or tackled: tumbles, then stands dazed for STUN_SECONDS and searches.
## A carried player is let go (released on the next frame unless freed first).
func stun() -> void:
	_stun_pending = true
	model.set_pose(&"tumble")


## The carried player mashed struggle: slows the carry.
func on_struggle() -> void:
	if _carrying < 0:
		return
	_struggle_mult = maxf(Tuning.STRUGGLE_MIN_SPEED_MULT, _struggle_mult - Tuning.STRUGGLE_SLOW_PER_PRESS)


## Radio tip (a pit boss saw `pid` at `position`): treated as a sighting.
func alert(pid: int, position: Vector3) -> void:
	if security_type == HR.SecurityType.PIT_BOSS or pid < 0:
		return
	if Perception.flat_distance(_current_position(), position) < Tuning.GUARD_ALERT_MIN_DISTANCE:
		return
	_alerts.append({"pid": pid, "position": position})


func set_fire_alarm(active: bool) -> void:
	fire_alarm = active


## World point on top of the right shoulder where a carried player rides.
func get_carry_point() -> Vector3:
	if model.is_inside_tree():
		return model.global_transform * model.get_carry_offset()
	return transform * (model.transform * model.get_carry_offset())


## pid being carried, or −1.
func carrying_pid() -> int:
	return _carrying


## True if `pid` was in view this frame (a pit boss's view sets pit_boss_view).
func sees_pid(pid: int) -> bool:
	return _visible.has(pid)


## pids in view this frame.
func visible_pids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _visible:
		out.append(pid)
	return out


## Where `pid` was last seen by this guard, or null.
func last_seen_position(pid: int) -> Variant:
	var entry: Variant = _last_seen.get(pid)
	return (entry as Dictionary)["position"] if entry is Dictionary else null


## HR.GuardState of the brain.
func get_state() -> int:
	return brain.state


## Speed multiplier from struggling (1 = full speed).
func struggle_multiplier() -> float:
	return _struggle_mult


## Unit vector the guard looks along, on the floor plane.
func front_direction() -> Vector3:
	return Vector3(-sin(facing), 0.0, -cos(facing))


## Turns to face a world point (a pit boss also adopts it as its resting gaze).
func face_toward(point: Vector3) -> void:
	var to := point - _current_position()
	to.y = 0.0
	if to.length_squared() < 0.0001:
		return
	facing = _yaw_of(to)
	_look_base = facing
	_apply_facing()


# --- Frame update -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if _avoid_pending:
		# The avoidance callback never came (no navigation map): move directly.
		_avoid_pending = false
		_apply_velocity(_desired)
	_time += delta
	_radio_flash = maxf(_radio_flash - delta, 0.0)
	if _carrying >= 0:
		_struggle_mult = minf(1.0, _struggle_mult + Tuning.STRUGGLE_RECOVER_PER_SECOND * delta)
	else:
		_struggle_mult = 1.0
	if _id_pid >= 0 and _id_result == GuardBrain.ID_PENDING and _time - _id_asked_at > Tuning.ID_QUIZ_SECONDS + Tuning.ID_QUIZ_GRACE_SECONDS + Tuning.GUARD_ID_RESULT_EXTRA_SECONDS:
		_id_result = GuardBrain.ID_PASSED
	var players := _query_players()
	var ctx := {
		"position": global_position,
		"seen": _look(players),
		"noises": _noises.duplicate(),
		"id_check": _id_result,
		"reached_destination": _reached(),
		"at_back_room": Perception.flat_distance(global_position, back_room) <= Tuning.GUARD_BACK_ROOM_REACH,
		"stunned": _stun_pending,
		"freed": _check_freed(players),
		"fire_alarm": fire_alarm,
	}
	_noises.clear()
	_stun_pending = false
	var intent := brain.update(delta, ctx)
	last_intent = intent
	_do_action(intent.get("action", GuardBrain.ACT_NONE))
	_move(intent, delta)
	_update_visuals(delta)


func _query_players() -> Array:
	if not _players_provider.is_valid():
		return []
	var result: Variant = _players_provider.call()
	return result if result is Array else []


## Sight: cone + line of sight for every player. Emits saw_player and returns
## the brain's `seen` list (plus radio tips).
func _look(players: Array) -> Array:
	_visible.clear()
	var seen: Array = []
	var space := get_world_3d().direct_space_state
	var eye := global_position + Vector3.UP * Tuning.GUARD_EYE_HEIGHT * model.scale.y
	var forward := front_direction()
	var pit_boss := security_type == HR.SecurityType.PIT_BOSS
	for entry: Variant in players:
		if not (entry is Dictionary):
			continue
		var p: Dictionary = entry
		var pid := int(p.get("pid", -1))
		var node := p.get("node") as Node3D
		if pid < 0 or node == null or not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree():
			continue
		if pid == _carrying:
			continue
		var pos := node.global_position
		if not Perception.in_vision_cone(eye, forward, pos, Tuning.VISION_FOV_DEGREES, Tuning.VISION_RANGE):
			continue
		if not _line_of_sight(space, eye, pos + Vector3.UP * Tuning.SIGHT_CHEST_HEIGHT):
			continue
		var running := node.has_method(&"is_running") and bool(node.call(&"is_running"))
		var heat := float(p.get("heat", 0.0))
		var available := bool(p.get("available", true))
		_visible[pid] = heat
		_last_seen[pid] = {"position": pos, "time": _time}
		seen.append({
			"pid": pid,
			"position": pos,
			"heat": heat,
			"matches_poster": bool(p.get("matches_poster", false)),
			"staff_uniform": bool(p.get("staff_uniform", false)),
			"running": running,
			# A pit boss only watches: its brain never approaches anyone.
			"available": available and not pit_boss,
		})
		saw_player.emit(self, pid, running)
		if pit_boss and available and heat >= Tuning.SUSPECTED_AT:
			_radio(pid, pos)
	for tip: Dictionary in _alerts:
		var pid: int = tip["pid"]
		if _visible.has(pid):
			continue
		var p := _entry_for(players, pid)
		seen.append({
			"pid": pid,
			"position": tip["position"],
			"heat": float(p.get("heat", Tuning.SUSPECTED_AT)),
			"matches_poster": bool(p.get("matches_poster", false)),
			"staff_uniform": bool(p.get("staff_uniform", false)),
			"running": false,
			"available": bool(p.get("available", true)),
		})
	_alerts.clear()
	return seen


func _line_of_sight(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	if space == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK)
	return space.intersect_ray(query).is_empty()


func _radio(pid: int, pos: Vector3) -> void:
	if _time < float(_radio_cooldowns.get(pid, -INF)):
		return
	_radio_cooldowns[pid] = _time + Tuning.PIT_BOSS_RADIO_COOLDOWN
	_radio_flash = RADIO_ICON_SECONDS
	radioed.emit(self, pid, pos)


## The carried player is available again (the sim freed them), or the grab
## never took (the player stayed available).
func _check_freed(players: Array) -> bool:
	if _carrying < 0 or brain.state != HR.GuardState.CARRY:
		return false
	var p := _entry_for(players, _carrying)
	if p.is_empty() or not bool(p.get("available", false)):
		_carry_confirmed = true
		return false
	if _carry_confirmed or _time - _carry_started >= Tuning.GUARD_GRAB_CONFIRM_SECONDS:
		_carrying = -1
		return true
	return false


func _do_action(action: StringName) -> void:
	match action:
		GuardBrain.ACT_ASK_ID:
			_id_pid = brain.target_pid
			_id_result = GuardBrain.ID_PENDING
			_id_asked_at = _time
			id_check_requested.emit(self, _id_pid)
		GuardBrain.ACT_GRAB:
			_carrying = brain.target_pid
			_carry_confirmed = false
			_carry_started = _time
			_struggle_mult = 1.0
			grabbed.emit(self, _carrying)
		GuardBrain.ACT_DROP:
			var pid := _carrying
			_carrying = -1
			if pid >= 0:
				delivered.emit(self, pid)
		GuardBrain.ACT_RELEASE:
			var pid := _carrying
			_carrying = -1
			if pid >= 0:
				released.emit(self, pid)


# --- Movement -----------------------------------------------------------------

func _move(intent: Dictionary, delta: float) -> void:
	var move_to: Variant = intent.get("move_to")
	var speed := float(intent.get("speed", 0.0))
	if brain.state == HR.GuardState.CARRY:
		speed *= _struggle_mult
	var desired := Vector3.ZERO
	if move_to is Vector3:
		var dest: Vector3 = move_to
		if security_type == HR.SecurityType.PIT_BOSS:
			dest = _clamp_to_post(dest)
		_dest = dest
		desired = _steer(dest, speed)
	else:
		_dest = null
	var face: Variant = intent.get("face")
	if face is Vector3:
		_turn_toward((face as Vector3) - global_position, delta)
	elif desired.length() > 0.1:
		_turn_toward(desired, delta)
	elif security_type == HR.SecurityType.PIT_BOSS and brain.state != HR.GuardState.STUNNED:
		var sway := sin(_time * TAU / Tuning.PIT_BOSS_LOOK_PERIOD) * deg_to_rad(Tuning.PIT_BOSS_LOOK_DEGREES)
		_turn_to_yaw(_look_base + sway, delta * 0.4)
	_height_timer -= delta
	if not _height_synced or _height_timer <= 0.0:
		_height_timer = PATH_HEIGHT_RESYNC_SECONDS
		_sync_path_height()
	if is_on_floor():
		_vy = 0.0
	else:
		_vy += get_gravity().y * delta
	_desired = desired
	if nav_agent.avoidance_enabled and nav_agent.is_inside_tree():
		_avoid_pending = true
		nav_agent.velocity = desired
	else:
		_apply_velocity(desired)


## Direction to walk this frame toward `dest` along the navmesh (straight
## when there is no navmesh).
func _steer(dest: Vector3, speed: float) -> Vector3:
	if speed <= 0.0:
		return Vector3.ZERO
	if not (_nav_target is Vector3) or (_nav_target as Vector3).distance_to(dest) > Tuning.GUARD_REPATH_DISTANCE:
		_nav_target = dest
		nav_agent.target_position = dest
	var next := dest
	if _nav_has_path():
		next = nav_agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.05:
		if nav_agent.is_navigation_finished() and _nav_has_path():
			return Vector3.ZERO
		to = dest - global_position
		to.y = 0.0
	if Perception.flat_distance(global_position, dest) <= Tuning.GUARD_TARGET_DESIRED_DISTANCE * 0.5:
		return Vector3.ZERO
	return to.normalized() * speed


func _nav_has_path() -> bool:
	if not nav_agent.is_inside_tree():
		return false
	var map := nav_agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	return not NavigationServer3D.map_get_regions(map).is_empty()


## The baked navmesh floats a couple of cells above the floor; the agent
## compares waypoints in 3D, so lower its path to our feet.
func _sync_path_height() -> void:
	if not _nav_has_path() or not is_on_floor():
		return
	var below := NavigationServer3D.map_get_closest_point(nav_agent.get_navigation_map(), global_position)
	var offset := below.y - global_position.y
	if Vector2(below.x - global_position.x, below.z - global_position.z).length() < 0.5 and offset > -0.1 and offset < 1.0:
		nav_agent.path_height_offset = offset
		_height_synced = true


## Arrived at last frame's destination (or at the end of a path that can't get closer).
func _reached() -> bool:
	if not (_dest is Vector3):
		return false
	var dest: Vector3 = _dest
	if Perception.flat_distance(global_position, dest) <= Tuning.GUARD_TARGET_DESIRED_DISTANCE + 0.05:
		return true
	if _nav_has_path() and nav_agent.is_navigation_finished() and _nav_target is Vector3:
		var path := nav_agent.get_current_navigation_path()
		return not path.is_empty() and Perception.flat_distance(global_position, path[path.size() - 1]) <= Tuning.GUARD_TARGET_DESIRED_DISTANCE + 0.05
	return false


func _clamp_to_post(dest: Vector3) -> Vector3:
	var offset := dest - post
	offset.y = 0.0
	if offset.length() <= Tuning.PIT_BOSS_POST_RADIUS:
		return dest
	var clamped := post + offset.normalized() * Tuning.PIT_BOSS_POST_RADIUS
	return Vector3(clamped.x, dest.y, clamped.z)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	if not _avoid_pending:
		return
	_avoid_pending = false
	_apply_velocity(safe_velocity)


func _apply_velocity(horizontal: Vector3) -> void:
	velocity = Vector3(horizontal.x, _vy, horizontal.z)
	move_and_slide()


func _turn_toward(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	_turn_to_yaw(_yaw_of(dir), delta)


func _turn_to_yaw(yaw: float, delta: float) -> void:
	facing = lerp_angle(facing, yaw, 1.0 - exp(-Tuning.GUARD_TURN_SHARPNESS * delta))
	_apply_facing()


func _apply_facing() -> void:
	model.rotation = Vector3(0.0, facing, 0.0)
	vision_cone.rotation = Vector3(0.0, facing, 0.0)


# --- Visuals ------------------------------------------------------------------

func _dress() -> void:
	match security_type:
		HR.SecurityType.UNDERCOVER:
			var rng := RandomNumberGenerator.new()
			rng.seed = hash("undercover:%d" % guard_id)
			model.appearance_seed = rng.randi()
			model.apply_outfit(OutfitCatalog.random_outfit(rng))
		HR.SecurityType.PIT_BOSS:
			model.appearance_seed = 7919 + guard_id
			model.apply_uniform(&"pit_boss")
		HR.SecurityType.HEAD_OF_SECURITY:
			model.appearance_seed = 7919 + guard_id
			model.apply_uniform(&"head_of_security")
		_:
			model.appearance_seed = 7919 + guard_id
			model.apply_uniform(&"guard")


func _update_visuals(delta: float) -> void:
	_apply_facing()
	_update_pose()
	var state := brain.state
	vision_cone.set_color(_cone_color(state))
	var undercover_hidden := security_type == HR.SecurityType.UNDERCOVER and state != HR.GuardState.CHASE and state != HR.GuardState.CARRY
	vision_cone.visible = not undercover_hidden
	_cone_timer -= delta
	if _cone_timer <= 0.0 and vision_cone.visible and is_inside_tree():
		_cone_timer = Tuning.VISION_CONE_REFRESH_SECONDS
		vision_cone.clip(get_world_3d().direct_space_state, Tuning.GUARD_EYE_HEIGHT * model.scale.y, WORLD_MASK)
	var text := ""
	var tint := Color.WHITE
	if ICONS.has(state):
		var entry: Array = ICONS[state]
		text = entry[0]
		tint = entry[1]
	if security_type == HR.SecurityType.PIT_BOSS and _radio_flash > 0.0:
		text = "!"
		tint = Color(1.0, 0.5, 0.1)
	if undercover_hidden:
		text = ""
	icon.text = text
	icon.modulate = tint
	icon.visible = text != ""
	var top := model.get_head_top() + 0.45
	if _carrying >= 0:
		top += 0.7
	icon.position = Vector3(0, top, 0)


func _cone_color(state: int) -> Color:
	if security_type == HR.SecurityType.PIT_BOSS:
		var hottest := 0.0
		for pid: int in _visible:
			hottest = maxf(hottest, float(_visible[pid]))
		if hottest >= Tuning.WANTED_AT:
			return CONE_RED
		if hottest >= Tuning.SUSPECTED_AT:
			return CONE_ORANGE
	match state:
		HR.GuardState.INVESTIGATE, HR.GuardState.SEARCH:
			return CONE_YELLOW
		HR.GuardState.CHECK_ID:
			return CONE_ORANGE
		HR.GuardState.CHASE, HR.GuardState.CARRY:
			return CONE_RED
		HR.GuardState.STUNNED:
			return CONE_GREY
	return CONE_GREEN


func _update_pose() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	match brain.state:
		HR.GuardState.STUNNED:
			if model.pose != &"tumble":
				model.set_pose(&"idle")
		HR.GuardState.CARRY:
			if _carrying >= 0:
				model.set_pose(&"carry")
			else:
				model.set_pose(&"walk" if speed > 0.3 else &"idle")
		_:
			if _stun_pending:
				pass
			elif speed > 0.3:
				model.set_pose(&"run" if speed > Tuning.GUARD_WALK_SPEED + 0.6 else &"walk")
			else:
				model.set_pose(&"idle")
	model.set_move_speed(speed)


func _on_brain_state_changed(old_state: int, new_state: int) -> void:
	if old_state == HR.GuardState.CHECK_ID:
		_id_pid = -1
		_id_result = GuardBrain.ID_PENDING
	state_changed.emit(self, old_state, new_state)


# --- Helpers ------------------------------------------------------------------

func _entry_for(players: Array, pid: int) -> Dictionary:
	for entry: Variant in players:
		if entry is Dictionary and int((entry as Dictionary).get("pid", -1)) == pid:
			return entry
	return {}


func _current_position() -> Vector3:
	return global_position if is_inside_tree() else position


static func _yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
