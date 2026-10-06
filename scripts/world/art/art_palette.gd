class_name ArtPalette
extends RefCounted
## Night-club colors for one casino (docs/ART_DIRECTION.md). Each casino's
## Tuning.CASINOS colors are pushed toward deep saturated walls and hot neon
## accents; a few casinos get hand-tuned touches (the Apex is a bright sky
## casino with white and gold walls and a starry blue carpet).
##
## for_casino(casino) returns a Dictionary of named Colors:
##   wall, wall_alt, wall_dark, wall_line, ceiling, floor_a (carpet base),
##   floor_b, floor_c, floor_d (carpet motifs), neon_1..neon_4, felt,
##   felt_border, wood, wood_dark, metal, gold, red, text, outline, ambient,
##   fog, sky
## plus floats ambient_energy, wall_glow (neon piping on wall lines) and
## wall_tile (metres per wall motif), ints carpet_pattern and wall_pattern
## (ArtPalette.CARPET_* / WALL_*) and day (bool: open sky, brighter).

const CLUB_WALL := Color("3b1d5e")
const CLUB_WALL_DEEP := Color("2a1640")
const CLUB_CEILING := Color("1c1033")
const NEON_MAGENTA := Color("ff3fd2")
const NEON_CYAN := Color("3ef0ff")
const NEON_LIME := Color("b6ff3b")
const NEON_SUNFLOWER := Color("ffd23f")
const NEON_ORANGE := Color("ff8a3d")
const NEONS: Array[Color] = [NEON_MAGENTA, NEON_CYAN, NEON_LIME, NEON_SUNFLOWER, NEON_ORANGE]
const FELT_GREEN := Color("16a05a")
const CASINO_RED := Color("e0283c")
const GOLD := Color("ffc23d")
const OUTLINE := Color("1c0f2e")
const TEXT := Color("fff8ec")

const CARPET_EYES := 0
const CARPET_STARS := 1
const CARPET_CONFETTI := 2
const WALL_DIAMONDS := 0
const WALL_SQUARES := 1
const WALL_ZIGZAG := 2
const WALL_STRIPES := 3

## Hand-tuned entries per casino id, applied over the computed palette.
const OVERRIDES := {
	&"apex": {
		"day": true,
		"wall": Color("e3d3b5"), "wall_alt": Color("efe2c8"), "wall_dark": Color("b39a68"),
		"wall_line": Color("d49a1c"), "wall_glow": 0.0, "wall_tile": 0.7,
		"ceiling": Color("6cc4ff"), "sky": Color("5fb8ff"),
		"floor_a": Color("142a78"), "floor_b": Color("ff6fae"), "floor_c": Color("e8287a"), "floor_d": Color("fff1a0"),
		"neon_1": Color("ffcf4a"), "neon_2": Color("ff5fc8"), "neon_3": Color("3ef0ff"), "neon_4": Color("ffffff"),
		"ambient": Color("e8eeff"), "ambient_energy": 0.55, "fog": Color("b9dcff"),
		"carpet_pattern": CARPET_STARS, "wall_pattern": WALL_STRIPES,
	},
	&"grand_marquee": {
		"wall": Color("3a1450"), "wall_alt": Color("4a1a62"), "wall_line": Color("ffc23d"), "wall_glow": 0.3,
		"floor_a": Color("2a0f2e"), "floor_b": Color("ff8a3d"), "floor_c": Color("e0283c"), "floor_d": Color("ffd23f"),
		"carpet_pattern": CARPET_EYES, "wall_pattern": WALL_SQUARES, "wall_tile": 1.0,
	},
	&"riverboat_queen": {
		"wall": Color("5c1a32"), "wall_alt": Color("6e2440"), "wall_line": Color("e8c27a"), "wall_glow": 0.0,
		"floor_a": Color("0e3644"), "floor_b": Color("e8a33d"), "floor_c": Color("c23a3a"), "floor_d": Color("f4e3c0"),
		"carpet_pattern": CARPET_EYES, "wall_pattern": WALL_STRIPES, "wall_tile": 0.8,
	},
	&"neon_oasis": {
		"wall": Color("3a1660"), "wall_alt": Color("4b1d78"), "wall_line": Color("ff4fd8"), "wall_glow": 0.35,
		"floor_a": Color("0f2346"), "floor_b": Color("ff5fb8"), "floor_c": Color("1fc8c0"), "floor_d": Color("ffd23f"),
		"carpet_pattern": CARPET_EYES, "wall_pattern": WALL_DIAMONDS, "wall_tile": 1.1,
	},
	&"rusty_spur": {
		"wall": Color("5a2418"), "wall_alt": Color("6c2e1c"), "wall_line": Color("e09a4a"), "wall_glow": 0.0,
		"floor_a": Color("3c1430"), "floor_b": Color("2fc4b2"), "floor_c": Color("ff8a3d"), "floor_d": Color("ffd23f"),
		"carpet_pattern": CARPET_CONFETTI, "wall_pattern": WALL_ZIGZAG, "wall_tile": 1.4,
	},
	&"sals_back_room": {
		"wall": Color("1f3a3a"), "wall_alt": Color("2a4a48"), "wall_line": Color("c9b86a"), "wall_glow": 0.0,
		"floor_a": Color("2a1440"), "floor_b": Color("f0a53a"), "floor_c": Color("e04a2c"), "floor_d": Color("ffd23f"),
		"carpet_pattern": CARPET_EYES, "wall_pattern": WALL_ZIGZAG, "wall_tile": 1.4,
	},
}


## The default night-club palette (no casino).
static func club() -> Dictionary:
	return for_casino({})


static func for_casino(casino: Dictionary) -> Dictionary:
	var floor_src: Color = casino.get("floor_color", Color("1f2a5a"))
	var wall_src: Color = casino.get("wall_color", CLUB_WALL)
	var accent_src: Color = casino.get("accent_color", NEON_MAGENTA)
	var p := {}
	# Walls: the casino's hue, dark and saturated, pulled toward club purple.
	var wall := push(wall_src, 0.5, 0.26, 0.4).lerp(CLUB_WALL, 0.45)
	p["wall"] = wall
	p["wall_alt"] = wall.lightened(0.12)
	p["wall_dark"] = wall.darkened(0.4)
	p["ceiling"] = wall.lerp(CLUB_CEILING, 0.6)
	p["sky"] = CLUB_CEILING.darkened(0.3)
	# Neons: the casino accent at full blast, then the club neons that contrast with it most.
	var accent := push(accent_src, 0.75, 0.95, 1.0)
	var others: Array[Color] = []
	for c: Color in NEONS:
		if _hue_distance(c, accent) > 0.08:
			others.append(c)
	others.sort_custom(func(a: Color, b: Color) -> bool: return _hue_distance(a, accent) > _hue_distance(b, accent))
	p["neon_1"] = accent
	for i in 3:
		p["neon_%d" % (i + 2)] = others[i % others.size()] if not others.is_empty() else NEON_CYAN
	p["wall_line"] = wall.lightened(0.3).lerp(accent, 0.35)
	p["wall_glow"] = 0.15
	p["wall_tile"] = 0.9
	# Carpet: a dark saturated base from the casino floor, loud motifs from the neons.
	p["floor_a"] = push(floor_src, 0.55, 0.14, 0.22).lerp(Color("15103f"), 0.3)
	p["floor_b"] = NEON_ORANGE
	p["floor_c"] = CASINO_RED
	p["floor_d"] = accent
	p["felt"] = FELT_GREEN
	p["felt_border"] = Color("ffe08a")
	p["wood"] = Color("a0522d")
	p["wood_dark"] = Color("5e2a1a")
	p["metal"] = Color("b8b2d8")
	p["gold"] = GOLD
	p["red"] = CASINO_RED
	p["text"] = TEXT
	p["outline"] = OUTLINE
	p["ambient"] = wall.lerp(Color.WHITE, 0.62).lerp(accent, 0.12)
	p["ambient_energy"] = 0.6
	p["fog"] = wall.darkened(0.2)
	p["carpet_pattern"] = CARPET_EYES
	p["wall_pattern"] = WALL_DIAMONDS
	p["day"] = false
	var id: StringName = StringName(casino.get("id", &""))
	if OVERRIDES.has(id):
		var o: Dictionary = OVERRIDES[id]
		for k: String in o:
			p[k] = o[k]
		if not o.has("ceiling") and o.has("wall"):
			p["ceiling"] = (p["wall"] as Color).lerp(CLUB_CEILING, 0.6)
		if not o.has("wall_dark") and o.has("wall"):
			p["wall_dark"] = (p["wall"] as Color).darkened(0.4)
		if not o.has("ambient") and o.has("wall"):
			p["ambient"] = (p["wall"] as Color).lerp(Color.WHITE, 0.62).lerp(p["neon_1"], 0.12)
		if not o.has("fog") and o.has("wall"):
			p["fog"] = (p["wall"] as Color).darkened(0.2)
	return p


## `c` with saturation at least `min_sat` and value clamped to [min_val, max_val].
static func push(c: Color, min_sat: float, min_val: float, max_val: float) -> Color:
	var out := Color.from_hsv(c.h, maxf(c.s, min_sat), clampf(c.v, min_val, max_val), c.a)
	return out


## The palette's four carpet colors, in carpet.gdshader order.
static func carpet_colors(palette: Dictionary) -> Array[Color]:
	var out: Array[Color] = [palette["floor_a"], palette["floor_b"], palette["floor_c"], palette["floor_d"]]
	return out


static func neons(palette: Dictionary) -> Array[Color]:
	var out: Array[Color] = [palette["neon_1"], palette["neon_2"], palette["neon_3"], palette["neon_4"]]
	return out


static func _hue_distance(a: Color, b: Color) -> float:
	var d := absf(a.h - b.h)
	return minf(d, 1.0 - d)
