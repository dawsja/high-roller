extends TestCase
## main.gd's progression wiring in the real game scene: the profile loads at
## boot, the local player's banked chips unlock things (announced, applied to
## the run and the player, saved), the run's score goes on the local board for
## its crew size when the run ends, and the title opens the unlocks and
## leaderboard screens.

var _main: Node
var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_progression_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_dir)


func after_each() -> void:
	if _main != null and is_instance_valid(_main):
		_main.queue_free()
	_main = null
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tree.process_frame
	await tree.physics_frame
	if DirAccess.dir_exists_absolute(_dir):
		for f: String in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)


func _path() -> String:
	return _dir.path_join("profile.json")


func _launch(profile_path: String, autostart: bool = true, rung: int = Tuning.TOP_RUNG, practice: bool = false) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	_main = scene.instantiate()
	_main.set(&"parse_args", false)
	_main.set(&"profile_path", profile_path)
	_main.set(&"autostart", autostart)
	_main.set(&"start_rung", rung)
	_main.set(&"practice", practice)
	_main.set(&"run_seed", 5)
	tree.root.add_child(_main)
	await _frames(3)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _host() -> SimHost:
	return _main.get(&"host")


func _profile() -> Profile:
	return _main.get(&"profile")


## Cashes `amount` out for the local player at the cashier.
func _bank(amount: int) -> Dictionary:
	var host := _host()
	host.sim.player(1).wallet.add(amount)
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cashier")
	return host.request_cash_out(1, amount)


func _end_run() -> VisitBanner:
	var director: CasinoDirector = _main.get(&"director")
	director.visit_finished.emit(CasinoDirector.OUTCOME_RUN_OVER)
	await tree.process_frame
	return _main.get(&"visit_banner")


func test_banking_unlocks_and_the_run_end_posts_the_score() -> void:
	await _launch(_path())
	assert_not_null(_main.get(&"profile_store"), "a profile path saves to disk")
	assert_eq(_profile().lifetime_banked, 0, "no file yet: a fresh profile")
	var res := _bank(5000)
	assert_true(bool(res["ok"]), str(res))
	assert_eq(_profile().lifetime_banked, 5000, "the local player's banked chips count")
	assert_eq(_main.get(&"run_unlocks"), [&"shrug", &"propeller_beanie", &"bell_bottoms"] as Array[StringName])
	assert_eq(_host().run.unlocked_pieces(1), [&"propeller_beanie", &"bell_bottoms"] as Array[StringName], "the gift shop can sell them now")
	var director: CasinoDirector = _main.get(&"director")
	assert_eq(director.player.emotes, [&"wave", &"shrug"] as Array[StringName], "the new emote is on the T key")
	assert_eq(ProfileStore.new(_path()).load_profile().lifetime_banked, 5000, "an unlock saves at once")
	# A pocket gift-shop purchase of the unlocked piece works end to end.
	_host().request_enter_zone(1, HR.ZoneType.GIFT_SHOP, &"gift_shop")
	assert_true(bool(_host().request_buy_outfit_piece(1, HR.OutfitSlot.HAT, &"propeller_beanie")["ok"]))

	var score: int = _host().run.score()
	assert_eq(score, 5000, "banked at The Apex")
	var banner := await _end_run()
	assert_true(banner.is_open())
	assert_eq(banner.kind, VisitBanner.KIND_SUMMARY)
	assert_true(banner.route_label.text.contains("5,000"))
	assert_eq(banner.rank_label.text, "NEW BEST!  #1 on your solo leaderboard.")
	assert_true(banner.unlocks_label.text.contains("Propeller Beanie"), banner.unlocks_label.text)
	var board := _profile().leaderboard(1)
	assert_eq(board.size(), 1)
	assert_eq(int(board[0]["score"]), score)
	assert_eq(board[0]["crew"], ["You"], "main.gd's single-player name")
	assert_eq(_profile().runs, 1)
	var saved := ProfileStore.new(_path()).load_profile()
	assert_eq(saved.leaderboard(1).size(), 1, "saved at the end of the run")
	assert_eq(saved.runs, 1)
	var board_panel: LeaderboardPanel = _main.get(&"leaderboard_panel")
	assert_eq(board_panel.highlight_serial, _profile().last_serial, "the new entry is highlighted")
	banner.continue_button.pressed.emit()
	await tree.process_frame
	var title: TitleScreen = _main.get(&"title_screen")
	assert_true(title.visible, "back to the title")
	assert_eq(title.unlocks_button.text, "Unlocks  (3 new)")


func test_practice_runs_are_not_posted() -> void:
	await _launch(_path(), true, Tuning.BOTTOM_RUNG, true)
	_bank(300)
	assert_eq(_profile().lifetime_banked, 300, "practice banking still counts")
	var banner := await _end_run()
	assert_true(banner.rank_label.text.begins_with("Practice"))
	assert_true(_profile().leaderboard(1).is_empty())
	assert_eq(_profile().runs, 1)


func test_profile_loads_at_boot_and_a_corrupt_file_is_set_aside() -> void:
	var p := Profile.new()
	p.add_banked(20_000)
	p.record_run(777, 2, {"crew": ["Ace", "Bea"]})
	assert_true(ProfileStore.new(_path()).save(p))
	await _launch(_path(), false)
	assert_eq(_profile().lifetime_banked, 20_000)
	assert_eq(_profile().leaderboard(2).size(), 1)
	var title: TitleScreen = _main.get(&"title_screen")
	assert_eq(title.unlocks_button.text, "Unlocks  (%d new)" % p.unseen.size())
	_main.queue_free()
	_main = null
	await tree.process_frame
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_string("{ definitely not a profile")
	f.close()
	await _launch(_path(), false)
	assert_eq(_profile().lifetime_banked, 0, "a fresh profile instead of a crash")
	assert_true(FileAccess.file_exists(_path() + ".corrupt"), "the bad file is kept aside")


func test_tests_and_tools_keep_the_profile_in_memory() -> void:
	await _launch("")
	assert_null(_main.get(&"profile_store"))
	_bank(1500)
	assert_eq(_profile().lifetime_banked, 1500)
	assert_true(_main.call(&"save_profile"), "nothing to write")


func test_title_opens_unlocks_and_leaderboard() -> void:
	var p := Profile.new()
	p.add_banked(9000)
	ProfileStore.new(_path()).save(p)
	await _launch(_path(), false)
	var title: TitleScreen = _main.get(&"title_screen")
	var unlocks: UnlocksPanel = _main.get(&"unlocks_panel")
	var board: LeaderboardPanel = _main.get(&"leaderboard_panel")
	title.unlocks_button.pressed.emit()
	assert_true(unlocks.is_open())
	assert_eq(unlocks.profile, _profile())
	unlocks.close_button.pressed.emit()
	assert_false(unlocks.is_open())
	assert_eq(title.unlocks_button.text, "Unlocks", "seen")
	assert_true(ProfileStore.new(_path()).load_profile().unseen.is_empty(), "saved as seen")
	title.leaderboard_button.pressed.emit()
	assert_true(board.is_open())
	board.close_button.pressed.emit()
	assert_false(board.is_open())


func test_a_clients_unlocks_reach_the_hosts_run() -> void:
	await _launch("")
	var host := _host()
	host.world_message.emit(&"unlocks", {"pieces": ["viking_helmet", "hawaiian_shirt"], "name_packs": ["space_age"]}, 7)
	assert_eq(host.run.unlocked_pieces(7), [&"viking_helmet"] as Array[StringName])
	assert_eq(host.run.name_packs(7), [&"space_age"] as Array[StringName])
	host.world_message.emit(&"unlocks", {"pieces": ["eye_patch"]}, 1)
	assert_false(host.run.unlocked_pieces(1).has(&"eye_patch"), "nobody speaks for the host")
	host.world_message.emit(&"unlocks", {"pieces": "garbage", "name_packs": 5}, 8)
	assert_true(host.run.unlocked_pieces(8).is_empty())
