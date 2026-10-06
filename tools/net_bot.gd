class_name NetBot
extends Node
## A scripted co-op test bot (`--net-bot`, tools/net_test.sh). It plays this
## peer's own player through input actions and the UI panels (like the
## Autopilot), never through SimHost requests, and logs `NET ... bot` lines.
##
## Script, on the first visit (practice at Sal's):
## - every client: walk to the nearest single-shot table, sit and bet until a
##   win (at most MAX_BETS), leave; walk to the cashier and bank the pocket.
## - the first client (the "runner") then waits to be made Wanted by the host
##   bot (a test shortcut: Heat raised in the host's sim), walks up to the
##   guard to get grabbed, rides to the back room and rejoins.
## - everyone then walks onto the exit pad and presses interact until the
##   crew climbs (the host tops the bank up to the buy-in if the clients'
##   banking fell short: another test shortcut).
## After the next visit has run for QUIT_AFTER_VISIT seconds every peer quits
## (clients first). ID checks are answered from the card in use.

enum Step { WAIT, TABLE, BET, CASHIER, BANK, WANTED, CARRIED, EXIT, DONE }
const STEP_NAMES: Array[String] = ["wait", "table", "bet", "cashier", "bank", "wanted", "carried", "exit", "done"]

const MOVE_ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right"]
const WAYPOINT_REACH := 0.4
const REPATH_SECONDS := 1.0
const STUCK_SECONDS := 6.0
const MAX_BETS := 8
const TAP_COOLDOWN := 0.7
## Real seconds on the next visit before quitting (clients one after another
## by pid order, the host last).
const QUIT_AFTER_VISIT := 4.0
const QUIT_STAGGER := 0.8
## Give a step up after this long (sim seconds) and move on.
const STEP_TIMEOUT := 90.0

var main: Node
var host: SimHost
var director: CasinoDirector
var step: int = Step.WAIT
var visits: int = 0
var bets: int = 0
var won: bool = false

var _held: Dictionary = {}
var _tap_left: float = 0.0
var _step_t: float = 0.0
var _path: PackedVector3Array = PackedVector3Array()
var _path_i: int = 0
var _repath_left: float = 0.0
var _goal: Vector3 = Vector3.ZERO
var _target: Interactable
var _best_dist: float = INF
var _best_t: float = 0.0
var _quiz: Dictionary = {}
var _quiz_t: float = 0.0
var _banner_t: float = 0.0
var _visit_started_msec: int = 0
var _runner_heated: bool = false
## Host: the runner came back from the back room.
var _runner_rejoined: bool = false
var _rejoined: bool = false
var _caught: bool = false
var _banked: bool = false
var _topped_up: bool = false
var _quit_called: bool = false


func setup(main_node: Node) -> void:
	main = main_node
	host = main.get(&"host")
	host.sim_event.connect(_on_sim_event)
	host.request_done.connect(_on_request_done)
	main.connect(&"visit_begun", _on_visit_begun)


## Final line for the test harness.
func report() -> void:
	_log("report", {"step": STEP_NAMES[step], "visits": visits, "bets": bets, "won": won, "caught": _caught, "rejoined": _rejoined, "banked": _banked})


func _exit_tree() -> void:
	_release_all()


# --- Frame ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_release_taps()
	_tap_left -= delta
	_handle_banner(delta)
	if director == null or not is_instance_valid(director) or not director.is_inside_tree():
		_stop_moving()
		return
	if visits >= 2:
		_stop_moving()
		var order: int = host.player_ids().find(host.local_pid)
		var wait: float = QUIT_AFTER_VISIT + QUIT_STAGGER * float(order if not host.is_authority() else host.player_ids().size() + 2)
		if not _quit_called and Time.get_ticks_msec() - _visit_started_msec > int(wait * 1000.0):
			_quit_called = true
			main.call(&"quit_game")
		return
	if director.finished or not director.npcs_active or director.player == null:
		_stop_moving()
		return
	_step_t += delta
	_answer_quiz(delta)
	if host.is_authority():
		_host_duties()
	match step:
		Step.WAIT:
			if not host.is_authority():
				_next(Step.TABLE)
			elif not _clients_busy() or _step_t > STEP_TIMEOUT * 2.0:
				# The host waits for the clients' script before heading out.
				_next(Step.EXIT)
		Step.TABLE:
			_go_table(delta)
		Step.BET:
			_bet()
		Step.CASHIER:
			_go_cashier(delta)
		Step.BANK:
			_bank()
		Step.WANTED:
			_go_get_caught(delta)
		Step.CARRIED:
			_stop_moving()
			if _rejoined and _status() == HR.PlayerStatus.FREE:
				_next(Step.EXIT)
		Step.EXIT:
			_go_exit(delta)
		Step.DONE:
			_stop_moving()
	if step != Step.WAIT and step != Step.DONE and _step_t > STEP_TIMEOUT:
		_log("step_timeout", {"step": STEP_NAMES[step]})
		_next(Step.EXIT if step != Step.EXIT else Step.DONE)


func _next(next_step: int) -> void:
	if next_step == step:
		return
	_log("step", {"from": STEP_NAMES[step], "to": STEP_NAMES[next_step]})
	step = next_step
	_step_t = 0.0
	_target = null
	_path = PackedVector3Array()
	_stop_moving()


# --- Steps ------------------------------------------------------------------------

func _go_table(delta: float) -> void:
	if director.player.state == PlayerCharacter.STATE_SEATED:
		_next(Step.BET)
		return
	if _target == null:
		_target = _nearest_table()
		if _target == null:
			_next(Step.CASHIER)
			return
		_start_walk(_target.global_position)
	_walk_to_interactable(delta)


func _bet() -> void:
	var panel: BetPanel = main.get(&"bet_panel")
	if director.player.state != PlayerCharacter.STATE_SEATED and not panel.is_open():
		_next(Step.CASHIER)
		return
	if won or bets >= MAX_BETS:
		if panel.is_open() and not panel.is_waiting():
			panel.request_leave()
		return
	if panel.game_type == HR.GameType.DICE and bets == 0 and not _crew_seated(panel.table_id) and _step_t < 15.0:
		return  # wait for the other clients: one shared roll
	if panel.is_open() and not panel.is_waiting() and not panel.is_locked() and not panel.main_button.disabled:
		panel.set_bet_amount(1)
		panel.press_main()


func _go_cashier(delta: float) -> void:
	var cashier: CashierPanel = main.get(&"cashier_panel")
	if cashier.is_open():
		_next(Step.BANK)
		return
	if _target == null:
		var its := director.map.interactables_of(&"cashier")
		if its.is_empty():
			_next(Step.WANTED)
			return
		_target = its[0]
		_start_walk(_target.global_position)
	_walk_to_interactable(delta)


func _bank() -> void:
	var cashier: CashierPanel = main.get(&"cashier_panel")
	if not cashier.is_open():
		_next(_after_bank())
		return
	if not _banked and _step_t > 0.5:
		var pocket: int = int(_me().get("pocket", 0))
		if pocket <= 0:
			_banked = true
		elif cashier.all_button.disabled == false and _tap_left <= 0.0:
			_tap_left = 2.0
			cashier.cash_out(pocket)
	if _banked:
		cashier.close()


func _after_bank() -> int:
	return Step.WANTED if _is_runner() else Step.EXIT


## The runner: once Wanted, walk (never run: a running bump stuns) to the guard.
func _go_get_caught(delta: float) -> void:
	var status := _status()
	if status == HR.PlayerStatus.CARRIED or status == HR.PlayerStatus.DETAINED:
		_next(Step.CARRIED)
		return
	if float(_me().get("heat", 0.0)) < Tuning.WANTED_AT:
		_stop_moving()
		return
	if director.guards.is_empty():
		_next(Step.EXIT)
		return
	var g: GuardNPC = director.guards[0]
	_repath_left -= delta
	if _repath_left <= 0.0 or _path.is_empty():
		_start_walk(g.global_position)
	if _flat(director.player.global_position, g.global_position) < 1.2:
		_stop_moving()
		return
	_walk(delta, g.global_position, false)


func _go_exit(delta: float) -> void:
	var exit_point: Vector3 = director.map.to_global(director.map.exit_point)
	if int(_me().get("zone", -1)) == HR.ZoneType.EXIT and _flat(director.player.global_position, exit_point) < 2.5:
		_stop_moving()
		var it := director.player.current_interactable()
		if it != null and it.kind == &"exit" and _tap_left <= 0.0:
			_tap_left = 2.0
			_log("exit_press", {})
			_tap(&"interact")
		elif it == null and _tap_left <= 0.0:
			_tap_left = 1.0
			_steer(exit_point - director.player.global_position, false)
		return
	if _path.is_empty():
		_start_walk(exit_point)
	_walk(delta, exit_point, true)


## Host: make the runner Wanted once it has banked; top the bank up for the
## climb once everyone is heading out.
func _host_duties() -> void:
	var sim := host.current_sim()
	if sim == null:
		return
	var runner := _runner_pid()
	if not _runner_heated and runner > 0 and _client_step(runner) >= Step.WANTED:
		var ps := sim.player(runner)
		if ps != null and ps.status == HR.PlayerStatus.FREE:
			_runner_heated = true
			_log("make_wanted", {"runner": runner})
			# Test shortcut: the sim's own Heat meter, so the guards react as in play.
			ps.heat.raise_to(Tuning.WANTED_AT + 5.0, &"net_test")
	if not _topped_up and step == Step.EXIT and not sim.run.can_climb():
		var need: int = CasinoLadder.buy_in_to_leave(sim.run.rung) - sim.run.bank
		if need > 0:
			_topped_up = true
			_log("top_up_bank", {"chips": need})
			sim.run.add_bank(need)


# --- Walking ----------------------------------------------------------------------

func _start_walk(to: Vector3) -> void:
	_goal = to
	_plan(to)
	_best_dist = INF
	_best_t = _step_t


func _plan(to: Vector3) -> void:
	_repath_left = REPATH_SECONDS
	_path_i = 0
	var nav: RID = director.map.navigation_map()
	var end := NavigationServer3D.map_get_closest_point(nav, Vector3(to.x, director.map.global_position.y, to.z))
	_path = NavigationServer3D.map_get_path(nav, director.player.global_position, end, true)
	if _path.is_empty():
		_path = PackedVector3Array([to])


func _walk(delta: float, to: Vector3, run: bool) -> float:
	var player := director.player
	var pos := player.global_position
	var dist := _flat(pos, to)
	_repath_left -= delta
	if _repath_left <= 0.0:
		_plan(to)
	while _path_i < _path.size() and _flat(pos, _path[_path_i]) < WAYPOINT_REACH:
		_path_i += 1
	var next: Vector3 = _path[_path_i] if _path_i < _path.size() else to
	_steer(next - pos, run)
	if dist < _best_dist - 0.3:
		_best_dist = dist
		_best_t = _step_t
	elif _step_t - _best_t > STUCK_SECONDS:
		# A bot convenience: hop along the path instead of grinding on a corner.
		_best_t = _step_t
		_best_dist = dist
		_log("stuck_hop", {"at": pos})
		player.teleport(next + Vector3.UP * 0.05)
	return dist


func _walk_to_interactable(delta: float) -> void:
	var it := _target
	if it == null or not is_instance_valid(it):
		_target = null
		return
	if director.player.current_interactable() == it:
		_stop_moving()
		if _tap_left <= 0.0:
			_tap_left = TAP_COOLDOWN * 3.0
			_tap(&"interact")
		return
	var d := _flat(director.player.global_position, it.global_position)
	if d < 1.4:
		_steer(it.global_position - director.player.global_position, false)
		return
	_walk(delta, _goal, true)


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


# --- UI ---------------------------------------------------------------------------

func _answer_quiz(delta: float) -> void:
	var quiz: IdQuizPanel = main.get(&"quiz_panel")
	if not quiz.is_waiting() or _quiz.is_empty():
		return
	_quiz_t += delta
	if _quiz_t < 0.6:
		return
	var options: Array = _quiz.get("options", [])
	var card := FakeId.from_dict(_me().get("id", {}))
	var pick: int = maxi(0, options.find(IdQuiz.answer_for(card, StringName(str(_quiz.get("field", ""))))))
	_log("quiz_answer", {"field": _quiz.get("field", ""), "pick": pick})
	_quiz = {}
	quiz.answer(pick)


func _handle_banner(delta: float) -> void:
	var banner: VisitBanner = main.get(&"visit_banner")
	if banner == null or not banner.is_open():
		_banner_t = 0.0
		return
	_banner_t += delta
	if _banner_t > 1.0 and banner.kind != VisitBanner.KIND_SUMMARY:
		banner.handle_key(KEY_SPACE)
		_banner_t = 0.0


# --- Events -----------------------------------------------------------------------

func _on_visit_begun(d: CasinoDirector) -> void:
	director = d
	visits += 1
	_visit_started_msec = Time.get_ticks_msec()
	_log("visit", {"n": visits, "rung": d.rung, "players": d.players.size()})
	if visits == 1:
		step = Step.WAIT
		_step_t = 0.0


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	var pid: int = int(data.get("pid", 0))
	var mine: bool = pid == host.local_pid
	match kind:
		&"bet":
			if mine and bool(data.get("round_over", true)):
				bets += 1
				var result: Dictionary = data.get("result", {})
				if bool(result.get("won", false)) and int(result.get("net", 0)) > 0:
					won = true
				_log("bet_result", {"n": bets, "won": bool(result.get("won", false))})
		&"id_check":
			if mine and not bool(data.get("auto_fail", false)):
				_quiz = data.get("question", {})
				_quiz_t = 0.0
		&"caught":
			if mine:
				_caught = true
		&"rejoined":
			if mine:
				_rejoined = true
			if host.is_authority() and pid == _runner_pid() and _runner_heated:
				_runner_rejoined = true
		&"banked":
			if mine:
				_banked = true


func _on_request_done(request: StringName, args: Array, res: Dictionary) -> void:
	if request == &"cash_out" and not args.is_empty() and int(args[0]) == host.local_pid:
		_log("cash_out_answer", {"ok": bool(res.get("ok", false)), "reason": res.get("reason", &"")})
		if bool(res.get("ok", false)):
			_banked = true


# --- Helpers ----------------------------------------------------------------------

func _me() -> Dictionary:
	return UiTheme.player_snapshot(host, host.local_pid)


func _status() -> int:
	return int(_me().get("status", HR.PlayerStatus.FREE))


## The lowest client pid (the one the host makes Wanted), or 0 solo.
func _runner_pid() -> int:
	var best := 0
	for pid: int in host.player_ids():
		if pid != 1 and (best == 0 or pid < best):
			best = pid
	return best


func _is_runner() -> bool:
	return not host.is_authority() and host.local_pid == _runner_pid()


## Host: a client's script step, as far as the host can tell from the sim.
func _client_step(pid: int) -> int:
	var sim := host.current_sim()
	var ps: PlayerState = sim.player(pid) if sim != null else null
	if ps == null:
		return Step.DONE
	if ps.status == HR.PlayerStatus.CARRIED or ps.status == HR.PlayerStatus.DETAINED:
		return Step.CARRIED
	# Banked at the cashier: the runner is ready to be made Wanted.
	if ps.wallet.lifetime_banked > 0 or (ps.zone == HR.ZoneType.CASHIER and ps.wallet.pocket == 0):
		return Step.WANTED
	return Step.TABLE


## Host: some client hasn't finished its pre-exit script yet.
func _clients_busy() -> bool:
	var sim := host.current_sim()
	if sim == null:
		return false
	var runner := _runner_pid()
	for pid: int in host.player_ids():
		if pid == 1:
			continue
		var ps := sim.player(pid)
		if ps == null:
			continue
		if pid == runner:
			# Wait for the whole grab -> back room -> rejoin sequence.
			if not _runner_rejoined or ps.status != HR.PlayerStatus.FREE:
				return true
		elif ps.wallet.lifetime_banked <= 0 and ps.zone != HR.ZoneType.EXIT and _step_t < STEP_TIMEOUT:
			return true
	return false


## The nearest single-shot table; with two or more clients, a dice table
## (they share one roll).
func _nearest_table() -> Interactable:
	var best: Interactable = null
	var best_d := INF
	if host.player_ids().size() >= 3:
		for t: TableNode in director.tables.values():
			if t.game_type == HR.GameType.DICE and t.interactable.enabled:
				return t.interactable
	for t: TableNode in director.tables.values():
		if not (t.game_type in [HR.GameType.SLOTS, HR.GameType.BIG_WHEEL, HR.GameType.DICE, HR.GameType.ROULETTE]):
			continue
		if not t.interactable.enabled:
			continue
		var d := _flat(director.player.global_position, t.interactable.global_position)
		if d < best_d:
			best = t.interactable
			best_d = d
	return best


## Every client sits at `table_id` (the snapshot's seat list).
func _crew_seated(table_id: StringName) -> bool:
	var t: Dictionary = (host.snapshot().get("tables", {}) as Dictionary).get(table_id, {})
	return (t.get("seated", []) as Array).size() >= host.player_ids().size() - 1


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _log(event: String, fields: Dictionary = {}) -> void:
	var f := {"bot": event}
	f.merge(fields)
	NetLog.line("bot", f)
