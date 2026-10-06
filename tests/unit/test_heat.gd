extends TestCase
## HeatMeter (clamping, signals, levels) and HeatRules (every Heat source).

const EPS := 0.0001
const U := HR.HeatLevel.UNNOTICED
const W := HR.HeatLevel.WATCHED
const S := HR.HeatLevel.SUSPECTED
const X := HR.HeatLevel.WANTED

var changes: Array[Dictionary] = []
var levels: Array = []
## Signals in the order they arrived: "changed" / "level".
var order: Array[String] = []


func before_each() -> void:
	changes.clear()
	levels.clear()
	order.clear()


func _meter(initial: float = 0.0) -> HeatMeter:
	var m := HeatMeter.new(initial)
	m.changed.connect(_on_changed)
	m.level_changed.connect(_on_level_changed)
	return m


func _on_changed(value: float, delta: float, reason: StringName) -> void:
	changes.append({"value": value, "delta": delta, "reason": reason})
	order.append("changed")


func _on_level_changed(old_level: int, new_level: int) -> void:
	levels.append([old_level, new_level])
	order.append("level")


func _assert_change(index: int, value: float, delta: float, reason: StringName) -> void:
	if index >= changes.size():
		fail("no changed signal #%d (got %d)" % [index, changes.size()])
		return
	var c: Dictionary = changes[index]
	assert_almost_eq(float(c["value"]), value, EPS, "changed[%d].value" % index)
	assert_almost_eq(float(c["delta"]), delta, EPS, "changed[%d].delta" % index)
	assert_eq(c["reason"], reason, "changed[%d].reason" % index)


# --- HeatMeter: construction ------------------------------------------------

func test_init_defaults_to_zero() -> void:
	var m := HeatMeter.new()
	assert_eq(m.value, 0.0)
	assert_eq(m.level(), U)


func test_init_uses_initial_value() -> void:
	var m := HeatMeter.new(30.0)
	assert_eq(m.value, 30.0)
	assert_eq(m.level(), W)


func test_init_clamps_initial_value() -> void:
	assert_eq(HeatMeter.new(-5.0).value, 0.0)
	assert_eq(HeatMeter.new(150.0).value, Tuning.HEAT_MAX)
	assert_eq(HeatMeter.new(NAN).value, 0.0)


# --- HeatMeter: add and clamping --------------------------------------------

func test_add_returns_applied_delta() -> void:
	var m := _meter()
	assert_almost_eq(m.add(10.0, HeatRules.WIN), 10.0)
	assert_almost_eq(m.value, 10.0)
	assert_almost_eq(m.add(-4.0, HeatRules.LOSE_ON_PURPOSE), -4.0)
	assert_almost_eq(m.value, 6.0)


func test_add_clamps_at_max() -> void:
	var m := _meter(95.0)
	assert_almost_eq(m.add(20.0, HeatRules.WIN), 5.0, EPS, "only the room left is applied")
	assert_eq(m.value, Tuning.HEAT_MAX)
	assert_eq(m.add(5.0, HeatRules.WIN), 0.0, "already at max")
	assert_eq(m.value, Tuning.HEAT_MAX)
	assert_eq(changes.size(), 1, "no signal once pinned at max")


func test_add_clamps_at_zero() -> void:
	var m := _meter(3.0)
	assert_almost_eq(m.add(-10.0, HeatRules.CHANGE_OUTFIT), -3.0)
	assert_eq(m.value, 0.0)
	assert_eq(m.add(-1.0, HeatRules.FLOOR_DECAY), 0.0, "already at zero")
	assert_eq(m.value, 0.0)
	assert_eq(changes.size(), 1, "no signal once pinned at zero")


func test_add_zero_emits_nothing() -> void:
	var m := _meter(40.0)
	assert_eq(m.add(0.0, HeatRules.WIN), 0.0)
	assert_eq(changes.size(), 0)
	assert_eq(levels.size(), 0)


func test_add_nan_is_ignored() -> void:
	var m := _meter(40.0)
	assert_eq(m.add(NAN, HeatRules.WIN), 0.0)
	assert_eq(m.value, 40.0)
	assert_eq(changes.size(), 0)


func test_add_and_raise_to_infinity_clamp() -> void:
	var m := _meter(40.0)
	assert_almost_eq(m.add(INF, HeatRules.BUMP_GUARD), 60.0)
	assert_eq(m.value, Tuning.HEAT_MAX)
	assert_almost_eq(m.add(-INF, HeatRules.CHANGE_OUTFIT), -Tuning.HEAT_MAX)
	assert_eq(m.value, 0.0)
	assert_almost_eq(m.raise_to(INF, HeatRules.TACKLE), Tuning.HEAT_MAX)
	assert_eq(m.raise_to(-INF, HeatRules.TACKLE), 0.0)
	assert_eq(HeatMeter.new(INF).value, Tuning.HEAT_MAX)
	assert_eq(changes.size(), 3)


func test_random_walk_keeps_signals_consistent() -> void:
	# Seeded random adds / raises / resets: every changed signal reports the
	# value the meter holds, deltas sum to the net change, and level_changed
	# stays an unbroken chain of adjacent steps ending on level().
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var m := _meter(37.0)
	var delta_sum := 0.0
	for i in 600:
		var before := m.value
		var applied := 0.0
		var roll := rng.randi_range(0, 9)
		if roll == 0:
			m.reset()
			applied = m.value - before
		elif roll == 1:
			applied = m.raise_to(rng.randf_range(-20.0, 130.0), HeatRules.TACKLE)
		else:
			applied = m.add(rng.randf_range(-40.0, 40.0), HeatRules.WIN)
		assert_almost_eq(applied, m.value - before, EPS, "step %d returns applied delta" % i)
		assert_between(m.value, 0.0, Tuning.HEAT_MAX)
		delta_sum += applied
	for c in changes:
		assert_ne(float(c["delta"]), 0.0, "no zero-delta signals")
	var signal_sum := 0.0
	for c in changes:
		signal_sum += float(c["delta"])
	assert_almost_eq(signal_sum, m.value - 37.0, 0.01, "signal deltas sum to net change")
	assert_almost_eq(delta_sum, m.value - 37.0, 0.01, "returned deltas sum to net change")
	if not changes.is_empty():
		assert_almost_eq(float(changes[changes.size() - 1]["value"]), m.value, EPS)
	_assert_level_chain(W, m)


func test_add_full_range_both_ways() -> void:
	var m := _meter()
	assert_almost_eq(m.add(1000.0, HeatRules.BUMP_GUARD), Tuning.HEAT_MAX)
	assert_almost_eq(m.add(-1000.0, HeatRules.CHANGE_OUTFIT), -Tuning.HEAT_MAX)
	assert_eq(m.value, 0.0)


# --- HeatMeter: changed signal ----------------------------------------------

func test_changed_signal_args() -> void:
	var m := _meter()
	m.add(12.5, HeatRules.WIN)
	m.add(-2.5, HeatRules.LOSE_ON_PURPOSE)
	assert_eq(changes.size(), 2)
	_assert_change(0, 12.5, 12.5, HeatRules.WIN)
	_assert_change(1, 10.0, -2.5, HeatRules.LOSE_ON_PURPOSE)


func test_changed_reports_clamped_delta() -> void:
	var m := _meter(98.0)
	m.add(10.0, HeatRules.BUMP_GUARD)
	_assert_change(0, 100.0, 2.0, HeatRules.BUMP_GUARD)
	var low := _meter(1.5)
	low.add(-10.0, HeatRules.OFF_TABLE)
	_assert_change(1, 0.0, -1.5, HeatRules.OFF_TABLE)


func test_changed_reason_is_string_name() -> void:
	var m := _meter()
	m.add(1.0, HeatRules.CAMERA)
	assert_eq(typeof(changes[0]["reason"]), TYPE_STRING_NAME)


func test_signals_see_final_value_and_changed_comes_first() -> void:
	var m := _meter()
	var seen: Array[float] = []
	var on_level := func(_o: int, _n: int) -> void: seen.append(m.value)
	var on_change := func(_v: float, _d: float, _r: StringName) -> void: seen.append(m.value)
	m.level_changed.connect(on_level)
	m.changed.connect(on_change)
	m.add(85.0, HeatRules.WIN)
	# The lambdas capture m; disconnect to break the reference cycle.
	m.level_changed.disconnect(on_level)
	m.changed.disconnect(on_change)
	assert_eq(order, ["changed", "level", "level", "level"] as Array[String])
	assert_eq(seen.size(), 4)
	for v in seen:
		assert_almost_eq(v, 85.0, EPS, "value already updated when signals fire")


# --- HeatMeter: level_changed -----------------------------------------------

func test_level_changed_up_one() -> void:
	var m := _meter(20.0)
	m.add(10.0, HeatRules.WIN)
	assert_eq(levels, [[U, W]])


func test_level_changed_down_one() -> void:
	var m := _meter(30.0)
	m.add(-10.0, HeatRules.LOSE_ON_PURPOSE)
	assert_eq(levels, [[W, U]])


func test_no_level_changed_within_a_level() -> void:
	var m := _meter(26.0)
	m.add(10.0, HeatRules.WIN)
	m.add(-5.0, HeatRules.FLOOR_DECAY)
	assert_eq(changes.size(), 2)
	assert_eq(levels.size(), 0)


func test_level_changed_steps_through_every_boundary_up() -> void:
	var m := _meter()
	m.add(90.0, HeatRules.WIN)
	assert_eq(changes.size(), 1, "one changed for one add")
	assert_eq(levels, [[U, W], [W, S], [S, X]])
	assert_eq(m.level(), X)


func test_level_changed_steps_through_every_boundary_down() -> void:
	var m := _meter(90.0)
	m.add(-90.0, HeatRules.CHANGE_OUTFIT)
	assert_eq(levels, [[X, S], [S, W], [W, U]])
	assert_eq(m.level(), U)


func test_level_changed_skipping_one_level() -> void:
	var m := _meter(30.0)
	m.add(55.0, HeatRules.BUMP_GUARD)
	assert_eq(levels, [[W, S], [S, X]])
	levels.clear()
	m.add(-40.0, HeatRules.CHANGE_OUTFIT)
	assert_eq(levels, [[X, S], [S, W]])


func test_level_changed_at_exact_thresholds_up() -> void:
	var m := _meter()
	m.raise_to(Tuning.WATCHED_AT - 0.01, HeatRules.WIN)
	assert_eq(levels.size(), 0, "24.99 is still Unnoticed")
	m.raise_to(Tuning.WATCHED_AT, HeatRules.WIN)
	assert_eq(levels, [[U, W]])
	m.raise_to(Tuning.SUSPECTED_AT - 0.01, HeatRules.WIN)
	assert_eq(levels.size(), 1, "49.99 is still Watched")
	m.raise_to(Tuning.SUSPECTED_AT, HeatRules.WIN)
	assert_eq(levels, [[U, W], [W, S]])
	m.raise_to(Tuning.WANTED_AT - 0.01, HeatRules.WIN)
	assert_eq(levels.size(), 2, "79.99 is still Suspected")
	m.raise_to(Tuning.WANTED_AT, HeatRules.WIN)
	assert_eq(levels, [[U, W], [W, S], [S, X]])


func test_level_changed_at_exact_thresholds_down() -> void:
	var m := _meter(Tuning.WANTED_AT)
	m.add(-0.01, HeatRules.FLOOR_DECAY)
	assert_eq(levels, [[X, S]], "80 -> 79.99 drops out of Wanted")
	assert_eq(HeatMeter.new(Tuning.SUSPECTED_AT).level(), S)
	var s := _meter(Tuning.SUSPECTED_AT)
	s.add(-0.01, HeatRules.FLOOR_DECAY)
	assert_eq(levels[1], [S, W])
	var w := _meter(Tuning.WATCHED_AT)
	w.add(-0.01, HeatRules.FLOOR_DECAY)
	assert_eq(levels[2], [W, U])


func test_level_changed_round_trip_across_one_boundary() -> void:
	var m := _meter(24.0)
	m.add(2.0, HeatRules.WIN)
	m.add(-2.0, HeatRules.FLOOR_DECAY)
	m.add(2.0, HeatRules.WIN)
	assert_eq(levels, [[U, W], [W, U], [U, W]])


func test_level_changed_from_clamped_add() -> void:
	var m := _meter(70.0)
	m.add(500.0, HeatRules.BUMP_GUARD)
	assert_eq(levels, [[S, X]])
	levels.clear()
	m.add(-500.0, HeatRules.CHANGE_OUTFIT)
	assert_eq(levels, [[X, S], [S, W], [W, U]])


## level_changed must form an unbroken chain of adjacent steps from `start`
## that ends on the meter's current level.
func _assert_level_chain(start: int, m: HeatMeter, msg: String = "") -> void:
	var at: int = start
	for i in levels.size():
		var step: Array = levels[i]
		if int(step[0]) != at or absi(int(step[1]) - int(step[0])) != 1:
			fail("broken level chain at #%d: %s (believed %d). %s" % [i, str(levels), at, msg])
			return
		at = int(step[1])
	assert_eq(at, m.level(), "last announced level is the current level. %s" % msg)


func test_reentrant_add_from_changed_listener_keeps_level_chain() -> void:
	# A listener that cools the player off from inside `changed` (20 -> 55 -> 25)
	# must not leave level_changed out of order or ending on a stale level.
	var m := _meter(20.0)
	var cool := func(_v: float, _d: float, r: StringName) -> void:
		if r == HeatRules.WIN:
			m.add(-30.0, HeatRules.LOSE_ON_PURPOSE)
	m.changed.connect(cool)
	m.add(35.0, HeatRules.WIN)
	m.changed.disconnect(cool)
	assert_almost_eq(m.value, 25.0)
	assert_eq(levels, [[U, W]])
	_assert_level_chain(U, m)


func test_reentrant_add_from_level_listener_keeps_level_chain() -> void:
	# 0 -> 90; on reaching Watched a listener drops Heat to 20. The outer add
	# must not go on to announce Suspected and Wanted.
	var m := _meter()
	var on_level := func(o: int, n: int) -> void:
		if o == U and n == W:
			m.add(-70.0, HeatRules.CHANGE_OUTFIT)
	m.level_changed.connect(on_level)
	m.add(90.0, HeatRules.WIN)
	m.level_changed.disconnect(on_level)
	assert_almost_eq(m.value, 20.0)
	assert_eq(levels, [[U, W], [W, U]])
	_assert_level_chain(U, m)


func test_reentrant_raise_from_level_listener_keeps_level_chain() -> void:
	# 30 -> 0 via reset; on dropping to Unnoticed a listener raises to Wanted.
	var m := _meter(30.0)
	var on_level := func(_o: int, n: int) -> void:
		if n == U:
			m.raise_to(Tuning.WANTED_AT, HeatRules.TACKLE)
	m.level_changed.connect(on_level)
	m.reset()
	m.level_changed.disconnect(on_level)
	assert_eq(m.value, Tuning.WANTED_AT)
	assert_eq(levels, [[W, U], [U, W], [W, S], [S, X]])
	_assert_level_chain(W, m)


# --- HeatMeter: raise_to ----------------------------------------------------

func test_raise_to_raises_and_returns_delta() -> void:
	var m := _meter(10.0)
	assert_almost_eq(m.raise_to(80.0, HeatRules.TACKLE), 70.0)
	assert_eq(m.value, 80.0)
	assert_eq(m.level(), X)
	_assert_change(0, 80.0, 70.0, HeatRules.TACKLE)
	assert_eq(levels, [[U, W], [W, S], [S, X]])


func test_raise_to_never_lowers() -> void:
	var m := _meter(90.0)
	assert_eq(m.raise_to(80.0, HeatRules.TACKLE), 0.0)
	assert_eq(m.value, 90.0)
	assert_eq(m.raise_to(-10.0, HeatRules.TACKLE), 0.0)
	assert_eq(m.raise_to(NAN, HeatRules.TACKLE), 0.0)
	assert_eq(m.value, 90.0)
	assert_eq(changes.size(), 0)
	assert_eq(levels.size(), 0)


func test_raise_to_same_value_is_noop() -> void:
	var m := _meter(80.0)
	assert_eq(m.raise_to(80.0, HeatRules.TACKLE), 0.0)
	assert_eq(changes.size(), 0)


func test_raise_to_clamps_to_max() -> void:
	var m := _meter(50.0)
	assert_almost_eq(m.raise_to(500.0, HeatRules.TACKLE), 50.0)
	assert_eq(m.value, Tuning.HEAT_MAX)
	assert_eq(m.raise_to(500.0, HeatRules.TACKLE), 0.0, "already at max")
	assert_eq(changes.size(), 1)


func test_tackler_goes_straight_to_wanted() -> void:
	var m := _meter(5.0)
	m.raise_to(HeatRules.tackle_min_heat(), HeatRules.TACKLE)
	assert_eq(m.level(), X)
	assert_eq(HeatRules.tackle_min_heat(), Tuning.WANTED_AT)


# --- HeatMeter: reset -------------------------------------------------------

func test_reset_returns_to_zero_and_emits() -> void:
	var m := _meter(85.0)
	m.reset()
	assert_eq(m.value, 0.0)
	assert_eq(m.level(), U)
	_assert_change(0, 0.0, -85.0, HeatRules.RESET)
	assert_eq(levels, [[X, S], [S, W], [W, U]])


func test_reset_at_zero_emits_nothing() -> void:
	var m := _meter()
	m.reset()
	assert_eq(m.value, 0.0)
	assert_eq(changes.size(), 0)
	assert_eq(levels.size(), 0)


# --- HeatMeter: levels ------------------------------------------------------

func test_level_for_boundaries() -> void:
	assert_eq(HeatMeter.level_for(0.0), U)
	assert_eq(HeatMeter.level_for(24.99), U)
	assert_eq(HeatMeter.level_for(25.0), W)
	assert_eq(HeatMeter.level_for(49.99), W)
	assert_eq(HeatMeter.level_for(50.0), S)
	assert_eq(HeatMeter.level_for(79.99), S)
	assert_eq(HeatMeter.level_for(80.0), X)
	assert_eq(HeatMeter.level_for(100.0), X)


func test_level_for_uses_tuning_thresholds() -> void:
	assert_eq(HeatMeter.level_for(Tuning.WATCHED_AT), W)
	assert_eq(HeatMeter.level_for(Tuning.SUSPECTED_AT), S)
	assert_eq(HeatMeter.level_for(Tuning.WANTED_AT), X)
	assert_eq(HeatMeter.level_for(Tuning.HEAT_MAX), X)


func test_meter_level_matches_level_for() -> void:
	var cases := {0.0: U, 24.99: U, 25.0: W, 49.99: W, 50.0: S, 79.99: S, 80.0: X, 100.0: X}
	for v: float in cases:
		var m := HeatMeter.new(v)
		assert_eq(m.level(), int(cases[v]), "level at %s" % v)
		assert_eq(m.level(), HeatMeter.level_for(v))


func test_level_name() -> void:
	assert_eq(HeatMeter.level_name(U), "Unnoticed")
	assert_eq(HeatMeter.level_name(W), "Watched")
	assert_eq(HeatMeter.level_name(S), "Suspected")
	assert_eq(HeatMeter.level_name(X), "Wanted")


# --- HeatRules: reasons -----------------------------------------------------

func test_reason_constants_are_distinct_string_names() -> void:
	var contract: Array[StringName] = [
		HeatRules.WIN, HeatRules.STREAK, HeatRules.CAMPING, HeatRules.LOSE_ON_PURPOSE,
		HeatRules.AREA_CHANGE, HeatRules.OFF_TABLE, HeatRules.SLOT_BLEND, HeatRules.FLOOR_DECAY,
		HeatRules.CHANGE_OUTFIT, HeatRules.RUN_IN_VIEW, HeatRules.TABLE_JUMP, HeatRules.BUMP_GUARD,
		HeatRules.KNOCK_OVER, HeatRules.POSTER_MATCH, HeatRules.CASH_OUT, HeatRules.CAMERA,
		HeatRules.TACKLE, HeatRules.SHARED_ROLL,
	]
	var seen := {}
	for r in contract:
		assert_eq(typeof(r), TYPE_STRING_NAME, str(r))
		assert_ne(r, &"", "reason must not be empty")
		assert_false(seen.has(r), "duplicate reason %s" % r)
		seen[r] = true
		assert_has(HeatRules.ALL_REASONS, r)
	assert_false(seen.has(HeatRules.RESET), "RESET is its own reason")
	assert_eq(HeatRules.ALL_REASONS.size(), contract.size() + 1)


# --- HeatRules: win heat ----------------------------------------------------

func test_heat_class_per_game() -> void:
	assert_eq(HeatRules.heat_class_for(HR.GameType.SLOTS), HR.HeatClass.LOW)
	assert_eq(HeatRules.heat_class_for(HR.GameType.HIGH_LOW), HR.HeatClass.LOW)
	assert_eq(HeatRules.heat_class_for(HR.GameType.BIG_WHEEL), HR.HeatClass.HIGH)
	assert_eq(HeatRules.heat_class_for(HR.GameType.DICE), HR.HeatClass.MEDIUM)
	assert_eq(HeatRules.heat_class_for(HR.GameType.ROULETTE), HR.HeatClass.MEDIUM)
	assert_eq(HeatRules.heat_class_for(HR.GameType.BLACKJACK), HR.HeatClass.MEDIUM)
	assert_eq(HeatRules.heat_class_for(HR.GameType.ROULETTE, true), Tuning.ROULETTE_NUMBER_HEAT_CLASS)
	assert_eq(HeatRules.heat_class_for(HR.GameType.ROULETTE, true), HR.HeatClass.VERY_HIGH)
	assert_eq(HeatRules.heat_class_for(HR.GameType.DICE, true), HR.HeatClass.MEDIUM, "number flag is roulette-only")
	assert_eq(HeatRules.heat_class_for(99), HR.HeatClass.MEDIUM, "unknown game falls back")


func test_bet_scale() -> void:
	assert_almost_eq(HeatRules.bet_scale(0, 100), Tuning.BET_HEAT_SCALE_MIN)
	assert_almost_eq(HeatRules.bet_scale(100, 100), Tuning.BET_HEAT_SCALE_MAX)
	assert_almost_eq(HeatRules.bet_scale(50, 100), 1.0)
	assert_almost_eq(HeatRules.bet_scale(10, 100), 0.6)
	assert_almost_eq(HeatRules.bet_scale(200, 100), Tuning.BET_HEAT_SCALE_MAX, EPS, "over max clamps")
	assert_almost_eq(HeatRules.bet_scale(-5, 100), Tuning.BET_HEAT_SCALE_MIN, EPS, "negative clamps")
	assert_almost_eq(HeatRules.bet_scale(10, 0), Tuning.BET_HEAT_SCALE_MAX, EPS, "no max bet counts as max")


func test_win_heat_at_max_bet_first_win() -> void:
	for game: int in Tuning.GAMES:
		var cls: int = int(Tuning.GAMES[game]["heat_class"])
		var expected: float = float(Tuning.WIN_HEAT[cls]) * Tuning.BET_HEAT_SCALE_MAX
		assert_almost_eq(HeatRules.win_heat(game, 2500, 2500, 1), expected, EPS, "game %d" % game)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.SLOTS, 100, 100, 1), 4.5)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 100, 100, 1), 9.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.BIG_WHEEL, 100, 100, 1), 15.0)


func test_win_heat_at_min_bet() -> void:
	for casino: Dictionary in Tuning.CASINOS:
		var min_bet: int = int(casino["min_bet"])
		var max_bet: int = int(casino["max_bet"])
		var scale: float = lerpf(Tuning.BET_HEAT_SCALE_MIN, Tuning.BET_HEAT_SCALE_MAX, float(min_bet) / float(max_bet))
		for game: int in Tuning.GAMES:
			var cls: int = int(Tuning.GAMES[game]["heat_class"])
			assert_almost_eq(HeatRules.win_heat(game, min_bet, max_bet, 1), float(Tuning.WIN_HEAT[cls]) * scale, EPS,
				"%s game %d" % [casino["id"], game])
	# The Apex: min 250 / max 2500 -> scale 0.6.
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 250, 2500, 1), 3.6)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.BIG_WHEEL, 250, 2500, 1), 6.0)


func test_win_heat_at_zero_and_over_max_bet() -> void:
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 0, 1000, 1), 3.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 5000, 1000, 1), 9.0, EPS, "bet above max clamps")
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 100, 0, 1), 9.0, EPS, "no max bet is safe")


func test_win_heat_grows_with_bet() -> void:
	var prev := -1.0
	for bet in [0, 50, 100, 250, 500, 1000]:
		var h := HeatRules.win_heat(HR.GameType.ROULETTE, bet, 1000, 1)
		assert_gt(h, prev, "bet %d" % bet)
		prev = h
	assert_almost_eq(HeatRules.win_heat(HR.GameType.ROULETTE, 500, 1000, 1), 6.0, EPS, "half bet = base")


func test_win_heat_roulette_number_bet() -> void:
	assert_almost_eq(HeatRules.win_heat(HR.GameType.ROULETTE, 1000, 1000, 1, true), 36.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.ROULETTE, 100, 1000, 1, true), 14.4)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.ROULETTE, 0, 1000, 1, true), 12.0)
	assert_gt(HeatRules.win_heat(HR.GameType.ROULETTE, 100, 1000, 1, true),
		HeatRules.win_heat(HR.GameType.ROULETTE, 100, 1000, 1, false), "number beats color")
	assert_almost_eq(HeatRules.win_heat(HR.GameType.ROULETTE, 1000, 1000, 3, true), 40.0, EPS, "streak adds on top")


func test_win_heat_number_flag_ignored_for_other_games() -> void:
	for game: int in Tuning.GAMES:
		if game == HR.GameType.ROULETTE:
			continue
		assert_almost_eq(HeatRules.win_heat(game, 300, 1000, 2, true), HeatRules.win_heat(game, 300, 1000, 2, false))


func test_win_heat_streak_math() -> void:
	# Dice at max bet: base 6 × 1.5 = 9, +2 per win beyond the first.
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 1000, 1000, 1), 9.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 1000, 1000, 2), 11.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 1000, 1000, 3), 13.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 1000, 1000, 5), 17.0)
	# The streak bonus is not bet-scaled.
	assert_almost_eq(HeatRules.win_heat(HR.GameType.DICE, 0, 1000, 3), 3.0 + 4.0)
	for game: int in Tuning.GAMES:
		for streak in [1, 2, 4, 10]:
			var expected: float = HeatRules.base_win_heat(game, 400, 1000) \
				+ HeatRules.streak_step(game) * float(streak - 1)
			assert_almost_eq(HeatRules.win_heat(game, 400, 1000, streak), expected, EPS, "game %d streak %d" % [game, streak])


func test_win_heat_streak_below_one_counts_as_first_win() -> void:
	var first := HeatRules.win_heat(HR.GameType.BLACKJACK, 500, 1000, 1)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.BLACKJACK, 500, 1000, 0), first)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.BLACKJACK, 500, 1000, -3), first)
	assert_eq(HeatRules.streak_bonus(HR.GameType.HIGH_LOW, 0), 0.0)


func test_high_low_streak_builds_faster() -> void:
	assert_eq(HeatRules.streak_step(HR.GameType.HIGH_LOW), Tuning.HIGH_LOW_STREAK_HEAT_STEP)
	for game: int in Tuning.GAMES:
		if game != HR.GameType.HIGH_LOW:
			assert_eq(HeatRules.streak_step(game), Tuning.STREAK_HEAT_STEP, "game %d" % game)
	# High-low and slots share the LOW class, so only the streak differs.
	var hl1 := HeatRules.win_heat(HR.GameType.HIGH_LOW, 100, 100, 1)
	var sl1 := HeatRules.win_heat(HR.GameType.SLOTS, 100, 100, 1)
	assert_almost_eq(hl1, sl1, EPS, "same first win")
	assert_almost_eq(HeatRules.win_heat(HR.GameType.HIGH_LOW, 100, 100, 3), 4.5 + 8.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.SLOTS, 100, 100, 3), 4.5 + 4.0)
	assert_almost_eq(HeatRules.streak_bonus(HR.GameType.HIGH_LOW, 4), 12.0)


func test_win_heat_is_base_plus_bonus() -> void:
	var base := HeatRules.base_win_heat(HR.GameType.BIG_WHEEL, 250, 500)
	var bonus := HeatRules.streak_bonus(HR.GameType.BIG_WHEEL, 3)
	assert_almost_eq(base, 10.0)
	assert_almost_eq(bonus, 4.0)
	assert_almost_eq(HeatRules.win_heat(HR.GameType.BIG_WHEEL, 250, 500, 3), base + bonus)


func test_shared_roll_heat_splits_evenly() -> void:
	assert_almost_eq(HeatRules.shared_roll_heat(30.0, 3), 10.0)
	assert_almost_eq(HeatRules.shared_roll_heat(9.0, 1), 9.0)
	assert_almost_eq(HeatRules.shared_roll_heat(10.0, 4), 2.5)
	assert_eq(HeatRules.shared_roll_heat(30.0, 0), 0.0)


# --- HeatRules: passive -----------------------------------------------------

func test_passive_empty_ctx_is_floor_decay() -> void:
	assert_almost_eq(HeatRules.passive_rate({}), Tuning.FLOOR_DECAY_PER_SECOND)
	assert_eq(HeatRules.passive_rates({}).keys(), [HeatRules.FLOOR_DECAY])


func test_passive_floor_decay_in_other_zones() -> void:
	for zone: int in HR.ZoneType.values():
		if zone in [HR.ZoneType.BAR, HR.ZoneType.BUFFET, HR.ZoneType.RESTROOM]:
			continue
		var ctx := {"seated_game": -1, "zone": zone}
		assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.FLOOR_DECAY_PER_SECOND, EPS, "zone %d" % zone)
		assert_eq(HeatRules.passive_rates(ctx).keys(), [HeatRules.FLOOR_DECAY])


func test_passive_off_table_zones() -> void:
	for zone: int in [HR.ZoneType.BAR, HR.ZoneType.BUFFET, HR.ZoneType.RESTROOM]:
		var ctx := {"zone": zone}
		assert_true(HeatRules.is_off_table_zone(zone))
		assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.OFF_TABLE_HEAT_PER_SECOND, EPS, "zone %d" % zone)
		assert_eq(HeatRules.passive_rates(ctx).keys(), [HeatRules.OFF_TABLE])
	assert_false(HeatRules.is_off_table_zone(HR.ZoneType.FLOOR))
	assert_false(HeatRules.is_off_table_zone(HR.ZoneType.CASHIER))


func test_passive_slot_blend() -> void:
	var ctx := {"seated_game": HR.GameType.SLOTS, "zone": HR.ZoneType.SLOTS}
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.SLOT_BLEND_HEAT_PER_SECOND)
	assert_eq(HeatRules.passive_rates(ctx).keys(), [HeatRules.SLOT_BLEND])
	ctx["seconds_at_table"] = 1000.0
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.SLOT_BLEND_HEAT_PER_SECOND, EPS, "slots never camp")


func test_passive_seated_within_grace_is_zero() -> void:
	for game: int in Tuning.GAMES:
		if game == HR.GameType.SLOTS:
			continue
		for secs in [0.0, 10.0, Tuning.CAMP_GRACE_SECONDS - 0.01, Tuning.CAMP_GRACE_SECONDS]:
			var ctx := {"seated_game": game, "seconds_at_table": secs, "zone": HR.ZoneType.TABLES}
			assert_eq(HeatRules.passive_rate(ctx), 0.0, "game %d at %ss" % [game, secs])
			assert_true(HeatRules.passive_rates(ctx).is_empty())


func test_passive_camping_after_grace() -> void:
	for game: int in Tuning.GAMES:
		if game == HR.GameType.SLOTS:
			continue
		for secs in [Tuning.CAMP_GRACE_SECONDS + 0.01, 60.0, 600.0]:
			var ctx := {"seated_game": game, "seconds_at_table": secs}
			assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.CAMP_HEAT_PER_SECOND, EPS, "game %d at %ss" % [game, secs])
			assert_eq(HeatRules.passive_rates(ctx).keys(), [HeatRules.CAMPING])
	assert_eq(HeatRules.camping_rate(Tuning.CAMP_GRACE_SECONDS), 0.0)
	assert_eq(HeatRules.camping_rate(Tuning.CAMP_GRACE_SECONDS + 1.0), Tuning.CAMP_HEAT_PER_SECOND)


func test_passive_seated_ignores_zone() -> void:
	var ctx := {"seated_game": HR.GameType.DICE, "seconds_at_table": 5.0, "zone": HR.ZoneType.BAR}
	assert_eq(HeatRules.passive_rate(ctx), 0.0, "seated at a table: no off-table cool-down")


func test_passive_not_seated_ignores_seconds_at_table() -> void:
	# A stale seat timer must not keep camping Heat going after standing up.
	var ctx := {"seated_game": -1, "seconds_at_table": 500.0}
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.FLOOR_DECAY_PER_SECOND)
	ctx["zone"] = HR.ZoneType.RESTROOM
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.OFF_TABLE_HEAT_PER_SECOND)


func test_passive_accepts_string_name_and_float_keys() -> void:
	# ctx may be built with &"key" / dot syntax, or arrive over RPC with numbers as floats.
	var ctx := {&"seated_game": float(HR.GameType.BLACKJACK), &"seconds_at_table": 31, &"in_camera_view": 1}
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.CAMP_HEAT_PER_SECOND + Tuning.CAMERA_HEAT_PER_SECOND)
	var bar := {}
	bar.zone = float(HR.ZoneType.BAR)
	bar.pit_boss_view = true
	assert_almost_eq(HeatRules.passive_rate(bar), Tuning.OFF_TABLE_HEAT_PER_SECOND)
	assert_eq(HeatRules.gain_multiplier(bar), Tuning.PIT_BOSS_HEAT_MULT)


func test_passive_running_in_view() -> void:
	var ctx := {"zone": HR.ZoneType.FLOOR, "running_in_view": true}
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.RUN_IN_VIEW_HEAT_PER_SECOND + Tuning.FLOOR_DECAY_PER_SECOND)
	var rates := HeatRules.passive_rates(ctx)
	assert_almost_eq(float(rates[HeatRules.RUN_IN_VIEW]), Tuning.RUN_IN_VIEW_HEAT_PER_SECOND)
	assert_almost_eq(float(rates[HeatRules.FLOOR_DECAY]), Tuning.FLOOR_DECAY_PER_SECOND)
	ctx["running_in_view"] = false
	assert_almost_eq(HeatRules.passive_rate(ctx), Tuning.FLOOR_DECAY_PER_SECOND, EPS, "false adds nothing")


func test_passive_camera() -> void:
	var floor_ctx := {"in_camera_view": true}
	assert_almost_eq(HeatRules.passive_rate(floor_ctx), Tuning.CAMERA_HEAT_PER_SECOND + Tuning.FLOOR_DECAY_PER_SECOND)
	assert_almost_eq(float(HeatRules.passive_rates(floor_ctx)[HeatRules.CAMERA]), Tuning.CAMERA_HEAT_PER_SECOND)
	var slots_ctx := {"seated_game": HR.GameType.SLOTS, "in_camera_view": true}
	assert_almost_eq(HeatRules.passive_rate(slots_ctx), Tuning.CAMERA_HEAT_PER_SECOND + Tuning.SLOT_BLEND_HEAT_PER_SECOND)
	var camp_ctx := {"seated_game": HR.GameType.BLACKJACK, "seconds_at_table": 45.0, "in_camera_view": true}
	assert_almost_eq(HeatRules.passive_rate(camp_ctx), Tuning.CAMERA_HEAT_PER_SECOND + Tuning.CAMP_HEAT_PER_SECOND)
	var bar_ctx := {"zone": HR.ZoneType.BAR, "in_camera_view": true}
	assert_almost_eq(HeatRules.passive_rate(bar_ctx), Tuning.CAMERA_HEAT_PER_SECOND + Tuning.OFF_TABLE_HEAT_PER_SECOND)


func test_camera_heat_only_from_watched_up() -> void:
	var cold := {"in_camera_view": true, "heat": Tuning.WATCHED_AT - 0.1}
	assert_false(HeatRules.passive_rates(cold).has(HeatRules.CAMERA), "Unnoticed: security does nothing")
	assert_almost_eq(HeatRules.passive_rate(cold), Tuning.FLOOR_DECAY_PER_SECOND)
	var watched := {"in_camera_view": true, "heat": Tuning.WATCHED_AT}
	assert_almost_eq(float(HeatRules.passive_rates(watched)[HeatRules.CAMERA]), Tuning.CAMERA_HEAT_PER_SECOND, EPS, "Watched: cameras follow you")


func test_passive_running_and_camera_stack() -> void:
	var ctx := {"zone": HR.ZoneType.TABLES, "running_in_view": true, "in_camera_view": true}
	var expected := Tuning.RUN_IN_VIEW_HEAT_PER_SECOND + Tuning.CAMERA_HEAT_PER_SECOND + Tuning.FLOOR_DECAY_PER_SECOND
	assert_almost_eq(HeatRules.passive_rate(ctx), expected)
	assert_eq(HeatRules.passive_rates(ctx).size(), 3)


func test_passive_rate_is_sum_of_rates() -> void:
	var contexts: Array[Dictionary] = [
		{},
		{"zone": HR.ZoneType.BUFFET, "running_in_view": true},
		{"seated_game": HR.GameType.ROULETTE, "seconds_at_table": 31.0, "in_camera_view": true},
		{"seated_game": HR.GameType.SLOTS, "running_in_view": true, "in_camera_view": true},
	]
	for ctx in contexts:
		var total := 0.0
		for r: float in HeatRules.passive_rates(ctx).values():
			total += r
		assert_almost_eq(HeatRules.passive_rate(ctx), total, EPS, str(ctx))


func test_effective_passive_rate_scales_gains_only() -> void:
	var camp := {"seated_game": HR.GameType.DICE, "seconds_at_table": 40.0, "pit_boss_view": true}
	assert_almost_eq(HeatRules.effective_passive_rate(camp), Tuning.CAMP_HEAT_PER_SECOND * Tuning.PIT_BOSS_HEAT_MULT)
	var run := {"running_in_view": true, "pit_boss_view": true}
	assert_almost_eq(HeatRules.effective_passive_rate(run),
		Tuning.RUN_IN_VIEW_HEAT_PER_SECOND * Tuning.PIT_BOSS_HEAT_MULT + Tuning.FLOOR_DECAY_PER_SECOND)
	var bar := {"zone": HR.ZoneType.BAR, "pit_boss_view": true}
	assert_almost_eq(HeatRules.effective_passive_rate(bar), Tuning.OFF_TABLE_HEAT_PER_SECOND, EPS, "cool-downs not multiplied")
	var bar_cam := {"zone": HR.ZoneType.BAR, "in_camera_view": true, "pit_boss_view": true}
	assert_almost_eq(HeatRules.effective_passive_rate(bar_cam),
		Tuning.OFF_TABLE_HEAT_PER_SECOND + Tuning.CAMERA_HEAT_PER_SECOND * Tuning.PIT_BOSS_HEAT_MULT)
	var no_boss := {"running_in_view": true}
	assert_almost_eq(HeatRules.effective_passive_rate(no_boss), HeatRules.passive_rate(no_boss))
	# passive_rate itself never applies the multiplier (callers use gain_multiplier).
	assert_almost_eq(HeatRules.passive_rate(camp), Tuning.CAMP_HEAT_PER_SECOND)
	assert_almost_eq(HeatRules.passive_rate(run), HeatRules.passive_rate(no_boss))


func test_passive_ticks_meter_over_time() -> void:
	var m := _meter(30.0)
	var ctx := {"zone": HR.ZoneType.BAR}
	for _i in 20:
		m.add(HeatRules.passive_rate(ctx) * 0.5, HeatRules.OFF_TABLE)
	assert_almost_eq(m.value, 10.0, EPS, "10 s at the bar = -20")
	assert_eq(levels, [[W, U]])
	var camp := _meter(20.0)
	var seated := {"seated_game": HR.GameType.BLACKJACK, "seconds_at_table": 60.0}
	for _i in 20:
		camp.add(HeatRules.passive_rate(seated) * 1.0, HeatRules.CAMPING)
	assert_almost_eq(camp.value, 30.0)


# --- HeatRules: pit boss ----------------------------------------------------

func test_gain_multiplier() -> void:
	assert_eq(HeatRules.gain_multiplier({}), 1.0)
	assert_eq(HeatRules.gain_multiplier({"pit_boss_view": false}), 1.0)
	assert_eq(HeatRules.gain_multiplier({"pit_boss_view": true}), Tuning.PIT_BOSS_HEAT_MULT)


func test_scale_gain_positive_only() -> void:
	var boss := {"pit_boss_view": true}
	assert_almost_eq(HeatRules.scale_gain(10.0, boss), 10.0 * Tuning.PIT_BOSS_HEAT_MULT)
	assert_almost_eq(HeatRules.scale_gain(-10.0, boss), -10.0, EPS, "losses are not multiplied")
	assert_eq(HeatRules.scale_gain(0.0, boss), 0.0)
	assert_almost_eq(HeatRules.scale_gain(10.0, {}), 10.0)
	var win := HeatRules.win_heat(HR.GameType.BIG_WHEEL, 500, 500, 1)
	assert_almost_eq(HeatRules.scale_gain(win, boss), 22.5)


# --- HeatRules: one-off events ----------------------------------------------

func test_event_heat_values() -> void:
	assert_eq(HeatRules.event_heat(HeatRules.LOSE_ON_PURPOSE), Tuning.LOSE_ON_PURPOSE_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.AREA_CHANGE), Tuning.AREA_CHANGE_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.CHANGE_OUTFIT), Tuning.CHANGE_OUTFIT_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.TABLE_JUMP), Tuning.TABLE_JUMP_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.BUMP_GUARD), Tuning.BUMP_GUARD_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.KNOCK_OVER), Tuning.KNOCK_OVER_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.POSTER_MATCH), Tuning.POSTER_MATCH_HEAT)
	assert_eq(HeatRules.event_heat(HeatRules.WIN), 0.0, "wins use win_heat")
	assert_eq(HeatRules.event_heat(&"nonsense"), 0.0)


func test_event_heat_signs_match_design_table() -> void:
	for up: StringName in [HeatRules.TABLE_JUMP, HeatRules.BUMP_GUARD, HeatRules.KNOCK_OVER, HeatRules.POSTER_MATCH]:
		assert_gt(HeatRules.event_heat(up), 0.0, str(up))
	for down: StringName in [HeatRules.LOSE_ON_PURPOSE, HeatRules.AREA_CHANGE, HeatRules.CHANGE_OUTFIT]:
		assert_lt(HeatRules.event_heat(down), 0.0, str(down))
	assert_gt(HeatRules.event_heat(HeatRules.BUMP_GUARD), HeatRules.event_heat(HeatRules.KNOCK_OVER), "bump is large, knock-over small")


func test_area_change_heat() -> void:
	assert_eq(HeatRules.area_change_heat(&"pit_a", &"pit_b", INF), Tuning.AREA_CHANGE_HEAT)
	assert_eq(HeatRules.area_change_heat(&"pit_a", &"bar", Tuning.AREA_CHANGE_COOLDOWN), Tuning.AREA_CHANGE_HEAT)
	assert_eq(HeatRules.area_change_heat(&"pit_a", &"pit_b", Tuning.AREA_CHANGE_COOLDOWN - 0.1), 0.0, "still cooling down")
	assert_eq(HeatRules.area_change_heat(&"pit_a", &"pit_a", INF), 0.0, "same area")
	assert_eq(HeatRules.area_change_heat(&"", &"pit_b", INF), 0.0, "just arrived")
	assert_eq(HeatRules.area_change_heat(&"pit_a", &"", INF), 0.0, "no area")


func test_table_jump_heat() -> void:
	assert_eq(HeatRules.table_jump_heat(&"t1", &"t2", 0.0, true), Tuning.TABLE_JUMP_HEAT)
	assert_eq(HeatRules.table_jump_heat(&"t1", &"t2", Tuning.TABLE_JUMP_WINDOW, true), Tuning.TABLE_JUMP_HEAT)
	assert_eq(HeatRules.table_jump_heat(&"t1", &"t2", Tuning.TABLE_JUMP_WINDOW + 0.01, true), 0.0, "outside window")
	assert_eq(HeatRules.table_jump_heat(&"t1", &"t2", 2.0, false), 0.0, "not in view")
	assert_eq(HeatRules.table_jump_heat(&"t1", &"t1", 2.0, true), 0.0, "same table")
	assert_eq(HeatRules.table_jump_heat(&"", &"t2", 2.0, true), 0.0, "no previous table")
	assert_eq(HeatRules.table_jump_heat(&"t1", &"t2", -1.0, true), 0.0, "never left")


func test_cash_out_heat_small_is_free() -> void:
	assert_eq(HeatRules.cash_out_heat(500, 100), 0.0)
	assert_eq(HeatRules.cash_out_heat(1000, 100), 0.0, "exactly the threshold")
	assert_eq(HeatRules.cash_out_heat(1, 100), 0.0)


func test_cash_out_heat_large() -> void:
	assert_almost_eq(HeatRules.cash_out_heat(1500, 100), 5.0)
	assert_almost_eq(HeatRules.cash_out_heat(2050, 100), 10.5)
	assert_almost_eq(HeatRules.cash_out_heat(3000, 100), Tuning.LARGE_CASHOUT_HEAT_MAX)
	assert_almost_eq(HeatRules.cash_out_heat(100000, 100), Tuning.LARGE_CASHOUT_HEAT_MAX, EPS, "capped")


func test_cash_out_heat_scales_with_casino_max_bet() -> void:
	var sals: int = int(Tuning.CASINOS[Tuning.BOTTOM_RUNG - 1]["max_bet"])
	var apex: int = int(Tuning.CASINOS[Tuning.TOP_RUNG - 1]["max_bet"])
	assert_almost_eq(HeatRules.cash_out_heat(5000, sals), Tuning.LARGE_CASHOUT_HEAT_MAX)
	assert_eq(HeatRules.cash_out_heat(5000, apex), 0.0)


func test_cash_out_heat_bad_inputs() -> void:
	assert_eq(HeatRules.cash_out_heat(0, 100), 0.0)
	assert_eq(HeatRules.cash_out_heat(-5000, 100), 0.0)
	assert_eq(HeatRules.cash_out_heat(5000, 0), 0.0)
	assert_eq(HeatRules.cash_out_heat(5000, -10), 0.0)


# --- Meter + rules together -------------------------------------------------

func test_lose_on_purpose_drops_a_level() -> void:
	var m := _meter(30.0)
	m.add(HeatRules.event_heat(HeatRules.LOSE_ON_PURPOSE), HeatRules.LOSE_ON_PURPOSE)
	assert_almost_eq(m.value, 20.0)
	assert_eq(levels, [[W, U]])
	_assert_change(0, 20.0, -10.0, HeatRules.LOSE_ON_PURPOSE)


func test_bump_guard_from_zero_is_watched() -> void:
	var m := _meter()
	m.add(HeatRules.event_heat(HeatRules.BUMP_GUARD), HeatRules.BUMP_GUARD)
	assert_eq(m.level(), W)


func test_win_streak_at_big_wheel_reaches_wanted() -> void:
	var m := _meter()
	var level_after: Array[int] = []
	for streak in range(1, 6):
		m.add(HeatRules.win_heat(HR.GameType.BIG_WHEEL, 1000, 1000, streak), HeatRules.WIN)
		level_after.append(m.level())
	# 15, 32, 51, 72, 95
	assert_almost_eq(m.value, 95.0)
	assert_eq(level_after, [U, W, S, S, X] as Array[int])
	assert_eq(levels, [[U, W], [W, S], [S, X]])
	assert_eq(changes.size(), 5)
