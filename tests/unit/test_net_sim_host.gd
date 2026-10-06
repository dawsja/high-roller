extends TestCase
## SimHost's co-op side without sockets: a host and a client SimHost wired
## through a fake transport that round-trips every message through
## var_to_bytes (so an Object can't sneak onto the wire). Covers request
## validation and serialization, replies, event broadcast and coalescing,
## snapshots, world messages, shared dice rolls and player removal.

const CLIENT_PID := 2

var host: SimHost
var client: SimHost
## [from, to, method] of every message sent.
var sent: Array = []
var client_events: Array = []
var host_events: Array = []
var client_done: Array = []
var host_done: Array = []


func before_each() -> void:
	sent.clear()
	client_events.clear()
	host_events.clear()
	client_done.clear()
	host_done.clear()
	host = SimHost.new()
	host.set_network(SimHost.Role.HOST, 1)
	client = SimHost.new()
	client.set_network(SimHost.Role.CLIENT, CLIENT_PID)
	host.transport = func(to: int, method: StringName, args: Array) -> void:
		sent.append([1, to, method])
		if to == 0 or to == CLIENT_PID:
			client.receive(1, method, _wire(args))
	client.transport = func(to: int, method: StringName, args: Array) -> void:
		sent.append([CLIENT_PID, to, method])
		if to == 1 or to == 0:
			host.receive(CLIENT_PID, method, _wire(args))
	host.sim_event.connect(func(k: StringName, d: Dictionary) -> void: host_events.append([k, d]))
	client.sim_event.connect(func(k: StringName, d: Dictionary) -> void: client_events.append([k, d]))
	host.request_done.connect(func(r: StringName, a: Array, res: Dictionary) -> void: host_done.append([r, a, res]))
	client.request_done.connect(func(r: StringName, a: Array, res: Dictionary) -> void: client_done.append([r, a, res]))


func after_each() -> void:
	if is_instance_valid(host):
		host.free()
	if is_instance_valid(client):
		client.free()


## What arrives on the other side: encoded and decoded like a packet.
func _wire(args: Array) -> Array:
	return bytes_to_var(var_to_bytes(args))


func _start(rung: int = Tuning.BOTTOM_RUNG) -> FloorSim:
	host.start_run(rung, 42, {1: "Ace", CLIENT_PID: "Deuce"})
	host.visit_extras = {"practice": true}
	var sim := host.start_visit()
	sim.register_table(&"slots_1", HR.GameType.SLOTS, &"slots_a")
	sim.register_table(&"dice_1", HR.GameType.DICE, &"tables_a")
	return sim


func _kinds(events: Array) -> Array:
	return events.map(func(e: Array) -> StringName: return e[0])


# --- Validation ------------------------------------------------------------------

func test_check_request_rules() -> void:
	assert_eq(SimHost.check_request(2, &"no_such", [])["reason"], SimHost.UNKNOWN_REQUEST)
	for host_only: StringName in [&"caught", &"freed", &"reach_back_room", &"set_player_flags", &"report_seen", &"register_table", &"start_id_check", &"place_shared_roll"]:
		assert_eq(SimHost.check_request(2, host_only, [2, -1])["reason"], SimHost.HOST_ONLY, String(host_only))
	assert_eq(SimHost.check_request(2, &"sit", [2, &"t"])["reason"], SimHost.BAD_ARGS, "missing argument")
	assert_eq(SimHost.check_request(2, &"sit", [2, &"t", false, 1])["reason"], SimHost.BAD_ARGS, "extra argument")
	assert_eq(SimHost.check_request(2, &"place_bet", [2, &"t", "100", {}])["reason"], SimHost.BAD_ARGS, "a String amount")
	assert_eq(SimHost.check_request(2, &"place_bet", [2, &"t", 1.5, {}])["reason"], SimHost.BAD_ARGS, "a fractional amount")
	assert_eq(SimHost.check_request(2, &"distraction", [2, HR.Distraction.KNOCK_OVER, Vector3(INF, 0, 0)])["reason"], SimHost.BAD_ARGS, "a non-finite position")
	assert_eq(SimHost.check_request(2, &"change_outfit", [2, "hat"])["reason"], SimHost.BAD_ARGS, "outfits travel as dicts")
	assert_eq(SimHost.check_request(2, &"sit", [3, &"t", false])["reason"], SimHost.NOT_YOUR_PLAYER, "someone else's pid")
	assert_eq(SimHost.check_request(2, &"give_chips", [1, 2, 10])["reason"], SimHost.NOT_YOUR_PLAYER, "giving away a teammate's chips")
	var long_name := "x".repeat(SimHost.MAX_NAME_LENGTH + 1)
	assert_eq(SimHost.check_request(2, &"sit", [2, long_name, false])["reason"], SimHost.BAD_ARGS)
	var ok := SimHost.check_request(2, &"place_bet", [2.0, "slots_1", 50.0, {"throw": true}])
	assert_true(bool(ok["ok"]))
	var args: Array = ok["args"]
	assert_eq(typeof(args[0]), TYPE_INT, "whole floats become ints")
	assert_eq(typeof(args[1]), TYPE_STRING_NAME, "Strings become StringNames")
	assert_eq(args[2], 50)
	assert_true(bool(SimHost.check_request(2, &"try_climb", [])["ok"]), "no pid argument")


func test_every_request_has_wire_types_and_clients_only_send_their_own() -> void:
	for request: StringName in SimHost.REQUESTS:
		assert_true(SimHost.REQUEST_ARGS.has(request), "REQUEST_ARGS.%s" % request)
	for request: StringName in SimHost.CLIENT_REQUESTS:
		assert_has(SimHost.REQUESTS, request)
		var index: int = SimHost.CLIENT_REQUESTS[request]
		if index >= 0:
			assert_eq(SimHost.REQUEST_ARGS[request][index], TYPE_INT, "%s pid argument" % request)


# --- Requests over the wire -----------------------------------------------------

func test_visit_announcement_builds_the_client_cache() -> void:
	var started: Array = []
	client.visit_started.connect(func(s: FloorSim) -> void: started.append(s))
	var sim := _start()
	assert_eq(started.size(), 1)
	assert_null(started[0], "a client has no sim")
	assert_null(client.current_sim())
	assert_eq(client.visit_info()["token"], host.visit_info()["token"])
	assert_eq(client.visit_info()["map_seed"], host.visit_info()["map_seed"])
	assert_true(bool(client.visit_info()["practice"]), "visit extras travel along")
	assert_eq(client.player_ids(), [1, CLIENT_PID] as Array[int], "join order")
	assert_eq(client.snapshot()["players"][CLIENT_PID]["name"], "Deuce")
	assert_eq(client.snapshot()["run"]["rung"], sim.run.rung)


func test_a_client_request_runs_on_the_host_and_is_answered() -> void:
	var sim := _start()
	client_events.clear()
	var res := client.request_sit(CLIENT_PID, &"slots_1")
	assert_eq(res, {"ok": true, "reason": SimHost.PENDING}, "pending on the client")
	assert_eq(sim.player(CLIENT_PID).status, HR.PlayerStatus.SEATED, "ran on the host")
	assert_eq(client_done.size(), 1, "answered")
	assert_eq(client_done[0][0], &"sit")
	assert_true(bool(client_done[0][2]["ok"]))
	assert_has(_kinds(client_events), &"seated")
	assert_eq(client.snapshot()["players"][CLIENT_PID]["table_id"], &"slots_1", "the cache follows the events")
	assert_eq(client.snapshot()["players"][CLIENT_PID]["status"], HR.PlayerStatus.SEATED)
	# The events reach the client before the answer (BetPanel adds up Heat in between).
	var bet := int(sim.casino()["min_bet"])
	var order: Array = []
	client.sim_event.connect(func(k: StringName, _d: Dictionary) -> void: order.append(k))
	client.request_done.connect(func(r: StringName, _a: Array, _x: Dictionary) -> void: order.append(StringName("done_%s" % r)))
	client.request_place_bet(CLIENT_PID, &"slots_1", bet, {"throw": false})
	assert_eq(order.back(), &"done_place_bet")
	assert_has(order, &"bet")
	var answer: Dictionary = client_done.back()[2]
	assert_eq(int(answer["pocket"]), sim.player(CLIENT_PID).wallet.pocket)
	assert_eq(int(answer["result"]["bet"]), bet)


func test_a_client_cannot_act_for_someone_else() -> void:
	var sim := _start()
	client.request_sit(1, &"slots_1")
	assert_eq(sim.player(1).status, HR.PlayerStatus.FREE, "refused on the host")
	assert_eq(client_done[0][2]["reason"], SimHost.NOT_YOUR_PLAYER)
	# A forged packet straight to the host is refused too.
	var forged := host.handle_remote_request(CLIENT_PID, &"cash_out", [1, 100])
	assert_eq(forged["reason"], SimHost.NOT_YOUR_PLAYER)
	var host_only := host.handle_remote_request(CLIENT_PID, &"caught", [CLIENT_PID, 1])
	assert_eq(host_only["reason"], SimHost.HOST_ONLY, "a client can't have itself caught")
	assert_eq(sim.player(CLIENT_PID).status, HR.PlayerStatus.FREE)


func test_host_only_requests_stay_on_the_client() -> void:
	_start()
	sent.clear()
	client_done.clear()
	assert_eq(client.request_caught(CLIENT_PID)["reason"], SimHost.HOST_ONLY)
	assert_eq(client_done.size(), 1, "answered at once")
	assert_eq(client.request_set_player_flags(CLIENT_PID, {})["reason"], SimHost.HOST_ONLY)
	assert_null(client.request_register_table(&"x", HR.GameType.SLOTS, &"a"))
	assert_true(sent.is_empty(), "nothing was sent")
	# Without a connection a request is refused and answered right away.
	client.transport = Callable()
	client_done.clear()
	assert_eq(client.request_stand(CLIENT_PID)["reason"], SimHost.NOT_CONNECTED)
	assert_eq(client_done.size(), 1)


func test_round_requests_answer_with_ok_and_reason() -> void:
	var sim := _start()
	sim.register_table(&"hl_1", HR.GameType.HIGH_LOW, &"tables_a")
	client.request_sit(CLIENT_PID, &"hl_1")
	assert_null(client.request_start_high_low(CLIENT_PID, &"hl_1", int(sim.casino()["min_bet"])), "start_* return null on a client")
	var answer: Dictionary = client_done.back()[2]
	assert_eq(client_done.back()[0], &"start_high_low")
	assert_true(bool(answer["ok"]))
	assert_not_null(sim.player(CLIENT_PID).high_low, "the run started on the host")
	assert_eq(client.round_state(CLIENT_PID)["kind"], &"high_low", "the &\"hand\" event reached the client")
	client.request_start_high_low(CLIENT_PID, &"nope", 10)
	assert_false(bool(client_done.back()[2]["ok"]))
	assert_ne(client_done.back()[2]["reason"], &"")
	# The host's own round start answers through request_done as well.
	sim.register_table(&"hl_2", HR.GameType.HIGH_LOW, &"tables_a")
	host.request_sit(1, &"hl_2")
	var hl := host.request_start_high_low(1, &"hl_2", int(sim.casino()["min_bet"]))
	assert_not_null(hl)
	assert_eq(host_done.back()[0], &"start_high_low")
	assert_true(bool(host_done.back()[2]["ok"]))


func test_change_outfit_sends_a_dict() -> void:
	var sim := _start()
	client.request_enter_zone(CLIENT_PID, HR.ZoneType.RESTROOM, &"restroom")
	var target: Outfit = sim.player(CLIENT_PID).stash[0].copy()
	client.request_change_outfit(CLIENT_PID, target)
	assert_true(bool(client_done.back()[2]["ok"]), "an Outfit object goes over as its dict")
	assert_true(sim.player(CLIENT_PID).outfit.equals(target))


func test_validators_run_on_client_requests() -> void:
	var sim := _start()
	var seen: Array = []
	host.set_validator(&"sit", func(sender: int, args: Array) -> StringName:
		seen.append([sender, args.duplicate()])
		args[2] = true
		return &"")
	client.request_sit(CLIENT_PID, &"slots_1", false)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0][0], CLIENT_PID)
	assert_eq(sim.player(CLIENT_PID).status, HR.PlayerStatus.SEATED)
	host.set_validator(&"stand", func(_s: int, _a: Array) -> StringName: return &"too_far")
	client.request_stand(CLIENT_PID)
	assert_eq(client_done.back()[2]["reason"], &"too_far")
	assert_eq(sim.player(CLIENT_PID).status, HR.PlayerStatus.SEATED, "refused")
	host.set_validator(&"stand", Callable())
	client.request_stand(CLIENT_PID)
	assert_eq(sim.player(CLIENT_PID).status, HR.PlayerStatus.FREE, "validator removed")
	# The host's own requests skip the validators (it is the authority).
	host.set_validator(&"sit", func(_s: int, _a: Array) -> StringName: return &"too_far")
	assert_true(bool(host.request_sit(1, &"slots_1")["ok"]))


func test_malformed_messages_are_dropped() -> void:
	_start()
	host.receive(CLIENT_PID, &"request", ["seq", 12, "nope"])
	host.receive(CLIENT_PID, &"request", [1])
	host.receive(CLIENT_PID, &"nonsense", [])
	client.receive(1, &"events", [3, "not an array"])
	client.receive(1, &"events", [3, [["kind"], 5, [&"chips", "x"]]])
	client.receive(1, &"snapshot", [99, [10, PackedByteArray([1, 2, 3])]])
	client.receive(1, &"world", [client.visit_token(), 5, {}])
	assert_null(SimHost._unpack([5, "x"]))
	assert_null(SimHost._unpack([-1, PackedByteArray()]))
	var packed := SimHost._pack({"a": [1, 2], "b": &"c"})
	assert_eq(SimHost._unpack(packed), {"a": [1, 2], "b": &"c"})
	# A request with bad args still gets a refusal back.
	client_done.clear()
	host.receive(CLIENT_PID, &"request", [77, &"place_bet", [CLIENT_PID, &"slots_1", "lots", {}]])
	assert_has(sent.map(func(m: Array) -> StringName: return m[2]), &"reply")


# --- Events and snapshots ---------------------------------------------------------

func test_events_reach_the_client_in_order() -> void:
	var sim := _start()
	client_events.clear()
	host_events.clear()
	client.request_sit(CLIENT_PID, &"slots_1")
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cashier")
	host.request_cash_out(1, 50)
	host._process(0.0)
	var host_kinds := _kinds(host_events).filter(func(k: StringName) -> bool: return k != &"heat")
	var client_kinds := _kinds(client_events).filter(func(k: StringName) -> bool: return k != &"heat")
	assert_eq(client_kinds, host_kinds, "same events, same order")
	assert_true(sim.run.bank > 0)
	assert_eq(client.snapshot()["run"]["bank"], sim.run.bank, "patched from &\"banked\"")


func test_passive_heat_is_coalesced() -> void:
	var sim := _start()
	sim.player(CLIENT_PID).heat.add(30.0, HeatRules.WIN)
	host._process(0.0)
	client_events.clear()
	host_events.clear()
	for i in 30:
		sim.tick(1.0 / 60.0)
	host._process(0.0)
	var heat: Array = client_events.filter(func(e: Array) -> bool: return e[0] == &"heat" and int(e[1]["pid"]) == CLIENT_PID)
	assert_true(heat.is_empty(), "passive ticks wait for the next snapshot")
	host._snapshot_due_usec = 0
	host._process(0.0)
	heat = client_events.filter(func(e: Array) -> bool: return e[0] == &"heat" and int(e[1]["pid"]) == CLIENT_PID)
	var host_heat: int = host_events.filter(func(e: Array) -> bool: return e[0] == &"heat" and int(e[1]["pid"]) == CLIENT_PID).size()
	assert_gt(host_heat, 5, "the host sees every tick")
	assert_eq(heat.size(), 1, "the client gets one coalesced passive event")
	assert_almost_eq(float(heat[0][1]["value"]), sim.player(CLIENT_PID).heat.value, 0.0001, "with the latest value")
	assert_almost_eq(float(client.snapshot()["players"][CLIENT_PID]["heat"]), sim.player(CLIENT_PID).heat.value, 0.0001)


func test_a_non_passive_heat_event_flushes_the_pending_passive_one_first() -> void:
	var sim := _start()
	sim.player(CLIENT_PID).heat.add(30.0, HeatRules.WIN)
	host._process(0.0)
	sim.tick(1.0 / 60.0)
	client_events.clear()
	sim.player(CLIENT_PID).heat.add(5.0, HeatRules.WIN)
	host._flush_events()
	var heat: Array = client_events.filter(func(e: Array) -> bool: return e[0] == &"heat")
	assert_eq(heat.size(), 2)
	assert_ne(heat[0][1]["reason"], HeatRules.WIN, "the passive tick first")
	assert_eq(heat[1][1]["reason"], HeatRules.WIN)


func test_snapshots_refresh_the_cache_and_stale_ones_are_dropped() -> void:
	var sim := _start()
	sim.player(CLIENT_PID).wallet.add(123)  # no event: only a snapshot shows it
	var got: Array = []
	client.snapshot_received.connect(func() -> void: got.append(true))
	host._snapshot_due_usec = 0
	host._process(0.0)
	assert_eq(got.size(), 1)
	assert_eq(int(client.snapshot()["players"][CLIENT_PID]["pocket"]), sim.player(CLIENT_PID).wallet.pocket)
	client.receive(1, &"snapshot", [0, SimHost._pack({"players": {}})])
	assert_false((client.snapshot()["players"] as Dictionary).is_empty(), "an older snapshot is ignored")


# --- World messages, shared rolls, leaving ---------------------------------------------

func test_world_messages_carry_the_visit_token() -> void:
	_start()
	var host_msgs: Array = []
	host.world_message.connect(func(k: StringName, d: Dictionary, from: int) -> void: host_msgs.append([k, d, from]))
	client.send_world(1, &"tackle", {"guard_id": 1})
	assert_eq(host_msgs.size(), 1)
	assert_eq(host_msgs[0][0], &"tackle")
	assert_eq(host_msgs[0][2], CLIENT_PID, "the sender's pid")
	host.receive(CLIENT_PID, &"world", [host.visit_token() + 5, &"tackle", {}])
	assert_eq(host_msgs.size(), 1, "another visit's message is dropped")
	host.send_world(1, &"to_myself", {})
	assert_eq(sent.filter(func(m: Array) -> bool: return m[2] == &"world" and m[0] == 1).size(), 0, "nothing sent to itself")


func test_crew_at_one_dice_table_rolls_together() -> void:
	var sim := _start()
	host.request_sit(1, &"dice_1")
	client.request_sit(CLIENT_PID, &"dice_1")
	var bet := int(sim.casino()["min_bet"])
	var opened: Array = host_events.filter(func(e: Array) -> bool: return e[0] == &"shared_roll")
	assert_true(opened.is_empty())
	var res := host.request_place_bet(1, &"dice_1", bet, {"call": GameResolver.DICE_CALL_HIGH})
	assert_eq(res["reason"], SimHost.PENDING, "the host's own bet waits for the crew")
	var rolls: Array = host_events.filter(func(e: Array) -> bool: return e[0] == &"shared_roll")
	assert_eq(rolls.size(), 1)
	assert_true(bool(rolls[0][1]["open"]))
	assert_eq(host.request_place_bet(1, &"dice_1", bet)["reason"], FloorSim.IN_ROUND, "one bet each")
	client_done.clear()
	client.request_place_bet(CLIENT_PID, &"dice_1", bet, {"call": GameResolver.DICE_CALL_LOW})
	assert_true(client_done.is_empty(), "the client's answer waits for the roll")
	host_done.clear()
	host._physics_process(0.016)  # everyone seated has bet: roll now
	assert_eq(client_done.size(), 1)
	assert_true(bool(client_done[0][2]["ok"]))
	assert_true(bool(client_done[0][2]["shared"]))
	var mine: Array = host_done.filter(func(d: Array) -> bool: return d[0] == &"place_bet")
	assert_eq(mine.size(), 1, "the host's bet is answered too")
	var bets: Array = client_events.filter(func(e: Array) -> bool: return e[0] == &"bet")
	assert_eq(bets.size(), 2, "one bet event per bettor")
	assert_eq(bets[0][1]["result"]["detail"]["dice"], bets[1][1]["result"]["detail"]["dice"], "one roll")


func test_a_lone_shared_bet_rolls_after_the_window() -> void:
	var sim := _start()
	host.request_sit(1, &"dice_1")
	client.request_sit(CLIENT_PID, &"dice_1")
	client.request_place_bet(CLIENT_PID, &"dice_1", int(sim.casino()["min_bet"]))
	host._physics_process(SimHost.SHARED_ROLL_SECONDS * 0.5)
	assert_true(client_done.filter(func(d: Array) -> bool: return d[0] == &"place_bet").is_empty())
	host._physics_process(SimHost.SHARED_ROLL_SECONDS)
	var done: Array = client_done.filter(func(d: Array) -> bool: return d[0] == &"place_bet")
	assert_eq(done.size(), 1, "rolled once the window closed")
	assert_true(bool(done[0][2]["ok"]))


func test_offline_dice_rolls_at_once() -> void:
	var solo := SimHost.new()
	solo.start_run(Tuning.BOTTOM_RUNG, 3, {1: "Ace", 2: "Deuce"})
	var sim := solo.start_visit()
	sim.register_table(&"dice_1", HR.GameType.DICE, &"tables_a")
	solo.request_sit(1, &"dice_1")
	solo.request_sit(2, &"dice_1")
	var res := solo.request_place_bet(1, &"dice_1", int(sim.casino()["min_bet"]))
	assert_true(bool(res["ok"]), "single player: no shared window")
	assert_true(res.has("result"))
	solo.free()


func test_remove_player_drops_them_from_the_visit_and_the_run() -> void:
	var sim := _start()
	client.request_sit(CLIENT_PID, &"slots_1")
	host.remove_player(CLIENT_PID)
	host._flush_events()
	assert_null(sim.player(CLIENT_PID))
	assert_false(sim.table(&"slots_1").is_seated(CLIENT_PID), "stood up first")
	assert_false(host.player_names.has(CLIENT_PID))
	assert_has(_kinds(client_events), &"player_left")
	assert_false((client.snapshot()["players"] as Dictionary).has(CLIENT_PID))
	var next := host.start_visit()
	assert_eq(next.player_ids(), [1] as Array[int], "not back on the next visit")
