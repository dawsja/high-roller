class_name UiTheme
extends RefCounted
## The casino look shared by every HUD element and panel: dark felt panels with
## gold trim, Fredoka body text and Lilita One display text (assets/fonts),
## colored chip buttons and the Heat level colors. Also small builders and
## text helpers the panels share.
##
## Type variations (set `theme_type_variation`):
## - Labels: TitleLabel, HeaderLabel, BigLabel, SmallLabel, CardLabel, CardSmallLabel
## - Panels (PanelContainer): HudPanel, CardPanel, BadgePanel, InsetPanel
## - Buttons: RedButton, BlackButton, GreenButton, BlueButton (default Button is gold)

const FELT := Color("0f3d2e")
const FELT_DARK := Color("082219")
const FELT_LIGHT := Color("1b6347")
const GOLD := Color("e8b923")
const GOLD_LIGHT := Color("ffe08a")
const GOLD_DARK := Color("8f6a12")
const CREAM := Color("fff6dc")
const INK := Color("1d1a14")
const MUTED := Color("b7c9bc")
const CHIP_RED := Color("c8283c")
const CHIP_BLACK := Color("26262e")
const CHIP_GREEN := Color("239a4b")
const CHIP_BLUE := Color("2463c4")
const WIN_COLOR := Color("6cf08a")
const LOSS_COLOR := Color("ff6b6b")
const DIM := Color(0.0, 0.0, 0.0, 0.5)

## HR.HeatLevel -> color: Unnoticed green, Watched yellow, Suspected orange, Wanted red.
const HEAT_COLORS := {
	HR.HeatLevel.UNNOTICED: Color("4cd964"),
	HR.HeatLevel.WATCHED: Color("ffd60a"),
	HR.HeatLevel.SUSPECTED: Color("ff9500"),
	HR.HeatLevel.WANTED: Color("ff3b30"),
}

const FONT_SMALL := 17
const FONT_BODY := 22
const FONT_BUTTON := 24
const FONT_LARGE := 30
const FONT_HEADER := 38
const FONT_HUGE := 56
const FONT_TITLE := 104

## Heat reasons that tick every frame; the UI filters them out of popups.
const PASSIVE_HEAT_REASONS: Array[StringName] = [
	HeatRules.CAMPING, HeatRules.SLOT_BLEND, HeatRules.OFF_TABLE,
	HeatRules.FLOOR_DECAY, HeatRules.RUN_IN_VIEW, HeatRules.CAMERA,
]

const STATUS_NAMES := {
	HR.PlayerStatus.FREE: "Free",
	HR.PlayerStatus.SEATED: "Seated",
	HR.PlayerStatus.ID_CHECK: "ID check",
	HR.PlayerStatus.CARRIED: "Carried",
	HR.PlayerStatus.DETAINED: "Detained",
	HR.PlayerStatus.ON_CURB: "On the curb",
}

const _REASON_TEXT := {
	&"no_sim": "The casino isn't open yet.",
	&"finished": "This visit is over.",
	&"unknown_player": "Who are you again?",
	&"unknown_table": "That table doesn't exist.",
	&"busy": "You can't do that right now.",
	&"wrong_zone": "You can't do that here.",
	&"bad_amount": "Pick an amount first.",
	&"not_enough": "Not enough chips.",
	&"below_min": "Below the table minimum.",
	&"above_max": "Above the table maximum.",
	&"table_closed": "The table is closed.",
	&"not_seated": "Sit down first.",
	&"wrong_game": "Wrong game for that.",
	&"in_round": "Finish the round first.",
	&"no_round": "No round in progress.",
	&"staff_uniform": "Staff can't sit at the tables.",
	&"no_bets": "No bets placed.",
	&"bad_index": "That option is gone.",
	&"bad_outfit": "That outfit doesn't fit together.",
	&"not_owned": "You don't own that piece.",
	&"same_outfit": "You're already wearing that.",
	&"bad_piece": "That piece isn't for sale.",
	&"already_wearing": "You're already wearing that piece.",
	&"cooldown": "Not yet. Wait a bit.",
	&"forger_not_here": "The forger isn't here right now.",
	&"bad_grade": "The forger doesn't make that.",
	&"no_question": "Nobody asked you anything.",
	&"not_available": "Not available.",
	&"not_carried": "Nobody is carrying you.",
	&"same_player": "That's you.",
	&"bad_kind": "That doesn't do anything.",
	&"used": "Already used this visit.",
	&"cant_climb": "The crew bank can't cover the buy-in yet.",
	&"not_at_exit": "The whole crew must be at the exit.",
	&"unknown_poster": "That poster is gone.",
	&"no_slot": "Nothing left to draw over.",
	&"bad_id": "Your ID is no good here.",
	&"correct": "Correct.",
	&"wrong": "Wrong answer!",
	&"timeout": "Too slow!",
	&"no_id": "You have no ID on you!",
	&"burned": "That ID is burned: security knows it's fake.",
	&"flagged": "That name is flagged: it won more than its cap.",
	&"spotted": "The guard spotted your cheap fake on sight!",
	&"pending": "Waiting for the host...",
	&"host_only": "Only the host can do that.",
	&"not_your_player": "That's not you.",
	&"bad_args": "The host didn't understand that.",
	&"unknown_request": "The host didn't understand that.",
	&"not_connected": "Not connected to the host.",
	&"too_far": "You're too far away.",
}

static var _theme: Theme = null
static var _bold: FontVariation = null
static var _heavy: FontVariation = null


## The shared Theme (built once). Assign it to a panel's root `theme`.
static func make_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = bold_font()
	t.default_font_size = FONT_BODY

	# Labels: cream text with a dark outline so they read over the 3D floor.
	t.set_color(&"font_color", &"Label", CREAM)
	t.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0.85))
	t.set_constant(&"outline_size", &"Label", 5)
	t.set_color(&"font_shadow_color", &"Label", Color(0, 0, 0, 0.0))
	_label_variation(t, &"TitleLabel", FONT_TITLE, GOLD, 14, heavy_font())
	_label_variation(t, &"HeaderLabel", FONT_HEADER, GOLD_LIGHT, 7, heavy_font())
	_label_variation(t, &"BigLabel", FONT_LARGE, CREAM, 6, heavy_font())
	_label_variation(t, &"SmallLabel", FONT_SMALL, MUTED, 4, null)
	_label_variation(t, &"CardLabel", FONT_LARGE, INK, 0, heavy_font())
	_label_variation(t, &"CardSmallLabel", FONT_SMALL, Color("4a4232"), 0, null)

	# Panels.
	var felt := flat_box(Color(FELT, 0.96), GOLD, 3, 16, 20)
	felt.shadow_color = Color(0, 0, 0, 0.55)
	felt.shadow_size = 10
	felt.shadow_offset = Vector2(0, 4)
	t.set_stylebox(&"panel", &"PanelContainer", felt)
	t.set_stylebox(&"panel", &"Panel", felt)
	_panel_variation(t, &"HudPanel", flat_box(Color(FELT_DARK, 0.82), GOLD_DARK, 2, 12, 12))
	_panel_variation(t, &"CardPanel", flat_box(CREAM, GOLD, 3, 10, 12))
	_panel_variation(t, &"BadgePanel", flat_box(CHIP_RED, Color("ffd0d0"), 2, 8, 6))
	_panel_variation(t, &"InsetPanel", flat_box(Color(FELT_DARK, 0.9), Color(GOLD_DARK, 0.6), 1, 10, 10))

	# Buttons: chunky chips with a darker lip at the bottom.
	_button_style(t, &"Button", GOLD, INK)
	_button_variation(t, &"RedButton", CHIP_RED, CREAM)
	_button_variation(t, &"BlackButton", CHIP_BLACK, CREAM)
	_button_variation(t, &"GreenButton", CHIP_GREEN, CREAM)
	_button_variation(t, &"BlueButton", CHIP_BLUE, CREAM)
	t.set_font_size(&"font_size", &"Button", FONT_BUTTON)
	_button_style(t, &"OptionButton", GOLD, INK)

	# Check buttons (the throw toggle) stay text-only.
	for type: StringName in [&"CheckButton", &"CheckBox"]:
		t.set_color(&"font_color", type, CREAM)
		t.set_color(&"font_hover_color", type, GOLD_LIGHT)
		t.set_color(&"font_pressed_color", type, GOLD_LIGHT)
		t.set_color(&"font_hover_pressed_color", type, GOLD_LIGHT)
		t.set_color(&"font_focus_color", type, CREAM)
		t.set_font_size(&"font_size", type, FONT_BODY)
		var empty := StyleBoxEmpty.new()
		for s: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus", &"disabled"]:
			t.set_stylebox(s, type, empty)

	# Bars.
	t.set_stylebox(&"background", &"ProgressBar", flat_box(Color(FELT_DARK, 0.95), GOLD_DARK, 2, 8, 0))
	t.set_stylebox(&"fill", &"ProgressBar", flat_box(GOLD, GOLD_LIGHT, 0, 8, 0))
	t.set_color(&"font_color", &"ProgressBar", CREAM)
	t.set_font_size(&"font_size", &"ProgressBar", FONT_SMALL)

	# Slider.
	var track := flat_box(FELT_DARK, GOLD_DARK, 2, 6, 0)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox(&"slider", &"HSlider", track)
	var area := flat_box(GOLD, GOLD, 0, 6, 0)
	area.content_margin_top = 6
	area.content_margin_bottom = 6
	t.set_stylebox(&"grabber_area", &"HSlider", area)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", area)

	# Text entry (spin boxes).
	var edit := flat_box(FELT_DARK, GOLD_DARK, 2, 8, 8)
	t.set_stylebox(&"normal", &"LineEdit", edit)
	t.set_stylebox(&"focus", &"LineEdit", flat_box(FELT_DARK, GOLD, 2, 8, 8))
	t.set_stylebox(&"read_only", &"LineEdit", edit)
	t.set_color(&"font_color", &"LineEdit", CREAM)
	t.set_color(&"caret_color", &"LineEdit", GOLD)
	t.set_font_size(&"font_size", &"LineEdit", FONT_BUTTON)

	# Popups (OptionButton lists).
	t.set_stylebox(&"panel", &"PopupMenu", flat_box(FELT, GOLD, 2, 8, 8))
	t.set_color(&"font_color", &"PopupMenu", CREAM)
	t.set_color(&"font_hover_color", &"PopupMenu", GOLD_LIGHT)

	var sep := StyleBoxLine.new()
	sep.color = Color(GOLD, 0.55)
	sep.thickness = 2
	t.set_stylebox(&"separator", &"HSeparator", sep)
	t.set_constant(&"separation", &"HSeparator", 10)
	t.set_constant(&"separation", &"VBoxContainer", 8)
	t.set_constant(&"separation", &"HBoxContainer", 10)
	_theme = t
	return t


## Body text: Fredoka SemiBold. Every UI text uses it unless a variation picks heavy_font().
static func bold_font() -> FontVariation:
	if _bold == null:
		_bold = ArtKit.body_font(600)
	return _bold


## Display weight for titles, headers, big numbers and buttons-as-signs: Lilita One.
static func heavy_font() -> FontVariation:
	if _heavy == null:
		_heavy = FontVariation.new()
		_heavy.base_font = ArtKit.display_font()
	return _heavy


static func flat_box(bg: Color, border: Color, border_width: int, radius: int, margin: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(margin)
	box.anti_aliasing = true
	return box


static func heat_color(level: int) -> Color:
	return HEAT_COLORS.get(level, HEAT_COLORS[HR.HeatLevel.UNNOTICED]) as Color


static func level_name(level: int) -> String:
	return HeatMeter.level_name(level)


static func status_name(status: int) -> String:
	return str(STATUS_NAMES.get(status, "?"))


static func is_passive_heat(reason: StringName) -> bool:
	return PASSIVE_HEAT_REASONS.has(reason)


## Player-facing text for a FloorSim / SimHost failure reason.
static func reason_text(reason: StringName) -> String:
	if _REASON_TEXT.has(reason):
		return str(_REASON_TEXT[reason])
	return String(reason).capitalize()


## 12345 -> "12,345" (negative numbers keep their sign).
static func chips(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if amount < 0 else "") + out


## 125.4 -> "02:05".
static func clock(seconds: float) -> String:
	var s: int = maxi(0, int(seconds))
	return "%02d:%02d" % [floori(s / 60.0), s % 60]


## "+5.2" / "-10".
static func signed(value: float) -> String:
	var text := ("%.1f" % absf(value)).trim_suffix(".0")
	return ("+" if value >= 0.0 else "-") + text


## High-low card value (2-14) -> "2".."10", "J", "Q", "K", "A".
static func high_low_card(value: int) -> String:
	match value:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
	return str(value)


## Blackjack card value (2-11; 10 covers faces, 11 is an ace).
static func blackjack_card(value: int) -> String:
	return "A" if value == 11 else str(value)


## Events that end whatever a modal panel was doing: this player got grabbed,
## or the crew left the floor (thrown out, climbed, curb).
static func ends_panel(kind: StringName, data: Dictionary, pid: int) -> bool:
	if kind == &"caught":
		return int(data.get("pid", -1)) == pid
	return kind == &"thrown_out" or kind == &"climbed" or kind == &"curb"


## The player's entry of a host snapshot ({} without one).
static func player_snapshot(host: SimHost, pid: int) -> Dictionary:
	if host == null:
		return {}
	var snap: Dictionary = host.snapshot()
	var players: Dictionary = snap.get("players", {})
	return players.get(pid, {})


static func make_label(text: String, variation: StringName = &"", font_size: int = 0, color: Variant = null) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if font_size > 0:
		l.add_theme_font_size_override(&"font_size", font_size)
	if color is Color:
		l.add_theme_color_override(&"font_color", color as Color)
	return l


static func make_button(text: String, variation: StringName = &"", min_size: Vector2 = Vector2.ZERO) -> Button:
	var b := Button.new()
	b.text = text
	if variation != &"":
		b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	return b


static func make_panel(variation: StringName = &"") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != &"":
		p.theme_type_variation = variation
	return p


## A filled rounded swatch of one outfit piece color; an empty slot (NONE) is a
## dashed-looking hollow box.
static func make_swatch(color: Color, swatch_size: Vector2 = Vector2(34, 34)) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = swatch_size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if color.a <= 0.01:
		p.add_theme_stylebox_override(&"panel", flat_box(Color(0, 0, 0, 0.25), Color(MUTED, 0.6), 2, 6, 0))
	else:
		p.add_theme_stylebox_override(&"panel", flat_box(color, Color(0, 0, 0, 0.7), 2, 6, 0))
	return p


## One swatch per outfit slot (hat, glasses, top, bottom, accessory) from an
## Outfit.to_dict(), each with a tooltip naming the piece.
static func make_outfit_row(outfit: Dictionary, swatch_size: Vector2 = Vector2(34, 34)) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := Outfit.from_dict(outfit)
	for slot: int in OutfitCatalog.all_slots():
		var piece: StringName = look.get_piece(slot)
		var sw := make_swatch(OutfitCatalog.piece_color(piece), swatch_size)
		sw.tooltip_text = "%s: %s" % [OutfitCatalog.slot_name(slot), OutfitCatalog.piece_name(piece)]
		row.add_child(sw)
	return row


## A dimmed full-screen backdrop plus a centered felt panel inside `root`.
## Returns the panel's VBoxContainer to fill.
static func build_modal(root: Control, min_width: float, dim: float = 0.5) -> VBoxContainer:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := make_panel()
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 12)
	panel.add_child(body)
	return body


## A header row: big gold title on the left, an optional close button on the right.
static func make_header(title: String, close_button: Button = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := make_label(title, &"HeaderLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if close_button != null:
		row.add_child(close_button)
	return row


## Sets mouse_filter IGNORE on `node` and every Control under it (HUD layers).
static func ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		ignore_mouse(child)


static func clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func _label_variation(t: Theme, name: StringName, font_size: int, color: Color, outline: int, font: Font) -> void:
	t.set_type_variation(name, &"Label")
	t.set_font_size(&"font_size", name, font_size)
	t.set_color(&"font_color", name, color)
	t.set_constant(&"outline_size", name, outline)
	t.set_color(&"font_outline_color", name, Color(0, 0, 0, 0.9))
	if font != null:
		t.set_font(&"font", name, font)


static func _panel_variation(t: Theme, name: StringName, box: StyleBox) -> void:
	t.set_type_variation(name, &"PanelContainer")
	t.set_stylebox(&"panel", name, box)


static func _button_variation(t: Theme, name: StringName, color: Color, text: Color) -> void:
	t.set_type_variation(name, &"Button")
	_button_style(t, name, color, text)


static func _button_style(t: Theme, type: StringName, color: Color, text: Color) -> void:
	var lip := color.darkened(0.45)
	t.set_stylebox(&"normal", type, chip_box(color, lip))
	t.set_stylebox(&"hover", type, chip_box(color.lightened(0.18), lip))
	t.set_stylebox(&"pressed", type, chip_box(color.darkened(0.2), lip, true))
	t.set_stylebox(&"hover_pressed", type, chip_box(color.darkened(0.1), lip, true))
	t.set_stylebox(&"disabled", type, chip_box(Color(0.32, 0.34, 0.33, 0.85), Color(0.2, 0.2, 0.2, 0.85)))
	var focus := flat_box(Color(0, 0, 0, 0), CREAM, 3, 12, 0)
	focus.expand_margin_left = 3
	focus.expand_margin_right = 3
	focus.expand_margin_top = 3
	focus.expand_margin_bottom = 3
	t.set_stylebox(&"focus", type, focus)
	t.set_color(&"font_color", type, text)
	t.set_color(&"font_hover_color", type, text)
	t.set_color(&"font_pressed_color", type, text)
	t.set_color(&"font_hover_pressed_color", type, text)
	t.set_color(&"font_focus_color", type, text)
	t.set_color(&"font_disabled_color", type, Color(0.72, 0.72, 0.72))
	t.set_color(&"font_outline_color", type, Color(0, 0, 0, 0.6))
	t.set_constant(&"outline_size", type, 3 if text == CREAM else 0)


## A chunky chip-button box: `color` face with a darker `lip` underneath.
static func chip_box(color: Color, lip: Color, pressed: bool = false) -> StyleBoxFlat:
	var box := flat_box(color, lip, 0, 12, 0)
	box.border_width_bottom = 2 if pressed else 6
	box.border_width_top = 4 if pressed else 0
	box.border_color = lip
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box
