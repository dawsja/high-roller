extends TestCase
## Wallet, Cashier, CasinoLadder and RunState.

const TOP := Tuning.TOP_RUNG
const BOTTOM := Tuning.BOTTOM_RUNG

## Signal log: ["kind", args...] in emit order.
var events: Array = []


func before_each() -> void:
	events.clear()


func _watch(run: RunState) -> void:
	run.strike_added.connect(func(s: int) -> void: events.append(["strike", s]))
	run.thrown_out.connect(func(f: int, t: int) -> void: events.append(["thrown_out", f, t]))
	run.climbed.connect(func(f: int, t: int) -> void: events.append(["climbed", f, t]))
	run.banked.connect(func(a: int, total: int) -> void: events.append(["banked", a, total]))


func _id(cap: int = 6000) -> FakeId:
	var id := FakeId.new()
	id.name = "Chip McTest"
	id.birthday = "Jan 1"
	id.home_state = "Nevada"
	id.grade = HR.IdGrade.CHEAP
	id.cap = cap
	id.banked_under = 0
	id.flagged = false
	id.burned = false
	return id


func _buy_in(rung: int) -> int:
	return int(Tuning.CASINOS[rung - 1]["buy_in"])


# --- Wallet ------------------------------------------------------------------

func test_wallet_start_pocket() -> void:
	assert_eq(Wallet.new().pocket, 0)
	assert_eq(Wallet.new(300).pocket, 300)
	assert_eq(Wallet.new(-5).pocket, 0, "never negative")
	assert_eq(Wallet.new(300).lifetime_banked, 0)


func test_wallet_add_and_spend() -> void:
	var w := Wallet.new(100)
	w.add(50)
	assert_eq(w.pocket, 150)
	w.add(0)
	w.add(-40)
	assert_eq(w.pocket, 150, "non-positive add ignored")
	assert_true(w.spend(120))
	assert_eq(w.pocket, 30)
	assert_true(w.spend(30), "can spend exactly the pocket")
	assert_eq(w.pocket, 0)
	assert_true(w.spend(0), "spending nothing is fine")


func test_wallet_spend_refuses_short_or_negative() -> void:
	var w := Wallet.new(100)
	assert_false(w.spend(101))
	assert_false(w.spend(-10))
	assert_eq(w.pocket, 100)
	assert_true(w.can_afford(100))
	assert_false(w.can_afford(101))


func test_wallet_lose_pocket() -> void:
	var w := Wallet.new(420)
	w.lifetime_banked = 900
	assert_eq(w.lose_pocket(), 420)
	assert_eq(w.pocket, 0)
	assert_eq(w.lifetime_banked, 900, "banked chips are safe")
	assert_eq(w.lose_pocket(), 0, "nothing left to lose")


func test_wallet_give_to() -> void:
	var a := Wallet.new(500)
	var b := Wallet.new(20)
	assert_true(a.give_to(b, 200))
	assert_eq(a.pocket, 300)
	assert_eq(b.pocket, 220)
	assert_true(a.give_to(b, 300), "can hand over everything")
	assert_eq(a.pocket, 0)
	assert_eq(b.pocket, 520)


func test_wallet_give_to_refuses_bad_requests() -> void:
	var a := Wallet.new(100)
	var b := Wallet.new(0)
	assert_false(a.give_to(b, 101), "short")
	assert_false(a.give_to(b, 0), "zero")
	assert_false(a.give_to(b, -5), "negative")
	assert_false(a.give_to(a, 10), "self")
	assert_false(a.give_to(null, 10), "null")
	assert_eq(a.pocket, 100)
	assert_eq(b.pocket, 0)


func test_wallet_changed_signal() -> void:
	var w := Wallet.new(100)
	var seen: Array = []
	w.changed.connect(func(p: int, d: int) -> void: seen.append([p, d]))
	w.add(10)
	w.spend(30)
	w.spend(500)
	w.add(-3)
	w.lose_pocket()
	assert_eq(seen, [[110, 10], [80, -30], [0, -80]])


func test_wallet_bank_out() -> void:
	var w := Wallet.new(100)
	assert_true(w.bank_out(60))
	assert_eq(w.pocket, 40)
	assert_eq(w.lifetime_banked, 60)
	assert_false(w.bank_out(41))
	assert_false(w.bank_out(0))
	assert_eq(w.pocket, 40)
	assert_eq(w.lifetime_banked, 60)
	assert_eq(w.to_dict(), {"pocket": 40, "lifetime_banked": 60})


# --- Cashier -----------------------------------------------------------------

func test_cash_out_moves_chips_and_records_against_id() -> void:
	var w := Wallet.new(1000)
	var id := _id(6000)
	var r := Cashier.cash_out(w, id, 400, 100)
	assert_true(r["ok"])
	assert_eq(r["reason"], Cashier.NO_REASON)
	assert_eq(r["banked"], 400)
	assert_eq(r["flagged"], false)
	assert_eq(w.pocket, 600)
	assert_eq(w.lifetime_banked, 400)
	assert_eq(id.banked_under, 400)
	assert_true(id.passes_check())
	var r2 := Cashier.cash_out(w, id, 600, 100)
	assert_true(r2["ok"])
	assert_eq(w.pocket, 0)
	assert_eq(w.lifetime_banked, 1000)
	assert_eq(id.banked_under, 1000)


func test_cash_out_result_has_every_key() -> void:
	var ok := Cashier.cash_out(Wallet.new(100), _id(), 50, 50)
	var bad := Cashier.cash_out(Wallet.new(100), null, 50, 50)
	for r: Dictionary in [ok, bad]:
		for key: String in ["ok", "reason", "banked", "heat", "flagged"]:
			assert_has(r, key)
	assert_eq(typeof(ok["heat"]), TYPE_FLOAT)
	assert_eq(typeof(bad["heat"]), TYPE_FLOAT)
	assert_eq(typeof(ok["reason"]), TYPE_STRING_NAME)
	assert_eq(typeof(bad["reason"]), TYPE_STRING_NAME)


func test_cash_out_heat_matches_heat_rules() -> void:
	var max_bet := 100
	var small_amount := int(Tuning.LARGE_CASHOUT_BETS) * max_bet
	var w := Wallet.new(1_000_000)
	var small := Cashier.cash_out(w, _id(1_000_000), small_amount, max_bet)
	assert_almost_eq(small["heat"], 0.0, 0.0001, "at the threshold: no Heat")
	var large_amount := small_amount + 5 * max_bet
	var large := Cashier.cash_out(w, _id(1_000_000), large_amount, max_bet)
	assert_gt(large["heat"], 0.0, "a large cash-out adds Heat")
	assert_almost_eq(large["heat"], HeatRules.cash_out_heat(large_amount, max_bet))
	var huge := Cashier.cash_out(w, _id(1_000_000), 500 * max_bet, max_bet)
	assert_almost_eq(huge["heat"], HeatRules.cash_out_heat(500 * max_bet, max_bet))
	assert_lte(huge["heat"], Tuning.LARGE_CASHOUT_HEAT_MAX)


func test_cash_out_refuses_bad_ids() -> void:
	var w := Wallet.new(1000)
	var flagged := _id()
	flagged.flagged = true
	var burned := _id()
	burned.burned = true
	for id: FakeId in [flagged, burned, null]:
		var r := Cashier.cash_out(w, id, 100, 100)
		assert_false(r["ok"])
		assert_eq(r["reason"], Cashier.BAD_ID)
		assert_eq(r["banked"], 0)
		assert_almost_eq(r["heat"], 0.0)
		assert_eq(r["flagged"], false)
	assert_eq(w.pocket, 1000, "a refused cash-out keeps the chips in the pocket")
	assert_eq(w.lifetime_banked, 0)
	assert_eq(flagged.banked_under, 0)
	assert_eq(burned.banked_under, 0)


func test_cash_out_checks_id_before_pocket() -> void:
	var id := _id()
	id.burned = true
	var r := Cashier.cash_out(Wallet.new(10), id, 500, 100)
	assert_eq(r["reason"], Cashier.BAD_ID)


func test_cash_out_not_enough() -> void:
	var w := Wallet.new(99)
	var id := _id()
	var r := Cashier.cash_out(w, id, 100, 100)
	assert_false(r["ok"])
	assert_eq(r["reason"], Cashier.NOT_ENOUGH)
	assert_eq(w.pocket, 99)
	assert_eq(id.banked_under, 0)
	assert_eq(Cashier.cash_out(null, _id(), 100, 100)["reason"], Cashier.NOT_ENOUGH)


func test_cash_out_bad_amount() -> void:
	var w := Wallet.new(100)
	assert_eq(Cashier.cash_out(w, _id(), 0, 100)["reason"], Cashier.BAD_AMOUNT)
	assert_eq(Cashier.cash_out(w, _id(), -50, 100)["reason"], Cashier.BAD_AMOUNT)
	assert_eq(w.pocket, 100)


func test_cash_out_crossing_cap_succeeds_then_flags_id() -> void:
	var w := Wallet.new(5000)
	var id := _id(1000)
	var r1 := Cashier.cash_out(w, id, 600, 100)
	assert_true(r1["ok"])
	assert_eq(r1["flagged"], false)
	assert_true(id.passes_check())
	var r2 := Cashier.cash_out(w, id, 600, 100)
	assert_true(r2["ok"], "crossing the cap still pays out")
	assert_eq(r2["banked"], 600)
	assert_eq(r2["flagged"], true)
	assert_true(id.flagged)
	assert_false(id.passes_check(), "the name is flagged for its next check")
	assert_eq(w.pocket, 3800)
	var r3 := Cashier.cash_out(w, id, 100, 100)
	assert_false(r3["ok"])
	assert_eq(r3["reason"], Cashier.BAD_ID)
	assert_eq(w.pocket, 3800)
	var fresh := _id(1000)
	assert_true(Cashier.cash_out(w, fresh, 100, 100)["ok"], "a fresh ID works again")


func test_cash_out_all() -> void:
	var w := Wallet.new(750)
	var id := _id()
	var r := Cashier.cash_out_all(w, id, 100)
	assert_true(r["ok"])
	assert_eq(r["banked"], 750)
	assert_eq(w.pocket, 0)
	assert_eq(Cashier.cash_out_all(w, id, 100)["reason"], Cashier.NOT_ENOUGH)
	var burned := _id()
	burned.burned = true
	assert_eq(Cashier.cash_out_all(Wallet.new(10), burned, 100)["reason"], Cashier.BAD_ID)


# --- CasinoLadder ------------------------------------------------------------

func test_ladder_rungs_in_order() -> void:
	assert_eq(CasinoLadder.rung_count(), 6)
	assert_eq(BOTTOM - TOP + 1, CasinoLadder.rung_count())
	var ids := [&"apex", &"grand_marquee", &"riverboat_queen", &"neon_oasis", &"rusty_spur", &"sals_back_room"]
	for rung in range(TOP, BOTTOM + 1):
		var c := CasinoLadder.casino(rung)
		assert_eq(c["rung"], rung)
		assert_eq(c["id"], ids[rung - TOP])
		assert_eq(CasinoLadder.casino_id(rung), ids[rung - TOP])
		assert_true(CasinoLadder.is_valid_rung(rung))
	assert_true(CasinoLadder.is_top(TOP))
	assert_true(CasinoLadder.is_bottom(BOTTOM))
	assert_false(CasinoLadder.is_top(BOTTOM))


func test_ladder_bets_grow_going_up() -> void:
	for rung in range(TOP, BOTTOM):
		var here := CasinoLadder.casino(rung)
		var below := CasinoLadder.casino(rung + 1)
		assert_gt(here["max_bet"], below["max_bet"])
		assert_gt(here["min_bet"], below["min_bet"])
		assert_gt(here["payout_bonus"], below["payout_bonus"])


func test_ladder_invalid_rungs() -> void:
	assert_eq(CasinoLadder.casino(0), {})
	assert_eq(CasinoLadder.casino(BOTTOM + 1), {})
	assert_false(CasinoLadder.is_valid_rung(0))
	assert_eq(CasinoLadder.casino_id(42), &"")
	assert_eq(CasinoLadder.buy_in_to_leave(0), 0)
	assert_eq(CasinoLadder.climb_target(99, 1_000_000), 99, "no climb off the ladder")


func test_ladder_casino_is_a_copy() -> void:
	var c := CasinoLadder.casino(TOP)
	c["max_bet"] = 1
	(c["security"] as Array).clear()
	assert_eq(CasinoLadder.casino(TOP)["max_bet"], Tuning.CASINOS[0]["max_bet"])
	assert_gt((CasinoLadder.casino(TOP)["security"] as Array).size(), 0)


func test_ladder_by_id_and_rung_of() -> void:
	assert_eq(CasinoLadder.by_id(&"neon_oasis")["rung"], 4)
	assert_eq(CasinoLadder.by_id(&"sals_back_room")["name"], "Sal's Back Room")
	assert_eq(CasinoLadder.by_id(&"nowhere"), {})
	assert_eq(CasinoLadder.rung_of(&"apex"), 1)
	assert_eq(CasinoLadder.rung_of(&"rusty_spur"), 5)
	assert_eq(CasinoLadder.rung_of(&"nowhere"), -1)


func test_buy_in_to_leave_is_the_casino_above() -> void:
	assert_eq(CasinoLadder.buy_in_to_leave(TOP), 0)
	for rung in range(TOP + 1, BOTTOM + 1):
		assert_eq(CasinoLadder.buy_in_to_leave(rung), _buy_in(rung - 1), "rung %d" % rung)
	assert_eq(CasinoLadder.buy_in_to_leave(6), 200)
	assert_eq(CasinoLadder.buy_in_to_leave(2), 17000)


func test_climb_target_single_rung() -> void:
	for rung in range(TOP + 1, BOTTOM + 1):
		var buy_in := CasinoLadder.buy_in_to_leave(rung)
		assert_eq(CasinoLadder.climb_target(rung, 0), rung)
		assert_eq(CasinoLadder.climb_target(rung, buy_in - 1), rung, "one chip short")
		assert_eq(CasinoLadder.climb_target(rung, buy_in), rung - 1, "exact buy-in")
		if rung - 2 >= TOP:
			var stretch := Tuning.STRETCH_MULT * buy_in
			assert_eq(CasinoLadder.climb_target(rung, stretch - 1), rung - 1, "one chip short of a stretch")


func test_climb_target_stretch_skips_a_rung() -> void:
	for rung in range(TOP + 2, BOTTOM + 1):
		var stretch := Tuning.STRETCH_MULT * CasinoLadder.buy_in_to_leave(rung)
		assert_eq(CasinoLadder.climb_target(rung, stretch), rung - 2, "rung %d" % rung)
		assert_eq(CasinoLadder.climb_target(rung, stretch * 10), rung - 2, "never more than two")
	assert_eq(CasinoLadder.climb_target(6, 400), 4)


func test_climb_target_stretch_blocked_above_top() -> void:
	var rung := TOP + 1
	var stretch := Tuning.STRETCH_MULT * CasinoLadder.buy_in_to_leave(rung)
	assert_eq(CasinoLadder.climb_target(rung, stretch), TOP)
	assert_eq(CasinoLadder.climb_target(rung, stretch * 100), TOP)


func test_climb_target_top_rung_is_impossible() -> void:
	assert_eq(CasinoLadder.climb_target(TOP, 0), TOP)
	assert_eq(CasinoLadder.climb_target(TOP, 10_000_000), TOP)


func test_climb_cost() -> void:
	assert_eq(CasinoLadder.climb_cost(6, 5), 200)
	assert_eq(CasinoLadder.climb_cost(6, 4), Tuning.STRETCH_MULT * 200)
	assert_eq(CasinoLadder.climb_cost(2, 1), 17000)
	assert_eq(CasinoLadder.climb_cost(3, 1), Tuning.STRETCH_MULT * 6000)
	assert_eq(CasinoLadder.climb_cost(4, 4), 0, "no climb")
	assert_eq(CasinoLadder.climb_cost(TOP, TOP), 0)
	assert_eq(CasinoLadder.climb_cost(6, 3), 0, "three rungs is not a legal climb")
	assert_eq(CasinoLadder.climb_cost(3, 4), 0, "down is not a climb")
	assert_eq(CasinoLadder.climb_cost(2, 0), 0, "off the ladder")


func test_drop_target() -> void:
	for rung in range(TOP, BOTTOM):
		assert_eq(CasinoLadder.drop_target(rung), rung + 1)
	assert_eq(CasinoLadder.drop_target(BOTTOM), BOTTOM, "Sal's is the floor")


# --- RunState ------------------------------------------------------------------

func test_run_starts_at_top() -> void:
	var run := RunState.new()
	assert_eq(run.rung, TOP)
	assert_eq(run.strikes, 0)
	assert_eq(run.bank, 0)
	assert_eq(run.top_banked, 0)
	assert_almost_eq(run.top_seconds, 0.0)
	assert_almost_eq(run.elapsed_seconds, 0.0)
	assert_not_null(run.posters)
	assert_false(run.fire_alarm_used)
	assert_eq(run.visits, 1)
	assert_eq(run.casino()["id"], &"apex")
	assert_eq(run.casino_id(), &"apex")
	assert_true(run.is_top())
	assert_eq(run.score(), 0)


func test_run_start_rung_is_clamped() -> void:
	assert_eq(RunState.new(BOTTOM).rung, BOTTOM)
	assert_eq(RunState.new(99).rung, BOTTOM)
	assert_eq(RunState.new(-3).rung, TOP)


func test_add_bank_at_top_goes_to_score() -> void:
	var run := RunState.new()
	_watch(run)
	run.add_bank(700)
	run.add_bank(300)
	assert_eq(run.top_banked, 1000)
	assert_eq(run.bank, 0, "top-rung chips are score, not spendable")
	assert_eq(run.score(), 1000)
	assert_eq(events, [["banked", 700, 700], ["banked", 300, 1000]])


func test_add_bank_below_top_goes_to_bank() -> void:
	var run := RunState.new(3)
	_watch(run)
	run.add_bank(250)
	run.add_bank(50)
	assert_eq(run.bank, 300)
	assert_eq(run.top_banked, 0)
	assert_eq(run.score(), 0)
	assert_eq(events, [["banked", 250, 250], ["banked", 50, 300]])


func test_add_bank_ignores_non_positive() -> void:
	var run := RunState.new(3)
	_watch(run)
	run.add_bank(0)
	run.add_bank(-40)
	assert_eq(run.bank, 0)
	assert_eq(events, [])


func test_strikes_count_to_throw_out() -> void:
	var run := RunState.new()
	_watch(run)
	for i in range(1, Tuning.STRIKES_TO_THROW_OUT):
		assert_false(run.add_strike(), "strike %d" % i)
		assert_eq(run.strikes, i)
	assert_true(run.add_strike(), "the last strike")
	assert_eq(run.strikes, Tuning.STRIKES_TO_THROW_OUT)
	assert_eq(run.rung, TOP, "add_strike doesn't throw out by itself")
	var expected: Array = []
	for i in range(1, Tuning.STRIKES_TO_THROW_OUT + 1):
		expected.append(["strike", i])
	assert_eq(events, expected)


func test_throw_out_drops_and_resets_visit_state() -> void:
	var run := RunState.new()
	_watch(run)
	run.add_strike()
	run.add_strike()
	assert_true(run.use_fire_alarm())
	run.tick(30.0)
	events.clear()
	assert_eq(run.throw_out(), TOP + 1)
	assert_eq(run.rung, TOP + 1)
	assert_eq(run.strikes, 0)
	assert_false(run.fire_alarm_used)
	assert_almost_eq(run.visit_seconds, 0.0)
	assert_eq(run.visits, 2)
	assert_eq(events, [["thrown_out", TOP, TOP + 1]])
	assert_eq(run.casino_id(), &"grand_marquee")


func test_full_ladder_walk_down_keeps_bank() -> void:
	var run := RunState.new()
	_watch(run)
	run.add_bank(5000)
	var board := run.posters
	var expected_bank := 0
	for to_rung in range(TOP + 1, BOTTOM + 1):
		var from_rung := run.rung
		for i in range(Tuning.STRIKES_TO_THROW_OUT - 1):
			assert_false(run.add_strike())
		assert_true(run.add_strike())
		events.clear()
		assert_eq(run.throw_out(), to_rung)
		assert_eq(events, [["thrown_out", from_rung, to_rung]])
		assert_eq(run.strikes, 0)
		assert_eq(run.bank, expected_bank, "bank carried down to rung %d" % to_rung)
		assert_eq(run.casino()["rung"], to_rung)
		# bank something here; it survives the next drop
		run.add_bank(100)
		expected_bank += 100
	assert_eq(run.rung, BOTTOM)
	assert_true(run.is_bottom())
	assert_eq(run.bank, expected_bank)
	assert_eq(run.top_banked, 5000, "score banked at the top is kept")
	assert_eq(run.visits, BOTTOM - TOP + 1)
	assert_true(run.posters == board, "same poster board for the whole run")


func test_curb_timeout_at_bottom() -> void:
	var run := RunState.new(BOTTOM)
	_watch(run)
	run.add_bank(40)
	run.add_strike()
	run.add_strike()
	run.add_strike()
	run.use_fire_alarm()
	events.clear()
	assert_eq(run.throw_out(), BOTTOM)
	assert_eq(run.rung, BOTTOM, "Sal's is the floor")
	assert_eq(run.strikes, 0)
	assert_false(run.fire_alarm_used)
	assert_eq(run.bank, 40)
	assert_eq(events, [["thrown_out", BOTTOM, BOTTOM]])
	# again, still the curb
	assert_eq(run.throw_out(), BOTTOM)
	assert_eq(events.size(), 2)


func test_full_ladder_walk_up() -> void:
	var run := RunState.new(BOTTOM)
	_watch(run)
	var visits := run.visits
	while run.rung > TOP:
		var from_rung := run.rung
		assert_false(run.can_climb(), "nothing banked yet at rung %d" % from_rung)
		var buy_in := CasinoLadder.buy_in_to_leave(from_rung)
		assert_eq(buy_in, _buy_in(from_rung - 1))
		run.add_bank(buy_in - 1)
		assert_false(run.can_climb(), "one chip short at rung %d" % from_rung)
		assert_eq(run.climb(), from_rung, "a short climb does nothing")
		run.add_bank(1)
		run.add_strike()
		run.use_fire_alarm()
		assert_true(run.can_climb())
		assert_eq(run.climb_target(), from_rung - 1)
		assert_eq(run.climb_cost(), buy_in)
		events.clear()
		assert_eq(run.climb(), from_rung - 1)
		assert_eq(events, [["climbed", from_rung, from_rung - 1]])
		assert_eq(run.bank, 0, "the buy-in was spent")
		assert_eq(run.strikes, 0)
		assert_false(run.fire_alarm_used)
		visits += 1
		assert_eq(run.visits, visits)
	assert_eq(run.rung, TOP)
	assert_eq(run.casino_id(), &"apex")
	run.add_bank(900)
	assert_eq(run.top_banked, 900, "back at the top, banking is score again")
	assert_eq(run.bank, 0)


func test_stretch_climb_skips_a_rung_and_pays_double() -> void:
	var run := RunState.new(BOTTOM)
	_watch(run)
	var stretch := Tuning.STRETCH_MULT * CasinoLadder.buy_in_to_leave(BOTTOM)
	run.add_bank(stretch + 25)
	assert_eq(run.climb_target(), BOTTOM - 2)
	assert_eq(run.climb_cost(), stretch)
	events.clear()
	assert_eq(run.climb(), BOTTOM - 2)
	assert_eq(run.bank, 25, "leftover chips stay in the bank")
	assert_eq(events, [["climbed", BOTTOM, BOTTOM - 2]])
	assert_eq(run.visits, 2, "a stretch is one visit, not two")


func test_stretch_to_the_top() -> void:
	var run := RunState.new(3)
	run.add_bank(Tuning.STRETCH_MULT * _buy_in(2))
	assert_eq(run.climb(), TOP)
	assert_eq(run.bank, 0)


func test_climb_from_second_rung_never_overshoots() -> void:
	var run := RunState.new(TOP + 1)
	run.add_bank(10 * _buy_in(TOP))
	assert_eq(run.climb_target(), TOP)
	assert_eq(run.climb(), TOP)
	assert_eq(run.bank, 9 * _buy_in(TOP), "only one buy-in spent")


func test_top_rung_climb_impossible() -> void:
	var run := RunState.new(TOP + 1)
	run.add_bank(50_000)
	run.climb()
	assert_eq(run.rung, TOP)
	var bank_before := run.bank
	run.add_bank(1_000_000)
	assert_false(run.can_climb())
	assert_eq(run.climb_cost(), 0)
	_watch(run)
	assert_eq(run.climb(), TOP)
	assert_eq(run.rung, TOP)
	assert_eq(run.bank, bank_before, "nothing spent")
	assert_eq(events, [])


func test_bank_survives_drops_and_pays_for_climb_back() -> void:
	var run := RunState.new(3)
	run.add_bank(1500)
	run.throw_out()
	run.throw_out()
	assert_eq(run.rung, 5)
	assert_eq(run.bank, 1500, "banked chips are safe")
	# 1500 >= 2 x 500: stretch from 5 straight to 3
	assert_eq(run.climb(), 3)
	assert_eq(run.bank, 500)


func test_top_banked_is_never_spent() -> void:
	var run := RunState.new()
	run.add_bank(50_000)
	run.throw_out()
	assert_eq(run.rung, TOP + 1)
	assert_eq(run.top_banked, 50_000)
	assert_eq(run.bank, 0)
	assert_false(run.can_climb(), "score chips don't buy back in")
	run.add_bank(_buy_in(TOP))
	assert_eq(run.bank, _buy_in(TOP))
	assert_eq(run.climb(), TOP)
	assert_eq(run.top_banked, 50_000)
	assert_eq(run.score(), 50_000)


func test_tick_counts_top_seconds_only_at_top() -> void:
	var run := RunState.new()
	run.tick(10.0)
	run.tick(-5.0)
	run.tick(0.0)
	assert_almost_eq(run.top_seconds, 10.0)
	assert_almost_eq(run.elapsed_seconds, 10.0)
	assert_almost_eq(run.visit_seconds, 10.0)
	run.throw_out()
	run.tick(20.0)
	assert_almost_eq(run.top_seconds, 10.0, 0.001, "not at the top")
	assert_almost_eq(run.elapsed_seconds, 30.0)
	assert_almost_eq(run.visit_seconds, 20.0)
	run.add_bank(_buy_in(TOP))
	run.climb()
	run.tick(5.0)
	assert_almost_eq(run.top_seconds, 15.0)
	assert_almost_eq(run.elapsed_seconds, 35.0)
	assert_almost_eq(run.visit_seconds, 5.0)


func test_score_math() -> void:
	var run := RunState.new()
	run.add_bank(1234)
	run.tick(59.9)
	assert_eq(run.score(), 1234, "no whole minute yet")
	run.tick(0.2)
	assert_eq(run.score(), 1234 + Tuning.SCORE_PER_MINUTE_AT_TOP)
	run.tick(60.0)
	assert_eq(run.score(), 1234 + 2 * Tuning.SCORE_PER_MINUTE_AT_TOP)
	run.throw_out()
	run.tick(600.0)
	run.add_bank(5000)
	assert_eq(run.score(), 1234 + 2 * Tuning.SCORE_PER_MINUTE_AT_TOP, "time and chips below the top don't score")
	assert_almost_eq(run.elapsed_seconds, 720.1)
	assert_eq(run.to_dict()["score"], run.score())


func test_fire_alarm_once_per_visit() -> void:
	var run := RunState.new(4)
	assert_true(run.use_fire_alarm())
	assert_true(run.fire_alarm_used)
	assert_false(run.use_fire_alarm(), "once per visit")
	run.throw_out()
	assert_true(run.use_fire_alarm(), "new visit, new alarm")


func test_to_dict() -> void:
	var run := RunState.new(2)
	run.add_bank(300)
	run.add_strike()
	var d := run.to_dict()
	assert_eq(d["rung"], 2)
	assert_eq(d["casino_id"], &"grand_marquee")
	assert_eq(d["bank"], 300)
	assert_eq(d["strikes"], 1)
	assert_eq(d["visits"], 1)
	assert_eq(d["top_banked"], 0)
	assert_eq(d["fire_alarm_used"], false)


# --- Review additions ----------------------------------------------------------

func test_score_counts_a_minute_of_frame_ticks() -> void:
	# 60 s of 60 Hz frames sums to 59.9999999999979 in floating point; the
	# minute must still count on the frame that completes it.
	var run := RunState.new()
	for i in 60 * 60:
		run.tick(1.0 / 60.0)
	assert_eq(run.score(), Tuning.SCORE_PER_MINUTE_AT_TOP, "one minute of frames")
	for i in 60 * 144:
		run.tick(1.0 / 144.0)
	assert_eq(run.score(), 2 * Tuning.SCORE_PER_MINUTE_AT_TOP, "another minute at 144 Hz")
	var short := RunState.new()
	for i in 60 * 60 - 1:
		short.tick(1.0 / 60.0)
	assert_eq(short.score(), 0, "one frame short of a minute")


func test_wallet_signals_on_give_and_bank_out() -> void:
	var a := Wallet.new(100)
	var b := Wallet.new(5)
	var seen_a: Array = []
	var seen_b: Array = []
	a.changed.connect(func(p: int, d: int) -> void: seen_a.append([p, d]))
	b.changed.connect(func(p: int, d: int) -> void: seen_b.append([p, d]))
	assert_true(a.give_to(b, 40))
	assert_false(a.give_to(b, 500))
	assert_true(a.bank_out(10))
	assert_false(a.bank_out(0))
	assert_true(a.spend(0))
	assert_eq(seen_a, [[60, -40], [50, -10]])
	assert_eq(seen_b, [[45, 40]])
	assert_eq(Wallet.new(0).lose_pocket(), 0)


func test_cash_out_emits_wallet_change_only_on_success() -> void:
	var w := Wallet.new(300)
	var seen: Array = []
	w.changed.connect(func(p: int, d: int) -> void: seen.append([p, d]))
	var burned := _id()
	burned.burned = true
	Cashier.cash_out(w, burned, 100, 100)
	Cashier.cash_out(w, _id(), 301, 100)
	Cashier.cash_out(w, _id(), 0, 100)
	assert_eq(seen, [], "failed cash-outs leave the pocket alone")
	assert_eq(w.lifetime_banked, 0)
	assert_true(Cashier.cash_out(w, _id(), 120, 100)["ok"])
	assert_eq(seen, [[180, -120]])


func test_cash_out_with_zero_max_bet_does_not_divide_by_zero() -> void:
	var w := Wallet.new(5000)
	var r := Cashier.cash_out(w, _id(), 4000, 0)
	assert_true(r["ok"])
	assert_eq(r["banked"], 4000)
	assert_eq(typeof(r["heat"]), TYPE_FLOAT)
	assert_almost_eq(r["heat"], HeatRules.cash_out_heat(4000, 0))
	var r2 := Cashier.cash_out(w, _id(), 100, -5)
	assert_true(r2["ok"])
	assert_eq(w.pocket, 900)


func test_strikes_past_threshold_still_report_throw_out() -> void:
	var run := RunState.new()
	for i in Tuning.STRIKES_TO_THROW_OUT:
		run.add_strike()
	assert_true(run.add_strike(), "already over the limit")
	assert_eq(run.strikes, Tuning.STRIKES_TO_THROW_OUT + 1)
	run.throw_out()
	assert_eq(run.strikes, 0)
	assert_false(run.add_strike())


func test_failed_climb_keeps_visit_state() -> void:
	var run := RunState.new(4)
	_watch(run)
	run.add_bank(CasinoLadder.buy_in_to_leave(4) - 1)
	run.add_strike()
	run.use_fire_alarm()
	run.tick(12.0)
	events.clear()
	assert_false(run.can_climb())
	assert_eq(run.climb_cost(), 0)
	assert_eq(run.climb(), 4)
	assert_eq(run.strikes, 1, "a failed climb is not a new visit")
	assert_true(run.fire_alarm_used)
	assert_almost_eq(run.visit_seconds, 12.0)
	assert_eq(run.visits, 1)
	assert_eq(run.bank, CasinoLadder.buy_in_to_leave(4) - 1)
	assert_eq(events, [])


func test_climb_cost_matches_spend_for_every_rung() -> void:
	for rung in range(TOP + 1, BOTTOM + 1):
		for banked: int in [CasinoLadder.buy_in_to_leave(rung), Tuning.STRETCH_MULT * CasinoLadder.buy_in_to_leave(rung) + 7]:
			var run := RunState.new(rung)
			run.add_bank(banked)
			var cost := run.climb_cost()
			var target := run.climb_target()
			assert_gt(cost, 0, "rung %d" % rung)
			assert_eq(run.climb(), target)
			assert_eq(run.bank, banked - cost, "rung %d spent exactly the cost" % rung)
			assert_gte(run.bank, 0)


func test_ladder_off_ladder_inputs() -> void:
	assert_eq(CasinoLadder.climb_cost(0, -1), 0)
	assert_eq(CasinoLadder.climb_cost(BOTTOM + 1, BOTTOM), 0)
	assert_eq(CasinoLadder.climb_target(BOTTOM, -100), BOTTOM, "negative bank never climbs")
	assert_eq(CasinoLadder.drop_target(BOTTOM + 3), BOTTOM)
	assert_eq(CasinoLadder.by_id(&""), {})
	assert_eq(CasinoLadder.buy_in_to_leave(BOTTOM + 1), 0)


func test_to_dict_is_complete_plain_data() -> void:
	var run := RunState.new()
	run.add_bank(500)
	run.tick(61.0)
	var d := run.to_dict()
	for key: String in ["rung", "casino_id", "strikes", "bank", "top_banked", "top_seconds",
			"elapsed_seconds", "visit_seconds", "fire_alarm_used", "visits", "score"]:
		assert_has(d, key)
	assert_almost_eq(d["top_seconds"], 61.0)
	assert_almost_eq(d["elapsed_seconds"], 61.0)
	assert_almost_eq(d["visit_seconds"], 61.0)
	assert_eq(d["score"], 500 + Tuning.SCORE_PER_MINUTE_AT_TOP)
	assert_false(d.has("posters"), "posters are objects, not plain data")
