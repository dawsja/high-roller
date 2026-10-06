class_name Patron
extends CharacterBody3D
## A casino patron in a random outfit. Wanders between patron points with
## pauses, or sits at a slot machine (pose "play"). Thrown chips make it rush
## over, scramble for a few seconds (a physical blob that blocks guards) and
## then go back to what it was doing. Thinks at a low, staggered rate
## (PATRON_REPATH_SECONDS) so dozens stay cheap. Spawned by PatronCrowd.
## A co-op client's patrons are puppets: PatronCrowd places them from the
## host's synced state and they don't think.

enum Mode { PAUSE, WANDER, SEATED, RUSH, SCRAMBLE, RETURN }

const GROUP := &"patrons"
## Layer 4 (patron); collides with world and other patrons only.
const PATRON_LAYER := 8
const BODY_MASK := 1 | 8
const ARRIVE_DISTANCE := 0.6
## Moved less than this between thinks while walking: stuck, pick elsewhere.
const STUCK_DISTANCE := 0.15

var model: CharacterModel
var nav_agent: NavigationAgent3D
var mode: int = Mode.PAUSE
## Slot seat this patron returns to (only if has_seat).
var seat: Transform3D = Transform3D.IDENTITY
var has_seat: bool = false
## Model yaw in radians; 0 faces -Z.
var facing: float = 0.0
## Co-op client copy: PatronCrowd moves it (see PatronCrowd.net_state).
var puppet: bool = false

var _rng := RandomNumberGenerator.new()
var _points: Array[Vector3] = []
var _target: Vector3 = Vector3.ZERO
var _rush_center: Vector3 = Vector3.ZERO
var _rush_radius: float = 0.0
var _scramble_seconds: float = 0.0
var _timer: float = 0.0
var _think: float = 0.0
var _last_think_pos: Vector3 = Vector3.ZERO
var _since_think_pos: float = 0.0
var _vy: float = 0.0
var _height_synced := false
var _shape: CollisionShape3D


func _init() -> void:
	collision_layer = PATRON_LAYER
	collision_mask = BODY_MASK
	floor_snap_length = 0.3
	add_to_group(GROUP)
	_shape = CollisionShape3D.new()
	_shape.name = "Capsule"
	var capsule := CapsuleShape3D.new()
	capsule.radius = Tuning.PATRON_RADIUS
	capsule.height = Tuning.PLAYER_HEIGHT
	_shape.shape = capsule
	_shape.position = Vector3(0, Tuning.PLAYER_HEIGHT * 0.5, 0)
	add_child(_shape)
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	nav_agent = NavigationAgent3D.new()
	nav_agent.name = "NavAgent"
	nav_agent.path_desired_distance = 0.6
	nav_agent.target_desired_distance = ARRIVE_DISTANCE
	nav_agent.height = Tuning.PLAYER_HEIGHT
	nav_agent.radius = Tuning.PATRON_RADIUS
	add_child(nav_agent)


## `points` are shared wander spots; the seed picks the look and the habits.
func setup(points: Array[Vector3], rng_seed: int) -> void:
	_points = points
	_rng.seed = rng_seed
	model.appearance_seed = _rng.randi()
	model.apply_outfit(OutfitCatalog.random_outfit(_rng))
	_think = _rng.randf() * Tuning.PATRON_REPATH_SECONDS
	_timer = _rng.randf_range(0.0, Tuning.PATRON_PAUSE_MAX)
	mode = Mode.PAUSE


## Sits at a slot seat (origin on the floor under the seat, −Z toward the machine).
func sit_at(seat_transform: Transform3D) -> void:
	seat = seat_transform
	has_seat = true
	_sit()


## Runs to `target` and scrambles there for `seconds`, then goes back to the
## seat or to wandering. `center` is where the chips landed (faced while
## scrambling); once inside `radius` of it and blocked by the crowd, it stops.
func rush(target: Vector3, center: Vector3, radius: float, seconds: float) -> void:
	_target = target
	_rush_center = center
	_scramble_seconds = maxf(seconds, 0.0)
	_rush_radius = maxf(radius, ARRIVE_DISTANCE)
	_timer = Tuning.PATRON_RUSH_MAX_TRAVEL
	mode = Mode.RUSH
	_set_nav_target(target)


func is_rushing() -> bool:
	return mode == Mode.RUSH or mode == Mode.SCRAMBLE


func is_seated() -> bool:
	return mode == Mode.SEATED


func _physics_process(delta: float) -> void:
	if puppet:
		return
	if mode == Mode.SEATED:
		model.set_pose(&"play")
		return
	_timer -= delta
	_think -= delta
	_since_think_pos += delta
	var desired := Vector3.ZERO
	match mode:
		Mode.PAUSE:
			if _timer <= 0.0:
				_wander()
		Mode.WANDER:
			desired = _walk(Tuning.PATRON_WALK_SPEED)
			if _arrived():
				_pause()
		Mode.RUSH:
			desired = _walk(Tuning.PATRON_RUSH_SPEED)
			if _arrived() or _timer <= 0.0:
				mode = Mode.SCRAMBLE
				_timer = _scramble_seconds
		Mode.SCRAMBLE:
			_turn_toward(_rush_center - global_position, delta)
			if _timer <= 0.0:
				_disperse()
		Mode.RETURN:
			desired = _walk(Tuning.PATRON_WALK_SPEED)
			if _arrived():
				_sit()
				return
	if _think <= 0.0:
		_think += Tuning.PATRON_REPATH_SECONDS
		_on_think()
	elif not _height_synced and mode != Mode.PAUSE:
		_sync_path_height()
	if desired.length() > 0.1:
		_turn_toward(desired, delta)
	if is_on_floor():
		_vy = 0.0
	else:
		_vy += get_gravity().y * delta
	velocity = Vector3(desired.x, _vy, desired.z)
	move_and_slide()
	if mode == Mode.RUSH and Perception.flat_distance(global_position, _rush_center) <= _rush_radius:
		var real := get_real_velocity()
		if Vector2(real.x, real.z).length() < Tuning.PATRON_WALK_SPEED * 0.5:
			mode = Mode.SCRAMBLE
			_timer = _scramble_seconds
	_update_pose()


## Low-rate check while walking: re-path to the same goal, or give up if stuck.
func _on_think() -> void:
	var moved := Perception.flat_distance(global_position, _last_think_pos)
	var waited := _since_think_pos
	_mark_think_pos()
	match mode:
		Mode.WANDER, Mode.RETURN:
			if moved < STUCK_DISTANCE and waited >= Tuning.PATRON_REPATH_SECONDS * 0.9:
				if mode == Mode.RETURN:
					_sit()
				else:
					_pause()
			else:
				_set_nav_target(_target)


func _walk(speed: float) -> Vector3:
	var next := _target
	if _nav_has_path():
		next = nav_agent.get_next_path_position()
	var to := next - global_position
	to.y = 0.0
	if to.length() < 0.05:
		to = _target - global_position
		to.y = 0.0
	if Perception.flat_distance(global_position, _target) <= ARRIVE_DISTANCE * 0.5:
		return Vector3.ZERO
	return to.normalized() * speed


func _arrived() -> bool:
	if Perception.flat_distance(global_position, _target) <= ARRIVE_DISTANCE:
		return true
	return _nav_has_path() and nav_agent.is_navigation_finished()


func _mark_think_pos() -> void:
	_last_think_pos = global_position
	_since_think_pos = 0.0


func _wander() -> void:
	if _points.is_empty():
		_pause()
		return
	var pick := _points[_rng.randi_range(0, _points.size() - 1)]
	if _points.size() > 1 and Perception.flat_distance(pick, global_position) < ARRIVE_DISTANCE * 2.0:
		pick = _points[_rng.randi_range(0, _points.size() - 1)]
	_target = pick
	_mark_think_pos()
	mode = Mode.WANDER
	_set_nav_target(pick)


func _pause() -> void:
	mode = Mode.PAUSE
	_timer = _rng.randf_range(Tuning.PATRON_PAUSE_MIN, Tuning.PATRON_PAUSE_MAX)


func _disperse() -> void:
	if has_seat:
		_target = seat.origin
		_mark_think_pos()
		mode = Mode.RETURN
		_set_nav_target(_target)
	else:
		_wander()


func _sit() -> void:
	mode = Mode.SEATED
	velocity = Vector3.ZERO
	_vy = 0.0
	if is_inside_tree():
		global_position = seat.origin
	else:
		position = seat.origin
	var forward := -seat.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		facing = atan2(-forward.x, -forward.z)
	model.rotation = Vector3(0, facing, 0)
	model.set_pose(&"play")


func _set_nav_target(target: Vector3) -> void:
	_sync_path_height()
	nav_agent.target_position = target


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


func _nav_has_path() -> bool:
	if not nav_agent.is_inside_tree():
		return false
	var map := nav_agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	return not NavigationServer3D.map_get_regions(map).is_empty()


func _turn_toward(dir: Vector3, delta: float) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return
	facing = lerp_angle(facing, atan2(-dir.x, -dir.z), 1.0 - exp(-Tuning.GUARD_TURN_SHARPNESS * delta))
	model.rotation = Vector3(0, facing, 0)


func _update_pose() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if mode == Mode.SCRAMBLE:
		model.set_pose(&"celebrate")
	elif speed > 0.3:
		model.set_pose(&"run" if speed > Tuning.PATRON_WALK_SPEED + 0.8 else &"walk")
	else:
		model.set_pose(&"idle")
	model.set_move_speed(speed)

