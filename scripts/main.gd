extends Node
## Game root (scenes/main.tscn): owns the NetSession, the SimHost, the UI
## layers and the title / lobby / pause / visit-to-visit flow, and swaps one
## CasinoDirector per casino visit.
##
## Single player: the title starts a run here (no network peer). Co-op: the
## title hosts (ENet, or a Steam lobby) or joins; the lobby shows the crew and
## the host starts the run. The host runs the sim and announces each visit;
## a client builds the visit the host announced (SimHost.visit_started) and
## goes back to the title if the host leaves. A client that drops out of a
## run is removed from it (SimHost.remove_player): their body goes, the crew
## carries on without them.
##
## Command line (after `--`): --practice, --rung=N, --seed=N, --autostart
## (skip the title screen), --autopilot (a bot plays: tools/autopilot.gd;
## implies --autostart), --autopilot-seconds=N (quit after N sim seconds with
## the bot's summary), --speed=N (run the game N times faster). Co-op:
## --host[=port] (host on start; with --autostart the run starts once
## --players=N are in the crew, default 1), --join=address[:port],
## --name=NAME, --net-log (one `NET ...` line per network event, for
## tools/net_test.sh), --net-bot (tools/net_bot.gd plays a scripted co-op
## test), --quit-after-seconds=N (quit after N real seconds). Progression:
## --profile=PATH (where the profile is saved), --no-profile (keep it in
## memory only). Tests and tools can set the same options as vars before
## adding the node to the tree (set parse_args = false to ignore the command
## line).
##
## Progression (design doc "Scoring and progression"): the Profile is loaded
## at boot (ProfileStore, user://profile.json) by the real game only: with
## parse_args off (tests, tools), or under --autopilot / --net-bot, it lives
## in memory unless profile_path is set. The local player's &"banked" events
## add to lifetime banked chips; new unlocks are announced on the HUD and
## saved at once; the run's score is posted to the local leaderboard for its
## crew size when the run ends (practice runs aren't), and the profile is
## saved then and on the way back to the title. Co-op: every peer keeps its
## own profile and posts the crew's score to its own board. Unlocks are each
## player's own: the host's RunState holds every player's unlocked pieces and
## name packs (set_unlocks; a client sends its own as an &"unlocks" world
## message each visit), so the gift shop sells you what you unlocked and your
## new fake IDs use your name packs; emotes play locally and their pose syncs
## like any other pose.

## Emitted after each new visit's director is set up.
signal visit_begun(director: CasinoDirector)

const LOCAL_PID := 1
const PLAYER_NAME := "You"

## Options (the command line can set these too).
var autostart: bool = false
var start_rung: int = Tuning.TOP_RUNG
var practice: bool = false
## 0 picks a random seed per run.
var run_seed: int = 0
var parse_args: bool = true
## A bot plays (Autopilot); it prints its timeline to stdout.
var autopilot: bool = false
## With autopilot: quit after this many sim seconds (0 = keep playing).
var autopilot_seconds: float = 0.0
## Engine.time_scale (physics ticks scale with it, so the step stays 1/60 s).
var speed: float = 1.0
## Co-op: host on this port at start (0 = don't).
var host_port: int = 0
## Co-op: join this address at start ("" = don't).
var join_address: String = ""
var join_port: int = NetSession.DEFAULT_PORT
## Co-op player name ("" = the title's field, or "Player").
var player_name: String = ""
## Co-op host with autostart: start once this many players are in the crew.
var autostart_players: int = 1
## Quit after this many real seconds (0 = never).
var quit_after_seconds: float = 0.0
## Print `NET ...` lines (NetLog).
var net_log: bool = false
## Run the scripted co-op test bot (tools/net_bot.gd).
var net_bot: bool = false
## The running Autopilot, if any.
var bot: Autopilot
## The running NetBot, if any.
var net_test_bot: NetBot
## Where the profile is saved; "" keeps it in memory (see the header).
var profile_path: String = ""
## Keep the profile in memory even in the real game (--no-profile).
var no_profile: bool = false
## This player's progression. Set it before adding the node to start from a
## given profile (tests, tools).
var profile: Profile
## Saves the profile (null when it lives in memory only).
var profile_store: ProfileStore
## Unlock ids earned during the current run (the run summary lists them).
var run_unlocks: Array[StringName] = []

var session: NetSession
var host: SimHost
var director: CasinoDirector
var world: Node3D
var hud_layer: CanvasLayer
var panel_layer: CanvasLayer
var menu_layer: CanvasLayer
var hud: Hud
var bet_panel: BetPanel
var quiz_panel: IdQuizPanel
var cashier_panel: CashierPanel
var wardrobe_panel: WardrobePanel
var forger_panel: ForgerPanel
var debug_overlay: DebugOverlay
var visit_banner: VisitBanner
var pause_menu: PauseMenu
var title_screen: TitleScreen
var lobby_panel: LobbyPanel
var unlocks_panel: UnlocksPanel
var leaderboard_panel: LeaderboardPanel

## Bumped whenever a run starts or stops, so a visit swap waiting on the
## banner never lands in a run that has since ended.
var _run_token: int = 0
var _swapping: bool = false
var _autostart_pending: bool = false
## The most players the current run has had (its leaderboard crew size).
var _run_crew: int = 1
var _run_posted: bool = false
var _profile_dirty: bool = false


func _ready() -> void:
	InputSetup.ensure_actions()
	if parse_args:
		_parse_args()
	if net_log:
		NetLog.enabled = true
		NetLog.pid = LOCAL_PID
	if not is_equal_approx(speed, 1.0):
		Engine.time_scale = speed
		Engine.physics_ticks_per_second = roundi(60.0 * speed)
	_load_profile()
	_build()
	if quit_after_seconds > 0.0:
		get_tree().create_timer(quit_after_seconds, true, false, true).timeout.connect(quit_game)
	if host_port > 0:
		host_coop(host_port, player_name)
	elif join_address != "":
		join_coop(join_address, join_port, player_name)
	elif autostart or autopilot:
		start_game(start_rung, practice)
	else:
		show_title()
	if autopilot and join_address != "":
		# The Autopilot reads the host's sim; a client has none.
		push_warning("--autopilot plays offline or as the host; use --net-bot on a client")
		autopilot = false
	if autopilot:
		bot = Autopilot.new()
		bot.echo = true
		bot.quit_after_seconds = autopilot_seconds
		add_child(bot)
		bot.setup(self)
	if net_bot:
		net_test_bot = NetBot.new()
		add_child(net_test_bot)
		net_test_bot.setup(self)


## Starts a fresh run at `rung` (practice: one floor guard, nothing else).
## Co-op: the host starts it for the whole crew; clients can't.
func start_game(rung: int, practice_mode: bool) -> void:
	if host.is_client():
		return
	_run_token += 1
	_stop_visit()
	visit_banner.dismiss()
	start_rung = clampi(rung, Tuning.TOP_RUNG, Tuning.BOTTOM_RUNG)
	practice = practice_mode
	var seed_value: int = run_seed if run_seed != 0 else hash([Time.get_ticks_usec(), Time.get_unix_time_from_system()])
	var names: Dictionary = {LOCAL_PID: PLAYER_NAME}
	if session.is_online():
		names = session.roster.duplicate()
		session.lobby_open = false
	host.start_run(start_rung, seed_value, names)
	_begin_run_progress(names.size())
	_apply_unlocks()
	title_screen.visible = false
	lobby_panel.close()
	hud.visible = true
	NetLog.line("run_start", {"rung": start_rung, "practice": practice, "crew": names.size()})
	_begin_visit()


func show_title(message: String = "") -> void:
	_run_token += 1
	_stop_visit()
	save_profile_if_dirty()
	title_screen.set_unlock_badge(profile.unseen.size())
	hud.visible = false
	visit_banner.dismiss()
	lobby_panel.close()
	title_screen.visible = true
	title_screen.show_message(message)
	if message != "":
		NetLog.line("title", {"message": message})
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if title_screen.is_inside_tree():
		title_screen.start_button.grab_focus()


## Co-op: the crew between runs (the host can start one).
func show_lobby() -> void:
	_run_token += 1
	_stop_visit()
	save_profile_if_dirty()
	hud.visible = false
	visit_banner.dismiss()
	title_screen.visible = false
	if session.state == NetSession.State.HOSTING:
		session.lobby_open = true
	lobby_panel.open()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_check_autostart()


## Hosts a co-op game on `port` (ENet) and opens the lobby.
func host_coop(port: int = NetSession.DEFAULT_PORT, name_text: String = "") -> void:
	session.local_name = name_text if name_text != "" else "Host"
	title_screen.show_message("")
	session.host(port)


## Joins a co-op game at `address`:`port` (ENet); the lobby shows progress.
func join_coop(address: String, port: int = NetSession.DEFAULT_PORT, name_text: String = "") -> void:
	session.local_name = name_text if name_text != "" else "Player"
	title_screen.show_message("")
	if session.join(address, port) == OK:
		show_lobby()
		lobby_panel.set_status("Connecting to %s:%d..." % [address, port])


## Leaves the co-op session (if any) and goes back to the title.
func leave_coop(message: String = "") -> void:
	session.leave()
	_go_offline()
	show_title(message)


## Quits the game, closing the co-op session first.
func quit_game() -> void:
	save_profile_if_dirty()
	NetLog.line("quit")
	if net_test_bot != null:
		net_test_bot.report()
	session.leave()
	get_tree().quit()


## The unlocks screen (over the title).
func open_unlocks() -> void:
	leaderboard_panel.close()
	unlocks_panel.set_profile(profile)
	unlocks_panel.open()


## The local leaderboards (over the title); crew_size 0 keeps the last board.
func open_leaderboard(crew_size: int = 0) -> void:
	unlocks_panel.close()
	leaderboard_panel.set_profile(profile)
	leaderboard_panel.open(crew_size)


## Adds banked chips to the profile's lifetime total; announces, applies and
## saves any unlocks they cross. Returns the new unlock ids.
func add_banked(amount: int) -> Array[StringName]:
	var fresh: Array[StringName] = profile.add_banked(amount)
	if amount > 0:
		_profile_dirty = true
	if not fresh.is_empty():
		run_unlocks.append_array(fresh)
		_announce_unlocks(fresh)
		_apply_unlocks()
		save_profile()
	title_screen.set_unlock_badge(profile.unseen.size())
	return fresh


## Writes the profile now (no-op when it lives in memory). False if the write failed.
func save_profile() -> bool:
	_profile_dirty = false
	if profile_store == null:
		return true
	var ok := profile_store.save(profile)
	if not ok:
		push_warning("Couldn't save the profile to %s" % profile_store.path)
	return ok


func save_profile_if_dirty() -> void:
	if _profile_dirty:
		save_profile()


func open_pause() -> void:
	if director == null or pause_menu.is_open() or title_screen.visible:
		return
	director.input_blocked = true
	director.sync_input(true)
	# A co-op game keeps running for everyone while one player is in the menu.
	if not session.is_online():
		host.paused = true
		get_tree().paused = true
	# A co-op restart would rebuild the visit under everyone's feet: leave instead.
	pause_menu.restart_button.visible = not session.is_online()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu.open()


func close_pause() -> void:
	get_tree().paused = false
	host.paused = false
	if pause_menu.is_open():
		pause_menu.close()
	if director != null:
		director.input_blocked = false
		director.sync_input(true)


# --- Build ------------------------------------------------------------------

func _build() -> void:
	session = NetSession.new()
	session.name = "NetSession"
	add_child(session)
	host = SimHost.new()
	host.name = "SimHost"
	host.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(host)
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	hud_layer = _layer("HudLayer", 1)
	panel_layer = _layer("PanelLayer", 2)
	menu_layer = _layer("MenuLayer", 3)
	hud = Hud.new()
	hud_layer.add_child(hud)
	bet_panel = BetPanel.new()
	quiz_panel = IdQuizPanel.new()
	cashier_panel = CashierPanel.new()
	wardrobe_panel = WardrobePanel.new()
	forger_panel = ForgerPanel.new()
	debug_overlay = DebugOverlay.new()
	for c: Control in [bet_panel, cashier_panel, wardrobe_panel, forger_panel, quiz_panel, debug_overlay]:
		panel_layer.add_child(c)
	visit_banner = VisitBanner.new()
	pause_menu = PauseMenu.new()
	title_screen = TitleScreen.new()
	lobby_panel = LobbyPanel.new()
	unlocks_panel = UnlocksPanel.new()
	leaderboard_panel = LeaderboardPanel.new()
	menu_layer.add_child(visit_banner)
	menu_layer.add_child(pause_menu)
	menu_layer.add_child(title_screen)
	menu_layer.add_child(lobby_panel)
	menu_layer.add_child(unlocks_panel)
	menu_layer.add_child(leaderboard_panel)
	title_screen.setup(host, LOCAL_PID)
	title_screen.set_unlock_badge(profile.unseen.size())
	unlocks_panel.set_profile(profile)
	leaderboard_panel.set_profile(profile)
	wardrobe_panel.set_profile(profile)
	lobby_panel.set_session(session)
	pause_menu.visible = false
	_setup_ui(LOCAL_PID)

	host.visit_started.connect(_on_host_visit_started)
	host.world_message.connect(_on_world_message)
	title_screen.start_requested.connect(start_game)
	title_screen.quit_requested.connect(quit_game)
	title_screen.unlocks_requested.connect(open_unlocks)
	title_screen.leaderboard_requested.connect(open_leaderboard)
	unlocks_panel.closed.connect(_on_unlocks_closed)
	leaderboard_panel.closed.connect(_focus_title)
	title_screen.host_requested.connect(func(port: int, name_text: String) -> void: host_coop(port, name_text))
	title_screen.join_requested.connect(func(address: String, port: int, name_text: String) -> void: join_coop(address, port, name_text))
	title_screen.steam_host_requested.connect(_on_steam_host_requested)
	lobby_panel.start_requested.connect(start_game)
	lobby_panel.leave_requested.connect(func() -> void: leave_coop())
	lobby_panel.invite_requested.connect(func() -> void: session.invite_friends())
	pause_menu.resume_requested.connect(close_pause)
	pause_menu.restart_requested.connect(_on_restart)
	pause_menu.quit_to_title_requested.connect(_on_quit_to_title)
	session.connected.connect(_on_session_connected)
	session.connection_failed.connect(_on_connection_failed)
	session.server_disconnected.connect(_on_server_disconnected)
	session.player_left.connect(_on_player_left)
	session.roster_changed.connect(func(_roster: Dictionary) -> void: _check_autostart())


## (Re)binds every panel to this peer's pid (1 offline and hosting).
func _setup_ui(pid: int) -> void:
	if host.sim_event.is_connected(_on_sim_event):
		host.sim_event.disconnect(_on_sim_event)
	for c: Control in [hud, bet_panel, quiz_panel, cashier_panel, wardrobe_panel, forger_panel, debug_overlay, visit_banner, pause_menu]:
		c.call(&"setup", host, pid)
	# After the banner's own handler (connected in setup above).
	host.sim_event.connect(_on_sim_event)


func _layer(layer_name: String, index: int) -> CanvasLayer:
	var l := CanvasLayer.new()
	l.name = layer_name
	l.layer = index
	add_child(l)
	return l


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for a: String in args:
		if a == "--practice":
			practice = true
		elif a == "--autostart":
			autostart = true
		elif a.begins_with("--rung="):
			start_rung = clampi(a.get_slice("=", 1).to_int(), Tuning.TOP_RUNG, Tuning.BOTTOM_RUNG)
		elif a.begins_with("--seed="):
			run_seed = a.get_slice("=", 1).to_int()
		elif a == "--autopilot":
			autopilot = true
		elif a.begins_with("--autopilot-seconds="):
			autopilot = true
			autopilot_seconds = maxf(0.0, a.get_slice("=", 1).to_float())
		elif a.begins_with("--speed="):
			speed = clampf(a.get_slice("=", 1).to_float(), 0.1, 16.0)
		elif a == "--host":
			host_port = NetSession.DEFAULT_PORT
		elif a.begins_with("--host="):
			var p: int = a.get_slice("=", 1).to_int()
			host_port = p if p > 0 and p < 65536 else NetSession.DEFAULT_PORT
		elif a.begins_with("--join="):
			var target: String = a.substr(7)
			join_address = target
			var colon: int = target.rfind(":")
			if colon > 0 and target.substr(colon + 1).is_valid_int():
				join_address = target.substr(0, colon)
				join_port = target.substr(colon + 1).to_int()
		elif a.begins_with("--name="):
			player_name = a.substr(7)
		elif a.begins_with("--players="):
			autostart_players = clampi(a.get_slice("=", 1).to_int(), 1, NetSession.MAX_PLAYERS)
		elif a.begins_with("--quit-after-seconds="):
			quit_after_seconds = maxf(0.0, a.get_slice("=", 1).to_float())
		elif a == "--net-log":
			net_log = true
		elif a == "--net-bot":
			net_bot = true
		elif a.begins_with("--profile="):
			profile_path = a.substr(10)
		elif a == "--no-profile":
			no_profile = true


# --- Co-op session --------------------------------------------------------------

func _on_steam_host_requested(name_text: String) -> void:
	session.local_name = name_text
	title_screen.show_message("Creating the Steam lobby...", UiTheme.GOLD_LIGHT)
	session.host_steam()


func _on_session_connected() -> void:
	if session.state == NetSession.State.HOSTING:
		host.set_network(SimHost.Role.HOST, LOCAL_PID)
		_setup_ui(LOCAL_PID)
	else:
		var pid: int = session.local_pid()
		host.set_network(SimHost.Role.CLIENT, pid)
		_setup_ui(pid)
	if not lobby_panel.is_open():
		show_lobby()
	lobby_panel.set_status("")
	lobby_panel.refresh()
	_check_autostart()


func _on_connection_failed(reason: String) -> void:
	_go_offline()
	show_title(reason)


func _on_server_disconnected() -> void:
	_go_offline()
	show_title("The host left the game.")


func _on_player_left(pid: int) -> void:
	if host.role == SimHost.Role.HOST:
		host.remove_player(pid)


func _go_offline() -> void:
	if host.role != SimHost.Role.OFFLINE:
		host.set_network(SimHost.Role.OFFLINE, LOCAL_PID)
		_setup_ui(LOCAL_PID)


## Host with --autostart: start once the crew has --players members.
func _check_autostart() -> void:
	if not autostart or _autostart_pending or session.state != NetSession.State.HOSTING or not lobby_panel.is_open():
		return
	if session.roster.size() < autostart_players:
		return
	_autostart_pending = true
	_autostart_now.call_deferred()


func _autostart_now() -> void:
	_autostart_pending = false
	if lobby_panel.is_open() and session.state == NetSession.State.HOSTING:
		start_game(start_rung, practice)


# --- Visits -----------------------------------------------------------------

func _begin_visit() -> void:
	host.visit_extras = {"practice": practice}
	host.start_visit()
	_make_director(host.run.rung)


## Client: the host announced a visit; build it.
func _on_host_visit_started(_sim: FloorSim) -> void:
	if not host.is_client():
		return
	_run_token += 1
	_swapping = false
	_stop_visit()
	visit_banner.dismiss()
	lobby_panel.close()
	title_screen.visible = false
	hud.visible = true
	var info: Dictionary = host.visit_info()
	practice = bool(info.get("practice", false))
	if int(info.get("visits", 1)) <= 1:
		_begin_run_progress(1)
	_make_director(int(info.get("rung", Tuning.BOTTOM_RUNG)))


func _make_director(rung: int) -> void:
	director = CasinoDirector.new()
	world.add_child(director)
	director.setup(host, rung, practice, {
		"hud": hud, "bet_panel": bet_panel, "quiz_panel": quiz_panel, "cashier_panel": cashier_panel,
		"wardrobe_panel": wardrobe_panel, "forger_panel": forger_panel, "visit_banner": visit_banner,
		"debug_overlay": debug_overlay,
	})
	director.visit_finished.connect(_on_visit_finished)
	director.pause_requested.connect(open_pause)
	_run_crew = maxi(_run_crew, host.player_ids().size())
	_apply_unlocks()
	hud.refresh()
	visit_begun.emit(director)


func _stop_visit() -> void:
	get_tree().paused = false
	if host != null:
		host.paused = false
	if pause_menu != null and pause_menu.is_open():
		pause_menu.close()
	if director != null:
		world.remove_child(director)
		director.queue_free()
		director = null
	for p: Control in [bet_panel, quiz_panel, cashier_panel, wardrobe_panel, forger_panel]:
		if p != null:
			p.call(&"close")


func _on_visit_finished(outcome: StringName) -> void:
	if _swapping:
		return
	var token := _run_token
	if outcome == CasinoDirector.OUTCOME_RUN_OVER:
		visit_banner.show_run_summary(_finish_run())
		await visit_banner.closed
		if token == _run_token:
			if session.is_online():
				show_lobby()
			else:
				show_title()
		return
	# A client waits for the host to announce the next visit.
	if host.is_client():
		return
	_swapping = true
	if visit_banner.is_open():
		await visit_banner.closed
	_swapping = false
	if token != _run_token or director == null:
		return
	_stop_visit()
	_begin_visit()


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if kind == &"banked" and int(data.get("pid", 0)) == host.local_pid:
		add_banked(int(data.get("amount", 0)))
	if kind == &"thrown_out" and visit_banner.is_open():
		visit_banner.route_label.text = "%s threw you out  >>  %s" % [
			str(CasinoLadder.casino(int(data.get("from", 0))).get("name", "")),
			str(CasinoLadder.casino(int(data.get("to", 0))).get("name", "")),
		]


# --- Progression ------------------------------------------------------------------

func _load_profile() -> void:
	if profile_path == "" and parse_args and not no_profile and not autopilot and not net_bot:
		profile_path = ProfileStore.DEFAULT_PATH
	if no_profile:
		profile_path = ""
	profile_store = ProfileStore.new(profile_path) if profile_path != "" else null
	if profile != null:
		return
	if profile_store == null:
		profile = Profile.new()
		return
	profile = profile_store.load_profile()
	if profile_store.last_error != "":
		push_warning("The profile at %s was unreadable (%s); it was moved to %s and a fresh one started." % [profile_path, profile_store.last_error, profile_store.corrupt_path])


## A run starts on this peer: no unlocks earned yet, nothing posted.
func _begin_run_progress(crew: int) -> void:
	run_unlocks.clear()
	_run_posted = false
	_run_crew = maxi(1, crew)


## This peer's unlocks into the run (gift shop pieces, ID name packs; offline
## and on the host straight into RunState, a client sends them to the host)
## and its emotes onto its player.
func _apply_unlocks() -> void:
	if host.is_authority():
		if host.run != null:
			host.run.set_unlocks(host.local_pid, profile.unlocked_pieces(), profile.unlocked_name_packs())
	elif host.visit_token() != 0:
		host.send_world(1, &"unlocks", {"pieces": _id_strings(profile.unlocked_pieces()), "name_packs": _id_strings(profile.unlocked_name_packs())})
	if director != null and director.player != null:
		director.player.set_emotes(profile.unlocked_emotes())
	if wardrobe_panel.is_open():
		wardrobe_panel.refresh()


## Host: a client's own unlocks for this run.
func _on_world_message(kind: StringName, data: Dictionary, from_pid: int) -> void:
	if kind != &"unlocks" or not host.is_authority() or host.run == null or from_pid == host.local_pid:
		return
	var pieces: Variant = data.get("pieces", [])
	var packs: Variant = data.get("name_packs", [])
	host.run.set_unlocks(from_pid, pieces if pieces is Array else [], packs if packs is Array else [])
	NetLog.line("unlocks", {"pid": from_pid, "pieces": (pieces as Array).size() if pieces is Array else 0})


func _announce_unlocks(ids: Array[StringName]) -> void:
	for id: StringName in ids:
		var where := ""
		match Unlocks.kind_of(id):
			Unlocks.KIND_PIECE:
				where = "On sale at every gift shop."
			Unlocks.KIND_EMOTE:
				where = "Press T to emote."
			Unlocks.KIND_NAME_PACK:
				where = "New names on your fake IDs."
		hud.push_notification("UNLOCKED: %s!  %s" % [Unlocks.display_name(id), where], UiTheme.GOLD_LIGHT)
	if hud.visible and not ids.is_empty():
		hud.show_banner("UNLOCKED: %s" % Unlocks.display_name(ids.back()).to_upper(), UiTheme.GOLD_LIGHT)


## The run is over: posts its score to this crew size's local board (once),
## saves, and returns the run summary's stats.
func _finish_run() -> Dictionary:
	var stats: Dictionary = (host.snapshot().get("run", {}) as Dictionary).duplicate()
	var crew := maxi(_run_crew, host.player_ids().size())
	var rank := 0
	if not _run_posted:
		_run_posted = true
		var entry := {
			"top_banked": int(stats.get("top_banked", 0)),
			"top_seconds": float(stats.get("top_seconds", 0.0)),
			"elapsed_seconds": float(stats.get("elapsed_seconds", 0.0)),
			"visits": int(stats.get("visits", 1)),
			"crew": _crew_names(),
			"date": Time.get_datetime_string_from_system(false, true),
		}
		rank = profile.record_run(int(stats.get("score", 0)), crew, entry, practice)
		leaderboard_panel.highlight_serial = 0 if practice else profile.last_serial
		save_profile()
		NetLog.line("run_posted", {"score": int(stats.get("score", 0)), "crew": crew, "rank": rank, "practice": practice})
	stats.merge({"rank": rank, "crew_size": crew, "practice": practice, "unlocks": run_unlocks.duplicate()}, true)
	return stats


func _crew_names() -> Array:
	var out: Array = []
	var players: Dictionary = host.snapshot().get("players", {})
	for pid: Variant in players:
		out.append(str((players[pid] as Dictionary).get("name", "Player")))
	if out.is_empty():
		out.append(PLAYER_NAME)
	return out


func _on_unlocks_closed() -> void:
	_profile_dirty = true
	save_profile()
	title_screen.set_unlock_badge(profile.unseen.size())
	_focus_title()


func _focus_title() -> void:
	if title_screen.visible and title_screen.is_inside_tree():
		title_screen.start_button.grab_focus()


static func _id_strings(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id: StringName in ids:
		out.append(String(id))
	return out


func _on_restart() -> void:
	start_game(start_rung, practice)


func _on_quit_to_title() -> void:
	if session.is_online():
		leave_coop()
	else:
		show_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and profile != null:
		save_profile_if_dirty()


func _unhandled_input(event: InputEvent) -> void:
	# Pause from anywhere the player itself doesn't read input (an open
	# panel that left Esc alone, the ID quiz, detention).
	if director != null and not title_screen.visible and not pause_menu.is_open() and event.is_action_pressed(&"pause"):
		open_pause()
		get_viewport().set_input_as_handled()
