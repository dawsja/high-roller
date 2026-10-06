class_name CashierPanel
extends Control
## The cashier window: banks pocket chips under the current fake ID
## (request_cash_out). Shows pocket, crew bank and buy-in progress, the ID in
## use with its winnings cap (warns before a cash-out would flag the name), the
## Heat a large cash-out adds, taking chips back out of the crew bank
## (request_withdraw, up to Tuning.UI_WITHDRAW_MAX_BETS max bets a press) and
## "hand chips to a teammate" (disabled solo). Results come back as
## host.request_done (right away offline and on the host, after a round trip
## on a co-op client).

signal cashed_out(result: Dictionary)
signal closed()

var host: SimHost = null
var pid: int = 1

var pocket_label: Label
var bank_label: Label
var bank_bar: ProgressBar
var bank_hint_label: Label
var id_label: Label
var cap_label: Label
var warning_label: Label
var all_button: Button
var half_button: Button
var preset_button: Button
var custom_spin: SpinBox
var custom_button: Button
var result_label: Label
## Takes withdraw_amount() chips out of the crew bank.
var withdraw_button: Button
var give_target: OptionButton
var give_spin: SpinBox
var give_button: Button
var give_hint_label: Label
var close_button: Button

var _pocket: int = 0
var _bank: int = 0
var _max_bet: int = 1
var _card: Dictionary = {}
var _teammates: Array[int] = []
var _refresh_left: float = 0.0


func _init() -> void:
	name = "CashierPanel"
	theme = UiTheme.make_theme()
	_build()
	visible = false


func setup(p_host: SimHost, p_pid: int) -> void:
	if host != null and host.sim_event.is_connected(_on_sim_event):
		host.sim_event.disconnect(_on_sim_event)
		host.request_done.disconnect(_on_request_done)
	host = p_host
	pid = p_pid
	if host != null:
		host.sim_event.connect(_on_sim_event)
		host.request_done.connect(_on_request_done)


func open() -> void:
	result_label.text = ""
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


## Banks `amount` pocket chips. Returns the request result ({ok: true,
## reason: &"pending"} on a co-op client; the answer shows when it arrives).
func cash_out(amount: int) -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	return host.request_cash_out(pid, amount)


## Takes `amount` chips out of the crew bank into the pocket. Returns the request result.
func withdraw(amount: int) -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	return host.request_withdraw(pid, amount)


## What the withdraw button takes: the bank, up to UI_WITHDRAW_MAX_BETS max bets.
func withdraw_amount() -> int:
	return mini(_bank, Tuning.UI_WITHDRAW_MAX_BETS * _max_bet)


## Hands `amount` pocket chips to the teammate picked in the list.
func give_chips(amount: int) -> Dictionary:
	if host == null or _teammates.is_empty():
		return {"ok": false, "reason": FloorSim.UNKNOWN_PLAYER}
	var to: int = _teammates[clampi(give_target.selected, 0, _teammates.size() - 1)]
	return host.request_give_chips(pid, to, amount)


func _on_request_done(request: StringName, args: Array, res: Dictionary) -> void:
	if args.is_empty() or int(args[0]) != pid or not (request in [&"cash_out", &"withdraw", &"give_chips"]):
		return
	var ok: bool = bool(res.get("ok", false))
	if not ok:
		result_label.text = UiTheme.reason_text(StringName(str(res.get("reason", ""))))
		result_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR)
	else:
		match request:
			&"cash_out":
				var text := "Banked %s." % UiTheme.chips(int(res.get("banked", 0)))
				if float(res.get("heat", 0.0)) > 0.0:
					text += "  Heat %s" % UiTheme.signed(float(res.get("heat", 0.0)))
				if bool(res.get("flagged", false)):
					text += "  The name is FLAGGED now!"
				result_label.text = text
				result_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR if bool(res.get("flagged", false)) else UiTheme.WIN_COLOR)
				cashed_out.emit(res)
			&"withdraw":
				result_label.text = "Took %s chips out of the crew bank." % UiTheme.chips(int(res.get("amount", 0)))
				result_label.add_theme_color_override(&"font_color", UiTheme.WIN_COLOR)
			&"give_chips":
				result_label.text = "Handed %s chips over." % UiTheme.chips(int(args[2]) if args.size() > 2 else 0)
				result_label.add_theme_color_override(&"font_color", UiTheme.WIN_COLOR)
	refresh()


func refresh() -> void:
	var snap: Dictionary = host.snapshot() if host != null else {}
	var run: Dictionary = snap.get("run", {})
	var players: Dictionary = snap.get("players", {})
	var me: Dictionary = players.get(pid, {})
	_pocket = int(me.get("pocket", 0))
	_max_bet = int(run.get("max_bet", 1))
	_card = me.get("id", {})
	pocket_label.text = UiTheme.chips(_pocket)
	var top: bool = bool(run.get("is_top", false))
	var bank: int = int(run.get("bank", 0))
	_bank = bank
	var buy_in: int = int(run.get("buy_in", 0))
	if top:
		bank_label.text = "Banked at The Apex: %s" % UiTheme.chips(int(run.get("top_banked", 0)))
		bank_bar.visible = false
		bank_hint_label.text = "Every chip banked here is score. Score now %s." % UiTheme.chips(int(run.get("score", 0)))
	else:
		bank_label.text = "Crew bank %s / %s" % [UiTheme.chips(bank), UiTheme.chips(buy_in)]
		bank_bar.visible = buy_in > 0
		bank_bar.max_value = maxf(1.0, float(buy_in))
		bank_bar.value = minf(float(bank), float(buy_in))
		var rung: int = int(run.get("rung", Tuning.TOP_RUNG))
		var above: String = str(CasinoLadder.casino(rung - 1).get("name", ""))
		if bool(run.get("can_climb", false)):
			bank_hint_label.text = "Buy-in covered! Get the crew to the exit to climb to %s." % above
		else:
			bank_hint_label.text = "%s more to climb to %s." % [UiTheme.chips(maxi(0, buy_in - bank)), above]
	if _card.is_empty():
		id_label.text = "No ID! The cashier won't pay out."
		cap_label.text = ""
	else:
		id_label.text = "Cashing out as %s (%s)" % [str(_card.get("name", "")), IdGenerator.grade_name(int(_card.get("grade", 0)))]
		var cap: int = int(_card.get("cap", 0))
		var under: int = int(_card.get("banked_under", 0))
		cap_label.text = "Banked under this name: %s of a %s cap" % [UiTheme.chips(under), UiTheme.chips(cap)]
	custom_spin.max_value = maxf(1.0, float(_pocket))
	if custom_spin.value > _pocket:
		custom_spin.set_value_no_signal(_pocket)
	var can: bool = _pocket > 0 and not _card.is_empty()
	all_button.disabled = not can
	half_button.disabled = not can or _pocket < 2
	preset_button.disabled = not can or _pocket < Tuning.UI_CASHIER_PRESET
	custom_button.disabled = not can or int(custom_spin.value) <= 0
	withdraw_button.disabled = withdraw_amount() <= 0
	withdraw_button.text = "TAKE %s OUT OF THE CREW BANK" % UiTheme.chips(withdraw_amount())
	all_button.text = "ALL  %s" % UiTheme.chips(_pocket)
	half_button.text = "HALF  %s" % UiTheme.chips(_pocket >> 1)
	_update_warning(int(custom_spin.value) if int(custom_spin.value) > 0 else _pocket)
	_refresh_teammates(players)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = Tuning.UI_REFRESH_SECONDS * 3.0
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _update_warning(amount: int) -> void:
	var lines: PackedStringArray = []
	var bad := false
	if not _card.is_empty():
		var card := FakeId.from_dict(_card)
		if not card.passes_check():
			lines.append("This ID is %s: the cashier will refuse it." % ("burned" if card.burned else "flagged"))
			bad = true
		elif card.would_flag(amount):
			lines.append("Careful: banking %s flags %s (only %s left under the cap)." % [UiTheme.chips(amount), card.name, UiTheme.chips(card.remaining_cap())])
			bad = true
		else:
			lines.append("%s more can go under this name safely." % UiTheme.chips(card.remaining_cap()))
	var heat: float = HeatRules.cash_out_heat(amount, _max_bet)
	if heat > 0.0:
		lines.append("A cash-out this big adds %s Heat." % UiTheme.signed(heat))
		bad = true
	warning_label.text = "\n".join(lines)
	warning_label.add_theme_color_override(&"font_color", UiTheme.heat_color(HR.HeatLevel.SUSPECTED) if bad else UiTheme.MUTED)


func _refresh_teammates(players: Dictionary) -> void:
	var others: Array[int] = []
	for key: Variant in players:
		if int(key) != pid:
			others.append(int(key))
	if str(others) != str(_teammates):
		_teammates = others
		give_target.clear()
		for other: int in _teammates:
			var p: Dictionary = players[other]
			give_target.add_item(str(p.get("name", "Player %d" % other)))
	var solo: bool = _teammates.is_empty()
	give_target.disabled = solo
	give_spin.editable = not solo
	give_spin.max_value = maxf(1.0, float(_pocket))
	give_button.disabled = solo or _pocket <= 0
	give_hint_label.text = "Solo run: no teammate to hand chips to." if solo else "Stand next to them. The hottest player shouldn't carry."


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if not visible:
		return
	if UiTheme.ends_panel(kind, data, pid):
		close()
		return
	if kind in [&"chips", &"banked", &"withdrawn", &"id", &"player_joined", &"status"]:
		if kind == &"banked" or kind == &"withdrawn" or int(data.get("pid", pid)) == pid or kind == &"player_joined":
			refresh()


func _build() -> void:
	var body := UiTheme.build_modal(self, 720.0)
	close_button = UiTheme.make_button("CLOSE  [Esc]", &"BlackButton")
	close_button.pressed.connect(close)
	body.add_child(UiTheme.make_header("CASHIER", close_button))

	var money := HBoxContainer.new()
	body.add_child(money)
	var pt := UiTheme.make_label("POCKET", &"SmallLabel")
	pt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money.add_child(pt)
	pocket_label = UiTheme.make_label("0", &"BigLabel", 40)
	pocket_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(pocket_label)
	bank_label = UiTheme.make_label("", &"BigLabel", 26)
	bank_label.add_theme_color_override(&"font_color", UiTheme.GOLD_LIGHT)
	bank_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	money.add_child(bank_label)
	bank_bar = ProgressBar.new()
	bank_bar.show_percentage = false
	bank_bar.custom_minimum_size = Vector2(0, 18)
	body.add_child(bank_bar)
	bank_hint_label = UiTheme.make_label("", &"SmallLabel", 19)
	body.add_child(bank_hint_label)
	body.add_child(HSeparator.new())

	var card := UiTheme.make_panel(&"InsetPanel")
	body.add_child(card)
	var cv := VBoxContainer.new()
	card.add_child(cv)
	id_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY)
	cv.add_child(id_label)
	cap_label = UiTheme.make_label("", &"SmallLabel", 19)
	cv.add_child(cap_label)
	warning_label = UiTheme.make_label("", &"SmallLabel", 19)
	warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(warning_label)

	var amounts := HBoxContainer.new()
	body.add_child(amounts)
	all_button = UiTheme.make_button("ALL", &"GreenButton", Vector2(0, 58))
	all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_button.pressed.connect(func() -> void: cash_out(_pocket))
	amounts.add_child(all_button)
	half_button = UiTheme.make_button("HALF", &"", Vector2(0, 58))
	half_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	half_button.pressed.connect(func() -> void: cash_out(_pocket >> 1))
	amounts.add_child(half_button)
	preset_button = UiTheme.make_button(UiTheme.chips(Tuning.UI_CASHIER_PRESET), &"BlueButton", Vector2(110, 58))
	preset_button.pressed.connect(func() -> void: cash_out(Tuning.UI_CASHIER_PRESET))
	amounts.add_child(preset_button)

	var custom := HBoxContainer.new()
	body.add_child(custom)
	var cl := UiTheme.make_label("Amount", &"SmallLabel")
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom.add_child(cl)
	custom_spin = SpinBox.new()
	custom_spin.min_value = 0
	custom_spin.max_value = 1
	custom_spin.step = 1
	custom_spin.custom_minimum_size = Vector2(200, 50)
	custom_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_spin.value_changed.connect(func(v: float) -> void:
		custom_button.disabled = int(v) <= 0 or _pocket <= 0
		_update_warning(int(v) if int(v) > 0 else _pocket))
	custom.add_child(custom_spin)
	custom_button = UiTheme.make_button("CASH OUT", &"", Vector2(180, 50))
	custom_button.pressed.connect(func() -> void: cash_out(int(custom_spin.value)))
	custom.add_child(custom_button)

	withdraw_button = UiTheme.make_button("TAKE OUT OF THE CREW BANK", &"BlackButton", Vector2(0, 46))
	withdraw_button.pressed.connect(func() -> void: withdraw(withdraw_amount()))
	body.add_child(withdraw_button)

	result_label = UiTheme.make_label("", &"BigLabel", 26)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(result_label)
	body.add_child(HSeparator.new())

	var give := HBoxContainer.new()
	body.add_child(give)
	var gl := UiTheme.make_label("Hand chips to", &"SmallLabel")
	gl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	give.add_child(gl)
	give_target = OptionButton.new()
	give_target.custom_minimum_size = Vector2(170, 46)
	give.add_child(give_target)
	give_spin = SpinBox.new()
	give_spin.min_value = 1
	give_spin.max_value = 1
	give_spin.step = 1
	give_spin.custom_minimum_size = Vector2(150, 46)
	give.add_child(give_spin)
	give_button = UiTheme.make_button("HAND OVER", &"BlueButton", Vector2(0, 46))
	give_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_button.pressed.connect(func() -> void: give_chips(int(give_spin.value)))
	give.add_child(give_button)
	give_hint_label = UiTheme.make_label("", &"SmallLabel", 18)
	body.add_child(give_hint_label)
