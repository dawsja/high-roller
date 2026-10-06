class_name ForgerPanel
extends Control
## The ID forger: buy a cheap, solid or flawless card (price, winnings cap,
## chance a guard spots it on sight) with request_buy_id, and swap between the
## cards you hold with request_swap_id. Burned and flagged cards are marked.

signal closed()

var host: SimHost = null
var pid: int = 1

var location_label: Label
var pocket_label: Label
## HR.IdGrade -> Buy button.
var buy_buttons: Dictionary = {}
var owned_box: VBoxContainer
## One Use button per held card (index = position in the player's ids).
var swap_buttons: Array[Button] = []
var result_label: Label
var close_button: Button

var _me: Dictionary = {}
var _snap: Dictionary = {}


func _init() -> void:
	name = "ForgerPanel"
	theme = UiTheme.make_theme()
	_build()
	visible = false


func setup(p_host: SimHost, p_pid: int) -> void:
	if host != null and host.sim_event.is_connected(_on_sim_event):
		host.sim_event.disconnect(_on_sim_event)
	host = p_host
	pid = p_pid
	if host != null:
		host.sim_event.connect(_on_sim_event)


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


func buy(grade: int) -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	var res: Dictionary = host.request_buy_id(pid, grade)
	if bool(res.get("ok", false)):
		var card: Dictionary = res.get("id", {})
		_result("You're %s now. Born %s, from %s. Remember that!" % [str(card.get("name", "")), str(card.get("birthday", "")), str(card.get("home_state", ""))], UiTheme.WIN_COLOR)
	else:
		_result(UiTheme.reason_text(StringName(str(res.get("reason", "")))), UiTheme.LOSS_COLOR)
	refresh()
	return res


func swap(index: int) -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	var res: Dictionary = host.request_swap_id(pid, index)
	if bool(res.get("ok", false)):
		var card: Dictionary = res.get("id", {})
		_result("Playing as %s." % str(card.get("name", "")), UiTheme.WIN_COLOR)
	else:
		_result(UiTheme.reason_text(StringName(str(res.get("reason", "")))), UiTheme.LOSS_COLOR)
	refresh()
	return res


func refresh() -> void:
	_snap = host.snapshot() if host != null else {}
	var players: Dictionary = _snap.get("players", {})
	_me = players.get(pid, {})
	var pocket: int = int(_me.get("pocket", 0))
	pocket_label.text = "Pocket %s" % UiTheme.chips(pocket)
	var where: StringName = StringName(str(_snap.get("forger_location", "")))
	var here: bool = int(_me.get("zone", -1)) == HR.ZoneType.FORGER and StringName(str(_me.get("area_id", ""))) == where
	var moves: int = ceili(float(_snap.get("forger_seconds_until_move", 0.0)))
	if here:
		location_label.text = "\"Psst. Need a new name?\"  (moves on in %d s)" % moves
		location_label.add_theme_color_override(&"font_color", UiTheme.CREAM)
	else:
		location_label.text = "The forger is at the %s right now (moves in %d s)." % [String(where).replace("_", " "), moves]
		location_label.add_theme_color_override(&"font_color", UiTheme.heat_color(HR.HeatLevel.WATCHED))
	for grade: Variant in buy_buttons:
		var b: Button = buy_buttons[grade]
		b.disabled = not here or pocket < IdGenerator.price(int(grade))
	_rebuild_owned()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if not visible:
		return
	if UiTheme.ends_panel(kind, data, pid):
		close()
		return
	if kind == &"forger_moved" or (kind in [&"id", &"chips", &"zone", &"status"] and int(data.get("pid", -1)) == pid):
		refresh()


func _rebuild_owned() -> void:
	UiTheme.clear_children(owned_box)
	swap_buttons.clear()
	var ids: Array = _me.get("ids", [])
	var in_use: int = int(_me.get("id_index", -1))
	var status: int = int(_me.get("status", HR.PlayerStatus.FREE))
	var can_swap: bool = status == HR.PlayerStatus.FREE or status == HR.PlayerStatus.SEATED
	if ids.is_empty():
		owned_box.add_child(UiTheme.make_label("You hold no IDs.", &"SmallLabel"))
	for i in ids.size():
		var card: Dictionary = ids[i]
		var panel := UiTheme.make_panel(&"CardPanel")
		owned_box.add_child(panel)
		var row := HBoxContainer.new()
		panel.add_child(row)
		var info := VBoxContainer.new()
		info.add_theme_constant_override(&"separation", 0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UiTheme.make_label(str(card.get("name", "")), &"CardLabel", 24))
		info.add_child(UiTheme.make_label("%s  ·  %s  ·  %s" % [str(card.get("birthday", "")), str(card.get("home_state", "")), IdGenerator.grade_name(int(card.get("grade", 0)))], &"CardSmallLabel"))
		info.add_child(UiTheme.make_label("Banked %s / %s cap" % [UiTheme.chips(int(card.get("banked_under", 0))), UiTheme.chips(int(card.get("cap", 0)))], &"CardSmallLabel", 15))
		var badge := ""
		if bool(card.get("burned", false)):
			badge = "BURNED"
		elif bool(card.get("flagged", false)):
			badge = "FLAGGED"
		if badge != "":
			var bp := UiTheme.make_panel(&"BadgePanel")
			bp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bp.add_child(UiTheme.make_label(badge, &"", UiTheme.FONT_SMALL))
			row.add_child(bp)
		var using: bool = i == in_use
		var b := UiTheme.make_button("IN USE" if using else "USE", &"BlackButton" if using else &"GreenButton", Vector2(110, 46))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = using or not can_swap
		b.pressed.connect(swap.bind(i))
		row.add_child(b)
		swap_buttons.append(b)


func _result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.add_theme_color_override(&"font_color", color)


func _build() -> void:
	var body := UiTheme.build_modal(self, 860.0)
	close_button = UiTheme.make_button("CLOSE  [Esc]", &"BlackButton")
	close_button.pressed.connect(close)
	body.add_child(UiTheme.make_header("THE FORGER", close_button))
	var top := HBoxContainer.new()
	body.add_child(top)
	location_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY)
	location_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(location_label)
	pocket_label = UiTheme.make_label("", &"BigLabel", 26)
	top.add_child(pocket_label)

	var grades := HBoxContainer.new()
	grades.add_theme_constant_override(&"separation", 12)
	body.add_child(grades)
	var variations := {HR.IdGrade.CHEAP: &"BlackButton", HR.IdGrade.SOLID: &"BlueButton", HR.IdGrade.FLAWLESS: &""}
	for grade: int in IdGenerator.all_grades():
		var card := UiTheme.make_panel(&"InsetPanel")
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grades.add_child(card)
		var v := VBoxContainer.new()
		card.add_child(v)
		v.add_child(UiTheme.make_label(IdGenerator.grade_name(grade).to_upper(), &"HeaderLabel", 30))
		v.add_child(UiTheme.make_label("Cap %s banked" % UiTheme.chips(IdGenerator.cap(grade)), &"", UiTheme.FONT_BODY - 2))
		var spotted: float = IdGenerator.spotted_chance(grade)
		var sl := UiTheme.make_label("Spotted on sight %d%%" % roundi(spotted * 100.0) if spotted > 0.0 else "Never spotted on sight", &"SmallLabel")
		if spotted > 0.0:
			sl.add_theme_color_override(&"font_color", UiTheme.heat_color(HR.HeatLevel.SUSPECTED))
		v.add_child(sl)
		var b := UiTheme.make_button("BUY  %s" % UiTheme.chips(IdGenerator.price(grade)), variations.get(grade, &"") as StringName, Vector2(0, 52))
		b.pressed.connect(buy.bind(grade))
		v.add_child(b)
		buy_buttons[grade] = b

	body.add_child(HSeparator.new())
	body.add_child(UiTheme.make_label("YOUR IDS", &"SmallLabel"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	owned_box = VBoxContainer.new()
	owned_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(owned_box)
	result_label = UiTheme.make_label("", &"BigLabel", 24)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(result_label)
