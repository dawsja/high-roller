class_name Hud
extends Control
## The in-game heads-up display (full screen, never takes the mouse): the Heat
## meter, pocket chips, crew bank and climb progress, strikes, casino and rung,
## visit clock (score at The Apex), the fake ID in use, the worn outfit, the
## interact prompt, a notification feed, a big center banner and a status line
## while carried, detained or on the curb.
##
## Reads host.snapshot() every Tuning.UI_REFRESH_SECONDS and reacts to
## host.sim_event right away. It never sends requests.

## Heat bar with level zones and tick marks at the level thresholds.
class HeatBar extends Control:

	var value: float = 0.0
	var color: Color = UiTheme.heat_color(HR.HeatLevel.UNNOTICED)

	func _init() -> void:
		custom_minimum_size = Vector2(0, 38)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_heat(v: float, level: int) -> void:
		value = clampf(v, 0.0, Tuning.HEAT_MAX)
		color = UiTheme.heat_color(level)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiTheme.flat_box(Color(0.02, 0.06, 0.04, 0.95), UiTheme.GOLD_DARK, 2, 9, 0), r)
		var inner := r.grow(-4.0)
		# Faint level zones so the thresholds read at a glance.
		var bounds: Array[float] = [0.0, Tuning.WATCHED_AT, Tuning.SUSPECTED_AT, Tuning.WANTED_AT, Tuning.HEAT_MAX]
		for i in 4:
			var x0: float = inner.position.x + inner.size.x * bounds[i] / Tuning.HEAT_MAX
			var x1: float = inner.position.x + inner.size.x * bounds[i + 1] / Tuning.HEAT_MAX
			draw_rect(Rect2(x0, inner.position.y, x1 - x0, inner.size.y), Color(UiTheme.heat_color(i), 0.16))
		var fill_w: float = inner.size.x * value / Tuning.HEAT_MAX
		if fill_w > 0.5:
			var fill := UiTheme.flat_box(color, color.lightened(0.35), 0, 6, 0)
			draw_style_box(fill, Rect2(inner.position, Vector2(maxf(fill_w, 8.0), inner.size.y)))
			draw_rect(Rect2(inner.position + Vector2(4, 3), Vector2(maxf(fill_w - 8.0, 0.0), inner.size.y * 0.28)), Color(1, 1, 1, 0.22))
		var font: Font = UiTheme.bold_font()
		for t: float in [Tuning.WATCHED_AT, Tuning.SUSPECTED_AT, Tuning.WANTED_AT]:
			var x: float = inner.position.x + inner.size.x * t / Tuning.HEAT_MAX
			draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(UiTheme.CREAM, 0.9), 3.0)
			draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(0, 0, 0, 0.6), 1.0)
			var label := str(int(t))
			var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string_outline(font, Vector2(x - w * 0.5, r.end.y + 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
			draw_string(font, Vector2(x - w * 0.5, r.end.y + 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.CREAM)


const _REFRESH_KINDS: Array[StringName] = [
	&"status", &"seated", &"stood", &"zone", &"outfit", &"id", &"banked", &"withdrawn", &"strike",
	&"rejoined", &"curb", &"detained", &"caught", &"freed", &"fire_alarm", &"poster",
	&"poster_removed", &"poster_defaced", &"look_recorded", &"player_joined", &"climbed", &"thrown_out",
]
const _BANNER_IN_SECONDS := 0.22
const _BANNER_OUT_SECONDS := 0.45
const _POPUP_SECONDS := 1.6

var host: SimHost = null
var pid: int = 1

var heat_panel: PanelContainer
var heat_bar: HeatBar
var heat_level_label: Label
var heat_value_label: Label
var heat_popup_label: Label
var casino_label: Label
var rung_label: Label
var clock_label: Label
var strike_icons: Array[Panel] = []
var pocket_label: Label
var bank_title_label: Label
var bank_label: Label
var bank_bar: ProgressBar
var bank_hint_label: Label
var id_panel: PanelContainer
var id_name_label: Label
var id_birthday_label: Label
var id_state_label: Label
var id_grade_label: Label
var id_cap_label: Label
var id_cap_bar: ProgressBar
var id_badge: PanelContainer
var id_badge_label: Label
var id_hidden_label: Label
var outfit_holder: HBoxContainer
var outfit_badge_label: Label
var prompt_panel: PanelContainer
var prompt_key_label: Label
var prompt_label: Label
var status_label: Label
var feed: VBoxContainer
var banner_label: Label

var _snap: Dictionary = {}
var _heat: float = 0.0
var _level: int = HR.HeatLevel.UNNOTICED
var _status: int = HR.PlayerStatus.FREE
var _refresh_left: float = 0.0
var _pulse_left: float = 0.0
var _popup_left: float = 0.0
var _banner_left: float = 0.0
var _banner_total: float = 0.0
var _time: float = 0.0
var _heat_holder: Control
var _outfit_key: String = ""
var _pocket_flash_left: float = 0.0
var _pocket_flash_color: Color = UiTheme.CREAM


func _init() -> void:
	name = "Hud"
	theme = UiTheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	UiTheme.ignore_mouse(self)
	set_prompt("")
	_render_heat()


func setup(p_host: SimHost, p_pid: int) -> void:
	if host != null:
		if host.sim_event.is_connected(_on_sim_event):
			host.sim_event.disconnect(_on_sim_event)
		if host.visit_started.is_connected(_on_visit_started):
			host.visit_started.disconnect(_on_visit_started)
	host = p_host
	pid = p_pid
	if host != null:
		host.sim_event.connect(_on_sim_event)
		host.visit_started.connect(_on_visit_started)
	refresh()


## Interact hint at the bottom of the screen; "" hides it. The director calls
## this from PlayerCharacter.focus_changed.
func set_prompt(text: String, key: String = "E") -> void:
	prompt_label.text = text
	prompt_key_label.text = key
	prompt_key_label.get_parent().visible = key != ""
	prompt_panel.visible = text != ""


## Big center text that pops in and fades out after `seconds`.
func show_banner(text: String, color: Color = UiTheme.GOLD, seconds: float = Tuning.UI_BANNER_SECONDS) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override(&"font_color", color)
	_banner_total = maxf(seconds, _BANNER_IN_SECONDS + _BANNER_OUT_SECONDS)
	_banner_left = _banner_total
	banner_label.visible = true
	_animate_banner()


## Adds a line to the notification feed (newest on top); it fades after
## Tuning.UI_NOTIFY_SECONDS.
func push_notification(text: String, color: Color = UiTheme.CREAM) -> void:
	var entry := UiTheme.make_panel(&"HudPanel")
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stripe := ColorRect.new()
	stripe.color = color
	stripe.custom_minimum_size = Vector2(6, 0)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stripe)
	var l := UiTheme.make_label(text, &"", UiTheme.FONT_BODY - 3, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(l)
	entry.add_child(box)
	entry.set_meta(&"age", 0.0)
	feed.add_child(entry)
	feed.move_child(entry, 0)
	while feed.get_child_count() > Tuning.UI_NOTIFY_MAX:
		var old: Node = feed.get_child(feed.get_child_count() - 1)
		feed.remove_child(old)
		old.queue_free()


## Texts of the feed entries, newest first (tests, debug).
func notification_texts() -> Array[String]:
	var out: Array[String] = []
	for entry: Node in feed.get_children():
		var labels: Array[Node] = entry.find_children("*", "Label", true, false)
		if not labels.is_empty():
			out.append((labels[0] as Label).text)
	return out


## Re-reads the host snapshot and redraws everything.
func refresh() -> void:
	_snap = host.snapshot() if host != null else {}
	var players: Dictionary = _snap.get("players", {})
	var me: Dictionary = players.get(pid, {})
	var run: Dictionary = _snap.get("run", {})
	if not me.is_empty():
		_heat = float(me.get("heat", 0.0))
		_level = int(me.get("level", HeatMeter.level_for(_heat)))
		_status = int(me.get("status", HR.PlayerStatus.FREE))
	_render_heat()
	_render_casino(run)
	_render_chips(me, run)
	_render_id(me)
	_render_outfit(me)
	_render_status(me)


func heat_value() -> float:
	return _heat


func heat_level() -> int:
	return _level


func _process(delta: float) -> void:
	advance(delta)


## Moves every HUD animation and the refresh clock forward (called from _process).
func advance(delta: float) -> void:
	_time += delta
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = Tuning.UI_REFRESH_SECONDS
		refresh()
	_age_feed(delta)
	_animate_heat(delta)
	if _banner_left > 0.0:
		_banner_left -= delta
		_animate_banner()
	if _popup_left > 0.0:
		_popup_left -= delta
		heat_popup_label.modulate.a = clampf(_popup_left / 0.5, 0.0, 1.0)
	if _pocket_flash_left > 0.0:
		_pocket_flash_left -= delta
		var k: float = clampf(_pocket_flash_left / 0.6, 0.0, 1.0)
		pocket_label.add_theme_color_override(&"font_color", UiTheme.CREAM.lerp(_pocket_flash_color, k))
	if _status == HR.PlayerStatus.CARRIED:
		status_label.modulate.a = 0.55 + 0.45 * absf(sin(_time * 7.0))
	else:
		status_label.modulate.a = 1.0


# --- Events -----------------------------------------------------------------

func _on_visit_started(_sim: FloorSim) -> void:
	refresh()


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	var who: int = int(data.get("pid", 0))
	var mine: bool = who == pid
	match kind:
		&"heat":
			if mine:
				_on_heat(data)
		&"level":
			if mine:
				_on_level(int(data.get("old", 0)), int(data.get("new", 0)))
		&"chips":
			if mine:
				pocket_label.text = UiTheme.chips(int(data.get("pocket", 0)))
				var d: int = int(data.get("delta", 0))
				_pocket_flash_color = UiTheme.WIN_COLOR if d > 0 else UiTheme.LOSS_COLOR
				_pocket_flash_left = 0.6
		&"dealer_swap":
			if mine:
				push_notification("Dealer swap! This table's luck just cooled off.", UiTheme.heat_color(HR.HeatLevel.WATCHED))
		&"look_recorded":
			if mine:
				push_notification("Security recorded your look. Time for a new outfit.", UiTheme.heat_color(HR.HeatLevel.SUSPECTED))
		&"poster":
			if mine:
				push_notification("A WANTED poster of your look just went up!", UiTheme.heat_color(HR.HeatLevel.WANTED))
			else:
				push_notification("Wanted poster printed for %s." % _name_of(who), UiTheme.heat_color(HR.HeatLevel.SUSPECTED))
		&"poster_match":
			if mine:
				push_notification("A guard matched you to a wanted poster!", UiTheme.heat_color(HR.HeatLevel.WANTED))
		&"poster_removed":
			push_notification("A wanted poster came down.", UiTheme.WIN_COLOR)
		&"strike":
			push_notification("STRIKE %d of %d!" % [int(data.get("strikes", 0)), int(data.get("max", Tuning.STRIKES_TO_THROW_OUT))], UiTheme.LOSS_COLOR)
		&"caught":
			if mine:
				show_banner("CAUGHT!", UiTheme.LOSS_COLOR)
				push_notification("A guard grabbed you! Mash SPACE to struggle.", UiTheme.LOSS_COLOR)
			else:
				push_notification("%s was grabbed! Tackle the guard (F)." % _name_of(who), UiTheme.LOSS_COLOR)
		&"freed":
			var tackler: int = int(data.get("tackler", 0))
			if mine:
				show_banner("FREE!", UiTheme.WIN_COLOR, 1.4)
				push_notification("You broke loose!" if tackler == 0 else "%s tackled the guard: you're free!" % _name_of(tackler), UiTheme.WIN_COLOR)
			elif tackler == pid:
				push_notification("You freed %s, but now you're WANTED." % _name_of(who), UiTheme.heat_color(HR.HeatLevel.WANTED))
		&"detained":
			if mine:
				var burned: String = str(data.get("id_name", ""))
				var text := "Back room: lost %s chips." % UiTheme.chips(int(data.get("chips_lost", 0)))
				if burned != "":
					text += " %s is burned." % burned
				push_notification(text, UiTheme.LOSS_COLOR)
		&"withdrawn":
			if mine:
				push_notification("Took %s chips out of the crew bank." % UiTheme.chips(int(data.get("amount", 0))), UiTheme.GOLD_LIGHT)
		&"banked":
			if mine:
				push_notification("Banked %s under %s." % [UiTheme.chips(int(data.get("amount", 0))), str(data.get("id_name", "?"))], UiTheme.GOLD_LIGHT)
		&"id":
			if mine:
				_on_id(data)
		&"id_result":
			if mine:
				var passed: bool = bool(data.get("passed", false))
				if passed:
					push_notification("ID check passed. Smooth.", UiTheme.WIN_COLOR)
				else:
					push_notification("ID check failed: %s" % UiTheme.reason_text(StringName(str(data.get("reason", "")))), UiTheme.LOSS_COLOR)
		&"fire_alarm":
			if bool(data.get("active", false)):
				show_banner("FIRE ALARM!", UiTheme.LOSS_COLOR)
				push_notification("Fire alarm: tables closed for %d s." % int(data.get("seconds", 0.0)), UiTheme.LOSS_COLOR)
			else:
				push_notification("Alarm over. Tables are open again.", UiTheme.WIN_COLOR)
		&"forger_moved":
			push_notification("The forger moved to the %s." % String(data.get("location", "")).replace("_", " "), UiTheme.MUTED)
		&"notify":
			if who == 0 or mine:
				var k: StringName = StringName(str(data.get("kind", "")))
				push_notification(str(data.get("text", "")), UiTheme.LOSS_COLOR if k == &"flagged" or k == &"broke" else UiTheme.GOLD_LIGHT)
		&"rejoined":
			if mine:
				push_notification("Back in the casino. Keep your head down.", UiTheme.WIN_COLOR)
		&"curb":
			push_notification("Tossed on the curb for %d s." % int(data.get("seconds", 0.0)), UiTheme.LOSS_COLOR)
	if _REFRESH_KINDS.has(kind):
		refresh()


func _on_heat(data: Dictionary) -> void:
	_heat = float(data.get("value", _heat))
	_level = int(data.get("level", HeatMeter.level_for(_heat)))
	var delta: float = float(data.get("delta", 0.0))
	var reason: StringName = StringName(str(data.get("reason", "")))
	_render_heat()
	if UiTheme.is_passive_heat(reason) or reason == HeatRules.RESET or absf(delta) < Tuning.UI_HEAT_POPUP_MIN:
		return
	heat_popup_label.text = "%s Heat  %s" % [UiTheme.signed(delta), String(reason).replace("_", " ")]
	heat_popup_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR if delta > 0.0 else UiTheme.WIN_COLOR)
	heat_popup_label.modulate.a = 1.0
	_popup_left = _POPUP_SECONDS
	if delta > 0.0:
		_pulse_left = Tuning.UI_HEAT_PULSE_SECONDS


func _on_level(old_level: int, new_level: int) -> void:
	var color := UiTheme.heat_color(new_level)
	var lname := UiTheme.level_name(new_level).to_upper()
	if new_level > old_level:
		match new_level:
			HR.HeatLevel.WATCHED:
				push_notification("You're being WATCHED. Cameras follow you.", color)
			HR.HeatLevel.SUSPECTED:
				show_banner(lname, color)
				push_notification("SUSPECTED: a guard is coming to check your ID.", color)
			HR.HeatLevel.WANTED:
				show_banner("WANTED!", color, 2.4)
				push_notification("WANTED: guards are chasing you. Run, hide, change!", color)
	else:
		push_notification("Cooling off: %s." % UiTheme.level_name(new_level), color)


func _on_id(data: Dictionary) -> void:
	var reason: StringName = StringName(str(data.get("reason", "")))
	var card: Dictionary = data.get("id", {})
	var id_name: String = str(card.get("name", ""))
	match reason:
		&"bought":
			push_notification("New ID: you're %s now." % id_name, UiTheme.GOLD_LIGHT)
		&"swapped":
			push_notification("Playing as %s." % id_name, UiTheme.CREAM)
		&"burned":
			push_notification("Your ID got burned.", UiTheme.LOSS_COLOR)
		&"rejoin":
			push_notification("Fresh cheap ID: %s. Memorize it!" % id_name, UiTheme.GOLD_LIGHT)
		&"auto_swap":
			push_notification("Switched to %s." % id_name, UiTheme.CREAM)


func _name_of(other: int) -> String:
	var players: Dictionary = _snap.get("players", {})
	var p: Dictionary = players.get(other, {})
	if p.is_empty() and host != null:
		p = UiTheme.player_snapshot(host, other)
	return str(p.get("name", "Player %d" % other))


# --- Rendering ----------------------------------------------------------------

func _render_heat() -> void:
	heat_bar.set_heat(_heat, _level)
	var color := UiTheme.heat_color(_level)
	heat_level_label.text = UiTheme.level_name(_level).to_upper()
	heat_level_label.add_theme_color_override(&"font_color", color)
	heat_value_label.text = str(int(floorf(_heat)))
	heat_value_label.add_theme_color_override(&"font_color", color)


func _render_casino(run: Dictionary) -> void:
	if run.is_empty():
		casino_label.text = "High Roller"
		rung_label.text = ""
		clock_label.text = ""
		_render_strikes(0)
		return
	var rung: int = int(run.get("rung", Tuning.TOP_RUNG))
	casino_label.text = str(run.get("casino_name", CasinoLadder.casino(rung).get("name", "")))
	rung_label.text = "Rung %d of %d" % [rung, Tuning.BOTTOM_RUNG]
	if bool(run.get("is_top", false)):
		clock_label.text = "SCORE %s   %s at the top" % [UiTheme.chips(int(run.get("score", 0))), UiTheme.clock(float(run.get("top_seconds", 0.0)))]
		clock_label.add_theme_color_override(&"font_color", UiTheme.GOLD_LIGHT)
	else:
		clock_label.text = "Time here %s" % UiTheme.clock(float(run.get("visit_seconds", 0.0)))
		clock_label.add_theme_color_override(&"font_color", UiTheme.CREAM)
	_render_strikes(int(run.get("strikes", 0)))


func _render_strikes(strikes: int) -> void:
	for i in strike_icons.size():
		var icon: Panel = strike_icons[i]
		var hit: bool = i < strikes
		icon.add_theme_stylebox_override(&"panel", UiTheme.flat_box(
			UiTheme.CHIP_RED if hit else Color(0, 0, 0, 0.35),
			Color("ffd0d0") if hit else Color(UiTheme.MUTED, 0.6), 3, 17, 0))
		var x_label: Label = icon.get_child(0)
		x_label.modulate.a = 1.0 if hit else 0.35


func _render_chips(me: Dictionary, run: Dictionary) -> void:
	pocket_label.text = UiTheme.chips(int(me.get("pocket", 0)))
	if run.is_empty():
		bank_label.text = ""
		bank_hint_label.text = ""
		bank_bar.visible = false
		return
	var rung: int = int(run.get("rung", Tuning.TOP_RUNG))
	if bool(run.get("is_top", false)):
		bank_title_label.text = "BANKED AT THE TOP (SCORE)"
		bank_label.text = UiTheme.chips(int(run.get("top_banked", 0)))
		bank_bar.visible = false
		bank_hint_label.text = "Every chip you bank here scores."
		bank_hint_label.add_theme_color_override(&"font_color", UiTheme.MUTED)
		return
	var bank: int = int(run.get("bank", 0))
	var buy_in: int = int(run.get("buy_in", 0))
	bank_title_label.text = "CREW BANK"
	bank_label.text = "%s / %s" % [UiTheme.chips(bank), UiTheme.chips(buy_in)]
	bank_bar.visible = buy_in > 0
	bank_bar.max_value = maxf(1.0, float(buy_in))
	bank_bar.value = minf(float(bank), float(buy_in))
	var above: String = str(CasinoLadder.casino(rung - 1).get("name", "the next casino"))
	if bool(run.get("can_climb", false)):
		bank_hint_label.text = "CLIMB READY! Crew to the exit."
		bank_hint_label.add_theme_color_override(&"font_color", UiTheme.WIN_COLOR)
	else:
		bank_hint_label.text = "Buy-in to %s" % above
		bank_hint_label.add_theme_color_override(&"font_color", UiTheme.MUTED)


func _render_id(me: Dictionary) -> void:
	var card: Dictionary = me.get("id", {})
	var hidden: bool = _status == HR.PlayerStatus.ID_CHECK
	for n: Control in [id_name_label, id_birthday_label, id_state_label, id_cap_label, id_cap_bar]:
		n.visible = not hidden and not card.is_empty()
	id_hidden_label.visible = hidden or card.is_empty()
	if hidden:
		id_hidden_label.text = "Your card is in the guard's hand..."
	elif card.is_empty():
		id_hidden_label.text = "NO ID! Find the forger."
	var grade: int = int(card.get("grade", HR.IdGrade.CHEAP))
	id_grade_label.text = "FAKE ID  -  %s" % IdGenerator.grade_name(grade).to_upper() if not card.is_empty() else "FAKE ID"
	id_name_label.text = str(card.get("name", ""))
	id_birthday_label.text = "Born  %s" % str(card.get("birthday", ""))
	id_state_label.text = "From  %s" % str(card.get("home_state", ""))
	var cap: int = int(card.get("cap", 0))
	var banked: int = int(card.get("banked_under", 0))
	id_cap_label.text = "Banked %s / %s cap" % [UiTheme.chips(banked), UiTheme.chips(cap)]
	id_cap_bar.max_value = maxf(1.0, float(cap))
	id_cap_bar.value = minf(float(banked), float(cap))
	var badge := ""
	if bool(card.get("burned", false)):
		badge = "BURNED"
	elif bool(card.get("flagged", false)):
		badge = "FLAGGED"
	id_badge.visible = badge != ""
	id_badge_label.text = badge


func _render_outfit(me: Dictionary) -> void:
	var outfit: Dictionary = me.get("outfit", {})
	var key := str(outfit)
	if key != _outfit_key:
		_outfit_key = key
		UiTheme.clear_children(outfit_holder)
		if not outfit.is_empty():
			var row := UiTheme.make_outfit_row(outfit, Vector2(30, 30))
			outfit_holder.add_child(row)
	var text := ""
	var color := UiTheme.MUTED
	if bool(me.get("matches_poster", false)):
		text = "MATCHES A WANTED POSTER"
		color = UiTheme.heat_color(HR.HeatLevel.WANTED)
	elif bool(me.get("recognized", false)):
		text = "Security knows this look"
		color = UiTheme.heat_color(HR.HeatLevel.SUSPECTED)
	elif bool(me.get("staff_uniform", false)):
		text = "Staff uniform"
		color = UiTheme.GOLD_LIGHT
	outfit_badge_label.text = text
	outfit_badge_label.add_theme_color_override(&"font_color", color)
	outfit_badge_label.visible = text != ""


func _render_status(me: Dictionary) -> void:
	var text := ""
	var color := UiTheme.LOSS_COLOR
	var secs: int = ceili(float(me.get("status_seconds", 0.0)))
	match _status:
		HR.PlayerStatus.CARRIED:
			text = "MASH SPACE TO STRUGGLE!"
		HR.PlayerStatus.DETAINED:
			text = "DETAINED IN THE BACK ROOM  -  back in %d s" % secs
		HR.PlayerStatus.ON_CURB:
			text = "ON THE CURB  -  back inside in %d s" % secs
		HR.PlayerStatus.ID_CHECK:
			text = "ID CHECK!"
			color = UiTheme.heat_color(HR.HeatLevel.SUSPECTED)
	if text == "" and bool(_snap.get("fire_alarm", false)):
		text = "FIRE ALARM  -  tables closed %d s" % ceili(float(_snap.get("fire_alarm_seconds", 0.0)))
		color = UiTheme.heat_color(HR.HeatLevel.SUSPECTED)
	status_label.text = text
	status_label.add_theme_color_override(&"font_color", color)
	status_label.visible = text != ""


# --- Animation ----------------------------------------------------------------

func _animate_heat(delta: float) -> void:
	var s := 1.0
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
		var k: float = 1.0 - _pulse_left / Tuning.UI_HEAT_PULSE_SECONDS
		s = 1.0 + (Tuning.UI_HEAT_PULSE_SCALE - 1.0) * sin(PI * k)
	heat_panel.pivot_offset = heat_panel.size * 0.5
	heat_panel.scale = Vector2(s, s)
	var offset := Vector2.ZERO
	if _level == HR.HeatLevel.WANTED:
		var px: float = Tuning.UI_HEAT_SHAKE_PIXELS
		offset = Vector2(sin(_time * 53.0) * px, cos(_time * 41.0) * px * 0.6)
	heat_panel.position = offset


func _animate_banner() -> void:
	if _banner_left <= 0.0:
		banner_label.visible = false
		return
	var shown: float = _banner_total - _banner_left
	var s := 1.0
	if shown < _BANNER_IN_SECONDS:
		var k: float = shown / _BANNER_IN_SECONDS
		s = lerpf(0.4, 1.0, ease(k, 0.4)) + 0.12 * sin(PI * k)
	banner_label.pivot_offset = banner_label.size * 0.5
	banner_label.scale = Vector2(s, s)
	banner_label.modulate.a = clampf(_banner_left / _BANNER_OUT_SECONDS, 0.0, 1.0)


func _age_feed(delta: float) -> void:
	for entry: Node in feed.get_children():
		var age: float = float(entry.get_meta(&"age", 0.0)) + delta
		entry.set_meta(&"age", age)
		var left: float = Tuning.UI_NOTIFY_SECONDS - age
		var item: CanvasItem = entry
		item.modulate.a = clampf(left / Tuning.UI_NOTIFY_FADE_SECONDS, 0.0, 1.0)
		if left <= 0.0:
			feed.remove_child(entry)
			entry.queue_free()


# --- Layout -----------------------------------------------------------------

func _build() -> void:
	# Top center: the Heat meter.
	_heat_holder = Control.new()
	_heat_holder.anchor_left = 0.5
	_heat_holder.anchor_right = 0.5
	_heat_holder.offset_left = -300
	_heat_holder.offset_right = 300
	_heat_holder.offset_top = 14
	_heat_holder.offset_bottom = 130
	add_child(_heat_holder)
	heat_panel = UiTheme.make_panel(&"HudPanel")
	heat_panel.size = Vector2(600, 0)
	_heat_holder.add_child(heat_panel)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override(&"separation", 4)
	heat_panel.add_child(hv)
	var top := HBoxContainer.new()
	hv.add_child(top)
	var heat_title := UiTheme.make_label("HEAT", &"SmallLabel")
	heat_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(heat_title)
	heat_level_label = UiTheme.make_label("UNNOTICED", &"BigLabel", 34)
	heat_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heat_level_label)
	heat_popup_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY)
	heat_popup_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(heat_popup_label)
	heat_value_label = UiTheme.make_label("0", &"BigLabel", 34)
	heat_value_label.custom_minimum_size = Vector2(64, 0)
	heat_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(heat_value_label)
	heat_bar = HeatBar.new()
	hv.add_child(heat_bar)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	hv.add_child(spacer)

	# Top left: casino, rung, clock or score, strikes.
	var casino := UiTheme.make_panel(&"HudPanel")
	casino.position = Vector2(16, 14)
	casino.custom_minimum_size = Vector2(340, 0)
	add_child(casino)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override(&"separation", 2)
	casino.add_child(cv)
	casino_label = UiTheme.make_label("", &"HeaderLabel", 32)
	cv.add_child(casino_label)
	rung_label = UiTheme.make_label("", &"SmallLabel", 19)
	cv.add_child(rung_label)
	clock_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY)
	cv.add_child(clock_label)
	var strikes_row := HBoxContainer.new()
	strikes_row.add_theme_constant_override(&"separation", 8)
	cv.add_child(strikes_row)
	var st := UiTheme.make_label("STRIKES", &"SmallLabel")
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strikes_row.add_child(st)
	for i in Tuning.STRIKES_TO_THROW_OUT:
		var icon := Panel.new()
		icon.custom_minimum_size = Vector2(34, 34)
		var x := UiTheme.make_label("X", &"", 20)
		x.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		x.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		x.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_child(x)
		strikes_row.add_child(icon)
		strike_icons.append(icon)

	# Top right: pocket and crew bank.
	var money := UiTheme.make_panel(&"HudPanel")
	money.anchor_left = 1.0
	money.anchor_right = 1.0
	money.offset_left = -376
	money.offset_right = -16
	money.offset_top = 14
	money.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(money)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override(&"separation", 2)
	money.add_child(mv)
	var pocket_row := HBoxContainer.new()
	mv.add_child(pocket_row)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(30, 30)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip_box := UiTheme.flat_box(UiTheme.CHIP_RED, UiTheme.CREAM, 4, 15, 0)
	chip.add_theme_stylebox_override(&"panel", chip_box)
	pocket_row.add_child(chip)
	var pt := UiTheme.make_label("POCKET", &"SmallLabel")
	pt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pocket_row.add_child(pt)
	pocket_label = UiTheme.make_label("0", &"BigLabel", 36)
	pocket_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pocket_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pocket_row.add_child(pocket_label)
	bank_title_label = UiTheme.make_label("CREW BANK", &"SmallLabel")
	mv.add_child(bank_title_label)
	bank_label = UiTheme.make_label("", &"", UiTheme.FONT_LARGE, UiTheme.GOLD_LIGHT)
	mv.add_child(bank_label)
	bank_bar = ProgressBar.new()
	bank_bar.show_percentage = false
	bank_bar.custom_minimum_size = Vector2(0, 16)
	mv.add_child(bank_bar)
	bank_hint_label = UiTheme.make_label("", &"SmallLabel")
	mv.add_child(bank_hint_label)

	# Bottom left: outfit and fake ID card.
	var bottom_left := VBoxContainer.new()
	bottom_left.anchor_top = 1.0
	bottom_left.anchor_bottom = 1.0
	bottom_left.offset_left = 16
	bottom_left.offset_right = 376
	bottom_left.offset_top = -16
	bottom_left.offset_bottom = -16
	bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom_left)
	var outfit_panel := UiTheme.make_panel(&"HudPanel")
	bottom_left.add_child(outfit_panel)
	var ov := VBoxContainer.new()
	ov.add_theme_constant_override(&"separation", 4)
	outfit_panel.add_child(ov)
	var orow := HBoxContainer.new()
	ov.add_child(orow)
	var ot := UiTheme.make_label("LOOK", &"SmallLabel")
	ot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	orow.add_child(ot)
	outfit_holder = HBoxContainer.new()
	orow.add_child(outfit_holder)
	outfit_badge_label = UiTheme.make_label("", &"", UiTheme.FONT_SMALL + 1)
	ov.add_child(outfit_badge_label)

	id_panel = UiTheme.make_panel(&"CardPanel")
	bottom_left.add_child(id_panel)
	var iv := VBoxContainer.new()
	iv.add_theme_constant_override(&"separation", 0)
	id_panel.add_child(iv)
	var irow := HBoxContainer.new()
	iv.add_child(irow)
	id_grade_label = UiTheme.make_label("FAKE ID", &"CardSmallLabel")
	id_grade_label.add_theme_color_override(&"font_color", UiTheme.GOLD_DARK)
	id_grade_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	irow.add_child(id_grade_label)
	id_badge = UiTheme.make_panel(&"BadgePanel")
	id_badge_label = UiTheme.make_label("FLAGGED", &"", UiTheme.FONT_SMALL)
	id_badge.add_child(id_badge_label)
	irow.add_child(id_badge)
	id_name_label = UiTheme.make_label("", &"CardLabel", 28)
	iv.add_child(id_name_label)
	id_birthday_label = UiTheme.make_label("", &"CardSmallLabel", 18)
	iv.add_child(id_birthday_label)
	id_state_label = UiTheme.make_label("", &"CardSmallLabel", 18)
	iv.add_child(id_state_label)
	id_cap_label = UiTheme.make_label("", &"CardSmallLabel", 15)
	iv.add_child(id_cap_label)
	id_cap_bar = ProgressBar.new()
	id_cap_bar.show_percentage = false
	id_cap_bar.custom_minimum_size = Vector2(0, 8)
	iv.add_child(id_cap_bar)
	id_hidden_label = UiTheme.make_label("", &"CardLabel", 20)
	id_hidden_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	iv.add_child(id_hidden_label)

	# Bottom center: interact prompt.
	prompt_panel = UiTheme.make_panel(&"HudPanel")
	prompt_panel.anchor_left = 0.5
	prompt_panel.anchor_right = 0.5
	prompt_panel.anchor_top = 1.0
	prompt_panel.anchor_bottom = 1.0
	prompt_panel.offset_top = -96
	prompt_panel.offset_bottom = -40
	prompt_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(prompt_panel)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override(&"separation", 12)
	prompt_panel.add_child(prow)
	var keycap := UiTheme.make_panel(&"CardPanel")
	keycap.custom_minimum_size = Vector2(42, 0)
	prompt_key_label = UiTheme.make_label("E", &"CardLabel", 24)
	prompt_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keycap.add_child(prompt_key_label)
	prow.add_child(keycap)
	prompt_label = UiTheme.make_label("", &"BigLabel", 26)
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(prompt_label)

	# Status line (carried / detained / curb) under the screen center.
	status_label = UiTheme.make_label("", &"HeaderLabel", 44)
	status_label.anchor_left = 0.0
	status_label.anchor_right = 1.0
	status_label.anchor_top = 0.66
	status_label.anchor_bottom = 0.66
	status_label.offset_bottom = 60
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_constant_override(&"outline_size", 10)
	add_child(status_label)

	# Right: notification feed.
	feed = VBoxContainer.new()
	feed.anchor_left = 1.0
	feed.anchor_right = 1.0
	feed.offset_left = -392
	feed.offset_right = -16
	feed.offset_top = 236
	feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed.add_theme_constant_override(&"separation", 6)
	add_child(feed)

	# Center banner.
	banner_label = UiTheme.make_label("", &"TitleLabel", 92)
	banner_label.anchor_left = 0.0
	banner_label.anchor_right = 1.0
	banner_label.anchor_top = 0.21
	banner_label.anchor_bottom = 0.21
	banner_label.offset_bottom = 120
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner_label.add_theme_constant_override(&"outline_size", 18)
	banner_label.visible = false
	add_child(banner_label)
