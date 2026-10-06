extends TestCase
## Plays the real game (scenes/main.tscn) with the Autopilot bot from
## tools/autopilot.gd, headless at 8x speed (the physics step stays 1/60 s).
## The bot only presses input actions and uses the UI panels, so this walks
## the whole stack: navmesh walking, tables and the bet panel, Heat, dealer
## swaps, guards, ID quizzes, the cashier, the restroom, getting caught, the
## exit and the next visit. Its watchdogs (stuck walking, panels left open,
## ID checks that never resolve, guards that never give up, a HUD out of step
## with the sim, visits that don't transition) must stay quiet, and
## tools/test.sh fails on any script error.

const SPEED := 8.0
## Wall-clock caps, so a broken run fails instead of hanging the suite.
const PRACTICE_WALL_MS := 50000
const APEX_WALL_MS := 30000

var _main: Node
var _bot: Autopilot
var _ticks: int = 60
var _time_scale: float = 1.0


func before_each() -> void:
	_ticks = Engine.physics_ticks_per_second
	_time_scale = Engine.time_scale
	InputSetup.ensure_actions()


func after_each() -> void:
	if _bot != null and is_instance_valid(_bot):
		_bot.stop()
	_bot = null
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	_main = null
	tree.paused = false
	Engine.physics_ticks_per_second = _ticks
	Engine.time_scale = _time_scale
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tree.process_frame
	await tree.physics_frame


func _launch(rung: int, practice: bool, seed_value: int) -> Autopilot:
	Engine.physics_ticks_per_second = roundi(60.0 * SPEED)
	Engine.time_scale = SPEED
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.set(&"parse_args", false)
	_main.set(&"autostart", true)
	_main.set(&"start_rung", rung)
	_main.set(&"practice", practice)
	_main.set(&"run_seed", seed_value)
	tree.root.add_child(_main)
	_bot = Autopilot.new()
	_bot.rng.seed = seed_value
	_main.add_child(_bot)
	_bot.setup(_main)
	return _bot


## Runs until cond() holds, the bot has played `max_sim` sim seconds, or the
## wall clock runs out. Returns whether cond() held.
func _play_until(cond: Callable, max_sim: float, max_wall_ms: int) -> bool:
	var started := Time.get_ticks_msec()
	while not cond.call():
		if _bot.sim_seconds >= max_sim or Time.get_ticks_msec() - started > max_wall_ms:
			break
		await tree.physics_frame
	return bool(cond.call())


func _report(title: String) -> void:
	print("\n--- %s: %d timeline lines, %.0f sim s ---" % [title, _bot.timeline.size(), _bot.sim_seconds])
	var milestones := _bot.timeline.filter(func(l: String) -> bool:
		return ["VISIT", "LEVEL", "DEALER SWAP", "ID CHECK", "ID result", "CAUGHT", "DETAINED", "STRIKE", "BANKED",
			"CLIMBED", "THROWN", "CURB", "withdraw", "changed outfit", "ANOMALY", "(you)"].any(func(k: String) -> bool: return l.contains(k)))
	for line: String in milestones.slice(0, 60):
		print(line)
	print(_bot.summary())


func _hud_said(text: String) -> bool:
	return _bot.timeline.any(func(l: String) -> bool: return l.contains("hud: ") and l.contains(text))


func test_practice_run_at_sals_plays_to_a_climb() -> void:
	var bot := _launch(Tuning.BOTTOM_RUNG, true, 5)
	# Press on through Suspected so the one sleepy guard has time to walk over.
	bot.greed = 1.0
	bot.min_play_seconds = 60.0
	var s := bot.stats
	var done := await _play_until(func() -> bool:
		var engaged: bool = int(s["id_checks"]) + int(s["chases"]) > 0
		var left: bool = int(s["climbs"]) + int(s["curbs"]) > 0
		return engaged and left and int(s["banked"]) > 0, 420.0, PRACTICE_WALL_MS)
	_report("practice at Sal's")
	assert_true(done, "the run reached a climb (or curb) with a check or chase on the way")
	assert_gt(s["bets"], 5, "bet repeatedly through the bet panel")
	assert_gt(s["wins"], s["losses"], "85% tables")
	assert_gte(s["dealer_swaps"], 1, "Watched at a table swaps the dealer")
	assert_gte(s["sits"], 3, "left swapped tables for others")
	assert_gt(s["banked"], 0, "banked chips at the cashier")
	assert_gte(int(s["id_checks"]) + int(s["chases"]), 1, "a guard checked or chased")
	assert_gte(int(s["climbs"]) + int(s["curbs"]), 1, "climbed out (or sat out a curb timeout)")
	assert_gt(float(s["max_heat"]), Tuning.SUSPECTED_AT, "Heat climbed past Suspected")
	assert_true(_hud_said("Dealer swap"), "the dealer swap reached the HUD")
	assert_true(_hud_said("Banked"), "the cash-out reached the HUD")
	if int(s["climbs"]) > 0:
		# The banner closes, the next casino is built and the bot plays on there.
		var bets_before: int = s["bets"]
		var next := await _play_until(func() -> bool: return bot.visits > 1 and int(s["bets"]) > bets_before + 1, bot.sim_seconds + 90.0, 20000)
		assert_true(next, "the climb started the next visit and the bot bet there")
		assert_lt(int(_main.get(&"host").run.rung), Tuning.BOTTOM_RUNG)
		print(_bot.timeline.filter(func(l: String) -> bool: return l.contains("VISIT")))
	assert_eq(bot.anomalies, [] as Array[String], "watchdogs stayed quiet")


func test_apex_guards_engage() -> void:
	var bot := _launch(Tuning.TOP_RUNG, false, 7)
	var s := bot.stats
	var done := await _play_until(func() -> bool:
		return int(s["engagements"]) > 0 and int(s["bets"]) >= 3, 180.0, APEX_WALL_MS)
	_report("The Apex")
	assert_true(done, "a guard came for the bot")
	var director: CasinoDirector = _main.get(&"director")
	assert_gt(director.guards.size(), 8, "every security type is on the floor")
	assert_gt(director.cameras.size(), 0)
	assert_gte(s["bets"], 3)
	assert_gte(s["engagements"], 1, "a guard walked over or gave chase")
	assert_eq(bot.anomalies, [] as Array[String], "watchdogs stayed quiet")
