extends TestCase
## GameMachine (through TestMachine) against a real offline SimHost: the play
## spot sits / stands the local player, occupant-only presses, requests and
## results, rounds, fire alarm, dealer swap, aim points and MachineFactory.

const RUNG := 3

var _nodes: Array[Node] = []


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			if n.is_inside_tree():
				n.queue_free()
			else:
				n.free()
	_nodes.clear()
	await tree.process_frame


func _host(players: Dictionary = {1: "Ace", 2: "Bo"}) -> SimHost:
	var host := SimHost.new()
	host.paused = true
	_nodes.append(host)
	host.start_run(RUNG, 7, players)
	host.start_visit()
	host.request_register_table(&"t1", HR.GameType.SLOTS, &"a1")
	host.request_register_table(&"t2", HR.GameType.SLOTS, &"a1")
	host.request_register_table(&"hl", HR.GameType.HIGH_LOW, &"a1")
	host.request_register_table(&"bj", HR.GameType.BLACKJACK, &"a1")
	return host


func _machine(host: SimHost, table: StringName = &"t1", game_type: int = HR.GameType.SLOTS,
		at: Vector3 = Vector3.ZERO, local_pid: int = 1) -> GameMachine:
	var m := TestMachine.new()
	m.setup(table, game_type, &"a1", RUNG, host, local_pid)
	m.position = at
	tree.root.add_child(m)
	_nodes.append(m)
	return m


## A stand-in player body on the player layer with a `pid` property.
func _body(pid: int, at: Vector3 = Vector3(0, 0, 8), puppet: bool = false) -> CharacterBody3D:
	var s := GDScript.new()
	s.source_code = "extends CharacterBody3D\nvar pid: int = 0\nvar is_local: bool = true\nvar puppet: bool = false\n"
	s.reload()
	var b: CharacterBody3D = s.new()
	b.set(&"pid", pid)
	b.set(&"puppet", puppet)
	b.set(&"is_local", not puppet)
	b.collision_layer = 2
	b.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	b.add_child(cs)
	b.position = at
	tree.root.add_child(b)
	_nodes.append(b)
	return b


func _physics(frames: int = 4) -> void:
	for i in frames:
		await tree.physics_frame


func _wait_until(cond: Callable, limit: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return bool(cond.call())


func _seat_of(host: SimHost, pid: int) -> StringName:
	return host.sim.player(pid).table_id


func _move(b: Node3D, to: Vector3) -> void:
	b.global_position = to
	await _physics(4)


func test_local_player_sits_on_enter_and_stands_on_exit() -> void:
	var host := _host()
	var m := _machine(host, &"t1", HR.GameType.SLOTS, Vector3(3, 0, -2))
	var changes: Array = []
	m.occupant_changed.connect(func(pid: int) -> void: changes.append(pid))
	var b := _body(1)
	await _physics(2)
	assert_eq(_seat_of(host, 1), &"", "not seated far away")
	await _move(b, m.get_play_transform().origin)
	assert_eq(_seat_of(host, 1), &"t1", "walking into the play spot sits you")
	assert_eq(m.occupants, [1] as Array[int])
	assert_eq(m.occupant, 1)
	assert_eq(changes, [1])
	await _move(b, Vector3(3, 0, 6))
	assert_eq(_seat_of(host, 1), &"", "walking away stands you up")
	assert_true(m.occupants.is_empty())
	assert_eq(changes, [1, 0])


func test_other_peers_bodies_do_not_sit() -> void:
	var host := _host()
	var m := _machine(host)
	var other := _body(2)
	var puppet := _body(1, Vector3(0, 0, 9), true)
	await _move(other, m.get_play_transform().origin)
	await _move(puppet, m.get_play_transform().origin)
	assert_eq(_seat_of(host, 2), &"", "another player's body is theirs to report")
	assert_eq(_seat_of(host, 1), &"", "a puppet copy of the local pid is ignored")


func test_leaving_an_old_spot_after_entering_a_new_one_keeps_you_seated() -> void:
	var host := _host()
	var a := _machine(host, &"t1")
	var b2 := _machine(host, &"t2", HR.GameType.SLOTS, Vector3(4, 0, 0))
	var body := _body(1, Vector3(50, 0, 50))
	await _physics(2)
	a._on_zone_entered(body)
	assert_eq(_seat_of(host, 1), &"t1")
	b2._on_zone_entered(body)
	assert_eq(_seat_of(host, 1), &"t2")
	a._on_zone_exited(body)
	assert_eq(_seat_of(host, 1), &"t2", "still at the newer machine")
	b2._on_zone_exited(body)
	assert_eq(_seat_of(host, 1), &"")


func test_only_the_occupant_can_play() -> void:
	var host := _host()
	var m := _machine(host)
	var bets: Array = []
	host.sim_event.connect(func(k: StringName, d: Dictionary) -> void:
		if k == &"bet":
			bets.append(d))
	assert_true(m.press_by_id(&"main", 1))
	assert_eq(m.console.message_line(), "Step up to play")
	host.request_sit(2, &"t1")
	assert_eq(m.occupants, [2] as Array[int], "occupants follow seated events for every pid")
	var pocket1 := host.sim.player(1).wallet.pocket
	m.press_by_id(&"main", 1)
	assert_eq(m.console.message_line(), "Occupied")
	assert_true(bets.is_empty())
	assert_eq(host.sim.player(1).wallet.pocket, pocket1)
	m.press_by_id(&"5", 1)
	assert_ne(m.console.bet, 5, "a non-occupant can't type a bet either")
	var shown: Array = []
	m.result_shown.connect(func(id: StringName) -> void: shown.append(id))
	m.press_by_id(&"main", 2)
	assert_eq(bets.size(), 1, "the occupant's press places a bet")
	assert_eq(int(bets[0]["pid"]), 2)
	var ok := await _wait_until(func() -> bool: return not shown.is_empty())
	assert_true(ok)
	assert_eq(shown, [&"t1"])


func test_occupied_spot_does_not_sit_the_local_player() -> void:
	var host := _host()
	var m := _machine(host)
	host.request_sit(2, &"t1")
	var b := _body(1)
	await _move(b, m.get_play_transform().origin)
	assert_eq(_seat_of(host, 1), &"", "one player per play spot")
	assert_eq(m.console.message_line(), "Occupied")


func test_bet_locks_the_console_until_the_result_is_shown() -> void:
	var host := _host()
	var m := _machine(host)
	var b := _body(1)
	await _move(b, m.get_play_transform().origin)
	assert_true(m.is_occupied_by(1))
	await _wait_until(func() -> bool: return m.console.min_bet > 0, 1.0)
	var snap := host.snapshot()
	assert_eq(m.console.min_bet, int(snap["run"]["min_bet"]), "limits from the snapshot")
	assert_eq(m.console.max_bet, int(snap["run"]["max_bet"]))
	assert_eq(m.console.pocket, host.sim.player(1).wallet.pocket)
	var shown: Array = []
	m.result_shown.connect(func(id: StringName) -> void: shown.append(id))
	m.press_by_id(&"min", 1)
	var shown_pocket := m.console.pocket
	m.press_by_id(&"main", 1)
	assert_true(m.console.is_locked(), "locked while the result animates")
	assert_eq(m.console.pocket, shown_pocket, "the pocket on the screen doesn't spoil the result")
	assert_true(m.is_animating())
	var bet_before := m.console.bet
	m.press_by_id(&"max", 1)
	assert_eq(m.console.bet, bet_before, "presses are ignored while locked")
	var ok := await _wait_until(func() -> bool: return not shown.is_empty())
	assert_true(ok)
	assert_false(m.console.is_locked(), "unlocked after result_shown")
	assert_eq(m.console.pocket, host.sim.player(1).wallet.pocket, "pocket follows the bet")
	assert_ne(m.console.get_message(), "")


func test_refused_request_unlocks_with_a_reason() -> void:
	var host := _host()
	var m := _machine(host)
	host.request_sit(1, &"t1")
	var reasons: Array = []
	host.request_done.connect(func(req: StringName, _a: Array, res: Dictionary) -> void:
		if req == &"place_bet":
			reasons.append(StringName(str(res.get("reason", "")))))
	m.request_bet(1, 0, {})
	assert_eq(reasons.size(), 1)
	assert_false(m.console.is_locked())
	assert_false(m.is_waiting())
	assert_eq(m.console.message_line(), DiegeticKit.reason_text(reasons[0]))


func test_high_low_round_through_action_keys() -> void:
	var host := _host()
	var m := _machine(host, &"hl", HR.GameType.HIGH_LOW)
	for id: StringName in [GameMachine.ACTION_HIGHER, GameMachine.ACTION_LOWER, GameMachine.ACTION_CASH_OUT]:
		assert_not_null(m.console.get_key(id), String(id))
	host.request_sit(1, &"hl")
	m.press_by_id(&"main", 1)
	assert_true(m.in_round(1), "PLAY starts a run")
	assert_eq(StringName(str(m.round_state(1).get("kind", ""))), &"high_low")
	assert_true(m.console.message_line().begins_with("Card"))
	var shown: Array = []
	m.result_shown.connect(func(id: StringName) -> void: shown.append(id))
	m.press_by_id(GameMachine.ACTION_HIGHER, 1)
	var ok := await _wait_until(func() -> bool: return not shown.is_empty())
	assert_true(ok)
	if m.in_round(1):
		m.press_by_id(GameMachine.ACTION_CASH_OUT, 1)
		ok = await _wait_until(func() -> bool: return shown.size() >= 2)
		assert_true(ok)
	assert_false(m.in_round(1), "the run is over")
	assert_null(host.sim.player(1).high_low)


func test_blackjack_deal_and_stand() -> void:
	var host := _host()
	var m := _machine(host, &"bj", HR.GameType.BLACKJACK)
	assert_eq(m.console.main_key.legend, "DEAL")
	host.request_sit(1, &"bj")
	m.press_by_id(&"main", 1)
	assert_true(m.in_round(1))
	var shown: Array = []
	m.result_shown.connect(func(id: StringName) -> void: shown.append(id))
	m.press_by_id(GameMachine.ACTION_STAND, 1)
	var ok := await _wait_until(func() -> bool: return not shown.is_empty())
	assert_true(ok)
	assert_false(m.in_round(1))
	assert_null(host.sim.player(1).blackjack)


func test_fire_alarm_closes_the_machine() -> void:
	var host := _host()
	var m := _machine(host)
	host.request_sit(1, &"t1")
	assert_false(m.closed)
	var r := host.request_distraction(1, HR.Distraction.FIRE_ALARM)
	assert_true(bool(r["ok"]), str(r))
	assert_true(m.closed, "the alarm closes it")
	assert_true(m.console.is_locked())
	assert_true(m._closed_sign.visible)
	assert_eq(m.console.message_line(), "CLOSED")
	assert_true(m.occupants.is_empty(), "everyone stood up")
	m.press_by_id(&"main", 1)
	assert_false(m.is_waiting())
	var b := _body(1)
	await _move(b, m.get_play_transform().origin)
	assert_eq(_seat_of(host, 1), &"", "no sitting while closed")
	host.sim.tick(Tuning.FIRE_ALARM_SECONDS + 1.0)
	assert_false(m.closed, "reopens when the alarm ends")
	assert_false(m.console.is_locked())
	assert_false(m._closed_sign.visible)


func test_machine_built_during_an_alarm_starts_closed() -> void:
	var host := _host()
	host.request_distraction(1, HR.Distraction.FIRE_ALARM)
	var m := _machine(host)
	assert_true(m.closed)


func test_dealer_swap_cue() -> void:
	var host := _host()
	var m := _machine(host)
	host.sim_event.emit(&"dealer_swap", {"pid": 1, "table_id": &"t1"})
	assert_eq(m.get_pop_text(), "COOLED", "no dealer: a cold flash")
	var first := m.spawn_dealer(Vector3(0, 0, -0.9), 0.0)
	assert_true(m.dealer == first)
	host.sim_event.emit(&"dealer_swap", {"pid": 1, "table_id": &"t1"})
	assert_ne(m.dealer, first, "a new dealer walks in")
	assert_eq(m.get_pop_text(), "NEW DEALER")
	host.sim_event.emit(&"dealer_swap", {"pid": 1, "table_id": &"t2"})
	assert_eq(m.get_pop_text(), "NEW DEALER", "other tables' swaps are ignored")


func test_play_transform_and_aim_points() -> void:
	var host := _host()
	var m := _machine(host, &"t1", HR.GameType.SLOTS, Vector3(5, 0, 2))
	m.rotation.y = PI * 0.5
	await tree.process_frame
	var xf := m.get_play_transform()
	assert_true(xf.origin.is_equal_approx(m.to_global(m.play_spot)))
	var to_machine := (m.global_position - xf.origin)
	to_machine.y = 0.0
	assert_gt((-xf.basis.z).dot(to_machine.normalized()), 0.9, "faces the machine")
	var main_pt := m.get_aim_point(&"main")
	assert_true(main_pt.is_equal_approx(m.console.main_key.aim_point()))
	assert_lt(xf.origin.distance_to(main_pt), 1.6, "keys are in reach from the play spot")
	assert_false(m.press_by_id(&"nope", 1))
	var lever := Lever3D.new()
	lever.setup()
	m.visuals.add_child(lever)
	m.register_pressable(&"lever", lever)
	assert_true(m.get_pressable(&"lever") == lever)
	host.request_sit(1, &"t1")
	assert_true(m.press_by_id(&"lever", 1))
	assert_eq(lever.pull_count, 1)


func test_seated_elsewhere_leaves_occupants() -> void:
	var host := _host()
	var m := _machine(host)
	host.request_sit(2, &"t1")
	assert_eq(m.occupant, 2)
	host.request_sit(2, &"t2")
	assert_eq(m.occupant, 0)


func test_factory_maps_types_to_scripts() -> void:
	assert_eq(MachineFactory.script_path(HR.GameType.SLOTS), "res://scripts/world/machines/slots_machine.gd")
	assert_eq(MachineFactory.script_path(HR.GameType.HIGH_LOW), "res://scripts/world/machines/high_low_machine.gd")
	assert_eq(MachineFactory.script_path(HR.GameType.BIG_WHEEL), "res://scripts/world/machines/big_wheel_machine.gd")
	assert_eq(MachineFactory.script_path(-42), "")
	var fallback := MachineFactory.create(-42)
	assert_true(fallback is TestMachine)
	fallback.free()
	for t: int in HR.GameType.values():
		var m := MachineFactory.create(t)
		assert_true(m is GameMachine, "type %d" % t)
		if not MachineFactory.has_machine(t):
			assert_true(m is TestMachine)
		m.free()
	var host := _host()
	var built := MachineFactory.build(HR.GameType.SLOTS, &"t1", &"a1", RUNG, host, 1)
	_nodes.append(built)
	assert_eq(built.table_id, &"t1")
	assert_eq(built.display_name, TableGames.display_name(HR.GameType.SLOTS, RUNG))


func test_real_player_sits_aims_at_keys_and_presses_them() -> void:
	InputSetup.ensure_actions()
	var host := _host()
	var floor := Primitives.static_box(Vector3(20, 1, 20), Color.DIM_GRAY)
	floor.position = Vector3(0, -0.5, 0)
	tree.root.add_child(floor)
	_nodes.append(floor)
	var m := _machine(host, &"t1", HR.GameType.SLOTS, Vector3(0, 0, -1))
	var bets: Array = []
	host.sim_event.connect(func(k: StringName, d: Dictionary) -> void:
		if k == &"bet":
			bets.append(d))
	var player := PlayerCharacter.new()
	player.setup(1, true, null)
	player.position = m.get_play_transform().origin + Vector3(0, 0.05, 0)
	tree.root.add_child(player)
	_nodes.append(player)
	await _physics(12)
	assert_eq(_seat_of(host, 1), &"t1", "the real player body sits on entering the play spot")
	player.camera_rig.look_toward(m.get_aim_point(&"7"))
	await _physics(3)
	assert_true(player.current_target() == m.console.get_key(&"7"), "the look ray finds keypad keys")
	assert_eq(player.current_hint(), "[LMB] 7")
	assert_true(m.console.get_key(&"7").hovered, "and hovers them")
	player.camera_rig.look_toward(m.get_aim_point(&"main"))
	await _physics(3)
	assert_true(player.current_target() == m.console.main_key, "and the main key")
	assert_false(m.console.get_key(&"7").hovered)
	Input.action_press(&"primary")
	await _physics(2)
	Input.action_release(&"primary")
	await _physics(2)
	assert_eq(bets.size(), 1, "LMB on SPIN places a bet")
	assert_eq(int(bets[0]["pid"]), 1)


func test_a_passing_sit_refusal_is_retried_while_in_the_spot() -> void:
	var host := _host()
	var m := _machine(host)
	var b := _body(1)
	await _move(b, m.get_play_transform().origin)
	assert_eq(_seat_of(host, 1), &"t1")
	host.request_stand(1)
	assert_eq(_seat_of(host, 1), &"", "stood up by the sim, still in the spot")
	# A co-op host said "too far" (its copy of the body lagged): try again soon.
	host.request_done.emit(&"sit", [1, &"t1", false], {"ok": false, "reason": &"too_far"})
	assert_ne(m.console.message_line(), DiegeticKit.reason_text(&"too_far"), "no message for a passing refusal")
	var ok := await _wait_until(func() -> bool: return _seat_of(host, 1) == &"t1", 3.0)
	assert_true(ok, "sat again on the retry")
	host.request_stand(1)
	host.request_done.emit(&"sit", [1, &"t1", false], {"ok": false, "reason": &"staff_uniform"})
	assert_eq(m.console.message_line(), DiegeticKit.reason_text(&"staff_uniform"))
	await _physics(70)
	assert_eq(_seat_of(host, 1), &"", "a real refusal is not retried")
