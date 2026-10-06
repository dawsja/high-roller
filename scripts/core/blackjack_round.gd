class_name BlackjackRound
extends RefCounted
## Blackjack, hit or stand only. The outcome is rolled when the hand is dealt
## (at the player's win rate for the table) and every later card is chosen to
## match it.
##
## Cards are values 2–11: 10 covers tens and faces (4 in 13 draws), 11 is an
## ace, which counts 1 when 11 would bust. On a winning hand, hit() never busts
## the player while their total is 20 or less; hitting on 21 busts. On a losing
## hand the player can bust, but never lands on 21 (the dealer must be able to
## beat them). Only hitting past 21 counts as losing on purpose: that is the
## one bust that throws away a pre-rolled win. A losing hand that busts was
## lost anyway, so it is an honest loss (no cooling); otherwise always hitting
## on 17-20 would cool every losing hand for free. stand() plays the dealer out
## (hits below 17, stands on all 17s) to a hand that loses to or beats the player.

const ACE := 11
const TEN := 10
const BLACKJACK := 21
const DEALER_STANDS_ON := 17
## Marks a dealer target of "bust" in _dealer_hand.
const _BUST := 0
const _MAX_DRAWS := 30

var player_cards: Array[int] = []
## Only the up card until the round finishes; then the full dealer hand.
var dealer_cards: Array[int] = []
var finished: bool = false
## The pre-rolled outcome (host only; never shown to players).
var will_win: bool = false
var bet: int = 0
## The final BetResult once finished (null before).
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
	will_win = GameResolver.roll_win(table, pid, rng)
	player_cards.append(draw_card(rng))
	var second: Array[int] = []
	for c in range(2, ACE + 1):
		# A losing hand can't open on 21: the dealer couldn't beat it.
		if will_win or hand_total([player_cards[0], c]) != BLACKJACK:
			second.append(c)
	player_cards.append(_pick_weighted(second, rng))
	dealer_cards.append(draw_card(rng))


func player_total() -> int:
	return hand_total(player_cards)


func dealer_total() -> int:
	return hand_total(dealer_cards)


## Deals the player a card and returns it (0 once finished). Busting ends the
## round; `result` (also returned by stand()) then holds the loss.
func hit() -> int:
	if finished:
		return 0
	var before: int = player_total()
	var options: Array[int] = []
	for c in range(2, ACE + 1):
		var t: int = _total_with(player_cards, c)
		if will_win and before < BLACKJACK and t > BLACKJACK:
			continue
		if not will_win and t == BLACKJACK:
			continue
		options.append(c)
	var card: int = _pick_weighted(options, _rng)
	player_cards.append(card)
	if player_total() > BLACKJACK:
		_finish_bust(before >= BLACKJACK)
	return card


## Ends the player's turn and plays the dealer out. Returns the round's result
## (the same result again if the round already finished).
func stand() -> BetResult:
	if finished:
		return result
	finished = true
	var p: int = player_total()
	var target: int
	if will_win:
		if p > DEALER_STANDS_ON and _rng.randf() >= Tuning.BLACKJACK_DEALER_BUST_SHARE:
			target = _rng.randi_range(DEALER_STANDS_ON, p - 1)
		else:
			target = _BUST
	else:
		var lo: int = mini(maxi(p + 1, DEALER_STANDS_ON), BLACKJACK)
		target = _rng.randi_range(lo, BLACKJACK)
	dealer_cards = _dealer_hand(dealer_cards[0], target, _rng)
	var r := GameResolver.new_result(_table, _pid, bet)
	var payout: int = GameResolver.win_payout(bet, TableGames.profit_multiple(HR.GameType.BLACKJACK), _payout_bonus)
	GameResolver.settle(r, _table, will_win, false, payout if will_win else 0, _max_bet)
	r.detail = _detail()
	result = r
	return r


## Loses on purpose in one go: the player keeps hitting until they bust.
## Returns the same result again if the round already finished.
func forfeit() -> BetResult:
	if finished:
		return result
	for i in _MAX_DRAWS:
		if player_total() > BLACKJACK:
			break
		player_cards.append(draw_card(_rng))
	_finish_bust(true)
	return result


## Best total: aces count 11 unless that busts, then 1.
static func hand_total(cards: Array) -> int:
	var total := 0
	var aces := 0
	for c: int in cards:
		total += c
		if c == ACE:
			aces += 1
	while total > BLACKJACK and aces > 0:
		total -= ACE - 1
		aces -= 1
	return total


## True if an ace still counts 11 in the best total.
static func is_soft(cards: Array) -> bool:
	var hard := 0
	var has_ace := false
	for c: int in cards:
		hard += 1 if c == ACE else c
		has_ace = has_ace or c == ACE
	return has_ace and hard + ACE - 1 <= BLACKJACK


## One card from a fresh deck: 2–9 and ace 1 in 13 each, ten-value 4 in 13.
static func draw_card(rng: RandomNumberGenerator) -> int:
	var all: Array[int] = []
	for c in range(2, ACE + 1):
		all.append(c)
	return _pick_weighted(all, rng)


func _finish_bust(on_purpose: bool) -> void:
	finished = true
	if dealer_cards.size() < 2:
		dealer_cards.append(draw_card(_rng))  # reveal the hole card
	var r := GameResolver.new_result(_table, _pid, bet)
	GameResolver.settle(r, _table, false, on_purpose, 0, _max_bet)
	r.detail = _detail()
	result = r


func _detail() -> Dictionary:
	var p: int = player_total()
	var d: int = dealer_total()
	return {
		"player_cards": player_cards.duplicate(),
		"dealer_cards": dealer_cards.duplicate(),
		"player_total": p,
		"dealer_total": d,
		"player_bust": p > BLACKJACK,
		"dealer_bust": d > BLACKJACK,
	}


## A dealer hand starting with `up` that hits below 17 and ends on `target`
## (17–21), or busts when target is _BUST.
static func _dealer_hand(up: int, target: int, rng: RandomNumberGenerator) -> Array[int]:
	var cards: Array[int] = [up]
	for i in _MAX_DRAWS:
		if hand_total(cards) >= DEALER_STANDS_ON:
			break
		var options: Array[int] = []
		for c in range(2, ACE + 1):
			var t: int = _total_with(cards, c)
			var ok: bool
			if target == _BUST:
				ok = t < DEALER_STANDS_ON or t > BLACKJACK
			else:
				ok = t < DEALER_STANDS_ON or t == target
			if ok:
				options.append(c)
		cards.append(_pick_weighted(options, rng))
	return cards


static func _total_with(cards: Array[int], extra: int) -> int:
	var trial: Array = cards.duplicate()
	trial.append(extra)
	return hand_total(trial)


static func _weight(card: int) -> int:
	return 4 if card == TEN else 1


## Weighted pick from `options` by deck frequency; any card if `options` is empty.
static func _pick_weighted(options: Array[int], rng: RandomNumberGenerator) -> int:
	var pool: Array[int] = options
	if pool.is_empty():
		pool = []
		for c in range(2, ACE + 1):
			pool.append(c)
	var total := 0
	for c: int in pool:
		total += _weight(c)
	var roll: int = rng.randi_range(0, total - 1)
	for c: int in pool:
		roll -= _weight(c)
		if roll < 0:
			return c
	return pool[pool.size() - 1]
