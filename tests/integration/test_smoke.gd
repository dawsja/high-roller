extends TestCase
## The whole game from scenes/main.tscn: autostart a visit, walk the player
## around for a while, and make sure nothing errors (tools/test.sh fails the
## run on any SCRIPT ERROR / ERROR line).

const WALK: Array[StringName] = [&"move_forward", &"move_left", &"move_back", &"move_right"]

var _main: Node
var _ticks: int = 60
var _time_scale: float = 1.0


func before_each() -> void:
	_ticks = Engine.physics_ticks_per_second
	_time_scale = Engine.time_scale


func after_each() -> void:
	for action: StringName in WALK + [&"run", &"jump"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	_main = null
	tree.paused = false
	Engine.physics_ticks_per_second = _ticks
	Engine.time_scale = _time_scale
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tree.process_frame
	await tree.physics_frame


func _launch(rung: int, practice: bool) -> CasinoDirector:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.set(&"parse_args", false)
	_main.set(&"autostart", true)
	_main.set(&"start_rung", rung)
	_main.set(&"practice", practice)
	_main.set(&"run_seed", 99)
	tree.root.add_child(_main)
	return _main.get(&"director")


func test_main_scene_is_the_run_main_scene() -> void:
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://scenes/main.tscn")
	var scene: PackedScene = load("res://scenes/main.tscn")
	assert_not_null(scene)


func test_title_screen_then_start() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.set(&"parse_args", false)
	tree.root.add_child(_main)
	await tree.process_frame
	var title: TitleScreen = _main.get(&"title_screen")
	assert_true(title.visible, "the game opens on the title screen")
	assert_null(_main.get(&"director"))
	title.start_requested.emit(Tuning.BOTTOM_RUNG, true)
	var director: CasinoDirector = _main.get(&"director")
	assert_not_null(director, "start builds a visit")
	assert_false(title.visible)
	assert_eq(director.casino["id"], &"sals_back_room")
	assert_true(director.practice)


func test_walk_around_for_600_frames() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var director := _launch(Tuning.BOTTOM_RUNG, true)
	assert_not_null(director)
	var player := director.player
	var start := player.global_position
	var moved := 0.0
	var last := start
	for i in 600:
		if i % 75 == 0:
			for action: StringName in WALK:
				Input.action_release(action)
			Input.action_press(WALK[(i / 75) % WALK.size()])
		if i % 150 == 0:
			Input.action_press(&"run")
		elif i % 150 == 90:
			Input.action_release(&"run")
		await tree.physics_frame
		moved += player.global_position.distance_to(last)
		last = player.global_position
	assert_true(director.npcs_active, "guards and patrons are running")
	assert_gt(moved, 5.0, "the player walked around")
	assert_true(is_instance_valid(director) and director.is_inside_tree())
	var hud: Hud = _main.get(&"hud")
	assert_true(hud.visible)


func test_apex_runs_for_a_while() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var director := _launch(Tuning.TOP_RUNG, false)
	Input.action_press(&"move_forward")
	for i in 240:
		await tree.physics_frame
	Input.action_release(&"move_forward")
	assert_true(director.npcs_active)
	assert_gt(director.guards.size(), 8)


func test_pause_menu_pauses_the_sim() -> void:
	var director := _launch(Tuning.BOTTOM_RUNG, true)
	await tree.physics_frame
	director.pause_requested.emit()
	var host: SimHost = _main.get(&"host")
	var pause: PauseMenu = _main.get(&"pause_menu")
	assert_true(pause.is_open())
	assert_true(host.paused)
	assert_true(tree.paused)
	var clock: float = host.run.visit_seconds
	await tree.physics_frame
	await tree.physics_frame
	assert_eq(host.run.visit_seconds, clock, "no sim ticks while paused")
	pause.resume()
	assert_false(tree.paused)
	assert_false(host.paused)
	assert_false(pause.is_open())
	pause.restart_requested.emit()
	assert_ne(_main.get(&"director"), director, "restart builds a new visit")


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.physics_frame
	return bool(cond.call())


func test_thrown_out_moves_the_crew_down_a_rung() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var director := _launch(5, false)
	var host: SimHost = _main.get(&"host")
	var banner: VisitBanner = _main.get(&"visit_banner")
	for strike in 3:
		host.request_caught(1)
		host.request_reach_back_room(1)
		if strike < 2:
			host.current_sim().tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
	assert_true(director.finished)
	assert_true(banner.is_open(), "the thrown-out card is up")
	assert_true(banner.route_label.text.contains("threw you out"))
	assert_true(await _until(func() -> bool: return director.outcome == &"thrown_out" and director._finish_emitted, 200))
	assert_eq(_main.get(&"director"), director, "the old visit stays up behind the banner")
	banner.dismiss()
	var next: CasinoDirector = _main.get(&"director")
	assert_ne(next, director, "dismissing the banner starts the next visit")
	assert_eq(next.rung, 6)
	assert_eq(host.run.rung, 6)


func test_exit_climbs_when_the_bank_covers_the_buy_in() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var director := _launch(Tuning.BOTTOM_RUNG, true)
	var host: SimHost = _main.get(&"host")
	var exit_it: Interactable = director.map.interactables_of(&"exit")[0]
	director.player.teleport(director.map.to_global(director.map.exit_point))
	assert_true(await _until(func() -> bool: return host.current_sim().player(1).zone == HR.ZoneType.EXIT, 30), "on the exit pad")
	director.interact(1, exit_it)
	assert_false(director.finished, "no climb without the buy-in")
	var hud: Hud = _main.get(&"hud")
	assert_true(hud.notification_texts()[0].contains("Bank"), "the HUD says why")
	host.run.add_bank(CasinoLadder.buy_in_to_leave(Tuning.BOTTOM_RUNG))
	director.interact(1, exit_it)
	assert_true(director.finished)
	assert_eq(host.run.rung, Tuning.BOTTOM_RUNG - 1)
	var banner: VisitBanner = _main.get(&"visit_banner")
	assert_true(await _until(func() -> bool: return director._finish_emitted, 200))
	banner.dismiss()
	var next: CasinoDirector = _main.get(&"director")
	assert_ne(next, director)
	assert_eq(next.casino["id"], &"rusty_spur")
