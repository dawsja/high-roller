class_name GameResolver
extends RefCounted
## Rolls single-shot bets (slots, big wheel, solo dice, roulette) and the crew's
## shared dice roll. The result is rolled first at the player's win rate for the
## table; `detail` is then built to match it. Also holds the settle/payout
## helpers HighLowRun and BlackjackRound share.
##
## choice keys: `throw: bool` (lose on purpose). Roulette: `kind` "color" (with
## `color` "red"/"black") or "number" (with `number` 0–36). Dice: `call` "high"
## (8–12 wins) or "low" (2–6 wins); 7 loses both. High-low: `higher: bool`.

# --- Slots ------------------------------------------------------------------
const SLOT_SYMBOLS: Array[String] = ["cherry", "lemon", "orange", "plum", "bell", "bar", "seven"]
## Three of these is the jackpot; plain wins show three of another symbol.
const SLOT_JACKPOT_SYMBOL := "seven"

# --- Big wheel --------------------------------------------------------------
const WHEEL_WIN_LABEL := "WIN"
const WHEEL_LOSE_LABEL := "BUST"
## Segment labels clockwise from the pointer's rest position.
const WHEEL_LABELS: Array[String] = [
	"WIN", "BUST", "WIN", "BUST", "WIN", "BUST", "WIN", "BUST",
	"WIN", "BUST", "WIN", "BUST", "WIN", "BUST", "WIN", "BUST",
]

# --- Dice -------------------------------------------------------------------
const DICE_CALL_HIGH := "high"
const DICE_CALL_LOW := "low"
## The total that loses for both calls.
const DICE_HOUSE_TOTAL := 7

# --- Roulette (European single-zero wheel) ----------------------------------
const ROULETTE_MAX_NUMBER := 36
const ROULETTE_RED_NUMBERS: Array[int] = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]

## Rejection-sampling cap when rolling dice to match an outcome.
const _MAX_ROLL_TRIES := 200


## Single-shot bet at `table` (SLOTS, BIG_WHEEL, DICE, ROULETTE). Updates the
## player's streak at the table. HIGH_LOW is played as one guess that cashes
## out on a win; BLACKJACK as a hand that stands on the deal.
static func resolve(table: TableState, pid: int, bet: int, choice: Dictionary, rng: RandomNumberGenerator, max_bet: int, payout_bonus: float = 1.0) -> BetResult:
	var thrown: bool = bool(choice.get("throw", false))
	if table.game_type == HR.GameType.HIGH_LOW:
		return _resolve_high_low(table, pid, bet, choice, rng, max_bet, payout_bonus, thrown)
	if table.game_type == HR.GameType.BLACKJACK:
		var hand := BlackjackRound.new(table, pid, bet, rng, max_bet, payout_bonus)
		return hand.forfeit() if thrown else hand.stand()

	var won: bool = not thrown and roll_win(table, pid, rng)
	var r := new_result(table, pid, bet)
	var profit: float = TableGames.profit_multiple(table.game_type)
	var number_bet := false
	match table.game_type:
		HR.GameType.SLOTS:
			r.jackpot = won and rng.randf() < Tuning.SLOT_JACKPOT_CHANCE
			if r.jackpot:
				profit = Tuning.SLOT_JACKPOT_PAYOUT
			r.detail = {"reels": slot_reels(won, r.jackpot, rng)}
		HR.GameType.BIG_WHEEL:
			var segment: int = wheel_segment(won, rng)
			r.detail = {"segment": segment, "label": WHEEL_LABELS[segment]}
		HR.GameType.DICE:
			var call: String = dice_call(choice)
			var dice: Array[int] = roll_dice(call, won, rng)
			r.detail = {"dice": dice, "total": dice[0] + dice[1], "call": call}
		HR.GameType.ROULETTE:
			number_bet = str(choice.get("kind", "color")) == "number"
			var number: int
			if number_bet:
				var pick: int = clampi(int(choice.get("number", 0)), 0, ROULETTE_MAX_NUMBER)
				profit = Tuning.ROULETTE_NUMBER_PAYOUT
				number = roulette_spin_number(pick, won, rng)
				r.detail = {"kind": "number", "pick": pick}
			else:
				var color: String = roulette_pick_color(choice)
				number = roulette_spin_color(color, won, rng)
				r.detail = {"kind": "color", "pick": color}
			r.detail["number"] = number
			r.detail["color"] = roulette_color(number)
	settle(r, table, won, thrown, win_payout(bet, profit, payout_bonus) if won else 0, max_bet, number_bet)
	r.loud = TableGames.is_loud(table.game_type) or r.jackpot
	return r


## Dice with the whole crew on one roll. `bets` items are {pid, bet, throw}
## (optional `call`; the first honest bettor's call is the crew's, default
## "high"). Returns pid -> BetResult. One result is rolled for everyone at the
## lowest win rate among the honest bettors (a swapped dealer rolls for the
## whole table). Throwers always lose: on a winning roll their bet is the
## opposite call. The winners' total win Heat is split evenly among them.
static func resolve_shared_roll(table: TableState, bets: Array, rng: RandomNumberGenerator, max_bet: int, payout_bonus: float = 1.0) -> Dictionary:
	var entries: Array[Dictionary] = []
	var seen: Dictionary = {}
	var crew_call := DICE_CALL_HIGH
	var call_set := false
	var rate: float = 1.0
	var honest := 0
	for item: Variant in bets:
		if not item is Dictionary:
			continue
		var b: Dictionary = item
		var pid: int = int(b.get("pid", 0))
		if seen.has(pid):
			continue
		seen[pid] = true
		var thrown: bool = bool(b.get("throw", false))
		entries.append({"pid": pid, "bet": int(b.get("bet", 0)), "throw": thrown})
		if not thrown:
			honest += 1
			rate = minf(rate, table.win_rate_for(pid))
			if not call_set and b.has("call"):
				crew_call = dice_call(b)
				call_set = true
	var out: Dictionary = {}
	if entries.is_empty():
		return out

	var won: bool = honest > 0 and rng.randf() < rate
	var dice: Array[int] = roll_dice(crew_call, won, rng)
	var profit: float = TableGames.profit_multiple(HR.GameType.DICE)
	var winners: Array[BetResult] = []
	var total_heat: float = 0.0
	for e: Dictionary in entries:
		var pid: int = e["pid"]
		var bet: int = e["bet"]
		var thrown: bool = e["throw"]
		var r := new_result(table, pid, bet)
		var w: bool = won and not thrown
		settle(r, table, w, thrown, win_payout(bet, profit, payout_bonus) if w else 0, max_bet)
		var call: String = opposite_dice_call(crew_call) if won and thrown else crew_call
		r.detail = {"dice": dice.duplicate(), "total": dice[0] + dice[1], "call": call, "shared": true, "crew": entries.size()}
		r.loud = TableGames.is_loud(HR.GameType.DICE)
		if w:
			winners.append(r)
			total_heat += r.heat
		out[pid] = r
	var share: float = HeatRules.shared_roll_heat(total_heat, winners.size())
	for r: BetResult in winners:
		r.heat = share
		r.detail["winners"] = winners.size()
	return out


# --- Shared helpers ---------------------------------------------------------

## True with the player's win rate at this table.
static func roll_win(table: TableState, pid: int, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < table.win_rate_for(pid)


## Chips back on a win: bet + bet × profit_mult × payout_bonus, rounded, and at
## least bet + 1. 0 for a non-positive bet.
static func win_payout(bet: int, profit_mult: float, payout_bonus: float) -> int:
	if bet <= 0:
		return 0
	return maxi(bet + 1, roundi(float(bet) * (1.0 + profit_mult * payout_bonus)))


static func new_result(table: TableState, pid: int, bet: int) -> BetResult:
	var r := BetResult.new()
	r.pid = pid
	r.table_id = table.id
	r.game_type = table.game_type
	r.bet = maxi(bet, 0)  # a negative bet must never pay out chips
	return r


## Fills won/payout/net/heat/streak/intentional_loss on `r` and updates the
## player's streak at the table.
static func settle(r: BetResult, table: TableState, won: bool, thrown: bool, payout: int, max_bet: int, number_bet: bool = false) -> void:
	r.won = won
	r.intentional_loss = thrown and not won
	if won:
		r.streak = table.record_win(r.pid)
		r.payout = payout
		r.heat = HeatRules.win_heat(r.game_type, r.bet, max_bet, r.streak, number_bet)
	else:
		table.record_loss(r.pid)
		r.streak = 0
		r.payout = 0
		r.heat = HeatRules.lose_on_purpose_heat(r.bet, max_bet) if thrown else 0.0
	r.net = r.payout - r.bet


# --- Slots ------------------------------------------------------------------

## Three of a kind on a win (jackpot symbol on a jackpot), never three alike on a loss.
static func slot_reels(won: bool, jackpot: bool, rng: RandomNumberGenerator) -> Array[String]:
	var reels: Array[String] = []
	if jackpot:
		reels.assign([SLOT_JACKPOT_SYMBOL, SLOT_JACKPOT_SYMBOL, SLOT_JACKPOT_SYMBOL])
		return reels
	if won:
		var plain: Array[String] = []
		for s: String in SLOT_SYMBOLS:
			if s != SLOT_JACKPOT_SYMBOL:
				plain.append(s)
		var sym: String = plain[rng.randi_range(0, plain.size() - 1)]
		reels.assign([sym, sym, sym])
		return reels
	for i in 3:
		reels.append(SLOT_SYMBOLS[rng.randi_range(0, SLOT_SYMBOLS.size() - 1)])
	if reels[0] == reels[1] and reels[1] == reels[2]:
		# Bump the last reel to a different symbol.
		var idx: int = SLOT_SYMBOLS.find(reels[2])
		var shift: int = rng.randi_range(1, SLOT_SYMBOLS.size() - 1)
		reels[2] = SLOT_SYMBOLS[(idx + shift) % SLOT_SYMBOLS.size()]
	return reels


static func slot_reels_win(reels: Array) -> bool:
	return reels.size() == 3 and reels[0] == reels[1] and reels[1] == reels[2]


# --- Big wheel --------------------------------------------------------------

static func wheel_segment(won: bool, rng: RandomNumberGenerator) -> int:
	var options: Array[int] = []
	for i in WHEEL_LABELS.size():
		if wheel_segment_wins(i) == won:
			options.append(i)
	return options[rng.randi_range(0, options.size() - 1)]


static func wheel_segment_wins(segment: int) -> bool:
	return segment >= 0 and segment < WHEEL_LABELS.size() and WHEEL_LABELS[segment] == WHEEL_WIN_LABEL


# --- Dice -------------------------------------------------------------------

## The call from a choice dictionary: "low" or (default) "high".
static func dice_call(choice: Dictionary) -> String:
	return DICE_CALL_LOW if str(choice.get("call", DICE_CALL_HIGH)) == DICE_CALL_LOW else DICE_CALL_HIGH


static func opposite_dice_call(call: String) -> String:
	return DICE_CALL_HIGH if call == DICE_CALL_LOW else DICE_CALL_LOW


static func dice_call_wins(call: String, total: int) -> bool:
	if call == DICE_CALL_LOW:
		return total < DICE_HOUSE_TOTAL
	return total > DICE_HOUSE_TOTAL


## Two dice whose total wins (or loses) for `call`.
static func roll_dice(call: String, won: bool, rng: RandomNumberGenerator) -> Array[int]:
	var dice: Array[int] = [1, 1]
	for i in _MAX_ROLL_TRIES:
		dice[0] = rng.randi_range(1, 6)
		dice[1] = rng.randi_range(1, 6)
		if dice_call_wins(call, dice[0] + dice[1]) == won:
			return dice
	# Practically unreachable; fall back to a fixed matching roll.
	if not won:
		dice.assign([3, 4])
	elif call == DICE_CALL_LOW:
		dice.assign([1, 2])
	else:
		dice.assign([5, 6])
	return dice


# --- Roulette ---------------------------------------------------------------

## "red", "black" or "green" (0) on the European wheel.
static func roulette_color(number: int) -> String:
	if number == 0:
		return "green"
	return "red" if ROULETTE_RED_NUMBERS.has(number) else "black"


static func roulette_pick_color(choice: Dictionary) -> String:
	return "black" if str(choice.get("color", "red")) == "black" else "red"


## A number of `color` on a win; any other pocket (the other color or 0) on a loss.
static func roulette_spin_color(color: String, won: bool, rng: RandomNumberGenerator) -> int:
	var options: Array[int] = []
	for n in ROULETTE_MAX_NUMBER + 1:
		if (roulette_color(n) == color) == won:
			options.append(n)
	return options[rng.randi_range(0, options.size() - 1)]


## `pick` on a win; any other pocket on a loss.
static func roulette_spin_number(pick: int, won: bool, rng: RandomNumberGenerator) -> int:
	if won:
		return pick
	var n: int = rng.randi_range(0, ROULETTE_MAX_NUMBER - 1)
	return n + 1 if n >= pick else n


# --- Fallbacks for the multi-step games -------------------------------------

static func _resolve_high_low(table: TableState, pid: int, bet: int, choice: Dictionary, rng: RandomNumberGenerator, max_bet: int, payout_bonus: float, thrown: bool) -> BetResult:
	var run := HighLowRun.new(table, pid, bet, rng, max_bet, payout_bonus)
	var g: BetResult = run.guess(bool(choice.get("higher", true)), thrown)
	if not g.won:
		return g
	var c: BetResult = run.cash_out()
	c.heat = g.heat
	var d: Dictionary = g.detail.duplicate(true)
	d.merge(c.detail, true)
	c.detail = d
	return c
