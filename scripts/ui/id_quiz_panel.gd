class_name IdQuizPanel
extends Control
## The ID check quiz. Opens on this player's &"id_check" event (or
## open_check(data) with that event's data): the guard asks one detail from the
## card in use — the card itself is NOT shown — and the player picks one of
## three big answers (keys 1 / 2 / 3) before the timer bar runs out
## (request_answer_id_check / request_expire_id_check). An auto-fail (no card,
## burned, flagged, spotted cheap fake) shows its reason. The pass/fail result
## stays up for Tuning.UI_QUIZ_RESULT_SECONDS, then the panel closes (at once
## if this player is grabbed or the visit ends). The answer's result arrives
## as host.request_done (or the &"id_result" event).

signal answered(passed: bool)
signal closed()

var host: SimHost = null
var pid: int = 1

var title_label: Label
var prompt_label: Label
var quote_label: Label
var option_buttons: Array[Button] = []
var timer_bar: ProgressBar
var result_label: Label
var reason_label: Label
var hint_label: Label

var _question: Dictionary = {}
var _seconds: float = Tuning.ID_QUIZ_SECONDS
var _left: float = 0.0
## Seconds left showing the result (> 0 once answered).
var _result_left: float = 0.0
var _answering: bool = false


func _init() -> void:
	name = "IdQuizPanel"
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


## Opens the quiz. `data` is the &"id_check" event data ({auto_fail,
## fail_reason, question, seconds}) or just its question {field, prompt, options}.
## Re-opening with the question already showing does nothing.
func open_check(data: Dictionary) -> void:
	var question: Dictionary = data.get("question", {}) if data.has("question") else data
	var auto_fail: bool = bool(data.get("auto_fail", false))
	if visible and _result_left <= 0.0 and not auto_fail and _same_question(question):
		return
	_question = question.duplicate(true)
	_answering = false
	visible = true
	if auto_fail:
		_show_auto_fail(StringName(str(data.get("fail_reason", ""))))
		return
	_seconds = float(data.get("seconds", Tuning.ID_QUIZ_SECONDS))
	if _seconds <= 0.0:
		_seconds = Tuning.ID_QUIZ_SECONDS
	_left = _seconds
	_result_left = 0.0
	var field: StringName = StringName(str(_question.get("field", "")))
	title_label.text = "ID CHECK!"
	title_label.add_theme_color_override(&"font_color", UiTheme.heat_color(HR.HeatLevel.SUSPECTED))
	prompt_label.text = "Guard: What's your %s?" % IdQuiz.field_label(field).to_lower()
	quote_label.text = "\"%s\"" % str(_question.get("prompt", ""))
	quote_label.visible = quote_label.text != "\"\""
	var options: Array = _question.get("options", [])
	for i in option_buttons.size():
		var b: Button = option_buttons[i]
		b.visible = i < options.size()
		b.disabled = false
		b.modulate = Color.WHITE
		b.remove_theme_stylebox_override(&"disabled")
		b.remove_theme_color_override(&"font_disabled_color")
		if i < options.size():
			b.text = "%d   %s" % [i + 1, str(options[i])]
	timer_bar.visible = true
	timer_bar.max_value = _seconds
	timer_bar.value = _left
	result_label.visible = false
	reason_label.visible = false
	hint_label.visible = true


func is_open() -> bool:
	return visible


## True while the player can still pick an answer.
func is_waiting() -> bool:
	return visible and _result_left <= 0.0 and not _question.is_empty()


func seconds_left() -> float:
	return _left


## Picks option `index` (0-based).
func answer(index: int) -> void:
	if not is_waiting() or _answering or host == null:
		return
	var options: Array = _question.get("options", [])
	if index < 0 or index >= options.size():
		return
	_answering = true
	host.request_answer_id_check(pid, index)


func _on_request_done(request: StringName, args: Array, res: Dictionary) -> void:
	if request != &"answer_id_check" or args.size() < 2 or int(args[0]) != pid:
		return
	_answering = false
	if not visible:
		return
	if not bool(res.get("ok", false)):
		if _result_left <= 0.0:
			_show_result(false, StringName(str(res.get("reason", ""))))
		return
	var passed: bool = bool(res.get("passed", false))
	if _result_left <= 0.0:
		_show_result(passed, FloorSim.ID_CORRECT if passed else FloorSim.ID_WRONG)
	_mark_choice(int(args[1]), passed)


## The timer ran out.
func expire() -> void:
	if not is_waiting() or host == null:
		return
	_answering = true
	host.request_expire_id_check(pid)
	_answering = false
	if _result_left <= 0.0:
		_show_result(false, FloorSim.ID_TIMEOUT)


func close() -> void:
	if not visible:
		return
	visible = false
	_question = {}
	_result_left = 0.0
	closed.emit()


func handle_key(keycode: Key) -> bool:
	if not is_waiting():
		return false
	match keycode:
		KEY_1, KEY_KP_1:
			answer(0)
		KEY_2, KEY_KP_2:
			answer(1)
		KEY_3, KEY_KP_3:
			answer(2)
		_:
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not is_waiting():
		return
	for i in 3:
		var action := StringName("ui_quiz_%d" % (i + 1))
		if InputMap.has_action(action) and event.is_action_pressed(action):
			answer(i)
			get_viewport().set_input_as_handled()
			return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if handle_key(code):
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	advance(delta)


## Timer bar and result countdown (called from _process).
func advance(delta: float) -> void:
	if not visible:
		return
	if _result_left > 0.0:
		_result_left -= delta
		if _result_left <= 0.0:
			close()
		return
	if _question.is_empty():
		return
	_left = maxf(0.0, _left - delta)
	timer_bar.value = _left
	var k: float = _left / maxf(_seconds, 0.001)
	var fill_color: Color = UiTheme.WIN_COLOR.lerp(UiTheme.LOSS_COLOR, 1.0 - k)
	timer_bar.add_theme_stylebox_override(&"fill", UiTheme.flat_box(fill_color, fill_color.lightened(0.3), 0, 8, 0))
	if _left <= 0.0:
		expire()


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	# Grabbed or the crew left: the sim dropped any check without an id_result,
	# and a result card still up (a failed check, then the grab) goes too.
	if UiTheme.ends_panel(kind, data, pid):
		if visible:
			close()
		return
	if int(data.get("pid", -1)) != pid:
		return
	match kind:
		&"id_check":
			open_check(data)
		&"id_result":
			_answering = false
			# Our answer, our timeout or the sim's own timeout: show it once.
			if visible and _result_left <= 0.0:
				_show_result(bool(data.get("passed", false)), StringName(str(data.get("reason", ""))))


func _same_question(q: Dictionary) -> bool:
	return not _question.is_empty() and str(q.get("prompt", "")) == str(_question.get("prompt", "")) \
		and str(q.get("options", [])) == str(_question.get("options", []))


## Paints the picked answer green (passed) or red (failed) and dims the rest.
func _mark_choice(index: int, passed: bool) -> void:
	var color: Color = UiTheme.CHIP_GREEN if passed else UiTheme.CHIP_RED
	for i in option_buttons.size():
		var b: Button = option_buttons[i]
		if i == index:
			b.add_theme_stylebox_override(&"disabled", UiTheme.chip_box(color, color.darkened(0.45)))
			b.add_theme_color_override(&"font_disabled_color", UiTheme.CREAM)
			b.modulate = Color.WHITE
		else:
			b.modulate = Color(1, 1, 1, 0.4)


func _show_auto_fail(reason: StringName) -> void:
	title_label.text = "ID CHECK!"
	title_label.add_theme_color_override(&"font_color", UiTheme.heat_color(HR.HeatLevel.WANTED))
	prompt_label.text = "Guard: Let me see that ID..."
	quote_label.visible = false
	for b: Button in option_buttons:
		b.visible = false
	timer_bar.visible = false
	_show_result(false, reason)


func _show_result(passed: bool, reason: StringName) -> void:
	_result_left = Tuning.UI_QUIZ_RESULT_SECONDS
	for b: Button in option_buttons:
		b.disabled = true
	timer_bar.visible = false
	hint_label.visible = false
	result_label.visible = true
	reason_label.visible = true
	if passed:
		result_label.text = "PASSED"
		result_label.add_theme_color_override(&"font_color", UiTheme.WIN_COLOR)
		reason_label.text = "The guard nods you through. Act natural."
	else:
		result_label.text = "FAILED!"
		result_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR)
		reason_label.text = "%s Run!" % UiTheme.reason_text(reason)
	answered.emit(passed)


func _build() -> void:
	var body := UiTheme.build_modal(self, 760.0, 0.35)
	title_label = UiTheme.make_label("ID CHECK!", &"TitleLabel", 64)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title_label)
	prompt_label = UiTheme.make_label("", &"BigLabel", 34)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(prompt_label)
	quote_label = UiTheme.make_label("", &"SmallLabel", 22)
	quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(quote_label)
	timer_bar = ProgressBar.new()
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(0, 22)
	timer_bar.max_value = Tuning.ID_QUIZ_SECONDS
	body.add_child(timer_bar)
	var variations: Array[StringName] = [&"", &"BlueButton", &"RedButton"]
	for i in 3:
		var b := UiTheme.make_button("", variations[i], Vector2(0, 72))
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override(&"font_size", 32)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(answer.bind(i))
		body.add_child(b)
		option_buttons.append(b)
	result_label = UiTheme.make_label("", &"TitleLabel", 72)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.visible = false
	body.add_child(result_label)
	reason_label = UiTheme.make_label("", &"BigLabel", 26)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason_label.visible = false
	body.add_child(reason_label)
	hint_label = UiTheme.make_label("Press 1, 2 or 3. Don't hesitate: guards notice.", &"SmallLabel")
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint_label)
