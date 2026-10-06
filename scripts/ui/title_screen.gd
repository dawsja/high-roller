class_name TitleScreen
extends Control
## Title screen: start a run at The Apex, practice at Sal's Back Room, see the
## controls sheet (every InputSetup action with its keys and pad buttons), or quit.

signal start_requested(start_rung: int, practice: bool)
signal quit_requested()

## What each InputSetup action does, for the controls sheet.
const ACTION_TEXT := {
	&"move_forward": "Move forward",
	&"move_back": "Move back",
	&"move_left": "Move left",
	&"move_right": "Move right",
	&"run": "Run (guards notice runners)",
	&"jump": "Jump / mash to struggle when carried",
	&"dive": "Dive",
	&"interact": "Interact (hold for posters)",
	&"tackle": "Tackle a guard (frees a teammate)",
	&"throw_chips": "Throw chips: the crowd rushes in",
	&"knock_over": "Knock over a tray (noise)",
	&"pause": "Pause",
	&"toggle_debug": "Debug overlay",
	&"ui_quiz_1": "ID quiz answer 1 / table choice 1",
	&"ui_quiz_2": "ID quiz answer 2 / table choice 2",
	&"ui_quiz_3": "ID quiz answer 3 / table choice 3",
}

const _PAD_BUTTONS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L-stick click", JOY_BUTTON_RIGHT_STICK: "R-stick click",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
}

var host: SimHost = null
var pid: int = 1

var title_label: Label
var tagline_label: Label
var start_button: Button
var practice_button: Button
var controls_button: Button
var quit_button: Button
var controls_panel: Control
var controls_back_button: Button
## Action names listed on the controls sheet, in order.
var listed_actions: Array[StringName] = []

var _menu: VBoxContainer
var _column: VBoxContainer
var _time: float = 0.0
var _chips: Array[Dictionary] = []


func _init() -> void:
	name = "TitleScreen"
	theme = UiTheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var colors: Array[Color] = [UiTheme.CHIP_RED, UiTheme.CHIP_BLACK, UiTheme.CHIP_BLUE, UiTheme.CHIP_GREEN, UiTheme.GOLD]
	while _chips.size() < 22:
		var pos := Vector2(rng.randf(), rng.randf())
		# Keep the middle clear for the title and the menu.
		if pos.x > 0.17 and pos.x < 0.83 and pos.y > 0.04 and pos.y < 0.96:
			continue
		_chips.append({
			"pos": pos,
			"r": rng.randf_range(22.0, 48.0),
			"color": colors[rng.randi_range(0, colors.size() - 1)],
			"speed": rng.randf_range(0.2, 0.6),
			"phase": rng.randf() * TAU,
		})
	_build()


## Kept for the shared panel interface; the title screen needs no sim.
func setup(p_host: SimHost, p_pid: int) -> void:
	host = p_host
	pid = p_pid


func show_controls(on: bool = true) -> void:
	controls_panel.visible = on
	_column.visible = not on
	if is_inside_tree():
		if on:
			controls_back_button.grab_focus()
		else:
			start_button.grab_focus()


func _ready() -> void:
	start_button.grab_focus()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if visible and controls_panel.visible and event.is_action_pressed(&"ui_cancel"):
		show_controls(false)
		get_viewport().set_input_as_handled()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, UiTheme.FELT_DARK)
	# Soft spotlight on the felt.
	var center := size * Vector2(0.5, 0.42)
	for i in 10:
		var k: float = 1.0 - float(i) / 10.0
		draw_circle(center, size.length() * 0.5 * k, Color(UiTheme.FELT_LIGHT, 0.06))
	for c: Dictionary in _chips:
		var p: Vector2 = (c["pos"] as Vector2) * size
		p.y += sin(_time * float(c["speed"]) + float(c["phase"])) * 10.0
		_draw_chip(p, float(c["r"]), c["color"] as Color)
	# Gold frame.
	draw_rect(r.grow(-18.0), UiTheme.GOLD, false, 4.0)
	draw_rect(r.grow(-28.0), Color(UiTheme.GOLD, 0.4), false, 2.0)


func _draw_chip(p: Vector2, radius: float, color: Color) -> void:
	draw_circle(p + Vector2(3, 5), radius, Color(0, 0, 0, 0.35))
	draw_circle(p, radius, color)
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(p + dir * radius * 0.72, p + dir * radius * 0.98, UiTheme.CREAM, radius * 0.22)
	draw_circle(p, radius * 0.62, color.lightened(0.15))
	draw_arc(p, radius * 0.62, 0.0, TAU, 24, Color(UiTheme.CREAM, 0.8), 2.0)


static func describe_events(action: StringName) -> Dictionary:
	var keys: PackedStringArray = []
	var pad: PackedStringArray = []
	var map: Dictionary = InputSetup.bindings()
	for event: InputEvent in map.get(action, []):
		if event is InputEventKey:
			var k: InputEventKey = event
			keys.append(OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode))
		elif event is InputEventJoypadButton:
			var jb: InputEventJoypadButton = event
			pad.append(str(_PAD_BUTTONS.get(jb.button_index, "Button %d" % jb.button_index)))
		elif event is InputEventJoypadMotion:
			var jm: InputEventJoypadMotion = event
			match jm.axis:
				JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y:
					pad.append("Left stick")
				JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y:
					pad.append("Right stick")
				JOY_AXIS_TRIGGER_LEFT:
					pad.append("LT")
				JOY_AXIS_TRIGGER_RIGHT:
					pad.append("RT")
	return {"keys": " / ".join(keys), "pad": " / ".join(pad)}


func _build() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	center.add_child(column)
	_column = column
	title_label = UiTheme.make_label("HIGH ROLLER", &"TitleLabel", 128)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_constant_override(&"outline_size", 22)
	column.add_child(title_label)
	tagline_label = UiTheme.make_label("Win too much. Stay on the floor.", &"BigLabel", 32)
	tagline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(tagline_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 16)
	column.add_child(gap)

	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override(&"separation", 14)
	column.add_child(_menu)
	var apex: Dictionary = CasinoLadder.casino(Tuning.TOP_RUNG)
	var sals: Dictionary = CasinoLadder.casino(Tuning.BOTTOM_RUNG)
	var guards: int = int(sals.get("guards", 1))
	start_button = _menu_button("Start run at %s" % str(apex.get("name", "The Apex")), &"")
	start_button.pressed.connect(func() -> void: start_requested.emit(Tuning.TOP_RUNG, false))
	practice_button = _menu_button("Practice at %s (%d guard%s)" % [str(sals.get("name", "Sal's Back Room")), guards, "" if guards == 1 else "s"], &"GreenButton")
	practice_button.pressed.connect(func() -> void: start_requested.emit(Tuning.BOTTOM_RUNG, true))
	controls_button = _menu_button("Controls", &"BlueButton")
	controls_button.pressed.connect(show_controls.bind(true))
	quit_button = _menu_button("Quit", &"RedButton")
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	var foot := UiTheme.make_label("A co-op casino party game  ·  phase 1 prototype", &"SmallLabel")
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(foot)

	var overlay := CenterContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	controls_panel = _build_controls()
	controls_panel.visible = false
	overlay.add_child(controls_panel)


func _menu_button(text: String, variation: StringName) -> Button:
	var b := UiTheme.make_button(text, variation, Vector2(640, 72))
	b.add_theme_font_size_override(&"font_size", 30)
	_menu.add_child(b)
	return b


func _build_controls() -> Control:
	var panel := UiTheme.make_panel()
	var v := VBoxContainer.new()
	panel.add_child(v)
	controls_back_button = UiTheme.make_button("BACK  [Esc]", &"BlackButton")
	controls_back_button.pressed.connect(show_controls.bind(false))
	v.add_child(UiTheme.make_header("CONTROLS", controls_back_button))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 28)
	grid.add_theme_constant_override(&"v_separation", 4)
	v.add_child(grid)
	for h: String in ["ACTION", "KEYBOARD", "GAMEPAD"]:
		grid.add_child(UiTheme.make_label(h, &"SmallLabel"))
	for action: StringName in InputSetup.ACTIONS:
		var ev: Dictionary = describe_events(action)
		grid.add_child(UiTheme.make_label(str(ACTION_TEXT.get(action, String(action).capitalize())), &"", 20))
		grid.add_child(UiTheme.make_label(str(ev["keys"]), &"", 20, UiTheme.GOLD_LIGHT))
		grid.add_child(UiTheme.make_label(str(ev["pad"]), &"SmallLabel", 18))
		listed_actions.append(action)
	v.add_child(HSeparator.new())
	var table := UiTheme.make_label("At a table: SPACE bet / deal / cash out  ·  1 2 3 choices  ·  ESC or BACKSPACE leave", &"SmallLabel", 18)
	table.add_theme_color_override(&"font_color", UiTheme.CREAM)
	v.add_child(table)
	return panel
