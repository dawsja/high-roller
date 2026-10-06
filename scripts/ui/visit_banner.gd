class_name VisitBanner
extends Control
## The big animated card between visits: thrown out (from -> to casino),
## climbed, a curb timeout at Sal's, or the end-of-run summary with the score.
## Listens for &"thrown_out", &"climbed" and &"curb" itself. Visit cards close
## after Tuning.UI_VISIT_BANNER_SECONDS or on Continue (Space / Enter); the run
## summary waits for its button.

signal closed()

const KIND_THROWN_OUT := &"thrown_out"
const KIND_CLIMBED := &"climbed"
const KIND_CURB := &"curb"
const KIND_SUMMARY := &"summary"
const _POP_SECONDS := 0.35

var host: SimHost = null
var pid: int = 1
## Which card is showing (KIND_*), &"" when hidden.
var kind: StringName = &""

var card: PanelContainer
var title_label: Label
var route_label: Label
var detail_label: Label
var continue_button: Button

var _left: float = 0.0
var _shown: float = 0.0


func _init() -> void:
	name = "VisitBanner"
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


func show_thrown_out(from_rung: int, to_rung: int, cause: StringName = &"strikes") -> void:
	var why := "Three strikes!" if cause == &"strikes" else "The whole crew got hauled off!"
	if cause == &"broke":
		why = "Out of chips!"
	_show(KIND_THROWN_OUT, "THROWN OUT!", UiTheme.LOSS_COLOR,
		"%s  >>  %s" % [_casino_name(from_rung), _casino_name(to_rung)],
		"%s Down to rung %d of %d. Your banked chips came with you." % [why, to_rung, Tuning.BOTTOM_RUNG], true)


func show_climbed(from_rung: int, to_rung: int, cost: int = 0) -> void:
	var detail := "Buy-in paid: %s chips." % UiTheme.chips(cost) if cost > 0 else "Up you go."
	if to_rung == Tuning.TOP_RUNG:
		detail += " Welcome to the top: every chip banked here scores."
	_show(KIND_CLIMBED, "CLIMBED!", UiTheme.WIN_COLOR,
		"%s  >>  %s" % [_casino_name(from_rung), _casino_name(to_rung)], detail, true)


func show_curb(seconds: float) -> void:
	_show(KIND_CURB, "ON THE CURB", UiTheme.heat_color(HR.HeatLevel.SUSPECTED),
		"Sal tossed the whole crew out",
		"Back inside in %d seconds. Sal's is the bottom: no lower to fall." % ceili(seconds), true)


## End of run. `stats` keys (all optional): score, top_banked, top_seconds,
## elapsed_seconds, visits, rung. Defaults to the host's run.
func show_run_summary(stats: Dictionary = {}) -> void:
	var s: Dictionary = stats
	if s.is_empty() and host != null:
		s = host.snapshot().get("run", {})
	var lines: PackedStringArray = []
	lines.append("Banked at The Apex: %s" % UiTheme.chips(int(s.get("top_banked", 0))))
	lines.append("Time at the top: %s" % UiTheme.clock(float(s.get("top_seconds", 0.0))))
	lines.append("Run time: %s  ·  Casino visits: %d" % [UiTheme.clock(float(s.get("elapsed_seconds", 0.0))), int(s.get("visits", 1))])
	_show(KIND_SUMMARY, "RUN OVER", UiTheme.GOLD,
		"SCORE  %s" % UiTheme.chips(int(s.get("score", 0))), "\n".join(lines), false)
	continue_button.text = "BACK TO TITLE"


func dismiss() -> void:
	if not visible:
		return
	visible = false
	kind = &""
	closed.emit()


func is_open() -> bool:
	return visible


func handle_key(keycode: Key) -> bool:
	if not visible:
		return false
	if keycode == KEY_SPACE or keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		dismiss()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if handle_key(code):
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	advance(delta)


## Pop-in animation and auto-close timer (called from _process).
func advance(delta: float) -> void:
	if not visible:
		return
	_shown += delta
	var k: float = clampf(_shown / _POP_SECONDS, 0.0, 1.0)
	var s: float = lerpf(0.5, 1.0, ease(k, 0.35)) + 0.08 * sin(PI * k)
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(s, s)
	card.rotation = deg_to_rad(lerpf(-6.0, 0.0, k))
	card.modulate.a = k
	if _left > 0.0:
		_left -= delta
		if _left <= 0.0:
			dismiss()


func _on_sim_event(event_kind: StringName, data: Dictionary) -> void:
	match event_kind:
		&"thrown_out":
			show_thrown_out(int(data.get("from", 0)), int(data.get("to", 0)), StringName(str(data.get("cause", ""))))
		&"climbed":
			show_climbed(int(data.get("from", 0)), int(data.get("to", 0)), int(data.get("cost", 0)))
		&"curb":
			show_curb(float(data.get("seconds", Tuning.CURB_TIMEOUT)))


func _show(p_kind: StringName, title: String, color: Color, route: String, detail: String, auto_close: bool) -> void:
	kind = p_kind
	title_label.text = title
	title_label.add_theme_color_override(&"font_color", color)
	route_label.text = route
	detail_label.text = detail
	continue_button.text = "CONTINUE  [Space]"
	_left = Tuning.UI_VISIT_BANNER_SECONDS if auto_close else 0.0
	_shown = 0.0
	card.add_theme_stylebox_override(&"panel", _card_box(color))
	visible = true
	advance(0.0)


func _casino_name(rung: int) -> String:
	return str(CasinoLadder.casino(rung).get("name", "Rung %d" % rung))


func _card_box(color: Color) -> StyleBoxFlat:
	var box := UiTheme.flat_box(Color(UiTheme.FELT, 0.98), color, 6, 22, 34)
	box.shadow_color = Color(0, 0, 0, 0.6)
	box.shadow_size = 24
	return box


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	card = UiTheme.make_panel()
	card.custom_minimum_size = Vector2(900, 0)
	center.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 16)
	card.add_child(v)
	title_label = UiTheme.make_label("", &"TitleLabel", 110)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_constant_override(&"outline_size", 20)
	v.add_child(title_label)
	route_label = UiTheme.make_label("", &"HeaderLabel", 40)
	route_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(route_label)
	detail_label = UiTheme.make_label("", &"BigLabel", 26)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(detail_label)
	continue_button = UiTheme.make_button("CONTINUE  [Space]", &"", Vector2(360, 64))
	continue_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	continue_button.add_theme_font_size_override(&"font_size", 28)
	continue_button.pressed.connect(dismiss)
	v.add_child(continue_button)
