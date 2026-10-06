class_name HighLowRun
extends RefCounted
## High-low cards: guess whether the next card is higher or lower, then cash
## out or double. Each guess is rolled at the player's win rate for the table
## and the card revealed is chosen to match; cards never tie.
##
## The first winning guess pays the game's low payout (Tuning.GAMES × payout
## bonus); each winning guess after that doubles the pot. A wrong guess ends
## the run and the pot is lost. Chips only reach the pocket on cash_out(), so a
## winning guess's BetResult carries payout 0 and net 0 (the pot is in
## detail.pot) along with that guess's win Heat (high-low streak step).
##
## The card you guess against is always 3–13 so both answers stay possible: if
## a winning reveal is a 2 or an ace, the dealer deals a fresh card for the
## next guess (detail.redeal).

const CARD_MIN := 2
const CARD_MAX := 14
## Doubling stops here so the pot can never wrap past the int64 limit into a
## negative payout (2^53 also keeps it exact in float math). Not a game number.
const POT_LIMIT := 1 << 53

var pot: int = 0
## The card the next guess is against.
var current_card: int = 0
## Winning guesses in this run.
var streak: int = 0
var finished: bool = false
## The stake that started the run.
var bet: int = 0
## The last BetResult this run produced (null before the first guess).
var result: BetResult = null

var _table: TableState
var _pid: int
var _rng: RandomNumberGenerator
var _max_bet: int
var _payout_bonus: float


func _init(table: TableState, pid: int, p_bet: int, rng: RandomNumberGenerator, max_bet: int, payout_bonus: float = 1.0) -> void:
	_table = table
	_pid = pid
	_rng = rng
	_max_bet = max_bet
	_payout_bonus = payout_bonus
	bet = maxi(p_bet, 0)
	pot = bet
	current_card = deal_base_card(rng)


## Guess the next card. `throw` loses on purpose. Returns a no-op result
## (bet 0, heat 0) once the run is finished.
func guess(higher: bool, throw: bool = false) -> BetResult:
	if finished:
		return _noop()
	var base: int = current_card
	var won: bool = not throw and GameResolver.roll_win(_table, _pid, _rng)
	var shown: int = reveal_card(base, higher, won, _rng)
	var r := GameResolver.new_result(_table, _pid, bet)
	GameResolver.settle(r, _table, won, throw, 0, _max_bet)
	var redeal := false
	if won:
		streak += 1
		if streak == 1:
			pot = GameResolver.win_payout(bet, TableGames.profit_multiple(HR.GameType.HIGH_LOW), _payout_bonus)
		else:
			pot = POT_LIMIT if pot >= (POT_LIMIT >> 1) else pot * 2
		# Chips ride in the pot until cash_out().
		r.payout = 0
		r.net = 0
		if shown <= CARD_MIN or shown >= CARD_MAX:
			current_card = deal_base_card(_rng)
			redeal = true
		else:
			current_card = shown
	else:
		finished = true
		pot = 0
		current_card = shown
	r.detail = {
		"card": base,
		"next_card": shown,
		"higher": higher,
		"pot": pot,
		"guesses": streak,
		"current_card": current_card,
		"redeal": redeal,
	}
	result = r
	return r


## Takes the pot: payout = pot, net = pot - bet, no Heat (it came per guess).
## Returns a no-op result once the run is finished.
func cash_out() -> BetResult:
	if finished:
		return _noop()
	finished = true
	var r := GameResolver.new_result(_table, _pid, bet)
	r.won = streak > 0
	r.payout = pot
	r.net = pot - bet
	r.streak = _table.streak(_pid)
	r.detail = {"cash_out": true, "pot": pot, "guesses": streak, "current_card": current_card}
	result = r
	return r


## A card both answers can beat: 3–13.
static func deal_base_card(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(CARD_MIN + 1, CARD_MAX - 1)


## The revealed card: strictly on the guessed side of `base` when `win`,
## strictly on the other side when not. Never equal to `base`.
static func reveal_card(base: int, higher: bool, win: bool, rng: RandomNumberGenerator) -> int:
	var go_higher: bool = higher == win
	if go_higher:
		if base >= CARD_MAX:
			return CARD_MIN  # unreachable while the base stays 3–13
		return rng.randi_range(base + 1, CARD_MAX)
	if base <= CARD_MIN:
		return CARD_MAX  # unreachable while the base stays 3–13
	return rng.randi_range(CARD_MIN, base - 1)


func _noop() -> BetResult:
	var r := GameResolver.new_result(_table, _pid, 0)
	r.streak = _table.streak(_pid)
	r.detail = {"finished": true}
	return r
