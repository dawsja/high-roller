class_name Autopilot
extends Node
## A bot that plays the real game end to end, for soak tests and the
## `--autopilot` command line flag (scripts/main.gd). It drives the local
## PlayerCharacter only through its input actions (Input.action_press on the
## move, run, interact and jump actions) and the UI panels through the same
## methods their buttons and keys call (BetPanel.press_main, IdQuizPanel.answer,
## CashierPanel.cash_out / withdraw, WardrobePanel.wear, ForgerPanel.buy,
## VisitBanner.handle_key). It
## never sends SimHost requests itself. To decide, it reads the sim and the
## director's nodes the way a player reads the screen (Heat, pocket, the ID
## card, where the tables are).
##
## Policy, every visit: walk the navmesh to a table, sit and bet; on a dealer
## swap (Watched) leave for a table in another game area; at Suspected cool
## off at the bar, buffet or restroom (or, `greed` of the time, press on to
## `greed_heat` first); at Wanted change into a stash outfit in the restroom
## first; bank winnings at the cashier, and take chips back out of the crew
## bank when broke; buy a solid ID from the forger when playing under a cheap
## one; answer ID quizzes from the card in use; struggle while carried; once
## the bank covers the buy-in and `min_play_seconds` of the visit have passed,
## walk to the exit and climb. It never uses the exit at the top rung (that
## ends the run) unless `leave_top_when_broke`.
##
## Everything notable goes into `timeline` (echoed to stdout with `echo`).
## `stats` counts it up, `heat_samples` holds Heat over time and `anomalies`
## lists watchdog hits: stuck walking, panels left open, ID checks that never
## resolve, a player stuck seated / carried / hidden, guards that never give
## up, a HUD out of sync with the sim, visits that don't transition.
##
## Usage: add it under main.gd's node, then setup(main). It follows every
## visit main starts (main.visit_begun).

## Every timeline line, as it is logged.
signal logged(line: String)

enum Goal { NONE, TABLE, CASHIER, COOL, CHANGE, EXIT, FORGER }
const GOAL_NAMES: Array[String] = ["none", "table", "cashier", "cool off", "change outfit", "exit", "forger"]

const LOCAL_PID := 1
const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
## A waypoint counts as reached this close (flat metres).
const WAYPOINT_REACH := 0.35
## Path re-planned this often while walking.
const REPATH_SECONDS := 1.0
## Walking makes less than this much progress toward the goal in STUCK_SECONDS: stuck.
const STUCK_PROGRESS := 0.3
const STUCK_SECONDS := 3.0
## Stuck this many times on one goal: give it up (and log an anomaly).
const STUCK_GIVE_UP := 4
## How far from an interactable the bot walks straight at it instead of along the path.
const APPROACH_RANGE := 1.8
## Seconds of walking straight at an interactable before giving up on it.
const APPROACH_SECONDS := 3.0
## Interact presses are at least this far apart.
const TAP_COOLDOWN := 0.6
## Heat the bot cools down to before it goes back to the tables.
const COOL_TARGET := Tuning.WATCHED_AT - 5.0
## A cashier trip needs at least this many max bets of winnings in the pocket
## (fewer at the top, where every banked chip is score).
const CASH_STEP_BETS := 6
const TOP_CASH_STEP_BETS := 3
## Pocket the bot keeps for betting after a cash-out, in max bets.
const RESERVE_BETS := 6
## The visit banner is dismissed (Space) after this long.
const BANNER_SECONDS := 1.0
## Watchdog thresholds (sim seconds).
const WATCH_MISMATCH_SECONDS := 1.5
const WATCH_CARRIED_SECONDS := 90.0
const WATCH_CHECK_ID_SECONDS := 25.0
const WATCH_CHASE_SECONDS := 60.0
const WATCH_TRANSITION_SECONDS := 20.0
const WATCH_INPUT_SECONDS := 3.0

# --- Options (set before setup) -------------------------------------------------

## Print every timeline line to stdout.
var echo: bool = false
## Sim seconds of the visit to play before heading for the exit (with the buy-in banked).
var min_play_seconds: float = 90.0
## Walk out and climb when the bank allows (never at the top rung).
var climb: bool = true
## At the top rung, broke with nothing in the bank: walk out (ends the run).
var leave_top_when_broke: bool = false
## Share of the casino's max bet to stake (also capped at a quarter of the pocket).
var bet_share: float = 0.6
## Chance a bet is thrown on purpose (lose on purpose) while Watched.
var throw_chance: float = 0.08
## Chance, per Suspected episode, of pressing on at the table until `greed_heat`
## instead of cooling off at once (a guard then has time to walk over).
var greed: float = 0.5
var greed_heat: float = 72.0
## Seconds the bot "reads" an ID question before answering.
var reaction_seconds: float = 1.0
## Chance of answering an ID question correctly.
var quiz_accuracy: float = 1.0
## Heat and status are sampled this often (sim seconds).
var sample_seconds: float = 5.0
## Quit the game (print the summary first) after this many sim seconds; 0 = never.
var quit_after_seconds: float = 0.0
var rng := RandomNumberGenerator.new()

# --- State (read-only outside) --------------------------------------------------

var main: Node
var host: SimHost
var director: CasinoDirector
var hud: Hud
var bet_panel: BetPanel
var quiz_panel: IdQuizPanel
var cashier_panel: CashierPanel
var wardrobe_panel: WardrobePanel
var forger_panel: ForgerPanel
var visit_banner: VisitBanner

var timeline: Array[String] = []
## {t, heat, level, status, pocket, bank, rung} every sample_seconds.
var heat_samples: Array[Dictionary] = []
var anomalies: Array[String] = []
var stats: Dictionary = {}
## Sim seconds since setup (scaled physics time).
var sim_seconds: float = 0.0
var goal: int = Goal.NONE
var visits: int = 0

var _active: bool = false
var _held: Dictionary = {}
var _visit_t: float = 0.0
var _visit_start_pocket: int = 0
## Pocket after the last cashier trip (or visit start, or back room): winnings are counted from here.
var _pocket_mark: int = 0
var _sample_left: float = 0.0
# Goal and walking.
var _target_it: Interactable
var _target_pos: Vector3 = Vector3.ZERO
var _path: PackedVector3Array = PackedVector3Array()
var _path_i: int = 0
var _repath_left: float = 0.0
var _best_dist: float = INF
var _best_t: float = 0.0
var _stuck_count: int = 0
var _unstick_left: float = 0.0
var _unstick_dir: Vector3 = Vector3.ZERO
var _approach_t: float = 0.0
var _tap_left: float = 0.0
var _use_pending: float = -1.0
var _use_kind: StringName = &""
## Interactable instance id -> sim time until which it is avoided.
var _avoid: Dictionary = {}
# Tables.
var _last_table: StringName = &""
var _last_area: StringName = &""
var _cool_planned: bool = false
var _swap_table: StringName = &""
## area id -> sim time the dealer swapped on us there.
var _cooled_areas: Dictionary = {}
var _leave_left: float = 0.0
var _changed_this_episode: bool = false
## Rolled once per Suspected episode: keep playing up to greed_heat.
var _greedy: bool = false
var _greed_rolled: bool = false
var _cash_left: float = 0.0
var _exit_left: float = 0.0
var _forger_left: float = 0.0
var _run_over_logged: bool = false
# Quiz.
var _quiz: Dictionary = {}
var _quiz_t: float = 0.0
var _struggle_left: float = 0.0
var _banner_t: float = 0.0
# Watchdogs: key -> seconds the condition has held.
var _watch: Dictionary = {}
var _reported: Dictionary = {}
var _finished_at: float = -1.0
## guard id -> [state, since].
var _guard_since: Dictionary = {}
var _hud_seen: Array[String] = []
var _hud_left: float = 0.0


func _init() -> void:
	name = "Autopilot"
	process_physics_priority = -100
	rng.seed = 1234
	_reset_stats()


## Starts driving `main_node` (scripts/main.gd, already in the tree). Picks up
## the current visit, if any, and every later one.
func setup(main_node: Node) -> void:
	main = main_node
	host = main.get(&"host")
	hud = main.get(&"hud")
	bet_panel = main.get(&"bet_panel")
	quiz_panel = main.get(&"quiz_panel")
	cashier_panel = main.get(&"cashier_panel")
	wardrobe_panel = main.get(&"wardrobe_panel")
	forger_panel = main.get(&"forger_panel")
	visit_banner = main.get(&"visit_banner")
	host.sim_event.connect(_on_sim_event)
	if main.has_signal(&"visit_begun"):
		main.connect(&"visit_begun", _on_visit_begun)
	_active = true
	var d: Variant = main.get(&"director")
	if d is CasinoDirector:
		_on_visit_begun(d)


## Stops driving and lets go of every input action.
func stop() -> void:
	_active = false
	_release_all()


func _exit_tree() -> void:
	_release_all()
	if host != null and host.sim_event.is_connected(_on_sim_event):
		host.sim_event.disconnect(_on_sim_event)


## A multi-line report: counters, Heat milestones and anomalies.
func summary() -> String:
	var lines: PackedStringArray = []
	lines.append("AUTOPILOT SUMMARY after %.0f sim s, %d visit(s), rungs %s" % [sim_seconds, visits, str(stats["rungs"])])
	lines.append("  bets %d (won %d, lost %d, thrown %d), wagered %d, net %+d" % [stats["bets"], stats["wins"], stats["losses"], stats["thrown"], stats["wagered"], stats["net"]])
	lines.append("  dealer swaps %d, tables sat %d, areas changed %d, cool-offs %d, outfit changes %d" % [stats["dealer_swaps"], stats["sits"], stats["area_changes"], stats["cool_offs"], stats["outfit_changes"]])
	lines.append("  banked %d in %d trip(s), withdrawn %d, IDs bought %d, climbs %d, thrown out %d, curbs %d" % [
		stats["banked"], stats["cash_outs"], stats["withdrawn"], stats["ids_bought"], stats["climbs"], stats["thrown_out"], stats["curbs"]])
	lines.append("  guard engagements %d (ID walk-overs %d, chases %d), ID checks %d (passed %d, failed %d), catches %d, freed %d, strikes %d" % [
		stats["engagements"], stats["check_walks"], stats["chases"], stats["id_checks"], stats["id_passed"], stats["id_failed"], stats["catches"], stats["frees"], stats["strikes"]])
	lines.append("  max Heat %.1f; first Watched %s, Suspected %s, Wanted %s; stuck %d" % [
		stats["max_heat"], _when(stats["first_watched"]), _when(stats["first_suspected"]), _when(stats["first_wanted"]), stats["stuck"]])
	lines.append("  Heat from wins %+.1f, passive %+.1f, cool-offs %+.1f, other %+.1f" % [stats["heat_win"], stats["heat_passive"], stats["heat_cool"], stats["heat_other"]])
	lines.append("  anomalies %d%s" % [anomalies.size(), "" if anomalies.is_empty() else ": " + "; ".join(anomalies)])
	return "\n".join(lines)


func _when(t: float) -> String:
	return "never" if t < 0.0 else "%.0fs" % t


func _reset_stats() -> void:
	stats = {
		"bets": 0, "wins": 0, "losses": 0, "thrown": 0, "wagered": 0, "net": 0,
		"dealer_swaps": 0, "sits": 0, "area_changes": 0, "cool_offs": 0, "outfit_changes": 0,
		"banked": 0, "cash_outs": 0, "climbs": 0, "thrown_out": 0, "curbs": 0,
		"engagements": 0, "check_walks": 0, "chases": 0, "id_checks": 0, "id_passed": 0, "id_failed": 0,
		"catches": 0, "frees": 0, "strikes": 0, "detained": 0,
		"max_heat": 0.0, "first_watched": -1.0, "first_suspected": -1.0, "first_wanted": -1.0,
		"stuck": 0, "rungs": [], "posters": 0, "ids_bought": 0, "withdrawn": 0,
		"heat_win": 0.0, "heat_passive": 0.0, "heat_cool": 0.0, "heat_other": 0.0,
	}


# --- Frame ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_release_taps()
	if not _active or host == null:
		return
	sim_seconds += delta
	if quit_after_seconds > 0.0 and sim_seconds >= quit_after_seconds:
		_quit()
		return
	_tap_left -= delta
	_cash_left -= delta
	_exit_left -= delta
	_forger_left -= delta
	_handle_banner(delta)
	if _finished_at >= 0.0 and sim_seconds - _finished_at > WATCH_TRANSITION_SECONDS and not _reported.has("no_transition"):
		_reported["no_transition"] = true
		_anomaly("no_transition", "the visit ended %.0f s ago but no new visit started" % (sim_seconds - _finished_at))
	if director == null or not is_instance_valid(director) or not director.is_inside_tree():
		_stop_moving()
		return
	_visit_t += delta
	var ps := _ps()
	if ps == null:
		return
	_sample(ps, delta)
	_watchdogs(ps, delta)
	_read_hud(delta)
	if director.finished:
		_stop_moving()
		if director.outcome == CasinoDirector.OUTCOME_RUN_OVER and not _run_over_logged:
			_run_over_logged = true
			_log("RUN OVER: score %d" % host.run.score())
		return
	if not director.npcs_active:
		_stop_moving()
		return
	match ps.status:
		HR.PlayerStatus.CARRIED:
			_stop_moving()
			_struggle_left -= delta
			if _struggle_left <= 0.0:
				_struggle_left = 0.25
				_tap(&"jump")
			return
		HR.PlayerStatus.DETAINED, HR.PlayerStatus.ON_CURB:
			_stop_moving()
			_set_goal(Goal.NONE, "held")
			return
		HR.PlayerStatus.ID_CHECK:
			_stop_moving()
			_answer_quiz(delta)
			return
	if bet_panel.is_open():
		_stop_moving()
		_play_table(ps, delta)
		return
	if cashier_panel.is_open():
		_stop_moving()
		_use_cashier(ps)
		return
	if wardrobe_panel.is_open():
		_stop_moving()
		_use_wardrobe(ps)
		return
	if forger_panel.is_open():
		_stop_moving()
		_use_forger(ps)
		return
	if ps.status == HR.PlayerStatus.SEATED:
		# Seated without the bet panel (shouldn't happen): stand up with Jump.
		_stop_moving()
		if _tap_left <= 0.0:
			_tap_left = TAP_COOLDOWN
			_tap(&"jump")
		return
	if not director.player.is_input_enabled():
		_stop_moving()
		return
	_choose_goal(ps)
	_pursue(ps, delta)


func _quit() -> void:
	_active = false
	_release_all()
	_log("quit after %.0f sim s" % sim_seconds)
	print(summary())
	get_tree().quit(0 if anomalies.is_empty() else 2)


# --- Decisions --------------------------------------------------------------------

func _choose_goal(ps: PlayerState) -> void:
	var level := ps.heat.level()
	var heat := ps.heat.value
	if level >= HR.HeatLevel.WANTED and not _changed_this_episode and _best_stash_index(ps) >= 0:
		_set_goal(Goal.CHANGE, "Wanted at %.0f Heat: change outfit" % heat)
		return
	if goal == Goal.CHANGE and not _changed_this_episode and heat >= Tuning.SUSPECTED_AT:
		return
	if level >= HR.HeatLevel.SUSPECTED or (goal == Goal.COOL and heat > COOL_TARGET):
		_set_goal(Goal.COOL, "%s at %.0f Heat: cool off" % [HeatMeter.level_name(level), heat])
		return
	if heat < Tuning.SUSPECTED_AT:
		_changed_this_episode = false
		_greed_rolled = false
	if _wants_cash(ps):
		_set_goal(Goal.CASHIER, "bank %d" % _cash_amount(ps))
		return
	if _wants_withdraw(ps):
		_set_goal(Goal.CASHIER, "broke: take chips out of the bank (%d)" % host.run.bank)
		return
	if _wants_forger(ps):
		_set_goal(Goal.FORGER, "playing under a %s card: buy a solid one" % ps.current_id().grade_name() if ps.current_id() != null else "no card")
		return
	if _wants_exit():
		_set_goal(Goal.EXIT, "buy-in banked (%d): climb" % host.run.bank)
		return
	if leave_top_when_broke and host.run.is_top() and ps.wallet.pocket < _min_bet() and host.run.bank < _min_bet():
		_set_goal(Goal.EXIT, "broke at the top: walk out")
		return
	if ps.wallet.pocket < _min_bet():
		if goal != Goal.NONE:
			_set_goal(Goal.NONE, "broke: pocket %d under the %d min bet, bank %d" % [ps.wallet.pocket, _min_bet(), host.run.bank])
		return
	_set_goal(Goal.TABLE, "play")


func _set_goal(g: int, why: String) -> void:
	if g == goal:
		return
	goal = g
	_target_it = null
	_path = PackedVector3Array()
	_stuck_count = 0
	_best_dist = INF
	_best_t = sim_seconds
	_approach_t = 0.0
	_use_pending = -1.0
	_cool_planned = false
	if g == Goal.COOL:
		stats["cool_offs"] += 1
	_log("goal -> %s (%s)" % [GOAL_NAMES[g], why])


func _wants_cash(ps: PlayerState) -> bool:
	if _cash_left > 0.0 or ps.zone == HR.ZoneType.EXIT:
		return false
	var id := ps.current_id()
	if id == null or not id.passes_check() or id.remaining_cap() <= 0:
		return false
	var amount := _cash_amount(ps)
	if amount <= 0:
		return false
	var step: int = (TOP_CASH_STEP_BETS if host.run.is_top() else CASH_STEP_BETS) * _max_bet()
	if ps.wallet.pocket - _pocket_mark >= step:
		return true
	# Before climbing, bank what the buy-in still needs (if the reserve allows).
	if climb and not host.run.is_top() and _visit_t >= min_play_seconds and not host.run.can_climb():
		return amount >= CasinoLadder.buy_in_to_leave(host.run.rung) - host.run.bank
	return false


## Chips to bank now: everything above the reserve, within the ID's cap.
func _cash_amount(ps: PlayerState) -> int:
	var amount: int = ps.wallet.pocket - RESERVE_BETS * _max_bet()
	var id := ps.current_id()
	if id != null:
		amount = mini(amount, id.remaining_cap())
	return maxi(0, amount)


## Broke (can't cover the min bet) with chips in the crew bank.
func _wants_withdraw(ps: PlayerState) -> bool:
	return _cash_left <= 0.0 and ps.wallet.pocket < _min_bet() and host.run.bank >= _min_bet()


## On a cheap (or no usable) card with chips to spare for a solid one.
func _wants_forger(ps: PlayerState) -> bool:
	if _forger_left > 0.0 or director.forger_interactable == null:
		return false
	var id := ps.current_id()
	if id != null and id.passes_check() and id.grade != HR.IdGrade.CHEAP:
		return false
	return ps.wallet.pocket >= IdGenerator.price(HR.IdGrade.SOLID) + 2 * _max_bet()


func _wants_exit() -> bool:
	if not climb or host.run.is_top() or not host.run.can_climb() or _exit_left > 0.0:
		return false
	return _visit_t >= min_play_seconds


func _min_bet() -> int:
	return int(director.casino.get("min_bet", 1))


func _max_bet() -> int:
	return int(director.casino.get("max_bet", 1))


# --- Walking to a goal ------------------------------------------------------------

func _pursue(ps: PlayerState, delta: float) -> void:
	if _use_pending >= 0.0:
		_use_pending += delta
		if _use_pending > 1.5:
			_log("using %s did nothing" % _use_kind)
			_avoid_target(20.0)
			_use_pending = -1.0
			_target_it = null
	match goal:
		Goal.TABLE:
			if _target_it == null:
				_target_it = _pick_table(ps)
				if _target_it == null:
					_stop_moving()
					return
				_start_walk(_target_it.global_position)
			_walk_to_interactable(delta)
		Goal.CASHIER:
			if _target_it == null:
				_target_it = _nearest_interactable(&"cashier")
				if _target_it == null:
					_cash_left = 30.0
					return
				_start_walk(_target_it.global_position)
			_walk_to_interactable(delta)
		Goal.CHANGE:
			if _target_it == null:
				_target_it = _nearest_interactable(&"restroom")
				if _target_it == null:
					_changed_this_episode = true
					return
				_start_walk(_target_it.global_position)
			_walk_to_interactable(delta)
		Goal.FORGER:
			if _target_it == null:
				_target_it = director.forger_interactable
				_start_walk(_target_it.global_position)
			elif _target_pos.distance_to(_target_it.global_position) > 1.0:
				_start_walk(_target_it.global_position)  # he moved
			_walk_to_interactable(delta)
		Goal.EXIT:
			if _target_it == null:
				_target_it = _nearest_interactable(&"exit")
				if _target_it == null:
					_exit_left = 60.0
					return
				_start_walk(_target_it.global_position)
			_walk_to_interactable(delta)
		Goal.COOL:
			if not _cool_planned:
				_cool_planned = true
				_target_pos = _cool_spot(ps)
				_start_walk(_target_pos)
			if HeatRules.is_off_table_zone(ps.zone) and _flat(director.player.global_position, _target_pos) < 1.5:
				_stop_moving()
				return
			_walk(delta, _target_pos, _chased())
		_:
			_stop_moving()


func _start_walk(to: Vector3) -> void:
	_target_pos = to
	_plan_path(to)
	_best_dist = INF
	_best_t = sim_seconds
	_approach_t = 0.0


func _plan_path(to: Vector3) -> void:
	_repath_left = REPATH_SECONDS
	_path_i = 0
	var map: RID = director.map.navigation_map()
	var from := director.player.global_position
	var end := _floor_point(to)
	_path = NavigationServer3D.map_get_path(map, from, end, true)
	if _path.is_empty():
		_path = PackedVector3Array([end])


## The navmesh point nearest the floor under `p`.
func _floor_point(p: Vector3) -> Vector3:
	var map: RID = director.map.navigation_map()
	var q := NavigationServer3D.map_get_closest_point(map, Vector3(p.x, director.map.global_position.y, p.z))
	return q if q != Vector3.ZERO or p == Vector3.ZERO else p


## Walks along the path to `to`; returns the flat distance left.
func _walk(delta: float, to: Vector3, run: bool) -> float:
	var player := director.player
	var pos := player.global_position
	var dist := _flat(pos, to)
	if _unstick_left > 0.0:
		_unstick_left -= delta
		_steer(_unstick_dir, false)
		if _unstick_left <= 0.0:
			_plan_path(to)
		return dist
	_repath_left -= delta
	if _repath_left <= 0.0:
		_plan_path(to)
	while _path_i < _path.size() and _flat(pos, _path[_path_i]) < WAYPOINT_REACH:
		_path_i += 1
	var next: Vector3 = _path[_path_i] if _path_i < _path.size() else to
	_steer(next - pos, run)
	# Progress watchdog.
	if dist < _best_dist - STUCK_PROGRESS:
		_best_dist = dist
		_best_t = sim_seconds
	elif sim_seconds - _best_t > STUCK_SECONDS:
		_stuck_count += 1
		stats["stuck"] += 1
		_best_t = sim_seconds
		_best_dist = dist
		var side := Vector3(-(next - pos).z, 0.0, (next - pos).x).normalized()
		_unstick_dir = (side * (1.0 if rng.randf() < 0.5 else -1.0) - (next - pos).normalized() * 0.5).normalized()
		_unstick_left = 0.6
		var hit := player.get_last_slide_collision()
		var blocker: String = str((hit.get_collider() as Node).name) if hit != null and hit.get_collider() is Node else "nothing"
		_log("stuck walking to %s at %s (%d), next waypoint %s, bumping %s" % [_goal_text(), _v(pos), _stuck_count, _v(next), blocker])
		if _stuck_count >= STUCK_GIVE_UP:
			_anomaly("stuck:%s" % _goal_text(), "stuck walking to %s near %s" % [_goal_text(), _v(pos)])
			_avoid_target(30.0)
			_target_it = null
			_stuck_count = 0
	return dist


## Walks to _target_it and presses interact once the player's sensor has it.
func _walk_to_interactable(delta: float) -> void:
	var it := _target_it
	if it == null or not is_instance_valid(it) or not it.enabled:
		_target_it = null
		return
	var player := director.player
	if player.current_interactable() == it:
		_stop_moving()
		if _tap_left <= 0.0 and _use_pending < 0.0:
			_tap_left = TAP_COOLDOWN
			_tap(&"interact")
			_use_pending = 0.0
			_use_kind = it.kind
		return
	var pos := player.global_position
	var d_it := _flat(pos, it.global_position)
	var end_dist := _flat(pos, _path[_path.size() - 1]) if not _path.is_empty() else d_it
	if d_it < APPROACH_RANGE and (end_dist < 0.6 or d_it < 1.0):
		_approach_t += delta
		_steer(it.global_position - pos, false)
		if _approach_t > APPROACH_SECONDS:
			_anomaly("focus:%s" % it.kind, "never got %s (%s) in reach from %s" % [it.kind, it.name, _v(pos)])
			_avoid_target(30.0)
			_target_it = null
		return
	_walk(delta, _target_pos, _chased())


func _avoid_target(seconds: float) -> void:
	if _target_it != null and is_instance_valid(_target_it):
		_avoid[_target_it.get_instance_id()] = sim_seconds + seconds


func _avoided(it: Interactable) -> bool:
	return sim_seconds < float(_avoid.get(it.get_instance_id(), -INF))


func _goal_text() -> String:
	if _target_it != null and is_instance_valid(_target_it):
		var label: String = str(_target_it.data.get("table_id", _target_it.kind))
		return "%s %s" % [GOAL_NAMES[goal], label]
	return GOAL_NAMES[goal]


## True while a guard chases the local player (the bot runs then).
func _chased() -> bool:
	for g: GuardNPC in director.guards:
		if g.get_state() == HR.GuardState.CHASE and g.brain.target_pid == LOCAL_PID:
			return true
	return false


func _pick_table(ps: PlayerState) -> Interactable:
	var sim := host.current_sim()
	var here: Vector3 = director.player.global_position
	var best: Interactable = null
	var best_score := INF
	for t: TableNode in director.tables.values():
		var it := t.interactable
		if it == null or not it.enabled or _avoided(it):
			continue
		var state: TableState = sim.table(t.table_id)
		if state == null or state.closed:
			continue
		if t.game_type == HR.GameType.SLOTS:
			continue
		if t.table_id == _last_table:
			continue
		var cooled_at: float = float(_cooled_areas.get(t.area_id, -INF))
		var score: float = _flat(here, it.global_position) + rng.randf_range(0.0, 6.0)
		if sim_seconds - cooled_at < 60.0:
			score += 100.0
		if t.area_id == ps.last_game_area and _swap_table != &"":
			score += 40.0
		if score < best_score:
			best_score = score
			best = it
	if best != null:
		_log("heading for %s (%s)" % [str(best.data.get("table_id", "")), _area_of(best)])
	return best


func _area_of(it: Interactable) -> String:
	var t: TableNode = director.tables.get(StringName(str(it.data.get("table_id", ""))))
	return String(t.area_id) if t != null else "?"


func _nearest_interactable(kind: StringName) -> Interactable:
	var here: Vector3 = director.player.global_position
	var best: Interactable = null
	var best_d := INF
	var list: Array[Interactable] = director.map.interactables_of(kind)
	if kind == &"forger" and director.forger_interactable != null:
		list = [director.forger_interactable]
	for it: Interactable in list:
		if not it.enabled or _avoided(it):
			continue
		var d := _flat(here, it.global_position)
		if d < best_d:
			best_d = d
			best = it
	return best


## A spot to cool off: the nearest bar, buffet or restroom (Wanted: the restroom).
func _cool_spot(ps: PlayerState) -> Vector3:
	var here: Vector3 = director.player.global_position
	var types: Array[int] = [HR.ZoneType.BAR, HR.ZoneType.BUFFET, HR.ZoneType.RESTROOM]
	if ps.heat.level() >= HR.HeatLevel.WANTED:
		types = [HR.ZoneType.RESTROOM]
	var best := here
	var best_d := INF
	for type: int in types:
		for z: CasinoZone in director.map.zones_of_type(type):
			for r: Rect2 in z.rects():
				var c := director.map.to_global(Vector3(r.get_center().x, 0.0, r.get_center().y))
				var p := _floor_point(c)
				var d := _flat(here, p)
				if d < best_d:
					best_d = d
					best = p
	return best


# --- Panels -----------------------------------------------------------------------

func _play_table(ps: PlayerState, delta: float) -> void:
	_leave_left -= delta
	if ps.status != HR.PlayerStatus.SEATED:
		return
	var level := ps.heat.level()
	var round_state: Dictionary = bet_panel.round_state()
	var why := ""
	if _swap_table != &"" and _swap_table == ps.table_id:
		why = "dealer swapped"
	elif level >= HR.HeatLevel.SUSPECTED and not (_roll_greed() and ps.heat.value < greed_heat):
		why = "Suspected"
	elif _wants_cash(ps):
		why = "time to bank"
	elif _wants_exit():
		why = "time to climb"
	elif round_state.is_empty() and ps.wallet.pocket < _min_bet():
		why = "broke"
	elif host.current_sim().fire_alarm_active():
		why = "fire alarm"
	if why != "":
		if _leave_left <= 0.0:
			_leave_left = 1.0
			_log("leave %s: %s" % [ps.table_id, why])
			bet_panel.request_leave()
		return
	if bet_panel.is_locked():
		return
	match bet_panel.game_type:
		HR.GameType.BLACKJACK:
			if round_state.is_empty():
				_deal(ps, false)
			elif not bet_panel.choice_buttons[0].disabled:
				var total: int = int(round_state.get("player_total", 0))
				bet_panel.press_choice(0 if total < 12 or (total < 16 and rng.randf() < 0.4) else 1)
		HR.GameType.HIGH_LOW:
			if round_state.is_empty():
				_deal(ps, false)
			elif not bet_panel.choice_buttons[0].disabled:
				var streak: int = int(round_state.get("streak", 0))
				if streak >= 2 or (streak >= 1 and rng.randf() < 0.5):
					bet_panel.press_main()
				else:
					var card: int = int(round_state.get("card", 8))
					bet_panel.press_choice(0 if card <= 8 else 1)
		HR.GameType.ROULETTE:
			bet_panel.press_choice(rng.randi_range(0, 1) if rng.randf() < 0.9 else 2)
			_deal(ps, true)
		HR.GameType.DICE:
			bet_panel.press_choice(rng.randi_range(0, 1))
			_deal(ps, true)
		_:
			_deal(ps, true)


## Sizes the bet, maybe flips "throw it", and presses the main button.
## Once per Suspected episode: does the bot press on at the table?
func _roll_greed() -> bool:
	if not _greed_rolled:
		_greed_rolled = true
		_greedy = rng.randf() < greed
		if _greedy:
			_log("Suspected, but pressing on until %.0f Heat" % greed_heat)
	return _greedy


func _deal(ps: PlayerState, can_throw: bool) -> void:
	if bet_panel.main_button.disabled:
		return
	var max_bet := _max_bet()
	var amount := int(round(float(max_bet) * bet_share))
	amount = mini(amount, int(ps.wallet.pocket * 0.25))
	amount = clampi(amount, _min_bet(), mini(max_bet, ps.wallet.pocket))
	bet_panel.set_bet_amount(amount)
	var throw := can_throw and ps.heat.level() == HR.HeatLevel.WATCHED and rng.randf() < throw_chance
	if bet_panel.throw_toggle.visible:
		bet_panel.throw_toggle.button_pressed = throw
	bet_panel.press_main()


func _answer_quiz(delta: float) -> void:
	if not quiz_panel.is_waiting():
		return
	_quiz_t += delta
	if _quiz_t < reaction_seconds:
		return
	var options: Array = _quiz.get("options", [])
	if options.is_empty():
		return
	var ps := _ps()
	var truth := IdQuiz.answer_for(ps.current_id(), StringName(str(_quiz.get("field", ""))))
	var pick := options.find(truth)
	if pick < 0 or rng.randf() >= quiz_accuracy:
		pick = (maxi(pick, 0) + 1) % options.size()
	_log("answer the ID check (%s): %s" % [str(_quiz.get("field", "")), str(options[pick])])
	_quiz = {}
	quiz_panel.answer(pick)


func _use_cashier(ps: PlayerState) -> void:
	_use_pending = -1.0
	if _wants_withdraw(ps) and cashier_panel.withdraw_amount() > 0:
		var take := cashier_panel.withdraw_amount()
		var got: Dictionary = cashier_panel.withdraw(take)
		_log("withdraw %d from the bank: %s" % [take, "ok" if bool(got.get("ok", false)) else str(got.get("reason", ""))])
	var amount := _cash_amount(ps)
	if amount > 0:
		var res: Dictionary = cashier_panel.cash_out(amount)
		if not bool(res.get("ok", false)):
			_log("cashier refused %d: %s" % [amount, str(res.get("reason", ""))])
	_cash_left = 20.0
	_pocket_mark = ps.wallet.pocket
	cashier_panel.close()
	_set_goal(Goal.NONE, "done at the cashier")


func _use_forger(ps: PlayerState) -> void:
	_use_pending = -1.0
	_forger_left = 60.0
	if goal == Goal.FORGER:
		var res: Dictionary = forger_panel.buy(HR.IdGrade.SOLID)
		if bool(res.get("ok", false)):
			stats["ids_bought"] += 1
			_log("bought a solid ID: %s" % str((res.get("id", {}) as Dictionary).get("name", "")))
		else:
			_log("forger refused: %s" % str(res.get("reason", "")))
	forger_panel.close()
	_set_goal(Goal.NONE, "done at the forger")


func _use_wardrobe(ps: PlayerState) -> void:
	_use_pending = -1.0
	if wardrobe_panel.mode == WardrobePanel.MODE_RESTROOM and goal == Goal.CHANGE:
		var index := _best_stash_index(ps)
		if index >= 0:
			var res: Dictionary = wardrobe_panel.wear(index)
			if not bool(res.get("ok", false)):
				_log("restroom change failed: %s" % str(res.get("reason", "")))
		_changed_this_episode = true
	wardrobe_panel.close()
	_set_goal(Goal.COOL, "changed; cool off in here")


## The stash outfit that shares the fewest pieces with the worn look and any
## poster up here, or -1.
func _best_stash_index(ps: PlayerState) -> int:
	var best := -1
	var best_score := 99
	var posters: Array = host.current_sim().posters_here()
	for i in ps.stash.size():
		var o: Outfit = ps.stash[i]
		if o.is_staff_uniform():
			continue
		var score := o.matches(ps.outfit)
		for p: Dictionary in posters:
			if WantedPoster.from_dict(p).matches(o):
				score += 10
		if score < best_score:
			best_score = score
			best = i
	return best if best_score < Tuning.RECOGNIZE_MATCHES else -1


func _handle_banner(delta: float) -> void:
	if visit_banner == null or not visit_banner.is_open():
		_banner_t = 0.0
		return
	_banner_t += delta
	if _banner_t >= BANNER_SECONDS and visit_banner.kind != VisitBanner.KIND_SUMMARY:
		_log("dismiss the %s banner" % visit_banner.kind)
		visit_banner.handle_key(KEY_SPACE)
		_banner_t = 0.0


# --- Input ------------------------------------------------------------------------

## Presses the move actions so the camera-relative input points along `dir`.
func _steer(dir: Vector3, run: bool) -> void:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		_stop_moving()
		return
	var rig := director.player.camera_rig
	var basis := rig.flat_basis() if rig != null else Basis.IDENTITY
	var local := basis.inverse() * dir.normalized()
	_axis(&"move_right", &"move_left", local.x)
	_axis(&"move_back", &"move_forward", local.z)
	if run:
		Input.action_press(&"run")
	else:
		Input.action_release(&"run")


func _axis(positive: StringName, negative: StringName, value: float) -> void:
	if value > 0.01:
		Input.action_press(positive, minf(value, 1.0))
		Input.action_release(negative)
	elif value < -0.01:
		Input.action_press(negative, minf(-value, 1.0))
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


func _stop_moving() -> void:
	for a: StringName in MOVE_ACTIONS:
		if Input.is_action_pressed(a):
			Input.action_release(a)
	if Input.is_action_pressed(&"run"):
		Input.action_release(&"run")


## Presses an action for two physics frames (just_pressed fires on the next one).
func _tap(action: StringName) -> void:
	Input.action_press(action)
	_held[action] = 2


func _release_taps() -> void:
	for a: StringName in _held.keys():
		_held[a] = int(_held[a]) - 1
		if int(_held[a]) <= 0:
			Input.action_release(a)
			_held.erase(a)


func _release_all() -> void:
	for a: StringName in MOVE_ACTIONS + [&"run", &"jump", &"interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)
	_held.clear()


# --- Visits and events ----------------------------------------------------------------

func _on_visit_begun(d: CasinoDirector) -> void:
	if d == director:
		return
	director = d
	visits += 1
	_visit_t = 0.0
	_finished_at = -1.0
	goal = Goal.NONE
	_target_it = null
	_path = PackedVector3Array()
	_avoid.clear()
	_cooled_areas.clear()
	_reported.erase("no_transition")
	_last_area = &""
	_last_table = &""
	_swap_table = &""
	_changed_this_episode = false
	_cash_left = 0.0
	_exit_left = 0.0
	_forger_left = 0.0
	_guard_since.clear()
	var ps := _ps()
	_visit_start_pocket = ps.wallet.pocket if ps != null else 0
	_pocket_mark = _visit_start_pocket
	(stats["rungs"] as Array).append(d.rung)
	var p: Dictionary = d.plan
	_log("VISIT %d: %s (rung %d)%s  guards %d (floor %d, undercover %d, head %d, pit %d), cameras %d, patrons %d  pocket %d bank %d buy-in %d" % [
		visits, str(d.casino.get("name", "")), d.rung, " practice" if d.practice else "",
		d.guards.size(), int(p.get("floor", 0)), int(p.get("undercover", 0)), int(p.get("head", 0)), int(p.get("pit_boss", 0)),
		d.cameras.size(), d.crowd.patron_count() if d.crowd != null else 0,
		_visit_start_pocket, host.run.bank, CasinoLadder.buy_in_to_leave(d.rung)])
	for g: GuardNPC in d.guards:
		g.state_changed.connect(_on_guard_state)


func _on_guard_state(g: GuardNPC, old_state: int, new_state: int) -> void:
	_guard_since[g.guard_id] = sim_seconds
	var target: int = g.brain.target_pid
	_log("G%d %s: %s -> %s%s" % [g.guard_id, str(CasinoDirector.SECURITY_NAMES.get(g.security_type, "?")),
		GuardBrain.name_of(old_state), g.brain.state_name(), " (you)" if target == LOCAL_PID else ""])
	if target == LOCAL_PID and new_state in [HR.GuardState.CHECK_ID, HR.GuardState.CHASE]:
		stats["engagements"] += 1
		if new_state == HR.GuardState.CHASE:
			stats["chases"] += 1
		else:
			stats["check_walks"] += 1


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if not _active:
		return
	var pid: int = int(data.get("pid", 0))
	var mine := pid == LOCAL_PID
	match kind:
		&"bet":
			if not mine:
				return
			var r: Dictionary = data.get("result", {})
			if not bool(data.get("round_over", true)):
				return
			stats["bets"] += 1
			stats["wagered"] += int(r.get("bet", 0))
			stats["net"] += int(r.get("net", 0))
			if bool(r.get("intentional_loss", false)):
				stats["thrown"] += 1
			if bool(r.get("won", false)):
				stats["wins"] += 1
			else:
				stats["losses"] += 1
			_log("bet %d at %s: %s %+d (Heat %+.1f, streak %d) pocket %d" % [int(r.get("bet", 0)), str(data.get("table_id", "")),
				"WIN" if bool(r.get("won", false)) else ("THROWN" if bool(r.get("intentional_loss", false)) else "loss"),
				int(r.get("net", 0)), float(r.get("heat", 0.0)), int(r.get("streak", 0)), int(data.get("pocket", 0))])
		&"seated":
			if mine:
				stats["sits"] += 1
				_last_table = StringName(str(data.get("table_id", "")))
				if _last_table != _swap_table:
					_swap_table = &""
				_use_pending = -1.0
				_log("sat at %s" % _last_table)
		&"stood":
			if mine:
				_log("stood up from %s" % str(data.get("table_id", "")))
				_set_goal(Goal.NONE, "stood up")
		&"heat":
			if mine:
				var v: float = float(data.get("value", 0.0))
				stats["max_heat"] = maxf(float(stats["max_heat"]), v)
				var d: float = float(data.get("delta", 0.0))
				var reason: StringName = StringName(str(data.get("reason", "")))
				if reason in [HeatRules.WIN, HeatRules.STREAK, HeatRules.SHARED_ROLL]:
					stats["heat_win"] += d
				elif UiTheme.is_passive_heat(reason):
					stats["heat_passive"] += d
				elif d < 0.0:
					stats["heat_cool"] += d
				else:
					stats["heat_other"] += d
				if not UiTheme.is_passive_heat(reason) and absf(d) >= 0.5 and reason not in [HeatRules.WIN, HeatRules.SHARED_ROLL]:
					_log("Heat %+.1f %s -> %.1f" % [d, reason, v])
		&"level":
			if mine:
				var new_level: int = int(data.get("new", 0))
				_log("LEVEL %s -> %s" % [HeatMeter.level_name(int(data.get("old", 0))), HeatMeter.level_name(new_level)])
				var key: String = ["", "first_watched", "first_suspected", "first_wanted"][new_level]
				if key != "" and float(stats[key]) < 0.0:
					stats[key] = sim_seconds
		&"dealer_swap":
			if mine:
				stats["dealer_swaps"] += 1
				_swap_table = StringName(str(data.get("table_id", "")))
				var t: TableNode = director.tables.get(_swap_table) if director != null else null
				if t != null:
					_cooled_areas[t.area_id] = sim_seconds
				_log("DEALER SWAP at %s" % _swap_table)
		&"zone":
			if mine:
				var area: StringName = StringName(str(data.get("area_id", "")))
				var zone: int = int(data.get("zone", 0))
				if (zone == HR.ZoneType.TABLES or zone == HR.ZoneType.SLOTS) and area != _last_area and _last_area != &"":
					stats["area_changes"] += 1
				if zone == HR.ZoneType.TABLES or zone == HR.ZoneType.SLOTS:
					_last_area = area
		&"look_recorded":
			if mine:
				_log("look recorded")
		&"poster":
			if mine:
				stats["posters"] += 1
				_log("WANTED poster printed")
		&"poster_match":
			if mine:
				_log("poster match (guard %d)" % int(data.get("guard_id", -1)))
		&"id_check":
			if mine:
				stats["id_checks"] += 1
				_quiz = (data.get("question", {}) as Dictionary).duplicate(true)
				_quiz_t = 0.0
				if bool(data.get("auto_fail", false)):
					_log("ID CHECK by guard %d: auto fail (%s)" % [int(data.get("guard_id", -1)), str(data.get("fail_reason", ""))])
				else:
					_log("ID CHECK by guard %d: \"%s\"" % [int(data.get("guard_id", -1)), str(_quiz.get("prompt", ""))])
		&"id_result":
			if mine:
				if bool(data.get("passed", false)):
					stats["id_passed"] += 1
				else:
					stats["id_failed"] += 1
				_log("ID result: %s (%s)" % ["passed" if bool(data.get("passed", false)) else "FAILED", str(data.get("reason", ""))])
		&"caught":
			if mine:
				stats["catches"] += 1
				_log("CAUGHT by guard %d (pocket %d)" % [int(data.get("guard_id", -1)), _ps().wallet.pocket if _ps() != null else 0])
		&"freed":
			if mine:
				stats["frees"] += 1
				_log("freed (tackler %d)" % int(data.get("tackler", 0)))
		&"detained":
			if mine:
				stats["detained"] += 1
				_pocket_mark = 0
				_log("DETAINED: lost %d chips, ID burned: %s" % [int(data.get("chips_lost", 0)), str(data.get("id_name", ""))])
		&"strike":
			stats["strikes"] += 1
			_log("STRIKE %d/%d" % [int(data.get("strikes", 0)), int(data.get("max", 0))])
		&"rejoined":
			if mine:
				_log("rejoined from %s" % str(data.get("from", "")))
		&"curb":
			stats["curbs"] += 1
			_log("CURB for %.0f s" % float(data.get("seconds", 0.0)))
		&"banked":
			if mine:
				stats["banked"] += int(data.get("amount", 0))
				stats["cash_outs"] += 1
				_log("BANKED %d under %s (bank %d, top %d)" % [int(data.get("amount", 0)), str(data.get("id_name", "")), int(data.get("bank", 0)), int(data.get("top_banked", 0))])
		&"outfit":
			if mine and bool(data.get("worn_changed", false)):
				stats["outfit_changes"] += 1
				_log("changed outfit (%s)" % str(data.get("reason", "")))
		&"thrown_out":
			stats["thrown_out"] += 1
			_finished_at = sim_seconds
			_log("THROWN OUT: rung %d -> %d (%s)" % [int(data.get("from", 0)), int(data.get("to", 0)), str(data.get("cause", ""))])
		&"climbed":
			stats["climbs"] += 1
			_finished_at = sim_seconds
			_log("CLIMBED: rung %d -> %d (cost %d)" % [int(data.get("from", 0)), int(data.get("to", 0)), int(data.get("cost", 0))])
		&"withdrawn":
			if mine:
				stats["withdrawn"] += int(data.get("amount", 0))
		&"notify":
			if pid == 0 or mine:
				_log("notify: %s" % str(data.get("text", "")))
		&"fire_alarm":
			_log("fire alarm %s" % ("ON" if bool(data.get("active", false)) else "off"))


# --- Samples and watchdogs ------------------------------------------------------------

func _sample(ps: PlayerState, delta: float) -> void:
	_sample_left -= delta
	if _sample_left > 0.0:
		return
	_sample_left = sample_seconds
	var s := {
		"t": snappedf(sim_seconds, 0.1), "heat": snappedf(ps.heat.value, 0.1), "level": ps.heat.level(),
		"status": ps.status, "pocket": ps.wallet.pocket, "bank": host.run.bank, "rung": host.run.rung,
	}
	heat_samples.append(s)
	var guards: PackedStringArray = []
	for g: GuardNPC in director.guards:
		if g.security_type != HR.SecurityType.PIT_BOSS:
			guards.append("%d:%s" % [g.guard_id, g.brain.debug_label])
	_log("~ Heat %5.1f %-9s %-8s pocket %d bank %d zone %s goal %s | %s" % [ps.heat.value, HeatMeter.level_name(ps.heat.level()),
		UiTheme.status_name(ps.status), ps.wallet.pocket, host.run.bank, _zone_name(ps.zone), GOAL_NAMES[goal], " ".join(guards)])


## Logs new HUD feed lines (what the player is told, e.g. why a climb failed).
func _read_hud(delta: float) -> void:
	_hud_left -= delta
	if hud == null or _hud_left > 0.0:
		return
	_hud_left = 0.2
	var texts: Array[String] = hud.notification_texts()
	for i in range(texts.size() - 1, -1, -1):
		if not _hud_seen.has(texts[i]):
			_log("hud: %s" % texts[i])
	_hud_seen = texts


func _zone_name(zone: int) -> String:
	var key: Variant = HR.ZoneType.find_key(zone)
	return str(key).to_lower() if key != null else "?"


func _watchdogs(ps: PlayerState, delta: float) -> void:
	var node: PlayerCharacter = director.player
	if node == null:
		return
	var status := ps.status
	_hold("seated_node", status == HR.PlayerStatus.SEATED and node.state != PlayerCharacter.STATE_SEATED, delta,
		"sim says SEATED but the player node is %s" % node.state)
	_hold("free_node", status == HR.PlayerStatus.FREE and node.state != PlayerCharacter.STATE_FREE and not director.finished, delta,
		"sim says FREE but the player node is %s" % node.state)
	_hold("carried_node", status == HR.PlayerStatus.CARRIED and node.state != PlayerCharacter.STATE_CARRIED, delta,
		"sim says CARRIED but the player node is %s" % node.state)
	_hold("hidden_node", (status == HR.PlayerStatus.DETAINED) and not node.is_hidden(), delta,
		"sim says DETAINED but the player node is visible")
	_hold("carried_long", status == HR.PlayerStatus.CARRIED, delta, "carried for over %.0f s" % WATCH_CARRIED_SECONDS, WATCH_CARRIED_SECONDS)
	_hold("id_check_long", status == HR.PlayerStatus.ID_CHECK, delta, "ID check never resolved",
		Tuning.ID_QUIZ_SECONDS + Tuning.ID_QUIZ_GRACE_SECONDS + 1.0)
	_hold("quiz_open", quiz_panel.is_waiting() and status != HR.PlayerStatus.ID_CHECK, delta, "the ID quiz is waiting with no check in the sim")
	_hold("bet_open", bet_panel.is_open() and status != HR.PlayerStatus.SEATED and status != HR.PlayerStatus.ID_CHECK, delta,
		"the bet panel is open while %s" % UiTheme.status_name(status))
	_hold("modal_open", (cashier_panel.is_open() or wardrobe_panel.is_open()) and status != HR.PlayerStatus.FREE, delta,
		"a modal panel is open while %s" % UiTheme.status_name(status))
	var panels_closed := not bet_panel.is_open() and not cashier_panel.is_open() and not wardrobe_panel.is_open() \
		and not forger_panel.is_open() and not quiz_panel.is_waiting()
	_hold("input_off", status == HR.PlayerStatus.FREE and panels_closed and not node.is_input_enabled() and not director.finished \
		and not director.input_blocked, delta, "player input stuck off while free", WATCH_INPUT_SECONDS)
	if hud != null:
		_hold("hud_heat", absf(hud.heat_value() - ps.heat.value) > 2.0, delta,
			"HUD Heat %.1f vs sim %.1f" % [hud.heat_value(), ps.heat.value])
	for g: GuardNPC in director.guards:
		var since: float = float(_guard_since.get(g.guard_id, sim_seconds))
		var held: float = sim_seconds - since
		var state := g.get_state()
		_hold("check_long_%d" % g.guard_id, state == HR.GuardState.CHECK_ID and held > WATCH_CHECK_ID_SECONDS, delta,
			"G%d stuck in CHECK_ID for %.0f s" % [g.guard_id, held], 0.0)
		_hold("chase_long_%d" % g.guard_id, state == HR.GuardState.CHASE and held > WATCH_CHASE_SECONDS, delta,
			"G%d chasing for %.0f s" % [g.guard_id, held], 0.0)


## Logs an anomaly once the condition has held for `limit` seconds (once per episode).
func _hold(key: String, cond: bool, delta: float, text: String, limit: float = WATCH_MISMATCH_SECONDS) -> void:
	if not cond:
		_watch.erase(key)
		_reported.erase(key)
		return
	_watch[key] = float(_watch.get(key, 0.0)) + delta
	if float(_watch[key]) >= limit and not _reported.has(key):
		_reported[key] = true
		_anomaly(key, text)


func _anomaly(key: String, text: String) -> void:
	var line := "ANOMALY [%s] %s" % [key, text]
	if anomalies.size() < 50:
		anomalies.append("%.0fs %s" % [sim_seconds, text])
	_log(line)


# --- Helpers ----------------------------------------------------------------------------

func _ps() -> PlayerState:
	var sim := host.current_sim() if host != null else null
	return sim.player(LOCAL_PID) if sim != null else null


func _log(text: String) -> void:
	var line := "[%6.1f] %s" % [sim_seconds, text]
	timeline.append(line)
	if echo:
		print(line)
	logged.emit(line)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _v(p: Vector3) -> String:
	return "(%.1f, %.1f)" % [p.x, p.z]
