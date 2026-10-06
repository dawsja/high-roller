class_name SecurityCamera
extends Node3D
## A wall-mounted security camera. The housing sweeps its yaw back and forth
## (CAMERA_SWEEP_DEGREES each side over CAMERA_SWEEP_SECONDS) and follows the
## hottest Watched+ player it sees within that arc. Its view (CAMERA_FOV_DEGREES,
## CAMERA_RANGE, Perception.in_vision_cone + a world-layer line of sight from
## the lens to the chest) is drawn as a fan on the floor. World-side only: it
## reports through signals (the director sets in_camera_view and reports
## sightings); it never changes Heat itself.
##
## Co-op: cameras look only on the host; enable_net_sync() sends the sweep and
## the watching light, and a client's `puppet` camera just shows them.

## A player entered (true) or left (false) the view. Drives in_camera_view.
signal watching(camera: SecurityCamera, pid: int, active: bool)
## A Suspected+ player is in view (per player at most every CAMERA_SPOT_COOLDOWN).
signal spotted(camera: SecurityCamera, pid: int)

const WORLD_MASK := 1
const HOUSING_COLOR := Color("d8d8dc")
const BRACKET_COLOR := Color("4a4a52")
const LENS_COLOR := Color("101014")
const LIGHT_ON := Color(1.0, 0.1, 0.08)
const LIGHT_OFF := Color("3a1414")
const CONE_IDLE := Color(0.55, 0.8, 1.0, 0.16)
const CONE_WATCHING := Color(1.0, 0.15, 0.1, 0.26)
## Lens distance in front of the pivot along the view.
const LENS_FORWARD := 0.32
const NET_SYNC_INTERVAL := 1.0 / 20.0

var camera_id: int = -1
var vision_cone: VisionCone
## Current yaw offset from the mount's forward, radians.
var sweep_yaw: float = 0.0
## Height of the floor the fan is drawn on.
var floor_y: float = 0.0
## Co-op client copy: shows the host's sweep and light, never looks itself.
var puppet: bool = false
# Synced from the host (see enable_net_sync()).
var net_yaw: float = 0.0
var net_watching: bool = false

var _players_provider: Callable
var _pivot: Node3D
var _head: Node3D
var _lens: Node3D
var _light_on: MeshInstance3D
var _light_off: MeshInstance3D
var _watched: Dictionary = {}
var _spot_cooldowns: Dictionary = {}
var _time: float = 0.0
var _cone_timer: float = 0.0
var _net_sync: bool = false


func _init() -> void:
	var bracket := Primitives.box(Vector3(0.14, 0.14, 0.22), BRACKET_COLOR)
	bracket.name = "Bracket"
	bracket.position = Vector3(0, 0.12, 0.08)
	add_child(bracket)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	var stem := Primitives.cylinder(0.035, 0.14, BRACKET_COLOR, 8)
	stem.position = Vector3(0, 0.06, 0)
	_pivot.add_child(stem)
	_head = Node3D.new()
	_head.name = "Head"
	_head.rotation = Vector3(-deg_to_rad(Tuning.CAMERA_TILT_DEGREES), 0, 0)
	_pivot.add_child(_head)
	var housing := Primitives.box(Vector3(0.2, 0.18, 0.46), HOUSING_COLOR)
	housing.position = Vector3(0, 0, -0.1)
	_head.add_child(housing)
	var hood := Primitives.box(Vector3(0.24, 0.03, 0.5), HOUSING_COLOR.darkened(0.15))
	hood.position = Vector3(0, 0.105, -0.12)
	_head.add_child(hood)
	var lens := Primitives.cylinder(0.065, 0.06, LENS_COLOR, 12)
	lens.rotation = Vector3(PI * 0.5, 0, 0)
	lens.position = Vector3(0, 0, -0.34)
	_head.add_child(lens)
	var glass := Primitives.sphere(0.045, Color(0.25, 0.45, 0.75), 10, 0.6)
	glass.position = Vector3(0, 0, -0.36)
	glass.scale = Vector3(1, 1, 0.4)
	_head.add_child(glass)
	_lens = Node3D.new()
	_lens.name = "Lens"
	_lens.position = Vector3(0, 0, -LENS_FORWARD - 0.06)
	_head.add_child(_lens)
	_light_on = Primitives.sphere(0.03, LIGHT_ON, 8, 3.0)
	_light_on.position = Vector3(0.07, 0.06, -0.31)
	_light_on.visible = false
	_head.add_child(_light_on)
	_light_off = Primitives.sphere(0.03, LIGHT_OFF, 8)
	_light_off.position = _light_on.position
	_head.add_child(_light_off)
	vision_cone = VisionCone.new(Tuning.CAMERA_RANGE, Tuning.CAMERA_FOV_DEGREES, CONE_IDLE)
	vision_cone.top_level = true
	add_child(vision_cone)


## `mount` places the camera (−Z looks into the room, origin at the mount
## height). `players_provider` is the same as GuardNPC's.
func setup(id: int, mount: Transform3D, players_provider: Callable) -> void:
	camera_id = id
	_players_provider = players_provider
	if is_inside_tree():
		global_transform = mount
	else:
		transform = mount
	floor_y = mount.origin.y - Tuning.CAMERA_MOUNT_HEIGHT
	# Cameras start at different points of their sweep.
	_time = fposmod(float(id) * 1.7, Tuning.CAMERA_SWEEP_SECONDS)
	sweep_yaw = _sweep_target()
	_pivot.rotation = Vector3(0, sweep_yaw, 0)


## Adds the MultiplayerSynchronizer for the sweep and the light (the host
## sends, a client's puppet applies; both sides need it).
func enable_net_sync() -> void:
	_net_sync = true
	net_yaw = sweep_yaw
	NetSync.attach(self, [&"net_yaw"], [&"net_watching"], NET_SYNC_INTERVAL)


## pids in view right now.
func watched_pids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in _watched:
		out.append(pid)
	return out


func is_watching(pid: int = -1) -> bool:
	return not _watched.is_empty() if pid < 0 else _watched.has(pid)


## World position of the lens.
func lens_position() -> Vector3:
	return _lens.global_position


## Unit vector the camera looks along, on the floor plane.
func view_direction() -> Vector3:
	var fwd := -_pivot.global_basis.z
	fwd.y = 0.0
	return fwd.normalized() if fwd.length_squared() > 0.000001 else Vector3.FORWARD


func _physics_process(delta: float) -> void:
	if puppet:
		sweep_yaw = lerp_angle(sweep_yaw, net_yaw, 1.0 - exp(-16.0 * delta))
		_pivot.rotation = Vector3(0, sweep_yaw, 0)
		_update_visuals(delta)
		return
	_time += delta
	var players := _query_players()
	_update_sweep(delta, players)
	var seen := _look(players)
	for pid: int in seen:
		if not _watched.has(pid):
			_watched[pid] = true
			watching.emit(self, pid, true)
	for pid: int in _watched.keys():
		if not seen.has(pid):
			_watched.erase(pid)
			watching.emit(self, pid, false)
	for pid: int in seen:
		if float(seen[pid]) >= Tuning.SUSPECTED_AT and _time >= float(_spot_cooldowns.get(pid, -INF)):
			_spot_cooldowns[pid] = _time + Tuning.CAMERA_SPOT_COOLDOWN
			spotted.emit(self, pid)
	_update_visuals(delta)
	if _net_sync:
		net_yaw = sweep_yaw
		net_watching = not _watched.is_empty()


func _exit_tree() -> void:
	for pid: int in _watched.keys():
		watching.emit(self, pid, false)
	_watched.clear()


func _query_players() -> Array:
	if not _players_provider.is_valid():
		return []
	var result: Variant = _players_provider.call()
	return result if result is Array else []


## pid -> Heat of every available player in view.
func _look(players: Array) -> Dictionary:
	var seen := {}
	var space := get_world_3d().direct_space_state
	var eye := lens_position()
	var forward := view_direction()
	for entry: Variant in players:
		if not (entry is Dictionary):
			continue
		var p: Dictionary = entry
		var pid := int(p.get("pid", -1))
		var node := p.get("node") as Node3D
		if pid < 0 or node == null or not is_instance_valid(node) or not node.is_inside_tree() or not node.is_visible_in_tree():
			continue
		if not bool(p.get("available", true)):
			continue
		var pos := node.global_position
		if not Perception.in_vision_cone(eye, forward, pos, Tuning.CAMERA_FOV_DEGREES, Tuning.CAMERA_RANGE):
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, pos + Vector3.UP * Tuning.SIGHT_CHEST_HEIGHT, WORLD_MASK)
		if not space.intersect_ray(query).is_empty():
			continue
		seen[pid] = float(p.get("heat", 0.0))
	return seen


## Sweeps, or turns toward the hottest Watched+ player already in view.
func _update_sweep(delta: float, players: Array) -> void:
	var target := _sweep_target()
	var hottest := -1.0
	var limit := deg_to_rad(Tuning.CAMERA_SWEEP_DEGREES)
	for entry: Variant in players:
		if not (entry is Dictionary):
			continue
		var p: Dictionary = entry
		var pid := int(p.get("pid", -1))
		var heat := float(p.get("heat", 0.0))
		var node := p.get("node") as Node3D
		if not _watched.has(pid) or heat < Tuning.WATCHED_AT or heat <= hottest or node == null or not is_instance_valid(node):
			continue
		var to := global_transform.affine_inverse() * node.global_position
		to.y = 0.0
		if to.length_squared() < 0.01:
			continue
		hottest = heat
		target = clampf(atan2(-to.x, -to.z), -limit, limit)
	var step := deg_to_rad(Tuning.CAMERA_TRACK_DEGREES_PER_SECOND) * delta
	sweep_yaw = move_toward(sweep_yaw, target, step)
	_pivot.rotation = Vector3(0, sweep_yaw, 0)


func _sweep_target() -> float:
	return sin(_time * TAU / Tuning.CAMERA_SWEEP_SECONDS) * deg_to_rad(Tuning.CAMERA_SWEEP_DEGREES)


func _update_visuals(delta: float) -> void:
	var on := net_watching if puppet else not _watched.is_empty()
	_light_on.visible = on
	_light_off.visible = not on
	vision_cone.set_color(CONE_WATCHING if on else CONE_IDLE)
	var lens := lens_position()
	var fwd := view_direction()
	vision_cone.global_transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), Vector3(lens.x, floor_y + Tuning.VISION_CONE_HEIGHT, lens.z))
	_cone_timer -= delta
	if _cone_timer <= 0.0:
		_cone_timer = Tuning.VISION_CONE_REFRESH_SECONDS
		vision_cone.clip(get_world_3d().direct_space_state, Tuning.SIGHT_CHEST_HEIGHT, WORLD_MASK)
