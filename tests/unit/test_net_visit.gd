extends TestCase
## Co-op visits are rebuilt on every peer from the host's rung and map seed,
## so the builders must be deterministic: the same seed gives the same map
## (geometry, anchors, routes, zones, node names) and the same crowd.


func _layout(map: CasinoMap) -> Dictionary:
	var anchors: Array = []
	for a: Dictionary in map.table_anchors:
		anchors.append([a["id"], a["game_type"], a["area_id"], a["transform"]])
	var zones: Array = []
	for z: CasinoZone in map.zones:
		zones.append([String(z.name), z.zone_type, z.area_id, z.rects()])
	var interactables: Array = []
	for it: Interactable in map.interactables:
		interactables.append([it.kind, it.position, str(it.data)])
	return {
		"anchors": anchors, "zones": zones, "interactables": interactables,
		"spawns": map.spawn_points, "routes": str(map.patrol_routes), "patrons": map.patron_points,
		"seats": map.slot_seats, "mounts": map.camera_mounts, "posts": map.pit_boss_posts,
		"forger": str(map.forger_points), "points": [map.curb_point, map.back_room_point, map.back_room_release_point, map.exit_point],
		"nodes": _names(map), "bounds": map.bounds,
	}


## Names given on purpose (auto names like "@StaticBody3D@12" are never synced).
func _names(node: Node) -> Array:
	var out: Array = []
	for child: Node in node.get_children():
		if not String(child.name).begins_with("@"):
			out.append(String(child.name))
		out.append_array(_names(child))
	return out


func test_the_same_seed_builds_the_same_map() -> void:
	for rung: int in [Tuning.BOTTOM_RUNG, 3, Tuning.TOP_RUNG]:
		var casino: Dictionary = CasinoLadder.casino(rung)
		var a := CasinoBuilder.build(casino, 9001)
		var b := CasinoBuilder.build(casino, 9001)
		var la := _layout(a)
		var lb := _layout(b)
		for key: String in la:
			assert_eq(str(lb[key]), str(la[key]), "%s: %s" % [casino["id"], key])
		a.free()
		b.free()


func test_a_different_seed_still_keeps_the_table_ids() -> void:
	var casino: Dictionary = CasinoLadder.casino(Tuning.BOTTOM_RUNG)
	var a := CasinoBuilder.build(casino, 1)
	var b := CasinoBuilder.build(casino, 2)
	var ids_a: Array = a.table_anchors.map(func(x: Dictionary) -> StringName: return x["id"])
	var ids_b: Array = b.table_anchors.map(func(x: Dictionary) -> StringName: return x["id"])
	assert_eq(ids_b, ids_a, "table ids name the same tables on every peer")
	a.free()
	b.free()


func test_the_same_seed_spawns_the_same_crowd() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 4)]
	var seats: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(8, 0, 0)), Transform3D(Basis.IDENTITY, Vector3(9, 0, 0))]
	var a := PatronCrowd.new()
	var b := PatronCrowd.new()
	b.puppet = true
	a.setup(points, seats, 8, 31337)
	b.setup(points, seats, 8, 31337)
	assert_eq(b.patron_count(), a.patron_count())
	for i in a.patrons.size():
		var pa: Patron = a.patrons[i]
		var pb: Patron = b.patrons[i]
		assert_eq(String(pb.name), String(pa.name))
		assert_eq(pb.position, pa.position, "patron %d starts in the same spot" % i)
		assert_eq(pb.model.appearance_seed, pa.model.appearance_seed, "and looks the same")
		assert_true(pb.puppet, "a puppet crowd's patrons are puppets")
	a.free()
	b.free()


func test_puppet_crowd_follows_the_packed_state() -> void:
	var points: Array[Vector3] = [Vector3(0, 0, 0), Vector3(4, 0, 0)]
	var seats: Array[Transform3D] = []
	var world := Node3D.new()
	tree.root.add_child(world)
	var src := PatronCrowd.new()
	var dst := PatronCrowd.new()
	dst.puppet = true
	world.add_child(src)
	world.add_child(dst)
	src.setup(points, seats, 3, 5)
	dst.setup(points, seats, 3, 5)
	src.patrons[1].global_position = Vector3(2, 0, 1)
	src.patrons[1].model.set_pose(&"celebrate")
	src._publish()
	dst.net_state = src.net_state
	for i in 60:
		dst._follow(1.0 / 60.0)
	assert_lt(dst.patrons[1].global_position.distance_to(Vector3(2, 0, 1)), 0.05)
	assert_eq(dst.patrons[1].model.pose, &"celebrate")
	world.free()
