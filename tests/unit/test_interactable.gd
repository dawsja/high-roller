extends TestCase

var _uses: Array = []


func _on_used(user: Node3D, it: Interactable) -> void:
	_uses.append([user, it])


func _poster(id: int, defaced: Array = []) -> Dictionary:
	var look := Outfit.new({"hat": "top_hat", "glasses": "none", "top": "hawaiian_shirt", "bottom": "blue_jeans", "accessory": "gold_chain"})
	var p := WantedPoster.new(id, &"apex", 1, look)
	for slot: int in defaced:
		p.deface(slot)
	return p.to_dict()


func _player_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.8
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	body.add_child(cs)
	return body


func test_interactable_defaults_to_layer_five_sphere() -> void:
	var it := Interactable.new()
	assert_eq(it.collision_layer, 16)
	assert_eq(it.collision_mask, 0)
	assert_true(it.monitorable)
	assert_false(it.monitoring)
	assert_true(it.enabled)
	assert_eq(it.hold_seconds, 0.0)
	assert_true(it.shape.shape is SphereShape3D)
	assert_almost_eq(it.get_radius(), Tuning.INTERACT_RADIUS)
	it.free()


func test_create_fills_the_contract_fields() -> void:
	var it := Interactable.create(&"poster", "Tear it", 0.4, {"poster_id": 3}, 4.0)
	assert_eq(it.kind, &"poster")
	assert_eq(it.prompt, "Tear it")
	assert_eq(it.data, {"poster_id": 3})
	assert_almost_eq(it.hold_seconds, 4.0)
	assert_almost_eq(it.get_radius(), 0.4)
	it.free()


func test_use_emits_used_with_user_and_self() -> void:
	_uses.clear()
	var it := Interactable.create(&"cashier", "Cash out")
	var user := Node3D.new()
	it.used.connect(_on_used)
	it.use(user)
	assert_eq(_uses.size(), 1)
	assert_eq(_uses[0][0], user)
	assert_eq(_uses[0][1], it)
	it.enabled = false
	assert_false(it.monitorable, "a disabled interactable hides from detectors")
	it.use(user)
	assert_eq(_uses.size(), 1, "disabled: no signal")
	it.enabled = true
	it.use(user)
	assert_eq(_uses.size(), 2)
	it.free()
	user.free()


func test_enabled_toggles_monitorable_safely_in_tree() -> void:
	var it := Interactable.create(&"tray", "Knock it over")
	tree.root.add_child(it)
	it.enabled = false
	await tree.process_frame
	assert_false(it.monitorable)
	it.enabled = true
	await tree.process_frame
	assert_true(it.monitorable)
	it.queue_free()
	await tree.process_frame


func test_player_detector_finds_interactables() -> void:
	var it := Interactable.create(&"exit", "Leave")
	it.position = Vector3(50, 1, 50)
	tree.root.add_child(it)
	var sensor := Area3D.new()
	sensor.collision_layer = 0
	sensor.collision_mask = Interactable.LAYER_BIT
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	cs.shape = sphere
	sensor.add_child(cs)
	sensor.position = Vector3(50.5, 1, 50)
	tree.root.add_child(sensor)
	for i in 3:
		await tree.physics_frame
	assert_has(sensor.get_overlapping_areas(), it)
	sensor.queue_free()
	it.queue_free()
	await tree.process_frame


func test_zone_watches_players_only_and_emits_on_entry() -> void:
	var zone := CasinoZone.create(HR.ZoneType.BAR, &"bar")
	zone.add_rect(Rect2(100, 100, 4, 4))
	assert_eq(zone.collision_mask, 2)
	assert_eq(zone.collision_layer, 0)
	assert_eq(zone.zone_type, HR.ZoneType.BAR)
	assert_eq(zone.area_id, &"bar")
	assert_true(zone.contains_point(Vector3(102, 0, 102)))
	assert_false(zone.contains_point(Vector3(99, 0, 102)))
	assert_almost_eq(zone.floor_area(), 16.0)
	var heard: Array = []
	zone.player_entered.connect(func(p: Node3D, z: CasinoZone) -> void: heard.append([p, z]))
	tree.root.add_child(zone)
	var guard := _player_body()
	guard.collision_layer = 4
	guard.position = Vector3(102, 0, 102)
	tree.root.add_child(guard)
	for i in 3:
		await tree.physics_frame
	assert_true(heard.is_empty(), "a guard (layer 3) doesn't count")
	var player := _player_body()
	player.position = Vector3(102, 0, 102)
	tree.root.add_child(player)
	for i in 3:
		await tree.physics_frame
	assert_eq(heard.size(), 1)
	if heard.size() == 1:
		assert_eq(heard[0][0], player)
		assert_eq(heard[0][1], zone)
	guard.queue_free()
	player.queue_free()
	zone.queue_free()
	await tree.process_frame


func test_poster_board_draws_posters_with_interactables() -> void:
	var board := PosterBoardNode.new(&"entrance")
	assert_eq(board.board_id, &"entrance")
	board.show_posters([_poster(2), _poster(5, [HR.OutfitSlot.TOP])])
	assert_eq(board.poster_ids, [5, 2] as Array[int], "newest first")
	assert_eq(board.interactables.size(), 2)
	for it: Interactable in board.interactables:
		assert_eq(it.kind, &"poster")
		assert_almost_eq(it.hold_seconds, Tuning.POSTER_TEAR_SECONDS, 0.001, "hold to tear")
		assert_eq(it.data["board_id"], &"entrance")
	assert_eq(board.interactable_for(5).data["poster_id"], 5)
	assert_null(board.interactable_for(99))
	var defaced: Node = board.find_child("Poster_5", true, false)
	var clean: Node = board.find_child("Poster_2", true, false)
	assert_not_null(defaced)
	assert_not_null(clean)
	assert_eq(defaced.find_children("Scribble_*", "", false, false).size(), 4, "one scribble per defaced slot")
	assert_eq(clean.find_children("Scribble_*", "", false, false).size(), 0)
	# One swatch per worn piece, colored from the catalog; no swatch for "none".
	var top: MeshInstance3D = clean.find_child("Swatch_top", false, false)
	assert_not_null(top)
	var mat := (top.mesh as BoxMesh).material as StandardMaterial3D
	assert_eq(mat.albedo_color, OutfitCatalog.piece_color(&"hawaiian_shirt"))
	assert_null(clean.find_child("Swatch_glasses", false, false), "nothing drawn for no glasses")
	board.free()


func test_poster_board_redraws_and_caps_what_it_shows() -> void:
	var board := PosterBoardNode.new(&"cashier")
	tree.root.add_child(board)
	var many: Array = []
	for i in PosterBoardNode.MAX_SHOWN + 3:
		many.append(_poster(i + 1))
	board.show_posters(many)
	assert_eq(board.interactables.size(), PosterBoardNode.MAX_SHOWN)
	assert_eq(board.poster_ids[0], PosterBoardNode.MAX_SHOWN + 3, "newest shown")
	# One row: every poster can be told apart by floor position.
	for i in range(1, board.interactables.size()):
		assert_gt(absf(board.interactables[i].global_position.x - board.interactables[i - 1].global_position.x), 0.3, "posters side by side")
		assert_almost_eq(board.interactables[i].global_position.y, board.interactables[i - 1].global_position.y, 0.001)
	var old: Interactable = board.interactables[0]
	board.show_posters([])
	assert_eq(board.interactables.size(), 0)
	assert_eq(board.poster_ids.size(), 0)
	await tree.process_frame
	assert_false(is_instance_valid(old), "old poster interactables are freed")
	# JSON round-trip data (floats for ints) still draws.
	var json: Variant = JSON.parse_string(JSON.stringify([_poster(7, [HR.OutfitSlot.HAT])]))
	board.show_posters(json)
	assert_eq(board.poster_ids, [7] as Array[int])
	board.queue_free()
	await tree.process_frame
