extends TestCase
## The HUD, the bet panel and the ID quiz against a real SimHost: wording that
## depends on the casino, the notes under the Heat meter, refusals and
## closing on a grab.

var _nodes: Array[Node] = []


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	await tree.process_frame


## A paused host at `rung` with a visit and a slots and a high-low table.
func _host(rung: int = 3, extras: Dictionary = {}) -> SimHost:
	var host := SimHost.new()
	tree.root.add_child(host)
	_nodes.append(host)
	host.visit_extras = extras
	host.start_run(rung, 42, {1: "Ace"})
	host.start_visit()
	host.paused = true
	host.request_register_table(&"slots_1", HR.GameType.SLOTS, &"slots_a")
	host.request_register_table(&"hl_1", HR.GameType.HIGH_LOW, &"tables_a")
	return host


func _add(node: Control, host: SimHost) -> Control:
	tree.root.add_child(node)
	_nodes.append(node)
	node.call(&"setup", host, 1)
	return node


func _ps(host: SimHost) -> PlayerState:
	return host.sim.player(1)


# --- HUD ----------------------------------------------------------------------

func test_watched_mentions_cameras_only_where_there_are_cameras() -> void:
	var with_cams := _host(3)
	assert_true(CasinoLadder.has_security(3, HR.SecurityType.CAMERA))
	var hud: Hud = _add(Hud.new(), with_cams)
	_ps(with_cams).heat.raise_to(Tuning.WATCHED_AT + 1.0, &"test")
	assert_eq(hud.notification_texts()[0], "You're being WATCHED. Cameras follow you.")

	var no_cams := _host(5)
	assert_false(CasinoLadder.has_security(5, HR.SecurityType.CAMERA))
	var hud2: Hud = _add(Hud.new(), no_cams)
	_ps(no_cams).heat.raise_to(Tuning.WATCHED_AT + 1.0, &"test")
	assert_false(hud2.notification_texts()[0].contains("Cameras"), "the Rusty Spur has no cameras")
	assert_true(hud2.notification_texts()[0].contains("WATCHED"))

	var practice := _host(3, {"practice": true})
	var hud3: Hud = _add(Hud.new(), practice)
	_ps(practice).heat.raise_to(Tuning.WATCHED_AT + 1.0, &"test")
	assert_false(hud3.notification_texts()[0].contains("Cameras"), "practice runs no cameras")


func test_heat_note_shows_the_rejoin_grace_then_loitering() -> void:
	var host := _host(3)
	var hud: Hud = _add(Hud.new(), host)
	assert_false(hud.heat_note_label.visible, "nothing to say at first")
	var ps := _ps(host)
	ps.rejoin_grace = 7.2
	hud.refresh()
	assert_true(hud.heat_note_label.visible)
	assert_true(hud.heat_note_label.text.contains("8 s"), hud.heat_note_label.text)
	ps.rejoin_grace = 0.0
	ps.loiter_seconds = Tuning.LOITER_GRACE_SECONDS + 1.0
	hud.refresh()
	assert_true(hud.heat_note_label.text.begins_with("LOITERING"), hud.heat_note_label.text)
	assert_true(hud.notification_texts()[0].contains("loiterers"), "told once when it starts")
	var count := hud.notification_texts().size()
	hud.refresh()
	assert_eq(hud.notification_texts().size(), count, "not again while it lasts")
	ps.loiter_seconds = 0.0
	hud.refresh()
	assert_false(hud.heat_note_label.visible)


func test_rejoin_notification_names_the_grace() -> void:
	var host := _host(3)
	var hud: Hud = _add(Hud.new(), host)
	host.sim.event.emit(&"rejoined", {"pid": 1, "from": &"back_room", "spawn": &"entrance", "grace": Tuning.REJOIN_GRACE_SECONDS, "new_id": false})
	assert_true(hud.notification_texts()[0].contains("%d s" % int(Tuning.REJOIN_GRACE_SECONDS)), hud.notification_texts()[0])


func test_bank_hint_warns_before_a_climb_that_would_arrive_broke() -> void:
	var host := _host(Tuning.BOTTOM_RUNG)
	var hud: Hud = _add(Hud.new(), host)
	_ps(host).wallet.lose_pocket()
	host.run.add_bank(CasinoLadder.buy_in_to_leave(Tuning.BOTTOM_RUNG))
	hud.refresh()
	var stake: int = int(CasinoLadder.casino(Tuning.BOTTOM_RUNG - 1)["min_bet"])
	assert_eq(hud.bank_hint_label.text, "Keep %s chips to bet upstairs!" % UiTheme.chips(stake))
	_ps(host).wallet.add(stake)
	hud.refresh()
	assert_true(hud.bank_hint_label.text.begins_with("CLIMB READY"), "a pocket covers the bet up there")


func test_climb_check_falls_back_from_a_stretch() -> void:
	# Rung 5: the stretch to rung 3 would leave nothing, one rung leaves enough.
	var run := {"can_climb": true, "rung": 5, "climb_target": 3, "bank": CasinoLadder.climb_cost(5, 3)}
	assert_true(Hud._arrives_broke(run, {}, 5, 3))
	assert_false(Hud.climb_would_arrive_broke(run, {}), "try_climb climbs one rung instead")
	run["bank"] = CasinoLadder.climb_cost(5, 4)
	run["climb_target"] = 4
	assert_true(Hud.climb_would_arrive_broke(run, {1: {"pocket": 0}}))
	assert_false(Hud.climb_would_arrive_broke(run, {1: {"pocket": 1000}}))
	run["can_climb"] = false
	assert_false(Hud.climb_would_arrive_broke(run, {}))


# --- ID quiz --------------------------------------------------------------------

func test_quiz_result_card_closes_when_grabbed() -> void:
	var host := _host(3)
	var quiz: IdQuizPanel = _add(IdQuizPanel.new(), host)
	host.request_start_id_check(1, 1)
	assert_true(quiz.is_waiting())
	var wrong: int = (int(_ps(host).id_question["correct_index"]) + 1) % 3
	quiz.answer(wrong)
	assert_true(quiz.is_open(), "the FAILED card is up")
	assert_eq(quiz.result_label.text, "FAILED!")
	# The guard's reaction is over well before the card times out.
	quiz.advance(Tuning.ID_FAIL_REACTION_SECONDS * 0.5)
	assert_true(quiz.is_open())
	_ps(host).rejoin_grace = 0.0
	assert_true(bool(host.request_caught(1, 1)["ok"]))
	assert_false(quiz.is_open(), "the grab closes the result card")


func test_quiz_result_card_ignores_a_teammates_grab() -> void:
	var host := _host(3)
	var quiz: IdQuizPanel = _add(IdQuizPanel.new(), host)
	host.request_start_id_check(1, 1)
	quiz.expire()
	assert_true(quiz.is_open())
	host.sim.event.emit(&"caught", {"pid": 2, "guard_id": 1})
	assert_true(quiz.is_open(), "someone else's grab")


# --- Bet panel ------------------------------------------------------------------

func test_bet_panel_shows_why_a_bet_was_refused() -> void:
	var host := _host(3)
	var panel: BetPanel = _add(BetPanel.new(), host)
	var answers: Array = []
	host.request_done.connect(func(request: StringName, _args: Array, res: Dictionary) -> void:
		if request == &"place_bet":
			answers.append(res))
	host.request_sit(1, &"slots_1")
	assert_true(panel.is_open())
	var min_bet: int = int(host.snapshot()["run"]["min_bet"])
	# The pocket drops under the bet behind the panel's back.
	_ps(host).wallet.spend(_ps(host).wallet.pocket - (min_bet - 1))
	panel.bet_amount = min_bet
	panel.press_main()
	assert_eq(answers.size(), 1)
	assert_false(bool(answers[0]["ok"]))
	var reason: StringName = answers[0]["reason"]
	assert_eq(panel.result_label.text, "REFUSED")
	assert_true(panel.result_label.visible and panel.result_label.get_parent().visible, "the result row shows it")
	assert_eq(panel.detail_label.text, panel.refusal_text(reason))
	assert_true(panel.detail_label.visible)
	assert_ne(panel.detail_label.text, "")


func test_bet_panel_says_why_a_press_did_nothing() -> void:
	var host := _host(3)
	var panel: BetPanel = _add(BetPanel.new(), host)
	host.request_sit(1, &"slots_1")
	panel.press_main()
	assert_true(panel.is_locked(), "a bet went in")
	panel.press_main()
	assert_eq(panel.hint_label.text, "Wait for the table to settle.")
	panel.notify_result_shown()
	host.request_start_id_check(1, 1)
	panel.press_main()
	assert_eq(panel.hint_label.text, "Not now: a guard is checking your ID.")
	panel.advance(BetPanel._REFUSAL_SECONDS + 0.1)
	assert_eq(panel.hint_label.text, "A guard wants to see your ID...", "the explanation fades")


func test_bet_panel_gives_up_on_a_missing_answer() -> void:
	var host := _host(3)
	var panel: BetPanel = _add(BetPanel.new(), host)
	host.request_sit(1, &"slots_1")
	panel._begin_collect()
	assert_true(panel.is_waiting())
	panel.press_main()
	assert_eq(panel.hint_label.text, "Still waiting for the dealer...")
	panel.advance(BetPanel._AWAIT_SECONDS + 0.1)
	assert_false(panel.is_waiting())
	assert_true(panel.hint_label.text.begins_with("No answer"), panel.hint_label.text)
	assert_false(panel.main_button.disabled, "can try again")
