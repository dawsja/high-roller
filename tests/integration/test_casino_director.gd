extends TestCase
## CasinoDirector end to end: building visits, the table path, the ID check,
## noises, and a grab -> back room -> three strikes -> next visit run.

var _host: SimHost
var _nodes: Array[Node] = []
var _ticks: int = 60
var _time_scale: float = 1.0
var _finished: Array[StringName] = []


func before_each() -> void:
	_ticks = Engine.physics_ticks_per_second
	_time_scale = Engine.time_scale
	_finished = []
	InputSetup.ensure_actions()


func after_each() -> void:
	Engine.physics_ticks_per_second = _ticks
	Engine.time_scale = _time_scale
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_host = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tree.process_frame
	await tree.physics_frame


# --- Helpers ------------------------------------------------------------------

## Four times the simulation speed with the same physics step (1/60 s).
func _fast() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0


func _start(rung: int, practice: bool, ui: Dictionary = {}) -> CasinoDirector:
	_host = SimHost.new()
	_host.name = "TestSimHost"
	tree.root.add_child(_host)
	_nodes.append(_host)
	_host.start_run(rung, 4242, {1: "Tester"})
	_host.start_visit()
	return _new_director(practice, ui)


func _new_director(practice: bool, ui: Dictionary = {}) -> CasinoDirector:
	var d := CasinoDirector.new()
	tree.root.add_child(d)
	_nodes.append(d)
	d.setup(_host, _host.run.rung, practice, ui)
	d.visit_finished.connect(func(outcome: StringName) -> void: _finished.append(outcome))
	return d


func _drop(d: CasinoDirector) -> void:
	if is_instance_valid(d):
		d.get_parent().remove_child(d)
		d.queue_free()
	_nodes.erase(d)


func _add(node: Node) -> Node:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Waits (physics frames) until cond.call() is true; returns whether it was.
func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.physics_frame
	return bool(cond.call())


func _activate(d: CasinoDirector) -> bool:
	return await _until(func() -> bool: return d.npcs_active, 400)


func _ps() -> PlayerState:
	return _host.current_sim().player(1)


func _guards_of(d: CasinoDirector, kind: int) -> Array[GuardNPC]:
	var out: Array[GuardNPC] = []
	for g: GuardNPC in d.guards:
		if g.security_type == kind:
			out.append(g)
	return out


## A table the player can bet on with one request (slots, wheel, dice, roulette).
func _single_shot_table(d: CasinoDirector) -> TableNode:
	for kind: int in [HR.GameType.ROULETTE, HR.GameType.SLOTS, HR.GameType.BIG_WHEEL, HR.GameType.DICE]:
		for t: TableNode in d.tables.values():
			if t.game_type == kind:
				return t
	return null


## Puts the guard on the open aisle by the security door, facing south, and
## the player `gap` metres in front of it.
func _face_off(d: CasinoDirector, g: GuardNPC, gap: float) -> void:
	var spot: Vector3 = d.map.to_global(d.map.back_room_release_point)
	g.global_position = spot
	g.velocity = Vector3.ZERO
	g.face_toward(spot + Vector3(0, 0, 3))
	d.player.teleport(spot + g.front_direction() * gap)


# --- Tests --------------------------------------------------------------------

func test_security_plan_matches_every_casino() -> void:
	for row: Dictionary in Tuning.CASINOS:
		var p: Dictionary = CasinoDirector.security_plan(row, false, 4, 6)
		var kinds: Array = row["security"]
		assert_eq(int(p["floor"]) + int(p["undercover"]) + int(p["head"]), int(row["guards"]), "walking guards at %s" % row["id"])
		assert_eq(int(p["cameras"]) > 0, kinds.has(HR.SecurityType.CAMERA), "cameras at %s" % row["id"])
		assert_eq(int(p["pit_boss"]), Tuning.DIRECTOR_MAX_PIT_BOSSES if kinds.has(HR.SecurityType.PIT_BOSS) else 0, "pit bosses at %s" % row["id"])
		assert_eq(int(p["undercover"]), 1 if kinds.has(HR.SecurityType.UNDERCOVER) else 0)
		assert_eq(int(p["head"]), 1 if kinds.has(HR.SecurityType.HEAD_OF_SECURITY) else 0)
	var practice: Dictionary = CasinoDirector.security_plan(Tuning.CASINOS[0], true, 4, 6)
	assert_eq(practice, {"floor": 1, "undercover": 0, "head": 0, "pit_boss": 0, "cameras": 0})


func test_builds_practice_sals() -> void:
	var d := _start(Tuning.BOTTOM_RUNG, true)
	var sim := _host.current_sim()
	assert_eq(d.casino["id"], &"sals_back_room")
	assert_eq(d.guards.size(), 1, "practice: one guard")
	assert_eq(d.guards[0].security_type, HR.SecurityType.FLOOR_GUARD)
	assert_eq(d.cameras.size(), 0)
	assert_gt(d.tables.size(), 0)
	assert_eq(d.tables.size(), d.map.table_anchors.size(), "a TableNode per anchor")
	assert_eq(sim.tables.size(), d.map.table_anchors.size(), "every table registered with the sim")
	for t: TableNode in d.tables.values():
		assert_eq(t.get_parent(), d.map.props_root, "tables are carved out of the navmesh")
	assert_not_null(d.player)
	assert_eq(d.player.pid, 1)
	assert_not_null(d.player.camera_rig, "the local player has the camera")
	assert_lt(d.player.global_position.distance_to(d.map.to_global(d.map.spawn_points[0])), 0.5)
	assert_eq(d.crowd.patron_count(), int(Tuning.DIRECTOR_PATRONS[d.map.size_class]))
	var forger_at: Vector3 = d.map.to_global(d.map.forger_points[sim.forger.location()])
	assert_lt(d.forger_npc.global_position.distance_to(forger_at), 0.01, "forger at the sim's spot")
	assert_eq(d.forger_interactable.kind, &"forger")
	assert_false(d.npcs_active, "NPCs wait for the navmesh")
	assert_true(await _activate(d), "NPCs start once the navmesh syncs")
	await _frames(5)
	assert_true(d.guards[0].nav_agent.get_navigation_map().is_valid())


func test_builds_the_apex_with_every_security_type() -> void:
	var d := _start(Tuning.TOP_RUNG, false)
	var row: Dictionary = Tuning.CASINOS[0]
	var floor_guards := _guards_of(d, HR.SecurityType.FLOOR_GUARD).size()
	var undercover := _guards_of(d, HR.SecurityType.UNDERCOVER).size()
	var head := _guards_of(d, HR.SecurityType.HEAD_OF_SECURITY).size()
	var bosses := _guards_of(d, HR.SecurityType.PIT_BOSS).size()
	assert_eq(floor_guards + undercover + head, int(row["guards"]), "walking guards = casino guards")
	assert_eq(undercover, 1)
	assert_eq(head, 1)
	assert_eq(bosses, mini(Tuning.DIRECTOR_MAX_PIT_BOSSES, d.map.pit_boss_posts.size()))
	assert_gt(bosses, 0)
	assert_eq(d.cameras.size(), d.map.camera_mounts.size())
	assert_gt(d.cameras.size(), 0)
	assert_eq(d.tables.size(), d.map.table_anchors.size())
	assert_eq(_host.current_sim().tables.size(), d.map.table_anchors.size())
	var ids: Dictionary = {}
	for g: GuardNPC in d.guards:
		ids[g.guard_id] = true
	assert_eq(ids.size(), d.guards.size(), "unique guard ids")
	for it: Interactable in d.map.interactables_of(&"exit"):
		assert_true(it.prompt.contains("end the run"))


func test_sit_and_bet_through_the_table_interactable() -> void:
	var panel: BetPanel = _add(BetPanel.new())
	var d := _start(Tuning.BOTTOM_RUNG, true, {"bet_panel": panel})
	panel.setup(_host, 1)
	var t := _single_shot_table(d)
	assert_not_null(t)
	d.player.teleport(Vector3(t.interactable.global_position.x, 0.0, t.interactable.global_position.z))
	assert_true(await _until(func() -> bool: return d.player.current_interactable() == t.interactable, 30), "the player's sensor finds the table")
	d.player.interact_pressed.emit(d.player.current_interactable())
	assert_eq(_ps().status, HR.PlayerStatus.SEATED)
	assert_eq(_ps().table_id, t.table_id)
	assert_eq(d.player.state, PlayerCharacter.STATE_SEATED)
	assert_lt(d.player.global_position.distance_to(t.seat_transform().origin), 0.01, "on the stool")
	assert_true(panel.is_open())
	assert_eq(panel.table_id, t.table_id)
	await _frames(2)
	assert_false(d.player.is_input_enabled(), "the bet panel takes the input")

	var before := _ps().wallet.pocket
	panel.press_main()
	assert_ne(_ps().wallet.pocket, before, "a bet changes the pocket")
	assert_true(t.is_animating(), "the table plays the result")

	panel.request_leave()
	assert_eq(_ps().status, HR.PlayerStatus.FREE)
	assert_eq(d.player.state, PlayerCharacter.STATE_FREE)
	assert_false(panel.is_open())
	await _frames(2)
	assert_true(d.player.is_input_enabled())


func test_suspected_player_passes_an_id_check() -> void:
	_fast()
	var quiz: IdQuizPanel = _add(IdQuizPanel.new())
	var d := _start(Tuning.BOTTOM_RUNG, true, {"quiz_panel": quiz})
	quiz.setup(_host, 1)
	assert_true(await _activate(d))
	var g: GuardNPC = d.guards[0]
	_ps().heat.raise_to(Tuning.SUSPECTED_AT + 5.0, &"test")
	_face_off(d, g, 1.5)
	assert_true(await _until(func() -> bool: return _ps().status == HR.PlayerStatus.ID_CHECK, 240), "the guard asks for ID")
	assert_true(quiz.is_waiting(), "the quiz is up")
	await _frames(2)
	assert_false(d.player.is_input_enabled(), "no walking off mid-quiz")
	var correct: int = int(_ps().id_question["correct_index"])
	quiz.answer(correct)
	assert_eq(_ps().status, HR.PlayerStatus.FREE)
	assert_true(await _until(func() -> bool: return g.get_state() != HR.GuardState.CHECK_ID, 30), "the guard got the result")
	assert_ne(g.get_state(), HR.GuardState.CHASE)
	await _frames(2)
	assert_true(d.player.is_input_enabled())


func test_knocking_over_a_tray_draws_a_guard() -> void:
	_fast()
	var d := _start(Tuning.BOTTOM_RUNG, true)
	assert_true(await _activate(d))
	var trays := d.map.interactables_of(&"tray")
	assert_false(trays.is_empty())
	var tray: Interactable = trays[0]
	var g: GuardNPC = d.guards[0]
	var at := Vector3(tray.global_position.x, 0.0, tray.global_position.z)
	g.global_position = at + Vector3(4.0, 0.0, 0.0)
	d.player.teleport(at + Vector3(0.0, 0.0, 0.8))
	await _frames(3)
	d.interact(1, tray)
	assert_false(tray.enabled, "a knocked tray can't be knocked again")
	assert_gt(_ps().heat.value, 0.0, "knocking it over costs Heat")
	assert_true(await _until(func() -> bool: return g.get_state() == HR.GuardState.INVESTIGATE, 20), "the guard heard it")


func test_grab_carry_strikes_and_the_next_visit() -> void:
	_fast()
	var d := _start(5, false)
	assert_eq(d.guards.size(), 2)
	assert_true(await _activate(d))
	var sim := _host.current_sim()
	_ps().heat.raise_to(Tuning.WANTED_AT + 10.0, &"test")
	assert_eq(sim.posters_here().size(), 1, "going Wanted prints a poster")
	assert_eq(d.map.poster_boards[0].poster_ids.size(), 1, "and it goes up on the board")
	var poster_id: int = d.map.poster_boards[0].poster_ids[0]

	var g: GuardNPC = d.guards[0]
	_face_off(d, g, 1.0)
	assert_true(await _until(func() -> bool: return _ps().status == HR.PlayerStatus.CARRIED, 240), "the guard grabs a Wanted player")
	assert_true(d.player.is_carried())
	assert_eq(g.carrying_pid(), 1)
	assert_true(await _until(func() -> bool: return _ps().status == HR.PlayerStatus.DETAINED, 2400), "carried to the back room")
	assert_eq(_host.run.strikes, 1, "a strike")
	assert_eq(_ps().wallet.pocket, 0, "pocket chips lost")
	assert_true(d.player.is_hidden())
	var back: Vector3 = d.map.to_global(d.map.back_room_point)
	assert_lt(Vector2(d.player.global_position.x - back.x, d.player.global_position.z - back.z).length(), 0.1, "held in the back room")

	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_eq(_ps().status, HR.PlayerStatus.FREE, "rejoined")
	assert_false(d.player.is_hidden())
	var release: Vector3 = d.map.to_global(d.map.back_room_release_point)
	assert_lt(d.player.global_position.distance_to(release), 0.5)

	for strike in [2, 3]:
		assert_true(bool(_host.request_caught(1)["ok"]))
		assert_true(bool(_host.request_reach_back_room(1)["ok"]))
		assert_eq(_host.run.strikes if strike < 3 else Tuning.STRIKES_TO_THROW_OUT, strike)
		if strike < 3:
			sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_true(d.finished)
	assert_true(await _until(func() -> bool: return not _finished.is_empty(), int(Tuning.DIRECTOR_VISIT_END_SECONDS * 60.0) + 30))
	assert_eq(_finished, [&"thrown_out"] as Array[StringName], "visit_finished once")
	assert_eq(_host.run.rung, 6, "dropped a rung")

	_drop(d)
	_host.start_visit()
	var d2 := _new_director(false)
	assert_eq(d2.casino["id"], &"sals_back_room")
	assert_eq(d2.map.poster_boards[0].poster_ids.size(), 0, "Sal's has no poster of us")
	assert_eq(_host.run.posters.posters_in(&"rusty_spur").size(), 1)

	# Climb back up: the Rusty Spur still has our poster on the wall.
	_drop(d2)
	_host.run.add_bank(CasinoLadder.buy_in_to_leave(6))
	_host.run.climb()
	_host.start_visit()
	var d3 := _new_director(false)
	assert_eq(d3.casino["id"], &"rusty_spur")
	for board: PosterBoardNode in d3.map.poster_boards:
		assert_eq(board.poster_ids, [poster_id] as Array[int], "poster still up on %s" % board.board_id)


func test_sitting_puts_the_player_in_the_table_area() -> void:
	var d := _start(Tuning.BOTTOM_RUNG, true)
	var t := _single_shot_table(d)
	var ps := _ps()
	ps.last_game_area = &"somewhere_else"
	ps.seconds_since_area_change = INF
	ps.heat.raise_to(20.0, &"test")
	d.player.teleport(Vector3(t.interactable.global_position.x, 0.0, t.interactable.global_position.z))
	assert_true(await _until(func() -> bool: return d.player.current_interactable() == t.interactable, 30))
	d.player.interact_pressed.emit(t.interactable)
	assert_eq(ps.status, HR.PlayerStatus.SEATED)
	assert_eq(ps.zone, HR.ZoneType.TABLES, "seated in the table's game area")
	assert_eq(ps.area_id, t.area_id)
	assert_almost_eq(ps.heat.value, 20.0 + Tuning.AREA_CHANGE_HEAT, 0.01, "the area change cools on arrival, not on leaving")
	_host.request_stand(1)
	await _frames(3)
	assert_almost_eq(ps.heat.value, 20.0 + Tuning.AREA_CHANGE_HEAT, 0.05, "standing up gives no second cool-off")


func test_forger_is_only_reachable_from_his_corner() -> void:
	var d := _start(4, true)
	var it := d.forger_interactable
	var reach: float = it.get_radius() + Tuning.PLAYER_INTERACT_RADIUS + Tuning.PLAYER_INTERACT_REACH \
		- Tuning.PLAYER_RADIUS - Tuning.CASINO_WALL_THICKNESS * 0.5
	for loc: StringName in d.map.forger_points:
		var at: Vector3 = d.map.forger_points[loc]
		for i in 16:
			var a: float = TAU * float(i) / 16.0
			var z: CasinoZone = d.map.zone_at(at + Vector3(cos(a), 0.0, sin(a)) * reach)
			assert_true(z == null or (z.zone_type == HR.ZoneType.FORGER and z.area_id == loc) or z.zone_type == HR.ZoneType.STAFF_ONLY,
				"%s: forger reachable from %s" % [loc, str(HR.ZoneType.find_key(z.zone_type)) if z != null else "-"])
