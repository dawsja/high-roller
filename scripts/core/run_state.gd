class_name RunState
extends RefCounted
## The crew's whole run across casino visits (design doc "Casino ladder" and
## "Scoring and progression"). Persists while FloorSim is rebuilt per visit.
## Host-owned.
##
## Two chip pools: `bank` is spendable on buy-ins, can be taken back out at
## the cashier (withdraw) and carries between visits (banked chips are safe,
## even through a throw-out); `top_banked` is what was banked at The Apex and
## is the score, never spent. A new visit (climb,
## throw-out or curb timeout) clears strikes and per-visit state.

signal strike_added(strikes: int)
## At the bottom rung this is a curb timeout and from_rung == to_rung.
signal thrown_out(from_rung: int, to_rung: int)
signal climbed(from_rung: int, to_rung: int)
## `total` is the pool the chips went to: `top_banked` at the top, else `bank`.
signal banked(amount: int, total: int)

## Float-precision slack for score(): far below one frame, far above the drift
## from accumulating frame deltas over hours. Not a design number.
const _MINUTE_TOLERANCE_SECONDS := 0.001

var rung: int = Tuning.TOP_RUNG
var strikes: int = 0
var bank: int = 0
var top_banked: int = 0
var top_seconds: float = 0.0
var elapsed_seconds: float = 0.0
## Lives for the whole run, so posters stay up between visits.
var posters: PosterBoard = PosterBoard.new()
## Per visit: the fire alarm can be pulled once per casino visit.
var fire_alarm_used: bool = false
## Per visit: seconds since the crew arrived at the current casino.
var visit_seconds: float = 0.0
## Casino visits so far, counting the current one (1 at the start of a run).
var visits: int = 1
## Cosmetic unlocks from each player's own profile (set_unlocks): pid ->
## {pieces: Array[StringName], name_packs: Array[StringName]}. The gift shop
## (locked pieces) and ID printing (name packs) read them for that player.
## A player without an entry has nothing unlocked.
var unlocks: Dictionary = {}


## `start_rung` is for tests and debug starts; a real run starts at the top.
func _init(start_rung: int = Tuning.TOP_RUNG) -> void:
	rung = clampi(start_rung, Tuning.TOP_RUNG, Tuning.BOTTOM_RUNG)


## A copy of the current casino's Tuning.CASINOS row.
func casino() -> Dictionary:
	return CasinoLadder.casino(rung)


func casino_id() -> StringName:
	return CasinoLadder.casino_id(rung)


func is_top() -> bool:
	return CasinoLadder.is_top(rung)


func is_bottom() -> bool:
	return CasinoLadder.is_bottom(rung)


## Banks chips cashed out by a player. At the top rung they go to `top_banked`
## (score), otherwise to `bank`. Non-positive amounts are ignored.
func add_bank(amount: int) -> void:
	if amount <= 0:
		return
	if is_top():
		top_banked += amount
		banked.emit(amount, top_banked)
	else:
		bank += amount
		banked.emit(amount, bank)


## Adds a crew strike. True when strikes reach Tuning.STRIKES_TO_THROW_OUT;
## the caller then calls throw_out().
func add_strike() -> bool:
	strikes += 1
	strike_added.emit(strikes)
	return strikes >= Tuning.STRIKES_TO_THROW_OUT


## Drops the crew one rung (bank is kept) and starts a new visit. At the
## bottom it is a curb timeout: the rung stays, everything else is the same.
## `to_rung` (> rung) drops further, e.g. a broke crew straight to where the
## bank covers a bet. Returns the new rung.
func throw_out(to_rung: int = -1) -> int:
	var from := rung
	rung = CasinoLadder.drop_target(rung)
	if to_rung > rung and CasinoLadder.is_valid_rung(to_rung):
		rung = to_rung
	_start_visit()
	thrown_out.emit(from, rung)
	return rung


## Where the bank can take the crew right now (see CasinoLadder.climb_target).
func climb_target() -> int:
	return CasinoLadder.climb_target(rung, bank)


## Chips the next climb() would spend (0 if it can't climb).
func climb_cost() -> int:
	return CasinoLadder.climb_cost(rung, climb_target())


func can_climb() -> bool:
	return climb_target() < rung


## Climbs as far as the bank allows (one rung, or two by the stretch rule),
## spending the buy-in from `bank`, and starts a new visit. `to_rung` asks
## for a shorter climb (one rung when the stretch is affordable); it can't go
## further than climb_target(). Does nothing if it can't climb. Returns the
## (possibly unchanged) rung.
func climb(to_rung: int = -1) -> int:
	var target := climb_target()
	if to_rung > target and to_rung < rung:
		target = to_rung
	if target >= rung:
		return rung
	var from := rung
	bank -= CasinoLadder.climb_cost(from, target)
	rung = target
	_start_visit()
	climbed.emit(from, rung)
	return rung


## Takes chips back out of the crew bank (never `top_banked`, the score).
## False (nothing taken) for a non-positive amount or more than the bank holds.
func withdraw(amount: int) -> bool:
	if amount <= 0 or amount > bank:
		return false
	bank -= amount
	return true


## Records a player's unlocked outfit pieces and ID name packs (ids from
## their profile). Unknown ids and pieces that aren't locked are dropped.
func set_unlocks(pid: int, piece_ids: Array, pack_ids: Array) -> void:
	var pieces: Array[StringName] = []
	for id: Variant in piece_ids:
		var piece := StringName(str(id))
		if OutfitCatalog.is_unlockable(piece) and not pieces.has(piece):
			pieces.append(piece)
	var packs: Array[StringName] = []
	for id: Variant in pack_ids:
		if IdGenerator.has_name_pack(id) and not packs.has(StringName(str(id))):
			packs.append(StringName(str(id)))
	unlocks[pid] = {"pieces": pieces, "name_packs": packs}


## Locked outfit pieces `pid` has unlocked (empty if none were set).
func unlocked_pieces(pid: int) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign((unlocks.get(pid, {}) as Dictionary).get("pieces", []))
	return out


## ID name packs `pid` has unlocked (empty if none were set).
func name_packs(pid: int) -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign((unlocks.get(pid, {}) as Dictionary).get("name_packs", []))
	return out


## Marks the once-per-visit fire alarm as pulled. False if already used.
func use_fire_alarm() -> bool:
	if fire_alarm_used:
		return false
	fire_alarm_used = true
	return true


## `scoring`: whether time at the top counts towards the score right now
## (FloorSim passes false while the whole crew is held or broke).
func tick(delta: float, scoring: bool = true) -> void:
	if delta <= 0.0:
		return
	elapsed_seconds += delta
	visit_seconds += delta
	if is_top() and scoring:
		top_seconds += delta


## Chips banked at the top plus SCORE_PER_MINUTE_AT_TOP per whole minute there.
## A minute counts on the frame that completes it, despite float drift from
## summing frame deltas (60 x 60 ticks of 1/60 s add up to 59.99999999999...).
func score() -> int:
	var minutes := int(floorf((top_seconds + _MINUTE_TOLERANCE_SECONDS) / 60.0))
	return top_banked + minutes * Tuning.SCORE_PER_MINUTE_AT_TOP


## Plain data for snapshots and late joiners (posters not included).
func to_dict() -> Dictionary:
	return {
		"rung": rung,
		"casino_id": casino_id(),
		"strikes": strikes,
		"bank": bank,
		"top_banked": top_banked,
		"top_seconds": top_seconds,
		"elapsed_seconds": elapsed_seconds,
		"visit_seconds": visit_seconds,
		"fire_alarm_used": fire_alarm_used,
		"visits": visits,
		"score": score(),
	}


func _start_visit() -> void:
	strikes = 0
	fire_alarm_used = false
	visit_seconds = 0.0
	visits += 1
