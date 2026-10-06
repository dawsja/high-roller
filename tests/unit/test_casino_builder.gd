extends TestCase

const REQUIRED_ZONES := [
	HR.ZoneType.FLOOR, HR.ZoneType.TABLES, HR.ZoneType.SLOTS, HR.ZoneType.BAR, HR.ZoneType.BUFFET,
	HR.ZoneType.RESTROOM, HR.ZoneType.CASHIER, HR.ZoneType.GIFT_SHOP, HR.ZoneType.BACK_ROOM,
	HR.ZoneType.EXIT, HR.ZoneType.STAFF_ONLY, HR.ZoneType.ENTRANCE, HR.ZoneType.FORGER,
]
const REQUIRED_KINDS := [
	&"cashier", &"restroom", &"gift_shop", &"forger", &"tray", &"fire_alarm",
	&"laundry_cart", &"staff_locker", &"exit", &"slot_alarm",
]
const COMMON_GAMES := [HR.GameType.BLACKJACK, HR.GameType.ROULETTE, HR.GameType.DICE, HR.GameType.HIGH_LOW]
## A path counts as arriving if it ends this close to the target (XZ).
const ARRIVE := 1.0


func _floor(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


func _zone_types(map: CasinoMap) -> Array:
	var types: Array = []
	for z: CasinoZone in map.zones:
		if not types.has(z.zone_type):
			types.append(z.zone_type)
	return types


func _free(node: Node) -> void:
	node.queue_free()
	await tree.process_frame
	await tree.physics_frame


## Builds, adds to the tree, bakes and waits for the navigation map.
func _baked(casino: Dictionary, seed_value: int = 3) -> CasinoMap:
	var map := CasinoBuilder.build(casino, seed_value)
	tree.root.add_child(map)
	map.bake_navigation()
	var ready: bool = await map.await_navigation()
	assert_true(ready, "%s navigation never synced" % casino["id"])
	return map


func _path_end(map: CasinoMap, from: Vector3, to: Vector3) -> Vector3:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map.navigation_map(), from, to, true)
	if path.is_empty():
		return Vector3.INF
	return path[path.size() - 1]


func _assert_reachable(map: CasinoMap, to: Vector3, what: String) -> void:
	var end: Vector3 = _path_end(map, map.spawn_points[0], to)
	assert_true(end != Vector3.INF, "%s: no path to %s %s" % [map.casino["id"], what, to])
	if end != Vector3.INF:
		assert_lt(Vector2(end.x, end.z).distance_to(Vector2(to.x, to.z)), ARRIVE, "%s: path to %s %s ends at %s" % [map.casino["id"], what, to, end])


func test_size_classes_follow_the_ladder() -> void:
	assert_eq(CasinoLayouts.size_class(6), CasinoLayouts.SMALL)
	assert_eq(CasinoLayouts.size_class(5), CasinoLayouts.SMALL)
	assert_eq(CasinoLayouts.size_class(4), CasinoLayouts.MEDIUM)
	assert_eq(CasinoLayouts.size_class(3), CasinoLayouts.MEDIUM)
	assert_eq(CasinoLayouts.size_class(2), CasinoLayouts.LARGE)
	assert_eq(CasinoLayouts.size_class(1), CasinoLayouts.LARGE)
	var small: Dictionary = CasinoLayouts.plan(CasinoLadder.casino(6))
	var medium: Dictionary = CasinoLayouts.plan(CasinoLadder.casino(4))
	var large: Dictionary = CasinoLayouts.plan(CasinoLadder.casino(1))
	assert_lt(float(small["w"]) * float(small["d"]), float(medium["w"]) * float(medium["d"]))
	assert_lt(float(medium["w"]) * float(medium["d"]), float(large["w"]) * float(large["d"]))


func test_plans_sit_on_the_two_metre_grid() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var plan: Dictionary = CasinoLayouts.plan(casino)
		var x0: float = plan["x0"]
		var z0: float = plan["z0"]
		var rects: Dictionary = plan["rects"]
		for key: String in rects:
			var r: Rect2 = rects[key]
			for v: float in [r.position.x - x0, r.end.x - x0]:
				assert_almost_eq(fposmod(v, CasinoLayouts.GRID), 0.0, 0.001, "%s %s x off grid" % [casino["id"], key])
			for v: float in [r.position.y - z0, r.end.y - z0]:
				assert_almost_eq(fposmod(v, CasinoLayouts.GRID), 0.0, 0.001, "%s %s z off grid" % [casino["id"], key])
		for d: Dictionary in plan["doors"]:
			var a: Vector2 = d["a"]
			assert_almost_eq(fposmod(a.x - x0, CasinoLayouts.GRID), 0.0, 0.001, "door %s" % d["kind"])
			assert_almost_eq(fposmod(a.y - z0, CasinoLayouts.GRID), 0.0, 0.001, "door %s" % d["kind"])


func test_every_rung_has_required_zones_interactables_and_points() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var map := CasinoBuilder.build(casino, 11)
		var id: String = String(casino["id"])
		assert_eq(map.casino["id"], casino["id"])
		var types: Array = _zone_types(map)
		for t: int in REQUIRED_ZONES:
			assert_has(types, t, "%s zone %s" % [id, HR.ZoneType.find_key(t)])
		var game_areas := {}
		for z: CasinoZone in map.zones:
			assert_eq(z.collision_mask, CasinoZone.PLAYER_BIT, "zones watch players")
			if z.zone_type == HR.ZoneType.TABLES:
				assert_false(game_areas.has(z.area_id), "%s duplicate area %s" % [id, z.area_id])
				game_areas[z.area_id] = true
		assert_gte(game_areas.size(), 2, "%s has 2+ table areas" % id)
		var forger_areas: Array = []
		for z: CasinoZone in map.zones_of_type(HR.ZoneType.FORGER):
			forger_areas.append(z.area_id)
		for loc: StringName in Forger.LOCATIONS:
			assert_has(forger_areas, loc, "%s forger zone" % id)
			assert_true(map.forger_points.has(loc), "%s forger point %s" % [id, loc])
			var at: CasinoZone = map.zone_at(map.forger_points[loc])
			assert_true(at != null and at.zone_type == HR.ZoneType.FORGER and at.area_id == loc, "%s forger point %s in its zone" % [id, loc])

		for kind: StringName in REQUIRED_KINDS:
			assert_false(map.interactables_of(kind).is_empty(), "%s interactable %s" % [id, kind])
		assert_eq(map.interactables_of(&"forger").size(), 3)
		assert_gte(map.interactables_of(&"tray").size(), 3, "%s trays around the floor" % id)
		for it: Interactable in map.interactables:
			assert_eq(it.collision_layer, Interactable.LAYER_BIT)
		var board_ids: Array = []
		for b: PosterBoardNode in map.poster_boards:
			board_ids.append(b.board_id)
		for b: StringName in [&"entrance", &"cashier", &"security_desk"]:
			assert_has(board_ids, b, "%s poster board" % id)

		# Interactables stand in the zone their request needs.
		var needs := {&"cashier": HR.ZoneType.CASHIER, &"restroom": HR.ZoneType.RESTROOM, &"gift_shop": HR.ZoneType.GIFT_SHOP,
			&"laundry_cart": HR.ZoneType.STAFF_ONLY, &"staff_locker": HR.ZoneType.STAFF_ONLY, &"exit": HR.ZoneType.EXIT}
		for kind: StringName in needs:
			var it: Interactable = map.interactables_of(kind)[0]
			var at: CasinoZone = map.zone_at(it.position)
			assert_true(at != null and at.zone_type == needs[kind], "%s %s stands in %s" % [id, kind, HR.ZoneType.find_key(needs[kind])])

		# Points land in the right places.
		assert_gte(map.spawn_points.size(), 4, "%s spawn points for a crew" % id)
		for p: Vector3 in map.spawn_points:
			assert_eq(map.zone_at(p).zone_type, HR.ZoneType.ENTRANCE, "%s spawn in the entrance" % id)
		assert_eq(map.zone_at(map.back_room_point).zone_type, HR.ZoneType.BACK_ROOM, "%s back room point" % id)
		assert_eq(map.zone_at(map.back_room_release_point).zone_type, HR.ZoneType.FLOOR, "%s release point on the floor" % id)
		assert_eq(map.zone_at(map.exit_point).zone_type, HR.ZoneType.EXIT, "%s exit point" % id)
		var curb: CasinoZone = map.zone_at(map.curb_point)
		assert_true(curb != null and curb.zone_type == HR.ZoneType.FLOOR and curb.area_id == &"outside", "%s curb is outside" % id)
		assert_gt(map.curb_point.z, 0.0, "%s curb in front of the building" % id)
		assert_gte(map.pit_boss_posts.size(), game_areas.size(), "%s pit boss post per table area" % id)
		assert_gte(map.camera_mounts.size(), 4, "%s camera mounts" % id)
		for m: Transform3D in map.camera_mounts:
			assert_gt(m.origin.y, 2.0, "camera mounted high")
			assert_lt((-m.basis.z).y, 0.0, "camera looks down at the floor")
		assert_gte(map.patron_points.size(), 15, "%s patron points" % id)
		assert_gte(map.slot_seats.size(), 3, "%s slot seats" % id)
		for s: Transform3D in map.slot_seats:
			assert_eq(map.zone_at(s.origin).zone_type, HR.ZoneType.SLOTS, "%s slot seat in the slots" % id)
		assert_true(map.bounds.has_point(map.exit_point + Vector3(0, 0.5, 0)), "bounds cover the lot")
		map.free()


func test_table_anchors_cover_every_game_with_unique_ids() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var map := CasinoBuilder.build(casino, 5)
		var id: String = String(casino["id"])
		var counts := {}
		var ids := {}
		for a: Dictionary in map.table_anchors:
			var tid: StringName = a["id"]
			assert_false(ids.has(tid), "%s duplicate table id %s" % [id, tid])
			ids[tid] = true
			var game: int = a["game_type"]
			counts[game] = int(counts.get(game, 0)) + 1
			var xf: Transform3D = a["transform"]
			var zone: CasinoZone = map.zone_at(xf.origin)
			assert_true(zone != null and zone.area_id == a["area_id"], "%s %s sits in area %s" % [id, tid, a["area_id"]])
			var want: int = HR.ZoneType.SLOTS if game == HR.GameType.SLOTS else HR.ZoneType.TABLES
			assert_eq(zone.zone_type if zone != null else -1, want, "%s %s zone type" % [id, tid])
			assert_almost_eq(xf.basis.y.y, 1.0, 0.001, "anchors stand upright")
		for game: int in TableGames.all_types():
			assert_gte(int(counts.get(game, 0)), 1, "%s has %s" % [id, HR.GameType.find_key(game)])
		if int(casino["rung"]) <= 4:
			for game: int in COMMON_GAMES:
				assert_gte(int(counts.get(game, 0)), 2, "%s has 2+ %s" % [id, HR.GameType.find_key(game)])
		assert_gte(int(counts.get(HR.GameType.SLOTS, 0)), 3, "%s has a row of slots" % id)
		map.free()


func test_patrol_routes_loop_through_the_floor_and_are_distinct() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var map := CasinoBuilder.build(casino, 9)
		var id: String = String(casino["id"])
		assert_gte(map.patrol_routes.size(), int(casino["guards"]), "%s route per guard" % id)
		var seen := {}
		for route: Variant in map.patrol_routes:
			assert_true(route is Array, "route is an array")
			var points: Array[Vector3] = []
			points.assign(route)
			assert_gte(points.size(), 4, "%s route is a loop" % id)
			var key: String = str(points)
			assert_false(seen.has(key), "%s routes are distinct" % id)
			seen[key] = true
			for p: Vector3 in points:
				var z: CasinoZone = map.zone_at(p)
				assert_true(z != null and z.zone_type in [HR.ZoneType.FLOOR, HR.ZoneType.CASHIER], "%s patrol point %s on the main floor" % [id, p])
		map.free()


func test_same_seed_same_map() -> void:
	var casino: Dictionary = CasinoLadder.casino(2)
	var a := CasinoBuilder.build(casino, 42)
	var b := CasinoBuilder.build(casino, 42)
	assert_eq(str(a.patrol_routes), str(b.patrol_routes))
	assert_eq(str(a.patron_points), str(b.patron_points))
	assert_eq(a.table_anchors.size(), b.table_anchors.size())
	a.free()
	b.free()


func test_static_geometry_is_world_layer_boxes() -> void:
	var map := CasinoBuilder.build(CasinoLadder.casino(6), 1)
	var bodies: Array[Node] = map.nav_region.find_children("*", "StaticBody3D", true, false)
	assert_gt(bodies.size(), 50, "plenty of solid geometry")
	for n: Node in bodies:
		var body := n as StaticBody3D
		assert_eq(body.collision_layer, 1, "%s on the world layer" % body.name)
		for c: Node in body.get_children():
			if c is CollisionShape3D:
				assert_true((c as CollisionShape3D).shape is BoxShape3D, "%s uses box collision" % body.name)
	var nm: NavigationMesh = map.nav_region.navigation_mesh
	assert_eq(nm.geometry_parsed_geometry_type, NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS)
	assert_almost_eq(nm.cell_size, Tuning.NAV_CELL_SIZE, 0.0001)
	assert_between(nm.agent_radius, Tuning.NAV_AGENT_RADIUS, Tuning.NAV_AGENT_RADIUS + nm.cell_size)
	assert_between(nm.agent_height, Tuning.NAV_AGENT_HEIGHT, Tuning.NAV_AGENT_HEIGHT + nm.cell_height)
	map.free()


func test_lighting_is_modest_and_there_is_no_ceiling() -> void:
	for rung: int in [6, 1]:
		var map := CasinoBuilder.build(CasinoLadder.casino(rung), 1)
		assert_eq(map.find_children("*", "WorldEnvironment", true, false).size(), 1)
		var lights: Array[Node] = map.find_children("*", "Light3D", true, false)
		assert_between(lights.size(), 2, 12, "a few lights")
		# Nothing solid above the walls spans the building (the camera sees in from above).
		var plan: Dictionary = CasinoLayouts.plan(CasinoLadder.casino(rung))
		var building := Rect2(plan["x0"], plan["z0"], plan["w"], plan["d"])
		for n: Node in map.nav_region.find_children("*", "StaticBody3D", true, false):
			var body := n as StaticBody3D
			if not building.has_point(Vector2(body.position.x, body.position.z)):
				continue
			for c: Node in body.get_children():
				if c is CollisionShape3D:
					var size: Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
					var top: float = body.position.y + size.y * 0.5
					if top > Tuning.CASINO_WALL_HEIGHT + 0.5:
						assert_lt(size.x * size.z, 4.0, "%s is a big slab above wall height" % body.name)
		var sign_found := false
		for l: Node in map.find_children("*", "Label3D", true, false):
			if (l as Label3D).text == str(CasinoLadder.casino(rung)["name"]).to_upper():
				sign_found = true
		assert_true(sign_found, "neon sign shows the casino name")
		map.free()


func test_navmesh_reaches_everything_on_every_rung() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var map: CasinoMap = await _baked(casino)
		assert_gt(map.nav_polygon_count(), 0, "%s navmesh" % casino["id"])
		_assert_reachable(map, map.back_room_point, "back room")
		_assert_reachable(map, map.back_room_release_point, "release point")
		_assert_reachable(map, map.exit_point, "exit")
		_assert_reachable(map, map.curb_point, "curb")
		_assert_reachable(map, _floor(map.interactables_of(&"cashier")[0].position), "cashier")
		_assert_reachable(map, _floor(map.interactables_of(&"restroom")[0].position), "restroom")
		_assert_reachable(map, _floor(map.interactables_of(&"gift_shop")[0].position), "gift shop")
		for loc: StringName in map.forger_points:
			_assert_reachable(map, map.forger_points[loc], "forger %s" % loc)
		for a: Dictionary in map.table_anchors:
			_assert_reachable(map, (a["transform"] as Transform3D).origin, "table %s" % a["id"])
		for p: Vector3 in map.pit_boss_posts:
			_assert_reachable(map, p, "pit boss post")
		await _free(map)


func test_patrol_and_patron_points_are_on_the_navmesh() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var map: CasinoMap = await _baked(casino)
		var nav: RID = map.navigation_map()
		for route: Variant in map.patrol_routes:
			for p: Vector3 in (route as Array):
				var hit: Vector3 = NavigationServer3D.map_get_closest_point(nav, p)
				assert_lt(hit.distance_to(p), 0.5, "%s patrol point %s off the navmesh (%s)" % [casino["id"], p, hit])
		for p: Vector3 in map.patron_points:
			var hit: Vector3 = NavigationServer3D.map_get_closest_point(nav, p)
			assert_lt(hit.distance_to(p), 0.5, "%s patron point %s off the navmesh (%s)" % [casino["id"], p, hit])
		for p: Vector3 in map.spawn_points:
			assert_lt(NavigationServer3D.map_get_closest_point(nav, p).distance_to(p), 0.5, "spawn on the navmesh")
		await _free(map)


func test_player_zone_follows_nested_zones() -> void:
	var map := CasinoBuilder.build(CasinoLadder.casino(6), 2)
	tree.root.add_child(map)
	var heard: Array = []
	for z: CasinoZone in map.zones:
		z.player_entered.connect(func(p: Node3D, zone: CasinoZone) -> void: heard.append([p, zone.zone_type, zone.area_id]))
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	tree.root.add_child(body)

	var mirror: Vector3 = _floor(map.interactables_of(&"restroom")[0].position)
	var spots: Array = [
		[mirror, HR.ZoneType.RESTROOM, &"restroom"],
		[map.forger_points[&"restroom"], HR.ZoneType.FORGER, &"restroom"],
		[mirror, HR.ZoneType.RESTROOM, &"restroom"],
		[map.spawn_points[0], HR.ZoneType.ENTRANCE, &"entrance"],
		[(map.table_anchors[0]["transform"] as Transform3D).origin, HR.ZoneType.SLOTS, map.table_anchors[0]["area_id"]],
		[map.back_room_release_point, HR.ZoneType.FLOOR, &"floor"],
	]
	for spot: Array in spots:
		body.global_position = spot[0]
		for i in 4:
			await tree.physics_frame
		await tree.process_frame
		var zone: CasinoZone = map.zone_of(body)
		assert_true(zone != null, "in a zone at %s" % spot[0])
		if zone != null:
			assert_eq(zone.zone_type, spot[1], "zone at %s" % spot[0])
			assert_eq(zone.area_id, spot[2], "area at %s" % spot[0])
		assert_false(heard.is_empty(), "player_entered fired")
		if not heard.is_empty():
			assert_eq(heard[-1][0], body)
			assert_eq(heard[-1][1], spot[1], "last announced zone at %s" % spot[0])
	body.queue_free()
	await _free(map)


## Zone-gated interactables can only be reached from inside their zone: a
## player whose sensor finds one is standing where the request works.
func test_zone_gated_interactables_are_only_reachable_from_their_zone() -> void:
	var needs := {&"cashier": HR.ZoneType.CASHIER, &"gift_shop": HR.ZoneType.GIFT_SHOP, &"exit": HR.ZoneType.EXIT}
	for rung in [Tuning.BOTTOM_RUNG, 4, Tuning.TOP_RUNG]:
		var map := CasinoBuilder.build(CasinoLadder.casino(rung), 1)
		for kind: StringName in needs:
			var it: Interactable = map.interactables_of(kind)[0]
			# Farthest a standing player's centre can be (body radius and half a wall off).
			var reach: float = it.get_radius() + Tuning.PLAYER_INTERACT_RADIUS + Tuning.PLAYER_INTERACT_REACH \
				- Tuning.PLAYER_RADIUS - Tuning.CASINO_WALL_THICKNESS * 0.5
			for i in 16:
				var a: float = TAU * float(i) / 16.0
				var p := Vector3(it.position.x + cos(a) * reach, 0.0, it.position.z + sin(a) * reach)
				var z: CasinoZone = map.zone_at(p)
				var ok: bool = z == null or z.zone_type == needs[kind] or z.zone_type == HR.ZoneType.STAFF_ONLY
				assert_true(ok, "rung %d: %s reachable from %s at %s" % [rung, kind, str(HR.ZoneType.find_key(z.zone_type)) if z != null else "-", str(p)])
		map.free()


func test_forger_interactables_follow_the_forger() -> void:
	var map := CasinoBuilder.build(CasinoLadder.casino(3), 2)
	map.set_forger_location(&"loading_dock")
	for it: Interactable in map.interactables_of(&"forger"):
		assert_eq(it.enabled, it.data["location"] == &"loading_dock", "only the dock forger is open")
	map.set_forger_location(&"restroom")
	for it: Interactable in map.interactables_of(&"forger"):
		assert_eq(it.enabled, it.data["location"] == &"restroom")
	map.free()


func test_show_posters_updates_every_board() -> void:
	var map := CasinoBuilder.build(CasinoLadder.casino(4), 2)
	var poster := WantedPoster.new(4, &"neon_oasis", 1, OutfitCatalog.random_outfit(RandomNumberGenerator.new()))
	map.show_posters([poster.to_dict()])
	for b: PosterBoardNode in map.poster_boards:
		assert_eq(b.poster_ids, [4] as Array[int], "board %s" % b.board_id)
	assert_not_null(map.poster_board(&"cashier"))
	map.free()


func test_area_signs_hang_below_the_floor_camera() -> void:
	for row: Dictionary in Tuning.CASINOS:
		var map := CasinoBuilder.build(row, 3)
		var blocks: int = 0
		for z: CasinoZone in map.zones:
			if z.zone_type == HR.ZoneType.TABLES or z.zone_type == HR.ZoneType.SLOTS:
				blocks += 1
		assert_eq(map.area_signs.size(), blocks, "%s: a sign per game area" % row["id"])
		# Default third-person eye height: the pivot plus the arm at the default pitch.
		var eye: float = Tuning.PLAYER_CAMERA_HEIGHT + Tuning.PLAYER_CAMERA_DISTANCE * sin(deg_to_rad(-Tuning.PLAYER_CAMERA_PITCH_DEFAULT_DEGREES))
		for s: Label3D in map.area_signs:
			var top: float = s.position.y + float(s.font_size) * s.pixel_size * 0.5
			assert_lt(top, minf(Tuning.CASINO_WALL_HEIGHT, eye), "%s: %s tops out under the walls and the eye line" % [row["id"], s.text])
			assert_gt(s.position.y - float(s.font_size) * s.pixel_size * 0.5, Tuning.PLAYER_HEIGHT, "above heads")
		map.free()


func test_area_signs_fade_with_distance_and_out_of_the_hud_band() -> void:
	assert_almost_eq(CasinoMap.sign_distance_alpha(0.5), 0.0, 0.001, "too close")
	assert_almost_eq(CasinoMap.sign_distance_alpha(6.0), 1.0, 0.001)
	assert_almost_eq(CasinoMap.sign_distance_alpha(CasinoMap.SIGN_FAR_HIDDEN + 1.0), 0.0, 0.001, "too far")
	assert_gt(CasinoMap.sign_distance_alpha(13.0), 0.0)
	assert_lt(CasinoMap.sign_distance_alpha(13.0), 1.0, "fading")

	var map := CasinoBuilder.build(Tuning.CASINOS[5], 3)
	tree.root.add_child(map)
	var cam := Camera3D.new()
	cam.fov = Tuning.PLAYER_CAMERA_FOV
	tree.root.add_child(cam)
	var s: Label3D = map.area_signs[0]
	# The default third-person view, 6 m short of the sign.
	cam.global_position = Vector3(s.global_position.x, 3.1, s.global_position.z + 6.0)
	cam.rotation = Vector3(deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_DEFAULT_DEGREES), 0.0, 0.0)
	map.fade_signs(cam)
	assert_true(s.visible, "in view below the HUD band")
	assert_gt(s.modulate.a, 0.5)
	# Looking down hard puts the sign up in the top band: it fades away.
	cam.rotation = Vector3(deg_to_rad(-55.0), 0.0, 0.0)
	map.fade_signs(cam)
	var y: float = cam.unproject_position(s.global_position).y / cam.get_viewport().get_visible_rect().size.y
	assert_lt(y, CasinoMap.SIGN_HUD_BAND, "the sign would sit in the top band")
	assert_false(s.visible, "hidden over the HUD")
	# Far away.
	cam.rotation = Vector3(deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_DEFAULT_DEGREES), 0.0, 0.0)
	cam.global_position = Vector3(s.global_position.x, 3.1, s.global_position.z + CasinoMap.SIGN_FAR_HIDDEN + 2.0)
	map.fade_signs(cam)
	assert_false(s.visible, "too far to matter")
	cam.free()
	await _free(map)
