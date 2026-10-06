class_name PauseMenu
extends Control
## Pause menu: resume, restart the run or quit to the title. Only emits signals
## (main.gd pauses the host and swaps scenes). Runs while the tree is paused.
## Shows a short run summary from the host snapshot.

signal resume_requested()
signal restart_requested()
signal quit_to_title_requested()
signal closed()

var host: SimHost = null
var pid: int = 1

var resume_button: Button
var restart_button: Button
var quit_button: Button
var summary_label: Label

var _opened_frame: int = -1


func _init() -> void:
	name = "PauseMenu"
	theme = UiTheme.make_theme()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func setup(p_host: SimHost, p_pid: int) -> void:
	host = p_host
	pid = p_pid


func open() -> void:
	visible = true
	_opened_frame = Engine.get_process_frames()
	_refresh_summary()
	if is_inside_tree():
		resume_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func resume() -> void:
	resume_requested.emit()
	close()


func _unhandled_input(event: InputEvent) -> void:
	# The Esc press that opened the menu must not close it again.
	if not visible or Engine.get_process_frames() == _opened_frame:
		return
	var pause_action: bool = InputMap.has_action(&"pause") and event.is_action_pressed(&"pause")
	if pause_action or event.is_action_pressed(&"ui_cancel"):
		resume()
		get_viewport().set_input_as_handled()


func _refresh_summary() -> void:
	var snap: Dictionary = host.snapshot() if host != null else {}
	var run: Dictionary = snap.get("run", {})
	if run.is_empty():
		summary_label.text = ""
		return
	var rung: int = int(run.get("rung", Tuning.TOP_RUNG))
	var name_text: String = str(run.get("casino_name", CasinoLadder.casino(rung).get("name", "")))
	var lines: PackedStringArray = []
	lines.append("%s  ·  Rung %d of %d" % [name_text, rung, Tuning.BOTTOM_RUNG])
	lines.append("Strikes %d / %d  ·  Crew bank %s" % [int(run.get("strikes", 0)), int(run.get("max_strikes", Tuning.STRIKES_TO_THROW_OUT)), UiTheme.chips(int(run.get("bank", 0)))])
	lines.append("Score %s  ·  Run time %s" % [UiTheme.chips(int(run.get("score", 0))), UiTheme.clock(float(run.get("elapsed_seconds", 0.0)))])
	summary_label.text = "\n".join(lines)


func _build() -> void:
	var body := UiTheme.build_modal(self, 560.0, 0.6)
	var title := UiTheme.make_label("PAUSED", &"TitleLabel", 80)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	summary_label = UiTheme.make_label("", &"SmallLabel", 20)
	summary_label.add_theme_color_override(&"font_color", UiTheme.CREAM)
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(summary_label)
	resume_button = UiTheme.make_button("Resume", &"GreenButton", Vector2(0, 68))
	resume_button.add_theme_font_size_override(&"font_size", 30)
	resume_button.pressed.connect(resume)
	body.add_child(resume_button)
	restart_button = UiTheme.make_button("Restart run", &"", Vector2(0, 68))
	restart_button.add_theme_font_size_override(&"font_size", 30)
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	body.add_child(restart_button)
	quit_button = UiTheme.make_button("Quit to title", &"RedButton", Vector2(0, 68))
	quit_button.add_theme_font_size_override(&"font_size", 30)
	quit_button.pressed.connect(func() -> void: quit_to_title_requested.emit())
	body.add_child(quit_button)
