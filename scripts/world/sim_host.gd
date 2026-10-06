class_name SimHost
extends Node
## Owns the run (RunState) and the current visit's FloorSim, ticks the sim in
## _physics_process and re-emits every FloorSim event as `sim_event`. World
## and UI code send requests only through the request_* methods, which take
## the same arguments and return the same values as the FloorSim request of
## the same name. This is the phase-2 RPC boundary: later these become RPCs to
## the host and sim_event is broadcast back.
##
## Without a current visit every request_* returns {ok: false, reason:
## &"no_sim"} (request_start_* return null, request_register_table null).

signal sim_event(kind: StringName, data: Dictionary)
## A new FloorSim is live (players added, no tables yet; the director registers them).
signal visit_started(sim: FloorSim)

const NO_SIM := &"no_sim"

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

var run: RunState = null
var sim: FloorSim = null
## While true the sim is not ticked (pause menu).
var paused: bool = false
## pid -> display name of the crew.
var player_names: Dictionary = {}

var _seed: int = 0


## Starts a new run. The first visit starts with start_visit().
func start_run(start_rung: int, seed_value: int, names: Dictionary) -> void:
	_drop_sim()
	run = RunState.new(start_rung)
	_seed = seed_value
	player_names = names.duplicate()
	paused = false


## Starts a visit at the run's current casino: a new FloorSim that carries the
## crew's PlayerStates over from the previous visit (new players are added
## from player_names). Starts a default run (top rung, 1 player) if none.
func start_visit() -> FloorSim:
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
	visit_started.emit(next)
	return next


func current_sim() -> FloorSim:
	return sim


## FloorSim.snapshot() of the current visit, or {"run": RunState.to_dict()}
## (or {}) when there is no visit.
func snapshot() -> Dictionary:
	if sim != null:
		return sim.snapshot()
	if run != null:
		return {"run": run.to_dict()}
	return {}


func _physics_process(delta: float) -> void:
	if paused or sim == null or sim.finished:
		return
	sim.tick(delta)


# --- Requests (same args and returns as FloorSim) ---------------------------

func request_register_table(id: StringName, game_type: int, area_id: StringName, position: Vector3 = Vector3.ZERO) -> TableState:
	return sim.register_table(id, game_type, area_id, position) if sim != null else null


func request_sit(pid: int, table_id: StringName, in_view: bool = false) -> Dictionary:
	return sim.sit(pid, table_id, in_view) if sim != null else _no_sim()


func request_stand(pid: int) -> Dictionary:
	return sim.stand(pid) if sim != null else _no_sim()


func request_place_bet(pid: int, table_id: StringName, amount: int, choice: Dictionary = {}) -> Dictionary:
	return sim.place_bet(pid, table_id, amount, choice) if sim != null else _no_sim()


func request_place_shared_roll(table_id: StringName, bets: Array) -> Dictionary:
	return sim.place_shared_roll(table_id, bets) if sim != null else _no_sim()


func request_start_high_low(pid: int, table_id: StringName, bet: int) -> HighLowRun:
	return sim.start_high_low(pid, table_id, bet) if sim != null else null


func request_high_low_guess(pid: int, higher: bool, throw: bool = false) -> Dictionary:
	return sim.high_low_guess(pid, higher, throw) if sim != null else _no_sim()


func request_high_low_cash_out(pid: int) -> Dictionary:
	return sim.high_low_cash_out(pid) if sim != null else _no_sim()


func request_start_blackjack(pid: int, table_id: StringName, bet: int) -> BlackjackRound:
	return sim.start_blackjack(pid, table_id, bet) if sim != null else null


func request_blackjack_hit(pid: int) -> Dictionary:
	return sim.blackjack_hit(pid) if sim != null else _no_sim()


func request_blackjack_stand(pid: int) -> Dictionary:
	return sim.blackjack_stand(pid) if sim != null else _no_sim()


func request_enter_zone(pid: int, zone: int, area_id: StringName) -> Dictionary:
	return sim.enter_zone(pid, zone, area_id) if sim != null else _no_sim()


func request_set_player_flags(pid: int, flags: Dictionary) -> Dictionary:
	return sim.set_player_flags(pid, flags) if sim != null else _no_sim()


func request_report_seen(pid: int, ctx: Dictionary = {}) -> Dictionary:
	return sim.report_seen(pid, ctx) if sim != null else _no_sim()


func request_change_to_stash(pid: int, index: int) -> Dictionary:
	return sim.change_to_stash(pid, index) if sim != null else _no_sim()


func request_change_outfit(pid: int, outfit: Variant) -> Dictionary:
	return sim.change_outfit(pid, outfit) if sim != null else _no_sim()


func request_buy_outfit_piece(pid: int, slot: int, piece_id: StringName) -> Dictionary:
	return sim.buy_outfit_piece(pid, slot, piece_id) if sim != null else _no_sim()


func request_steal_outfit_piece(pid: int) -> Dictionary:
	return sim.steal_outfit_piece(pid) if sim != null else _no_sim()


func request_buy_id(pid: int, grade: int) -> Dictionary:
	return sim.buy_id(pid, grade) if sim != null else _no_sim()


func request_swap_id(pid: int, index: int) -> Dictionary:
	return sim.swap_id(pid, index) if sim != null else _no_sim()


func request_start_id_check(pid: int, guard_id: int = -1) -> Dictionary:
	return sim.start_id_check(pid, guard_id) if sim != null else _no_sim()


func request_answer_id_check(pid: int, option_index: int) -> Dictionary:
	return sim.answer_id_check(pid, option_index) if sim != null else _no_sim()


func request_expire_id_check(pid: int) -> Dictionary:
	return sim.expire_id_check(pid) if sim != null else _no_sim()


func request_tear_poster(pid: int, poster_id: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return sim.tear_poster(pid, poster_id, position) if sim != null else _no_sim()


func request_deface_poster(pid: int, poster_id: int, slot: int = -1) -> Dictionary:
	return sim.deface_poster(pid, poster_id, slot) if sim != null else _no_sim()


func request_caught(pid: int, guard_id: int = -1) -> Dictionary:
	return sim.caught(pid, guard_id) if sim != null else _no_sim()


func request_freed(pid: int, tackler_pid: int = 0) -> Dictionary:
	return sim.freed(pid, tackler_pid) if sim != null else _no_sim()


func request_reach_back_room(pid: int) -> Dictionary:
	return sim.reach_back_room(pid) if sim != null else _no_sim()


func request_cash_out(pid: int, amount: int) -> Dictionary:
	return sim.cash_out(pid, amount) if sim != null else _no_sim()


func request_withdraw(pid: int, amount: int) -> Dictionary:
	return sim.withdraw(pid, amount) if sim != null else _no_sim()


func request_distraction(pid: int, kind: int, position: Vector3 = Vector3.ZERO) -> Dictionary:
	return sim.distraction(pid, kind, position) if sim != null else _no_sim()


func request_give_chips(from_pid: int, to_pid: int, amount: int) -> Dictionary:
	return sim.give_chips(from_pid, to_pid, amount) if sim != null else _no_sim()


func request_try_climb() -> Dictionary:
	return sim.try_climb() if sim != null else _no_sim()


# --- Internals ----------------------------------------------------------------

func _visit_seed() -> int:
	return hash([_seed, run.visits, run.rung])


func _drop_sim() -> void:
	if sim != null and sim.event.is_connected(_on_sim_event):
		sim.event.disconnect(_on_sim_event)
	sim = null


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	sim_event.emit(kind, data)


static func _no_sim() -> Dictionary:
	return {"ok": false, "reason": NO_SIM}
