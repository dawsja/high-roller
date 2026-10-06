extends TestCase
## SimHost: run/visit lifecycle, event forwarding, request pass-through and ticking.

var host_events: Array = []
var sim_events: Array = []


func before_each() -> void:
	host_events.clear()
	sim_events.clear()


func _host(rung: int = Tuning.TOP_RUNG, crew: Dictionary = {1: "Ace"}) -> SimHost:
	var host := SimHost.new()
	host.sim_event.connect(func(k: StringName, d: Dictionary) -> void: host_events.append([k, d]))
	host.start_run(rung, 42, crew)
	return host


func test_start_run_and_visit() -> void:
	var host := _host(3, {1: "Ace", 2: "Deuce"})
	assert_not_null(host.run)
	assert_eq(host.run.rung, 3)
	assert_null(host.current_sim(), "no visit until start_visit")
	var started: Array = []
	host.visit_started.connect(func(s: FloorSim) -> void: started.append(s))
	var sim := host.start_visit()
	assert_not_null(sim)
	assert_true(host.current_sim() == sim)
	assert_true(host.sim == sim)
	assert_true(sim.run == host.run)
	assert_eq(started.size(), 1)
	assert_eq(sim.player(1).display_name, "Ace")
	assert_eq(sim.player(2).display_name, "Deuce")
	assert_true(sim.tables.is_empty(), "the director registers tables")
	assert_eq(host_events.filter(func(e: Array) -> bool: return e[0] == &"player_joined").size(), 2)
	host.free()


func test_start_visit_without_run_starts_a_default_one() -> void:
	var host := SimHost.new()
	var sim := host.start_visit()
	assert_not_null(sim)
	assert_eq(host.run.rung, Tuning.TOP_RUNG)
	assert_eq(sim.player_ids(), [1] as Array[int])
	host.free()


func test_requests_without_a_visit() -> void:
	var host := SimHost.new()
	var r := host.request_sit(1, &"t")
	assert_eq(r, {"ok": false, "reason": SimHost.NO_SIM})
	assert_eq(host.request_try_climb()["reason"], SimHost.NO_SIM)
	assert_null(host.request_start_high_low(1, &"t", 10))
	assert_null(host.request_start_blackjack(1, &"t", 10))
	assert_null(host.request_register_table(&"t", HR.GameType.SLOTS, &"a"))
	assert_eq(host.snapshot(), {})
	host.start_run(2, 1, {1: "A"})
	assert_eq(host.snapshot()["run"]["rung"], 2)
	host.free()


func test_every_floor_sim_request_has_a_matching_host_method() -> void:
	var host := SimHost.new()
	var sim := FloorSim.new(RunState.new(), 1)
	var host_methods := _methods(host)
	var sim_methods := _methods(sim)
	for name: StringName in SimHost.REQUESTS:
		var request := "request_%s" % name
		assert_true(sim_methods.has(String(name)), "FloorSim.%s" % name)
		assert_true(host_methods.has(request), "SimHost.%s" % request)
		if sim_methods.has(String(name)) and host_methods.has(request):
			var a: Dictionary = sim_methods[String(name)]
			var b: Dictionary = host_methods[request]
			assert_eq(b["args"].size(), a["args"].size(), "%s arg count" % name)
			assert_eq(b["default_args"].size(), a["default_args"].size(), "%s default args" % name)
			for i in a["args"].size():
				assert_eq(b["args"][i]["type"], a["args"][i]["type"], "%s arg %d type" % [name, i])
			assert_eq(b["return"]["type"], a["return"]["type"], "%s return type" % name)
	# Every public FloorSim request is listed (setup, tick and queries aren't requests).
	var not_requests := ["add_player", "tick", "player", "player_ids", "table", "casino", "score", "snapshot", "fire_alarm_active", "matches_poster", "posters_here"]
	for m: String in sim_methods:
		if m.begins_with("_") or not_requests.has(m):
			continue
		assert_has(SimHost.REQUESTS, StringName(m), "FloorSim.%s missing from SimHost.REQUESTS" % m)
	host.free()


func _methods(obj: Object) -> Dictionary:
	var out: Dictionary = {}
	var script: Script = obj.get_script()
	for m: Dictionary in script.get_script_method_list():
		out[m["name"]] = m
	return out


func test_requests_pass_through_and_events_are_reemitted() -> void:
	var host := _host(Tuning.TOP_RUNG, {1: "Ace", 2: "Deuce"})
	var sim := host.start_visit()
	sim.event.connect(func(k: StringName, d: Dictionary) -> void: sim_events.append([k, d]))
	host_events.clear()
	var t := host.request_register_table(&"wheel", HR.GameType.BIG_WHEEL, &"a", Vector3(1, 0, 1))
	assert_true(sim.table(&"wheel") == t)
	assert_true(host.request_sit(1, &"wheel")["ok"])
	var bet := host.request_place_bet(1, &"wheel", int(sim.casino()["min_bet"]))
	assert_true(bet["ok"])
	assert_eq(bet["pocket"], sim.player(1).wallet.pocket)
	assert_true(host.request_give_chips(1, 2, 10)["ok"])
	assert_true(host.request_distraction(2, HR.Distraction.KNOCK_OVER, Vector3.ONE)["ok"])
	assert_eq(host.request_enter_zone(2, HR.ZoneType.CASHIER, &"cage")["ok"], true)
	assert_true(host.request_cash_out(2, 100)["ok"])
	assert_eq(host.request_freed(1)["reason"], FloorSim.NOT_CARRIED)
	assert_gt(sim_events.size(), 5)
	assert_eq(host_events, sim_events, "every sim event re-emitted, in order")
	assert_eq(host.snapshot(), sim.snapshot())
	host.free()


func test_multi_step_rounds_through_the_host() -> void:
	var host := _host()
	var sim := host.start_visit()
	host.request_register_table(&"hl", HR.GameType.HIGH_LOW, &"a")
	host.request_register_table(&"bj", HR.GameType.BLACKJACK, &"a")
	host.request_sit(1, &"hl")
	var bet := int(sim.casino()["min_bet"])
	var hl := host.request_start_high_low(1, &"hl", bet)
	assert_not_null(hl)
	assert_true(sim.player(1).high_low == hl)
	assert_true(host.request_high_low_guess(1, true)["ok"])
	if sim.player(1).high_low != null:
		assert_true(host.request_high_low_cash_out(1)["ok"])
	host.request_sit(1, &"bj")
	assert_not_null(host.request_start_blackjack(1, &"bj", bet))
	assert_true(host.request_blackjack_hit(1)["ok"])
	if sim.player(1).blackjack != null:
		assert_true(host.request_blackjack_stand(1)["ok"])
	assert_null(sim.player(1).blackjack)
	host.free()


func test_new_visit_carries_players_and_detaches_old_sim() -> void:
	var host := _host(2, {1: "Ace", 2: "Deuce"})
	var first := host.start_visit()
	var ace := first.player(1)
	ace.wallet.add(500)
	for i in Tuning.STRIKES_TO_THROW_OUT:
		host.request_caught(2)
		host.request_reach_back_room(2)
		first.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
		first.tick(Tuning.REJOIN_GRACE_SECONDS + 0.1)  # guards leave a rejoined player alone that long
	assert_true(first.finished)
	assert_eq(host.run.rung, 3)
	host_events.clear()
	var second := host.start_visit()
	assert_false(second == first)
	assert_true(second.player(1) == ace, "same PlayerState carried over")
	assert_eq(ace.wallet.pocket, CasinoLadder.start_chips(2) + 500)
	assert_eq(second.casino()["rung"], 3)
	assert_eq(host_events.filter(func(e: Array) -> bool: return e[0] == &"player_joined").size(), 0, "nobody new")
	first.event.emit(&"stale", {})
	assert_false(host_events.any(func(e: Array) -> bool: return e[0] == &"stale"), "old sim no longer forwarded")
	host.free()


func test_new_names_join_on_the_next_visit() -> void:
	var host := _host(2, {1: "Ace"})
	host.start_visit()
	host.player_names[2] = "Deuce"
	var sim := host.start_visit()
	assert_eq(sim.player_ids(), [1, 2] as Array[int])
	host.free()


func test_physics_ticks_the_sim_unless_paused() -> void:
	var host := _host()
	tree.root.add_child(host)
	var sim := host.start_visit()
	for i in 5:
		await tree.physics_frame
	var t := host.run.elapsed_seconds
	assert_gt(t, 0.0, "ticked by _physics_process")
	host.paused = true
	for i in 3:
		await tree.physics_frame
	assert_eq(host.run.elapsed_seconds, t, "paused")
	host.paused = false
	sim.finished = true
	for i in 3:
		await tree.physics_frame
	assert_eq(host.run.elapsed_seconds, t, "a finished visit isn't ticked")
	host.queue_free()
	await tree.process_frame


func test_start_run_resets() -> void:
	var host := _host(2)
	var sim := host.start_visit()
	host.start_run(4, 7, {5: "Five"})
	assert_null(host.current_sim())
	assert_eq(host.run.rung, 4)
	sim.event.emit(&"stale", {})
	assert_false(host_events.any(func(e: Array) -> bool: return e[0] == &"stale"))
	var next := host.start_visit()
	assert_eq(next.player_ids(), [5] as Array[int])
	assert_eq(next.player(5).wallet.pocket, CasinoLadder.start_chips(4))
	host.free()
