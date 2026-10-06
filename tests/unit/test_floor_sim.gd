extends TestCase
## FloorSim and PlayerState: every request, its validation and its events.

const TOP := Tuning.TOP_RUNG
const BOTTOM := Tuning.BOTTOM_RUNG

## [kind, data] in emit order.
var log: Array = []


func before_each() -> void:
	log.clear()


# --- Helpers ----------------------------------------------------------------

func _sim(rung: int = TOP, seed_value: int = 1, crew: int = 1) -> FloorSim:
	var sim := FloorSim.new(RunState.new(rung), seed_value)
	sim.event.connect(_record)
	for i in crew:
		sim.add_player(i + 1, "P%d" % (i + 1))
	return sim


func _record(kind: StringName, data: Dictionary) -> void:
	log.append([kind, data])


func _events(kind: StringName) -> Array:
	var out: Array = []
	for e: Array in log:
		if e[0] == kind:
			out.append(e[1])
	return out


func _heat_events(reason: StringName) -> Array:
	return _events(&"heat").filter(func(d: Dictionary) -> bool: return d["reason"] == reason)


func _min_bet(sim: FloorSim) -> int:
	return int(sim.casino()["min_bet"])


func _max_bet(sim: FloorSim) -> int:
	return int(sim.casino()["max_bet"])


## Registers and sits pid at a fresh table of the type.
func _seat(sim: FloorSim, pid: int, game_type: int, id: StringName = &"t1", area: StringName = &"a1") -> TableState:
	var t := sim.register_table(id, game_type, area)
	var r := sim.sit(pid, id)
	assert_true(r["ok"], "sit: %s" % str(r))
	return t


## Bets until the result's won matches; returns the result dict (or {}).
func _bet_until(sim: FloorSim, pid: int, table_id: StringName, amount: int, want_win: bool, choice: Dictionary = {}) -> Dictionary:
	for i in 200:
		var r := sim.place_bet(pid, table_id, amount, choice)
		if not r["ok"]:
			fail("bet failed: %s" % str(r))
			return {}
		if bool(r["result"]["won"]) == want_win:
			return r
	fail("never got won=%s" % str(want_win))
	return {}


func _rich(sim: FloorSim, pid: int, chips: int = 1000000) -> void:
	sim.player(pid).wallet.add(chips)


func _check_ok_shape(r: Dictionary, msg: String = "") -> void:
	assert_true(r.has("ok") and typeof(r["ok"]) == TYPE_BOOL, "has ok %s" % msg)
	assert_true(r.has("reason") and typeof(r["reason"]) == TYPE_STRING_NAME, "has reason %s" % msg)


## True if v holds no Objects (recursively) — safe for RPC.
func _is_plain(v: Variant) -> bool:
	match typeof(v):
		TYPE_OBJECT:
			return v == null
		TYPE_DICTIONARY:
			for k: Variant in v:
				if not _is_plain(k) or not _is_plain(v[k]):
					return false
		TYPE_ARRAY:
			for x: Variant in v:
				if not _is_plain(x):
					return false
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
	return true


# --- Setup ------------------------------------------------------------------

func test_add_player_gives_starting_kit() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	assert_not_null(ps)
	assert_eq(ps.pid, 1)
	assert_eq(ps.display_name, "P1")
	assert_eq(ps.wallet.pocket, Tuning.START_CHIPS)
	assert_false(ps.outfit.is_staff_uniform())
	assert_eq(ps.ids.size(), 1)
	assert_eq(ps.id_index, 0)
	assert_eq(ps.current_id().grade, HR.IdGrade.SOLID)
	assert_true(ps.current_id().passes_check())
	assert_eq(ps.stash.size(), Tuning.START_STASH_OUTFITS)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(ps.heat.value, 0.0)
	assert_null(ps.recorded_look)
	assert_eq(_events(&"player_joined").size(), 1)
	assert_true(sim.add_player(1, "Again") == ps, "same pid returns the existing player")
	assert_eq(sim.player_ids(), [1] as Array[int])
	assert_null(sim.player(42))


func test_same_seed_same_kit() -> void:
	var a := _sim(TOP, 99, 2)
	var b := _sim(TOP, 99, 2)
	for pid in [1, 2]:
		assert_true(a.player(pid).outfit.equals(b.player(pid).outfit))
		assert_eq(a.player(pid).current_id().name, b.player(pid).current_id().name)


func test_register_table_returns_existing() -> void:
	var sim := _sim()
	var t := sim.register_table(&"x", HR.GameType.DICE, &"a")
	assert_true(sim.register_table(&"x", HR.GameType.SLOTS, &"b") == t)
	assert_eq(sim.table(&"x").game_type, HR.GameType.DICE)
	assert_null(sim.table(&"nope"))


# --- Bad input never throws ---------------------------------------------------

func test_bad_input_returns_ok_false() -> void:
	var sim := _sim()
	sim.register_table(&"t1", HR.GameType.SLOTS, &"a")
	var results: Array[Dictionary] = [
		sim.sit(99, &"t1"),
		sim.sit(1, &"missing"),
		sim.stand(99),
		sim.stand(1),
		sim.place_bet(99, &"t1", 300),
		sim.place_bet(1, &"missing", 300),
		sim.place_bet(1, &"t1", -50),
		sim.place_shared_roll(&"missing", []),
		sim.place_shared_roll(&"t1", [{"pid": 1, "bet": 300}]),
		sim.high_low_guess(99, true),
		sim.high_low_guess(1, true),
		sim.high_low_cash_out(1),
		sim.blackjack_hit(1),
		sim.blackjack_stand(1),
		sim.enter_zone(99, HR.ZoneType.BAR, &"bar"),
		sim.set_player_flags(99, {}),
		sim.report_seen(99),
		sim.change_to_stash(1, 0),
		sim.change_to_stash(99, 0),
		sim.change_outfit(1, null),
		sim.change_outfit(1, 17),
		sim.buy_outfit_piece(1, 0, &"lucky_ball_cap"),
		sim.steal_outfit_piece(1),
		sim.buy_id(1, HR.IdGrade.CHEAP),
		sim.swap_id(1, 5),
		sim.swap_id(1, -1),
		sim.start_id_check(99),
		sim.answer_id_check(1, 0),
		sim.expire_id_check(1),
		sim.tear_poster(1, 12345),
		sim.deface_poster(1, 12345),
		sim.caught(99),
		sim.freed(1, 0),
		sim.reach_back_room(1),
		sim.cash_out(1, 100),
		sim.cash_out(99, 100),
		sim.distraction(1, 999),
		sim.distraction(1, HR.Distraction.WIN_BIG),
		sim.distraction(99, HR.Distraction.KNOCK_OVER),
		sim.give_chips(1, 99, 10),
		sim.give_chips(1, 1, 10),
		sim.give_chips(1, 1, -10),
		sim.try_climb(),
	]
	for i in results.size():
		_check_ok_shape(results[i], "case %d" % i)
		assert_false(results[i]["ok"], "case %d should fail: %s" % [i, str(results[i])])
	assert_null(sim.start_high_low(99, &"t1", 300))
	assert_eq(sim.last_reason, FloorSim.UNKNOWN_PLAYER)
	assert_null(sim.start_blackjack(1, &"missing", 300))
	assert_eq(sim.last_reason, FloorSim.UNKNOWN_TABLE)
	assert_eq(sim.player(1).wallet.pocket, Tuning.START_CHIPS, "nothing was charged")


func test_reason_codes() -> void:
	var sim := _sim()
	assert_eq(sim.sit(99, &"x")["reason"], FloorSim.UNKNOWN_PLAYER)
	assert_eq(sim.sit(1, &"x")["reason"], FloorSim.UNKNOWN_TABLE)
	assert_eq(sim.stand(1)["reason"], FloorSim.NOT_SEATED)
	assert_eq(sim.give_chips(1, 1, 5)["reason"], FloorSim.SAME_PLAYER)
	assert_eq(sim.distraction(1, 999)["reason"], FloorSim.BAD_KIND)
	assert_eq(sim.try_climb()["reason"], FloorSim.CANT_CLIMB, "nothing above the top")


# --- Sit and stand ------------------------------------------------------------

func test_sit_and_stand() -> void:
	var sim := _sim()
	var t := sim.register_table(&"t1", HR.GameType.ROULETTE, &"a1")
	var r := sim.sit(1, &"t1")
	assert_true(r["ok"])
	assert_eq(r["game_type"], HR.GameType.ROULETTE)
	var ps := sim.player(1)
	assert_eq(ps.status, HR.PlayerStatus.SEATED)
	assert_eq(ps.table_id, &"t1")
	assert_true(t.is_seated(1))
	assert_eq(_events(&"seated").size(), 1)
	assert_true(sim.sit(1, &"t1")["ok"], "sitting again is a no-op")
	assert_eq(_events(&"seated").size(), 1)
	var s := sim.stand(1)
	assert_true(s["ok"])
	assert_eq(s["table_id"], &"t1")
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(ps.table_id, &"")
	assert_false(t.is_seated(1))
	assert_eq(_events(&"stood").size(), 1)
	assert_eq(sim.stand(1)["reason"], FloorSim.NOT_SEATED)


func test_sit_elsewhere_stands_first() -> void:
	var sim := _sim()
	var a := sim.register_table(&"a", HR.GameType.SLOTS, &"s")
	var b := sim.register_table(&"b", HR.GameType.ROULETTE, &"r")
	sim.sit(1, &"a")
	sim.sit(1, &"b")
	assert_false(a.is_seated(1))
	assert_true(b.is_seated(1))
	assert_eq(sim.player(1).table_id, &"b")


func test_staff_uniform_cannot_sit() -> void:
	var sim := _sim()
	sim.register_table(&"t1", HR.GameType.SLOTS, &"a")
	sim.player(1).outfit = OutfitCatalog.staff_uniform()
	assert_eq(sim.sit(1, &"t1")["reason"], FloorSim.STAFF_UNIFORM)


func test_table_jump_heat_in_view_within_window() -> void:
	var sim := _sim()
	sim.register_table(&"a", HR.GameType.SLOTS, &"s")
	sim.register_table(&"b", HR.GameType.SLOTS, &"s")
	sim.sit(1, &"a")
	sim.stand(1)
	var r := sim.sit(1, &"b", true)
	assert_almost_eq(r["heat"], Tuning.TABLE_JUMP_HEAT)
	assert_eq(_heat_events(HeatRules.TABLE_JUMP).size(), 1)
	# Out of view: nothing.
	sim.sit(1, &"a", false)
	assert_eq(_heat_events(HeatRules.TABLE_JUMP).size(), 1)
	# Outside the window: nothing.
	sim.stand(1)
	sim.tick(Tuning.TABLE_JUMP_WINDOW + 0.5)
	assert_almost_eq(sim.sit(1, &"b", true)["heat"], 0.0)
	assert_eq(_heat_events(HeatRules.TABLE_JUMP).size(), 1)


# --- Single-shot bets -----------------------------------------------------------

func test_place_bet_validation() -> void:
	var sim := _sim()
	var minb := _min_bet(sim)
	var maxb := _max_bet(sim)
	sim.register_table(&"slots", HR.GameType.SLOTS, &"a")
	sim.register_table(&"hl", HR.GameType.HIGH_LOW, &"a")
	assert_eq(sim.place_bet(1, &"slots", minb)["reason"], FloorSim.NOT_SEATED)
	sim.sit(1, &"slots")
	assert_eq(sim.place_bet(1, &"slots", 0)["reason"], FloorSim.BAD_AMOUNT)
	assert_eq(sim.place_bet(1, &"slots", -5)["reason"], FloorSim.BAD_AMOUNT)
	assert_eq(sim.place_bet(1, &"slots", minb - 1)["reason"], FloorSim.BELOW_MIN)
	assert_eq(sim.place_bet(1, &"slots", maxb + 1)["reason"], FloorSim.ABOVE_MAX)
	sim.player(1).wallet.lose_pocket()
	assert_eq(sim.place_bet(1, &"slots", minb)["reason"], FloorSim.NOT_ENOUGH)
	_rich(sim, 1)
	sim.sit(1, &"hl")
	assert_eq(sim.place_bet(1, &"hl", minb)["reason"], FloorSim.WRONG_GAME)
	assert_eq(sim.place_bet(1, &"slots", minb)["reason"], FloorSim.NOT_SEATED, "seated elsewhere")
	sim.sit(1, &"slots")
	sim.table(&"slots").closed = true
	assert_eq(sim.place_bet(1, &"slots", minb)["reason"], FloorSim.TABLE_CLOSED)


func test_place_bet_pays_and_heats_once() -> void:
	var sim := _sim(TOP, 3)
	_seat(sim, 1, HR.GameType.ROULETTE)
	var ps := sim.player(1)
	var bet := _min_bet(sim)
	var before := ps.wallet.pocket
	var r := _bet_until(sim, 1, &"t1", bet, true, {"kind": "color", "color": "black"})
	var result: Dictionary = r["result"]
	assert_true(result["won"])
	assert_eq(r["pocket"], ps.wallet.pocket)
	assert_gt(ps.heat.value, 0.0)
	var wins := _heat_events(HeatRules.WIN)
	assert_eq(wins.size(), 1, "one heat event for the one win")
	assert_almost_eq(wins[0]["delta"], result["heat"])
	var bets := _events(&"bet")
	assert_eq(bets[bets.size() - 1]["result"]["won"], true)
	assert_true(bets[bets.size() - 1]["round_over"])
	# Every bet moved the pocket by exactly its net.
	var net_total := 0
	for b: Dictionary in bets:
		net_total += int(b["result"]["net"])
	assert_eq(ps.wallet.pocket, before + net_total)


func test_pit_boss_multiplies_gains() -> void:
	var sim := _sim(TOP, 5)
	_seat(sim, 1, HR.GameType.SLOTS)
	sim.set_player_flags(1, {"pit_boss_view": true})
	var r := _bet_until(sim, 1, &"t1", _min_bet(sim), true)
	var wins := _heat_events(HeatRules.WIN)
	assert_almost_eq(wins[0]["delta"], float(r["result"]["heat"]) * Tuning.PIT_BOSS_HEAT_MULT)


func test_throw_loses_and_cools() -> void:
	var sim := _sim()
	_rich(sim, 1)
	_seat(sim, 1, HR.GameType.SLOTS)
	var ps := sim.player(1)
	ps.heat.add(20.0, &"test")
	var r := sim.place_bet(1, &"t1", _max_bet(sim), {"throw": true})
	assert_false(r["result"]["won"])
	assert_true(r["result"]["intentional_loss"])
	assert_almost_eq(ps.heat.value, 20.0 + Tuning.LOSE_ON_PURPOSE_HEAT, 0.001, "a max-bet throw cools the full amount")
	assert_eq(_heat_events(HeatRules.LOSE_ON_PURPOSE).size(), 1)
	# A min-bet throw cools in proportion: big wins can't be laundered cheaply.
	sim.place_bet(1, &"t1", _min_bet(sim), {"throw": true})
	var cooled: float = HeatRules.lose_on_purpose_heat(_min_bet(sim), _max_bet(sim))
	assert_almost_eq(ps.heat.value, 20.0 + Tuning.LOSE_ON_PURPOSE_HEAT + cooled)
	assert_gt(cooled, Tuning.LOSE_ON_PURPOSE_HEAT)


func test_dice_solo_is_a_shared_roll() -> void:
	var sim := _sim()
	_seat(sim, 1, HR.GameType.DICE)
	var r := sim.place_bet(1, &"t1", _min_bet(sim), {"call": "low"})
	assert_true(r["ok"])
	assert_true(r["result"]["detail"]["shared"])
	assert_eq(r["result"]["detail"]["crew"], 1)
	assert_eq(r["result"]["detail"]["call"], "low")


func test_shared_roll_crew() -> void:
	var sim := _sim(TOP, 11, 3)
	sim.register_table(&"dice", HR.GameType.DICE, &"a")
	sim.sit(1, &"dice")
	sim.sit(2, &"dice")
	var bet := _min_bet(sim)
	var won := false
	for i in 50:
		var r := sim.place_shared_roll(&"dice", [{"pid": 1, "bet": bet}, {"pid": 2, "bet": bet}, {"pid": 3, "bet": bet}, {"pid": 1, "bet": bet}, "junk"])
		assert_true(r["ok"])
		assert_eq(r["results"].size(), 2)
		assert_eq(r["rejected"], {3: FloorSim.NOT_SEATED})
		_rich(sim, 1, bet)
		_rich(sim, 2, bet)
		if r["results"][1]["won"]:
			won = true
			break
	assert_true(won)
	assert_eq(_heat_events(HeatRules.SHARED_ROLL).size(), 2, "both winners get a share")
	assert_eq(_heat_events(HeatRules.WIN).size(), 0)
	var none := sim.place_shared_roll(&"dice", [{"pid": 3, "bet": bet}])
	assert_false(none["ok"])
	assert_eq(none["reason"], FloorSim.NOT_SEATED)
	assert_eq(sim.place_shared_roll(&"dice", [])["reason"], FloorSim.NO_BETS)


func test_big_wheel_makes_noise_at_the_table() -> void:
	var sim := _sim()
	sim.register_table(&"wheel", HR.GameType.BIG_WHEEL, &"a", Vector3(4, 0, -2))
	sim.sit(1, &"wheel")
	sim.place_bet(1, &"wheel", _min_bet(sim))
	var noises := _events(&"noise")
	assert_eq(noises.size(), 1)
	assert_eq(noises[0]["kind"], &"big_wheel")
	assert_eq(noises[0]["position"], Vector3(4, 0, -2))
	assert_almost_eq(noises[0]["radius"], float(Tuning.NOISE_RADIUS[&"big_wheel"]))


# --- Heat levels --------------------------------------------------------------

func test_watched_while_seated_swaps_dealer_once() -> void:
	var sim := _sim()
	var t := _seat(sim, 1, HR.GameType.ROULETTE)
	sim.player(1).heat.add(Tuning.WATCHED_AT + 1.0, HeatRules.WIN)
	assert_true(t.is_cooled(1))
	assert_almost_eq(t.win_rate_for(1), Tuning.COOLED_WIN_RATE)
	var swaps := _events(&"dealer_swap")
	assert_eq(swaps.size(), 1)
	assert_eq(swaps[0], {"pid": 1, "table_id": &"t1"})
	assert_eq(_events(&"level")[0]["new"], HR.HeatLevel.WATCHED)
	# Higher levels don't swap again.
	sim.player(1).heat.add(30.0, &"test")
	assert_eq(_events(&"dealer_swap").size(), 1)


func test_winning_into_watched_at_a_table_swaps_its_dealer() -> void:
	var sim := _sim()
	_rich(sim, 1)
	var t := _seat(sim, 1, HR.GameType.ROULETTE)
	var red := {"kind": "color", "color": "red"}
	for i in 30:
		_bet_until(sim, 1, &"t1", _max_bet(sim), true, red)
		if sim.player(1).level() >= HR.HeatLevel.WATCHED:
			break
	assert_eq(sim.player(1).level(), HR.HeatLevel.WATCHED)
	assert_true(t.is_cooled(1), "won into Watched here")
	assert_eq(_events(&"dealer_swap"), [{"pid": 1, "table_id": &"t1"}])


func test_table_jump_into_watched_does_not_swap_the_new_dealer() -> void:
	var sim := _sim()
	_seat(sim, 1, HR.GameType.ROULETTE, &"a")
	var b := sim.register_table(&"b", HR.GameType.ROULETTE, &"a1")
	sim.player(1).heat.add(Tuning.WATCHED_AT - 1.0, &"test")
	sim.stand(1)
	var r := sim.sit(1, &"b", true)
	assert_almost_eq(r["heat"], Tuning.TABLE_JUMP_HEAT)
	assert_eq(sim.player(1).level(), HR.HeatLevel.WATCHED, "the jump crossed Watched")
	assert_false(b.is_cooled(1), "but the new dealer stays")
	assert_almost_eq(b.win_rate_for(1), Tuning.WIN_RATE)
	assert_eq(_events(&"dealer_swap").size(), 0)


func test_passive_or_poster_heat_into_watched_while_seated_does_not_swap() -> void:
	var sim := _sim()
	var t := _seat(sim, 1, HR.GameType.ROULETTE)
	sim.player(1).heat.add(Tuning.WATCHED_AT - 1.0, &"test")
	sim.player(1).heat.add(2.0, HeatRules.POSTER_MATCH)
	assert_eq(sim.player(1).level(), HR.HeatLevel.WATCHED)
	assert_false(t.is_cooled(1))
	sim.player(1).heat.add(-5.0, &"test")
	sim.player(1).heat.add(5.0, HeatRules.CAMERA)
	assert_false(t.is_cooled(1))
	# Camping at this table is playing it: that swaps.
	sim.player(1).heat.add(-5.0, &"test")
	sim.player(1).heat.add(5.0, HeatRules.CAMPING)
	assert_true(t.is_cooled(1))
	assert_eq(_events(&"dealer_swap").size(), 1)


func test_watched_while_standing_cools_nothing() -> void:
	var sim := _sim()
	var t := sim.register_table(&"t1", HR.GameType.ROULETTE, &"a")
	sim.player(1).heat.add(30.0, &"test")
	sim.sit(1, &"t1")
	assert_false(t.is_cooled(1))
	assert_eq(_events(&"dealer_swap").size(), 0)


func test_suspected_records_look() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(Tuning.SUSPECTED_AT, &"test")
	assert_not_null(ps.recorded_look)
	assert_true(ps.recorded_look.equals(ps.outfit))
	assert_false(ps.recorded_look == ps.outfit, "a copy")
	assert_eq(_events(&"look_recorded").size(), 1)
	assert_true(sim.snapshot()["players"][1]["recognized"])


func test_wanted_prints_poster_once_per_episode() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(Tuning.WANTED_AT, &"test")
	var posters := _events(&"poster")
	assert_eq(posters.size(), 1)
	assert_eq(posters[0]["pid"], 1)
	assert_eq(posters[0]["casino_id"], sim.run.casino_id())
	assert_eq(posters[0]["poster"]["outfit"], ps.outfit.to_dict())
	assert_eq(sim.run.posters.count(sim.run.casino_id()), 1)
	assert_true(sim.matches_poster(1))
	ps.heat.add(10.0, &"test")
	ps.heat.add(-5.0, &"test")
	assert_eq(_events(&"poster").size(), 1, "still the same Wanted episode")
	# Drop below Wanted, new look, back up: a second poster.
	ps.heat.add(-20.0, &"test")
	ps.outfit = ps.stash[0]
	ps.heat.add(30.0, &"test")
	assert_eq(_events(&"poster").size(), 2)
	assert_eq(sim.run.posters.count(sim.run.casino_id()), 2)


func test_passive_heat_by_context() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.register_table(&"bj", HR.GameType.BLACKJACK, &"a")
	sim.register_table(&"slots", HR.GameType.SLOTS, &"b")
	sim.sit(1, &"bj")
	sim.tick(Tuning.CAMP_GRACE_SECONDS)
	assert_almost_eq(ps.heat.value, 0.0, 0.001, "grace period")
	sim.tick(10.0)
	assert_almost_eq(ps.heat.value, 10.0 * Tuning.CAMP_HEAT_PER_SECOND, 0.01)
	assert_gt(_heat_events(HeatRules.CAMPING).size(), 0)
	sim.sit(1, &"slots")
	var h := ps.heat.value
	sim.tick(2.0)
	assert_almost_eq(ps.heat.value, h + 2.0 * Tuning.SLOT_BLEND_HEAT_PER_SECOND, 0.01)
	sim.stand(1)
	sim.enter_zone(1, HR.ZoneType.BAR, &"bar")
	h = ps.heat.value
	sim.tick(1.0)
	assert_almost_eq(ps.heat.value, h + Tuning.OFF_TABLE_HEAT_PER_SECOND, 0.01)
	sim.enter_zone(1, HR.ZoneType.FLOOR, &"floor")
	sim.set_player_flags(1, {"running_in_view": true, "in_camera_view": true, "pit_boss_view": true})
	ps.heat.raise_to(Tuning.WATCHED_AT + 5.0, &"test")  # cameras only follow Watched+ players
	h = ps.heat.value
	sim.tick(1.0)
	var gain := (Tuning.RUN_IN_VIEW_HEAT_PER_SECOND + Tuning.CAMERA_HEAT_PER_SECOND) * Tuning.PIT_BOSS_HEAT_MULT
	assert_almost_eq(ps.heat.value, h + gain + Tuning.FLOOR_DECAY_PER_SECOND, 0.01)
	assert_eq(sim.set_player_flags(1, {"in_camera_view": false, "bogus": true})["flags"],
		{"running_in_view": true, "in_camera_view": false, "pit_boss_view": true})


func test_no_passive_heat_while_carried_or_detained() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.set_player_flags(1, {"running_in_view": true})
	sim.caught(1)
	sim.tick(1.0)
	assert_almost_eq(ps.heat.value, 0.0)


func test_area_change_cooloff() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(30.0, &"test")
	assert_almost_eq(sim.enter_zone(1, HR.ZoneType.TABLES, &"a1")["heat"], 0.0, 0.001, "first area")
	assert_almost_eq(sim.enter_zone(1, HR.ZoneType.TABLES, &"a2")["heat"], Tuning.AREA_CHANGE_HEAT)
	assert_almost_eq(sim.enter_zone(1, HR.ZoneType.SLOTS, &"a3")["heat"], 0.0, 0.001, "cooldown")
	sim.enter_zone(1, HR.ZoneType.BAR, &"bar")
	sim.tick(Tuning.AREA_CHANGE_COOLDOWN)
	ps.heat.add(30.0, &"test")  # the bar cooled them right down
	assert_almost_eq(sim.enter_zone(1, HR.ZoneType.TABLES, &"a1")["heat"], Tuning.AREA_CHANGE_HEAT)
	assert_eq(_heat_events(HeatRules.AREA_CHANGE).size(), 2)
	assert_eq(ps.zone, HR.ZoneType.TABLES)
	assert_eq(ps.area_id, &"a1")
	assert_gt(_events(&"zone").size(), 0)


# --- Multi-step games -----------------------------------------------------------

func test_high_low_wrappers_apply_once() -> void:
	var sim := _sim(TOP, 21)
	sim.register_table(&"hl", HR.GameType.HIGH_LOW, &"a")
	sim.register_table(&"slots", HR.GameType.SLOTS, &"a")
	sim.sit(1, &"slots")
	assert_null(sim.start_high_low(1, &"slots", _min_bet(sim)))
	assert_eq(sim.last_reason, FloorSim.WRONG_GAME)
	sim.sit(1, &"hl")
	var ps := sim.player(1)
	var bet := _min_bet(sim)
	var before := ps.wallet.pocket
	var hl := sim.start_high_low(1, &"hl", bet)
	assert_not_null(hl)
	assert_eq(sim.last_reason, FloorSim.NO_REASON)
	assert_eq(ps.wallet.pocket, before - bet)
	assert_eq(_events(&"hand").size(), 1)
	assert_eq(_events(&"hand")[0]["state"]["card"], hl.current_card)
	assert_eq(sim.place_bet(1, &"hl", bet)["reason"], FloorSim.IN_ROUND)
	assert_null(sim.start_high_low(1, &"hl", bet))
	assert_eq(sim.last_reason, FloorSim.IN_ROUND)
	var wins := 0
	var lost := false
	for i in 3:
		var g := sim.high_low_guess(1, hl.current_card <= 8)
		assert_true(g["ok"])
		if g["won"]:
			wins += 1
		else:
			lost = true
			break
	assert_eq(_heat_events(HeatRules.WIN).size(), wins, "heat per winning guess")
	if lost:
		assert_eq(ps.wallet.pocket, before - bet)
		assert_null(ps.high_low)
		assert_eq(sim.high_low_cash_out(1)["reason"], FloorSim.NO_ROUND)
	else:
		var pot := hl.pot
		var c := sim.high_low_cash_out(1)
		assert_true(c["ok"])
		assert_eq(c["payout"], pot)
		assert_eq(ps.wallet.pocket, before - bet + pot)
		assert_eq(sim.high_low_cash_out(1)["reason"], FloorSim.NO_ROUND)
		assert_eq(ps.wallet.pocket, before - bet + pot, "second cash out does nothing")
	assert_true(_events(&"bet").back()["round_over"])


func test_high_low_throw_cools() -> void:
	var sim := _sim()
	_seat(sim, 1, HR.GameType.HIGH_LOW)
	var ps := sim.player(1)
	ps.heat.add(20.0, &"test")
	sim.start_high_low(1, &"t1", _min_bet(sim))
	var g := sim.high_low_guess(1, true, true)
	assert_false(g["won"])
	assert_true(g["finished"])
	assert_almost_eq(ps.heat.value, 20.0 + HeatRules.lose_on_purpose_heat(_min_bet(sim), _max_bet(sim)))


func test_blackjack_wrappers_apply_once() -> void:
	var sim := _sim(TOP, 8)
	_seat(sim, 1, HR.GameType.BLACKJACK)
	var ps := sim.player(1)
	var bet := _min_bet(sim)
	var before := ps.wallet.pocket
	var bj := sim.start_blackjack(1, &"t1", bet)
	assert_not_null(bj)
	assert_eq(ps.wallet.pocket, before - bet)
	assert_eq(_events(&"hand")[0]["state"]["player_cards"].size(), 2)
	assert_eq(_events(&"hand")[0]["state"]["dealer_cards"].size(), 1, "hole card hidden")
	var s := sim.blackjack_stand(1)
	assert_true(s["ok"])
	var r: Dictionary = s["result"]
	assert_eq(ps.wallet.pocket, before - bet + int(r["payout"]))
	assert_eq(sim.blackjack_stand(1)["reason"], FloorSim.NO_ROUND)
	assert_eq(sim.blackjack_hit(1)["reason"], FloorSim.NO_ROUND)
	assert_eq(ps.wallet.pocket, before - bet + int(r["payout"]))
	assert_eq(_events(&"bet").size(), 1)
	assert_eq(_heat_events(HeatRules.WIN).size(), 1 if r["won"] else 0)


func test_blackjack_hit_past_21_is_a_thrown_hand() -> void:
	var sim := _sim(TOP, 4)
	_seat(sim, 1, HR.GameType.BLACKJACK)
	var ps := sim.player(1)
	ps.heat.add(20.0, &"test")
	sim.start_blackjack(1, &"t1", _min_bet(sim))
	var h: Dictionary = {}
	for i in 15:
		h = sim.blackjack_hit(1)
		assert_true(h["ok"])
		if h["finished"]:
			break
	assert_true(h["finished"])
	assert_gt(h["total"], 21)
	assert_false(h["result"]["won"])
	assert_null(ps.blackjack)
	assert_eq(_events(&"bet").size(), 1)
	if h["result"]["intentional_loss"]:
		assert_almost_eq(ps.heat.value, 20.0 + HeatRules.lose_on_purpose_heat(_min_bet(sim), _max_bet(sim)))


func test_stand_settles_round_in_progress() -> void:
	var sim := _sim()
	_seat(sim, 1, HR.GameType.HIGH_LOW)
	var ps := sim.player(1)
	var before := ps.wallet.pocket
	sim.start_high_low(1, &"t1", _min_bet(sim))
	sim.stand(1)
	assert_null(ps.high_low)
	assert_eq(ps.wallet.pocket, before, "pot (the stake) refunded on an untouched run")
	_seat(sim, 1, HR.GameType.BLACKJACK, &"bj")
	sim.start_blackjack(1, &"bj", _min_bet(sim))
	sim.stand(1)
	assert_null(ps.blackjack)
	assert_eq(_events(&"bet").size(), 2)


# --- Identity ---------------------------------------------------------------

func test_change_to_stash_in_restroom() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(40.0, &"test")
	var worn := ps.outfit
	var first := ps.stash[0]
	assert_eq(sim.change_to_stash(1, 0)["reason"], FloorSim.WRONG_ZONE)
	sim.enter_zone(1, HR.ZoneType.RESTROOM, &"wc")
	assert_eq(sim.change_to_stash(1, 7)["reason"], FloorSim.BAD_INDEX)
	var r := sim.change_to_stash(1, 0)
	assert_true(r["ok"])
	assert_true(ps.outfit == first)
	assert_true(ps.stash[0] == worn)
	assert_almost_eq(r["heat"], Tuning.CHANGE_OUTFIT_HEAT)
	assert_almost_eq(ps.heat.value, 40.0 + Tuning.CHANGE_OUTFIT_HEAT)
	var outfits := _events(&"outfit")
	assert_eq(outfits.size(), 1)
	assert_true(outfits[0]["worn_changed"])
	assert_eq(outfits[0]["outfit"], first.to_dict())
	assert_eq(ps.outfit_changes, 1)


func test_change_outfit_mixes_owned_pieces() -> void:
	var sim := _sim(TOP, 2)
	var ps := sim.player(1)
	sim.enter_zone(1, HR.ZoneType.RESTROOM, &"wc")
	ps.stash[0].set_piece(HR.OutfitSlot.TOP, &"rented_tuxedo")
	ps.outfit.set_piece(HR.OutfitSlot.TOP, &"hawaiian_shirt")
	var mix := ps.outfit.copy()
	mix.set_piece(HR.OutfitSlot.TOP, &"rented_tuxedo")
	mix.set_piece(HR.OutfitSlot.HAT, OutfitCatalog.NONE)
	var old := ps.outfit.copy()
	var stash_before := ps.stash.size()
	var r := sim.change_outfit(1, mix.to_dict())
	assert_true(r["ok"], str(r))
	assert_true(ps.outfit.equals(mix))
	assert_eq(ps.stash.size(), stash_before + 1, "old look goes into the stash")
	assert_true(ps.stash.back().equals(old))
	assert_eq(sim.change_outfit(1, mix)["reason"], FloorSim.SAME_OUTFIT)
	var stranger := mix.copy()
	stranger.set_piece(HR.OutfitSlot.ACCESSORY, &"foam_finger")
	var owns_finger := ps.outfit.get_piece(HR.OutfitSlot.ACCESSORY) == &"foam_finger" or ps.stash.any(func(o: Outfit) -> bool: return o.get_piece(HR.OutfitSlot.ACCESSORY) == &"foam_finger")
	if not owns_finger:
		assert_eq(sim.change_outfit(1, stranger)["reason"], FloorSim.NOT_OWNED)
	var bad := {"top": "blue_jeans"}
	assert_eq(sim.change_outfit(1, bad)["reason"], FloorSim.BAD_OUTFIT)
	# Changing back into the old look takes it out of the stash.
	assert_true(sim.change_outfit(1, old)["ok"])
	assert_false(ps.stash.any(func(o: Outfit) -> bool: return o.equals(old)))


func test_buy_outfit_piece_adds_stash_variant() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.outfit.set_piece(HR.OutfitSlot.HAT, OutfitCatalog.NONE)
	assert_eq(sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"top_hat")["reason"], FloorSim.WRONG_ZONE)
	sim.enter_zone(1, HR.ZoneType.GIFT_SHOP, &"shop")
	var worn := ps.outfit.copy()
	var before := ps.wallet.pocket
	var r := sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"top_hat")
	assert_true(r["ok"], str(r))
	var price := OutfitCatalog.piece_price(&"top_hat")
	assert_eq(r["price"], price)
	assert_eq(ps.wallet.pocket, before - price)
	assert_true(ps.outfit.equals(worn), "not worn until changed at a restroom")
	assert_eq(ps.stash.size(), Tuning.START_STASH_OUTFITS + 1)
	assert_eq(ps.stash[r["stash_index"]].get_piece(HR.OutfitSlot.HAT), &"top_hat")
	assert_false(_events(&"outfit")[0]["worn_changed"])
	assert_eq(sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"staff_hat")["reason"], FloorSim.BAD_PIECE)
	assert_eq(sim.buy_outfit_piece(1, HR.OutfitSlot.TOP, &"top_hat")["reason"], FloorSim.BAD_PIECE)
	assert_eq(sim.buy_outfit_piece(1, 9, &"top_hat")["reason"], FloorSim.BAD_PIECE)
	ps.outfit.set_piece(HR.OutfitSlot.HAT, &"bucket_hat")
	assert_eq(sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"bucket_hat")["reason"], FloorSim.ALREADY_WEARING)
	ps.wallet.lose_pocket()
	assert_eq(sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"top_hat")["reason"], FloorSim.NOT_ENOUGH)


func test_steal_outfit_piece() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	assert_eq(sim.steal_outfit_piece(1)["reason"], FloorSim.WRONG_ZONE)
	sim.enter_zone(1, HR.ZoneType.STAFF_ONLY, &"laundry")
	var r := sim.steal_outfit_piece(1)
	assert_true(r["ok"])
	assert_eq(ps.stash.size(), Tuning.START_STASH_OUTFITS + 1)
	assert_eq(sim.steal_outfit_piece(1)["reason"], FloorSim.COOLDOWN)
	sim.tick(Tuning.STEAL_COOLDOWN)
	assert_true(sim.steal_outfit_piece(1)["ok"])
	# Across seeds both outcomes happen and the uniform is a real staff uniform.
	var uniforms := 0
	var pieces := 0
	for s in 40:
		var other := FloorSim.new(RunState.new(), 1000 + s)
		var p := other.add_player(1, "X")
		other.enter_zone(1, HR.ZoneType.STAFF_ONLY, &"locker")
		var res := other.steal_outfit_piece(1)
		if res["uniform"]:
			uniforms += 1
			assert_true(p.stash.back().is_staff_uniform())
		else:
			pieces += 1
			assert_eq(p.stash.back().get_piece(res["slot"]), res["piece"])
			assert_ne(res["piece"], p.outfit.get_piece(res["slot"]))
			assert_false(OutfitCatalog.is_none(res["piece"]))
	assert_gt(uniforms, 0)
	assert_gt(pieces, 0)


func test_buy_id_only_at_the_forger() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	var here := sim.forger.location()
	var elsewhere := sim.forger.next_location()
	sim.enter_zone(1, HR.ZoneType.FORGER, elsewhere)
	assert_eq(sim.buy_id(1, HR.IdGrade.CHEAP)["reason"], FloorSim.FORGER_NOT_HERE)
	sim.enter_zone(1, HR.ZoneType.BAR, here)
	assert_eq(sim.buy_id(1, HR.IdGrade.CHEAP)["reason"], FloorSim.FORGER_NOT_HERE)
	sim.enter_zone(1, HR.ZoneType.FORGER, here)
	assert_eq(sim.buy_id(1, 77)["reason"], FloorSim.BAD_GRADE)
	var before := ps.wallet.pocket
	var r := sim.buy_id(1, HR.IdGrade.CHEAP)
	assert_true(r["ok"])
	assert_eq(r["price"], IdGenerator.price(HR.IdGrade.CHEAP))
	assert_eq(ps.wallet.pocket, before - r["price"])
	assert_eq(ps.ids.size(), 2)
	assert_eq(ps.id_index, 1, "new card in use")
	assert_eq(ps.current_id().grade, HR.IdGrade.CHEAP)
	assert_ne(ps.ids[0].name, ps.ids[1].name)
	assert_eq(_events(&"id").back()["reason"], &"bought")
	ps.wallet.lose_pocket()
	assert_eq(sim.buy_id(1, HR.IdGrade.FLAWLESS)["reason"], FloorSim.NOT_ENOUGH)


func test_swap_id() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.ids.append(IdGenerator.generate(HR.IdGrade.CHEAP, sim.rng))
	var r := sim.swap_id(1, 1)
	assert_true(r["ok"])
	assert_eq(ps.id_index, 1)
	assert_eq(r["id"]["name"], ps.ids[1].name)
	assert_eq(sim.swap_id(1, 2)["reason"], FloorSim.BAD_INDEX)
	sim.start_id_check(1)
	if ps.status == HR.PlayerStatus.ID_CHECK:
		assert_eq(sim.swap_id(1, 0)["reason"], FloorSim.BUSY, "no swapping mid-check")


func test_id_check_quiz() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	_seat(sim, 1, HR.GameType.SLOTS)
	var r := sim.start_id_check(1, 4)
	assert_true(r["ok"])
	assert_false(r["auto_fail"])
	assert_eq(r["question"]["options"].size(), Tuning.ID_QUIZ_OPTIONS)
	assert_false(r["question"].has("correct_index"), "the answer stays on the host")
	assert_eq(ps.status, HR.PlayerStatus.ID_CHECK)
	assert_eq(sim.place_bet(1, &"t1", _min_bet(sim))["reason"], FloorSim.BUSY)
	assert_eq(sim.start_id_check(1)["reason"], FloorSim.BUSY)
	var checks := _events(&"id_check")
	assert_eq(checks.size(), 1)
	assert_eq(checks[0]["guard_id"], 4)
	var correct: int = ps.id_question["correct_index"]
	var a := sim.answer_id_check(1, correct)
	assert_true(a["ok"])
	assert_true(a["passed"])
	assert_eq(ps.status, HR.PlayerStatus.SEATED, "back to the table")
	assert_eq(_events(&"id_result")[0], {"pid": 1, "guard_id": 4, "passed": true, "reason": FloorSim.ID_CORRECT})
	assert_eq(sim.answer_id_check(1, correct)["reason"], FloorSim.NO_QUESTION)
	assert_true(ps.id_cleared(), "a passed check clears them crew-wide")
	sim.stand(1)
	assert_eq(sim.start_id_check(1)["reason"], FloorSim.CLEARED, "no second check back to back")
	ps.heat.add(Tuning.WATCHED_AT, &"test")
	assert_false(ps.id_cleared(), "drew new attention")
	sim.start_id_check(1)
	var wrong: int = (int(ps.id_question["correct_index"]) + 1) % Tuning.ID_QUIZ_OPTIONS
	assert_false(sim.answer_id_check(1, wrong)["passed"])
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(_events(&"id_result")[1]["reason"], FloorSim.ID_WRONG)


func test_id_check_times_out() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.start_id_check(1)
	sim.tick(Tuning.ID_QUIZ_SECONDS)
	assert_eq(ps.status, HR.PlayerStatus.ID_CHECK, "grace before the sim gives up")
	sim.tick(Tuning.ID_QUIZ_GRACE_SECONDS + 0.01)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(_events(&"id_result")[0]["reason"], FloorSim.ID_TIMEOUT)
	sim.start_id_check(1)
	var e := sim.expire_id_check(1)
	assert_true(e["ok"])
	assert_false(e["passed"])
	assert_eq(_events(&"id_result").size(), 2)
	assert_eq(sim.expire_id_check(1)["reason"], FloorSim.NO_QUESTION)


func test_id_check_auto_fails() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.current_id().flagged = true
	var r := sim.start_id_check(1)
	assert_true(r["auto_fail"])
	assert_eq(r["fail_reason"], FloorSim.ID_FLAGGED)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(_events(&"id_check")[0]["auto_fail"], true)
	assert_eq(_events(&"id_result")[0]["reason"], FloorSim.ID_FLAGGED)
	ps.current_id().burn()
	assert_eq(sim.start_id_check(1)["fail_reason"], FloorSim.ID_BURNED)
	ps.id_index = -1
	assert_eq(sim.start_id_check(1)["fail_reason"], FloorSim.ID_NONE)
	# A cheap card is sometimes spotted on sight, and the event says so.
	ps.ids.append(IdGenerator.generate(HR.IdGrade.CHEAP, sim.rng))
	ps.id_index = ps.ids.size() - 1
	var spotted := 0
	for i in 60:
		var c := sim.start_id_check(1)
		if c["auto_fail"]:
			assert_eq(c["fail_reason"], FloorSim.ID_SPOTTED)
			spotted += 1
		else:
			# A wrong answer, so the player never ends up cleared.
			sim.answer_id_check(1, (int(ps.id_question["correct_index"]) + 1) % Tuning.ID_QUIZ_OPTIONS)
	assert_between(spotted, 1, 30)


func test_report_seen_poster_match_once_per_sighting() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	var clean := sim.report_seen(1, {"guard_id": 2})
	assert_true(clean["ok"])
	assert_false(clean["matches_poster"])
	assert_false(clean["recognized"])
	var poster := sim.run.posters.print_poster(sim.run.casino_id(), 1, ps.outfit)
	var r := sim.report_seen(1, {"guard_id": 2})
	assert_true(r["matches_poster"])
	assert_eq(r["poster_id"], poster.id)
	assert_almost_eq(r["heat"], Tuning.POSTER_MATCH_HEAT)
	assert_eq(_events(&"poster_match").size(), 1)
	assert_almost_eq(sim.report_seen(1, {"guard_id": 3})["heat"], 0.0, 0.001, "same sighting")
	sim.tick(Tuning.POSTER_MATCH_REARM_SECONDS - 1.0)
	assert_almost_eq(sim.report_seen(1)["heat"], 0.0, 0.001, "not unseen long enough")
	sim.tick(Tuning.POSTER_MATCH_REARM_SECONDS)
	var p := sim.report_seen(1, {"pit_boss": true})
	assert_almost_eq(p["heat"], Tuning.POSTER_MATCH_HEAT * Tuning.PIT_BOSS_HEAT_MULT)
	assert_eq(_heat_events(HeatRules.POSTER_MATCH).size(), 2)
	# A poster in another casino doesn't count.
	var other := _sim(TOP + 1)
	other.run.posters.print_poster(sim.run.casino_id(), 1, other.player(1).outfit)
	assert_false(other.report_seen(1)["matches_poster"])


func test_outfit_change_rearms_poster_match_and_beats_recognition() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.run.posters.print_poster(sim.run.casino_id(), 1, ps.outfit)
	ps.heat.add(Tuning.SUSPECTED_AT, &"test")
	var seen := sim.report_seen(1)
	assert_true(seen["recognized"])
	assert_false(ps.poster_match_armed)
	sim.enter_zone(1, HR.ZoneType.RESTROOM, &"wc")
	ps.stash[0] = OutfitCatalog.staff_uniform()
	sim.change_to_stash(1, 0)
	assert_true(ps.poster_match_armed)
	var after := sim.report_seen(1)
	assert_false(after["recognized"])
	assert_false(after["matches_poster"])


func test_tear_and_deface_posters() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	var a := sim.run.posters.print_poster(sim.run.casino_id(), 1, ps.outfit)
	var b := sim.run.posters.print_poster(sim.run.casino_id(), 2, ps.stash[0])
	var elsewhere := sim.run.posters.print_poster(&"somewhere_else", 1, ps.outfit)
	assert_eq(sim.deface_poster(1, elsewhere.id)["reason"], FloorSim.UNKNOWN_POSTER)
	var d := sim.deface_poster(1, a.id)
	assert_true(d["ok"])
	assert_true(a.is_defaced(d["slot"]))
	assert_eq(_events(&"poster_defaced").size(), 1)
	assert_true(sim.deface_poster(1, a.id, HR.OutfitSlot.BOTTOM)["ok"] or a.is_defaced(HR.OutfitSlot.BOTTOM))
	assert_eq(sim.deface_poster(1, a.id, d["slot"])["reason"], FloorSim.NO_SLOT, "already defaced")
	var t := sim.tear_poster(1, b.id, Vector3(1, 2, 3))
	assert_true(t["ok"])
	assert_null(sim.run.posters.get_poster(b.id))
	assert_eq(_events(&"poster_removed")[0]["poster_id"], b.id)
	var noise: Dictionary = _events(&"noise").back()
	assert_eq(noise["kind"], &"tear_poster")
	assert_eq(noise["position"], Vector3(1, 2, 3))
	assert_eq(sim.tear_poster(1, b.id)["reason"], FloorSim.UNKNOWN_POSTER)


# --- Capture ----------------------------------------------------------------

func test_caught_stands_and_carries() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	_seat(sim, 1, HR.GameType.HIGH_LOW)
	sim.start_high_low(1, &"t1", _min_bet(sim))
	var r := sim.caught(1, 6)
	assert_true(r["ok"])
	assert_eq(ps.status, HR.PlayerStatus.CARRIED)
	assert_eq(ps.table_id, &"")
	assert_null(ps.high_low, "round settled")
	assert_eq(_events(&"caught")[0], {"pid": 1, "guard_id": 6})
	assert_eq(sim.caught(1)["reason"], FloorSim.NOT_AVAILABLE)
	assert_eq(sim.sit(1, &"t1")["reason"], FloorSim.BUSY)
	assert_false(sim.finished, "a solo player isn't a crew wipe")


func test_caught_during_id_check_drops_it() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.start_id_check(1)
	sim.caught(1)
	assert_true(ps.id_question.is_empty())
	assert_eq(ps.status, HR.PlayerStatus.CARRIED)
	sim.tick(Tuning.ID_QUIZ_SECONDS + 1.0)
	assert_eq(_events(&"id_result").size(), 0)


func test_freed_by_teammate() -> void:
	var sim := _sim(TOP, 1, 3)
	sim.caught(1)
	assert_eq(sim.freed(1, 1)["reason"], FloorSim.SAME_PLAYER)
	assert_eq(sim.freed(1, 9)["reason"], FloorSim.UNKNOWN_PLAYER)
	sim.caught(3)
	assert_eq(sim.freed(1, 3)["reason"], FloorSim.NOT_AVAILABLE, "a carried player can't tackle")
	var r := sim.freed(1, 2)
	assert_true(r["ok"])
	assert_eq(sim.player(1).status, HR.PlayerStatus.FREE)
	assert_gte(sim.player(2).heat.value, Tuning.WANTED_AT)
	assert_eq(_heat_events(HeatRules.TACKLE).size(), 1)
	assert_eq(_events(&"poster")[0]["pid"], 2, "the tackler goes Wanted and gets a poster")
	assert_eq(_events(&"freed")[0], {"pid": 1, "tackler": 2})
	assert_eq(sim.freed(1, 2)["reason"], FloorSim.NOT_CARRIED)
	# Released by the guard itself: no tackler, no Heat.
	var g := sim.freed(3, 0)
	assert_true(g["ok"])
	assert_eq(_heat_events(HeatRules.TACKLE).size(), 1)


func test_back_room_detains_and_rejoins() -> void:
	var sim := _sim(TOP + 1)
	var ps := sim.player(1)
	ps.heat.add(60.0, &"test")
	var card := ps.current_id()
	var pocket := ps.wallet.pocket
	assert_eq(pocket, CasinoLadder.start_chips(TOP + 1))
	sim.caught(1)
	var r := sim.reach_back_room(1)
	assert_true(r["ok"])
	assert_eq(r["chips_lost"], pocket)
	assert_eq(r["strikes"], 1)
	assert_false(r["thrown_out"])
	assert_false(r["curb"])
	assert_eq(ps.wallet.pocket, 0)
	assert_true(card.burned)
	assert_eq(ps.status, HR.PlayerStatus.DETAINED)
	assert_almost_eq(ps.heat.value, 0.0)
	assert_eq(sim.run.strikes, 1)
	assert_eq(_events(&"strike")[0]["strikes"], 1)
	assert_eq(_events(&"detained")[0]["chips_lost"], pocket)
	assert_true(_events(&"detained")[0]["id_burned"])
	assert_eq(sim.reach_back_room(1)["reason"], FloorSim.NOT_CARRIED)
	assert_eq(sim.caught(1)["reason"], FloorSim.NOT_AVAILABLE)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT - 0.5)
	assert_eq(ps.status, HR.PlayerStatus.DETAINED)
	sim.tick(1.0)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	var rejoined := _events(&"rejoined")
	assert_eq(rejoined.size(), 1)
	assert_true(rejoined[0]["new_id"])
	assert_eq(rejoined[0]["from"], &"back_room")
	assert_eq(rejoined[0]["spawn"], &"entrance", "back in at the entrance, not outside the security office")
	assert_eq(ps.zone, HR.ZoneType.ENTRANCE)
	assert_almost_eq(ps.heat.value, 0.0, 0.001, "processed: Heat 0")
	assert_eq(ps.ids.size(), 2)
	assert_eq(ps.current_id().grade, Tuning.REJOIN_ID_GRADE)
	assert_true(ps.current_id().passes_check())


func test_rejoin_switches_to_a_held_card() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.ids.append(IdGenerator.generate(HR.IdGrade.FLAWLESS, sim.rng))
	sim.caught(1)
	sim.reach_back_room(1)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_false(_events(&"rejoined")[0]["new_id"])
	assert_eq(ps.id_index, 1)
	assert_eq(ps.ids.size(), 2)


func test_three_strikes_throw_out() -> void:
	var sim := _sim(TOP + 1)
	sim.run.bank = 1000  # not broke after losing the pocket, so only strikes count
	for i in Tuning.STRIKES_TO_THROW_OUT:
		assert_true(sim.caught(1)["ok"])
		var r := sim.reach_back_room(1)
		if i < Tuning.STRIKES_TO_THROW_OUT - 1:
			assert_false(r["thrown_out"])
			sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
			assert_eq(sim.caught(1)["reason"], FloorSim.NOT_AVAILABLE, "rejoin grace")
			sim.tick(Tuning.REJOIN_GRACE_SECONDS + 0.1)
		else:
			assert_true(r["thrown_out"])
	assert_true(sim.finished)
	assert_eq(sim.outcome, &"thrown_out")
	assert_eq(_events(&"thrown_out")[0], {"from": TOP + 1, "to": TOP + 2, "cause": &"strikes"})
	assert_eq(sim.run.rung, TOP + 2)
	assert_eq(sim.run.strikes, 0)
	assert_eq(sim.sit(1, &"x")["reason"], FloorSim.FINISHED)
	var elapsed := sim.run.elapsed_seconds
	sim.tick(1.0)
	assert_eq(sim.run.elapsed_seconds, elapsed, "a finished sim doesn't tick")


func test_whole_crew_held_throws_out() -> void:
	var sim := _sim(TOP, 1, 2)
	sim.caught(1)
	assert_false(sim.finished)
	sim.reach_back_room(1)
	assert_false(sim.finished)
	sim.caught(2)
	assert_true(sim.finished)
	assert_eq(_events(&"thrown_out")[0]["cause"], &"crew_detained")
	assert_eq(sim.run.rung, TOP + 1)


func test_sals_curb_timeout() -> void:
	var sim := _sim(BOTTOM, 1, 2)
	sim.caught(1)
	sim.caught(2)
	assert_false(sim.finished)
	assert_eq(_events(&"curb").size(), 1)
	assert_eq(_events(&"thrown_out").size(), 0)
	for pid in [1, 2]:
		assert_eq(sim.player(pid).status, HR.PlayerStatus.ON_CURB)
	assert_eq(sim.run.rung, BOTTOM)
	sim.tick(Tuning.CURB_TIMEOUT + 0.1)
	for pid in [1, 2]:
		assert_eq(sim.player(pid).status, HR.PlayerStatus.FREE)
		assert_eq(sim.player(pid).zone, HR.ZoneType.ENTRANCE)
	assert_eq(_events(&"rejoined").size(), 2)
	assert_eq(_events(&"rejoined")[0]["from"], &"curb")


# --- Bank, crew play, climbing ----------------------------------------------

func test_cash_out() -> void:
	var sim := _sim(TOP + 2)
	var ps := sim.player(1)
	_rich(sim, 1, 1000)
	var start := ps.wallet.pocket
	assert_eq(sim.cash_out(1, 100)["reason"], FloorSim.WRONG_ZONE)
	sim.enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	assert_eq(sim.cash_out(1, -5)["reason"], Cashier.BAD_AMOUNT)
	assert_eq(sim.cash_out(1, ps.wallet.pocket + 1)["reason"], Cashier.NOT_ENOUGH)
	var r := sim.cash_out(1, 1000)
	assert_true(r["ok"])
	assert_eq(r["banked"], 1000)
	assert_eq(sim.run.bank, 1000)
	assert_eq(r["bank"], 1000)
	assert_eq(ps.wallet.pocket, start - 1000)
	assert_eq(_events(&"banked")[0]["amount"], 1000)
	# Large cash-out Heat (max bet 500 at rung 3: 1000 is under 10 bets).
	assert_almost_eq(r["heat"], 0.0)
	_rich(sim, 1, 20000)
	var big := sim.cash_out(1, 10000)
	assert_almost_eq(big["heat"], HeatRules.cash_out_heat(10000, _max_bet(sim)))
	assert_gt(big["heat"], 0.0)
	assert_eq(_heat_events(HeatRules.CASH_OUT).size(), 1)


func test_withdraw_takes_chips_back_out_of_the_bank() -> void:
	var sim := _sim(TOP + 2)
	var ps := sim.player(1)
	var start := ps.wallet.pocket
	sim.run.bank = 300
	assert_eq(sim.withdraw(1, 100)["reason"], FloorSim.WRONG_ZONE)
	sim.enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	assert_eq(sim.withdraw(1, 0)["reason"], FloorSim.BAD_AMOUNT)
	assert_eq(sim.withdraw(1, 301)["reason"], FloorSim.NOT_ENOUGH)
	assert_eq(sim.withdraw(9, 10)["reason"], FloorSim.UNKNOWN_PLAYER)
	var r := sim.withdraw(1, 120)
	_check_ok_shape(r)
	assert_true(r["ok"])
	assert_eq(r["amount"], 120)
	assert_eq(r["bank"], 180)
	assert_eq(sim.run.bank, 180)
	assert_eq(ps.wallet.pocket, start + 120)
	assert_eq(r["pocket"], ps.wallet.pocket)
	assert_eq(_events(&"withdrawn"), [{"pid": 1, "amount": 120, "bank": 180}])
	assert_eq(_events(&"chips").back()["delta"], 120)
	assert_eq(ps.wallet.lifetime_banked, 0, "taking chips out isn't banking")
	_seat(sim, 1, HR.GameType.SLOTS)
	assert_eq(sim.withdraw(1, 10)["reason"], FloorSim.BUSY)


func test_withdraw_never_touches_the_top_score() -> void:
	var sim := _sim(TOP)
	sim.enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	sim.cash_out(1, 500)
	assert_eq(sim.run.top_banked, 500)
	assert_eq(sim.withdraw(1, 100)["reason"], FloorSim.NOT_ENOUGH, "banked at the top is score")
	assert_eq(sim.run.top_banked, 500)


## Lose the pocket the way a back-room trip does.
func _go_broke(sim: FloorSim) -> void:
	for pid: int in sim.player_ids():
		sim.player(pid).wallet.lose_pocket()


func test_broke_crew_above_sals_is_walked_out() -> void:
	var sim := _sim(TOP + 2)
	_go_broke(sim)
	sim.tick(0.1)
	var notes := _events(&"notify")
	assert_eq(notes.size(), 1, "a warning first")
	assert_eq(notes[0]["kind"], &"broke")
	assert_eq(notes[0]["pid"], 0)
	sim.tick(Tuning.BROKE_GRACE_SECONDS - 0.5)
	assert_false(sim.finished, "a grace period to read it")
	sim.tick(1.0)
	assert_true(sim.finished)
	assert_eq(sim.outcome, &"thrown_out")
	assert_eq(_events(&"thrown_out")[0], {"from": TOP + 2, "to": BOTTOM, "cause": &"broke"}, "nothing banked: back to Sal's")
	assert_eq(sim.run.rung, BOTTOM)
	assert_eq(_events(&"notify").size(), 1, "warned once")


func test_broke_crew_drops_to_where_the_bank_covers_a_bet() -> void:
	var sim := _sim(TOP + 2)
	_go_broke(sim)
	# Under rung 3's and rung 4's min bets, enough for the Rusty Spur (rung 5).
	sim.run.bank = int(CasinoLadder.casino(TOP + 4)["min_bet"])
	assert_lt(sim.run.bank, int(CasinoLadder.casino(TOP + 3)["min_bet"]))
	sim.tick(0.1)
	sim.tick(Tuning.BROKE_GRACE_SECONDS + 0.1)
	assert_eq(_events(&"thrown_out")[0]["to"], TOP + 4)


func test_broke_crew_with_a_bank_or_at_the_top_stays() -> void:
	var banked := _sim(TOP + 2)
	_go_broke(banked)
	banked.run.bank = _min_bet(banked)
	banked.tick(0.1)
	banked.tick(Tuning.BROKE_GRACE_SECONDS * 2.0)
	assert_false(banked.finished, "it can take chips out of the bank")
	var top := _sim(TOP)
	_go_broke(top)
	top.tick(0.1)
	top.tick(Tuning.BROKE_GRACE_SECONDS * 2.0)
	assert_false(top.finished, "the top's exit (end of run) is always open")
	var bottom := _sim(BOTTOM)
	_go_broke(bottom)
	bottom.tick(Tuning.BROKE_GRACE_SECONDS * 2.0)
	assert_false(bottom.finished, "Sal's bails a broke crew out instead")


func test_broke_countdown_waits_for_the_crew_to_be_back_on_the_floor() -> void:
	var sim := _sim(TOP + 2)
	sim.caught(1)
	sim.reach_back_room(1)
	assert_eq(sim.player(1).wallet.pocket, 0)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_eq(sim.player(1).status, HR.PlayerStatus.FREE, "rejoined, broke")
	assert_false(sim.finished, "no countdown while detained, and the warning comes first")
	assert_eq(_events(&"notify").filter(func(d: Dictionary) -> bool: return d["kind"] == &"broke").size(), 1)
	sim.player(1).rejoin_grace = 0.0  # skip the after-rejoin grace: grabbed mid-countdown
	assert_true(sim.caught(1)["ok"])
	sim.tick(Tuning.BROKE_GRACE_SECONDS * 2.0)
	assert_false(sim.finished, "carried: the countdown stopped")


func test_cash_out_at_top_scores() -> void:
	var sim := _sim(TOP)
	sim.enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	sim.cash_out(1, 500)
	assert_eq(sim.run.top_banked, 500)
	assert_eq(sim.run.bank, 0)
	assert_eq(sim.score(), 500)


func test_cash_out_past_cap_flags_and_notifies() -> void:
	var sim := _sim(TOP + 2)
	var ps := sim.player(1)
	sim.enter_zone(1, HR.ZoneType.CASHIER, &"cage")
	_rich(sim, 1, 100000)
	var cap := ps.current_id().cap
	var r := sim.cash_out(1, cap + 1)
	assert_true(r["flagged"])
	assert_true(ps.current_id().flagged)
	var notes := _events(&"notify")
	assert_eq(notes.size(), 1)
	assert_eq(notes[0]["kind"], &"flagged")
	assert_eq(notes[0]["pid"], 1)
	assert_eq(sim.cash_out(1, 10)["reason"], Cashier.BAD_ID)


func test_seated_player_cannot_cash_out() -> void:
	var sim := _sim()
	_seat(sim, 1, HR.GameType.SLOTS)
	sim.player(1).zone = HR.ZoneType.CASHIER
	assert_eq(sim.cash_out(1, 10)["reason"], FloorSim.BUSY)


func test_throw_chips() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	var pos := Vector3(3, 0, 3)
	var r := sim.distraction(1, HR.Distraction.THROW_CHIPS, pos)
	var cost := maxi(Tuning.THROW_CHIPS_MIN, floori(Tuning.START_CHIPS * Tuning.THROW_CHIPS_FRACTION))
	assert_true(r["ok"])
	assert_eq(r["cost"], cost)
	assert_eq(ps.wallet.pocket, Tuning.START_CHIPS - cost)
	assert_eq(_events(&"noise")[0], {"position": pos, "radius": float(Tuning.NOISE_RADIUS[&"throw_chips"]), "kind": &"throw_chips", "pid": 1})
	var rush: Dictionary = _events(&"crowd_rush")[0]
	assert_eq(rush["position"], pos)
	assert_almost_eq(rush["radius"], Tuning.THROW_CHIPS_BLOCK_RADIUS)
	assert_almost_eq(rush["seconds"], Tuning.THROW_CHIPS_BLOCK_SECONDS)
	_rich(sim, 1, 100000)
	var big := sim.distraction(1, HR.Distraction.THROW_CHIPS, pos)
	assert_eq(big["cost"], floori((Tuning.START_CHIPS - cost + 100000) * Tuning.THROW_CHIPS_FRACTION))
	ps.wallet.lose_pocket()
	ps.wallet.add(Tuning.THROW_CHIPS_MIN - 1)
	assert_eq(sim.distraction(1, HR.Distraction.THROW_CHIPS, pos)["reason"], FloorSim.NOT_ENOUGH)


func test_knock_over_and_bump_guard() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	var k := sim.distraction(1, HR.Distraction.KNOCK_OVER, Vector3.ONE)
	assert_almost_eq(k["heat"], Tuning.KNOCK_OVER_HEAT)
	assert_eq(_events(&"noise")[0]["kind"], &"knock_over")
	var b := sim.distraction(1, HR.Distraction.BUMP_GUARD, Vector3.ONE)
	assert_almost_eq(b["heat"], Tuning.BUMP_GUARD_HEAT)
	assert_eq(_events(&"noise")[1]["kind"], &"bump")
	assert_almost_eq(ps.heat.value, Tuning.KNOCK_OVER_HEAT + Tuning.BUMP_GUARD_HEAT)


func test_slot_alarm_cooldown_is_crew_wide() -> void:
	var sim := _sim(TOP, 1, 2)
	assert_true(sim.distraction(1, HR.Distraction.SLOT_ALARM, Vector3.ZERO)["ok"])
	var noise: Dictionary = _events(&"noise")[0]
	assert_eq(noise["kind"], &"slot_jackpot")
	assert_almost_eq(noise["radius"], float(Tuning.NOISE_RADIUS[&"slot_jackpot"]))
	assert_eq(sim.distraction(2, HR.Distraction.SLOT_ALARM, Vector3.ZERO)["reason"], FloorSim.COOLDOWN)
	sim.tick(Tuning.SLOT_ALARM_COOLDOWN)
	assert_true(sim.distraction(2, HR.Distraction.SLOT_ALARM, Vector3.ZERO)["ok"])


func test_fire_alarm() -> void:
	var sim := _sim(TOP, 1, 2)
	var t := _seat(sim, 2, HR.GameType.ROULETTE)
	var r := sim.distraction(1, HR.Distraction.FIRE_ALARM, Vector3.ZERO)
	assert_true(r["ok"])
	assert_true(sim.fire_alarm_active())
	assert_true(t.closed)
	assert_eq(sim.player(2).status, HR.PlayerStatus.FREE, "stood up")
	assert_eq(sim.sit(2, &"t1")["reason"], FloorSim.TABLE_CLOSED)
	assert_eq(_events(&"fire_alarm")[0]["active"], true)
	assert_true(sim.register_table(&"late", HR.GameType.SLOTS, &"a").closed)
	assert_eq(sim.distraction(2, HR.Distraction.FIRE_ALARM, Vector3.ZERO)["reason"], FloorSim.USED)
	sim.tick(Tuning.FIRE_ALARM_SECONDS + 0.1)
	assert_false(sim.fire_alarm_active())
	assert_false(t.closed)
	assert_eq(_events(&"fire_alarm")[1]["active"], false)
	assert_eq(sim.distraction(2, HR.Distraction.FIRE_ALARM, Vector3.ZERO)["reason"], FloorSim.USED, "once per visit")


func test_give_chips() -> void:
	var sim := _sim(TOP, 1, 2)
	var r := sim.give_chips(1, 2, 300)
	assert_true(r["ok"])
	assert_eq(r["from_pocket"], Tuning.START_CHIPS - 300)
	assert_eq(r["to_pocket"], Tuning.START_CHIPS + 300)
	assert_eq(_events(&"chips_given")[0], {"from": 1, "to": 2, "amount": 300})
	assert_eq(sim.give_chips(1, 2, 0)["reason"], FloorSim.BAD_AMOUNT)
	assert_eq(sim.give_chips(1, 2, -3)["reason"], FloorSim.BAD_AMOUNT)
	assert_eq(sim.give_chips(1, 2, 999999)["reason"], FloorSim.NOT_ENOUGH)
	sim.caught(2)
	assert_eq(sim.give_chips(1, 2, 10)["reason"], FloorSim.BUSY)
	assert_eq(sim.give_chips(2, 1, 10)["reason"], FloorSim.BUSY)


func test_chips_events_track_the_pocket() -> void:
	var sim := _sim()
	sim.distraction(1, HR.Distraction.THROW_CHIPS, Vector3.ZERO)
	var chips: Dictionary = _events(&"chips")[0]
	assert_eq(chips["pid"], 1)
	assert_eq(chips["pocket"], sim.player(1).wallet.pocket)
	assert_lt(chips["delta"], 0)


func test_try_climb() -> void:
	var sim := _sim(TOP + 3, 1, 2)
	assert_eq(sim.try_climb()["reason"], FloorSim.CANT_CLIMB)
	sim.run.bank = CasinoLadder.buy_in_to_leave(TOP + 3)
	var r := sim.try_climb()
	assert_eq(r["reason"], FloorSim.NOT_AT_EXIT)
	assert_eq(r["missing"], [1, 2])
	sim.enter_zone(1, HR.ZoneType.EXIT, &"exit")
	assert_eq(sim.try_climb()["missing"], [2])
	# A detained player comes along.
	sim.caught(2)
	sim.reach_back_room(2)
	var ok := sim.try_climb()
	assert_true(ok["ok"], str(ok))
	assert_eq(ok["from"], TOP + 3)
	assert_eq(ok["to"], TOP + 2)
	assert_eq(ok["cost"], CasinoLadder.buy_in_to_leave(TOP + 3))
	assert_true(sim.finished)
	assert_eq(sim.outcome, &"climbed")
	assert_eq(sim.run.bank, 0)
	assert_eq(_events(&"climbed")[0], {"from": TOP + 3, "to": TOP + 2, "cost": ok["cost"]})
	assert_eq(sim.try_climb()["reason"], FloorSim.FINISHED)


func test_bailout_at_sals_only() -> void:
	var sim := _sim(BOTTOM, 1, 2)
	for pid in [1, 2]:
		sim.player(pid).wallet.lose_pocket()
	sim.tick(0.1)
	for pid in [1, 2]:
		assert_eq(sim.player(pid).wallet.pocket, Tuning.BAILOUT_CHIPS)
	assert_eq(_events(&"notify")[0]["kind"], &"bailout")
	sim.tick(0.1)
	assert_eq(sim.player(1).wallet.pocket, Tuning.BAILOUT_CHIPS, "only when broke")
	var other := _sim(BOTTOM - 1)
	other.player(1).wallet.lose_pocket()
	other.tick(0.1)
	assert_eq(other.player(1).wallet.pocket, 0)
	var banked := _sim(BOTTOM)
	banked.player(1).wallet.lose_pocket()
	banked.run.bank = int(banked.casino()["min_bet"])
	banked.tick(0.1)
	assert_eq(banked.player(1).wallet.pocket, 0, "the bank still covers a bet")


func test_forger_moves() -> void:
	var sim := _sim()
	var first := sim.forger.location()
	sim.tick(Tuning.FORGER_MOVE_SECONDS + 0.01)
	var moved := _events(&"forger_moved")
	assert_eq(moved.size(), 1)
	assert_ne(moved[0]["location"], first)
	assert_eq(sim.snapshot()["forger_location"], sim.forger.location())


# --- Playtest rules: loitering, scoring, rejoin grace, crew-wide ID clearance ----

func test_add_player_uses_the_casinos_start_chips() -> void:
	for rung in range(TOP, BOTTOM + 1):
		var sim := _sim(rung)
		assert_eq(sim.player(1).wallet.pocket, int(Tuning.CASINOS[rung - TOP]["start_chips"]), "rung %d" % rung)
		assert_eq(sim.player(1).wallet.pocket, CasinoLadder.start_chips(rung))
	assert_eq(CasinoLadder.start_chips(TOP), Tuning.START_CHIPS)
	assert_eq(CasinoLadder.start_chips(99), Tuning.START_CHIPS, "fallback")
	# Bottom rungs start small enough to need a real climb.
	assert_lte(CasinoLadder.start_chips(BOTTOM), CasinoLadder.buy_in_to_leave(BOTTOM) / 2)


func test_loitering_off_the_tables_builds_heat_after_the_grace() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.enter_zone(1, HR.ZoneType.BAR, &"bar")
	ps.heat.add(50.0, &"test")
	sim.tick(Tuning.LOITER_GRACE_SECONDS - 1.0)
	assert_eq(_heat_events(HeatRules.LOITERING).size(), 0)
	assert_lt(ps.heat.value, 50.0, "cooling off at the bar inside the grace")
	assert_false(ps.is_loitering())
	var before := ps.heat.value
	log.clear()
	for i in 20:
		sim.tick(0.5)
	assert_true(ps.is_loitering())
	assert_gt(_heat_events(HeatRules.LOITERING).size(), 0)
	assert_gt(ps.heat.value, before, "security notices someone who isn't playing")
	log.clear()
	sim.tick(0.5)
	assert_eq(_heat_events(HeatRules.OFF_TABLE).size(), 0, "the bar stopped cooling once loitering started")
	assert_eq(_heat_events(HeatRules.LOITERING).size(), 1)
	assert_true(sim.snapshot()["players"][1]["loitering"])


func test_sitting_and_betting_reset_loitering_once_per_play() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.register_table(&"s1", HR.GameType.SLOTS, &"slots")
	sim.register_table(&"s2", HR.GameType.SLOTS, &"slots")
	sim.tick(Tuning.LOITER_GRACE_SECONDS + 5.0)
	assert_true(ps.is_loitering())
	sim.sit(1, &"s1")
	assert_almost_eq(ps.loiter_seconds, 0.0, 0.001, "sitting down resets it")
	sim.tick(Tuning.LOITER_GRACE_SECONDS + 1.0)
	assert_true(ps.is_loitering(), "sitting at a slot without playing")
	log.clear()
	sim.tick(1.0)
	assert_eq(_heat_events(HeatRules.SLOT_BLEND).size(), 0, "no blending in without playing")
	assert_eq(_heat_events(HeatRules.LOITERING).size(), 1)
	sim.stand(1)
	sim.sit(1, &"s2")
	assert_true(ps.is_loitering(), "standing up and sitting again doesn't reset it a second time")
	assert_true(sim.place_bet(1, &"s2", _min_bet(sim))["ok"])
	assert_almost_eq(ps.loiter_seconds, 0.0, 0.001, "a bet resets it")
	log.clear()
	sim.tick(1.0)
	assert_eq(_heat_events(HeatRules.SLOT_BLEND).size(), 1, "playing slots blends in again")
	sim.stand(1)
	sim.tick(10.0)
	sim.sit(1, &"s1")
	assert_almost_eq(ps.loiter_seconds, 0.0, 0.001, "after a bet the next sit resets it again")


func test_rounds_count_as_play() -> void:
	var sim := _sim(TOP + 2)
	var ps := sim.player(1)
	_seat(sim, 1, HR.GameType.HIGH_LOW, &"hl")
	sim.tick(20.0)
	sim.start_high_low(1, &"hl", _min_bet(sim))
	assert_almost_eq(ps.loiter_seconds, 0.0)
	sim.tick(20.0)
	sim.high_low_guess(1, true)
	assert_almost_eq(ps.loiter_seconds, 0.0, 0.001, "a guess is play")


func test_waiting_at_the_exit_below_the_top_is_not_loitering() -> void:
	var sim := _sim(TOP + 2)
	sim.enter_zone(1, HR.ZoneType.EXIT, &"door")
	sim.tick(Tuning.LOITER_GRACE_SECONDS * 3.0)
	assert_false(sim.player(1).is_loitering(), "waiting for the crew to climb")
	var top := _sim(TOP)
	top.enter_zone(1, HR.ZoneType.EXIT, &"door")
	top.tick(Tuning.LOITER_GRACE_SECONDS + 1.0)
	assert_true(top.player(1).is_loitering(), "at the top the exit is no place to farm time")


func test_top_seconds_only_count_while_the_crew_can_play() -> void:
	var sim := _sim(TOP, 1, 2)
	sim.tick(10.0)
	assert_almost_eq(sim.run.top_seconds, 10.0)
	assert_true(sim.snapshot()["run"]["scoring"])
	# Whole crew held: one carried still counts, all detained doesn't.
	sim.run.bank = 0
	for pid in [1, 2]:
		sim.player(pid).wallet.add(100000)
	sim.caught(1)
	sim.tick(1.0)
	assert_almost_eq(sim.run.top_seconds, 11.0, 0.001, "one carried, one on the floor")
	sim.reach_back_room(1)
	sim.caught(2)
	assert_true(sim.finished or sim.player(2).status == HR.PlayerStatus.CARRIED)
	# A solo crew in the back room scores nothing while held.
	var solo := _sim(TOP)
	solo.caught(1)
	solo.reach_back_room(1)
	solo.tick(Tuning.BACK_ROOM_TIMEOUT - 1.0)
	assert_almost_eq(solo.run.top_seconds, 0.0, 0.001, "detained: no score for time")
	assert_false(solo.snapshot()["run"]["scoring"])


func test_a_broke_crew_at_the_top_scores_no_time() -> void:
	var sim := _sim(TOP)
	var ps := sim.player(1)
	ps.wallet.spend(ps.wallet.pocket - (_min_bet(sim) - 1))
	sim.tick(120.0)
	assert_almost_eq(sim.run.top_seconds, 0.0, 0.001, "idling broke at the top farms nothing")
	assert_eq(sim.score(), 0)
	sim.run.bank = _min_bet(sim)
	sim.tick(60.0)
	assert_almost_eq(sim.run.top_seconds, 60.0, 0.001, "chips in the bank to withdraw: still in the game")
	sim.run.bank = 0
	ps.wallet.add(1)
	sim.tick(1.0)
	assert_almost_eq(sim.run.top_seconds, 61.0, 0.001, "a pocket covering the min bet")


func test_rejoin_grace_keeps_guards_off_then_ends() -> void:
	var sim := _sim(TOP + 1)
	sim.run.bank = 1000
	var ps := sim.player(1)
	sim.caught(1)
	sim.reach_back_room(1)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_true(ps.is_available())
	assert_false(ps.is_targetable(), "just processed: guards leave them alone")
	assert_almost_eq(ps.rejoin_grace, Tuning.REJOIN_GRACE_SECONDS)
	assert_eq(_events(&"rejoined")[0]["grace"], Tuning.REJOIN_GRACE_SECONDS)
	assert_false(sim.snapshot()["players"][1]["targetable"])
	assert_eq(sim.caught(1)["reason"], FloorSim.NOT_AVAILABLE)
	assert_eq(sim.start_id_check(1)["reason"], FloorSim.NOT_AVAILABLE)
	# Their look on a poster adds no Heat during the grace.
	sim.run.posters.print_poster(sim.run.casino_id(), 1, ps.outfit)
	var seen := sim.report_seen(1, {"guard_id": 2})
	assert_true(seen["matches_poster"])
	assert_almost_eq(seen["heat"], 0.0)
	sim.tick(Tuning.REJOIN_GRACE_SECONDS)
	assert_true(ps.is_targetable(), "grace over")
	assert_true(sim.caught(1)["ok"])


func test_rejoin_grace_ends_early_on_sitting_or_reaching_watched() -> void:
	var sim := _sim(TOP + 1)
	sim.run.bank = 1000
	var ps := sim.player(1)
	sim.register_table(&"t1", HR.GameType.ROULETTE, &"a")
	sim.caught(1)
	sim.reach_back_room(1)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_false(ps.is_targetable())
	sim.sit(1, &"t1")
	assert_true(ps.is_targetable(), "back at a table: back in the game")
	sim.stand(1)
	sim.tick(Tuning.REJOIN_GRACE_SECONDS)
	sim.caught(1)
	sim.reach_back_room(1)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_false(ps.is_targetable())
	ps.heat.add(Tuning.WATCHED_AT, HeatRules.BUMP_GUARD)
	assert_true(ps.is_targetable(), "drew attention: grace over")


func test_curb_rejoin_also_comes_back_at_the_entrance_with_grace() -> void:
	var sim := _sim(BOTTOM)
	var ps := sim.player(1)
	for i in Tuning.STRIKES_TO_THROW_OUT:
		if ps.rejoin_grace > 0.0:
			sim.tick(ps.rejoin_grace + 0.01)
		sim.caught(1)
		sim.reach_back_room(1)
		if ps.status == HR.PlayerStatus.DETAINED:
			sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_eq(ps.status, HR.PlayerStatus.ON_CURB)
	sim.tick(Tuning.CURB_TIMEOUT + 0.1)
	var last: Dictionary = _events(&"rejoined").back()
	assert_eq(last["from"], &"curb")
	assert_eq(last["spawn"], &"entrance")
	assert_eq(ps.zone, HR.ZoneType.ENTRANCE)
	assert_false(ps.is_targetable())


func test_passed_check_clears_the_player_crew_wide() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(Tuning.SUSPECTED_AT + 5.0, &"test")
	sim.start_id_check(1, 3)
	sim.answer_id_check(1, int(ps.id_question["correct_index"]))
	assert_true(ps.id_cleared())
	assert_eq(ps.id_cleared_level, HR.HeatLevel.SUSPECTED)
	assert_true(sim.snapshot()["players"][1]["id_cleared"])
	var again := sim.start_id_check(1, 4)
	assert_false(again["ok"], "a second guard doesn't check them back to back")
	assert_eq(again["reason"], FloorSim.CLEARED)
	assert_eq(_events(&"id_check").size(), 1)
	# Hotter within the same level: still cleared. Wanted: not.
	ps.heat.add(10.0, &"test")
	assert_true(ps.id_cleared())
	ps.heat.add(Tuning.WANTED_AT, &"test")
	assert_false(ps.id_cleared(), "rose above the level they passed at")


func test_clearance_follows_the_lowest_level_since() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(Tuning.SUSPECTED_AT + 5.0, &"test")
	sim.start_id_check(1)
	sim.answer_id_check(1, int(ps.id_question["correct_index"]))
	ps.heat.add(-20.0, &"test")
	assert_eq(ps.level(), HR.HeatLevel.WATCHED)
	assert_true(ps.id_cleared())
	ps.heat.add(20.0, &"test")
	assert_false(ps.id_cleared(), "cooled to Watched then back to Suspected: check again")
	assert_true(sim.start_id_check(1)["ok"])


func test_new_poster_match_ends_the_clearance() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	sim.start_id_check(1)
	sim.answer_id_check(1, int(ps.id_question["correct_index"]))
	assert_true(ps.id_cleared())
	sim.report_seen(1)
	assert_true(ps.id_cleared(), "no poster yet")
	sim.run.posters.print_poster(sim.run.casino_id(), 1, ps.outfit)
	sim.report_seen(1)
	assert_false(ps.id_cleared(), "a new poster match")
	# Passing while matching a poster: the same match doesn't end it.
	sim.start_id_check(1)
	sim.answer_id_check(1, int(ps.id_question["correct_index"]))
	assert_true(ps.id_cleared())
	assert_true(ps.id_cleared_poster)
	sim.report_seen(1)
	assert_true(ps.id_cleared(), "the poster they passed with")


func test_clearance_resets_on_rejoin_and_new_visit() -> void:
	var sim := _sim(TOP + 1)
	sim.run.bank = 1000
	var ps := sim.player(1)
	sim.start_id_check(1)
	sim.answer_id_check(1, int(ps.id_question["correct_index"]))
	assert_true(ps.id_cleared())
	sim.caught(1)
	sim.reach_back_room(1)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_false(ps.id_cleared(), "processed: a clean slate")
	ps.id_cleared_level = 0
	var next := FloorSim.new(sim.run, 2, [ps])
	assert_false(next.player(1).id_cleared(), "a new casino doesn't know them")


func test_snapshot_says_whether_the_casino_has_cameras() -> void:
	var apex := _sim(TOP)
	assert_true(CasinoLadder.has_security(TOP, HR.SecurityType.CAMERA))
	assert_true(CasinoLadder.has_security(TOP, HR.SecurityType.HEAD_OF_SECURITY))
	assert_true(apex.snapshot()["run"]["has_cameras"])
	var sals := _sim(BOTTOM)
	assert_false(CasinoLadder.has_security(BOTTOM, HR.SecurityType.CAMERA), "no cameras to follow you at Sal's")
	assert_true(CasinoLadder.has_security(BOTTOM, HR.SecurityType.FLOOR_GUARD))
	assert_false(CasinoLadder.has_security(99, HR.SecurityType.FLOOR_GUARD), "no such rung")
	assert_false(sals.snapshot()["run"]["has_cameras"])
	assert_true(_sim(TOP + 3).snapshot()["run"]["has_cameras"], "Neon Oasis has the first cameras")
	assert_eq(sals.snapshot()["run"]["security"], [HR.SecurityType.FLOOR_GUARD])


func test_climb_needs_a_stake_for_the_casino_above() -> void:
	var sim := _sim(TOP + 3)
	var ps := sim.player(1)
	var buy_in := CasinoLadder.buy_in_to_leave(TOP + 3)
	sim.run.bank = buy_in
	ps.wallet.spend(ps.wallet.pocket)
	sim.enter_zone(1, HR.ZoneType.EXIT, &"door")
	var r := sim.try_climb()
	assert_eq(r["reason"], FloorSim.NO_STAKE)
	assert_eq(r["to"], TOP + 2)
	assert_eq(r["stake"], int(CasinoLadder.casino(TOP + 2)["min_bet"]))
	assert_false(sim.finished)
	assert_eq(sim.snapshot()["run"]["climb_stake"], r["stake"])
	ps.wallet.add(r["stake"] - 1)
	assert_eq(sim.try_climb()["reason"], FloorSim.NO_STAKE)
	ps.wallet.add(1)
	assert_true(sim.try_climb()["ok"])


func test_a_stretch_that_would_leave_the_crew_broke_climbs_one_rung() -> void:
	var sim := _sim(TOP + 3)
	var ps := sim.player(1)
	var buy_in := CasinoLadder.buy_in_to_leave(TOP + 3)
	sim.run.bank = Tuning.STRETCH_MULT * buy_in
	ps.wallet.spend(ps.wallet.pocket)
	sim.enter_zone(1, HR.ZoneType.EXIT, &"door")
	var r := sim.try_climb()
	assert_true(r["ok"], str(r))
	assert_eq(r["to"], TOP + 2, "one rung, keeping a buy-in's worth in the bank")
	assert_eq(r["cost"], buy_in)
	assert_eq(sim.run.bank, buy_in)


func test_outfit_swaps_back_and_forth_cool_only_once_per_cooldown() -> void:
	var sim := _sim()
	var ps := sim.player(1)
	ps.heat.add(90.0, &"test")
	sim.enter_zone(1, HR.ZoneType.RESTROOM, &"wc")
	assert_almost_eq(sim.change_to_stash(1, 0)["heat"], Tuning.CHANGE_OUTFIT_HEAT)
	var after := ps.heat.value
	var again := sim.change_to_stash(1, 0)
	assert_true(again["ok"], "the look still changes")
	assert_almost_eq(again["heat"], 0.0, 0.001, "but swapping straight back cools nothing")
	assert_almost_eq(ps.heat.value, after)
	sim.tick(Tuning.CHANGE_OUTFIT_COOLDOWN)
	var later := ps.heat.value
	assert_almost_eq(sim.change_to_stash(1, 0)["heat"], Tuning.CHANGE_OUTFIT_HEAT)
	assert_almost_eq(ps.heat.value, later + Tuning.CHANGE_OUTFIT_HEAT)
	assert_almost_eq(HeatRules.change_outfit_heat(INF), Tuning.CHANGE_OUTFIT_HEAT)
	assert_almost_eq(HeatRules.change_outfit_heat(Tuning.CHANGE_OUTFIT_COOLDOWN - 0.1), 0.0)


func test_winning_at_slots_pauses_the_blend() -> void:
	var sim := _sim()
	_rich(sim, 1)
	_seat(sim, 1, HR.GameType.SLOTS)
	var ps := sim.player(1)
	ps.heat.add(30.0, &"test")
	_bet_until(sim, 1, &"t1", _max_bet(sim), true)
	log.clear()
	sim.tick(Tuning.SLOT_BLEND_WIN_PAUSE_SECONDS - 0.5)
	assert_eq(_heat_events(HeatRules.SLOT_BLEND).size(), 0, "no blending in right after a payout")
	sim.tick(1.0)
	assert_eq(_heat_events(HeatRules.SLOT_BLEND).size(), 1, "back to blending in")
	# A max-bet win plus a min-bet throw every few rounds no longer nets out.
	var start := ps.heat.value
	for i in 12:
		if i % 3 == 2:
			sim.place_bet(1, &"t1", _min_bet(sim), {"throw": true})
		else:
			sim.place_bet(1, &"t1", _max_bet(sim))
		sim.tick(float(Tuning.GAMES[HR.GameType.SLOTS]["round_seconds"]))
	assert_gt(ps.heat.value, start, "winning at slots builds Heat")


func test_noise_radii_stay_local() -> void:
	# A big wheel or jackpot pulls the guards nearby, not every guard on the Apex floor.
	assert_lte(float(Tuning.NOISE_RADIUS[&"big_wheel"]), 16.0)
	assert_lte(float(Tuning.NOISE_RADIUS[&"slot_jackpot"]), 18.0)
	assert_gt(float(Tuning.NOISE_RADIUS[&"big_wheel"]), float(Tuning.NOISE_RADIUS[&"knock_over"]))
	assert_gt(float(Tuning.NOISE_RADIUS[&"slot_jackpot"]), float(Tuning.NOISE_RADIUS[&"throw_chips"]))


# --- Visits -----------------------------------------------------------------

func test_carried_players_keep_kit_and_reset_visit_state() -> void:
	var old := _sim(TOP + 1, 1, 2)
	var ps := old.player(1)
	_rich(old, 1, 777)
	ps.heat.add(60.0, &"test")
	old.enter_zone(1, HR.ZoneType.BAR, &"bar")
	var pocket := ps.wallet.pocket
	var look := ps.outfit
	var card := ps.current_id()
	var fresh := FloorSim.new(old.run, 9, old.players.values())
	assert_true(fresh.player(1) == ps, "same PlayerState object")
	assert_eq(ps.wallet.pocket, pocket)
	assert_true(ps.outfit == look)
	assert_true(ps.current_id() == card)
	assert_almost_eq(ps.heat.value, 0.0)
	assert_null(ps.recorded_look)
	assert_eq(ps.status, HR.PlayerStatus.FREE)
	assert_eq(ps.zone, HR.ZoneType.ENTRANCE)
	# The old sim no longer hears this player.
	var old_count := log.size()
	var fresh_log: Array = []
	fresh.event.connect(func(k: StringName, d: Dictionary) -> void: fresh_log.append(k))
	ps.heat.add(5.0, &"test")
	ps.wallet.add(5)
	assert_eq(log.size(), old_count)
	assert_has(fresh_log, &"heat")
	assert_has(fresh_log, &"chips")


func test_new_visit_hands_out_an_id_when_all_are_burned() -> void:
	var old := _sim(TOP + 1)
	old.player(1).current_id().burn()
	var fresh := FloorSim.new(old.run, 2, old.players.values())
	assert_eq(fresh.player(1).ids.size(), 2)
	assert_true(fresh.player(1).current_id().passes_check())


# --- Snapshot and events ------------------------------------------------------

func test_snapshot_shape() -> void:
	var sim := _sim(TOP + 1, 1, 2)
	sim.register_table(&"t1", HR.GameType.DICE, &"a")
	sim.sit(2, &"t1")
	var snap := sim.snapshot()
	for key in ["players", "run", "tables", "fire_alarm", "fire_alarm_seconds", "slot_alarm_cooldown", "forger_location", "forger_seconds_until_move", "posters", "finished", "outcome"]:
		assert_has(snap, key)
	var p: Dictionary = snap["players"][1]
	for key in ["pid", "name", "heat", "level", "pocket", "lifetime_banked", "status", "status_seconds", "zone", "area_id", "table_id", "round", "outfit", "stash", "stash_size", "id", "id_index", "ids", "id_count", "id_check", "recorded_look", "recognized", "matches_poster", "staff_uniform", "available", "targetable", "rejoin_grace", "id_cleared", "loiter_seconds", "loitering", "flags"]:
		assert_has(p, key)
	assert_eq(p["name"], "P1")
	assert_eq(p["pocket"], CasinoLadder.start_chips(TOP + 1))
	assert_true(p["targetable"])
	assert_false(p["id_cleared"])
	assert_eq(p["stash_size"], Tuning.START_STASH_OUTFITS)
	assert_eq(p["id_count"], 1)
	assert_eq(p["id"]["name"], sim.player(1).current_id().name)
	assert_eq(p["outfit"], sim.player(1).outfit.to_dict())
	assert_eq(snap["players"][2]["table_id"], &"t1")
	assert_eq(snap["players"][2]["status"], HR.PlayerStatus.SEATED)
	var run: Dictionary = snap["run"]
	for key in ["rung", "casino_id", "casino_name", "min_bet", "max_bet", "strikes", "max_strikes", "bank", "buy_in", "stretch_buy_in", "climb_target", "can_climb", "top_banked", "score", "top_seconds", "visit_seconds", "elapsed_seconds", "visits", "fire_alarm_used", "is_top", "is_bottom", "security", "has_cameras", "start_chips", "climb_stake", "scoring"]:
		assert_has(run, key)
	assert_true(run["has_cameras"], "the Marquee has cameras")
	assert_eq(run["start_chips"], CasinoLadder.start_chips(TOP + 1))
	assert_eq(run["casino_name"], "The Grand Marquee")
	assert_eq(run["buy_in"], int(Tuning.CASINOS[0]["buy_in"]))
	assert_eq(run["stretch_buy_in"], 0, "no rung two above the second")
	assert_eq(snap["tables"][&"t1"], {"game_type": HR.GameType.DICE, "area_id": &"a", "closed": false, "seated": [2]})
	assert_true(_is_plain(snap))


func test_all_events_are_plain_data() -> void:
	var sim := _sim(TOP + 1, 3, 2)
	sim.register_table(&"bj", HR.GameType.BLACKJACK, &"a")
	sim.register_table(&"hl", HR.GameType.HIGH_LOW, &"a")
	sim.register_table(&"wheel", HR.GameType.BIG_WHEEL, &"b")
	sim.sit(1, &"bj")
	sim.start_blackjack(1, &"bj", _min_bet(sim))
	sim.blackjack_hit(1)
	sim.stand(1)
	sim.sit(1, &"hl")
	sim.start_high_low(1, &"hl", _min_bet(sim))
	sim.high_low_guess(1, true)
	sim.stand(1)
	sim.sit(2, &"wheel")
	for i in 20:
		sim.place_bet(2, &"wheel", _max_bet(sim))
	sim.start_id_check(1)
	sim.expire_id_check(1)
	sim.report_seen(2)
	sim.distraction(1, HR.Distraction.THROW_CHIPS, Vector3.ONE)
	sim.distraction(1, HR.Distraction.FIRE_ALARM, Vector3.ONE)
	sim.caught(1)
	sim.freed(1, 2)
	sim.caught(1)
	sim.reach_back_room(1)
	sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	sim.tick(Tuning.FORGER_MOVE_SECONDS)
	assert_gt(log.size(), 20)
	var kinds: Dictionary = {}
	for e: Array in log:
		kinds[e[0]] = true
		assert_eq(typeof(e[0]), TYPE_STRING_NAME)
		assert_true(_is_plain(e[1]), "event %s carries an Object" % e[0])
	for k in [&"bet", &"hand", &"heat", &"level", &"chips", &"noise", &"crowd_rush", &"fire_alarm", &"caught", &"freed", &"detained", &"strike", &"rejoined", &"id_check", &"id_result", &"poster", &"forger_moved", &"status", &"seated", &"stood"]:
		assert_has(kinds, k)
