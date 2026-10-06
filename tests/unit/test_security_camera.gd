extends TestCase

var _world: Node3D
var _players: Array = []
var _events: Array = []


func before_each() -> void:
	_players = []
	_events = []
	_world = Node3D.new()
	_world.name = "CameraTestWorld"
	tree.root.add_child(_world)
	var floor := Primitives.static_box(Vector3(40, 1, 40), Color.DIM_GRAY)
	floor.position = Vector3(0, -0.5, 0)
	_world.add_child(floor)


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await tree.process_frame
		await tree.physics_frame
	_world = null
	_players = []


func _provider() -> Array:
	return _players


func _player(pid: int, pos: Vector3, heat: float) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	_world.add_child(p)
	_players.append({"pid": pid, "node": p, "heat": heat, "matches_poster": false, "staff_uniform": false, "available": true})
	return p


## Camera on a wall at z = 8 looking toward -Z, mid-sweep (yaw 0) at id 0.
func _camera(id: int = 0, origin: Vector3 = Vector3(0, Tuning.CAMERA_MOUNT_HEIGHT, 8)) -> SecurityCamera:
	var cam := SecurityCamera.new()
	_world.add_child(cam)
	cam.setup(id, Transform3D(Basis.IDENTITY, origin), _provider)
	cam.watching.connect(func(_c: SecurityCamera, pid: int, active: bool) -> void: _events.append(["watching", pid, active]))
	cam.spotted.connect(func(_c: SecurityCamera, pid: int) -> void: _events.append(["spotted", pid, true]))
	return cam


func _count(kind: String, pid: int = -1, active: Variant = null) -> int:
	var n := 0
	for e: Array in _events:
		if e[0] == kind and (pid < 0 or e[1] == pid) and (active == null or e[2] == active):
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func test_builds_mounted_camera_with_floor_fan() -> void:
	var cam := _camera()
	await _frames(2)
	assert_almost_eq(cam.global_position.y, Tuning.CAMERA_MOUNT_HEIGHT, 0.001)
	assert_lt(cam.lens_position().z, 8.0, "lens sticks out from the wall into the room")
	assert_not_null(cam.vision_cone)
	assert_almost_eq(cam.vision_cone.reach, Tuning.CAMERA_RANGE, 0.001)
	assert_almost_eq(cam.vision_cone.fov_degrees, Tuning.CAMERA_FOV_DEGREES, 0.001)
	assert_almost_eq(cam.vision_cone.global_position.y, Tuning.VISION_CONE_HEIGHT, 0.01, "fan lies on the floor")
	assert_false(cam.is_watching())


func test_sweeps_back_and_forth_within_limits() -> void:
	var cam := _camera()
	var lo := INF
	var hi := -INF
	for i in 200:
		await tree.physics_frame
		lo = minf(lo, cam.sweep_yaw)
		hi = maxf(hi, cam.sweep_yaw)
	var limit := deg_to_rad(Tuning.CAMERA_SWEEP_DEGREES)
	assert_gt(hi, limit * 0.8, "swept one way")
	assert_lte(hi, limit + 0.001)
	assert_lt(lo, 0.0, "and started back")
	assert_gte(lo, -limit - 0.001)
	var fan_dir := -cam.vision_cone.global_basis.z
	assert_gt(fan_dir.dot(cam.view_direction()), 0.99, "fan follows the sweep")


func test_watching_toggles_and_lights_up() -> void:
	var cam := _camera()
	var p := _player(1, Vector3(0, 0, 2), 10.0)
	await _frames(2)
	assert_eq(_count("watching", 1, true), 1, "started watching")
	assert_true(cam.is_watching(1))
	assert_true(cam.vision_cone.color.is_equal_approx(SecurityCamera.CONE_WATCHING), "red while watching")
	p.position = Vector3(0, 0, 30)
	await _frames(2)
	assert_eq(_count("watching", 1, false), 1, "stopped watching")
	assert_false(cam.is_watching())
	assert_true(cam.vision_cone.color.is_equal_approx(SecurityCamera.CONE_IDLE))
	p.position = Vector3(0, 0, 2)
	await _frames(2)
	assert_eq(_count("watching", 1, true), 2, "on again")


func test_wall_blocks_the_camera() -> void:
	var wall := Primitives.static_box(Vector3(10, 3, 0.4), Color.GRAY)
	wall.position = Vector3(0, 1.5, 4)
	_world.add_child(wall)
	var cam := _camera()
	_player(1, Vector3(0, 0, 0), 60.0)
	await _frames(5)
	assert_eq(_count("watching"), 0)
	assert_eq(_count("spotted"), 0)
	assert_lt(cam.vision_cone.min_ray_length(), 6.0, "fan cut at the wall")


func test_spots_suspected_players_with_a_cooldown() -> void:
	var cam := _camera()
	_player(1, Vector3(0, 0, 2), 60.0)
	_player(2, Vector3(1, 0, 2), 30.0)
	await _frames(30)
	assert_eq(_count("spotted", 1), 1, "spotted once (cooldown)")
	assert_eq(_count("spotted", 2), 0, "Watched is not spotted")
	assert_true(cam.is_watching(2), "but is watched")


func test_unavailable_or_hidden_players_are_ignored() -> void:
	var cam := _camera()
	_player(1, Vector3(0, 0, 2), 60.0)
	_players[0]["available"] = false
	var p2 := _player(2, Vector3(1, 0, 2), 60.0)
	p2.visible = false
	await _frames(3)
	assert_false(cam.is_watching())


func test_follows_a_watched_player_within_its_arc() -> void:
	var cam := _camera()
	# 30 degrees to the camera's left (the way the sweep starts), 6 m out.
	var spot := Vector3(-sin(deg_to_rad(30.0)) * 6.0, 0, 8.0 - cos(deg_to_rad(30.0)) * 6.0)
	_player(1, spot, 40.0)
	await _frames(150)
	assert_true(cam.is_watching(1), "keeps the player in view")
	var to := spot - cam.lens_position()
	to.y = 0.0
	assert_gt(cam.view_direction().dot(to.normalized()), 0.97, "turned to follow")


func test_leaving_the_tree_ends_watching() -> void:
	var cam := _camera()
	_player(1, Vector3(0, 0, 2), 10.0)
	await _frames(2)
	assert_true(cam.is_watching(1))
	_world.remove_child(cam)
	assert_eq(_count("watching", 1, false), 1, "watching(false) on exit")
	cam.free()
