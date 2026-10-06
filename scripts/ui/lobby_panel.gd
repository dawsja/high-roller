class_name LobbyPanel
extends Control
## The co-op lobby between the title and a run: the crew roster (names, the
## host marked, "you"), a status line, and for the host the start buttons
## (The Apex, or practice at Sal's) and, on Steam, "Invite friends". Clients
## wait for the host to start. Leave closes the session. Reads a NetSession;
## emits signals, main.gd does the rest.

signal start_requested(start_rung: int, practice: bool)
signal leave_requested()
signal invite_requested()

var session: NetSession = null

var title_label: Label
var status_label: Label
var roster_box: VBoxContainer
var start_button: Button
var practice_button: Button
var invite_button: Button
var leave_button: Button
var hint_label: Label


func _init() -> void:
	name = "LobbyPanel"
	theme = UiTheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


## Kept for the shared panel interface.
func setup(_host: SimHost, _pid: int) -> void:
	pass


func set_session(p_session: NetSession) -> void:
	if session != null and session.roster_changed.is_connected(_on_roster_changed):
		session.roster_changed.disconnect(_on_roster_changed)
		session.status_changed.disconnect(set_status)
	session = p_session
	if session != null:
		session.roster_changed.connect(_on_roster_changed)
		session.status_changed.connect(set_status)


func open() -> void:
	visible = true
	refresh()
	if is_inside_tree():
		(start_button if start_button.visible else leave_button).grab_focus()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = text != ""


func refresh() -> void:
	var hosting: bool = session != null and session.state == NetSession.State.HOSTING
	var joined: bool = session != null and session.state == NetSession.State.JOINED
	title_label.text = "YOUR CREW" if hosting else ("THE CREW" if joined else "JOINING A CREW")
	start_button.visible = hosting
	practice_button.visible = hosting
	invite_button.visible = hosting and session.backend_kind() == &"steam"
	UiTheme.clear_children(roster_box)
	var roster: Dictionary = session.roster if session != null else {}
	var me: int = session.local_pid() if session != null else 1
	for pid: Variant in roster:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		roster_box.add_child(row)
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(26, 26)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.add_theme_stylebox_override(&"panel", UiTheme.flat_box(UiTheme.GOLD if int(pid) == 1 else UiTheme.CHIP_BLUE, UiTheme.CREAM, 3, 13, 0))
		row.add_child(chip)
		var label := UiTheme.make_label(str(roster[pid]), &"BigLabel", 28)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var tags: PackedStringArray = []
		if int(pid) == 1:
			tags.append("host")
		if int(pid) == me:
			tags.append("you")
		row.add_child(UiTheme.make_label(" · ".join(tags), &"SmallLabel"))
	var count: int = roster.size()
	if hosting:
		hint_label.text = "%d of %d players. Friends join with your address and port, then you start." % [count, NetSession.MAX_PLAYERS]
		start_button.disabled = false
	elif joined:
		hint_label.text = "Waiting for the host to start the run..."
	else:
		hint_label.text = "Connecting..."


func _on_roster_changed(_roster: Dictionary) -> void:
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		leave_requested.emit()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var body := UiTheme.build_modal(self, 720.0, 0.7)
	leave_button = UiTheme.make_button("LEAVE  [Esc]", &"RedButton")
	leave_button.pressed.connect(func() -> void: leave_requested.emit())
	var header := UiTheme.make_header("YOUR CREW", leave_button)
	title_label = header.get_child(0) as Label
	body.add_child(header)
	status_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY, UiTheme.GOLD_LIGHT)
	status_label.visible = false
	body.add_child(status_label)
	var inset := UiTheme.make_panel(&"InsetPanel")
	inset.custom_minimum_size = Vector2(0, 220)
	body.add_child(inset)
	roster_box = VBoxContainer.new()
	roster_box.add_theme_constant_override(&"separation", 8)
	inset.add_child(roster_box)
	hint_label = UiTheme.make_label("", &"SmallLabel", 19)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint_label)
	var apex: Dictionary = CasinoLadder.casino(Tuning.TOP_RUNG)
	var sals: Dictionary = CasinoLadder.casino(Tuning.BOTTOM_RUNG)
	start_button = UiTheme.make_button("Start the run at %s" % str(apex.get("name", "The Apex")), &"", Vector2(0, 64))
	start_button.add_theme_font_size_override(&"font_size", 28)
	start_button.pressed.connect(func() -> void: start_requested.emit(Tuning.TOP_RUNG, false))
	body.add_child(start_button)
	practice_button = UiTheme.make_button("Practice at %s" % str(sals.get("name", "Sal's Back Room")), &"GreenButton", Vector2(0, 58))
	practice_button.pressed.connect(func() -> void: start_requested.emit(Tuning.BOTTOM_RUNG, true))
	body.add_child(practice_button)
	invite_button = UiTheme.make_button("Invite Steam friends", &"BlueButton", Vector2(0, 52))
	invite_button.pressed.connect(func() -> void: invite_requested.emit())
	body.add_child(invite_button)
