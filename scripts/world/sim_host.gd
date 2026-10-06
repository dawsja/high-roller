class_name SimHost
extends Node
## Owns the run (RunState) and the current visit's FloorSim, ticks the sim in
## _physics_process and re-emits every FloorSim event as `sim_event`. World
## and UI code send requests only through the request_* methods, which take
## the same arguments and return the same values as the FloorSim request of
## the same name. This is the RPC boundary of co-op (docs/ARCHITECTURE.md,
## "Networking"):
##
## - OFFLINE (single player) and HOST run the FloorSim here. A request runs at
##   once, returns its result and emits `request_done` before it returns.
## - HOST also broadcasts every sim event to the clients (reliable, batched per
##   frame; passive Heat ticks coalesced to SNAPSHOT_SECONDS), a compressed
##   snapshot every SNAPSHOT_SECONDS (unreliable ordered) and each new visit.
##   Requests from clients are type-checked, must name the sender's own pid,
##   pass any world-side validator (set_validator), then run and are answered.
## - CLIENT has no sim. request_<name>() sends the request to the host and
##   returns {ok: true, reason: &"pending"} (request_start_* return null);
##   the answer arrives as `request_done`, the effects as `sim_event`.
##   snapshot() is the last snapshot from the host, patched by every event.
##   Host-only requests (guards, flags, tables) return {ok: false, reason:
##   &"host_only"} and are not sent.
##
## Without a current visit every request_* returns {ok: false, reason:
## &"no_sim"} (request_start_* return null, request_register_table null).

signal sim_event(kind: StringName, data: Dictionary)
## A new FloorSim is live (players added, no tables yet; the director
## registers them). On a client `sim` is null: the host announced a visit
## (see visit_info()).
signal visit_started(sim: FloorSim)
## A request this peer made has its answer: on the host and offline right
## away (inside request_*), on a client when the host's reply arrives. Every
## request_* call gets exactly one, with the same args. request_start_* answer
## {ok, reason}.
signal request_done(request: StringName, args: Array, result: Dictionary)
## A world message (send_world) from peer `from_pid`, for the current visit.
signal world_message(kind: StringName, data: Dictionary, from_pid: int)
## Client: a fresh snapshot from the host replaced the cached one.
signal snapshot_received()

const NO_SIM := &"no_sim"
## A client's request is on its way to the host.
const PENDING := &"pending"
## Only the host may make this request (guards, cameras, flags, tables).
const HOST_ONLY := &"host_only"
## A client asked for a player that isn't its own.
const NOT_YOUR_PLAYER := &"not_your_player"
## A client's arguments had the wrong count or types.
const BAD_ARGS := &"bad_args"
const UNKNOWN_REQUEST := &"unknown_request"
const NOT_CONNECTED := &"not_connected"

enum Role { OFFLINE, HOST, CLIENT }

## Snapshots (and coalesced passive Heat) go out this often (real seconds).
const SNAPSHOT_SECONDS := 0.1
## A dice table with two or more crew seated collects bets this long, then
## rolls them all at once (FloorSim.place_shared_roll).
const SHARED_ROLL_SECONDS := 3.0
## Longest StringName a client may send.
const MAX_NAME_LENGTH := 128
## Heat reasons that tick every frame (HUD popups ignore them too).
const PASSIVE_HEAT: Array[StringName] = [
	HeatRules.CAMPING, HeatRules.SLOT_BLEND, HeatRules.OFF_TABLE,
	HeatRules.FLOOR_DECAY, HeatRules.RUN_IN_VIEW, HeatRules.CAMERA,
]

## Every FloorSim request that has a request_<name> method here.
const REQUESTS: Array[StringName] = [
	&"register_table", &"sit", &"stand", &"place_bet", &"place_shared_roll",
	&"start_high_low", &"high_low_guess", &"high_low_cash_out",
	&"start_blackjack", &"blackjack_hit", &"blackjack_stand",
	&"enter_zone", &"set_player_flags", &"report_seen",
	&"change_to_stash", &"change_outfit", &"buy_outfit_piece", &"steal_outfit_piece",
	&"buy_id", &"swap_id", &"start_id_check", &"answer_id_check", &"expire_id_check",
	&"tear_poster", &"deface_poster",
	&"caught", &"freed", &"reach_back_room",
	&"cash_out", &"withdraw", &"distraction", &"give_chips", &"try_climb",
]

## Wire types of each request's arguments (all of them, defaults filled in).
const REQUEST_ARGS := {
	&"register_table": [TYPE_STRING_NAME, TYPE_INT, TYPE_STRING_NAME, TYPE_VECTOR3],
	&"sit": [TYPE_INT, TYPE_STRING_NAME, TYPE_BOOL],
	&"stand": [TYPE_INT],
	&"place_bet": [TYPE_INT, TYPE_STRING_NAME, TYPE_INT, TYPE_DICTIONARY],
	&"place_shared_roll": [TYPE_STRING_NAME, TYPE_ARRAY],
	&"start_high_low": [TYPE_INT, TYPE_STRING_NAME, TYPE_INT],
	&"high_low_guess": [TYPE_INT, TYPE_BOOL, TYPE_BOOL],
	&"high_low_cash_out": [TYPE_INT],
	&"start_blackjack": [TYPE_INT, TYPE_STRING_NAME, TYPE_INT],
	&"blackjack_hit": [TYPE_INT],
	&"blackjack_stand": [TYPE_INT],
	&"enter_zone": [TYPE_INT, TYPE_INT, TYPE_STRING_NAME],
	&"set_player_flags": [TYPE_INT, TYPE_DICTIONARY],
	&"report_seen": [TYPE_INT, TYPE_DICTIONARY],
	&"change_to_stash": [TYPE_INT, TYPE_INT],
	&"change_outfit": [TYPE_INT, TYPE_DICTIONARY],
	&"buy_outfit_piece": [TYPE_INT, TYPE_INT, TYPE_STRING_NAME],
	&"steal_outfit_piece": [TYPE_INT],
	&"buy_id": [TYPE_INT, TYPE_INT],
	&"swap_id": [TYPE_INT, TYPE_INT],
	&"start_id_check": [TYPE_INT, TYPE_INT],
	&"answer_id_check": [TYPE_INT, TYPE_INT],
	&"expire_id_check": [TYPE_INT],
	&"tear_poster": [TYPE_INT, TYPE_INT, TYPE_VECTOR3],
	&"deface_poster": [TYPE_INT, TYPE_INT, TYPE_INT],
	&"caught": [TYPE_INT, TYPE_INT],
	&"freed": [TYPE_INT, TYPE_INT],
	&"reach_back_room": [TYPE_INT],
	&"cash_out": [TYPE_INT, TYPE_INT],
	&"withdraw": [TYPE_INT, TYPE_INT],
	&"distraction": [TYPE_INT, TYPE_INT, TYPE_VECTOR3],
	&"give_chips": [TYPE_INT, TYPE_INT, TYPE_INT],
	&"try_climb": [],
}

## Requests a client may send -> index of the argument that must be the
## sender's own pid (-1: none). Everything else is host-only.
const CLIENT_REQUESTS := {
	&"sit": 0, &"stand": 0, &"place_bet": 0,
	&"start_high_low": 0, &"high_low_guess": 0, &"high_low_cash_out": 0,
	&"start_blackjack": 0, &"blackjack_hit": 0, &"blackjack_stand": 0,
	&"enter_zone": 0, &"change_to_stash": 0, &"change_outfit": 0,
	&"buy_outfit_piece": 0, &"steal_outfit_piece": 0, &"buy_id": 0, &"swap_id": 0,
	&"answer_id_check": 0, &"expire_id_check": 0, &"tear_poster": 0, &"deface_poster": 0,
	&"cash_out": 0, &"withdraw": 0, &"distraction": 0, &"give_chips": 0, &"try_climb": -1,
}

var run: RunState = null
var sim: FloorSim = null
## While true the sim is not ticked (pause menu; never in co-op).
var paused: bool = false
## pid -> display name of the crew.
var player_names: Dictionary = {}
## Role.OFFLINE, HOST or CLIENT (set_network).
var role: int = Role.OFFLINE
## This peer's player id (1 offline and on the host).
var local_pid: int = 1
## Extra keys for visit_info() of the next start_visit() (main.gd: practice).
var visit_extras: Dictionary = {}
## Tests: outgoing messages go to transport.call(to_peer: int, method:
## StringName, args: Array) instead of RPCs (to_peer 0 = every client; the
## receiving side calls receive()).
var transport: Callable = Callable()

var _seed: int = 0
var _visit_serial: int = 0
var _visit_info: Dictionary = {}
# Host side.
var _outbox: Array = []
var _passive: Dictionary = {}
var _event_serial: int = 0
var _snapshot_due_usec: int = 0
var _validators: Dictionary = {}
var _rolls: Dictionary = {}
# Client side.
var _cache: Dictionary = {}
var _hands: Dictionary = {}
var _seq: int = 0
var _pending: Dictionary = {}
var _applied_serial: int = 0
var _snap_serial: int = 0


## OFFLINE (single player), HOST or CLIENT; `pid` is this peer's player id.
## Clears the per-session network state.
func set_network(p_role: int, pid: int = 1) -> void:
	role = p_role
	local_pid = pid
	_outbox.clear()
	_passive.clear()
	_pending.clear()
	_rolls.clear()
	_hands.clear()
	_applied_serial = 0
	_snap_serial = 0
	if role == Role.CLIENT:
		_drop_sim()
		run = null
		_cache = {}
	else:
		_cache = {}


func is_client() -> bool:
	return role == Role.CLIENT


## True offline and on the host: this peer runs the FloorSim.
func is_authority() -> bool:
	return role != Role.CLIENT


func is_online() -> bool:
	return role != Role.OFFLINE


## Starts a new run. The first visit starts with start_visit(). Host only.
func start_run(start_rung: int, seed_value: int, names: Dictionary) -> void:
	_drop_sim()
	run = RunState.new(start_rung)
	_seed = seed_value
	player_names = names.duplicate()
	paused = false


## Starts a visit at the run's current casino: a new FloorSim that carries the
## crew's PlayerStates over from the previous visit (new players are added
## from player_names). Starts a default run (top rung, 1 player) if none.
## The host announces the visit to every client. Host only (null on a client).
func start_visit() -> FloorSim:
	if role == Role.CLIENT:
		return null
	if run == null:
		start_run(Tuning.TOP_RUNG, 0, {1: "Player"})
	var carried: Array = []
	if sim != null:
		carried.assign(sim.players.values())
	_drop_sim()
	var next := FloorSim.new(run, _visit_seed(), carried)
	sim = next
	next.event.connect(_on_sim_event)
	for pid: Variant in player_names:
		if next.player(int(pid)) == null:
			next.add_player(int(pid), str(player_names[pid]))
	_visit_serial += 1
	_visit_info = {
		"token": _visit_serial,
		"rung": run.rung,
		"visits": run.visits,
		"casino_id": run.casino_id(),
		"map_seed": hash([String(run.casino_id()), run.visits, run.rung]),
	}
	_visit_info.merge(visit_extras, true)
	NetLog.line("visit", {"token": _visit_serial, "rung": run.rung, "map_seed": _visit_info["map_seed"]})
	visit_started.emit(next)
	if role == Role.HOST:
		_flush_events()
		_visit_info["serial"] = _event_serial
		_send(0, &"visit", [_visit_info, _pack(next.snapshot())])
	return next


func current_sim() -> FloorSim:
	return sim


## The current visit: {token, rung, visits, casino_id, map_seed} plus
## visit_extras ({} before the first visit).
func visit_info() -> Dictionary:
	return _visit_info


## Changes with every visit (world messages carry it).
func visit_token() -> int:
	return int(_visit_info.get("token", 0))


## FloorSim.snapshot() of the current visit, or {"run": RunState.to_dict()}
## (or {}) when there is no visit. A client returns the host's last snapshot,
## patched by every event since.
func snapshot() -> Dictionary:
	if role == Role.CLIENT:
		return _cache
	if sim != null:
		return sim.snapshot()
	if run != null:
		return {"run": run.to_dict()}
	return {}


## pids of the crew in join order (the snapshot's order on a client).
func player_ids() -> Array[int]:
	if sim != null:
		return sim.player_ids()
	var out: Array[int] = []
	for pid: Variant in (snapshot().get("players", {}) as Dictionary):
		out.append(int(pid))
	return out


## The round `pid` has in progress, as the last &"hand" event state ({} if none).
func round_state(pid: int) -> Dictionary:
	if role == Role.CLIENT:
		return (_hands.get(pid, {}) as Dictionary).duplicate(true)
	var ps: PlayerState = sim.player(pid) if sim != null else null
	if ps == null:
		return {}
	if ps.high_low != null:
		var hl: HighLowRun = ps.high_low
		return {"kind": &"high_low", "bet": hl.bet, "pot": hl.pot, "card": hl.current_card, "streak": hl.streak, "finished": hl.finished}
	if ps.blackjack != null:
		var bj: BlackjackRound = ps.blackjack
		return {"kind": &"blackjack", "bet": bj.bet, "player_cards": bj.player_cards.duplicate(), "dealer_cards": bj.dealer_cards.duplicate(), "player_total": bj.player_total(), "finished": bj.finished}
	return {}


## Host: `check.call(sender_pid: int, args: Array) -> StringName` runs on every
## client request of that name after the type and pid checks; a non-empty
## reason rejects it. It may adjust `args` in place (e.g. the host's own view
## of `in_view`). An invalid Callable removes it.
func set_validator(request: StringName, check: Callable) -> void:
	if check.is_valid():
		_validators[request] = check
	else:
		_validators.erase(request)


## Host: drops a player who left the session. They stand up (a round in
## progress settles), and leave the visit's crew and the run. The world layer
## emits a synthetic &"player_left" {pid} event.
func remove_player(pid: int) -> void:
	player_names.erase(pid)
	if sim == null or sim.player(pid) == null:
		return
	sim.stand(pid)
	var ps := sim.player(pid)
	ps.release_listeners()
	# FloorSim has no removal request yet: drop the PlayerState so the crew
	# rules (climb, crew wipe, broke) only count who is still here.
	sim.players.erase(pid)
	_emit_world_event(&"player_left", {"pid": pid})


## Sends a world message for the current visit to peer `to_pid` (0: every
## other peer). The receiver gets `world_message` if it is on the same visit.
## Unreliable messages may be dropped (positions, probes).
func send_world(to_pid: int, kind: StringName, data: Dictionary = {}, reliable: bool = true) -> void:
	if role == Role.OFFLINE or to_pid == local_pid:
		return
	_flush_events()
	_send(to_pid, &"world" if reliable else &"world_fast", [visit_token(), kind, data])


func _physics_process(delta: float) -> void:
	if role == Role.CLIENT or paused or sim == null:
		return
	if not sim.finished:
		sim.tick(delta)
	if not _rolls.is_empty():
		_tick_shared_rolls(delta)


func _process(_delta: float) -> void:
	if role != Role.HOST:
		return
	var now := Time.get_ticks_usec()
	if sim != null and now >= _snapshot_due_usec and _has_audience():
		_snapshot_due_usec = now + int(SNAPSHOT_SECONDS * 1_000_000.0)
		for pid: int in _passive.keys():
			_flush_passive(pid)
		_flush_events()
		_send(0, &"snapshot", [_event_serial, _pack(sim.snapshot())])
	else:
		_flush_events()


# --- Requests (same args and returns as FloorSim) ---------------------------

func request_register_table(id: StringName, game_type: int, area_id: StringName, position: Vector3 = Vector3.ZERO) -> TableState:
	if role == Role.CLIENT or sim == null:
		return null
	return sim.register_table(id, game_type, area_id, position)


func request_sit(pid: int, table_id: StringName, in_view: bool = false) -> Dictionary:
	return _request(&"sit", [pid, table_id, in_view])


func request_stand(pid: int) -> Dictionary:
	return _request(&"stand", [pid])


func request_place_bet(pid: int, table_id: StringName, amount: int, choice: Dictionary = {}) -> Dictionary:
	return _request(&"place_bet", [pid, table_id, amount, choice])


func request_place_shared_roll(table_id: StringName, bets: Array) -> Dictionary:
	return _request(&"place_shared_roll", [table_id, bets])


func request_start_high_low(pid: int, table_id: StringName, bet: int) -> HighLowRun:
	return _request_round(&"start_high_low", [pid, table_id, bet]) as HighLowRun


func request_high_low_guess(pid: int, higher: bool, throw: bool = false) -> Dictionary:
	return _request(&"high_low_guess", [pid, higher, throw])


func request_high_low_cash_out(pid: int) -> Dictionary:
	return _request(&"high_low_cash_out", [pid])


func request_start_blackjack(pid: int, table_id: StringName, bet: int) -> BlackjackRound:
	return _request_round(&"start_blackjack", [pid, table_id, bet]) as BlackjackRound


func request_blackjack_hit(pid: int) -> Dictionary:
	return _request(&"blackjack_hit", [pid])


func request_blackjack_stand(pid: int) -> Dictionary:
	return _request(&"blackjack_stand", [pid])


func request_enter_zone(pid: int, zone: int, area_id: StringName) -> Dictionary:
	return _request(&"enter_zone", [pid, zone, area_id])


func request_set_player_flags(pid: int, flags: Dictionary) -> Dictionary:
	return _request(&"set_player_flags", [pid, flags])


func request_report_seen(pid: int, ctx: Dictionary = {}) -> Dictionary:
	return _request(&"report_seen", [pid, ctx])


func request_change_to_stash(pid: int, index: int) -> Dictionary:
	return _request(&"change_to_stash", [pid, index])


func request_change_outfit(pid: int, outfit: Variant) -> Dictionary:
	# Objects never go over the wire: a client sends the outfit's dict.
	var look: Variant = outfit
	if role == Role.CLIENT and outfit is Outfit:
		look = (outfit as Outfit).to_dict()
	return _request(&"change_outfit", [pid, look])


func request_buy_outfit_piece(pid: int, slot: int, piece_id: StringName) -> Dictionary:
	return _request(&"buy_outfit_piece", [pid, slot, piece_id])


func request_steal_outfit_piece(pid: int) -> Dictionary:
	return _request(&"steal_outfit_piece", [pid])


func request_buy_id(pid: int, grade: int) -> Dictionary:
	return _request(&"buy_id", [pid, grade])


func request_swap_id(pid: int, index: int) -> Dictionary:
	return _request(&"swap_id", [pid, index])


func request_start_id_check(pid: int, guard_id: int = -1) -> Dictionary:
	return _request(&"start_id_check", [pid, guard_id])


func request_answer_id_check(pid: int, option_index: int) -> Dictionary:
	return _request(&"answer_id_check", [pid, option_index])


func request_expire_id_check(pid: int) -> Dictionary:
	return _request(&"expire_id_check", [pid])


func request_tear_poster(pid: int, poster_id: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return _request(&"tear_poster", [pid, poster_id, position])


func request_deface_poster(pid: int, poster_id: int, slot: int = -1) -> Dictionary:
	return _request(&"deface_poster", [pid, poster_id, slot])


func request_caught(pid: int, guard_id: int = -1) -> Dictionary:
	return _request(&"caught", [pid, guard_id])


func request_freed(pid: int, tackler_pid: int = 0) -> Dictionary:
	return _request(&"freed", [pid, tackler_pid])


func request_reach_back_room(pid: int) -> Dictionary:
	return _request(&"reach_back_room", [pid])


func request_cash_out(pid: int, amount: int) -> Dictionary:
	return _request(&"cash_out", [pid, amount])


func request_withdraw(pid: int, amount: int) -> Dictionary:
	return _request(&"withdraw", [pid, amount])


func request_distraction(pid: int, kind: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return _request(&"distraction", [pid, kind, position])


func request_give_chips(from_pid: int, to_pid: int, amount: int) -> Dictionary:
	return _request(&"give_chips", [from_pid, to_pid, amount])


func request_try_climb() -> Dictionary:
	return _request(&"try_climb", [])


# --- Request plumbing -----------------------------------------------------------

func _request(request: StringName, args: Array) -> Dictionary:
	if role == Role.CLIENT:
		var refused: Dictionary = {}
		if not CLIENT_REQUESTS.has(request):
			refused = _fail(HOST_ONLY)
		elif not _send_request(request, args):
			refused = _fail(NOT_CONNECTED)
		if not refused.is_empty():
			request_done.emit(request, args, refused)
			return refused
		return {"ok": true, "reason": PENDING}
	if _is_shared_bet(request, args):
		var queued := _queue_shared_bet(local_pid, -1, args)
		if not queued.is_empty():
			request_done.emit(request, args, queued)
			return queued
		return {"ok": true, "reason": PENDING}
	var res := _run(request, args)
	request_done.emit(request, args, res)
	return res


func _request_round(request: StringName, args: Array) -> Object:
	if role == Role.CLIENT:
		if not _send_request(request, args):
			request_done.emit(request, args, _fail(NOT_CONNECTED))
		return null
	if sim == null:
		request_done.emit(request, args, _no_sim())
		return null
	var round_obj: Object = sim.callv(request, args)
	request_done.emit(request, args, {"ok": round_obj != null, "reason": FloorSim.NO_REASON if round_obj != null else sim.last_reason})
	return round_obj


## Runs a request on the sim (host and offline). Round starts answer {ok, reason}.
func _run(request: StringName, args: Array) -> Dictionary:
	if sim == null:
		return _no_sim()
	match request:
		&"start_high_low", &"start_blackjack":
			var round_obj: Object = sim.callv(request, args)
			return {"ok": round_obj != null, "reason": FloorSim.NO_REASON if round_obj != null else sim.last_reason}
		&"register_table":
			var t: Object = sim.callv(request, args)
			return {"ok": t != null, "reason": FloorSim.NO_REASON}
	var res: Variant = sim.callv(request, args)
	return res if res is Dictionary else _fail(UNKNOWN_REQUEST)


## Checks a client's request: known, client-allowed, the right argument count
## and wire types, and the sender's own pid. -> {ok, reason, args} with the
## arguments converted to the request's types (String -> StringName, whole
## floats -> int).
static func check_request(sender: int, request: StringName, args: Array) -> Dictionary:
	if not REQUEST_ARGS.has(request):
		return _fail(UNKNOWN_REQUEST)
	if not CLIENT_REQUESTS.has(request):
		return _fail(HOST_ONLY)
	var types: Array = REQUEST_ARGS[request]
	if args.size() != types.size():
		return _fail(BAD_ARGS)
	var clean: Array = []
	for i in types.size():
		var converted: Array = _coerce(args[i], int(types[i]))
		if not bool(converted[0]):
			return _fail(BAD_ARGS)
		clean.append(converted[1])
	var pid_index: int = int(CLIENT_REQUESTS[request])
	if pid_index >= 0 and int(clean[pid_index]) != sender:
		return _fail(NOT_YOUR_PLAYER)
	return {"ok": true, "reason": FloorSim.NO_REASON, "args": clean}


## [ok, value]: `value` as wire type `type`, or [false, null].
static func _coerce(value: Variant, type: int) -> Array:
	match type:
		TYPE_INT:
			if value is int:
				return [true, value]
			if value is float and is_finite(value) and absf(value) < 2147483647.0 and is_equal_approx(value, roundf(value)):
				return [true, int(value)]
		TYPE_BOOL:
			if value is bool:
				return [true, value]
		TYPE_STRING_NAME:
			if (value is StringName or value is String) and String(value).length() <= MAX_NAME_LENGTH:
				return [true, StringName(value)]
		TYPE_VECTOR3:
			if value is Vector3 and (value as Vector3).is_finite():
				return [true, value]
		TYPE_DICTIONARY:
			if value is Dictionary:
				return [true, value]
		TYPE_ARRAY:
			if value is Array:
				return [true, value]
	return [false, null]


## Host: a client's request (`seq` is its id on that client). Returns the
## result, or {} when it was queued (a shared dice roll answers later).
## Public for tests; the RPC path calls it too.
func handle_remote_request(sender: int, request: StringName, args: Array, seq: int = -1) -> Dictionary:
	if role == Role.CLIENT:
		return _fail(HOST_ONLY)
	var checked := check_request(sender, request, args)
	var res: Dictionary
	if not bool(checked["ok"]):
		res = checked
	else:
		var clean: Array = checked["args"]
		var check: Callable = _validators.get(request, Callable())
		var why: StringName = FloorSim.NO_REASON
		if check.is_valid():
			why = StringName(str(check.call(sender, clean)))
		if why != FloorSim.NO_REASON:
			res = _fail(why)
		elif _is_shared_bet(request, clean):
			res = _queue_shared_bet(sender, seq, clean)
			if res.is_empty():
				return {}
		else:
			res = _run(request, clean)
	NetLog.line("request", {"from": sender, "name": request, "ok": bool(res.get("ok", false)), "reason": res.get("reason", &"")})
	return res


func _send_request(request: StringName, args: Array) -> bool:
	_seq += 1
	var seq := _seq
	# Registered first: a local transport may answer before _send returns.
	_pending[seq] = [request, args.duplicate()]
	if not _send(1, &"request", [seq, request, args]):
		_pending.erase(seq)
		return false
	return true


# --- Shared dice rolls (host) ------------------------------------------------------

func _is_shared_bet(request: StringName, args: Array) -> bool:
	if role != Role.HOST or request != &"place_bet" or sim == null or args.size() < 2:
		return false
	var table_id := StringName(str(args[1]))
	var t := sim.table(table_id)
	if t == null or t.game_type != HR.GameType.DICE:
		return false
	return _rolls.has(table_id) or t.seated_players().size() >= 2


## Adds a bet to the table's open roll (opening it). {} = queued; otherwise
## the bet was refused at once.
func _queue_shared_bet(requester: int, seq: int, args: Array) -> Dictionary:
	var pid: int = int(args[0])
	var table_id := StringName(str(args[1]))
	var roll: Dictionary = _rolls.get(table_id, {})
	if roll.is_empty():
		roll = {"left": SHARED_ROLL_SECONDS, "bets": [], "waiting": []}
		_rolls[table_id] = roll
	for b: Dictionary in roll["bets"]:
		if int(b["pid"]) == pid:
			return _fail(FloorSim.IN_ROUND)
	var choice: Dictionary = args[3] if args.size() > 3 and args[3] is Dictionary else {}
	var bet := {"pid": pid, "bet": int(args[2]), "throw": bool(choice.get("throw", false))}
	if choice.has("call"):
		bet["call"] = choice["call"]
	(roll["bets"] as Array).append(bet)
	(roll["waiting"] as Array).append([requester, seq, args])
	_emit_world_event(&"shared_roll", {"table_id": table_id, "open": true, "seconds": float(roll["left"]), "pids": _roll_pids(roll)})
	return {}


func _tick_shared_rolls(delta: float) -> void:
	for table_id: StringName in _rolls.keys():
		var roll: Dictionary = _rolls[table_id]
		roll["left"] = float(roll["left"]) - delta
		var t := sim.table(table_id) if sim != null else null
		var everyone_in: bool = t != null and (roll["bets"] as Array).size() >= t.seated_players().size()
		if float(roll["left"]) <= 0.0 or everyone_in:
			_resolve_shared_roll(table_id)


func _resolve_shared_roll(table_id: StringName) -> void:
	var roll: Dictionary = _rolls[table_id]
	_rolls.erase(table_id)
	var res: Dictionary = sim.place_shared_roll(table_id, roll["bets"]) if sim != null else _no_sim()
	var results: Dictionary = res.get("results", {})
	var rejected: Dictionary = res.get("rejected", {})
	_emit_world_event(&"shared_roll", {"table_id": table_id, "open": false, "seconds": 0.0, "pids": _roll_pids(roll)})
	for w: Array in roll["waiting"]:
		var args: Array = w[2]
		var pid: int = int(args[0])
		var out: Dictionary
		if results.has(pid):
			var ps: PlayerState = sim.player(pid) if sim != null else null
			out = {"ok": true, "reason": FloorSim.NO_REASON, "result": results[pid], "pocket": ps.wallet.pocket if ps != null else 0, "shared": true}
		else:
			out = _fail(StringName(str(rejected.get(pid, res.get("reason", FloorSim.NO_BETS)))))
		if int(w[1]) >= 0:
			NetLog.line("request", {"from": int(w[0]), "name": &"place_bet", "ok": bool(out["ok"]), "reason": out["reason"], "shared": true})
		_answer(int(w[0]), int(w[1]), &"place_bet", args, out)


func _roll_pids(roll: Dictionary) -> Array:
	var out: Array = []
	for b: Dictionary in roll["bets"]:
		out.append(int(b["pid"]))
	return out


## Answers a request: request_done for this peer's own, a reply otherwise.
func _answer(requester: int, seq: int, request: StringName, args: Array, result: Dictionary) -> void:
	if requester == local_pid and seq < 0:
		request_done.emit(request, args, result)
	else:
		_reply(requester, seq, result)


func _cancel_shared_rolls() -> void:
	var rolls := _rolls
	_rolls = {}
	for table_id: StringName in rolls:
		for w: Array in (rolls[table_id] as Dictionary)["waiting"]:
			_answer(int(w[0]), int(w[1]), &"place_bet", w[2], _fail(FloorSim.FINISHED))


# --- Events and snapshots -----------------------------------------------------------

func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if role == Role.HOST:
		_queue_event(kind, data)
	_log_event(kind, data)
	sim_event.emit(kind, data)


## A world-layer event (player_left, shared_roll) emitted like a sim event.
func _emit_world_event(kind: StringName, data: Dictionary) -> void:
	_on_sim_event(kind, data)


func _queue_event(kind: StringName, data: Dictionary) -> void:
	if not _has_audience():
		return
	if kind == &"heat":
		var pid: int = int(data.get("pid", 0))
		if PASSIVE_HEAT.has(StringName(str(data.get("reason", "")))):
			var merged: Dictionary = data.duplicate()
			var prev: Dictionary = _passive.get(pid, {})
			merged["delta"] = float(data.get("delta", 0.0)) + float(prev.get("delta", 0.0))
			_passive[pid] = merged
			return
		_flush_passive(pid)
	_event_serial += 1
	_outbox.append([kind, data])


func _flush_passive(pid: int) -> void:
	if not _passive.has(pid):
		return
	_event_serial += 1
	_outbox.append([&"heat", _passive[pid]])
	_passive.erase(pid)


func _flush_events() -> void:
	if role != Role.HOST or _outbox.is_empty():
		return
	var batch := _outbox
	_outbox = []
	_send(0, &"events", [_event_serial, batch])


func _reply(peer: int, seq: int, result: Dictionary) -> void:
	_flush_events()
	_send(peer, &"reply", [seq, result])


func _log_event(kind: StringName, data: Dictionary) -> void:
	if not NetLog.enabled:
		return
	if kind == &"heat" and PASSIVE_HEAT.has(StringName(str(data.get("reason", "")))):
		return
	var fields := {"kind": kind}
	for key: Variant in data:
		var v: Variant = data[key]
		if v is int or v is float or v is bool or v is String or v is StringName:
			fields[key] = v
	if kind == &"bet":
		var result: Dictionary = data.get("result", {})
		fields["won"] = bool(result.get("won", false))
		fields["bet"] = int(result.get("bet", 0))
	NetLog.line("event", fields)


static func _pack(value: Variant) -> Array:
	var raw := var_to_bytes(value)
	return [raw.size(), raw.compress(FileAccess.COMPRESSION_ZSTD)]


## The value packed by _pack, or null if it doesn't decode.
static func _unpack(packed: Variant) -> Variant:
	if not (packed is Array) or (packed as Array).size() != 2:
		return null
	var size: int = int(packed[0])
	var bytes: Variant = packed[1]
	if size <= 0 or size > 16 * 1024 * 1024 or not (bytes is PackedByteArray):
		return null
	var raw: PackedByteArray = (bytes as PackedByteArray).decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size:
		return null
	return bytes_to_var(raw)


# --- Receiving (client and host) --------------------------------------------------

## Delivers one network message from peer `from_peer` (the RPC stubs and test
## transports call this). Malformed messages are dropped.
func receive(from_peer: int, method: StringName, args: Array) -> void:
	match method:
		&"request":
			if role != Role.HOST or args.size() != 3:
				return
			var request: StringName = StringName(str(args[1])) if (args[1] is String or args[1] is StringName) else &""
			var req_args: Array = args[2] if args[2] is Array else []
			var res := handle_remote_request(from_peer, request, req_args, int(args[0]) if args[0] is int else -1)
			if not res.is_empty():
				_reply(from_peer, int(args[0]) if args[0] is int else -1, res)
		&"reply":
			if role != Role.CLIENT or args.size() != 2 or not (args[1] is Dictionary):
				return
			var entry: Variant = _pending.get(args[0])
			_pending.erase(args[0])
			if entry is Array:
				request_done.emit(entry[0], entry[1], args[1])
		&"events":
			if role == Role.CLIENT and args.size() == 2 and args[1] is Array:
				_on_events(int(args[0]), args[1])
		&"snapshot":
			if role == Role.CLIENT and args.size() == 2:
				_on_snapshot(int(args[0]), args[1])
		&"visit":
			if role == Role.CLIENT and args.size() == 2 and args[0] is Dictionary:
				_on_visit(args[0], args[1])
		&"world", &"world_fast":
			if args.size() != 3 or not (args[2] is Dictionary) or not (args[1] is String or args[1] is StringName):
				return
			if int(args[0]) != visit_token():
				return
			world_message.emit(StringName(args[1]), args[2], from_peer)


func _on_events(last_serial: int, batch: Array) -> void:
	var first: int = last_serial - batch.size() + 1
	for i in batch.size():
		var e: Variant = batch[i]
		if not (e is Array) or (e as Array).size() != 2 or not (e[1] is Dictionary):
			continue
		var kind := StringName(str(e[0]))
		var data: Dictionary = e[1]
		var serial: int = first + i
		if serial > _snap_serial:
			_patch(kind, data)
		_applied_serial = maxi(_applied_serial, serial)
		_log_event(kind, data)
		sim_event.emit(kind, data)


func _on_snapshot(serial: int, packed: Variant) -> void:
	if serial < _applied_serial:
		return
	var snap: Variant = _unpack(packed)
	if not (snap is Dictionary):
		return
	_cache = snap
	_snap_serial = serial
	snapshot_received.emit()


func _on_visit(info: Dictionary, packed: Variant) -> void:
	var snap: Variant = _unpack(packed)
	_visit_info = info
	_cache = snap if snap is Dictionary else {}
	_snap_serial = int(info.get("serial", _applied_serial))
	_applied_serial = maxi(_applied_serial, _snap_serial)
	_hands.clear()
	NetLog.line("visit", {"token": int(info.get("token", 0)), "rung": int(info.get("rung", 0)), "map_seed": int(info.get("map_seed", 0))})
	visit_started.emit(null)


## Keeps the cached snapshot current between snapshots.
func _patch(kind: StringName, data: Dictionary) -> void:
	var players: Dictionary = _cache.get("players", {})
	var run_d: Dictionary = _cache.get("run", {})
	var tables: Dictionary = _cache.get("tables", {})
	var pid: int = int(data.get("pid", 0))
	var p: Dictionary = players.get(pid, {})
	match kind:
		&"status":
			p["status"] = int(data.get("status", 0))
		&"heat":
			p["heat"] = float(data.get("value", 0.0))
			p["level"] = int(data.get("level", 0))
		&"chips":
			p["pocket"] = int(data.get("pocket", 0))
		&"zone":
			p["zone"] = int(data.get("zone", 0))
			p["area_id"] = StringName(str(data.get("area_id", "")))
		&"seated":
			var table_id := StringName(str(data.get("table_id", "")))
			p["table_id"] = table_id
			var t: Dictionary = tables.get(table_id, {})
			if not t.is_empty() and not (t.get("seated", []) as Array).has(pid):
				(t["seated"] as Array).append(pid)
		&"stood":
			var table_id := StringName(str(data.get("table_id", "")))
			p["table_id"] = &""
			p["round"] = &""
			_hands.erase(pid)
			var t: Dictionary = tables.get(table_id, {})
			if not t.is_empty():
				(t.get("seated", []) as Array).erase(pid)
		&"outfit":
			p["outfit"] = data.get("outfit", {})
			p["stash"] = data.get("stash", [])
			p["stash_size"] = (p["stash"] as Array).size()
		&"id":
			p["id"] = data.get("id", {})
			p["id_index"] = int(data.get("index", -1))
			p["id_count"] = int(data.get("count", 0))
		&"hand":
			var state: Dictionary = data.get("state", {})
			p["round"] = StringName(str(state.get("kind", "")))
			_hands[pid] = state.duplicate(true)
		&"bet":
			if bool(data.get("round_over", true)):
				p["round"] = &""
				_hands.erase(pid)
			p["pocket"] = int(data.get("pocket", p.get("pocket", 0)))
		&"id_check":
			p["id_check"] = data.get("question", {})
		&"id_result":
			p["id_check"] = {}
		&"poster":
			if StringName(str(data.get("casino_id", ""))) == StringName(str(run_d.get("casino_id", ""))):
				(_cache.get("posters", []) as Array).append(data.get("poster", {}))
		&"poster_removed":
			_drop_poster(int(data.get("poster_id", -1)))
		&"poster_defaced":
			var posters: Array = _cache.get("posters", [])
			for i in posters.size():
				if int((posters[i] as Dictionary).get("id", -2)) == int(data.get("poster_id", -1)):
					posters[i] = data.get("poster", posters[i])
		&"fire_alarm":
			_cache["fire_alarm"] = bool(data.get("active", false))
			_cache["fire_alarm_seconds"] = float(data.get("seconds", 0.0)) if bool(data.get("active", false)) else 0.0
		&"forger_moved":
			_cache["forger_location"] = StringName(str(data.get("location", "")))
		&"banked":
			run_d["bank"] = int(data.get("bank", run_d.get("bank", 0)))
			run_d["top_banked"] = int(data.get("top_banked", run_d.get("top_banked", 0)))
		&"withdrawn":
			run_d["bank"] = int(data.get("bank", run_d.get("bank", 0)))
		&"strike":
			run_d["strikes"] = int(data.get("strikes", run_d.get("strikes", 0)))
		&"player_left":
			players.erase(pid)


func _drop_poster(poster_id: int) -> void:
	var posters: Array = _cache.get("posters", [])
	for i in range(posters.size() - 1, -1, -1):
		if int((posters[i] as Dictionary).get("id", -2)) == poster_id:
			posters.remove_at(i)


# --- Transport ------------------------------------------------------------------------

func _connected() -> bool:
	if not is_inside_tree() or not multiplayer.has_multiplayer_peer():
		return false
	var peer := multiplayer.multiplayer_peer
	return not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _has_audience() -> bool:
	if role != Role.HOST:
		return false
	if transport.is_valid():
		return true
	return _connected() and not multiplayer.get_peers().is_empty()


## Sends `method` with `args` to peer `to` (0 = every other peer). False if
## there is no connection.
func _send(to: int, method: StringName, args: Array) -> bool:
	if transport.is_valid():
		transport.call(to, method, args)
		return true
	if not _connected():
		return false
	if to != 0 and not multiplayer.get_peers().has(to):
		return false
	match method:
		&"request":
			_rpc_request.rpc_id(1, args[0], args[1], args[2])
		&"reply":
			_rpc_reply.rpc_id(to, args[0], args[1])
		&"events":
			_rpc_events.rpc(args[0], args[1])
		&"snapshot":
			_rpc_snapshot.rpc(args[0], args[1])
		&"visit":
			_rpc_visit.rpc(args[0], args[1])
		&"world":
			if to == 0:
				_rpc_world.rpc(args[0], args[1], args[2])
			else:
				_rpc_world.rpc_id(to, args[0], args[1], args[2])
		&"world_fast":
			if to == 0:
				_rpc_world_fast.rpc(args[0], args[1], args[2])
			else:
				_rpc_world_fast.rpc_id(to, args[0], args[1], args[2])
		_:
			return false
	return true


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request(seq: Variant, request: Variant, args: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"request", [seq, request, args])


@rpc("authority", "call_remote", "reliable")
func _rpc_reply(seq: Variant, result: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"reply", [seq, result])


@rpc("authority", "call_remote", "reliable")
func _rpc_events(last_serial: Variant, batch: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"events", [last_serial, batch])


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(serial: Variant, packed: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"snapshot", [serial, packed])


@rpc("authority", "call_remote", "reliable")
func _rpc_visit(info: Variant, packed: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"visit", [info, packed])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_world(token: Variant, kind: Variant, data: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"world", [token, kind, data])


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_world_fast(token: Variant, kind: Variant, data: Variant) -> void:
	receive(multiplayer.get_remote_sender_id(), &"world_fast", [token, kind, data])


# --- Internals ----------------------------------------------------------------

func _visit_seed() -> int:
	return hash([_seed, run.visits, run.rung])


func _drop_sim() -> void:
	if sim != null and sim.event.is_connected(_on_sim_event):
		sim.event.disconnect(_on_sim_event)
	if not _rolls.is_empty():
		_cancel_shared_rolls()
	sim = null


static func _no_sim() -> Dictionary:
	return {"ok": false, "reason": NO_SIM}


static func _fail(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason}
