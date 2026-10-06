extends Node
## Game root (scenes/main.tscn): owns the SimHost, the UI layers and the
## title / pause / visit-to-visit flow, and swaps one CasinoDirector per
## casino visit.
##
## Command line (after `--`): --practice, --rung=N, --seed=N, --autostart
## (skip the title screen), --autopilot (a bot plays: tools/autopilot.gd;
## implies --autostart), --autopilot-seconds=N (quit after N sim seconds with
## the bot's summary), --speed=N (run the game N times faster). Tests and
## tools can set the same options as vars before adding the node to the tree
## (set parse_args = false to ignore the command line).

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
## The running Autopilot, if any.
var bot: Autopilot

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

## Bumped whenever a run starts or stops, so a visit swap waiting on the
## banner never lands in a run that has since ended.
var _run_token: int = 0
var _swapping: bool = false


func _ready() -> void:
	InputSetup.ensure_actions()
	if parse_args:
		_parse_args()
	if not is_equal_approx(speed, 1.0):
		Engine.time_scale = speed
		Engine.physics_ticks_per_second = roundi(60.0 * speed)
	_build()
	if autostart or autopilot:
		start_game(start_rung, practice)
	else:
		show_title()
	if autopilot:
		bot = Autopilot.new()
		bot.echo = true
		bot.quit_after_seconds = autopilot_seconds
		add_child(bot)
		bot.setup(self)


## Starts a fresh run at `rung` (practice: one floor guard, nothing else).
func start_game(rung: int, practice_mode: bool) -> void:
	_run_token += 1
	_stop_visit()
	visit_banner.dismiss()
	start_rung = clampi(rung, Tuning.TOP_RUNG, Tuning.BOTTOM_RUNG)
	practice = practice_mode
	var seed_value: int = run_seed if run_seed != 0 else hash([Time.get_ticks_usec(), Time.get_unix_time_from_system()])
	host.start_run(start_rung, seed_value, {LOCAL_PID: PLAYER_NAME})
	title_screen.visible = false
	hud.visible = true
	_begin_visit()


func show_title() -> void:
	_run_token += 1
	_stop_visit()
	hud.visible = false
	visit_banner.dismiss()
	title_screen.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if title_screen.is_inside_tree():
		title_screen.start_button.grab_focus()


func open_pause() -> void:
	if director == null or pause_menu.is_open() or title_screen.visible:
		return
	director.input_blocked = true
	director.sync_input(true)
	host.paused = true
	get_tree().paused = true
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
	menu_layer.add_child(visit_banner)
	menu_layer.add_child(pause_menu)
	menu_layer.add_child(title_screen)
	for c: Control in [hud, bet_panel, quiz_panel, cashier_panel, wardrobe_panel, forger_panel, debug_overlay, visit_banner, pause_menu]:
		c.call(&"setup", host, LOCAL_PID)
	title_screen.setup(host, LOCAL_PID)
	pause_menu.visible = false

	# After the banner's own handler (connected in setup above).
	host.sim_event.connect(_on_sim_event)
	title_screen.start_requested.connect(start_game)
	title_screen.quit_requested.connect(func() -> void: get_tree().quit())
	pause_menu.resume_requested.connect(close_pause)
	pause_menu.restart_requested.connect(_on_restart)
	pause_menu.quit_to_title_requested.connect(_on_quit_to_title)


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


# --- Visits -----------------------------------------------------------------

func _begin_visit() -> void:
	host.start_visit()
	director = CasinoDirector.new()
	world.add_child(director)
	director.setup(host, host.run.rung, practice, {
		"hud": hud, "bet_panel": bet_panel, "quiz_panel": quiz_panel, "cashier_panel": cashier_panel,
		"wardrobe_panel": wardrobe_panel, "forger_panel": forger_panel, "visit_banner": visit_banner,
		"debug_overlay": debug_overlay,
	})
	director.visit_finished.connect(_on_visit_finished)
	director.pause_requested.connect(open_pause)
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
		visit_banner.show_run_summary()
		await visit_banner.closed
		if token == _run_token:
			show_title()
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
	if kind == &"thrown_out" and visit_banner.is_open():
		visit_banner.route_label.text = "%s threw you out  >>  %s" % [
			str(CasinoLadder.casino(int(data.get("from", 0))).get("name", "")),
			str(CasinoLadder.casino(int(data.get("to", 0))).get("name", "")),
		]


func _on_restart() -> void:
	start_game(start_rung, practice)


func _on_quit_to_title() -> void:
	show_title()


func _unhandled_input(event: InputEvent) -> void:
	# Pause from anywhere the player itself doesn't read input (an open
	# panel that left Esc alone, the ID quiz, detention).
	if director != null and not title_screen.visible and not pause_menu.is_open() and event.is_action_pressed(&"pause"):
		open_pause()
		get_viewport().set_input_as_handled()
