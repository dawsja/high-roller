class_name LeaderboardPanel
extends Control
## Local leaderboards (design doc "Scoring and progression"): the top
## Profile.LEADERBOARD_SIZE run scores on this machine, one board per crew
## size (solo, crew of 2, 3, 4). Score is chips banked at The Apex plus
## minutes survived there. The last posted entry is highlighted. Steam
## leaderboards replace these later. Opened from the title screen.

signal closed()

const COLUMNS := ["#", "SCORE", "APEX BANKED", "TIME AT TOP", "CREW", "DATE"]
const COLUMN_WIDTHS := [50, 150, 170, 150, 330, 190]

var profile: Profile = null
## Crew size shown (1..Profile.MAX_CREW).
var crew_size: int = 1
## Entry serial to highlight (Profile.last_serial after a run; 0 = none).
var highlight_serial: int = 0

var title_label: Label
var close_button: Button
## One per crew size, index 0 = solo.
var crew_buttons: Array[Button] = []
var rows_box: VBoxContainer
var empty_label: Label
var best_label: Label


func _init() -> void:
	name = "LeaderboardPanel"
	theme = UiTheme.make_theme()
	_build()
	visible = false


func set_profile(p: Profile) -> void:
	profile = p
	if visible:
		refresh()


## Opens on a crew size (0 keeps the last one shown).
func open(p_crew_size: int = 0) -> void:
	if p_crew_size > 0:
		crew_size = clampi(p_crew_size, 1, Profile.MAX_CREW)
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func show_crew(crew: int) -> void:
	crew_size = clampi(crew, 1, Profile.MAX_CREW)
	refresh()


## Entries on the board being shown.
func row_count() -> int:
	return rows_box.get_child_count()


## "Solo", "Crew of 3".
static func crew_name(crew: int) -> String:
	return "Solo" if crew <= 1 else "Crew of %d" % crew


func refresh() -> void:
	var p: Profile = profile if profile != null else Profile.new()
	for i in crew_buttons.size():
		var n: int = p.leaderboard(i + 1).size()
		crew_buttons[i].text = "%s  (%d)" % [crew_name(i + 1).to_upper(), n]
		crew_buttons[i].modulate = Color.WHITE if i + 1 == crew_size else Color(1, 1, 1, 0.5)
	UiTheme.clear_children(rows_box)
	var board: Array = p.leaderboard(crew_size)
	empty_label.visible = board.is_empty()
	empty_label.text = "No %s runs posted yet. Walk out of The Apex's exit to end a run and post its score." % crew_name(crew_size).to_lower()
	best_label.text = "Best %s: %s  ·  Best overall: %s" % [crew_name(crew_size).to_lower(), UiTheme.chips(p.best_for(crew_size)), UiTheme.chips(p.best_score)]
	for i in board.size():
		rows_box.add_child(_row(i + 1, board[i]))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _row(rank: int, e: Dictionary) -> Control:
	var mine: bool = highlight_serial > 0 and int(e.get("serial", 0)) == highlight_serial
	var panel := UiTheme.make_panel(&"InsetPanel")
	if mine:
		panel.add_theme_stylebox_override(&"panel", UiTheme.flat_box(Color(UiTheme.GOLD_DARK, 0.55), UiTheme.GOLD, 2, 10, 8))
	var h := HBoxContainer.new()
	panel.add_child(h)
	var crew: PackedStringArray = []
	for n: Variant in e.get("crew", []):
		crew.append(str(n))
	var cells := [
		"%d" % rank,
		UiTheme.chips(int(e.get("score", 0))),
		UiTheme.chips(int(e.get("top_banked", 0))),
		UiTheme.clock(float(e.get("top_seconds", 0.0))),
		", ".join(crew) if not crew.is_empty() else "-",
		str(e.get("date", "")).substr(0, 16),
	]
	for c in cells.size():
		var color: Variant = null
		if c == 0:
			color = UiTheme.GOLD if rank <= 3 else UiTheme.CREAM
		elif c == 1:
			color = UiTheme.GOLD_LIGHT
		var l := UiTheme.make_label(str(cells[c]), &"BigLabel" if c <= 1 else &"", 26 if c <= 1 else 19, color)
		l.custom_minimum_size = Vector2(COLUMN_WIDTHS[c], 0)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(l)
	return panel


func _build() -> void:
	var body := UiTheme.build_modal(self, 1120.0, 0.7)
	close_button = UiTheme.make_button("CLOSE  [Esc]", &"BlackButton")
	close_button.pressed.connect(close)
	var header := UiTheme.make_header("LEADERBOARDS", close_button)
	title_label = header.get_child(0) as Label
	body.add_child(header)
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	for crew in range(1, Profile.MAX_CREW + 1):
		var b := UiTheme.make_button(crew_name(crew).to_upper(), &"BlueButton", Vector2(0, 46))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override(&"font_size", 20)
		b.pressed.connect(show_crew.bind(crew))
		tabs.add_child(b)
		crew_buttons.append(b)
	# Inset like the rows (InsetPanel: 10 px margin + 1 px border) so the columns line up.
	var head_margin := MarginContainer.new()
	head_margin.add_theme_constant_override(&"margin_left", 11)
	head_margin.add_theme_constant_override(&"margin_right", 11)
	body.add_child(head_margin)
	var head := HBoxContainer.new()
	head_margin.add_child(head)
	for c in COLUMNS.size():
		var l := UiTheme.make_label(str(COLUMNS[c]), &"SmallLabel")
		l.custom_minimum_size = Vector2(COLUMN_WIDTHS[c], 0)
		head.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	rows_box = VBoxContainer.new()
	rows_box.add_theme_constant_override(&"separation", 4)
	list.add_child(rows_box)
	empty_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY, UiTheme.MUTED)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list.add_child(empty_label)
	best_label = UiTheme.make_label("", &"BigLabel", 22)
	body.add_child(best_label)
	var foot := UiTheme.make_label("Score = chips banked at The Apex + %s per minute survived there. Local scores on this machine; Steam leaderboards come later." % UiTheme.chips(Tuning.SCORE_PER_MINUTE_AT_TOP), &"SmallLabel", 17)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(foot)
