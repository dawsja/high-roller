class_name HeatRules
extends RefCounted
## How much Heat each situation and event is worth (design doc "Heat" table).
## Static functions only; every number comes from Tuning. Positive values raise
## Heat, negative values lower it. Callers apply the result to a HeatMeter with
## the matching reason constant below, scaling gains with `scale_gain` where a
## pit boss is watching.

# --- Reasons (HeatMeter.changed `reason`) ------------------------------------
const WIN := &"win"
const STREAK := &"streak"
const CAMPING := &"camping"
const LOSE_ON_PURPOSE := &"lose_on_purpose"
const AREA_CHANGE := &"area_change"
const OFF_TABLE := &"off_table"
const SLOT_BLEND := &"slot_blend"
const FLOOR_DECAY := &"floor_decay"
const CHANGE_OUTFIT := &"change_outfit"
const RUN_IN_VIEW := &"run_in_view"
const TABLE_JUMP := &"table_jump"
const BUMP_GUARD := &"bump_guard"
const KNOCK_OVER := &"knock_over"
const POSTER_MATCH := &"poster_match"
const CASH_OUT := &"cash_out"
const CAMERA := &"camera"
const TACKLE := &"tackle"
const SHARED_ROLL := &"shared_roll"
## Used by HeatMeter.reset().
const RESET := &"reset"

const ALL_REASONS: Array[StringName] = [
	WIN, STREAK, CAMPING, LOSE_ON_PURPOSE, AREA_CHANGE, OFF_TABLE, SLOT_BLEND,
	FLOOR_DECAY, CHANGE_OUTFIT, RUN_IN_VIEW, TABLE_JUMP, BUMP_GUARD, KNOCK_OVER,
	POSTER_MATCH, CASH_OUT, CAMERA, TACKLE, SHARED_ROLL, RESET,
]

## Zones that count as "time off the tables".
const OFF_TABLE_ZONES: Array[int] = [HR.ZoneType.BAR, HR.ZoneType.BUFFET, HR.ZoneType.RESTROOM]


# --- Wins -------------------------------------------------------------------

## Heat for one win: base by heat class × bet scale + streak step × (streak − 1).
## `streak` counts this win (1 = first win; values below 1 count as 1).
## `number_bet` only matters for roulette (single number = very high Heat).
static func win_heat(game_type: int, bet: int, max_bet: int, streak: int, number_bet: bool = false) -> float:
	return base_win_heat(game_type, bet, max_bet, number_bet) + streak_bonus(game_type, streak)


## The bet-scaled part of win_heat, without the streak bonus.
static func base_win_heat(game_type: int, bet: int, max_bet: int, number_bet: bool = false) -> float:
	var base: float = float(Tuning.WIN_HEAT[heat_class_for(game_type, number_bet)])
	return base * bet_scale(bet, max_bet)


## The streak part of win_heat: step × (streak − 1), never negative.
static func streak_bonus(game_type: int, streak: int) -> float:
	return streak_step(game_type) * float(maxi(streak - 1, 0))


## Extra Heat per win beyond the first; high-low builds faster.
static func streak_step(game_type: int) -> float:
	if game_type == HR.GameType.HIGH_LOW:
		return Tuning.HIGH_LOW_STREAK_HEAT_STEP
	return Tuning.STREAK_HEAT_STEP


## HR.HeatClass of a win. Roulette number bets use ROULETTE_NUMBER_HEAT_CLASS.
## An unknown game type falls back to MEDIUM.
static func heat_class_for(game_type: int, number_bet: bool = false) -> int:
	if number_bet and game_type == HR.GameType.ROULETTE:
		return Tuning.ROULETTE_NUMBER_HEAT_CLASS
	if not Tuning.GAMES.has(game_type):
		return HR.HeatClass.MEDIUM
	return int(Tuning.GAMES[game_type]["heat_class"])


## lerp(BET_HEAT_SCALE_MIN, BET_HEAT_SCALE_MAX, bet / max_bet), ratio clamped to
## [0, 1]. A non-positive max_bet counts as betting the max.
static func bet_scale(bet: int, max_bet: int) -> float:
	var ratio: float = 1.0
	if max_bet > 0:
		ratio = clampf(float(bet) / float(max_bet), 0.0, 1.0)
	return lerpf(Tuning.BET_HEAT_SCALE_MIN, Tuning.BET_HEAT_SCALE_MAX, ratio)


## Each winner's share of a shared dice roll's total win Heat.
static func shared_roll_heat(total_heat: float, winners: int) -> float:
	if winners <= 0:
		return 0.0
	return total_heat / float(winners)


# --- Passive (per second) ---------------------------------------------------

## Heat per second from the current situation (sum of passive_rates).
## Does not include the pit boss multiplier; see effective_passive_rate.
static func passive_rate(ctx: Dictionary) -> float:
	var total: float = 0.0
	for rate: float in passive_rates(ctx).values():
		total += rate
	return total


## Per-second Heat by reason, so each part can be applied with its own reason.
## Only non-zero parts are present. ctx keys (all optional):
## `seated_game: int` (−1 = not seated), `seconds_at_table: float`,
## `zone: int` (HR.ZoneType, default FLOOR), `running_in_view: bool`,
## `in_camera_view: bool`.
## Seated at slots: SLOT_BLEND (slots never count as camping). Seated anywhere
## else: CAMPING once past CAMP_GRACE_SECONDS. Not seated: OFF_TABLE in a bar,
## buffet or restroom, otherwise FLOOR_DECAY. RUN_IN_VIEW and CAMERA add on top.
static func passive_rates(ctx: Dictionary) -> Dictionary:
	var rates: Dictionary = {}
	var seated_game: int = int(ctx.get("seated_game", -1))
	if seated_game == HR.GameType.SLOTS:
		rates[SLOT_BLEND] = Tuning.SLOT_BLEND_HEAT_PER_SECOND
	elif seated_game >= 0:
		var camp: float = camping_rate(float(ctx.get("seconds_at_table", 0.0)))
		if camp != 0.0:
			rates[CAMPING] = camp
	else:
		var zone: int = int(ctx.get("zone", HR.ZoneType.FLOOR))
		if is_off_table_zone(zone):
			rates[OFF_TABLE] = Tuning.OFF_TABLE_HEAT_PER_SECOND
		else:
			rates[FLOOR_DECAY] = Tuning.FLOOR_DECAY_PER_SECOND
	if bool(ctx.get("running_in_view", false)):
		rates[RUN_IN_VIEW] = Tuning.RUN_IN_VIEW_HEAT_PER_SECOND
	if bool(ctx.get("in_camera_view", false)):
		rates[CAMERA] = Tuning.CAMERA_HEAT_PER_SECOND
	return rates


## passive_rate with the pit boss multiplier applied to each positive part.
## Also reads `pit_boss_view: bool` from ctx.
static func effective_passive_rate(ctx: Dictionary) -> float:
	var total: float = 0.0
	for rate: float in passive_rates(ctx).values():
		total += scale_gain(rate, ctx)
	return total


## Heat per second for camping at one (non-slot) table.
static func camping_rate(seconds_at_table: float) -> float:
	if seconds_at_table > Tuning.CAMP_GRACE_SECONDS:
		return Tuning.CAMP_HEAT_PER_SECOND
	return 0.0


static func is_off_table_zone(zone: int) -> bool:
	return OFF_TABLE_ZONES.has(zone)


# --- Multipliers ------------------------------------------------------------

## ctx.pit_boss_view → PIT_BOSS_HEAT_MULT, else 1. Applies to positive gains only.
static func gain_multiplier(ctx: Dictionary) -> float:
	if bool(ctx.get("pit_boss_view", false)):
		return Tuning.PIT_BOSS_HEAT_MULT
	return 1.0


## Applies gain_multiplier to a positive amount; reductions pass through unchanged.
static func scale_gain(amount: float, ctx: Dictionary) -> float:
	if amount > 0.0:
		return amount * gain_multiplier(ctx)
	return amount


# --- One-off events ---------------------------------------------------------

## Flat Heat for an unconditional one-off event reason (LOSE_ON_PURPOSE,
## AREA_CHANGE, CHANGE_OUTFIT, TABLE_JUMP, BUMP_GUARD, KNOCK_OVER, POSTER_MATCH).
## 0 for any other reason. Use area_change_heat / table_jump_heat when the
## conditions still need checking.
static func event_heat(reason: StringName) -> float:
	match reason:
		LOSE_ON_PURPOSE:
			return Tuning.LOSE_ON_PURPOSE_HEAT
		AREA_CHANGE:
			return Tuning.AREA_CHANGE_HEAT
		CHANGE_OUTFIT:
			return Tuning.CHANGE_OUTFIT_HEAT
		TABLE_JUMP:
			return Tuning.TABLE_JUMP_HEAT
		BUMP_GUARD:
			return Tuning.BUMP_GUARD_HEAT
		KNOCK_OVER:
			return Tuning.KNOCK_OVER_HEAT
		POSTER_MATCH:
			return Tuning.POSTER_MATCH_HEAT
	return 0.0


## Cool-down for moving into a different game area. 0 if either area is empty
## (e.g. just arrived), the area didn't change, or the last area-change
## cool-down was under AREA_CHANGE_COOLDOWN seconds ago (pass INF if never).
static func area_change_heat(from_area: StringName, to_area: StringName, seconds_since_last: float) -> float:
	if from_area == &"" or to_area == &"" or from_area == to_area:
		return 0.0
	if seconds_since_last < Tuning.AREA_CHANGE_COOLDOWN:
		return 0.0
	return Tuning.AREA_CHANGE_HEAT


## Heat for sitting at `new_table` within TABLE_JUMP_WINDOW seconds of leaving a
## different table, in a guard's view. A negative `seconds_since_left` means
## there was no previous table.
static func table_jump_heat(left_table: StringName, new_table: StringName, seconds_since_left: float, in_view: bool) -> float:
	if not in_view or left_table == &"" or left_table == new_table:
		return 0.0
	if seconds_since_left < 0.0 or seconds_since_left > Tuning.TABLE_JUMP_WINDOW:
		return 0.0
	return Tuning.TABLE_JUMP_HEAT


## Large cash-out Heat: LARGE_CASHOUT_HEAT_PER_BET for every max bet's worth
## above LARGE_CASHOUT_BETS, capped at LARGE_CASHOUT_HEAT_MAX.
static func cash_out_heat(amount: int, max_bet: int) -> float:
	if amount <= 0 or max_bet <= 0:
		return 0.0
	var over: float = float(amount) / float(max_bet) - Tuning.LARGE_CASHOUT_BETS
	if over <= 0.0:
		return 0.0
	return minf(over * Tuning.LARGE_CASHOUT_HEAT_PER_BET, Tuning.LARGE_CASHOUT_HEAT_MAX)


## A tackler "goes straight to Wanted": use with HeatMeter.raise_to(_, TACKLE).
static func tackle_min_heat() -> float:
	return Tuning.WANTED_AT
