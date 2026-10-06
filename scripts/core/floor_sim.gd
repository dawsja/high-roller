class_name FloorSim
extends RefCounted
## The host-authoritative game for one casino visit (docs/ARCHITECTURE.md,
## "Simulation facade"). RunState persists across visits; each visit is a new
## FloorSim that carries the crew's PlayerStates over.
##
## World and UI code never change chips, Heat, IDs or outfits: they call the
## requests below and react to `event`. Every request returns a Dictionary with
## at least {ok: bool, reason: StringName} (reason &"" on success) and never
## throws on bad input. start_high_low / start_blackjack return the round
## object (read it, never call its methods) or null with the reason in
## `last_reason`. All event data is plain (ints, floats, strings, StringNames,
## Vector3, dictionaries, arrays) so it can go over RPC.

signal event(kind: StringName, data: Dictionary)

# --- Request failure reasons --------------------------------------------------
const NO_REASON := &""
const FINISHED := &"finished"
const UNKNOWN_PLAYER := &"unknown_player"
const UNKNOWN_TABLE := &"unknown_table"
## The player's status doesn't allow it (carried, detained, in an ID check, seated, ...).
const BUSY := &"busy"
const WRONG_ZONE := &"wrong_zone"
const BAD_AMOUNT := &"bad_amount"
const NOT_ENOUGH := &"not_enough"
const BELOW_MIN := &"below_min"
const ABOVE_MAX := &"above_max"
const TABLE_CLOSED := &"table_closed"
const NOT_SEATED := &"not_seated"
const WRONG_GAME := &"wrong_game"
const IN_ROUND := &"in_round"
const NO_ROUND := &"no_round"
const STAFF_UNIFORM := &"staff_uniform"
const NO_BETS := &"no_bets"
const BAD_INDEX := &"bad_index"
const BAD_OUTFIT := &"bad_outfit"
const NOT_OWNED := &"not_owned"
const SAME_OUTFIT := &"same_outfit"
const BAD_PIECE := &"bad_piece"
const ALREADY_WEARING := &"already_wearing"
const COOLDOWN := &"cooldown"
const FORGER_NOT_HERE := &"forger_not_here"
const BAD_GRADE := &"bad_grade"
const NO_QUESTION := &"no_question"
const NOT_AVAILABLE := &"not_available"
const NOT_CARRIED := &"not_carried"
const SAME_PLAYER := &"same_player"
const BAD_KIND := &"bad_kind"
const USED := &"used"
const CANT_CLIMB := &"cant_climb"
const NOT_AT_EXIT := &"not_at_exit"
const UNKNOWN_POSTER := &"unknown_poster"
const NO_SLOT := &"no_slot"
## start_id_check on a player who already passed a check (PlayerState.id_cleared()).
const CLEARED := &"cleared"
## try_climb that would land the crew upstairs unable to cover a bet there.
const NO_STAKE := &"no_stake"

# --- ID check result reasons (id_result.reason) -------------------------------
const ID_CORRECT := &"correct"
const ID_WRONG := &"wrong"
const ID_TIMEOUT := &"timeout"
const ID_NONE := &"no_id"
const ID_BURNED := &"burned"
const ID_FLAGGED := &"flagged"
const ID_SPOTTED := &"spotted"

const PLAYER_FLAGS: Array[String] = ["running_in_view", "in_camera_view", "pit_boss_view"]

var run: RunState
var rng: RandomNumberGenerator
## pid (int) -> PlayerState, in join order.
var players: Dictionary = {}
## table id (StringName) -> TableState.
var tables: Dictionary = {}
var forger: Forger
## True once the visit is over (thrown out or climbed); requests then fail with &"finished".
var finished: bool = false
## &"thrown_out" or &"climbed" once finished.
var outcome: StringName = &""
## Why the last start_high_low / start_blackjack returned null (&"" on success).
var last_reason: StringName = &""
## Seconds left of the fire alarm (> 0 while tables are closed).
var fire_alarm_seconds: float = 0.0
## Seconds until the slot jackpot alarm can be tripped again (crew-wide).
var slot_alarm_cooldown: float = 0.0
## Seconds the crew has been broke on the floor with nothing to withdraw
## (above Sal's, below the top); at Tuning.BROKE_GRACE_SECONDS it is thrown out.
var broke_seconds: float = 0.0

var _casino: Dictionary = {}
var _table_positions: Dictionary = {}
var _broke_warned: bool = false
## pid -> reason of the player's last Heat change (decides dealer swaps).
var _heat_reason: Dictionary = {}


## `carried_players` are PlayerStates from the previous visit (the crew).
## They keep pocket, outfit, stash and IDs; per-visit state resets.
func _init(p_run: RunState, p_seed: int, carried_players: Array = []) -> void:
	run = p_run if p_run != null else RunState.new()
	rng = RandomNumberGenerator.new()
	rng.seed = p_seed
	_casino = run.casino()
	forger = Forger.new(Forger.LOCATIONS[rng.randi_range(0, Forger.LOCATIONS.size() - 1)])
	forger.moved.connect(_on_forger_moved)
	for item: Variant in carried_players:
		if not item is PlayerState:
			continue
		var ps: PlayerState = item
		if players.has(ps.pid):
			continue
		ps.release_listeners()
		ps.begin_visit()
		_adopt(ps)
		_ensure_usable_id(ps)


# --- Setup ------------------------------------------------------------------

## Adds a new player: this casino's start_chips (a fresh run at this rung;
## CasinoLadder.start_chips), a random outfit, a START_ID_GRADE ID and
## START_STASH_OUTFITS random outfits in the stash. Returns the existing
## player for a pid already in the crew. Emits &"player_joined".
func add_player(pid: int, display_name: String) -> PlayerState:
	if players.has(pid):
		return players[pid]
	var ps := PlayerState.new(pid, display_name)
	ps.wallet = Wallet.new(CasinoLadder.start_chips(run.rung))
	ps.outfit = OutfitCatalog.random_outfit(rng)
	for i in Tuning.START_STASH_OUTFITS:
		ps.stash.append(OutfitCatalog.random_outfit(rng))
	ps.ids.append(IdGenerator.generate(Tuning.START_ID_GRADE, rng, _id_names(), run.name_packs(pid)))
	ps.id_index = 0
	_adopt(ps)
	_emit(&"player_joined", {"pid": pid, "name": display_name})
	return ps


## Registers a table (the director does this after building the map).
## `position` is where its noises come from. Returns the existing table for a
## known id. Tables registered during a fire alarm start closed.
func register_table(id: StringName, game_type: int, area_id: StringName, position: Vector3 = Vector3.ZERO) -> TableState:
	if tables.has(id):
		return tables[id]
	var t := TableState.new(id, game_type, area_id)
	t.closed = fire_alarm_active()
	tables[id] = t
	_table_positions[id] = position
	return t


# --- Seats and bets -----------------------------------------------------------

## Sits at a table (standing up from another one first). `in_view`: a guard
## sees it, so leaving another table under TABLE_JUMP_WINDOW ago adds
## table-jump Heat (never a dealer swap). Staff uniforms can't sit; closed
## tables refuse. Ends the after-rejoin grace; resets the loiter timer once
## per play.
## -> {ok, reason, table_id, game_type, heat}
func sit(pid: int, table_id: StringName, in_view: bool = false) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	var t := table(table_id)
	if t == null:
		return _fail(UNKNOWN_TABLE)
	if not ps.can_act():
		return _fail(BUSY)
	if t.closed:
		return _fail(TABLE_CLOSED)
	if ps.outfit.is_staff_uniform():
		return _fail(STAFF_UNIFORM)
	var extra := {"table_id": table_id, "game_type": t.game_type, "heat": 0.0}
	if ps.table_id == table_id and t.is_seated(pid):
		return _ok(extra)
	if ps.table_id != &"":
		_stand_up(ps)
	t.seat(pid)
	ps.table_id = table_id
	ps.rejoin_grace = 0.0
	if ps.loiter_sit_reset:
		ps.loiter_sit_reset = false
		ps.loiter_seconds = 0.0
	_set_status(ps, HR.PlayerStatus.SEATED)
	_emit(&"seated", {"pid": pid, "table_id": table_id, "game_type": t.game_type})
	var jump: float = HeatRules.table_jump_heat(ps.last_table_id, table_id, ps.seconds_since_left_table, in_view)
	if jump != 0.0:
		extra["heat"] = _add_heat(ps, jump, HeatRules.TABLE_JUMP)
	return _ok(extra)


## Stands up, finishing any high-low run (cash out) or blackjack hand (stand).
## -> {ok, reason, table_id}
func stand(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	if ps.table_id == &"":
		return _fail(NOT_SEATED)
	var left: StringName = ps.table_id
	_stand_up(ps)
	return _ok({"table_id": left})


## Single-shot bet at slots, big wheel, dice (a solo shared roll) or roulette.
## `choice` as GameResolver.resolve (throw, kind/color/number, call).
## -> {ok, reason, result: BetResult.to_dict(), pocket}
func place_bet(pid: int, table_id: StringName, amount: int, choice: Dictionary = {}) -> Dictionary:
	var ps := _ps(pid)
	var t := table(table_id)
	var why := _bet_check(ps, t, amount)
	if why == NO_REASON and (t.game_type == HR.GameType.HIGH_LOW or t.game_type == HR.GameType.BLACKJACK):
		why = WRONG_GAME
	if why != NO_REASON:
		return _fail(why)
	ps.wallet.spend(amount)
	_mark_played(ps)
	var r: BetResult
	if t.game_type == HR.GameType.DICE:
		var bet := {"pid": pid, "bet": amount, "throw": bool(choice.get("throw", false))}
		if choice.has("call"):
			bet["call"] = choice["call"]
		var rolled: Dictionary = GameResolver.resolve_shared_roll(t, [bet], rng, _max_bet(), _payout_bonus())
		r = rolled[pid]
	else:
		r = GameResolver.resolve(t, pid, amount, choice, rng, _max_bet(), _payout_bonus())
	_apply_result(ps, r, HeatRules.WIN, true)
	return _ok({"result": r.to_dict(), "pocket": ps.wallet.pocket})


## The crew bets on one dice roll. `bets` items are {pid, bet, throw?, call?}.
## Invalid bets are left out (reason per pid in `rejected`); fails only if no
## bet is valid. Winners split the win Heat (reason SHARED_ROLL with 2+ bettors).
## -> {ok, reason, results: {pid: BetResult dict}, rejected: {pid: reason}}
func place_shared_roll(table_id: StringName, bets: Array) -> Dictionary:
	if finished:
		return _fail(FINISHED, {"results": {}, "rejected": {}})
	var t := table(table_id)
	if t == null:
		return _fail(UNKNOWN_TABLE, {"results": {}, "rejected": {}})
	if t.game_type != HR.GameType.DICE:
		return _fail(WRONG_GAME, {"results": {}, "rejected": {}})
	var valid: Array = []
	var rejected: Dictionary = {}
	var seen: Dictionary = {}
	var first_reject: StringName = NO_BETS
	for item: Variant in bets:
		if not item is Dictionary:
			continue
		var b: Dictionary = item
		var pid: int = int(b.get("pid", 0))
		if seen.has(pid):
			continue
		seen[pid] = true
		var amount: int = int(b.get("bet", 0))
		var why := _bet_check(_ps(pid), t, amount)
		if why != NO_REASON:
			if rejected.is_empty():
				first_reject = why
			rejected[pid] = why
			continue
		var entry := {"pid": pid, "bet": amount, "throw": bool(b.get("throw", false))}
		if b.has("call"):
			entry["call"] = b["call"]
		valid.append(entry)
	if valid.is_empty():
		return _fail(first_reject, {"results": {}, "rejected": rejected})
	for entry: Dictionary in valid:
		_ps(entry["pid"]).wallet.spend(entry["bet"])
		_mark_played(_ps(entry["pid"]))
	var rolled: Dictionary = GameResolver.resolve_shared_roll(t, valid, rng, _max_bet(), _payout_bonus())
	var reason: StringName = HeatRules.SHARED_ROLL if valid.size() > 1 else HeatRules.WIN
	var results: Dictionary = {}
	for entry: Dictionary in valid:
		var pid: int = entry["pid"]
		var r: BetResult = rolled[pid]
		_apply_result(_ps(pid), r, reason, true)
		results[pid] = r.to_dict()
	return _ok({"results": results, "rejected": rejected})


## Starts a high-low run (the bet leaves the pocket now). Returns the run (read
## only) or null with `last_reason`. Play it with high_low_guess / high_low_cash_out.
func start_high_low(pid: int, table_id: StringName, bet: int) -> HighLowRun:
	var ps := _ps(pid)
	var t := table(table_id)
	last_reason = _bet_check(ps, t, bet)
	if last_reason == NO_REASON and t.game_type != HR.GameType.HIGH_LOW:
		last_reason = WRONG_GAME
	if last_reason != NO_REASON:
		return null
	ps.wallet.spend(bet)
	_mark_played(ps)
	var hl := HighLowRun.new(t, pid, bet, rng, _max_bet(), _payout_bonus())
	ps.high_low = hl
	ps.round_table_id = table_id
	_emit_hand(ps)
	return hl


## One guess. Win Heat is applied per winning guess; a wrong guess ends the
## run (pot lost). -> {ok, reason, result, won, pot, card, finished, pocket}
func high_low_guess(pid: int, higher: bool, throw: bool = false) -> Dictionary:
	var ps := _ps(pid)
	var why := _round_check(ps, &"high_low")
	if why != NO_REASON:
		return _fail(why)
	var hl: HighLowRun = ps.high_low
	_mark_played(ps)
	var r: BetResult = hl.guess(higher, throw)
	var over: bool = hl.finished
	if over:
		_clear_round(ps)
	_apply_result(ps, r, HeatRules.WIN, over)
	if not over:
		_emit_hand(ps)
	return _ok({"result": r.to_dict(), "won": r.won, "pot": hl.pot, "card": hl.current_card, "finished": over, "pocket": ps.wallet.pocket})


## Takes the pot into the pocket and ends the run. -> {ok, reason, result, payout, pocket}
func high_low_cash_out(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _round_check(ps, &"high_low")
	if why != NO_REASON:
		return _fail(why)
	_mark_played(ps)
	var r: BetResult = _cash_out_high_low(ps)
	return _ok({"result": r.to_dict(), "payout": r.payout, "pocket": ps.wallet.pocket})


## Deals a blackjack hand (the bet leaves the pocket now). Returns the round
## (read only) or null with `last_reason`. Play it with blackjack_hit / blackjack_stand.
func start_blackjack(pid: int, table_id: StringName, bet: int) -> BlackjackRound:
	var ps := _ps(pid)
	var t := table(table_id)
	last_reason = _bet_check(ps, t, bet)
	if last_reason == NO_REASON and t.game_type != HR.GameType.BLACKJACK:
		last_reason = WRONG_GAME
	if last_reason != NO_REASON:
		return null
	ps.wallet.spend(bet)
	_mark_played(ps)
	var bj := BlackjackRound.new(t, pid, bet, rng, _max_bet(), _payout_bonus())
	ps.blackjack = bj
	ps.round_table_id = table_id
	_emit_hand(ps)
	return bj


## Deals the player a card. Busting ends the hand (hitting past 21 is a thrown
## hand). -> {ok, reason, card, total, finished, result ({} until finished), pocket}
func blackjack_hit(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _round_check(ps, &"blackjack")
	if why != NO_REASON:
		return _fail(why)
	var bj: BlackjackRound = ps.blackjack
	_mark_played(ps)
	var card: int = bj.hit()
	var extra := {"card": card, "total": bj.player_total(), "finished": bj.finished, "result": {}}
	if bj.finished:
		_clear_round(ps)
		_apply_result(ps, bj.result, HeatRules.WIN, true)
		extra["result"] = bj.result.to_dict()
	else:
		_emit_hand(ps)
	extra["pocket"] = ps.wallet.pocket
	return _ok(extra)


## Stands; the dealer plays out and the hand settles. -> {ok, reason, result, pocket}
func blackjack_stand(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _round_check(ps, &"blackjack")
	if why != NO_REASON:
		return _fail(why)
	_mark_played(ps)
	var r: BetResult = _stand_blackjack(ps)
	return _ok({"result": r.to_dict(), "pocket": ps.wallet.pocket})


# --- Movement and perception ------------------------------------------------

## The player walked into a zone. Entering a TABLES/SLOTS area other than the
## last one gives the area-change cool-off (at most every AREA_CHANGE_COOLDOWN).
## -> {ok, reason, heat}
func enter_zone(pid: int, zone: int, area_id: StringName) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	var changed: bool = ps.zone != zone or ps.area_id != area_id
	ps.zone = zone
	ps.area_id = area_id
	if changed:
		_emit(&"zone", {"pid": pid, "zone": zone, "area_id": area_id})
	var applied := 0.0
	if (zone == HR.ZoneType.TABLES or zone == HR.ZoneType.SLOTS) and area_id != &"":
		if ps.is_available():
			var h: float = HeatRules.area_change_heat(ps.last_game_area, area_id, ps.seconds_since_area_change)
			if h != 0.0:
				applied = _add_heat(ps, h, HeatRules.AREA_CHANGE)
				ps.seconds_since_area_change = 0.0
		ps.last_game_area = area_id
	return _ok({"heat": applied})


## What the world sees about a player this frame, for passive Heat and gain
## multipliers: any of running_in_view, in_camera_view, pit_boss_view (bools).
## Missing keys keep their last value. -> {ok, reason, flags}
func set_player_flags(pid: int, new_flags: Dictionary) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	for key: String in PLAYER_FLAGS:
		if new_flags.has(key):
			ps.flags[key] = bool(new_flags[key])
	return _ok({"flags": ps.flags.duplicate()})


## A guard (or pit boss) sees the player this frame. ctx: {guard_id: int,
## pit_boss: bool}. A poster match in this casino adds POSTER_MATCH_HEAT once
## per sighting (re-arms after POSTER_MATCH_REARM_SECONDS unseen or an outfit
## change; not during the after-rejoin grace) and ends a passed check's
## clearance if they didn't match a poster when they passed.
## -> {ok, reason, matches_poster, recognized, poster_id (-1), heat}
func report_seen(pid: int, ctx: Dictionary = {}) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why, {"matches_poster": false, "recognized": false, "poster_id": -1, "heat": 0.0})
	ps.seconds_unseen = 0.0
	var poster: WantedPoster = run.posters.matching_poster(run.casino_id(), ps.outfit)
	_refresh_clearance(ps, poster != null)
	var applied := 0.0
	if poster != null and ps.poster_match_armed and ps.is_targetable():
		ps.poster_match_armed = false
		var pit_boss: bool = bool(ctx.get("pit_boss", false))
		_emit(&"poster_match", {"pid": pid, "poster_id": poster.id, "guard_id": int(ctx.get("guard_id", -1)), "pit_boss": pit_boss})
		applied = _add_heat(ps, HeatRules.event_heat(HeatRules.POSTER_MATCH), HeatRules.POSTER_MATCH, {"pit_boss_view": true} if pit_boss else {})
	return _ok({
		"matches_poster": poster != null,
		"recognized": _recognized(ps),
		"poster_id": poster.id if poster != null else -1,
		"heat": applied,
	})


# --- Identity ---------------------------------------------------------------

## Restroom: swaps the worn outfit with stash[index]. CHANGE_OUTFIT_HEAT (none within
## CHANGE_OUTFIT_COOLDOWN of the last change).
## -> {ok, reason, outfit, heat}
func change_to_stash(pid: int, index: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _free_in_zone(ps, HR.ZoneType.RESTROOM)
	if why != NO_REASON:
		return _fail(why)
	if index < 0 or index >= ps.stash.size():
		return _fail(BAD_INDEX)
	if ps.stash[index].equals(ps.outfit):
		return _fail(SAME_OUTFIT)
	var old: Outfit = ps.outfit
	ps.outfit = ps.stash[index]
	ps.stash[index] = old
	var applied := _after_outfit_change(ps, &"restroom")
	return _ok({"outfit": ps.outfit.to_dict(), "heat": applied})


## Restroom: wears a mix of pieces the player owns (any piece of the worn
## outfit or a stash outfit; NONE in optional slots). `outfit` is an Outfit or
## its to_dict(). The old look goes into the stash (unless an equal one is
## there) and an equal stash outfit is taken out. CHANGE_OUTFIT_HEAT.
## -> {ok, reason, outfit, heat}
func change_outfit(pid: int, outfit: Variant) -> Dictionary:
	var ps := _ps(pid)
	var why := _free_in_zone(ps, HR.ZoneType.RESTROOM)
	if why != NO_REASON:
		return _fail(why)
	var wanted: Outfit = null
	if outfit is Outfit:
		wanted = (outfit as Outfit).copy()
	elif outfit is Dictionary:
		wanted = Outfit.from_dict(outfit)
	if wanted == null:
		return _fail(BAD_OUTFIT)
	for slot: int in OutfitCatalog.all_slots():
		var piece: StringName = wanted.get_piece(slot)
		if not OutfitCatalog.fits(piece, slot):
			return _fail(BAD_OUTFIT)
		if not OutfitCatalog.is_none(piece) and not _owns_piece(ps, slot, piece):
			return _fail(NOT_OWNED)
	if wanted.equals(ps.outfit):
		return _fail(SAME_OUTFIT)
	var old: Outfit = ps.outfit
	ps.outfit = wanted
	for i in ps.stash.size():
		if ps.stash[i].equals(wanted):
			ps.stash.remove_at(i)
			break
	if not ps.stash.any(func(o: Outfit) -> bool: return o.equals(old)):
		ps.stash.append(old)
	var applied := _after_outfit_change(ps, &"restroom")
	return _ok({"outfit": ps.outfit.to_dict(), "heat": applied})


## Gift shop: buys one piece. It is NOT worn right away: the stash gains a copy
## of the worn outfit with that piece (change into it at a restroom).
## -> {ok, reason, price, stash_index, outfit (the new stash outfit)}
func buy_outfit_piece(pid: int, slot: int, piece_id: StringName) -> Dictionary:
	var ps := _ps(pid)
	var why := _free_in_zone(ps, HR.ZoneType.GIFT_SHOP)
	if why != NO_REASON:
		return _fail(why)
	if not OutfitCatalog.fits(piece_id, slot) or not OutfitCatalog.is_for_sale(piece_id, run.unlocked_pieces(pid)):
		return _fail(BAD_PIECE)
	if ps.outfit.get_piece(slot) == piece_id:
		return _fail(ALREADY_WEARING)
	var price: int = OutfitCatalog.piece_price(piece_id)
	if not ps.wallet.spend(price):
		return _fail(NOT_ENOUGH)
	var variant: Outfit = ps.outfit.copy()
	variant.set_piece(slot, piece_id)
	ps.stash.append(variant)
	_emit_outfit(ps, false, &"bought")
	return _ok({"price": price, "stash_index": ps.stash.size() - 1, "outfit": variant.to_dict()})


## Laundry cart / staff locker (zone STAFF_ONLY): STEAL_UNIFORM_CHANCE of the
## full staff uniform, else one random civilian piece on a copy of the worn
## outfit. Either lands in the stash. Per-player STEAL_COOLDOWN.
## -> {ok, reason, uniform, slot (-1 for the uniform), piece, stash_index, outfit}
func steal_outfit_piece(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _free_in_zone(ps, HR.ZoneType.STAFF_ONLY)
	if why != NO_REASON:
		return _fail(why)
	if ps.steal_cooldown > 0.0:
		return _fail(COOLDOWN, {"seconds": ps.steal_cooldown})
	ps.steal_cooldown = Tuning.STEAL_COOLDOWN
	var uniform: bool = rng.randf() < Tuning.STEAL_UNIFORM_CHANCE
	var slot := -1
	var piece: StringName = &""
	var variant: Outfit
	if uniform:
		variant = OutfitCatalog.staff_uniform()
	else:
		slot = rng.randi_range(0, HR.OUTFIT_SLOT_COUNT - 1)
		var options: Array[StringName] = []
		for id: StringName in OutfitCatalog.pieces_for(slot):
			if not OutfitCatalog.is_none(id) and id != ps.outfit.get_piece(slot):
				options.append(id)
		piece = options[rng.randi_range(0, options.size() - 1)]
		variant = ps.outfit.copy()
		variant.set_piece(slot, piece)
	ps.stash.append(variant)
	_emit_outfit(ps, false, &"stolen")
	return _ok({"uniform": uniform, "slot": slot, "piece": piece, "stash_index": ps.stash.size() - 1, "outfit": variant.to_dict()})


## Buys an ID from the forger; only in a FORGER zone whose area_id is
## forger.location(). The new card becomes the one in use.
## -> {ok, reason, price, id, index}
func buy_id(pid: int, grade: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _free_in_zone(ps, HR.ZoneType.FORGER)
	if why == WRONG_ZONE or (why == NO_REASON and ps.area_id != forger.location()):
		why = FORGER_NOT_HERE
	if why != NO_REASON:
		return _fail(why)
	if not IdGenerator.is_valid_grade(grade):
		return _fail(BAD_GRADE)
	var price: int = forger.price(grade)
	if not ps.wallet.spend(price):
		return _fail(NOT_ENOUGH)
	var id: FakeId = IdGenerator.generate(grade, rng, _id_names(), run.name_packs(pid))
	ps.ids.append(id)
	ps.id_index = ps.ids.size() - 1
	_emit_id(ps, &"bought")
	return _ok({"price": price, "id": id.to_dict(), "index": ps.id_index})


## Plays under another held card (FREE or SEATED, not mid-check). -> {ok, reason, id, index}
func swap_id(pid: int, index: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	if not ps.can_act():
		return _fail(BUSY)
	if index < 0 or index >= ps.ids.size():
		return _fail(BAD_INDEX)
	ps.id_index = index
	_emit_id(ps, &"swapped")
	return _ok({"id": ps.ids[index].to_dict(), "index": index})


## A guard asks for ID. Fails on the spot (auto_fail) with no card, a burned or
## flagged card, or a cheap card spotted on sight; otherwise the player gets a
## quiz (status ID_CHECK) to answer with answer_id_check. Refused (ok false)
## during the after-rejoin grace (NOT_AVAILABLE) and for a player who already
## passed a check (CLEARED, crew-wide: PlayerState.id_cleared()).
## -> {ok, reason, auto_fail, fail_reason, question {field, prompt, options}, seconds}
func start_id_check(pid: int, guard_id: int = -1) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	if not ps.can_act():
		return _fail(BUSY)
	if not ps.is_targetable():
		return _fail(NOT_AVAILABLE)
	var id: FakeId = ps.current_id()
	var fail_reason: StringName = &""
	if id == null:
		fail_reason = ID_NONE
	elif id.burned:
		fail_reason = ID_BURNED
	elif id.flagged:
		fail_reason = ID_FLAGGED
	elif ps.id_cleared():
		return _fail(CLEARED)
	elif IdQuiz.spotted_on_sight(id, rng):
		fail_reason = ID_SPOTTED
	if fail_reason != &"":
		_emit(&"id_check", {"pid": pid, "guard_id": guard_id, "auto_fail": true, "fail_reason": fail_reason, "question": {}, "seconds": 0.0})
		_emit(&"id_result", {"pid": pid, "guard_id": guard_id, "passed": false, "reason": fail_reason})
		return _ok({"auto_fail": true, "fail_reason": fail_reason, "question": {}, "seconds": 0.0})
	ps.id_question = IdQuiz.make_question(id, rng)
	ps.id_check_guard = guard_id
	ps.id_check_seconds = Tuning.ID_QUIZ_SECONDS + Tuning.ID_QUIZ_GRACE_SECONDS
	_set_status(ps, HR.PlayerStatus.ID_CHECK)
	var question := _public_question(ps.id_question)
	_emit(&"id_check", {"pid": pid, "guard_id": guard_id, "auto_fail": false, "fail_reason": &"", "question": question, "seconds": Tuning.ID_QUIZ_SECONDS})
	return _ok({"auto_fail": false, "fail_reason": &"", "question": question, "seconds": Tuning.ID_QUIZ_SECONDS})


## Answers the pending quiz. -> {ok, reason, passed}
func answer_id_check(pid: int, option_index: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why, {"passed": false})
	if ps.id_question.is_empty():
		return _fail(NO_QUESTION, {"passed": false})
	var passed: bool = IdQuiz.is_correct(ps.id_question, option_index)
	_end_id_check(ps, passed, ID_CORRECT if passed else ID_WRONG)
	return _ok({"passed": passed})


## The quiz timer ran out: a fail. -> {ok, reason, passed (false)}
func expire_id_check(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why, {"passed": false})
	if ps.id_question.is_empty():
		return _fail(NO_QUESTION, {"passed": false})
	_end_id_check(ps, false, ID_TIMEOUT)
	return _ok({"passed": false})


## Tears a poster in this casino down (noisy). -> {ok, reason, poster_id}
func tear_poster(pid: int, poster_id: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why == NO_REASON and ps.status != HR.PlayerStatus.FREE:
		why = BUSY
	if why == NO_REASON and _poster_here(poster_id) == null:
		why = UNKNOWN_POSTER
	if why != NO_REASON:
		return _fail(why)
	run.posters.tear_down(poster_id)
	_emit(&"poster_removed", {"poster_id": poster_id, "casino_id": run.casino_id()})
	_noise(&"tear_poster", position, pid)
	return _ok({"poster_id": poster_id})


## Draws over one slot of a poster in this casino. slot -1 picks the first
## readable slot that matches the player's worn outfit (else the first readable
## slot). -> {ok, reason, slot, poster}
func deface_poster(pid: int, poster_id: int, slot: int = -1) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why == NO_REASON and ps.status != HR.PlayerStatus.FREE:
		why = BUSY
	var poster: WantedPoster = _poster_here(poster_id) if why == NO_REASON else null
	if why == NO_REASON and poster == null:
		why = UNKNOWN_POSTER
	if why != NO_REASON:
		return _fail(why)
	var s: int = slot if slot >= 0 else _deface_slot(poster, ps.outfit)
	if s < 0 or not run.posters.deface(poster_id, s):
		return _fail(NO_SLOT)
	_emit(&"poster_defaced", {"poster_id": poster_id, "slot": s, "casino_id": run.casino_id(), "poster": poster.to_dict()})
	return _ok({"slot": s, "poster": poster.to_dict()})


# --- Capture ----------------------------------------------------------------

## A guard grabbed the player: stands them up (rounds settle), drops any ID
## check, status CARRIED. Refused (NOT_AVAILABLE) unless targetable (on the
## floor and past the after-rejoin grace). The whole crew carried/detained at
## once (crew of CREW_WIPE_MIN_PLAYERS+) throws it out. -> {ok, reason}
func caught(pid: int, guard_id: int = -1) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	if not ps.is_targetable():
		return _fail(NOT_AVAILABLE)
	_drop_id_check(ps)
	_stand_up(ps)
	_set_status(ps, HR.PlayerStatus.CARRIED)
	_emit(&"caught", {"pid": pid, "guard_id": guard_id})
	_check_crew_wipe()
	return _ok()


## A carried player gets loose. tackler_pid > 0: a teammate tackled the guard
## and goes straight to Wanted (raise_to WANTED_AT, reason TACKLE). 0: the
## guard let go on its own (stunned, fire alarm). -> {ok, reason}
func freed(pid: int, tackler_pid: int = 0) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	if ps.status != HR.PlayerStatus.CARRIED:
		return _fail(NOT_CARRIED)
	var tackler: PlayerState = null
	if tackler_pid != 0:
		if tackler_pid == pid:
			return _fail(SAME_PLAYER)
		tackler = _ps(tackler_pid)
		if tackler == null:
			return _fail(UNKNOWN_PLAYER)
		if not tackler.is_available():
			return _fail(NOT_AVAILABLE)
	_set_status(ps, HR.PlayerStatus.FREE)
	_emit(&"freed", {"pid": pid, "tackler": tackler_pid})
	if tackler != null:
		tackler.heat.raise_to(HeatRules.tackle_min_heat(), HeatRules.TACKLE)
	return _ok()


## The guard got the player to the back room: pocket chips lost, current ID
## burned, Heat reset, a crew strike, DETAINED for BACK_ROOM_TIMEOUT, then
## `rejoined` at the entrance with REJOIN_GRACE_SECONDS of grace. Third
## strike (or the whole crew held) throws the crew out.
## -> {ok, reason, chips_lost, strikes, thrown_out, curb}
func reach_back_room(pid: int) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why != NO_REASON:
		return _fail(why)
	if ps.status != HR.PlayerStatus.CARRIED:
		return _fail(NOT_CARRIED)
	var lost: int = ps.wallet.lose_pocket()
	var id: FakeId = ps.current_id()
	var burned_name := ""
	if id != null and not id.burned:
		id.burn()
		burned_name = id.name
	_set_status(ps, HR.PlayerStatus.DETAINED)
	ps.status_seconds = Tuning.BACK_ROOM_TIMEOUT
	ps.heat.reset()
	_emit(&"detained", {"pid": pid, "chips_lost": lost, "id_burned": burned_name != "", "id_name": burned_name, "seconds": Tuning.BACK_ROOM_TIMEOUT})
	if burned_name != "":
		_emit_id(ps, &"burned")
	var limit_hit: bool = run.add_strike()
	var strikes: int = run.strikes
	_emit(&"strike", {"pid": pid, "strikes": strikes, "max": Tuning.STRIKES_TO_THROW_OUT})
	if limit_hit:
		_throw_out(&"strikes")
	else:
		_check_crew_wipe()
	return _ok({
		"chips_lost": lost,
		"strikes": strikes,
		"thrown_out": finished and outcome == &"thrown_out",
		"curb": ps.status == HR.PlayerStatus.ON_CURB,
	})


# --- Bank, crew play, climbing ----------------------------------------------

## Cashier: banks pocket chips under the current ID (Cashier.cash_out). Banked
## chips go to RunState.add_bank; large cash-outs add Heat; crossing the ID's
## cap flags it (notify). -> {ok, reason, banked, heat, flagged, bank, top_banked}
func cash_out(pid: int, amount: int) -> Dictionary:
	var empty := {"banked": 0, "heat": 0.0, "flagged": false, "bank": run.bank, "top_banked": run.top_banked}
	var ps := _ps(pid)
	var why := _free_in_zone(ps, HR.ZoneType.CASHIER)
	if why != NO_REASON:
		return _fail(why, empty)
	var id: FakeId = ps.current_id()
	var res: Dictionary = Cashier.cash_out(ps.wallet, id, amount, _max_bet())
	if not bool(res["ok"]):
		return _fail(StringName(res["reason"]), empty)
	var banked: int = int(res["banked"])
	var flagged: bool = bool(res["flagged"])
	run.add_bank(banked)
	_emit(&"banked", {"pid": pid, "amount": banked, "bank": run.bank, "top_banked": run.top_banked, "flagged": flagged, "id_name": id.name})
	var applied := 0.0
	if float(res["heat"]) > 0.0:
		applied = _add_heat(ps, float(res["heat"]), HeatRules.CASH_OUT)
	if flagged:
		_emit_id(ps, &"flagged")
		_notify(pid, "%s is flagged: that name fails its next ID check." % id.name, &"flagged")
	return _ok({"banked": banked, "heat": applied, "flagged": flagged, "bank": run.bank, "top_banked": run.top_banked})


## Cashier: takes chips back out of the crew bank into the pocket (never the
## top-rung score). FREE in a CASHIER zone; no ID needed, no Heat.
## -> {ok, reason, amount, pocket, bank}
func withdraw(pid: int, amount: int) -> Dictionary:
	var ps := _ps(pid)
	var empty := {"amount": 0, "pocket": ps.wallet.pocket if ps != null else 0, "bank": run.bank}
	var why := _free_in_zone(ps, HR.ZoneType.CASHIER)
	if why == NO_REASON and amount <= 0:
		why = BAD_AMOUNT
	if why == NO_REASON and amount > run.bank:
		why = NOT_ENOUGH
	if why != NO_REASON:
		return _fail(why, empty)
	run.withdraw(amount)
	ps.wallet.add(amount)
	_emit(&"withdrawn", {"pid": pid, "amount": amount, "bank": run.bank})
	return _ok({"amount": amount, "pocket": ps.wallet.pocket, "bank": run.bank})


## Crew-play distractions (HR.Distraction). `position` is where it happens.
## THROW_CHIPS: costs max(THROW_CHIPS_MIN, pocket × THROW_CHIPS_FRACTION), noise
## + crowd_rush. KNOCK_OVER / BUMP_GUARD: Heat + noise. SLOT_ALARM: crew-wide
## SLOT_ALARM_COOLDOWN, big noise. FIRE_ALARM: once per visit, tables closed
## for FIRE_ALARM_SECONDS. WIN_BIG is not a request (just bet).
## -> {ok, reason, kind, cost, heat}
func distraction(pid: int, kind: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	var ps := _ps(pid)
	var why := _common(ps)
	if why == NO_REASON and not ps.can_act():
		why = BUSY
	var extra := {"kind": kind, "cost": 0, "heat": 0.0}
	if why != NO_REASON:
		return _fail(why, extra)
	match kind:
		HR.Distraction.THROW_CHIPS:
			var cost: int = maxi(Tuning.THROW_CHIPS_MIN, floori(float(ps.wallet.pocket) * Tuning.THROW_CHIPS_FRACTION))
			if not ps.wallet.spend(cost):
				return _fail(NOT_ENOUGH, extra)
			extra["cost"] = cost
			_noise(&"throw_chips", position, pid)
			_emit(&"crowd_rush", {"pid": pid, "position": position, "radius": Tuning.THROW_CHIPS_BLOCK_RADIUS, "seconds": Tuning.THROW_CHIPS_BLOCK_SECONDS})
		HR.Distraction.KNOCK_OVER:
			extra["heat"] = _add_heat(ps, HeatRules.event_heat(HeatRules.KNOCK_OVER), HeatRules.KNOCK_OVER)
			_noise(&"knock_over", position, pid)
		HR.Distraction.BUMP_GUARD:
			extra["heat"] = _add_heat(ps, HeatRules.event_heat(HeatRules.BUMP_GUARD), HeatRules.BUMP_GUARD)
			_noise(&"bump", position, pid)
		HR.Distraction.SLOT_ALARM:
			if slot_alarm_cooldown > 0.0:
				extra["seconds"] = slot_alarm_cooldown
				return _fail(COOLDOWN, extra)
			slot_alarm_cooldown = Tuning.SLOT_ALARM_COOLDOWN
			_noise(&"slot_jackpot", position, pid)
		HR.Distraction.FIRE_ALARM:
			if not run.use_fire_alarm():
				return _fail(USED, extra)
			_start_fire_alarm(position, pid)
		_:
			return _fail(BAD_KIND, extra)
	return _ok(extra)


## Hands pocket chips to a teammate (both FREE or SEATED).
## -> {ok, reason, from_pocket, to_pocket}
func give_chips(from_pid: int, to_pid: int, amount: int) -> Dictionary:
	var a := _ps(from_pid)
	var b := _ps(to_pid)
	var why := _common(a)
	if why == NO_REASON:
		why = _common(b)
	if why == NO_REASON and from_pid == to_pid:
		why = SAME_PLAYER
	if why == NO_REASON and amount <= 0:
		why = BAD_AMOUNT
	if why == NO_REASON and (not a.can_act() or not b.can_act()):
		why = BUSY
	if why == NO_REASON and not a.wallet.give_to(b.wallet, amount):
		why = NOT_ENOUGH
	if why != NO_REASON:
		return _fail(why)
	_emit(&"chips_given", {"from": from_pid, "to": to_pid, "amount": amount})
	return _ok({"from_pocket": a.wallet.pocket, "to_pocket": b.wallet.pocket})


## Climbs when the bank covers the buy-in (two rungs with the stretch amount)
## and every player who isn't DETAINED is FREE in an EXIT zone. Ends the visit.
## Refused with NO_STAKE when the crew would arrive unable to cover the
## min bet up there (every pocket and the bank left after the buy-in short;
## `stake` is that min bet); a stretch that would do that climbs one rung
## instead when that leaves enough.
## -> {ok, reason, from, to, cost, missing: [pids not at the exit], stake}
func try_climb() -> Dictionary:
	var extra := {"from": run.rung, "to": run.rung, "cost": 0, "missing": [], "stake": 0}
	if finished:
		return _fail(FINISHED, extra)
	if not run.can_climb():
		return _fail(CANT_CLIMB, extra)
	var missing: Array = []
	var present := 0
	for ps: PlayerState in players.values():
		if ps.status == HR.PlayerStatus.DETAINED:
			continue
		if ps.status == HR.PlayerStatus.FREE and ps.zone == HR.ZoneType.EXIT:
			present += 1
		else:
			missing.append(ps.pid)
	extra["missing"] = missing
	if not missing.is_empty() or present == 0:
		return _fail(NOT_AT_EXIT, extra)
	var target: int = run.climb_target()
	if _arrives_broke(target) and target == run.rung - 2 and not _arrives_broke(run.rung - 1):
		target = run.rung - 1
	if _arrives_broke(target):
		extra["to"] = target
		extra["stake"] = int(CasinoLadder.casino(target).get("min_bet", 1))
		return _fail(NO_STAKE, extra)
	for ps: PlayerState in players.values():
		_clear_for_exit(ps)
	var from: int = run.rung
	var cost: int = CasinoLadder.climb_cost(from, target)
	var to: int = run.climb(target)
	finished = true
	outcome = &"climbed"
	_emit(&"climbed", {"from": from, "to": to, "cost": cost})
	return _ok({"from": from, "to": to, "cost": cost, "missing": [], "stake": 0})


# --- Clock ------------------------------------------------------------------

## Advances the visit: tables, run clock, forger, fire alarm, slot alarm,
## per-player timers (detention, curb, ID quiz, poster re-arm, rejoin grace,
## loitering) and passive Heat. Time at the top only scores while someone is
## on the floor (not everyone DETAINED / ON_CURB) and the crew isn't broke.
func tick(delta: float) -> void:
	if finished or not delta > 0.0:
		return
	run.tick(delta, _crew_scoring())
	for t: TableState in tables.values():
		t.tick(delta)
	forger.tick(delta)
	if slot_alarm_cooldown > 0.0:
		slot_alarm_cooldown = maxf(0.0, slot_alarm_cooldown - delta)
	if fire_alarm_seconds > 0.0:
		fire_alarm_seconds -= delta
		if fire_alarm_seconds <= 0.0:
			_end_fire_alarm()
	for ps: PlayerState in players.values():
		_tick_player(ps, delta)
	_check_bailout()
	_check_broke(delta)


# --- Queries ----------------------------------------------------------------

func player(pid: int) -> PlayerState:
	return players.get(pid) as PlayerState


func player_ids() -> Array[int]:
	var out: Array[int] = []
	for pid: int in players:
		out.append(pid)
	return out


func table(id: StringName) -> TableState:
	return tables.get(id) as TableState


## A copy of the current casino's Tuning.CASINOS row.
func casino() -> Dictionary:
	return run.casino()


func score() -> int:
	return run.score()


func fire_alarm_active() -> bool:
	return fire_alarm_seconds > 0.0


## True if a poster in this casino recognizes the player's worn outfit.
func matches_poster(pid: int) -> bool:
	var ps := _ps(pid)
	return ps != null and run.posters.matching_poster(run.casino_id(), ps.outfit) != null


## WantedPoster.to_dict() of every poster up in this casino, oldest first.
func posters_here() -> Array:
	var out: Array = []
	for p: WantedPoster in run.posters.posters_in(run.casino_id()):
		out.append(p.to_dict())
	return out


## Full plain-data state for late joiners and the HUD (see ARCHITECTURE.md).
func snapshot() -> Dictionary:
	var ps_out: Dictionary = {}
	for ps: PlayerState in players.values():
		ps_out[ps.pid] = _player_snapshot(ps)
	var tables_out: Dictionary = {}
	for t: TableState in tables.values():
		var seated: Array = []
		seated.assign(t.seated_players())
		tables_out[t.id] = {"game_type": t.game_type, "area_id": t.area_id, "closed": t.closed, "seated": seated}
	var buy_in: int = CasinoLadder.buy_in_to_leave(run.rung)
	var stretch: int = CasinoLadder.climb_cost(run.rung, run.rung - 2)
	var security: Array = []
	security.assign(_casino.get("security", []))
	var climb_to: int = run.climb_target()
	return {
		"players": ps_out,
		"run": {
			"rung": run.rung,
			"casino_id": run.casino_id(),
			"casino_name": str(_casino.get("name", "")),
			"min_bet": _min_bet(),
			"max_bet": _max_bet(),
			"strikes": run.strikes,
			"max_strikes": Tuning.STRIKES_TO_THROW_OUT,
			"bank": run.bank,
			"buy_in": buy_in,
			"stretch_buy_in": stretch,
			"climb_target": run.climb_target(),
			"can_climb": run.can_climb(),
			"top_banked": run.top_banked,
			"score": run.score(),
			"top_seconds": run.top_seconds,
			"visit_seconds": run.visit_seconds,
			"elapsed_seconds": run.elapsed_seconds,
			"visits": run.visits,
			"fire_alarm_used": run.fire_alarm_used,
			"is_top": run.is_top(),
			"is_bottom": run.is_bottom(),
			"security": security,
			"has_cameras": CasinoLadder.has_security(run.rung, HR.SecurityType.CAMERA),
			"start_chips": CasinoLadder.start_chips(run.rung),
			"climb_stake": int(CasinoLadder.casino(climb_to).get("min_bet", 0)) if climb_to < run.rung else 0,
			"scoring": run.is_top() and _crew_scoring(),
		},
		"tables": tables_out,
		"fire_alarm": fire_alarm_active(),
		"fire_alarm_seconds": maxf(0.0, fire_alarm_seconds),
		"slot_alarm_cooldown": slot_alarm_cooldown,
		"forger_location": forger.location(),
		"forger_seconds_until_move": forger.seconds_until_move(),
		"posters": posters_here(),
		"finished": finished,
		"outcome": outcome,
	}


# --- Internals: players -------------------------------------------------------

func _adopt(ps: PlayerState) -> void:
	players[ps.pid] = ps
	ps.heat.changed.connect(_on_heat_changed.bind(ps.pid))
	ps.heat.level_changed.connect(_on_level_changed.bind(ps.pid))
	ps.wallet.changed.connect(_on_pocket_changed.bind(ps.pid))


func _ps(pid: int) -> PlayerState:
	return players.get(pid) as PlayerState


func _common(ps: PlayerState) -> StringName:
	if finished:
		return FINISHED
	if ps == null:
		return UNKNOWN_PLAYER
	return NO_REASON


func _free_in_zone(ps: PlayerState, zone: int) -> StringName:
	var why := _common(ps)
	if why != NO_REASON:
		return why
	if ps.status != HR.PlayerStatus.FREE:
		return BUSY
	if ps.zone != zone:
		return WRONG_ZONE
	return NO_REASON


func _set_status(ps: PlayerState, status: int) -> void:
	if ps.status == status:
		return
	var old: int = ps.status
	ps.status = status
	if status == HR.PlayerStatus.CARRIED or status == HR.PlayerStatus.DETAINED:
		# Someone off the floor: a broke crew's countdown starts over once they're back.
		broke_seconds = 0.0
		_broke_warned = false
	_emit(&"status", {"pid": ps.pid, "status": status, "old": old})


func _seated_table(ps: PlayerState) -> TableState:
	if ps.table_id == &"":
		return null
	var t := table(ps.table_id)
	if t != null and t.is_seated(ps.pid):
		return t
	return null


## Leaves the current table (settling any round first).
func _stand_up(ps: PlayerState) -> void:
	_end_round(ps)
	if ps.table_id == &"":
		return
	var left: StringName = ps.table_id
	var t := table(left)
	if t != null:
		t.leave(ps.pid)
	ps.table_id = &""
	ps.last_table_id = left
	ps.seconds_since_left_table = 0.0
	if ps.status == HR.PlayerStatus.SEATED:
		_set_status(ps, HR.PlayerStatus.FREE)
	_emit(&"stood", {"pid": ps.pid, "table_id": left})


## Settles a round in progress: cash out a high-low run, stand on a blackjack hand.
func _end_round(ps: PlayerState) -> void:
	if ps.high_low != null:
		_cash_out_high_low(ps)
	if ps.blackjack != null:
		_stand_blackjack(ps)


func _cash_out_high_low(ps: PlayerState) -> BetResult:
	var hl: HighLowRun = ps.high_low
	_clear_round(ps)
	var r: BetResult = hl.cash_out()
	_apply_result(ps, r, HeatRules.WIN, true)
	return r


func _stand_blackjack(ps: PlayerState) -> BetResult:
	var bj: BlackjackRound = ps.blackjack
	_clear_round(ps)
	var r: BetResult = bj.stand()
	_apply_result(ps, r, HeatRules.WIN, true)
	return r


func _clear_round(ps: PlayerState) -> void:
	ps.high_low = null
	ps.blackjack = null


func _clear_for_exit(ps: PlayerState) -> void:
	_drop_id_check(ps)
	_stand_up(ps)


func _drop_id_check(ps: PlayerState) -> void:
	ps.id_question = {}
	ps.id_check_guard = -1
	ps.id_check_seconds = 0.0


func _end_id_check(ps: PlayerState, passed: bool, reason: StringName) -> void:
	var guard_id: int = ps.id_check_guard
	_drop_id_check(ps)
	if passed:
		ps.id_cleared_level = ps.heat.level()
		ps.id_cleared_poster = matches_poster(ps.pid)
	if ps.status == HR.PlayerStatus.ID_CHECK:
		_set_status(ps, HR.PlayerStatus.SEATED if _seated_table(ps) != null else HR.PlayerStatus.FREE)
	_emit(&"id_result", {"pid": ps.pid, "guard_id": guard_id, "passed": passed, "reason": reason})


func _public_question(q: Dictionary) -> Dictionary:
	var options: Array = []
	options.assign(q.get("options", []))
	return {"field": q.get("field", &""), "prompt": str(q.get("prompt", "")), "options": options}


func _recognized(ps: PlayerState) -> bool:
	return ps.recorded_look != null and ps.outfit.is_recognized_as(ps.recorded_look)


## Makes sure the player plays under a card that passes a check: switches to a
## held one, else hands out a fresh REJOIN_ID_GRADE card. True if a card was given.
func _ensure_usable_id(ps: PlayerState) -> bool:
	var cur: FakeId = ps.current_id()
	if cur != null and cur.passes_check():
		return false
	var i: int = ps.first_usable_id_index()
	if i >= 0:
		ps.id_index = i
		_emit_id(ps, &"auto_swap")
		return false
	ps.ids.append(IdGenerator.generate(Tuning.REJOIN_ID_GRADE, rng, _id_names(), run.name_packs(ps.pid)))
	ps.id_index = ps.ids.size() - 1
	_emit_id(ps, &"rejoin")
	return true


func _id_names() -> Array:
	var names: Array = []
	for ps: PlayerState in players.values():
		for id: FakeId in ps.ids:
			names.append(id.name)
	return names


func _owns_piece(ps: PlayerState, slot: int, piece: StringName) -> bool:
	if ps.outfit.get_piece(slot) == piece:
		return true
	for o: Outfit in ps.stash:
		if o.get_piece(slot) == piece:
			return true
	return false


## A new look: poster match re-armed, clearance refreshed and the outfit
## cool-down (none within CHANGE_OUTFIT_COOLDOWN of the last change).
func _after_outfit_change(ps: PlayerState, reason: StringName) -> float:
	ps.outfit_changes += 1
	ps.poster_match_armed = true
	_refresh_clearance(ps, matches_poster(ps.pid))
	_emit_outfit(ps, true, reason)
	var cool: float = HeatRules.change_outfit_heat(ps.seconds_since_outfit_change)
	ps.seconds_since_outfit_change = 0.0
	return ps.heat.add(cool, HeatRules.CHANGE_OUTFIT)


## A passed check stops counting on a new poster match (one that wasn't
## there when they passed); not matching any more forgets the old match, so
## matching again later counts as new.
func _refresh_clearance(ps: PlayerState, poster_match: bool) -> void:
	if not ps.id_cleared():
		return
	if poster_match and not ps.id_cleared_poster:
		ps.clear_id_clearance()
	else:
		ps.id_cleared_poster = poster_match


## Sat down or played: loitering starts over, and the next sit may reset it again.
func _mark_played(ps: PlayerState) -> void:
	ps.loiter_seconds = 0.0
	ps.loiter_sit_reset = true


func _poster_here(poster_id: int) -> WantedPoster:
	for p: WantedPoster in run.posters.posters_in(run.casino_id()):
		if p.id == poster_id:
			return p
	return null


static func _deface_slot(poster: WantedPoster, look: Outfit) -> int:
	var first := -1
	for slot: int in OutfitCatalog.all_slots():
		if poster.is_defaced(slot):
			continue
		if first < 0:
			first = slot
		if poster.outfit.get_piece(slot) == look.get_piece(slot):
			return slot
	return first


# --- Internals: heat and results ----------------------------------------------

## Adds Heat with the pit boss multiplier on gains (player flags, plus extra_ctx).
func _add_heat(ps: PlayerState, amount: float, reason: StringName, extra_ctx: Dictionary = {}) -> float:
	var ctx: Dictionary = ps.flags
	if not extra_ctx.is_empty():
		ctx = ps.flags.duplicate()
		ctx.merge(extra_ctx, true)
	return ps.heat.add(HeatRules.scale_gain(amount, ctx), reason)


## Pays out, emits &"bet", applies the result's Heat and any loud noise. Called
## exactly once per BetResult.
func _apply_result(ps: PlayerState, r: BetResult, win_reason: StringName, round_over: bool) -> void:
	if r.won:
		ps.seconds_since_win = 0.0
	if r.payout > 0:
		ps.wallet.add(r.payout)
	_emit(&"bet", {"pid": ps.pid, "table_id": r.table_id, "game_type": r.game_type, "result": r.to_dict(), "pocket": ps.wallet.pocket, "round_over": round_over})
	if r.heat > 0.0:
		_add_heat(ps, r.heat, win_reason)
	elif r.heat < 0.0:
		_add_heat(ps, r.heat, HeatRules.LOSE_ON_PURPOSE)
	if r.loud:
		var kind: StringName = &"slot_jackpot" if r.jackpot else &"big_wheel"
		_noise(kind, _table_positions.get(r.table_id, Vector3.ZERO), ps.pid)


func _bet_check(ps: PlayerState, t: TableState, amount: int) -> StringName:
	var why := _common(ps)
	if why != NO_REASON:
		return why
	if t == null:
		return UNKNOWN_TABLE
	if t.closed:
		return TABLE_CLOSED
	if ps.table_id != t.id or not t.is_seated(ps.pid):
		return NOT_SEATED
	if ps.status != HR.PlayerStatus.SEATED:
		return BUSY
	if ps.in_round():
		return IN_ROUND
	if amount <= 0:
		return BAD_AMOUNT
	if amount < _min_bet():
		return BELOW_MIN
	if amount > _max_bet():
		return ABOVE_MAX
	if amount > ps.wallet.pocket:
		return NOT_ENOUGH
	return NO_REASON


func _round_check(ps: PlayerState, kind: StringName) -> StringName:
	var why := _common(ps)
	if why != NO_REASON:
		return why
	if ps.round_kind() != kind:
		return NO_ROUND
	if ps.status != HR.PlayerStatus.SEATED:
		return BUSY
	return NO_REASON


func _emit_hand(ps: PlayerState) -> void:
	var state: Dictionary = {}
	var game_type := -1
	if ps.high_low != null:
		var hl: HighLowRun = ps.high_low
		game_type = HR.GameType.HIGH_LOW
		state = {"kind": &"high_low", "bet": hl.bet, "pot": hl.pot, "card": hl.current_card, "streak": hl.streak, "finished": hl.finished}
	elif ps.blackjack != null:
		var bj: BlackjackRound = ps.blackjack
		game_type = HR.GameType.BLACKJACK
		state = {
			"kind": &"blackjack", "bet": bj.bet,
			"player_cards": bj.player_cards.duplicate(), "dealer_cards": bj.dealer_cards.duplicate(),
			"player_total": bj.player_total(), "finished": bj.finished,
		}
	else:
		return
	_emit(&"hand", {"pid": ps.pid, "table_id": ps.round_table_id, "game_type": game_type, "state": state})


func _check_crew_wipe() -> void:
	if finished or players.size() < Tuning.CREW_WIPE_MIN_PLAYERS:
		return
	for ps: PlayerState in players.values():
		if ps.status != HR.PlayerStatus.CARRIED and ps.status != HR.PlayerStatus.DETAINED:
			return
	_throw_out(&"crew_detained")


## Three strikes, the whole crew held, or a broke crew. At the bottom rung
## it's a curb timeout (&"curb", the visit goes on); otherwise the visit ends
## (&"thrown_out"), one rung down or to `to_rung` when given.
func _throw_out(cause: StringName, to_rung: int = -1) -> void:
	if finished:
		return
	var from: int = run.rung
	if run.is_bottom():
		run.throw_out()
		for ps: PlayerState in players.values():
			_clear_for_exit(ps)
			_set_status(ps, HR.PlayerStatus.ON_CURB)
			ps.status_seconds = Tuning.CURB_TIMEOUT
			ps.recorded_look = null
			ps.heat.reset()
		_emit(&"curb", {"rung": from, "seconds": Tuning.CURB_TIMEOUT, "cause": cause})
		return
	for ps: PlayerState in players.values():
		_clear_for_exit(ps)
	var to: int = run.throw_out(to_rung)
	finished = true
	outcome = &"thrown_out"
	_emit(&"thrown_out", {"from": from, "to": to, "cause": cause})


## Back on the floor after the back room or the curb: processed, so Heat 0,
## no ID clearance, loitering starts over and guards leave them alone for
## REJOIN_GRACE_SECONDS. They come back in at the entrance (`spawn`).
func _rejoin(ps: PlayerState) -> void:
	var from: StringName = &"curb" if ps.status == HR.PlayerStatus.ON_CURB else &"back_room"
	ps.status_seconds = 0.0
	ps.zone = HR.ZoneType.ENTRANCE
	ps.area_id = &""
	ps.rejoin_grace = Tuning.REJOIN_GRACE_SECONDS
	ps.loiter_seconds = 0.0
	ps.loiter_sit_reset = true
	ps.clear_id_clearance()
	ps.heat.reset()
	_set_status(ps, HR.PlayerStatus.FREE)
	var new_id: bool = _ensure_usable_id(ps)
	_emit(&"rejoined", {"pid": ps.pid, "from": from, "new_id": new_id, "spawn": &"entrance", "grace": Tuning.REJOIN_GRACE_SECONDS})


func _tick_player(ps: PlayerState, delta: float) -> void:
	if ps.seconds_since_left_table >= 0.0:
		ps.seconds_since_left_table += delta
	ps.seconds_since_area_change += delta
	ps.seconds_since_outfit_change += delta
	ps.seconds_since_win += delta
	ps.seconds_unseen += delta
	if ps.seconds_unseen >= Tuning.POSTER_MATCH_REARM_SECONDS:
		ps.poster_match_armed = true
	if ps.steal_cooldown > 0.0:
		ps.steal_cooldown = maxf(0.0, ps.steal_cooldown - delta)
	match ps.status:
		HR.PlayerStatus.DETAINED, HR.PlayerStatus.ON_CURB:
			ps.status_seconds -= delta
			if ps.status_seconds <= 0.0:
				_rejoin(ps)
			return
		HR.PlayerStatus.CARRIED:
			return
		HR.PlayerStatus.ID_CHECK:
			ps.id_check_seconds -= delta
			if ps.id_check_seconds <= 0.0 and not ps.id_question.is_empty():
				_end_id_check(ps, false, ID_TIMEOUT)
	if ps.rejoin_grace > 0.0:
		ps.rejoin_grace = maxf(0.0, ps.rejoin_grace - delta)
	# Waiting at the exit for the crew is fine below the top (no score there).
	if run.is_top() or ps.zone != HR.ZoneType.EXIT:
		ps.loiter_seconds += delta
	var ctx: Dictionary = ps.flags.duplicate()
	ctx["zone"] = ps.zone
	ctx["heat"] = ps.heat.value
	ctx["loiter_seconds"] = ps.loiter_seconds
	ctx["seconds_since_win"] = ps.seconds_since_win
	var t := _seated_table(ps)
	ctx["seated_game"] = t.game_type if t != null else -1
	ctx["seconds_at_table"] = t.seconds_seated(ps.pid) if t != null else 0.0
	var rates: Dictionary = HeatRules.passive_rates(ctx)
	for reason: StringName in rates:
		ps.heat.add(HeatRules.scale_gain(float(rates[reason]), ctx) * delta, reason)


## Sal's: a broke crew (every pocket and the bank under the min bet, no round
## in progress) gets BAILOUT_CHIPS each.
func _check_bailout() -> void:
	if not run.is_bottom() or players.is_empty():
		return
	if not _crew_broke():
		return
	for ps: PlayerState in players.values():
		ps.wallet.add(Tuning.BAILOUT_CHIPS)
	_notify(0, "Sal takes pity: %d chips each to get back in the game." % Tuning.BAILOUT_CHIPS, &"bailout")


## Above Sal's and below the top: a crew on the floor that can't cover a bet
## (every pocket and the bank under the min bet, no round in progress) can't
## do anything there. After BROKE_GRACE_SECONDS it is thrown out to the
## highest rung below where the bank covers a bet (Sal's at worst, where the
## bailout picks it up). At the top the exit (end of run) is always open.
func _check_broke(delta: float) -> void:
	if finished or run.is_bottom() or run.is_top() or players.is_empty() or not _crew_broke():
		broke_seconds = 0.0
		_broke_warned = false
		return
	for ps: PlayerState in players.values():
		if ps.status == HR.PlayerStatus.CARRIED or ps.status == HR.PlayerStatus.DETAINED:
			broke_seconds = 0.0
			_broke_warned = false
			return
	if not _broke_warned:
		# Counting starts on the next tick, so one long tick (a rejoin in the
		# middle of it) never skips the warning.
		_broke_warned = true
		_notify(0, "Out of chips, and nothing in the bank: security walks the crew out in %d s." % ceili(Tuning.BROKE_GRACE_SECONDS), &"broke")
		return
	broke_seconds += delta
	if broke_seconds < Tuning.BROKE_GRACE_SECONDS:
		return
	broke_seconds = 0.0
	var to: int = Tuning.BOTTOM_RUNG
	for r in range(run.rung + 1, Tuning.BOTTOM_RUNG):
		if run.bank >= int(CasinoLadder.casino(r).get("min_bet", 1)):
			to = r
			break
	_throw_out(&"broke", to)


## Time at the top counts towards the score: someone is on the floor (not
## every player DETAINED or ON_CURB) and the crew can still cover a bet.
func _crew_scoring() -> bool:
	for ps: PlayerState in players.values():
		if ps.status != HR.PlayerStatus.DETAINED and ps.status != HR.PlayerStatus.ON_CURB:
			return not _crew_broke()
	return false


## After climbing to `target` (paying its cost) every pocket and the bank
## left would be under the min bet there.
func _arrives_broke(target: int) -> bool:
	var min_bet: int = int(CasinoLadder.casino(target).get("min_bet", 1))
	if run.bank - CasinoLadder.climb_cost(run.rung, target) >= min_bet:
		return false
	for ps: PlayerState in players.values():
		if ps.wallet.pocket >= min_bet:
			return false
	return true


## Every pocket and the crew bank are under this casino's min bet, and no round is in progress.
func _crew_broke() -> bool:
	var min_bet: int = _min_bet()
	if run.bank >= min_bet:
		return false
	for ps: PlayerState in players.values():
		if ps.in_round() or ps.wallet.pocket >= min_bet:
			return false
	return true


func _start_fire_alarm(position: Vector3, pid: int) -> void:
	fire_alarm_seconds = Tuning.FIRE_ALARM_SECONDS
	for t: TableState in tables.values():
		t.closed = true
	_emit(&"fire_alarm", {"active": true, "seconds": Tuning.FIRE_ALARM_SECONDS, "pid": pid})
	for ps: PlayerState in players.values():
		if ps.table_id != &"":
			_stand_up(ps)
	_noise(&"fire_alarm", position, pid)


func _end_fire_alarm() -> void:
	fire_alarm_seconds = 0.0
	for t: TableState in tables.values():
		t.closed = false
	_emit(&"fire_alarm", {"active": false, "seconds": 0.0, "pid": 0})


# --- Internals: casino numbers ------------------------------------------------

func _min_bet() -> int:
	return int(_casino.get("min_bet", 1))


func _max_bet() -> int:
	return int(_casino.get("max_bet", 1))


func _payout_bonus() -> float:
	return float(_casino.get("payout_bonus", 1.0))


# --- Internals: events --------------------------------------------------------

static func _ok(extra: Dictionary = {}) -> Dictionary:
	var d := {"ok": true, "reason": NO_REASON}
	d.merge(extra)
	return d


static func _fail(reason: StringName, extra: Dictionary = {}) -> Dictionary:
	var d := {"ok": false, "reason": reason}
	d.merge(extra)
	return d


func _emit(kind: StringName, data: Dictionary) -> void:
	event.emit(kind, data)


func _noise(kind: StringName, position: Vector3, pid: int) -> void:
	var radius: float = float(Tuning.NOISE_RADIUS.get(kind, Tuning.NOISE_RADIUS[&"knock_over"]))
	_emit(&"noise", {"position": position, "radius": radius, "kind": kind, "pid": pid})


func _notify(pid: int, text: String, kind: StringName) -> void:
	_emit(&"notify", {"pid": pid, "text": text, "kind": kind})


func _emit_id(ps: PlayerState, reason: StringName) -> void:
	var cur: FakeId = ps.current_id()
	_emit(&"id", {"pid": ps.pid, "id": cur.to_dict() if cur != null else {}, "index": ps.id_index, "count": ps.ids.size(), "reason": reason})


func _emit_outfit(ps: PlayerState, worn_changed: bool, reason: StringName) -> void:
	_emit(&"outfit", {"pid": ps.pid, "outfit": ps.outfit.to_dict(), "stash": ps.stash_dicts(), "worn_changed": worn_changed, "reason": reason})


func _player_snapshot(ps: PlayerState) -> Dictionary:
	var cur: FakeId = ps.current_id()
	return {
		"pid": ps.pid,
		"name": ps.display_name,
		"heat": ps.heat.value,
		"level": ps.heat.level(),
		"pocket": ps.wallet.pocket,
		"lifetime_banked": ps.wallet.lifetime_banked,
		"status": ps.status,
		"status_seconds": maxf(0.0, ps.status_seconds),
		"zone": ps.zone,
		"area_id": ps.area_id,
		"table_id": ps.table_id,
		"round": ps.round_kind(),
		"outfit": ps.outfit.to_dict(),
		"stash": ps.stash_dicts(),
		"stash_size": ps.stash.size(),
		"id": cur.to_dict() if cur != null else {},
		"id_index": ps.id_index,
		"ids": ps.id_dicts(),
		"id_count": ps.ids.size(),
		"id_check": _public_question(ps.id_question) if not ps.id_question.is_empty() else {},
		"recorded_look": ps.recorded_look.to_dict() if ps.recorded_look != null else {},
		"recognized": _recognized(ps),
		"matches_poster": run.posters.matching_poster(run.casino_id(), ps.outfit) != null,
		"staff_uniform": ps.outfit.is_staff_uniform(),
		"available": ps.is_available(),
		"targetable": ps.is_targetable(),
		"rejoin_grace": ps.rejoin_grace,
		"id_cleared": ps.id_cleared(),
		"loiter_seconds": ps.loiter_seconds,
		"loitering": ps.is_loitering(),
		"flags": ps.flags.duplicate(),
	}


# --- Signal handlers ----------------------------------------------------------

func _on_heat_changed(value: float, delta: float, reason: StringName, pid: int) -> void:
	_heat_reason[pid] = reason
	_emit(&"heat", {"pid": pid, "value": value, "delta": delta, "reason": reason, "level": HeatMeter.level_for(value)})


func _on_level_changed(old_level: int, new_level: int, pid: int) -> void:
	var ps := _ps(pid)
	if ps == null:
		return
	_emit(&"level", {"pid": pid, "old": old_level, "new": new_level, "name": HeatMeter.level_name(new_level)})
	if new_level < old_level:
		if old_level == HR.HeatLevel.WANTED:
			ps.poster_armed = true
		if ps.id_cleared_level > new_level:
			ps.id_cleared_level = new_level
		return
	if ps.id_cleared() and new_level > ps.id_cleared_level:
		ps.clear_id_clearance()
	if new_level >= HR.HeatLevel.WATCHED:
		ps.rejoin_grace = 0.0
	match new_level:
		HR.HeatLevel.WATCHED:
			# Only Heat earned playing this table swaps its dealer (not a
			# table jump, camera or poster that crosses Watched as they sit).
			var t := _seated_table(ps)
			if t != null and not t.is_cooled(pid) and HeatRules.is_table_play(_heat_reason.get(pid, &"")):
				t.mark_cooled(pid)
				_emit(&"dealer_swap", {"pid": pid, "table_id": t.id})
		HR.HeatLevel.SUSPECTED:
			ps.recorded_look = ps.outfit.copy()
			_emit(&"look_recorded", {"pid": pid, "outfit": ps.recorded_look.to_dict()})
		HR.HeatLevel.WANTED:
			if ps.poster_armed:
				ps.poster_armed = false
				var poster: WantedPoster = run.posters.print_poster(run.casino_id(), pid, ps.outfit)
				_emit(&"poster", {"pid": pid, "casino_id": run.casino_id(), "poster": poster.to_dict()})


func _on_pocket_changed(pocket: int, delta: int, pid: int) -> void:
	_emit(&"chips", {"pid": pid, "pocket": pocket, "delta": delta})


func _on_forger_moved(location: StringName) -> void:
	_emit(&"forger_moved", {"location": location})
