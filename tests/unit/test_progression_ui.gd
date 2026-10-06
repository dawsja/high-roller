extends TestCase
## Progression in the world and the UI: the emote key plays unlocked emote
## poses (and a teammate's puppet shows them), the unlocks and leaderboard
## screens, the gift shop's locked rows, the title buttons and the run summary.

var _nodes: Array[Node] = []
var _world: Node3D


func before_each() -> void:
	InputSetup.ensure_actions()
	_world = Node3D.new()
	_world.name = "ProgressionTestWorld"
	tree.root.add_child(_world)
	_nodes.append(_world)
	var floor := Primitives.static_box(Vector3(30, 1, 30), Color.DIM_GRAY)
	floor.position = Vector3(0, -0.5, 0)
	_world.add_child(floor)


func after_each() -> void:
	for action: StringName in InputSetup.ACTIONS:
		Input.action_release(action)
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _press(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(1)


func _spawn(local: bool = true) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.setup(1 if local else 2, local, null)
	player.position = Vector3(0, 0.05, 0)
	_world.add_child(player)
	await _frames(10)
	return player


func _add(node: Control) -> Control:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


func _host(rung: int = 3) -> SimHost:
	var host := SimHost.new()
	tree.root.add_child(host)
	_nodes.append(host)
	host.start_run(rung, 42, {1: "Ace"})
	host.start_visit()
	host.paused = true
	host.sim.player(1).wallet.add(5000)
	return host


func _profile(banked: int) -> Profile:
	var p := Profile.new()
	p.add_banked(banked)
	return p


# --- Emotes ---------------------------------------------------------------------------

func test_emote_key_plays_the_unlocked_emotes_in_turn() -> void:
	var player := await _spawn()
	var played: Array = []
	player.emoted.connect(func(id: StringName) -> void: played.append(id))
	assert_eq(player.emotes, [&"wave"] as Array[StringName], "the starter emote")
	await _press(&"emote")
	assert_eq(player.model.pose, &"wave", "T plays the emote pose")
	player.set_emotes([&"shrug", &"chip_flip", &"not_an_emote", &"shrug"])
	assert_eq(player.emotes, [&"shrug", &"chip_flip"] as Array[StringName], "unknown and repeated ids dropped")
	await _press(&"emote")
	assert_eq(player.model.pose, &"shrug")
	await _frames(20)
	assert_eq(player.model.pose, &"shrug", "it keeps playing while standing still")
	await _press(&"emote")
	assert_eq(player.model.pose, &"chip_flip")
	assert_true(player.model.get_chip().visible, "the chip comes out")
	await _press(&"emote")
	assert_eq(player.model.pose, &"shrug", "cycles back")
	assert_eq(played, [&"wave", &"shrug", &"chip_flip", &"shrug"])
	Input.action_press(&"move_forward")
	await _frames(20)
	Input.action_release(&"move_forward")
	assert_ne(player.model.pose, &"shrug", "moving cancels the emote")
	assert_false(player.model.get_chip().visible)


func test_emote_runs_out_and_needs_a_free_player() -> void:
	var player := await _spawn()
	assert_true(player.play_emote(&"dance"))
	assert_eq(player.model.pose, &"dance")
	await _frames(int(PlayerCharacter.EMOTE_SECONDS * 60.0) + 10)
	assert_eq(player.model.pose, &"idle", "back to idle after EMOTE_SECONDS")
	assert_false(player.play_emote(&"tackle"), "not an emote")
	player.sit_at(Transform3D(Basis.IDENTITY, Vector3(2, 0, 0)))
	assert_false(player.play_emote(&"wave"), "not while seated")
	await _press(&"emote")
	assert_eq(player.model.pose, &"sit")
	player.stand_up()
	player.set_input_enabled(false)
	await _press(&"emote")
	assert_ne(player.model.pose, &"wave", "no emote with a panel open")


func test_a_teammates_puppet_shows_the_synced_emote() -> void:
	var owner := await _spawn()
	var puppet := PlayerCharacter.new()
	puppet.setup(2, false, null)
	_world.add_child(puppet)
	puppet.make_puppet(Vector3(3, 0, 0))
	owner.enable_net_sync()
	owner.play_emote(&"bow")
	await _frames(2)
	assert_eq(owner.net_pose, &"bow", "the owner publishes the emote pose")
	puppet.net_pose = owner.net_pose
	puppet.net_state = owner.net_state
	puppet.net_position = Vector3(3, 0, 0)
	await _frames(2)
	assert_eq(puppet.model.pose, &"bow", "the puppet plays it")


func test_every_emote_pose_animates_and_only_chip_flip_shows_the_chip() -> void:
	var model := CharacterModel.new()
	for e: StringName in CharacterModel.EMOTES:
		model.set_pose(e)
		var tops: Array[float] = []
		for i in 40:
			model.advance(1.0 / 30.0)
			tops.append(model.get_body_aabb().end.y)
		assert_eq(model.pose, e, "%s loops" % e)
		assert_eq(model.get_chip().visible, e == &"chip_flip", String(e))
		assert_between(tops.max(), 1.0, 2.6, "%s stays person-sized" % e)
		if e == &"bow":
			assert_lt(tops.min(), CharacterModel.HEAD_TOP - 0.25, "bows down")
	model.set_pose(&"chip_flip")
	var heights: Array[float] = []
	for i in 40:
		model.advance(1.0 / 40.0)
		heights.append(model.get_chip().position.y)
	assert_gt(heights.max() - heights.min(), CharacterModel.CHIP_FLIP_HEIGHT * 0.6, "the chip goes up and comes down")
	model.free()


# --- Unlocks screen ---------------------------------------------------------------------

func test_unlocks_panel_lists_previews_and_marks_seen() -> void:
	var panel: UnlocksPanel = _add(UnlocksPanel.new())
	var p := _profile(26_000)
	panel.set_profile(p)
	var closed: Array = []
	panel.closed.connect(func() -> void: closed.append(true))
	panel.open(Unlocks.KIND_PIECE)
	assert_true(panel.is_open())
	assert_eq(panel.rows.size(), Unlocks.ids_of(Unlocks.KIND_PIECE).size(), "one row per piece")
	assert_true(panel.lifetime_label.text.contains("26,000"))
	assert_true(panel.next_label.text.contains("Shoulder Parrot"), panel.next_label.text)
	assert_true(panel.next_label.text.contains("4,000 to go"), panel.next_label.text)
	assert_eq((panel.status_labels[&"eye_patch"] as Label).text, "NEW!")
	assert_true((panel.status_labels[&"gold_tuxedo"] as Label).text.contains("210,000"), "locked rows show what they need")
	assert_true((panel.status_labels[&"gold_tuxedo"] as Label).text.contains("184,000 to go"))
	(panel.rows[&"viking_helmet"] as Button).pressed.emit()
	assert_eq(panel.selected, &"viking_helmet")
	assert_eq(panel.preview_model.get_slot_piece(HR.OutfitSlot.HAT), &"viking_helmet", "the mannequin wears it")
	assert_true(panel.preview_detail_label.text.contains("LOCKED"))
	panel.select(&"eye_patch")
	assert_eq(panel.preview_model.get_slot_piece(HR.OutfitSlot.GLASSES), &"eye_patch")
	assert_eq(panel.preview_model.get_slot_piece(HR.OutfitSlot.HAT), OutfitCatalog.NONE, "one piece at a time")
	assert_false(panel.preview_detail_label.text.contains("LOCKED"))
	(panel.tab_buttons[Unlocks.KIND_EMOTE] as Button).pressed.emit()
	assert_eq(panel.kind, Unlocks.KIND_EMOTE)
	assert_eq(panel.rows.size(), Unlocks.ids_of(Unlocks.KIND_EMOTE).size())
	panel.select(&"chip_flip")
	assert_eq(panel.preview_model.pose, &"chip_flip", "emotes play on the mannequin")
	panel.select(&"silver_screen")
	assert_eq(panel.kind, Unlocks.KIND_NAME_PACK, "selecting switches the list")
	assert_true(panel.preview_detail_label.text.contains("Clark"), panel.preview_detail_label.text)
	await tree.process_frame
	assert_false(p.unseen.is_empty())
	panel.close_button.pressed.emit()
	assert_false(panel.is_open())
	assert_eq(closed.size(), 1)
	assert_true(p.unseen.is_empty(), "closing marks everything seen")


func test_unlocks_panel_with_everything_unlocked() -> void:
	var panel: UnlocksPanel = _add(UnlocksPanel.new())
	panel.set_profile(_profile(10_000_000))
	panel.open()
	assert_true(panel.next_label.text.contains("Everything"))
	assert_almost_eq(panel.progress_bar.value, 1.0)


# --- Leaderboard screen -----------------------------------------------------------------

func test_leaderboard_panel_shows_each_crew_size() -> void:
	var p := Profile.new()
	p.post_score(1200, 1, {"crew": ["Ace"], "date": "2026-10-01 10:00:00", "top_banked": 1000, "top_seconds": 75.0})
	p.post_score(4500, 1, {"crew": ["Ace"], "date": "2026-10-02 10:00:00"})
	for i in 12:
		p.post_score(100 * i, 3, {"crew": ["Ace", "Bea", "Cy"]})
	var panel: LeaderboardPanel = _add(LeaderboardPanel.new())
	panel.set_profile(p)
	panel.highlight_serial = 1
	panel.open(1)
	assert_eq(panel.row_count(), 2)
	assert_false(panel.empty_label.visible)
	var first: Array = panel.rows_box.get_child(0).find_children("*", "Label", true, false)
	assert_eq((first[1] as Label).text, "4,500", "best first")
	assert_true(panel.crew_buttons[2].text.contains("(10)"), "the crew of 3 board is trimmed")
	panel.crew_buttons[2].pressed.emit()
	assert_eq(panel.crew_size, 3)
	assert_eq(panel.row_count(), Profile.LEADERBOARD_SIZE)
	panel.crew_buttons[1].pressed.emit()
	assert_eq(panel.row_count(), 0)
	assert_true(panel.empty_label.visible)
	assert_true(panel.empty_label.text.contains("crew of 2"))
	panel.close_button.pressed.emit()
	assert_false(panel.is_open())
	assert_eq(LeaderboardPanel.crew_name(1), "Solo")
	assert_eq(LeaderboardPanel.crew_name(4), "Crew of 4")


# --- Gift shop ------------------------------------------------------------------------------

func test_gift_shop_greys_locked_pieces_and_sells_unlocked_ones() -> void:
	var host := _host()
	var wardrobe: WardrobePanel = _add(WardrobePanel.new())
	wardrobe.setup(host, 1)
	var p := _profile(3000)
	wardrobe.set_profile(p)
	host.run.set_unlocks(1, p.unlocked_pieces(), p.unlocked_name_packs())
	host.request_enter_zone(1, HR.ZoneType.GIFT_SHOP, &"gift_shop")
	wardrobe.open_mode(WardrobePanel.MODE_GIFT_SHOP)
	wardrobe.select_slot(HR.OutfitSlot.HAT)
	assert_true(wardrobe.buy_buttons.has(&"propeller_beanie"), "an unlocked piece is for sale")
	assert_false(wardrobe.buy_buttons.has(&"viking_helmet"))
	assert_true(wardrobe.locked_labels.has(&"viking_helmet"), "a locked one is greyed out")
	assert_true(wardrobe.locked_labels.has(&"pirate_tricorn"))
	assert_eq(wardrobe.buy_buttons.size(), OutfitCatalog.shop_pieces(HR.OutfitSlot.HAT, p.unlocked_pieces()).size())
	assert_true((wardrobe.locked_labels[&"viking_helmet"] as Label).text.contains("69,000"), "chips still needed")
	(wardrobe.buy_buttons[&"propeller_beanie"] as Button).pressed.emit()
	assert_true(wardrobe.result_label.text.begins_with("Bought"), wardrobe.result_label.text)
	assert_eq(host.sim.player(1).stash.back().get_piece(HR.OutfitSlot.HAT), &"propeller_beanie")
	wardrobe.set_profile(null)
	assert_true(wardrobe.locked_labels.has(&"propeller_beanie"), "no profile: everything locked is locked")


# --- Title, banner -----------------------------------------------------------------------

func test_title_screen_progression_buttons() -> void:
	var title: TitleScreen = _add(TitleScreen.new())
	title.setup(null, 1)
	var asked: Array = []
	title.unlocks_requested.connect(func() -> void: asked.append("unlocks"))
	title.leaderboard_requested.connect(func() -> void: asked.append("leaderboard"))
	title.unlocks_button.pressed.emit()
	title.leaderboard_button.pressed.emit()
	assert_eq(asked, ["unlocks", "leaderboard"])
	title.set_unlock_badge(3)
	assert_eq(title.unlocks_button.text, "Unlocks  (3 new)")
	title.set_unlock_badge(0)
	assert_eq(title.unlocks_button.text, "Unlocks")
	assert_true(title.controls_button.visible and title.host_button.visible and title.join_button.visible, "co-op controls stay")
	assert_true(str(TitleScreen.describe_events(&"emote")["keys"]).contains("T"))


func test_run_summary_shows_rank_and_new_unlocks() -> void:
	var banner: VisitBanner = _add(VisitBanner.new())
	banner.setup(null, 1)
	banner.show_run_summary({"score": 30_000, "top_banked": 28_000, "top_seconds": 130.0, "visits": 4,
		"rank": 1, "crew_size": 2, "unlocks": [&"shrug", "propeller_beanie"]})
	assert_true(banner.route_label.text.contains("30,000"))
	assert_true(banner.rank_label.visible)
	assert_eq(banner.rank_label.text, "NEW BEST!  #1 on your crew of 2 leaderboard.")
	assert_true(banner.unlocks_label.visible)
	assert_eq(banner.unlocks_label.text, "NEW UNLOCKS: Shrug, Propeller Beanie")
	banner.continue_button.pressed.emit()
	banner.show_run_summary({"score": 10, "rank": 4, "crew_size": 1})
	assert_eq(banner.rank_label.text, "#4 on your solo leaderboard.")
	assert_false(banner.unlocks_label.visible)
	banner.show_run_summary({"score": 10, "rank": 0, "crew_size": 1})
	assert_true(banner.rank_label.text.contains("top 10"))
	banner.show_run_summary({"score": 10, "practice": true, "rank": 0})
	assert_true(banner.rank_label.text.begins_with("Practice"))
	banner.show_climbed(2, 1, 100)
	assert_false(banner.rank_label.visible, "only on the summary")
	assert_false(banner.unlocks_label.visible)
