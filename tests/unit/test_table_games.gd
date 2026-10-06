extends TestCase
## Table games: TableGames, TableState, BetResult, GameResolver, HighLowRun,
## BlackjackRound.

const PID := 1
const MAX_BET := 100
const ROUNDS := 4000
const RATE_TOLERANCE := 0.03
const SEEDS := 400


func _table(game_type: int) -> TableState:
	return TableState.new(&"t1", game_type, &"area_a")


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## Win rate over ROUNDS single-shot bets with a fresh table (cooled or not).
func _single_shot_rate(game_type: int, choice: Dictionary, cooled: bool, seed_value: int) -> float:
	var table := _table(game_type)
	table.seat(PID)
	if cooled:
		table.mark_cooled(PID)
	var rng := _rng(seed_value)
	var wins := 0
	for i in ROUNDS:
		if GameResolver.resolve(table, PID, 10, choice, rng, MAX_BET).won:
			wins += 1
	return float(wins) / float(ROUNDS)


## Dealer hits below 17 and stands on 17+.
func _assert_dealer_rule(cards: Array, msg: String) -> void:
	assert_gte(cards.size(), 2, "dealer has up and hole card. " + msg)
	for k in range(1, cards.size()):
		assert_lt(BlackjackRound.hand_total(cards.slice(0, k)), 17, "dealer only hits below 17. " + msg)
	assert_gte(BlackjackRound.hand_total(cards), 17, "dealer finishes on 17+. " + msg)


# --- TableGames -------------------------------------------------------------

func test_def_copies_tuning_row() -> void:
	var d := TableGames.def(HR.GameType.ROULETTE)
	assert_eq(d["type"], HR.GameType.ROULETTE)
	assert_eq(d["name"], "Roulette")
	assert_eq(d["payout"], 1.0)
	d["payout"] = 99.0
	assert_eq(Tuning.GAMES[HR.GameType.ROULETTE]["payout"], 1.0, "def returns a copy")
	assert_false(Tuning.GAMES[HR.GameType.ROULETTE].has("type"))
	assert_true(TableGames.def(999).is_empty())


func test_all_types() -> void:
	var types := TableGames.all_types()
	assert_eq(types.size(), 6)
	for t: int in HR.GameType.values():
		assert_has(types, t)


func test_display_name_reskins_bottom_two_rungs() -> void:
	assert_eq(TableGames.display_name(HR.GameType.SLOTS, 1), "Slots")
	assert_eq(TableGames.display_name(HR.GameType.DICE, 4), "Dice")
	assert_eq(TableGames.display_name(HR.GameType.SLOTS, 5), "Coin Pusher")
	assert_eq(TableGames.display_name(HR.GameType.HIGH_LOW, 6), "Scratch Cards")
	assert_eq(TableGames.display_name(HR.GameType.DICE, 6), "Bingo")
	var names: Dictionary = {}
	for t: int in TableGames.all_types():
		var reskin := TableGames.display_name(t, Tuning.BOTTOM_RUNG)
		assert_ne(reskin, TableGames.display_name(t, Tuning.TOP_RUNG), "type %d reskinned" % t)
		assert_eq(TableGames.display_name(t, 5), reskin)
		names[reskin] = true
	assert_eq(names.size(), 6, "reskin names are distinct")


# --- TableState -------------------------------------------------------------

func test_table_state_seating_and_time() -> void:
	var t := _table(HR.GameType.DICE)
	assert_eq(t.id, &"t1")
	assert_eq(t.area_id, &"area_a")
	assert_false(t.closed)
	t.seat(1)
	t.seat(2)
	t.seat(1)
	assert_eq(t.seated_players(), [1, 2] as Array[int])
	t.tick(1.5)
	t.tick(2.0)
	assert_almost_eq(t.seconds_seated(1), 3.5)
	t.leave(2)
	assert_false(t.is_seated(2))
	assert_true(t.is_seated(1))
	t.tick(1.0)
	assert_almost_eq(t.seconds_seated(1), 4.5)
	assert_almost_eq(t.seconds_seated(2), 0.0)
	t.seat(2)
	assert_almost_eq(t.seconds_seated(2), 0.0, 0.001, "re-seating restarts the clock")


func test_table_state_leave_clears_streak_and_cooled() -> void:
	var t := _table(HR.GameType.SLOTS)
	t.seat(PID)
	assert_almost_eq(t.win_rate_for(PID), Tuning.WIN_RATE)
	t.mark_cooled(PID)
	assert_true(t.is_cooled(PID))
	assert_almost_eq(t.win_rate_for(PID), Tuning.COOLED_WIN_RATE)
	assert_almost_eq(t.win_rate_for(2), Tuning.WIN_RATE, 0.001, "cooled is per player")
	assert_eq(t.record_win(PID), 1)
	assert_eq(t.record_win(PID), 2)
	assert_eq(t.streak(PID), 2)
	t.leave(PID)
	assert_eq(t.streak(PID), 0)
	assert_false(t.is_cooled(PID))
	assert_almost_eq(t.win_rate_for(PID), Tuning.WIN_RATE)


# --- Odds -------------------------------------------------------------------

func test_win_rate_is_085_for_every_single_shot_game() -> void:
	var cases := [
		[HR.GameType.SLOTS, {}],
		[HR.GameType.BIG_WHEEL, {}],
		[HR.GameType.DICE, {"call": "high"}],
		[HR.GameType.DICE, {"call": "low"}],
		[HR.GameType.ROULETTE, {"kind": "color", "color": "red"}],
		[HR.GameType.ROULETTE, {"kind": "number", "number": 17}],
	]
	var seed_value := 11
	for c: Array in cases:
		seed_value += 1
		var rate := _single_shot_rate(c[0], c[1], false, seed_value)
		assert_almost_eq(rate, Tuning.WIN_RATE, RATE_TOLERANCE, "game %d %s" % [c[0], str(c[1])])


func test_cooled_win_rate_is_050() -> void:
	var seed_value := 101
	for t: int in [HR.GameType.SLOTS, HR.GameType.BIG_WHEEL, HR.GameType.DICE, HR.GameType.ROULETTE]:
		seed_value += 1
		var rate := _single_shot_rate(t, {}, true, seed_value)
		assert_almost_eq(rate, Tuning.COOLED_WIN_RATE, RATE_TOLERANCE, "game %d cooled" % t)


func test_cooled_lasts_until_leaving() -> void:
	var table := _table(HR.GameType.SLOTS)
	table.seat(PID)
	table.mark_cooled(PID)
	table.leave(PID)
	table.seat(PID)
	var rng := _rng(5)
	var wins := 0
	for i in ROUNDS:
		if GameResolver.resolve(table, PID, 10, {}, rng, MAX_BET).won:
			wins += 1
	assert_almost_eq(float(wins) / ROUNDS, Tuning.WIN_RATE, RATE_TOLERANCE)


# --- Payout, Heat, streak ---------------------------------------------------

func test_payout_and_net() -> void:
	var rng := _rng(3)
	for t: int in [HR.GameType.SLOTS, HR.GameType.BIG_WHEEL, HR.GameType.DICE, HR.GameType.ROULETTE]:
		var table := _table(t)
		var profit: float = Tuning.GAMES[t]["payout"]
		for i in 300:
			var bet := 7 + i % 40
			var r := GameResolver.resolve(table, PID, bet, {}, rng, MAX_BET, 1.3)
			assert_eq(r.bet, bet)
			assert_eq(r.pid, PID)
			assert_eq(r.table_id, &"t1")
			assert_eq(r.game_type, t)
			if r.won:
				var mult: float = Tuning.SLOT_JACKPOT_PAYOUT if r.jackpot else profit
				assert_eq(r.payout, maxi(bet + 1, roundi(bet * (1.0 + mult * 1.3))), "game %d bet %d" % [t, bet])
				assert_gte(r.payout, bet + 1)
			else:
				assert_eq(r.payout, 0)
			assert_eq(r.net, r.payout - r.bet)


func test_win_payout_rounds_and_has_a_floor() -> void:
	assert_eq(GameResolver.win_payout(10, 0.5, 1.0), 15)
	assert_eq(GameResolver.win_payout(10, 1.0, 1.5), 25)
	assert_eq(GameResolver.win_payout(3, 0.5, 1.0), 5, "4.5 rounds to 5")
	assert_eq(GameResolver.win_payout(1, 0.1, 1.0), 2, "at least bet + 1")
	assert_eq(GameResolver.win_payout(0, 1.0, 1.0), 0)


func test_roulette_number_pays_number_payout() -> void:
	var table := _table(HR.GameType.ROULETTE)
	var rng := _rng(8)
	var saw_win := false
	for i in 50:
		var r := GameResolver.resolve(table, PID, 20, {"kind": "number", "number": 5}, rng, MAX_BET, 1.2)
		if r.won:
			saw_win = true
			assert_eq(r.payout, roundi(20 * (1.0 + Tuning.ROULETTE_NUMBER_PAYOUT * 1.2)))
	assert_true(saw_win)


func test_win_heat_comes_from_heat_rules_with_streak() -> void:
	for t: int in [HR.GameType.SLOTS, HR.GameType.BIG_WHEEL, HR.GameType.DICE, HR.GameType.ROULETTE]:
		var table := _table(t)
		var rng := _rng(21 + t)
		for i in 200:
			var r := GameResolver.resolve(table, PID, 40, {}, rng, MAX_BET)
			if r.won:
				assert_gt(r.heat, 0.0)
				assert_almost_eq(r.heat, HeatRules.win_heat(t, 40, MAX_BET, r.streak), 0.0001)
			else:
				assert_almost_eq(r.heat, 0.0, 0.0001, "honest loss has no Heat")
				assert_false(r.intentional_loss)
	var roul := _table(HR.GameType.ROULETTE)
	var rng2 := _rng(77)
	for i in 50:
		var r := GameResolver.resolve(roul, PID, 40, {"kind": "number", "number": 9}, rng2, MAX_BET)
		if r.won:
			assert_almost_eq(r.heat, HeatRules.win_heat(HR.GameType.ROULETTE, 40, MAX_BET, r.streak, true), 0.0001)


func test_throw_forces_a_loss_with_cooling_heat() -> void:
	var rng := _rng(4)
	for t: int in TableGames.all_types():
		var table := _table(t)
		table.record_win(PID)
		for i in 100:
			var r := GameResolver.resolve(table, PID, 30, {"throw": true}, rng, MAX_BET)
			assert_false(r.won, "game %d" % t)
			assert_true(r.intentional_loss)
			assert_eq(r.payout, 0)
			assert_eq(r.net, -30)
			assert_almost_eq(r.heat, Tuning.LOSE_ON_PURPOSE_HEAT)
			assert_eq(r.streak, 0)
			assert_eq(table.streak(PID), 0)


func test_streak_counts_consecutive_wins_and_resets() -> void:
	var table := _table(HR.GameType.DICE)
	table.seat(PID)
	var rng := _rng(9)
	var expected := 0
	for i in 500:
		var r := GameResolver.resolve(table, PID, 10, {}, rng, MAX_BET)
		expected = expected + 1 if r.won else 0
		assert_eq(r.streak, expected)
		assert_eq(table.streak(PID), expected)
	table.leave(PID)
	assert_eq(table.streak(PID), 0)


func test_same_seed_same_results() -> void:
	for t: int in TableGames.all_types():
		var a := _rng(1234)
		var b := _rng(1234)
		var ta := _table(t)
		var tb := _table(t)
		for i in 50:
			var ra := GameResolver.resolve(ta, PID, 25, {"kind": "number", "number": 3}, a, MAX_BET)
			var rb := GameResolver.resolve(tb, PID, 25, {"kind": "number", "number": 3}, b, MAX_BET)
			assert_eq(ra.to_dict(), rb.to_dict(), "game %d" % t)


# --- Details ----------------------------------------------------------------

func test_slots_detail_matches_outcome() -> void:
	for s in SEEDS:
		var rng := _rng(s)
		var table := _table(HR.GameType.SLOTS)
		for i in 10:
			var r := GameResolver.resolve(table, PID, 10, {"throw": i == 9}, rng, MAX_BET)
			var reels: Array = r.detail["reels"]
			assert_eq(reels.size(), 3)
			for sym: String in reels:
				assert_has(GameResolver.SLOT_SYMBOLS, sym)
			var three: bool = reels[0] == reels[1] and reels[1] == reels[2]
			assert_eq(three, r.won, "reels %s won %s" % [str(reels), str(r.won)])
			if r.jackpot:
				assert_eq(reels[0], GameResolver.SLOT_JACKPOT_SYMBOL)
			elif r.won:
				assert_ne(reels[0], GameResolver.SLOT_JACKPOT_SYMBOL)
			assert_eq(r.loud, r.jackpot)


func test_slots_jackpot_is_rare_loud_and_pays_big() -> void:
	var table := _table(HR.GameType.SLOTS)
	var rng := _rng(42)
	var jackpots := 0
	var spins := 20000
	for i in spins:
		var r := GameResolver.resolve(table, PID, 10, {}, rng, MAX_BET)
		if r.jackpot:
			jackpots += 1
			assert_true(r.won)
			assert_true(r.loud)
			assert_eq(r.payout, roundi(10 * (1.0 + Tuning.SLOT_JACKPOT_PAYOUT)))
	var rate := float(jackpots) / spins
	assert_gt(jackpots, 0, "some jackpots")
	assert_lt(rate, Tuning.SLOT_JACKPOT_CHANCE * 2.0, "jackpots stay rare")


func test_big_wheel_is_loud_and_segment_matches() -> void:
	for s in SEEDS:
		var rng := _rng(s)
		var table := _table(HR.GameType.BIG_WHEEL)
		for i in 10:
			var r := GameResolver.resolve(table, PID, 10, {"throw": i == 9}, rng, MAX_BET)
			assert_true(r.loud, "big wheel always loud")
			var seg: int = r.detail["segment"]
			assert_between(seg, 0, GameResolver.WHEEL_LABELS.size() - 1)
			assert_eq(r.detail["label"], GameResolver.WHEEL_LABELS[seg])
			assert_eq(GameResolver.wheel_segment_wins(seg), r.won)
			assert_eq(r.detail["label"] == GameResolver.WHEEL_WIN_LABEL, r.won)


func test_dice_detail_matches_outcome() -> void:
	for s in SEEDS:
		var rng := _rng(s)
		var table := _table(HR.GameType.DICE)
		for i in 10:
			var call := "low" if i % 2 == 0 else "high"
			var r := GameResolver.resolve(table, PID, 10, {"call": call, "throw": i == 9}, rng, MAX_BET)
			var dice: Array = r.detail["dice"]
			assert_eq(dice.size(), 2)
			assert_between(dice[0], 1, 6)
			assert_between(dice[1], 1, 6)
			var total: int = r.detail["total"]
			assert_eq(total, dice[0] + dice[1])
			assert_eq(r.detail["call"], call)
			var wins := total >= 8 if call == "high" else total <= 6
			assert_eq(wins, r.won, "call %s total %d" % [call, total])
			assert_false(r.loud)


func test_roulette_wheel_colors() -> void:
	assert_eq(GameResolver.roulette_color(0), "green")
	var reds := 0
	var blacks := 0
	for n in range(1, 37):
		var c := GameResolver.roulette_color(n)
		if c == "red":
			reds += 1
		elif c == "black":
			blacks += 1
	assert_eq(reds, 18)
	assert_eq(blacks, 18)
	for n: int in [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]:
		assert_eq(GameResolver.roulette_color(n), "red", str(n))
	for n: int in [2, 4, 6, 8, 10, 11, 13, 15, 17, 20, 22, 24, 26, 28, 29, 31, 33, 35]:
		assert_eq(GameResolver.roulette_color(n), "black", str(n))


func test_roulette_detail_matches_outcome() -> void:
	for s in SEEDS:
		var rng := _rng(s)
		var table := _table(HR.GameType.ROULETTE)
		for i in 12:
			var choice: Dictionary
			match i % 3:
				0:
					choice = {"kind": "color", "color": "red"}
				1:
					choice = {"kind": "color", "color": "black"}
				_:
					choice = {"kind": "number", "number": (s + i) % 37}
			choice["throw"] = i == 11
			var r := GameResolver.resolve(table, PID, 10, choice, rng, MAX_BET)
			var n: int = r.detail["number"]
			assert_between(n, 0, 36)
			assert_eq(r.detail["color"], GameResolver.roulette_color(n))
			assert_eq(r.detail["kind"], choice["kind"])
			if choice["kind"] == "color":
				assert_eq(r.detail["pick"], choice["color"])
				assert_eq(r.detail["color"] == choice["color"], r.won, "number %d bet %s" % [n, choice["color"]])
			else:
				assert_eq(r.detail["pick"], choice["number"])
				assert_eq(n == choice["number"], r.won)


func test_roulette_color_bet_can_lose_on_zero() -> void:
	var table := _table(HR.GameType.ROULETTE)
	var rng := _rng(6)
	var zeros := 0
	for i in ROUNDS:
		var r := GameResolver.resolve(table, PID, 10, {"kind": "color", "color": "black"}, rng, MAX_BET)
		if r.detail["number"] == 0:
			zeros += 1
			assert_false(r.won)
			assert_eq(r.detail["color"], "green")
	assert_gt(zeros, 0, "0 comes up on some losses")


# --- Shared dice roll -------------------------------------------------------

func test_shared_roll_one_result_for_everyone() -> void:
	for s in SEEDS:
		var table := _table(HR.GameType.DICE)
		var bets := [{"pid": 1, "bet": 10, "throw": false}, {"pid": 2, "bet": 50, "throw": false}, {"pid": 3, "bet": 20, "throw": false}]
		var out := GameResolver.resolve_shared_roll(table, bets, _rng(s), MAX_BET)
		assert_eq(out.size(), 3)
		var r1: BetResult = out[1]
		for pid: int in [1, 2, 3]:
			var r: BetResult = out[pid]
			assert_eq(r.pid, pid)
			assert_eq(r.won, r1.won)
			assert_eq(r.detail["dice"], r1.detail["dice"])
			assert_eq(r.detail["total"], r1.detail["total"])
			assert_true(r.detail["shared"])
			assert_eq(GameResolver.dice_call_wins(r.detail["call"], r.detail["total"]), r.won)
			assert_eq(r.net, r.payout - r.bet)
		assert_eq((out[2] as BetResult).payout, (50 * 2) if r1.won else 0)


func test_shared_roll_splits_crew_heat_among_winners() -> void:
	var table := _table(HR.GameType.DICE)
	table.record_win(2)
	var bets := [{"pid": 1, "bet": 10, "throw": false}, {"pid": 2, "bet": 100, "throw": false}, {"pid": 3, "bet": 30, "throw": true}]
	var rng := _rng(1)
	var out: Dictionary = {}
	for i in 50:
		out = GameResolver.resolve_shared_roll(table, bets, rng, MAX_BET)
		if (out[1] as BetResult).won:
			break
	var r1: BetResult = out[1]
	var r2: BetResult = out[2]
	var r3: BetResult = out[3]
	assert_true(r1.won and r2.won, "found a winning roll")
	var total := HeatRules.win_heat(HR.GameType.DICE, 10, MAX_BET, r1.streak) + HeatRules.win_heat(HR.GameType.DICE, 100, MAX_BET, r2.streak)
	assert_almost_eq(r1.heat, total / 2.0, 0.0001)
	assert_almost_eq(r2.heat, total / 2.0, 0.0001)
	assert_false(r3.won, "thrower loses a winning roll")
	assert_true(r3.intentional_loss)
	assert_almost_eq(r3.heat, Tuning.LOSE_ON_PURPOSE_HEAT)
	assert_ne(r3.detail["call"], r1.detail["call"], "thrower bet the other way")
	assert_false(GameResolver.dice_call_wins(r3.detail["call"], r3.detail["total"]))


func test_shared_roll_throwers_always_lose() -> void:
	for s in SEEDS:
		var table := _table(HR.GameType.DICE)
		var bets := [{"pid": 1, "bet": 10, "throw": true}, {"pid": 2, "bet": 10, "throw": false, "call": "low"}]
		var out := GameResolver.resolve_shared_roll(table, bets, _rng(s), MAX_BET)
		var r1: BetResult = out[1]
		var r2: BetResult = out[2]
		assert_false(r1.won)
		assert_true(r1.intentional_loss)
		assert_eq(r2.detail["call"], "low", "crew call comes from the honest bettor")
		assert_eq(GameResolver.dice_call_wins(r1.detail["call"], r1.detail["total"]), false)
		assert_eq(GameResolver.dice_call_wins(r2.detail["call"], r2.detail["total"]), r2.won)
		if r2.won:
			assert_almost_eq(r2.heat, HeatRules.win_heat(HR.GameType.DICE, 10, MAX_BET, r2.streak), 0.0001)
		else:
			assert_almost_eq(r2.heat, 0.0)
	var all_throw := GameResolver.resolve_shared_roll(_table(HR.GameType.DICE), [{"pid": 4, "bet": 5, "throw": true}], _rng(2), MAX_BET)
	assert_false((all_throw[4] as BetResult).won)
	assert_true(GameResolver.resolve_shared_roll(_table(HR.GameType.DICE), [], _rng(2), MAX_BET).is_empty())


func test_shared_roll_win_rate() -> void:
	var table := _table(HR.GameType.DICE)
	var rng := _rng(55)
	var wins := 0
	var bets := [{"pid": 1, "bet": 10, "throw": false}, {"pid": 2, "bet": 10, "throw": false}]
	for i in ROUNDS:
		if (GameResolver.resolve_shared_roll(table, bets, rng, MAX_BET)[1] as BetResult).won:
			wins += 1
	assert_almost_eq(float(wins) / ROUNDS, Tuning.WIN_RATE, RATE_TOLERANCE)
	table.mark_cooled(2)
	wins = 0
	for i in ROUNDS:
		if (GameResolver.resolve_shared_roll(table, bets, rng, MAX_BET)[1] as BetResult).won:
			wins += 1
	assert_almost_eq(float(wins) / ROUNDS, Tuning.COOLED_WIN_RATE, RATE_TOLERANCE, "a cooled bettor cools the shared roll")


# --- High-low ---------------------------------------------------------------

func test_high_low_cards_match_outcome() -> void:
	for s in SEEDS:
		var rng := _rng(s)
		var table := _table(HR.GameType.HIGH_LOW)
		var run := HighLowRun.new(table, PID, 10, rng, MAX_BET, 1.0)
		var guesses := 0
		while not run.finished and guesses < 12:
			var base := run.current_card
			assert_between(base, 3, 13, "guess base keeps both answers possible")
			var higher := base <= 8
			var r := run.guess(higher, guesses == 10)
			guesses += 1
			var next: int = r.detail["next_card"]
			assert_eq(r.detail["card"], base)
			assert_between(next, HighLowRun.CARD_MIN, HighLowRun.CARD_MAX)
			assert_ne(next, base, "never a tie")
			assert_eq((next > base) == higher, r.won, "base %d next %d higher %s" % [base, next, str(higher)])
			if r.won and not r.detail["redeal"]:
				assert_eq(run.current_card, next)


func test_high_low_pot_doubles_and_cash_out_pays_it() -> void:
	var rng := _rng(17)
	for attempt in 50:
		var table := _table(HR.GameType.HIGH_LOW)
		var run := HighLowRun.new(table, PID, 20, rng, MAX_BET, 1.2)
		assert_eq(run.pot, 20)
		var r := run.guess(true)
		if not r.won:
			continue
		var first_pot := GameResolver.win_payout(20, Tuning.GAMES[HR.GameType.HIGH_LOW]["payout"], 1.2)
		assert_eq(run.pot, first_pot, "first win pays the low payout")
		assert_eq(r.payout, 0, "chips ride in the pot")
		assert_eq(r.net, 0)
		assert_eq(r.detail["pot"], first_pot)
		var r2 := run.guess(run.current_card <= 8)
		if not r2.won:
			continue
		assert_eq(run.pot, first_pot * 2, "a further win doubles the pot")
		assert_eq(run.streak, 2)
		var c := run.cash_out()
		assert_true(run.finished)
		assert_true(c.won)
		assert_eq(c.payout, first_pot * 2)
		assert_eq(c.net, first_pot * 2 - 20)
		assert_almost_eq(c.heat, 0.0)
		var after := run.cash_out()
		assert_eq(after.payout, 0, "cashing out twice pays nothing")
		return
	fail("never won two guesses in a row")


func test_high_low_loss_ends_run() -> void:
	var rng := _rng(23)
	var losses := 0
	for attempt in 200:
		var table := _table(HR.GameType.HIGH_LOW)
		table.record_win(PID)
		var run := HighLowRun.new(table, PID, 20, rng, MAX_BET, 1.0)
		var r := run.guess(true)
		if r.won:
			continue
		losses += 1
		assert_true(run.finished)
		assert_eq(run.pot, 0)
		assert_eq(r.payout, 0)
		assert_eq(r.net, -20)
		assert_almost_eq(r.heat, 0.0)
		assert_eq(table.streak(PID), 0)
		var again := run.guess(true)
		assert_eq(again.payout, 0)
		assert_almost_eq(again.heat, 0.0)
		assert_eq(run.cash_out().payout, 0)
	assert_gt(losses, 0)


func test_high_low_heat_per_win_uses_streak() -> void:
	var table := _table(HR.GameType.HIGH_LOW)
	var rng := _rng(31)
	var run := HighLowRun.new(table, PID, 50, rng, MAX_BET, 1.0)
	var checked := 0
	while not run.finished:
		var r := run.guess(run.current_card <= 8)
		if r.won:
			checked += 1
			assert_eq(r.streak, table.streak(PID))
			var expected := HeatRules.win_heat(HR.GameType.HIGH_LOW, 50, MAX_BET, r.streak)
			assert_almost_eq(r.heat, expected, 0.0001)
			var base := HeatRules.win_heat(HR.GameType.HIGH_LOW, 50, MAX_BET, 1)
			assert_almost_eq(r.heat - base, Tuning.HIGH_LOW_STREAK_HEAT_STEP * (r.streak - 1), 0.0001)
	assert_gt(checked, 1)


func test_high_low_throw_and_win_rate() -> void:
	var rng := _rng(37)
	var wins := 0
	var cooled_wins := 0
	for i in ROUNDS:
		var table := _table(HR.GameType.HIGH_LOW)
		var run := HighLowRun.new(table, PID, 10, rng, MAX_BET, 1.0)
		if run.guess(rng.randf() < 0.5).won:
			wins += 1
		var cooled := _table(HR.GameType.HIGH_LOW)
		cooled.mark_cooled(PID)
		var crun := HighLowRun.new(cooled, PID, 10, rng, MAX_BET, 1.0)
		if crun.guess(true).won:
			cooled_wins += 1
	assert_almost_eq(float(wins) / ROUNDS, Tuning.WIN_RATE, RATE_TOLERANCE)
	assert_almost_eq(float(cooled_wins) / ROUNDS, Tuning.COOLED_WIN_RATE, RATE_TOLERANCE)
	var t := _table(HR.GameType.HIGH_LOW)
	var thrown := HighLowRun.new(t, PID, 10, rng, MAX_BET, 1.0).guess(true, true)
	assert_false(thrown.won)
	assert_true(thrown.intentional_loss)
	assert_almost_eq(thrown.heat, Tuning.LOSE_ON_PURPOSE_HEAT)
	assert_true(thrown.detail["next_card"] < thrown.detail["card"])


# --- Blackjack --------------------------------------------------------------

func test_blackjack_totals_with_soft_aces() -> void:
	assert_eq(BlackjackRound.hand_total([11, 10]), 21)
	assert_eq(BlackjackRound.hand_total([11, 11]), 12)
	assert_eq(BlackjackRound.hand_total([11, 6, 10]), 17)
	assert_eq(BlackjackRound.hand_total([11, 11, 9]), 21)
	assert_eq(BlackjackRound.hand_total([10, 10, 5]), 25)
	assert_true(BlackjackRound.is_soft([11, 6]))
	assert_false(BlackjackRound.is_soft([11, 6, 10]))
	assert_false(BlackjackRound.is_soft([10, 7]))


func test_blackjack_deal() -> void:
	for s in SEEDS:
		var hand := BlackjackRound.new(_table(HR.GameType.BLACKJACK), PID, 10, _rng(s), MAX_BET, 1.0)
		assert_eq(hand.player_cards.size(), 2)
		assert_eq(hand.dealer_cards.size(), 1, "hole card hidden until stand")
		for c: int in hand.player_cards + hand.dealer_cards:
			assert_between(c, 2, 11)
		assert_false(hand.finished)
		if not hand.will_win:
			assert_ne(hand.player_total(), 21, "a losing hand never opens on 21")


func test_blackjack_winning_hand_never_busts_below_21() -> void:
	var checked := 0
	for s in SEEDS:
		var table := _table(HR.GameType.BLACKJACK)
		var hand := BlackjackRound.new(table, PID, 10, _rng(s), MAX_BET, 1.0)
		if not hand.will_win:
			continue
		checked += 1
		while hand.player_total() < 21:
			hand.hit()
			assert_lte(hand.player_total(), 21)
			assert_false(hand.finished)
		var r := hand.stand()
		assert_true(r.won, "pre-rolled win stands and wins")
		assert_lte(r.detail["player_total"], 21)
	assert_gt(checked, SEEDS / 2)


func test_blackjack_hitting_hard_21_busts_on_purpose() -> void:
	var checked := 0
	for s in SEEDS:
		var table := _table(HR.GameType.BLACKJACK)
		table.record_win(PID)
		var hand := BlackjackRound.new(table, PID, 10, _rng(s), MAX_BET, 1.0)
		if not hand.will_win:
			continue
		while not (hand.player_total() == 21 and not BlackjackRound.is_soft(hand.player_cards)):
			hand.hit()
		hand.hit()
		checked += 1
		assert_true(hand.finished)
		assert_gt(hand.player_total(), 21)
		var r := hand.result
		assert_not_null(r)
		assert_false(r.won)
		assert_true(r.intentional_loss)
		assert_almost_eq(r.heat, Tuning.LOSE_ON_PURPOSE_HEAT)
		assert_eq(r.payout, 0)
		assert_eq(table.streak(PID), 0)
		assert_eq(hand.stand(), r, "stand after a bust returns the same result")
		assert_eq(hand.hit(), 0)
		assert_true(r.detail["player_bust"])
		assert_eq(hand.dealer_cards.size(), 2, "hole card revealed")
	assert_gt(checked, 0)


func test_blackjack_stand_reveals_matching_dealer_hand() -> void:
	for s in SEEDS:
		var rng := _rng(s)
		var table := _table(HR.GameType.BLACKJACK)
		var hand := BlackjackRound.new(table, PID, 10, rng, MAX_BET, 1.3)
		var up := hand.dealer_cards[0]
		var hits := s % 3
		for i in hits:
			if hand.finished or hand.player_total() >= 17:
				break
			hand.hit()
		var r := hand.stand()
		var p: int = r.detail["player_total"]
		var d: int = r.detail["dealer_total"]
		assert_eq(p, BlackjackRound.hand_total(r.detail["player_cards"]))
		assert_eq(d, BlackjackRound.hand_total(r.detail["dealer_cards"]))
		if r.detail["player_bust"]:
			assert_false(r.won)
			continue
		assert_eq(r.won, hand.will_win)
		assert_eq(r.detail["dealer_cards"][0], up, "up card stays")
		_assert_dealer_rule(r.detail["dealer_cards"], "seed %d" % s)
		if r.won:
			assert_true(d > 21 or d < p, "player %d beats dealer %d" % [p, d])
			assert_eq(r.payout, roundi(10 * (1.0 + Tuning.GAMES[HR.GameType.BLACKJACK]["payout"] * 1.3)))
			assert_almost_eq(r.heat, HeatRules.win_heat(HR.GameType.BLACKJACK, 10, MAX_BET, r.streak), 0.0001)
		else:
			assert_true(d <= 21 and d > p, "dealer %d beats player %d" % [d, p])
			assert_almost_eq(r.heat, 0.0)
			assert_false(r.intentional_loss)


func test_blackjack_losing_hand_never_reaches_21() -> void:
	var checked := 0
	for s in SEEDS:
		var hand := BlackjackRound.new(_table(HR.GameType.BLACKJACK), PID, 10, _rng(s), MAX_BET, 1.0)
		if hand.will_win:
			continue
		checked += 1
		while not hand.finished:
			hand.hit()
			if not hand.finished:
				assert_ne(hand.player_total(), 21)
		var r := hand.result
		assert_false(r.won)
		assert_false(r.intentional_loss, "a pre-rolled loss busts honestly")
		assert_almost_eq(r.heat, 0.0)
	assert_gt(checked, 0)


## Hitting on 17-20 must not turn a pre-rolled loss into free cooling: only a
## bust that gives up a pre-rolled win (hitting past 21) is a thrown loss.
func test_blackjack_bust_is_thrown_only_when_it_gives_up_a_win() -> void:
	var losers := 0
	var winners := 0
	for s in SEEDS:
		var table := _table(HR.GameType.BLACKJACK)
		table.mark_cooled(PID)
		var hand := BlackjackRound.new(table, PID, 10, _rng(s), MAX_BET, 1.0)
		var draws := 0
		while not hand.finished and draws < 30:
			hand.hit()
			draws += 1
		assert_true(hand.finished, "seed %d" % s)
		var r := hand.result
		assert_false(r.won)
		assert_eq(r.intentional_loss, hand.will_win, "seed %d cards %s" % [s, str(hand.player_cards)])
		if hand.will_win:
			winners += 1
			assert_almost_eq(r.heat, Tuning.LOSE_ON_PURPOSE_HEAT)
		else:
			losers += 1
			assert_almost_eq(r.heat, 0.0, 0.0001, "no free cooling on a hand that was lost anyway")
	assert_gt(losers, 0)
	assert_gt(winners, 0)


## Always hitting on 17-20 must not cool you down more than standing does.
func test_blackjack_hitting_on_17_plus_is_not_a_free_heat_sink() -> void:
	var stand_heat := 0.0
	var hit_heat := 0.0
	var stand_wins := 0
	var hit_wins := 0
	for s in SEEDS:
		var a := _table(HR.GameType.BLACKJACK)
		a.mark_cooled(PID)
		var stand_hand := BlackjackRound.new(a, PID, 10, _rng(s), MAX_BET, 1.0)
		var sr := stand_hand.stand()
		stand_heat += sr.heat
		stand_wins += 1 if sr.won else 0
		var b := _table(HR.GameType.BLACKJACK)
		b.mark_cooled(PID)
		var hit_hand := BlackjackRound.new(b, PID, 10, _rng(s), MAX_BET, 1.0)
		while not hit_hand.finished and hit_hand.player_total() >= 17 and hit_hand.player_total() < 21:
			hit_hand.hit()
		var hr := hit_hand.stand()
		hit_heat += hr.heat
		hit_wins += 1 if hr.won else 0
	assert_eq(hit_wins, stand_wins, "same deals, same pre-rolled winners")
	assert_gte(hit_heat, stand_heat - 0.0001, "hitting 17-20 gives no extra cooling")


func test_blackjack_win_rate() -> void:
	var rng := _rng(61)
	var wins := 0
	var cooled_wins := 0
	for i in ROUNDS:
		if BlackjackRound.new(_table(HR.GameType.BLACKJACK), PID, 10, rng, MAX_BET, 1.0).stand().won:
			wins += 1
		var cooled := _table(HR.GameType.BLACKJACK)
		cooled.mark_cooled(PID)
		if BlackjackRound.new(cooled, PID, 10, rng, MAX_BET, 1.0).stand().won:
			cooled_wins += 1
	assert_almost_eq(float(wins) / ROUNDS, Tuning.WIN_RATE, RATE_TOLERANCE)
	assert_almost_eq(float(cooled_wins) / ROUNDS, Tuning.COOLED_WIN_RATE, RATE_TOLERANCE)


func test_blackjack_forfeit_is_a_thrown_loss() -> void:
	for s in 50:
		var hand := BlackjackRound.new(_table(HR.GameType.BLACKJACK), PID, 10, _rng(s), MAX_BET, 1.0)
		var r := hand.forfeit()
		assert_false(r.won)
		assert_true(r.intentional_loss)
		assert_gt(r.detail["player_total"], 21)


# --- Fallbacks and BetResult ------------------------------------------------

func test_resolve_plays_high_low_and_blackjack_as_one_shot() -> void:
	for s in 100:
		var rng := _rng(s)
		var hl := GameResolver.resolve(_table(HR.GameType.HIGH_LOW), PID, 10, {"higher": true}, rng, MAX_BET)
		var base: int = hl.detail["card"]
		var next: int = hl.detail["next_card"]
		assert_eq(next > base, hl.won)
		if hl.won:
			assert_eq(hl.payout, GameResolver.win_payout(10, Tuning.GAMES[HR.GameType.HIGH_LOW]["payout"], 1.0))
			assert_gt(hl.heat, 0.0)
		else:
			assert_eq(hl.payout, 0)
		var bj := GameResolver.resolve(_table(HR.GameType.BLACKJACK), PID, 10, {}, rng, MAX_BET)
		var p: int = bj.detail["player_total"]
		var d: int = bj.detail["dealer_total"]
		assert_eq(bj.won, p <= 21 and (d > 21 or p > d))


func test_bet_result_dict_round_trip() -> void:
	var r := GameResolver.resolve(_table(HR.GameType.ROULETTE), PID, 10, {"kind": "number", "number": 4}, _rng(3), MAX_BET)
	var d := r.to_dict()
	for key: String in ["pid", "table_id", "game_type", "bet", "won", "payout", "net", "heat", "streak", "intentional_loss", "loud", "jackpot", "detail"]:
		assert_has(d, key)
	var back := BetResult.from_dict(d)
	assert_eq(back.to_dict(), d)


# --- Edge cases -------------------------------------------------------------

func test_high_low_pot_never_overflows() -> void:
	var rng := _rng(41)
	for attempt in 200:
		var run := HighLowRun.new(_table(HR.GameType.HIGH_LOW), PID, 10, rng, MAX_BET, 1.0)
		if not run.guess(true).won:
			continue
		run.pot = 1 << 62
		var r := run.guess(run.current_card <= 8)
		if not r.won:
			continue
		assert_gt(run.pot, 0, "doubling saturates instead of wrapping negative")
		assert_gt(r.detail["pot"], 0)
		var c := run.cash_out()
		assert_gt(c.payout, 0)
		assert_eq(c.net, c.payout - c.bet)
		return
	fail("never won a guess after the first")


func test_negative_bet_never_mints_chips() -> void:
	var rng := _rng(13)
	for t: int in TableGames.all_types():
		for i in 40:
			var choice := {"throw": i % 2 == 0, "kind": "number", "number": 3}
			var r := GameResolver.resolve(_table(t), PID, -50, choice, rng, MAX_BET)
			assert_gte(r.bet, 0, "game %d" % t)
			assert_gte(r.payout, 0, "game %d" % t)
			assert_lte(r.net, 0, "game %d: a bet below zero can't pay out chips" % t)
			assert_eq(r.net, r.payout - r.bet)
	var run := HighLowRun.new(_table(HR.GameType.HIGH_LOW), PID, -50, rng, MAX_BET, 1.0)
	assert_gte(run.pot, 0)
	var c := run.cash_out()
	assert_gte(c.payout, 0)
	assert_lte(c.net, 0)
	var bj := BlackjackRound.new(_table(HR.GameType.BLACKJACK), PID, -50, rng, MAX_BET, 1.0).stand()
	assert_gte(bj.payout, 0)
	assert_lte(bj.net, 0)
	var shared := GameResolver.resolve_shared_roll(_table(HR.GameType.DICE), [{"pid": 1, "bet": -50, "throw": true}], rng, MAX_BET)
	assert_lte((shared[1] as BetResult).net, 0)


func test_high_low_throw_after_wins_forfeits_the_pot() -> void:
	var rng := _rng(19)
	for attempt in 100:
		var table := _table(HR.GameType.HIGH_LOW)
		var run := HighLowRun.new(table, PID, 40, rng, MAX_BET, 1.0)
		if not run.guess(run.current_card <= 8).won:
			continue
		assert_gt(run.pot, 40)
		var r := run.guess(true, true)
		assert_true(run.finished)
		assert_false(r.won)
		assert_true(r.intentional_loss)
		assert_almost_eq(r.heat, Tuning.LOSE_ON_PURPOSE_HEAT)
		assert_eq(run.pot, 0)
		assert_eq(r.payout, 0)
		assert_eq(r.net, -40, "only the stake was ever taken from the pocket")
		assert_eq(table.streak(PID), 0)
		assert_eq(run.cash_out().payout, 0)
		return
	fail("never won a first guess")


func test_high_low_cash_out_before_guessing_returns_the_stake() -> void:
	var table := _table(HR.GameType.HIGH_LOW)
	var run := HighLowRun.new(table, PID, 30, _rng(2), MAX_BET, 1.0)
	var c := run.cash_out()
	assert_true(run.finished)
	assert_false(c.won)
	assert_eq(c.payout, 30)
	assert_eq(c.net, 0)
	assert_almost_eq(c.heat, 0.0)
	assert_false(c.intentional_loss)
	assert_eq(run.guess(true).bet, 0, "no guessing after cashing out")


func test_shared_roll_ignores_duplicate_pids() -> void:
	var table := _table(HR.GameType.DICE)
	var bets := [{"pid": 1, "bet": 10, "throw": false}, {"pid": 1, "bet": 999, "throw": true}, "junk"]
	var out := GameResolver.resolve_shared_roll(table, bets, _rng(4), MAX_BET)
	assert_eq(out.size(), 1)
	var r: BetResult = out[1]
	assert_eq(r.bet, 10, "first entry wins")
	assert_false(r.intentional_loss)
	assert_eq(r.detail["crew"], 1)


func test_zero_max_bet_still_gives_finite_heat() -> void:
	for t: int in TableGames.all_types():
		var table := _table(t)
		var rng := _rng(7 + t)
		for i in 30:
			var r := GameResolver.resolve(table, PID, 10, {}, rng, 0)
			assert_false(is_nan(r.heat) or is_inf(r.heat), "game %d" % t)
			if r.won:
				assert_gt(r.heat, 0.0, "game %d" % t)


func test_table_state_to_dict() -> void:
	var t := _table(HR.GameType.ROULETTE)
	t.seat(3)
	t.tick(2.0)
	t.record_win(3)
	t.mark_cooled(3)
	t.closed = true
	var d := t.to_dict()
	assert_eq(d["id"], &"t1")
	assert_eq(d["game_type"], HR.GameType.ROULETTE)
	assert_eq(d["area_id"], &"area_a")
	assert_true(d["closed"])
	var p: Dictionary = d["players"][3]
	assert_almost_eq(p["seconds"], 2.0)
	assert_eq(p["streak"], 1)
	assert_true(p["cooled"])
