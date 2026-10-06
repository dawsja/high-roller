class_name DebugOverlay
extends Control
## F3 debug overlay (toggle_debug): FPS, this player's raw Heat and status,
## guard states from a provider the director passes in, and a compact
## pretty-print of the sim snapshot. Never takes the mouse.

## Arrays longer than this print as "[n items]".
const MAX_ARRAY_ITEMS := 6
## Snapshot lines shown at most.
const MAX_LINES := 24

var host: SimHost = null
var pid: int = 1

var stats_label: Label
var guards_label: Label
var snapshot_label: Label

## Returns an Array of guard descriptions: Strings or Dictionaries
## (e.g. {id, type, state, target, position}).
var _guard_provider: Callable = Callable()
var _refresh_left: float = 0.0


func _init() -> void:
	name = "DebugOverlay"
	theme = UiTheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	UiTheme.ignore_mouse(self)
	visible = false


func setup(p_host: SimHost, p_pid: int) -> void:
	host = p_host
	pid = p_pid


## `provider.call()` -> Array of Strings or Dictionaries, one per guard.
func set_guard_provider(provider: Callable) -> void:
	_guard_provider = provider


func toggle() -> void:
	visible = not visible
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(&"toggle_debug") and event.is_action_pressed(&"toggle_debug"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and not InputMap.has_action(&"toggle_debug") and key.physical_keycode == KEY_F3:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = Tuning.UI_DEBUG_REFRESH_SECONDS
		refresh()


func refresh() -> void:
	var snap: Dictionary = host.snapshot() if host != null else {}
	var players: Dictionary = snap.get("players", {})
	var me: Dictionary = players.get(pid, {})
	var lines: PackedStringArray = []
	lines.append("FPS %d   physics %d Hz   paused %s" % [Engine.get_frames_per_second(), Engine.physics_ticks_per_second, str(host.paused) if host != null else "-"])
	if not me.is_empty():
		lines.append("P%d heat %.3f  %s  status %s  zone %d %s  table %s" % [
			pid, float(me.get("heat", 0.0)), UiTheme.level_name(int(me.get("level", 0))),
			UiTheme.status_name(int(me.get("status", 0))), int(me.get("zone", 0)),
			str(me.get("area_id", "")), str(me.get("table_id", "")),
		])
		lines.append("flags %s" % str(me.get("flags", {})))
	stats_label.text = "\n".join(lines)
	guards_label.text = "\n".join(guard_lines())
	snapshot_label.text = "\n".join(format_snapshot(snap))


## One line per guard from the provider ("no guard provider" without one).
func guard_lines() -> PackedStringArray:
	var out: PackedStringArray = ["GUARDS"]
	if not _guard_provider.is_valid():
		out.append("  (no guard provider)")
		return out
	var guards: Variant = _guard_provider.call()
	if not guards is Array:
		out.append("  %s" % str(guards))
		return out
	for g: Variant in guards:
		if g is Dictionary:
			var parts: PackedStringArray = []
			var d: Dictionary = g
			for k: Variant in d:
				parts.append("%s=%s" % [str(k), _short(d[k])])
			out.append("  " + " ".join(parts))
		else:
			out.append("  " + str(g))
	return out


## The snapshot as compact lines: one "key: k=v k=v" line per sub-dictionary
## (players and tables get a line each), scalars gathered on the last line.
static func format_snapshot(snap: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = ["SNAPSHOT"]
	var loose: PackedStringArray = []
	for key: Variant in snap:
		var v: Variant = snap[key]
		if v is Dictionary and not (v as Dictionary).is_empty():
			var d: Dictionary = v
			if d.values().all(func(x: Variant) -> bool: return x is Dictionary):
				out.append("%s:" % str(key))
				for sub: Variant in d:
					out.append("  %s: %s" % [str(sub), _flat(d[sub])])
			else:
				out.append("%s: %s" % [str(key), _flat(d)])
		else:
			loose.append("%s=%s" % [str(key), _short(v)])
	if not loose.is_empty():
		out.append(" ".join(loose))
	if out.size() > MAX_LINES:
		var extra: int = out.size() - MAX_LINES
		out = out.slice(0, MAX_LINES)
		out.append("... %d more lines" % extra)
	return out


static func _flat(d: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: Variant in d:
		var v: Variant = d[k]
		if v is Dictionary:
			var inner: Dictionary = v
			parts.append("%s=%s" % [str(k), str(inner["name"]) if inner.has("name") else "{%d}" % inner.size()])
		else:
			parts.append("%s=%s" % [str(k), _short(v)])
	return " ".join(parts)


static func _short(v: Variant) -> String:
	if v is float:
		return "%.2f" % float(v)
	if v is Vector3:
		var p: Vector3 = v
		return "(%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
	if v is Array:
		var a: Array = v
		if a.size() > MAX_ARRAY_ITEMS or (not a.is_empty() and (a[0] is Dictionary or a[0] is Array)):
			return "[%d items]" % a.size()
	return str(v)


func _build() -> void:
	var panel := UiTheme.make_panel(&"HudPanel")
	panel.position = Vector2(16, 200)
	panel.custom_minimum_size = Vector2(640, 0)
	panel.self_modulate = Color(1, 1, 1, 0.92)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 6)
	panel.add_child(v)
	var title := UiTheme.make_label("DEBUG  (F3)", &"SmallLabel")
	title.add_theme_color_override(&"font_color", UiTheme.GOLD)
	v.add_child(title)
	stats_label = _mono_label(15)
	v.add_child(stats_label)
	guards_label = _mono_label(14)
	v.add_child(guards_label)
	snapshot_label = _mono_label(13)
	snapshot_label.max_lines_visible = 22
	v.add_child(snapshot_label)


func _mono_label(font_size: int) -> Label:
	var l := UiTheme.make_label("", &"", font_size, UiTheme.CREAM)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
	l.add_theme_font_override(&"font", mono)
	l.add_theme_constant_override(&"outline_size", 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(612, 0)
	return l
