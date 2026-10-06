extends TestCase

var _world: Node3D
var _region: NavigationRegion3D


func before_each() -> void:
	_world = Node3D.new()
	_world.name = "CrowdTestWorld"
	tree.root.add_child(_world)
	_region = NavigationRegion3D.new()
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	_region.navigation_mesh = nav_mesh
	_world.add_child(_region)
	var floor := Primitives.static_box(Vector3(50, 1, 50), Color.DIM_GRAY)
	floor.position = Vector3(0, -0.5, 0)
	_region.add_child(floor)
	var wall := Primitives.static_box(Vector3(0.4, 3, 8), Color.GRAY)
	wall.position = Vector3(-12, 1.5, 0)
	_region.add_child(wall)


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await tree.process_frame
		await tree.physics_frame
	_world = null


func _bake() -> void:
	_region.bake_navigation_mesh(false)
	var map := _region.get_navigation_map()
	for i in 60:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_path(map, Vector3(-1, 0, 1), Vector3(1, 0, 1), true).is_empty():
			break
	await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for x in [-6.0, -2.0, 2.0, 6.0]:
		for z in [-6.0, -2.0, 2.0, 6.0]:
			pts.append(Vector3(x, 0, z))
	return pts


func _seats() -> Array[Transform3D]:
	var seats: Array[Transform3D] = []
	for i in 4:
		seats.append(Transform3D(Basis.IDENTITY, Vector3(-8.0 + i * 1.2, 0, 9.0)))
	return seats


func _crowd(count: int, rng_seed: int = 7) -> PatronCrowd:
	var crowd := PatronCrowd.new()
	_world.add_child(crowd)
	crowd.setup(_points(), _seats(), count, rng_seed)
	return crowd


func _mean_distance(crowd: PatronCrowd, center: Vector3, only: Array = []) -> float:
	var total := 0.0
	var n := 0
	for p: Patron in crowd.patrons:
		if not only.is_empty() and not only.has(p):
			continue
		total += Perception.flat_distance(p.global_position, center)
		n += 1
	return total / maxf(n, 1)


func test_spawns_patrons_in_random_outfits_some_seated() -> void:
	await _bake()
	var crowd := _crowd(10)
	await _frames(2)
	assert_eq(crowd.patron_count(), 10)
	assert_eq(crowd.seated_count(), 4, "35% of 10 rounds to 4 (and 4 seats)")
	var looks := {}
	for p: Patron in crowd.patrons:
		assert_eq(p.collision_layer, 8, "patron layer 4")
		assert_eq(p.collision_mask, 1 | 8, "world + patron")
		assert_true(p.is_in_group(&"patrons"))
		assert_not_null(p.model.outfit)
		assert_false(p.model.outfit.is_staff_uniform())
		looks[str(p.model.outfit.to_dict())] = true
		if p.is_seated():
			assert_eq(p.model.pose, &"play", "seated patrons play the slots")
	assert_gt(looks.size(), 5, "outfits vary")


func test_same_seed_same_crowd() -> void:
	var a := _crowd(6, 42)
	var b := _crowd(6, 42)
	for i in 6:
		assert_true(a.patrons[i].model.outfit.equals(b.patrons[i].model.outfit), "patron %d dressed the same" % i)
		assert_true(a.patrons[i].position.is_equal_approx(b.patrons[i].position))
	var c := _crowd(6, 43)
	var same := 0
	for i in 6:
		if a.patrons[i].model.outfit.equals(c.patrons[i].model.outfit):
			same += 1
	assert_lt(same, 6, "another seed dresses them differently")


func test_patrons_wander_between_points() -> void:
	await _bake()
	var crowd := _crowd(6)
	var starts := {}
	for p: Patron in crowd.patrons:
		starts[p] = p.global_position
	await _frames(360)
	var moved := 0
	for p: Patron in crowd.patrons:
		if not p.is_seated() and p.global_position.distance_to(starts[p]) > 1.0:
			moved += 1
	assert_gt(moved, 0, "some patrons strolled off")


func test_rush_moves_patrons_toward_the_point() -> void:
	await _bake()
	var crowd := _crowd(12)
	var far := Patron.new()
	far.setup(_points(), 99)
	far.position = Vector3(20, 0.05, 20)
	crowd.add_child(far)
	crowd.patrons.append(far)
	await _frames(5)
	var center := Vector3(1, 0, 1)
	var near: Array = []
	for p: Patron in crowd.patrons:
		if Perception.flat_distance(p.global_position, center) <= Tuning.PATRON_RUSH_RANGE:
			near.append(p)
	var before := _mean_distance(crowd, center, near)
	var sent := crowd.rush_to(center, Tuning.THROW_CHIPS_BLOCK_RADIUS, Tuning.THROW_CHIPS_BLOCK_SECONDS)
	assert_eq(sent, near.size(), "everyone within range rushes")
	assert_false(far.is_rushing(), "patrons too far away keep going")
	await _frames(150)
	var after := _mean_distance(crowd, center, near)
	assert_lt(after, before * 0.6, "crowded in: %.2f -> %.2f" % [before, after])
	assert_lt(after, Tuning.THROW_CHIPS_BLOCK_RADIUS + 1.0, "a blob around the chips")
	var scrambling := 0
	for p: Patron in near:
		if p.is_rushing():
			scrambling += 1
	assert_gt(scrambling, near.size() / 2, "still scrambling")


func test_rushers_disperse_and_seated_ones_go_back() -> void:
	await _bake()
	var crowd := _crowd(10)
	await _frames(3)
	var sitter: Patron = null
	for p: Patron in crowd.patrons:
		if p.is_seated():
			sitter = p
			break
	assert_not_null(sitter)
	var seat := sitter.seat.origin
	crowd.rush_to(seat + Vector3(3, 0, -2), 2.0, 0.3)
	await _frames(2)
	assert_true(sitter.is_rushing(), "a seated patron joins the rush")
	var back := false
	for i in 400:
		await tree.physics_frame
		if sitter.is_seated():
			back = true
			break
	assert_true(back, "back at the slot machine")
	assert_lt(Perception.flat_distance(sitter.global_position, seat), 0.05)
	var rushing := func() -> bool: return crowd.patrons.any(func(p: Patron) -> bool: return p.is_rushing())
	for i in 240:
		if not rushing.call():
			break
		await tree.physics_frame
	assert_false(rushing.call(), "the rush ended for everyone")
