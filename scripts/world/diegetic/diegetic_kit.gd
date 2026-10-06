class_name DiegeticKit
extends RefCounted
## Shared look and helpers for the diegetic machine kit (keys, consoles,
## screens, cards, dice, chips): the key and screen palette, money text,
## flat Label3D text sized in metres, and short screen texts for the sim's
## refusal reasons. Visuals come from Primitives / MeshFactory / ArtKit.

# --- Palette (docs/ART_DIRECTION.md: toy-like, saturated, neon club) ---------
const KEY_CREAM := Color("f3d9e4")
const KEY_ORANGE := Color("ffa62b")
const KEY_GREEN := Color("98e83a")
const KEY_RED := Color("ff3448")
const KEY_YELLOW := Color("ffd23f")
const KEY_BLUE := Color("47a6ff")
const KEY_PURPLE := Color("a259ff")
const LEGEND_DARK := Color("2a1f3d")
const LEGEND_LIGHT := Color("fff8ec")
const CONSOLE_BODY := Color("241a35")
const CONSOLE_DECK := Color("150f22")
const BEZEL := Color("120c1c")
const CHROME := Color("c8cde0")
const NEON_TRIM := Color("ff3fd2")
const TEXT_WHITE := Color("fff8ec")
const TEXT_MONEY := Color("ffd23f")
const TEXT_POCKET := Color("8dff6a")
const TEXT_INFO := Color("3ef0ff")
const TEXT_WIN := Color("7dff5a")
const TEXT_LOSE := Color("ff4d5e")
const TEXT_WARN := Color("ffb020")
## Lilita One cap height as a share of the font size.
const CAP_RATIO := 0.7
## Flat machine text stops drawing beyond this distance (m).
const TEXT_FADE_DISTANCE := 18.0
## Font pixels per glyph for flat machine text (crisp up close).
const TEXT_FONT_SIZE := 64


## "$1,250" (negative amounts get a leading minus).
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-$" if amount < 0 else "$") + out


## "$950", "$12.5K", "$3.2M", "$1.1B": short money for small screens.
static func money_short(amount: int) -> String:
	var a := absi(amount)
	var sign_text := "-" if amount < 0 else ""
	if a < 10000:
		return sign_text + money(a)
	var units: Array = [[1000000000000, "T"], [1000000000, "B"], [1000000, "M"], [1000, "K"]]
	for u: Array in units:
		var base: int = u[0]
		if a >= base:
			var v := float(a) / float(base)
			var text := ("%.0f" % v) if v >= 100.0 else ("%.1f" % v).trim_suffix(".0")
			return "%s$%s%s" % [sign_text, text, u[1]]
	return sign_text + money(a)


## A flat (not billboarded) Label3D in the display font whose capital
## letters are about `height` metres tall, reading along +X and facing +Z.
## `outline_px` > 0 adds a dark outline that many font pixels wide.
static func text_label(text: String, height: float, color: Color = TEXT_WHITE, outline_px: int = 0,
		outline_color: Color = ArtKit.OUTLINE_COLOR) -> Label3D:
	var l := Label3D.new()
	l.font = ArtKit.display_font()
	l.font_size = TEXT_FONT_SIZE
	l.text = text
	l.pixel_size = pixel_size_for(height)
	l.modulate = color
	l.outline_size = outline_px
	l.outline_modulate = outline_color
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = false
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	l.visibility_range_end = TEXT_FADE_DISTANCE
	return l


static func pixel_size_for(height: float, font_size: int = TEXT_FONT_SIZE) -> float:
	return maxf(height, 0.0005) / (float(font_size) * CAP_RATIO)


## Width in metres `text` takes in `label`'s font at `pixel_size`.
static func text_width(label: Label3D, text: String, pixel_size: float) -> float:
	var font: Font = label.font if label.font != null else ThemeDB.fallback_font
	var w := 0.0
	for line: String in text.split("\n"):
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x)
	return w * pixel_size


## Sets `text` with capitals `height` tall, shrunk to fit `max_width` metres.
static func fit_label(label: Label3D, text: String, height: float, max_width: float) -> void:
	label.text = text
	var px := pixel_size_for(height, label.font_size)
	var w := text_width(label, text, px)
	if max_width > 0.0 and w > max_width:
		px *= max_width / w
	label.pixel_size = px


## Readable legend color for a key cap of `color`: dark ink on light caps,
## white (with an outline) on saturated or dark ones.
static func legend_color_for(color: Color) -> Color:
	return LEGEND_DARK if color.get_luminance() > 0.62 and color.s < 0.55 else LEGEND_LIGHT


## Glossy toon material for key caps and console parts (cached by ArtKit).
static func key_material(color: Color, emission: float = 0.0) -> Material:
	return ArtKit.toon_material(color, emission, false, true, 0.5)


## The cap color of a disabled key: darker and greyer.
static func disabled_color(color: Color) -> Color:
	var c := color.lerp(Color(0.36, 0.34, 0.42), 0.72)
	return c.darkened(0.2)


## Short screen text for a FloorSim / SimHost refusal reason.
static func reason_text(reason: StringName) -> String:
	match reason:
		&"below_min":
			return "Bet too low"
		&"above_max":
			return "Over the max"
		&"not_enough", &"bad_amount":
			return "Not enough chips"
		&"table_closed":
			return "CLOSED"
		&"not_seated":
			return "Step up to play"
		&"busy":
			return "Not now"
		&"in_round":
			return "Finish your round"
		&"no_round":
			return "No round on"
		&"staff_uniform":
			return "Staff can't play"
		&"finished", &"no_sim":
			return "Not open"
		&"too_far":
			return "Too far away"
		&"wrong_game":
			return "Wrong game"
		&"unknown_table":
			return "Out of order"
		&"not_your_player", &"bad_args", &"unknown_request", &"not_connected", &"host_only":
			return "Try again"
	var s := String(reason).replace("_", " ")
	return s.capitalize() if s != "" else "Refused"
