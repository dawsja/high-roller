extends TestCase
## UI panels against a real SimHost: they react to sim events and their
## buttons call the right requests.

var _nodes: Array[Node] = []
var _signals: Array = []


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame


## A paused host at `rung` with a visit and one table of every kind used here.
func _host(rung: int = 3, crew: Dictionary = {1: "Ace"}) -> SimHost:
	var host := SimHost.new()
	tree.root.add_child(host)
	_nodes.append(host)
	host.start_run(rung, 42, crew)
	host.start_visit()
	host.paused = true
	# Panels are tested with the Apex starting pocket (more than this casino's max bet).
	for pid: int in crew:
		var wallet: Wallet = host.sim.player(pid).wallet
		wallet.add(Tuning.START_CHIPS - wallet.pocket)
	host.request_register_table(&"slots_1", HR.GameType.SLOTS, &"slots_a")
	host.request_register_table(&"hl_1", HR.GameType.HIGH_LOW, &"tables_a")
	host.request_register_table(&"bj_1", HR.GameType.BLACKJACK, &"tables_a")
	host.request_register_table(&"rou_1", HR.GameType.ROULETTE, &"tables_a")
	return host


func _add(node: Control, host: SimHost, pid: int = 1) -> Control:
	tree.root.add_child(node)
	_nodes.append(node)
	node.call(&"setup", host, pid)
	return node


func _record(sig: Signal, tag: String) -> void:
	sig.connect(func(a: Variant = null, b: Variant = null) -> void: _signals.append([tag, a, b]))


func _recorded(tag: String) -> Array:
	return _signals.filter(func(e: Array) -> bool: return e[0] == tag)


func _me(host: SimHost) -> Dictionary:
	return UiTheme.player_snapshot(host, 1)


# --- Theme ------------------------------------------------------------------

func test_theme_and_helpers() -> void:
	var t := UiTheme.make_theme()
	assert_not_null(t)
	assert_true(t == UiTheme.make_theme(), "cached")
	for v: StringName in [&"TitleLabel", &"HeaderLabel", &"HudPanel", &"CardPanel", &"RedButton", &"GreenButton"]:
		assert_ne(t.get_type_variation_base(v), &"", "variation %s" % v)
	assert_eq(UiTheme.chips(12345), "12,345")
	assert_eq(UiTheme.chips(-1500), "-1,500")
	assert_eq(UiTheme.chips(999), "999")
	assert_eq(UiTheme.clock(125.4), "02:05")
	assert_eq(UiTheme.high_low_card(14), "A")
	assert_eq(UiTheme.blackjack_card(11), "A")
	var colors: Array = []
	for level: int in HR.HeatLevel.values():
		colors.append(UiTheme.heat_color(level))
	assert_eq(colors.size(), 4)
	for i in 3:
		assert_ne(colors[i], colors[i + 1], "levels have distinct colors")
	assert_true(UiTheme.is_passive_heat(HeatRules.CAMPING))
	assert_false(UiTheme.is_passive_heat(HeatRules.WIN))
	assert_ne(UiTheme.reason_text(FloorSim.NOT_ENOUGH), "")


# --- HUD --------------------------------------------------------------------

func test_hud_shows_run_and_player() -> void:
	var host := _host()
	var hud: Hud = _add(Hud.new(), host)
	assert_eq(hud.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	assert_eq(hud.casino_label.text, "The Riverboat Queen")
	assert_eq(hud.rung_label.text, "Rung 3 of 6")
	assert_eq(hud.pocket_label.text, UiTheme.chips(Tuning.START_CHIPS))
	assert_eq(hud.strike_icons.size(), Tuning.STRIKES_TO_THROW_OUT)
	assert_eq(hud.id_name_label.text, host.sim.player(1).current_id().name)
	assert_true(hud.bank_bar.visible, "progress toward the buy-in below the top")
	hud.set_prompt("Sit at Roulette")
	assert_true(hud.prompt_panel.visible)
	assert_eq(hud.prompt_label.text, "Sit at Roulette")
	hud.set_prompt("")
	assert_false(hud.prompt_panel.visible)


func test_hud_heat_meter_follows_events() -> void:
	var host := _host()
	var hud: Hud = _add(Hud.new(), host)
	host.request_sit(1, &"slots_1")
	host.request_place_bet(1, &"slots_1", 50, {"throw": false})
	var heat: float = host.sim.player(1).heat.value
	assert_almost_eq(hud.heat_value(), heat, 0.001, "heat events update the meter right away")
	host.sim.player(1).heat.add(90.0, HeatRules.WIN)
	assert_eq(hud.heat_level(), HR.HeatLevel.WANTED)
	assert_eq(hud.heat_level_label.text, "WANTED")
	assert_true(hud.banner_label.visible, "Wanted banner")
	assert_true(hud.notification_texts().any(func(t: String) -> bool: return t.contains("poster")), "poster printed in the feed")
	hud.advance(0.05)
	assert_eq(hud.heat_panel.scale.x > 1.0, true, "pulses after a rise")
	hud.advance(Tuning.UI_BANNER_SECONDS + 1.0)
	assert_false(hud.banner_label.visible, "banner fades out")


func test_hud_feed_banner_and_fade() -> void:
	var host := _host()
	var hud: Hud = _add(Hud.new(), host)
	hud.show_banner("JACKPOT", UiTheme.GOLD, 1.0)
	assert_true(hud.banner_label.visible)
	assert_eq(hud.banner_label.text, "JACKPOT")
	for i in Tuning.UI_NOTIFY_MAX + 3:
		hud.push_notification("note %d" % i)
	assert_eq(hud.feed.get_child_count(), Tuning.UI_NOTIFY_MAX, "feed is capped")
	assert_eq(hud.notification_texts()[0], "note %d" % (Tuning.UI_NOTIFY_MAX + 2), "newest first")
	hud.advance(Tuning.UI_NOTIFY_SECONDS + 0.1)
	assert_eq(hud.feed.get_child_count(), 0, "entries fade away")
	assert_false(hud.banner_label.visible)
	# Key events land in the feed.
	host.request_distraction(1, HR.Distraction.FIRE_ALARM)
	assert_true(hud.notification_texts().any(func(t: String) -> bool: return t.contains("Fire alarm")))
	host.sim.tick(Tuning.FORGER_MOVE_SECONDS + 0.1)
	assert_true(hud.notification_texts().any(func(t: String) -> bool: return t.contains("forger")))


func test_hud_status_line_and_strikes() -> void:
	var host := _host()
	var hud: Hud = _add(Hud.new(), host)
	host.request_start_id_check(1, 3)
	assert_false(hud.id_name_label.visible, "the ID card is hidden during the quiz")
	host.request_answer_id_check(1, 0)
	assert_true(hud.id_name_label.visible)
	host.request_caught(1, 3)
	assert_true(hud.status_label.visible)
	assert_true(hud.status_label.text.contains("MASH SPACE"))
	host.request_reach_back_room(1)
	assert_true(hud.status_label.text.contains("DETAINED"))
	assert_true(hud.notification_texts().any(func(t: String) -> bool: return t.contains("STRIKE 1")))
	var lit := hud.strike_icons.filter(func(p: Panel) -> bool: return (p.get_child(0) as Label).modulate.a > 0.9)
	assert_eq(lit.size(), 1, "one strike icon lit")
	assert_true(hud.id_badge.visible, "burned badge")
	assert_eq(hud.id_badge_label.text, "BURNED")


func test_hud_at_the_top_shows_score() -> void:
	var host := _host(Tuning.TOP_RUNG)
	var hud: Hud = _add(Hud.new(), host)
	assert_true(hud.clock_label.text.begins_with("SCORE"))
	assert_false(hud.bank_bar.visible)


# --- Bet panel ----------------------------------------------------------------

func test_bet_panel_slots_bet() -> void:
	var host := _host()
	var panel: BetPanel = _add(BetPanel.new(), host)
	_record(panel.bet_resolved, "bet")
	assert_true(bool(host.request_sit(1, &"slots_1")["ok"]))
	panel.open_for_table(&"slots_1", HR.GameType.SLOTS)
	assert_true(panel.is_open())
	assert_eq(panel.bet_amount, 50, "starts at the casino min")
	panel.set_bet_amount(1_000_000)
	assert_eq(panel.bet_amount, 500, "clamped to the max bet")
	panel.set_bet_amount(1)
	assert_eq(panel.bet_amount, 50, "clamped to the min bet")
	panel.set_bet_amount(100)
	panel.main_button.pressed.emit()
	assert_eq(_recorded("bet").size(), 1)
	var result: Dictionary = _recorded("bet")[0][1]
	assert_eq(int(result["game_type"]), HR.GameType.SLOTS)
	assert_eq(int(result["bet"]), 100)
	assert_eq(_me(host)["pocket"], Tuning.START_CHIPS - 100 + int(result["payout"]))
	assert_true(panel.result_label.text.begins_with("WIN") or panel.result_label.text.begins_with("LOSS") or panel.result_label.text.begins_with("JACKPOT"))
	assert_true(panel.is_locked(), "locked while the reels spin")
	assert_true(panel.main_button.disabled)
	panel.main_button.pressed.emit()
	assert_eq(_recorded("bet").size(), 1, "no bet while locked")
	panel.advance(float(Tuning.GAMES[HR.GameType.SLOTS]["round_seconds"]) * Tuning.UI_RESULT_LOCK_SHARE + 0.05)
	assert_false(panel.is_locked())
	assert_false(panel.main_button.disabled)
	# Throw it: loses on purpose.
	panel.throw_toggle.button_pressed = true
	assert_true(panel.handle_key(KEY_SPACE))
	var thrown: Dictionary = _recorded("bet")[1][1]
	assert_true(bool(thrown["intentional_loss"]))
	assert_true(panel.result_label.text.begins_with("THROWN"))


func test_bet_panel_roulette_choices() -> void:
	var host := _host()
	var panel: BetPanel = _add(BetPanel.new(), host)
	_record(panel.bet_resolved, "bet")
	host.request_sit(1, &"rou_1")
	panel.open_for_table(&"rou_1", HR.GameType.ROULETTE)
	assert_true(panel.number_spin.visible)
	panel.choice_buttons[1].pressed.emit()
	panel.press_main()
	var r1: Dictionary = _recorded("bet")[0][1]
	assert_eq(str(r1["detail"]["kind"]), "color")
	assert_eq(str(r1["detail"]["pick"]), "black")
	panel.notify_result_shown()
	panel.number_spin.value = 7
	panel.press_main()
	var r2: Dictionary = _recorded("bet")[1][1]
	assert_eq(str(r2["detail"]["kind"]), "number")
	assert_eq(int(r2["detail"]["pick"]), 7)


func test_bet_panel_high_low_run_with_cash_out() -> void:
	var host := _host()
	var panel: BetPanel = _add(BetPanel.new(), host)
	_record(panel.bet_resolved, "bet")
	_record(panel.hand_updated, "hand")
	host.request_sit(1, &"hl_1")
	panel.open_for_table(&"hl_1", HR.GameType.HIGH_LOW)
	var cashed := false
	for attempt in 12:
		panel.notify_result_shown()
		panel.main_button.pressed.emit()
		assert_false(panel.round_state().is_empty(), "deal starts a run")
		assert_eq(panel.round_state()["kind"], &"high_low")
		panel.choice_buttons[0].pressed.emit()
		if panel.round_state().is_empty():
			continue  # wrong guess: the pot is gone
		assert_true(panel.result_label.text.begins_with("CORRECT"))
		panel.advance(Tuning.UI_HAND_STEP_LOCK_SECONDS + 0.05)
		var pocket_before: int = int(_me(host)["pocket"])
		var pot: int = int(panel.round_state()["pot"])
		assert_true(panel.main_button.text.begins_with("CASH OUT"))
		panel.main_button.pressed.emit()
		assert_true(panel.round_state().is_empty(), "cash out ends the run")
		assert_eq(int(_me(host)["pocket"]), pocket_before + pot)
		var last: Array = _recorded("bet").back()
		assert_true(bool((last[1] as Dictionary)["detail"].get("cash_out", false)))
		cashed = true
		break
	assert_true(cashed, "won a guess and cashed out")
	assert_gte(_recorded("hand").size(), 2.0, "hand_updated on deal and on each winning guess")


func test_bet_panel_blackjack_hand() -> void:
	var host := _host()
	var panel: BetPanel = _add(BetPanel.new(), host)
	_record(panel.bet_resolved, "bet")
	_record(panel.hand_updated, "hand")
	host.request_sit(1, &"bj_1")
	panel.open_for_table(&"bj_1", HR.GameType.BLACKJACK)
	assert_false(panel.throw_toggle.visible, "blackjack throws by hitting past 21")
	assert_true(panel.handle_key(KEY_SPACE), "Space deals")
	var state: Dictionary = panel.round_state()
	assert_eq(state["kind"], &"blackjack")
	assert_eq((state["player_cards"] as Array).size(), 2)
	assert_eq(panel.player_cards_holder.get_child_count(), 2)
	assert_eq(panel.dealer_cards_holder.get_child_count(), 2, "up card plus a face-down card")
	assert_false(panel.choice_buttons[0].disabled, "hit enabled")
	panel.choice_buttons[1].pressed.emit()
	assert_true(panel.round_state().is_empty(), "stand settles the hand")
	assert_eq(_recorded("bet").size(), 1)
	var result: Dictionary = _recorded("bet")[0][1]
	assert_eq(int(result["game_type"]), HR.GameType.BLACKJACK)
	assert_true(panel.is_locked())
	assert_gte(_recorded("hand").size(), 1.0)
	assert_eq(_me(host)["round"], &"")


func test_bet_panel_leave_and_stood_closes() -> void:
	var host := _host()
	var panel: BetPanel = _add(BetPanel.new(), host)
	_record(panel.leave_requested, "leave")
	_record(panel.closed, "closed")
	_record(panel.opened, "opened")
	host.request_sit(1, &"slots_1")
	assert_true(panel.is_open(), "opens itself on seated")
	assert_eq(panel.table_id, &"slots_1")
	assert_eq(panel.game_type, HR.GameType.SLOTS)
	assert_eq(_recorded("opened").size(), 1)
	assert_true(panel.handle_key(KEY_ESCAPE))
	assert_eq(_recorded("leave").size(), 1)
	panel.leave_button.pressed.emit()
	assert_eq(_recorded("leave").size(), 2)
	assert_true(panel.is_open(), "the director stands the player up")
	host.request_stand(1)
	assert_false(panel.is_open(), "closes on stood")
	assert_eq(_recorded("closed").size(), 1)


func test_bet_panel_disabled_during_id_check() -> void:
	var host := _host()
	var panel: BetPanel = _add(BetPanel.new(), host)
	host.request_sit(1, &"slots_1")
	panel.open_for_table(&"slots_1", HR.GameType.SLOTS)
	assert_false(panel.main_button.disabled)
	host.request_start_id_check(1, 1)
	assert_true(panel.main_button.disabled, "no bets mid ID check")
	assert_false(panel.handle_key(KEY_1), "1/2/3 belong to the quiz")
	host.request_answer_id_check(1, 0)
	assert_false(panel.main_button.disabled)


# --- ID quiz ------------------------------------------------------------------

func test_id_quiz_answers_correctly() -> void:
	var host := _host()
	var quiz: IdQuizPanel = _add(IdQuizPanel.new(), host)
	_record(quiz.answered, "answered")
	_record(quiz.closed, "closed")
	var res: Dictionary = host.request_start_id_check(1, 2)
	assert_false(bool(res["auto_fail"]))
	assert_true(quiz.is_open(), "opens on the id_check event")
	assert_true(quiz.is_waiting())
	var q: Dictionary = res["question"]
	assert_true(quiz.prompt_label.text.begins_with("Guard: What's your"))
	var card: FakeId = host.sim.player(1).current_id()
	var correct: int = (q["options"] as Array).find(IdQuiz.answer_for(card, StringName(q["field"])))
	assert_gte(correct, 0.0)
	var texts: Array = quiz.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_false(texts.any(func(t: String) -> bool: return t.contains(card.birthday) and t.contains(card.home_state)), "the card isn't shown")
	quiz.option_buttons[correct].pressed.emit()
	assert_eq(quiz.result_label.text, "PASSED")
	assert_eq(_recorded("answered")[0][1], true)
	assert_eq(int(_me(host)["status"]), HR.PlayerStatus.FREE)
	quiz.advance(Tuning.UI_QUIZ_RESULT_SECONDS + 0.05)
	assert_false(quiz.is_open())
	assert_eq(_recorded("closed").size(), 1)


func test_id_quiz_times_out() -> void:
	var host := _host()
	var quiz: IdQuizPanel = _add(IdQuizPanel.new(), host)
	var results: Array = []
	host.sim_event.connect(func(k: StringName, d: Dictionary) -> void:
		if k == &"id_result":
			results.append(d))
	host.request_start_id_check(1, 2)
	quiz.advance(Tuning.ID_QUIZ_SECONDS * 0.5)
	assert_true(quiz.is_waiting())
	assert_between(quiz.seconds_left(), Tuning.ID_QUIZ_SECONDS * 0.4, Tuning.ID_QUIZ_SECONDS * 0.6)
	quiz.advance(Tuning.ID_QUIZ_SECONDS * 0.5 + 0.05)
	assert_eq(results.size(), 1)
	assert_false(bool(results[0]["passed"]))
	assert_eq(results[0]["reason"], FloorSim.ID_TIMEOUT)
	assert_eq(quiz.result_label.text, "FAILED!")
	assert_true(quiz.reason_label.text.contains(UiTheme.reason_text(FloorSim.ID_TIMEOUT)))
	quiz.advance(Tuning.UI_QUIZ_RESULT_SECONDS + 0.05)
	assert_false(quiz.is_open())


func test_id_quiz_keys_and_auto_fail() -> void:
	var host := _host()
	var quiz: IdQuizPanel = _add(IdQuizPanel.new(), host)
	host.request_start_id_check(1, 2)
	assert_true(quiz.handle_key(KEY_2), "2 answers the second option")
	assert_false(quiz.is_waiting())
	quiz.advance(Tuning.UI_QUIZ_RESULT_SECONDS + 0.05)
	host.sim.player(1).current_id().burn()
	var res: Dictionary = host.request_start_id_check(1, 2)
	assert_true(bool(res["auto_fail"]))
	assert_true(quiz.is_open())
	assert_eq(quiz.result_label.text, "FAILED!")
	assert_true(quiz.reason_label.text.contains("burned"))
	assert_false(quiz.option_buttons[0].visible)


# --- Cashier ------------------------------------------------------------------

func test_cashier_banks_chips() -> void:
	var host := _host()
	var cashier: CashierPanel = _add(CashierPanel.new(), host)
	_record(cashier.cashed_out, "cashed")
	cashier.open()
	cashier.half_button.pressed.emit()
	assert_eq(_recorded("cashed").size(), 0, "not at the cashier yet")
	assert_eq(cashier.result_label.text, UiTheme.reason_text(FloorSim.WRONG_ZONE))
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cashier")
	cashier.refresh()
	var half: int = Tuning.START_CHIPS >> 1
	cashier.half_button.pressed.emit()
	assert_eq(_recorded("cashed").size(), 1)
	assert_eq(host.run.bank, half)
	assert_eq(int(_me(host)["pocket"]), Tuning.START_CHIPS - half)
	assert_true(cashier.result_label.text.begins_with("Banked"))
	cashier.preset_button.pressed.emit()
	assert_eq(host.run.bank, half + Tuning.UI_CASHIER_PRESET)
	cashier.custom_spin.value = 25
	cashier.custom_button.pressed.emit()
	assert_eq(host.run.bank, half + Tuning.UI_CASHIER_PRESET + 25)
	assert_true(cashier.give_button.disabled, "no teammate in single player")
	assert_true(cashier.bank_label.text.contains(UiTheme.chips(host.run.bank)))
	cashier.all_button.pressed.emit()
	assert_eq(int(_me(host)["pocket"]), 0)
	assert_true(cashier.all_button.disabled, "nothing left to bank")
	cashier.close_button.pressed.emit()
	assert_false(cashier.is_open())


func test_cashier_takes_chips_out_of_the_bank() -> void:
	var host := _host()
	var cashier: CashierPanel = _add(CashierPanel.new(), host)
	host.request_enter_zone(1, HR.ZoneType.CASHIER, &"cashier")
	cashier.open()
	assert_true(cashier.withdraw_button.disabled, "nothing banked yet")
	cashier.all_button.pressed.emit()
	var banked: int = host.run.bank
	assert_eq(banked, Tuning.START_CHIPS)
	var max_bet: int = int(host.snapshot()["run"]["max_bet"])
	assert_eq(cashier.withdraw_amount(), mini(banked, Tuning.UI_WITHDRAW_MAX_BETS * max_bet))
	assert_false(cashier.withdraw_button.disabled)
	var take: int = cashier.withdraw_amount()
	cashier.withdraw_button.pressed.emit()
	assert_eq(host.run.bank, banked - take)
	assert_eq(int(_me(host)["pocket"]), take)
	assert_true(cashier.result_label.text.begins_with("Took"))


func test_cashier_hands_chips_to_a_teammate() -> void:
	var host := _host(3, {1: "Ace", 2: "Deuce"})
	var cashier: CashierPanel = _add(CashierPanel.new(), host)
	cashier.open()
	assert_false(cashier.give_button.disabled)
	cashier.give_spin.value = 200
	cashier.give_button.pressed.emit()
	assert_eq(host.sim.player(2).wallet.pocket, Tuning.START_CHIPS + 200)
	assert_eq(host.sim.player(1).wallet.pocket, Tuning.START_CHIPS - 200)


# --- Wardrobe -----------------------------------------------------------------

func test_wardrobe_restroom_changes_into_the_stash() -> void:
	var host := _host()
	var wardrobe: WardrobePanel = _add(WardrobePanel.new(), host)
	host.request_enter_zone(1, HR.ZoneType.RESTROOM, &"restroom")
	wardrobe.open_mode(WardrobePanel.MODE_RESTROOM)
	assert_eq(wardrobe.wear_buttons.size(), Tuning.START_STASH_OUTFITS)
	var target: Dictionary = host.sim.player(1).stash[0].to_dict()
	wardrobe.wear_buttons[0].pressed.emit()
	assert_eq(host.sim.player(1).outfit.to_dict(), target)
	assert_true(wardrobe.result_label.text.begins_with("New look"))
	assert_eq(wardrobe.look_badge_label.text, "No poster matches this look.")


func test_wardrobe_gift_shop_and_steal() -> void:
	var host := _host()
	var wardrobe: WardrobePanel = _add(WardrobePanel.new(), host)
	host.request_enter_zone(1, HR.ZoneType.GIFT_SHOP, &"gift_shop")
	wardrobe.open_mode(WardrobePanel.MODE_GIFT_SHOP)
	wardrobe.slot_buttons[HR.OutfitSlot.HAT].pressed.emit()
	assert_eq(wardrobe.shop_slot, HR.OutfitSlot.HAT)
	assert_eq(wardrobe.buy_buttons.size(), OutfitCatalog.shop_pieces(HR.OutfitSlot.HAT).size())
	var piece: StringName = &""
	for id: StringName in wardrobe.buy_buttons:
		if not (wardrobe.buy_buttons[id] as Button).disabled:
			piece = id
			break
	assert_ne(piece, &"")
	var stash_before: int = host.sim.player(1).stash.size()
	(wardrobe.buy_buttons[piece] as Button).pressed.emit()
	assert_eq(host.sim.player(1).stash.size(), stash_before + 1)
	assert_eq(host.sim.player(1).stash.back().get_piece(HR.OutfitSlot.HAT), piece)
	assert_true(wardrobe.result_label.text.begins_with("Bought"))
	assert_eq(int(_me(host)["pocket"]), Tuning.START_CHIPS - OutfitCatalog.piece_price(piece))

	host.request_enter_zone(1, HR.ZoneType.STAFF_ONLY, &"laundry")
	wardrobe.open_mode(WardrobePanel.MODE_STEAL)
	assert_not_null(wardrobe.steal_button)
	wardrobe.steal_button.pressed.emit()
	assert_eq(host.sim.player(1).stash.size(), stash_before + 2)
	wardrobe.steal_button.pressed.emit()
	assert_true(wardrobe.result_label.text.contains("Try again"), "cooldown")
	assert_eq(host.sim.player(1).stash.size(), stash_before + 2)


func test_wardrobe_flags_a_poster_match() -> void:
	var host := _host()
	var wardrobe: WardrobePanel = _add(WardrobePanel.new(), host)
	wardrobe.open_mode(WardrobePanel.MODE_RESTROOM)
	host.sim.player(1).heat.add(90.0, HeatRules.WIN)
	assert_true(wardrobe.look_badge_label.text.contains("WANTED POSTER"))


# --- Forger -------------------------------------------------------------------

func test_forger_buys_and_swaps_ids() -> void:
	var host := _host()
	var forger: ForgerPanel = _add(ForgerPanel.new(), host)
	forger.open()
	assert_true((forger.buy_buttons[HR.IdGrade.CHEAP] as Button).disabled, "forger is elsewhere")
	host.request_enter_zone(1, HR.ZoneType.FORGER, host.sim.forger.location())
	forger.refresh()
	assert_false((forger.buy_buttons[HR.IdGrade.CHEAP] as Button).disabled)
	assert_true((forger.buy_buttons[HR.IdGrade.FLAWLESS] as Button).disabled, "too expensive")
	(forger.buy_buttons[HR.IdGrade.CHEAP] as Button).pressed.emit()
	assert_eq(int(_me(host)["id_count"]), 2)
	assert_eq(int(_me(host)["id_index"]), 1)
	assert_eq(forger.swap_buttons.size(), 2)
	assert_true(forger.swap_buttons[1].disabled, "in use")
	forger.swap_buttons[0].pressed.emit()
	assert_eq(int(_me(host)["id_index"]), 0)
	host.sim.player(1).ids[1].burn()
	forger.refresh()
	var badges := forger.owned_box.find_children("*", "Label", true, false).filter(func(l: Label) -> bool: return l.text == "BURNED")
	assert_eq(badges.size(), 1)


# --- Menus --------------------------------------------------------------------

func test_title_screen_buttons() -> void:
	var title: TitleScreen = _add(TitleScreen.new(), null)
	_record(title.start_requested, "start")
	_record(title.quit_requested, "quit")
	title.start_button.pressed.emit()
	title.practice_button.pressed.emit()
	assert_eq(_recorded("start")[0][1], Tuning.TOP_RUNG)
	assert_eq(_recorded("start")[0][2], false)
	assert_eq(_recorded("start")[1][1], Tuning.BOTTOM_RUNG)
	assert_eq(_recorded("start")[1][2], true)
	assert_true(title.practice_button.text.contains("Sal's Back Room (1 guard)"))
	title.controls_button.pressed.emit()
	assert_true(title.controls_panel.visible)
	assert_eq(title.listed_actions, InputSetup.ACTIONS, "every action is on the controls sheet")
	title.controls_back_button.pressed.emit()
	assert_false(title.controls_panel.visible)
	title.quit_button.pressed.emit()
	assert_eq(_recorded("quit").size(), 1)
	assert_true(str(TitleScreen.describe_events(&"interact")["keys"]).contains("E"))


func test_pause_menu_signals() -> void:
	var host := _host()
	var menu: PauseMenu = _add(PauseMenu.new(), host)
	_record(menu.resume_requested, "resume")
	_record(menu.restart_requested, "restart")
	_record(menu.quit_to_title_requested, "quit")
	_record(menu.closed, "closed")
	assert_eq(menu.process_mode, Node.PROCESS_MODE_ALWAYS)
	menu.open()
	assert_true(menu.is_open())
	assert_true(menu.summary_label.text.contains("The Riverboat Queen"))
	menu.restart_button.pressed.emit()
	menu.quit_button.pressed.emit()
	menu.resume_button.pressed.emit()
	assert_eq(_recorded("restart").size(), 1)
	assert_eq(_recorded("quit").size(), 1)
	assert_eq(_recorded("resume").size(), 1)
	assert_eq(_recorded("closed").size(), 1)
	assert_false(menu.is_open())


func test_visit_banner_thrown_out_and_summary() -> void:
	var host := _host()
	var banner: VisitBanner = _add(VisitBanner.new(), host)
	_record(banner.closed, "closed")
	for i in Tuning.STRIKES_TO_THROW_OUT:
		assert_true(bool(host.request_caught(1, 1)["ok"]), "catch %d" % i)
		host.request_reach_back_room(1)
		if i < Tuning.STRIKES_TO_THROW_OUT - 1:
			host.sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
			host.sim.player(1).rejoin_grace = 0.0  # skip the after-rejoin grace (broke crew: no time to wait)
	assert_true(host.sim.finished)
	assert_true(banner.is_open())
	assert_eq(banner.kind, VisitBanner.KIND_THROWN_OUT)
	assert_true(banner.route_label.text.contains("The Riverboat Queen"))
	assert_true(banner.route_label.text.contains("Neon Oasis"))
	banner.advance(Tuning.UI_VISIT_BANNER_SECONDS + 0.1)
	assert_false(banner.is_open(), "auto-closes")
	assert_eq(_recorded("closed").size(), 1)
	banner.show_climbed(2, 1, 17000)
	assert_eq(banner.kind, VisitBanner.KIND_CLIMBED)
	assert_true(banner.handle_key(KEY_SPACE))
	assert_false(banner.is_open())
	banner.show_run_summary({"score": 23456, "top_banked": 21456, "top_seconds": 130.0, "visits": 3})
	assert_true(banner.route_label.text.contains("23,456"))
	banner.advance(Tuning.UI_VISIT_BANNER_SECONDS + 1.0)
	assert_true(banner.is_open(), "the summary waits for its button")
	banner.continue_button.pressed.emit()
	assert_false(banner.is_open())


func test_visit_banner_curb_at_sals() -> void:
	var host := _host(Tuning.BOTTOM_RUNG)
	var banner: VisitBanner = _add(VisitBanner.new(), host)
	for i in Tuning.STRIKES_TO_THROW_OUT:
		host.request_caught(1, 1)
		host.request_reach_back_room(1)
		if i < Tuning.STRIKES_TO_THROW_OUT - 1:
			host.sim.tick(Tuning.BACK_ROOM_TIMEOUT + 0.1)
			host.sim.player(1).rejoin_grace = 0.0  # skip the after-rejoin grace
	assert_eq(banner.kind, VisitBanner.KIND_CURB)
	assert_true(banner.title_label.text.contains("CURB"))


func test_debug_overlay() -> void:
	var host := _host()
	var overlay: DebugOverlay = _add(DebugOverlay.new(), host)
	assert_false(overlay.visible)
	overlay.set_guard_provider(func() -> Array: return [{"id": 1, "state": "PATROL"}, "camera 2 idle"])
	overlay.toggle()
	assert_true(overlay.visible)
	assert_true(overlay.guards_label.text.contains("state=PATROL"))
	assert_true(overlay.guards_label.text.contains("camera 2 idle"))
	assert_true(overlay.stats_label.text.contains("heat"))
	assert_true(overlay.snapshot_label.text.begins_with("SNAPSHOT"))
	assert_lte(overlay.snapshot_label.text.split("\n").size(), DebugOverlay.MAX_LINES + 1.0)
	overlay.toggle()
	assert_false(overlay.visible)


func test_modal_panels_close_when_grabbed() -> void:
	var host := _host()
	var quiz: IdQuizPanel = _add(IdQuizPanel.new(), host)
	var cashier: CashierPanel = _add(CashierPanel.new(), host)
	var forger: ForgerPanel = _add(ForgerPanel.new(), host)
	host.request_start_id_check(1, 1)
	cashier.open()
	forger.open()
	assert_true(quiz.is_waiting())
	host.request_caught(1, 1)
	assert_false(quiz.is_open(), "the sim dropped the check")
	assert_false(cashier.is_open())
	assert_false(forger.is_open())
