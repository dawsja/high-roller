extends TestCase
## Seeded end-to-end scenarios through SimHost requests, the way the world
## layer drives the simulation.

const MARQUEE := 2
const RIVERBOAT := 3
const NEON := 4

## [kind, data] from SimHost.sim_event.
var log: Array = []


func before_each() -> void:
	log.clear()


func _host(rung: int, seed_value: int, crew: Dictionary) -> SimHost:
	var host := SimHost.new()
	host.sim_event.connect(func(k: StringName, d: Dictionary) -> void: log.append([k, d]))
	host.start_run(rung, seed_value, crew)
	host.start_visit()
	return host


func _events(kind: StringName) -> Array:
	var out: Array = []
	for e: Array in log:
		if e[0] == kind:
			out.append(e[1])
	return out


func _min_bet(host: SimHost) -> int:
	return int(host.current_sim().casino()["min_bet"])


func _max_bet(host: SimHost) -> int:
	return int(host.current_sim().casino()["max_bet"])


## Caught, carried to the back room, and (unless that ended the visit) waits
## out the timeout. A player still in their after-rejoin grace can't be
## grabbed, so that runs out first.
func _back_room(host: SimHost, pid: int) -> Dictionary:
	var grace: float = host.current_sim().player(pid).rejoin_grace
	if grace > 0.0:
		host.current_sim().tick(grace + 0.01)
	assert_true(host.request_caught(pid, 1)["ok"], "caught %d" % pid)
	var r := host.request_reach_back_room(pid)
	assert_true(r["ok"], "back room %d" % pid)
	if not host.current_sim().finished and host.current_sim().player(pid).status == HR.PlayerStatus.DETAINED:
		host.current_sim().tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	return r


## Two-player crew at the Grand Marquee: player 2 is grabbed, player 1 tackles
## the guard (goes Wanted: poster of their look), then three strikes drop the
## crew to the Riverboat. Returns the host with the new visit started.
func _drop_from_marquee() -> SimHost:
	var host := _host(MARQUEE, 31, {1: "Ace", 2: "Deuce"})
	var sim := host.current_sim()
	assert_true(host.request_caught(2, 1)["ok"])
	assert_true(host.request_freed(2, 1)["ok"])
	assert_eq(sim.player(1).heat.level(), HR.HeatLevel.WANTED)
	assert_eq(sim.run.posters.count(&"grand_marquee"), 1)
	_back_room(host, 2)
	_back_room(host, 2)
	assert_false(sim.finished)
	var last := _back_room(host, 1)
	assert_true(last["thrown_out"])
	assert_true(sim.finished)
	assert_eq(sim.outcome, &"thrown_out")
	assert_eq(_events(&"thrown_out").back(), {"from": MARQUEE, "to": RIVERBOAT, "cause": &"strikes"})
	host.start_visit()
	return host


func test_bet_until_watched_dealer_swap_then_half_win_rate() -> void:
	var host := _host(Tuning.TOP_RUNG, 7, {1: "Ace"})
	var sim := host.current_sim()
	var ps := sim.player(1)
	ps.wallet.add(10000000)
	host.request_register_table(&"roulette_1", HR.GameType.ROULETTE, &"pit_a")
	host.request_register_table(&"roulette_2", HR.GameType.ROULETTE, &"pit_b")
	host.request_sit(1, &"roulette_1")
	var red := {"kind": "color", "color": "red"}
	for i in 100:
		host.request_place_bet(1, &"roulette_1", _min_bet(host), red)
		if not _events(&"dealer_swap").is_empty():
			break
	assert_eq(_events(&"dealer_swap").size(), 1, "dealer swapped on reaching Watched")
	assert_eq(_events(&"dealer_swap")[0]["table_id"], &"roulette_1")
	assert_gte(ps.heat.level(), HR.HeatLevel.WATCHED)
	assert_true(sim.table(&"roulette_1").is_cooled(1))
	var wins := 0
	var n := 400
	for i in n:
		var r := host.request_place_bet(1, &"roulette_1", _min_bet(host), red)
		assert_true(r["ok"])
		if r["result"]["won"]:
			wins += 1
	assert_between(float(wins) / n, 0.42, 0.58, "cooled table wins about half")
	# Leaving the table restores the normal rate elsewhere.
	assert_true(host.request_sit(1, &"roulette_2")["ok"])
	assert_false(sim.table(&"roulette_2").is_cooled(1))
	wins = 0
	for i in n:
		if host.request_place_bet(1, &"roulette_2", _min_bet(host), red)["result"]["won"]:
			wins += 1
	assert_between(float(wins) / n, 0.78, 0.92, "fresh table back at the normal rate")
	host.free()


func test_wanted_prints_poster_of_current_look() -> void:
	var host := _host(MARQUEE, 12, {1: "Ace"})
	var sim := host.current_sim()
	var ps := sim.player(1)
	ps.wallet.add(1000000)
	host.request_register_table(&"wheel", HR.GameType.BIG_WHEEL, &"main", Vector3(0, 0, -6))
	host.request_sit(1, &"wheel")
	var look := ps.outfit.to_dict()
	for i in 200:
		host.request_place_bet(1, &"wheel", _max_bet(host))
		if not _events(&"poster").is_empty():
			break
	var posters := _events(&"poster")
	assert_eq(posters.size(), 1)
	assert_eq(posters[0]["poster"]["outfit"], look)
	assert_eq(posters[0]["casino_id"], &"grand_marquee")
	assert_eq(ps.heat.level(), HR.HeatLevel.WANTED)
	assert_not_null(ps.recorded_look, "Suspected came first and recorded the look")
	var snap := host.snapshot()
	assert_eq(snap["posters"].size(), 1)
	assert_true(snap["players"][1]["matches_poster"])
	assert_gt(_events(&"noise").size(), 0, "the big wheel is loud")
	host.free()


func test_three_strikes_drop_a_rung_carrying_players_and_posters() -> void:
	var host := _drop_from_marquee()
	var sim := host.current_sim()
	assert_eq(host.run.rung, RIVERBOAT)
	assert_eq(sim.casino()["id"], &"riverboat_queen")
	assert_eq(sim.player_ids(), [1, 2] as Array[int])
	for pid in [1, 2]:
		var ps := sim.player(pid)
		assert_eq(ps.status, HR.PlayerStatus.FREE)
		assert_almost_eq(ps.heat.value, 0.0)
		assert_eq(ps.wallet.pocket, 0, "both lost their pockets in the back room")
		assert_true(ps.current_id().passes_check(), "a usable ID for the new visit")
		assert_eq(ps.stash.size(), Tuning.START_STASH_OUTFITS)
	assert_eq(host.run.strikes, 0)
	assert_eq(host.run.posters.count(&"grand_marquee"), 1, "posters stay up between visits")
	assert_eq(sim.posters_here().size(), 0, "none at the Riverboat")
	assert_false(sim.matches_poster(1))
	host.free()


func test_poster_still_matches_when_coming_back() -> void:
	var host := _drop_from_marquee()
	var sim := host.current_sim()
	var ace := sim.player(1)
	var look := ace.outfit.copy()
	# Bank the Marquee's buy-in at the Riverboat cashier and leave together.
	var buy_in := CasinoLadder.buy_in_to_leave(RIVERBOAT)
	ace.wallet.add(buy_in)
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	var cash := host.request_cash_out(1, buy_in)
	assert_true(cash["ok"], str(cash))
	assert_eq(host.run.bank, buy_in)
	assert_eq(host.request_try_climb()["reason"], FloorSim.NOT_AT_EXIT)
	host.request_enter_zone(1, HR.ZoneType.EXIT, &"front_door")
	host.request_enter_zone(2, HR.ZoneType.EXIT, &"front_door")
	# Everything went into the buy-in: upstairs they couldn't cover a bet.
	var stake: int = int(CasinoLadder.casino(MARQUEE)["min_bet"])
	var broke := host.request_try_climb()
	assert_eq(broke["reason"], FloorSim.NO_STAKE)
	assert_eq(broke["stake"], stake)
	assert_false(sim.finished)
	ace.wallet.add(stake)
	var climb := host.request_try_climb()
	assert_true(climb["ok"], str(climb))
	assert_eq(climb["to"], MARQUEE)
	assert_eq(_events(&"climbed").back(), {"from": RIVERBOAT, "to": MARQUEE, "cost": buy_in})
	var back := host.start_visit()
	assert_eq(back.casino()["id"], &"grand_marquee")
	assert_true(ace.outfit.equals(look))
	assert_eq(back.posters_here().size(), 1)
	var seen := host.request_report_seen(1, {"guard_id": 1})
	assert_true(seen["matches_poster"], "the old look is still on the wall")
	assert_almost_eq(seen["heat"], Tuning.POSTER_MATCH_HEAT)
	assert_false(host.request_report_seen(2)["matches_poster"])
	host.free()


func test_climb_with_buy_in_and_stretch_skip() -> void:
	# One rung: bank exactly the buy-in through the cashier.
	var host := _host(NEON, 3, {1: "Ace"})
	var sim := host.current_sim()
	var buy_in := CasinoLadder.buy_in_to_leave(NEON)
	sim.player(1).wallet.add(buy_in)
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	host.request_cash_out(1, buy_in - 1)
	host.request_enter_zone(1, HR.ZoneType.EXIT, &"door")
	assert_eq(host.request_try_climb()["reason"], FloorSim.CANT_CLIMB)
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	host.request_cash_out(1, 1)
	host.request_enter_zone(1, HR.ZoneType.EXIT, &"door")
	var r := host.request_try_climb()
	assert_true(r["ok"])
	assert_eq(r["to"], NEON - 1)
	assert_eq(r["cost"], buy_in)
	assert_eq(host.run.bank, 0)
	host.free()
	# Stretch: double the buy-in skips a rung.
	var stretch := _host(NEON, 3, {1: "Ace"})
	stretch.run.bank = Tuning.STRETCH_MULT * buy_in
	assert_eq(stretch.snapshot()["run"]["climb_target"], NEON - 2)
	stretch.request_enter_zone(1, HR.ZoneType.EXIT, &"door")
	var s := stretch.request_try_climb()
	assert_true(s["ok"])
	assert_eq(s["to"], NEON - 2)
	assert_eq(s["cost"], Tuning.STRETCH_MULT * buy_in)
	assert_eq(stretch.run.bank, 0)
	assert_eq(stretch.start_visit().casino()["rung"], NEON - 2)
	stretch.free()
	# Never past the top: from rung 2 a stretch amount still climbs one rung.
	var top := _host(MARQUEE, 3, {1: "Ace"})
	var top_buy_in := CasinoLadder.buy_in_to_leave(MARQUEE)
	top.run.bank = Tuning.STRETCH_MULT * top_buy_in
	top.request_enter_zone(1, HR.ZoneType.EXIT, &"door")
	var t := top.request_try_climb()
	assert_eq(t["to"], Tuning.TOP_RUNG)
	assert_eq(top.run.bank, top_buy_in)
	top.free()


func test_sals_curb_timeout() -> void:
	var host := _host(Tuning.BOTTOM_RUNG, 5, {1: "Ace"})
	var sim := host.current_sim()
	var ps := sim.player(1)
	var visits := host.run.visits
	_back_room(host, 1)
	assert_gt(_events(&"notify").filter(func(d: Dictionary) -> bool: return d["kind"] == &"bailout").size(), 0,
		"broke at Sal's: bailout chips")
	assert_eq(ps.wallet.pocket, Tuning.BAILOUT_CHIPS)
	_back_room(host, 1)
	var r := _back_room(host, 1)
	assert_true(r["curb"])
	assert_false(r["thrown_out"])
	assert_false(sim.finished, "no drop below Sal's")
	assert_eq(ps.status, HR.PlayerStatus.ON_CURB)
	assert_eq(_events(&"curb").size(), 1)
	assert_eq(_events(&"thrown_out").size(), 0)
	assert_eq(host.run.rung, Tuning.BOTTOM_RUNG)
	assert_eq(host.run.strikes, 0)
	assert_eq(host.run.visits, visits + 1)
	host.request_register_table(&"coin", HR.GameType.SLOTS, &"a")
	assert_eq(host.request_sit(1, &"coin")["reason"], FloorSim.BUSY, "on the curb")
	sim.tick(Tuning.CURB_TIMEOUT + 0.1)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(_events(&"rejoined").back()["from"], &"curb")
	assert_true(host.request_sit(1, &"coin")["ok"])
	assert_true(host.request_place_bet(1, &"coin", _min_bet(host))["ok"], "back in the game")
	host.free()


func test_cash_out_past_cap_flags_id() -> void:
	var host := _host(RIVERBOAT, 9, {1: "Ace"})
	var sim := host.current_sim()
	var ps := sim.player(1)
	ps.wallet.add(20000)
	host.request_enter_zone(1, HR.ZoneType.FORGER, sim.forger.location())
	var bought := host.request_buy_id(1, HR.IdGrade.CHEAP)
	assert_true(bought["ok"])
	var cheap := ps.current_id()
	var cap: int = int(Tuning.ID_GRADES[HR.IdGrade.CHEAP]["cap"])
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	var safe := host.request_cash_out(1, cap)
	assert_true(safe["ok"])
	assert_false(safe["flagged"], "exactly the cap is fine")
	var over := host.request_cash_out(1, 1)
	assert_true(over["ok"])
	assert_true(over["flagged"])
	assert_true(cheap.flagged)
	var note: Dictionary = _events(&"notify").back()
	assert_eq(note["kind"], &"flagged")
	assert_true(String(note["text"]).contains(cheap.name))
	assert_eq(host.request_cash_out(1, 1)["reason"], Cashier.BAD_ID)
	var check := host.request_start_id_check(1, 2)
	assert_true(check["auto_fail"])
	assert_eq(check["fail_reason"], FloorSim.ID_FLAGGED)
	assert_false(_events(&"id_result").back()["passed"])
	# The old solid card still works.
	assert_true(host.request_swap_id(1, 0)["ok"])
	assert_false(host.request_start_id_check(1)["auto_fail"])
	host.free()


func test_teammate_frees_carried_player() -> void:
	var host := _host(MARQUEE, 4, {1: "Ace", 2: "Deuce"})
	var sim := host.current_sim()
	host.request_register_table(&"dice", HR.GameType.DICE, &"a")
	host.request_sit(1, &"dice")
	assert_true(host.request_caught(1, 3)["ok"])
	assert_eq(sim.player(1).status, HR.PlayerStatus.CARRIED)
	assert_eq(sim.player(1).table_id, &"", "grabbed out of the seat")
	var deuce_look := sim.player(2).outfit.to_dict()
	var r := host.request_freed(1, 2)
	assert_true(r["ok"])
	assert_eq(sim.player(1).status, HR.PlayerStatus.FREE)
	assert_eq(sim.player(2).heat.level(), HR.HeatLevel.WANTED)
	var poster: Dictionary = _events(&"poster").back()
	assert_eq(poster["pid"], 2)
	assert_eq(poster["poster"]["outfit"], deuce_look)
	assert_eq(host.request_reach_back_room(1)["reason"], FloorSim.NOT_CARRIED)
	assert_eq(host.run.strikes, 0)
	assert_true(host.request_sit(1, &"dice")["ok"])
	host.free()


func test_fire_alarm_once_per_visit() -> void:
	var host := _host(MARQUEE, 6, {1: "Ace", 2: "Deuce"})
	var sim := host.current_sim()
	host.request_register_table(&"bj", HR.GameType.BLACKJACK, &"a")
	host.request_sit(2, &"bj")
	var before := sim.player(2).wallet.pocket
	assert_not_null(host.request_start_blackjack(2, &"bj", _min_bet(host)))
	assert_true(host.request_distraction(1, HR.Distraction.FIRE_ALARM, Vector3.ZERO)["ok"])
	assert_null(sim.player(2).blackjack, "the hand was settled")
	var settled: Dictionary = _events(&"bet").back()
	assert_eq(sim.player(2).wallet.pocket, before + int(settled["result"]["net"]))
	assert_eq(sim.player(2).status, HR.PlayerStatus.FREE)
	assert_true(sim.table(&"bj").closed)
	assert_true(host.snapshot()["fire_alarm"])
	assert_eq(host.request_sit(2, &"bj")["reason"], FloorSim.TABLE_CLOSED)
	assert_eq(host.request_distraction(2, HR.Distraction.FIRE_ALARM, Vector3.ZERO)["reason"], FloorSim.USED)
	sim.tick(Tuning.FIRE_ALARM_SECONDS + 0.1)
	assert_false(sim.table(&"bj").closed)
	assert_eq(_events(&"fire_alarm").map(func(d: Dictionary) -> bool: return d["active"]), [true, false])
	assert_true(host.request_sit(2, &"bj")["ok"])
	assert_eq(host.request_distraction(1, HR.Distraction.FIRE_ALARM, Vector3.ZERO)["reason"], FloorSim.USED)
	# Next visit: usable again.
	for pid in [1, 2]:
		host.request_caught(pid)
	assert_true(sim.finished, "whole crew grabbed")
	var next := host.start_visit()
	assert_false(host.run.fire_alarm_used)
	assert_true(host.request_distraction(1, HR.Distraction.FIRE_ALARM, Vector3.ZERO)["ok"])
	assert_true(next.fire_alarm_active())
	host.free()


func test_high_low_and_blackjack_apply_exactly_once() -> void:
	var host := _host(Tuning.TOP_RUNG, 15, {1: "Ace"})
	var sim := host.current_sim()
	var ps := sim.player(1)
	ps.wallet.add(1000000)
	var start := ps.wallet.pocket
	host.request_register_table(&"hl", HR.GameType.HIGH_LOW, &"a")
	host.request_register_table(&"bj", HR.GameType.BLACKJACK, &"b")
	var bet := _min_bet(host)
	var expected_net := 0
	var expected_win_heat_events := 0
	log.clear()
	# High-low: up to three guesses, then cash out.
	host.request_sit(1, &"hl")
	for round_i in 10:
		var hl := host.request_start_high_low(1, &"hl", bet)
		assert_not_null(hl)
		var alive := true
		for g in 3:
			var r := host.request_high_low_guess(1, hl.current_card <= 8)
			if r["won"]:
				expected_win_heat_events += 1
			else:
				alive = false
				expected_net -= bet
				break
		if alive:
			var c := host.request_high_low_cash_out(1)
			expected_net += int(c["payout"]) - bet
			assert_eq(host.request_high_low_cash_out(1)["reason"], FloorSim.NO_ROUND)
	# Blackjack: hit below 12, then stand.
	host.request_sit(1, &"bj")
	for hand in 20:
		var bj := host.request_start_blackjack(1, &"bj", bet)
		assert_not_null(bj)
		var done := false
		while bj.player_total() < 12:
			var h := host.request_blackjack_hit(1)
			if h["finished"]:
				expected_net += int(h["result"]["net"])
				done = true
				break
		if not done:
			var s := host.request_blackjack_stand(1)
			expected_net += int(s["result"]["net"])
			if s["result"]["won"]:
				expected_win_heat_events += 1
		assert_eq(host.request_blackjack_stand(1)["reason"], FloorSim.NO_ROUND)
		assert_eq(host.request_blackjack_hit(1)["reason"], FloorSim.NO_ROUND)
	assert_eq(ps.wallet.pocket, start + expected_net, "every result paid exactly once")
	var chip_total := 0
	for d: Dictionary in _events(&"chips"):
		chip_total += int(d["delta"])
	assert_eq(chip_total, expected_net, "chips events add up to the same")
	var win_heat := _events(&"heat").filter(func(d: Dictionary) -> bool: return d["reason"] == HeatRules.WIN and d["delta"] > 0.0)
	# Heat clamps at HEAT_MAX, after which wins add nothing (no event).
	assert_lte(win_heat.size(), expected_win_heat_events)
	assert_gt(win_heat.size(), 0)
	assert_eq(_events(&"bet").filter(func(d: Dictionary) -> bool: return d["round_over"]).size(), 30, "one settled result per round")
	host.free()


# --- Climb times (tuning check) ---------------------------------------------

const CLIMB_SEEDS := 16
const CLIMB_STEP := 0.5
## Walk from a table to the bar and back, and to the cashier / exit.
const CLIMB_WALK_SECONDS := 6.0
const CLIMB_ERRAND_SECONDS := 12.0
## Cool off at the bar until Heat is this low.
const CLIMB_COOL_TO := 8.0
## Keep this many min bets of the casino above in the pocket when climbing.
const CLIMB_STAKE_BETS := 4
const CLIMB_GAMES: Array[int] = [HR.GameType.ROULETTE, HR.GameType.DICE, HR.GameType.BIG_WHEEL]
const CLIMB_LIMIT_SECONDS := 40.0 * 60.0


## A fresh solo run starting at each rung below the top: how long a steady
## player takes to bank the buy-in and leave. The bot bets ~60% of the max
## bet every round_seconds + 3 s, moves on and cools off at the bar whenever
## it reaches Watched, then banks the buy-in (keeping a stake) and walks to
## the exit. No guards, cameras or pit bosses, so it should land a bit
## under the design doc's climb_minutes; lower rungs must be quicker.
## Measured at tuning time (40 seeds, mean / median minutes): Sal's 1.6 / 1.3
## (target 2), Rusty Spur 2.7 / 2.6 (3), Neon Oasis 4.5 / 4.3 (5), Riverboat
## 5.7 / 5.4 (7), Grand Marquee 7.5 / 7.4 (10); 0-8% of runs go broke.
func test_climb_times_track_the_design_targets() -> void:
	var means: Dictionary = {}
	for rung in range(Tuning.BOTTOM_RUNG, Tuning.TOP_RUNG, -1):
		var times: Array[float] = []
		var broke := 0
		for i in CLIMB_SEEDS:
			var t := _climb_seconds(rung, 100 + i)
			if t < 0.0:
				broke += 1
			else:
				times.append(t)
		times.sort()
		assert_false(times.is_empty(), "rung %d: never climbed" % rung)
		if times.is_empty():
			continue
		var mean := 0.0
		for t: float in times:
			mean += t / 60.0
		mean /= float(times.size())
		var target := float(CasinoLadder.casino(rung)["climb_minutes"])
		means[rung] = mean
		print("  climb from %s (start %d, buy-in %d): mean %.2f min, median %.2f (%.2f-%.2f), target %.0f, broke %d/%d" % [
			CasinoLadder.casino(rung)["name"], CasinoLadder.start_chips(rung), CasinoLadder.buy_in_to_leave(rung),
			mean, times[times.size() / 2] / 60.0, times[0] / 60.0, times.back() / 60.0, target, broke, CLIMB_SEEDS])
		assert_between(mean, target * 0.6, target * 1.3, "rung %d climbs in roughly the target time" % rung)
		assert_lte(broke, CLIMB_SEEDS / 4, "rung %d: the start chips carry a steady player" % rung)
	for rung in range(Tuning.BOTTOM_RUNG, Tuning.TOP_RUNG + 1, -1):
		if means.has(rung) and means.has(rung - 1):
			assert_lt(means[rung], means[rung - 1], "rung %d is quicker to climb out of than rung %d" % [rung, rung - 1])


## Seconds for the climb bot above, or -1 if it went broke (or ran out of time).
func _climb_seconds(rung: int, seed_value: int) -> float:
	var sim := FloorSim.new(RunState.new(rung), seed_value)
	var ps := sim.add_player(1, "Bot")
	var min_bet: int = int(sim.casino()["min_bet"])
	var max_bet: int = int(sim.casino()["max_bet"])
	var buy_in: int = CasinoLadder.buy_in_to_leave(rung)
	var stake: int = int(CasinoLadder.casino(rung - 1)["min_bet"]) * CLIMB_STAKE_BETS
	var count: int = CLIMB_GAMES.size() * 2
	for i in count:
		sim.register_table(StringName("t%d" % i), CLIMB_GAMES[i % CLIMB_GAMES.size()], StringName("area%d" % (i % 3)))
	var t := 0.0
	var next := 0
	while t < CLIMB_LIMIT_SECONDS and not sim.finished:
		if ps.wallet.pocket >= buy_in + stake:
			sim.stand(1)
			t += _climb_walk(sim, CLIMB_ERRAND_SECONDS)
			sim.enter_zone(1, HR.ZoneType.CASHIER, &"cage")
			if not sim.cash_out(1, buy_in)["ok"]:
				return -1.0
			t += _climb_walk(sim, CLIMB_ERRAND_SECONDS)
			sim.enter_zone(1, HR.ZoneType.EXIT, &"door")
			return t if sim.try_climb()["ok"] else -1.0
		if ps.wallet.pocket < min_bet:
			return -1.0
		var table_id := StringName("t%d" % next)
		var table := sim.table(table_id)
		next = (next + 1) % count
		sim.enter_zone(1, HR.ZoneType.TABLES, table.area_id)
		sim.sit(1, table_id)
		var round_seconds: float = float(Tuning.GAMES[table.game_type]["round_seconds"]) + 3.0
		var choice := {"kind": "color", "color": "red"} if table.game_type == HR.GameType.ROULETTE else {}
		while ps.level() < HR.HeatLevel.WATCHED and ps.wallet.pocket >= min_bet and ps.wallet.pocket < buy_in + stake and t < CLIMB_LIMIT_SECONDS:
			sim.place_bet(1, table_id, clampi(roundi(max_bet * 0.6), min_bet, ps.wallet.pocket), choice)
			t += _climb_tick(sim, round_seconds)
		sim.stand(1)
		if ps.level() >= HR.HeatLevel.WATCHED:
			t += _climb_walk(sim, CLIMB_WALK_SECONDS)
			sim.enter_zone(1, HR.ZoneType.BAR, &"bar")
			while ps.heat.value > CLIMB_COOL_TO and t < CLIMB_LIMIT_SECONDS:
				t += _climb_tick(sim, CLIMB_STEP)
			t += _climb_walk(sim, CLIMB_WALK_SECONDS)
	return -1.0


func _climb_walk(sim: FloorSim, seconds: float) -> float:
	sim.enter_zone(1, HR.ZoneType.FLOOR, &"aisle")
	return _climb_tick(sim, seconds)


func _climb_tick(sim: FloorSim, seconds: float) -> float:
	var left := seconds
	while left > 0.0:
		var d := minf(CLIMB_STEP, left)
		sim.tick(d)
		left -= d
	return seconds
