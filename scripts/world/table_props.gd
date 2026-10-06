class_name TableProps
extends RefCounted
## Per-game graybox props for TableNode, built from Primitives: a slot cabinet,
## a high-low card table, the upright big wheel, a dice table, a roulette table
## and a blackjack half-moon.
##
## A prop is a Node3D in table space: floor at y = 0, the player's seat on the
## +Z side (a seated player faces -Z), the dealer on the -Z side facing the
## seat. TableNode plays a result as prepare(result, seconds) then step(t) for
## t from 0 to 1. Every step sets the whole animated state from t alone, so
## step(1.0) snaps straight to the result. show_hand() runs its own short
## tween; finish_hand() completes it at once.

const WOOD := Color("6b3f1f")
const WOOD_DARK := Color("3f2412")
const LEATHER := Color("2b1a12")
const FELT := Color("1f7a3d")
const FELT_DARK := Color("165a2d")
const FELT_LINE := Color("e8e2c8")
const GOLD := Color("d4a72c")
const STEEL := Color("9aa0a6")
const CHROME := Color("c8ccd2")
const CUSHION := Color("7a1f2b")
const SCREEN_DARK := Color("141418")
const CARD_FACE := Color("f7f5ee")
const CARD_BACK := Color("8b1e2d")
const CARD_RED := Color("c81e32")
const CARD_BLACK := Color("16161a")
const POCKET_RED := Color("c0392b")
const POCKET_BLACK := Color("1b1b1f")
const POCKET_GREEN := Color("1e8c3a")
const DIE_WHITE := Color("f4f1ea")
const PIP := Color("1a1a1e")
const SUITS: Array[String] = ["♠", "♥", "♦", "♣"]
## Seat height of the stools (a seated CharacterModel's hips are at SIT_HIP_Y).
const STOOL_TOP := 0.4


## Builds the prop for a game type (an unknown type gets a blackjack table).
static func create(game_type: int, accent: Color, rng_seed: int = 0) -> Prop:
	var p: Prop
	match game_type:
		HR.GameType.SLOTS:
			p = SlotsProp.new()
		HR.GameType.HIGH_LOW:
			p = HighLowProp.new()
		HR.GameType.BIG_WHEEL:
			p = WheelProp.new()
		HR.GameType.DICE:
			p = DiceProp.new()
		HR.GameType.ROULETTE:
			p = RouletteProp.new()
		HR.GameType.BLACKJACK:
			p = BlackjackProp.new()
		_:
			push_warning("TableProps: unknown game type %d" % game_type)
			p = BlackjackProp.new()
	p.game_type = game_type
	p.accent = accent
	p.rng.seed = rng_seed
	p.build()
	return p


## "2".."10", "J", "Q", "K", "A" for a high-low card value (2–14).
static func rank_text(value: int) -> String:
	match value:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14, 1:
			return "A"
	return str(clampi(value, 2, 10))


## A blackjack card value (2–11; 10 covers tens and faces, 11 is the ace) as a
## rank. `pick` chooses which ten-value card a 10 shows.
static func blackjack_rank(value: int, pick: int) -> String:
	if value >= 11:
		return "A"
	if value == 10:
		return ["10", "J", "Q", "K"][posmod(pick, 4)]
	return str(clampi(value, 2, 9))


static func suit_for(value: int, salt: int) -> String:
	return SUITS[posmod(hash(Vector2i(value, salt)), SUITS.size())]


static func is_red_suit(suit: String) -> bool:
	return suit == "♥" or suit == "♦"


## Sets a label's text and scales it to fit max_w × max_h metres.
static func fit_label(label: Label3D, text: String, max_w: float, max_h: float, font_size: int = 64) -> void:
	label.font_size = font_size
	label.text = text
	label.pixel_size = fit_pixel_size(text, max_w, max_h, font_size)


static func fit_pixel_size(text: String, max_w: float, max_h: float, font_size: int = 64) -> float:
	var font: Font = ThemeDB.fallback_font
	var lines: PackedStringArray = text.split("\n")
	var w := 1.0
	for line: String in lines:
		w = maxf(w, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var h: float = maxf(1.0, font.get_height(font_size) * float(lines.size()))
	return minf(max_w / w, max_h / h)


## The basis that turns a die (pips laid out as in DiceProp) so `value` faces up.
static func die_face_up(value: int) -> Basis:
	match value:
		6:
			return Basis(Vector3.RIGHT, PI)
		2:
			return Basis(Vector3.RIGHT, -PI * 0.5)
		5:
			return Basis(Vector3.RIGHT, PI * 0.5)
		3:
			return Basis(Vector3.BACK, PI * 0.5)
		4:
			return Basis(Vector3.BACK, -PI * 0.5)
	return Basis.IDENTITY


## Which die value a basis shows on top.
static func die_value_up(basis: Basis) -> int:
	var best := 1
	var best_dot := -2.0
	for v in range(1, 7):
		var n: Vector3 = basis * DiceProp.FACE_NORMALS[v]
		if n.y > best_dot:
			best_dot = n.y
			best = v
	return best


static func ease_out(t: float, power: float = 3.0) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), power)


static func ints(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if v is Array:
		for x: Variant in v:
			out.append(int(x))
	return out


static func detail_of(result: Dictionary) -> Dictionary:
	var d: Variant = result.get("detail", {})
	return d if d is Dictionary else {}


# --- Base ----------------------------------------------------------------------

class Prop extends Node3D:
	var game_type: int = 0
	var accent: Color = TableProps.GOLD
	var rng := RandomNumberGenerator.new()
	## Table collision on the world layer: players and guards walk around it.
	var body: StaticBody3D
	## Floor point under the main seat; a seated player there faces -Z.
	var seat_x: float = 0.0
	var seat_z: float = 1.0
	var seat_count: int = 1
	## Extra seats (crew dice) alternate left and right of the main one.
	var seat_spacing: float = 0.75
	var has_dealer: bool = true
	var dealer_spot := Vector3(0.0, 0.0, -0.85)
	## CharacterModel yaw at the dealer spot (PI faces the seat side).
	var dealer_yaw: float = PI
	## Highest point of the prop (the name sign floats above it).
	var top_y: float = 1.9
	var interact_point := Vector3(0.0, 0.9, 0.6)
	var light_point := Vector3(0.0, 1.7, 0.5)
	## Where the result caption pops (above the dealer's head by default).
	var pop_point := Vector3(0.0, 2.18, 0.2)
	## Height of the floating name sign above top_y.
	var name_lift: float = 0.75
	## A swapped dealer walks off this way (and the new one comes back from there).
	var swap_dir := Vector3.RIGHT
	## Where the win chips burst from.
	var burst_point := Vector3(0.0, 0.95, 0.1)
	var _hand_tween: Tween

	func build() -> void:
		body = StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		_build()
		for i in seat_count:
			_stool(seat_position(i))
		if has_dealer:
			add_collider(Vector3(0.8, 1.2, 0.6), dealer_spot + Vector3(0.0, 0.6, 0.0))

	func seat_position(index: int) -> Vector3:
		var i: int = clampi(index, 0, seat_count - 1)
		var offset := 0.0
		if i > 0:
			offset = seat_spacing * float((i + 1) >> 1) * (1.0 if i % 2 == 1 else -1.0)
		return Vector3(seat_x + offset, 0.0, seat_z)

	## The game name: a floating sign above the prop by default.
	func place_name(label: Label3D, text: String, color: Color) -> void:
		label.name = "NameLabel"
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.outline_size = 10
		label.modulate = color
		TableProps.fit_label(label, text, 1.8, 0.24)
		label.position = Vector3(0.0, top_y + name_lift, 0.0)
		add_child(label)

	# Overridden per game.
	func _build() -> void:
		pass

	func prepare(_result: Dictionary, _seconds: float) -> void:
		pass

	func step(_t: float) -> void:
		pass

	## A first line for the result caption ("17 RED", "8", "BUST 24"...).
	func caption(_result: Dictionary) -> String:
		return ""

	func on_reveal(_result: Dictionary) -> void:
		pass

	func on_loud(_seconds: float) -> void:
		pass

	func show_hand(_state: Dictionary) -> void:
		pass

	## What the prop shows right now (per game; for tests and debugging).
	func shown() -> Dictionary:
		return {}

	func finish_hand() -> void:
		if _hand_tween != null and _hand_tween.is_valid():
			var tw := _hand_tween
			_hand_tween = null
			tw.custom_step(1000.0)
			tw.kill()

	func _run_hand(seconds: float, method: Callable) -> void:
		finish_hand()
		if not is_inside_tree():
			method.call(1.0)
			return
		_hand_tween = create_tween()
		_hand_tween.tween_method(method, 0.0, 1.0, maxf(seconds, 0.01))

	# --- Building helpers ---

	func add_box(size: Vector3, color: Color, pos: Vector3, parent: Node3D = null, emission: float = 0.0) -> MeshInstance3D:
		var mi := Primitives.box(size, color, emission)
		mi.position = pos
		(parent if parent != null else self).add_child(mi)
		return mi

	func add_cylinder(radius: float, height: float, color: Color, pos: Vector3, parent: Node3D = null, sides: int = 12, top_radius: float = -1.0) -> MeshInstance3D:
		var mi := Primitives.cylinder(radius, height, color, sides, top_radius)
		mi.position = pos
		(parent if parent != null else self).add_child(mi)
		return mi

	func add_sphere(radius: float, color: Color, pos: Vector3, parent: Node3D = null, segments: int = 8, emission: float = 0.0) -> MeshInstance3D:
		var mi := Primitives.sphere(radius, color, segments, emission)
		mi.position = pos
		(parent if parent != null else self).add_child(mi)
		return mi

	func add_collider(size: Vector3, pos: Vector3) -> CollisionShape3D:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.position = pos
		body.add_child(cs)
		return cs

	## A text label (flat when `flat`: lying on a surface, reading from the seat).
	func add_text(text: String, pos: Vector3, max_w: float, max_h: float, color: Color, flat: bool = false, parent: Node3D = null) -> Label3D:
		var l := Label3D.new()
		TableProps.fit_label(l, text, max_w, max_h)
		l.modulate = color
		l.outline_size = 0
		l.position = pos
		if flat:
			l.rotation.x = -PI * 0.5
		(parent if parent != null else self).add_child(l)
		return l

	## A felt top on a wood top on a pedestal: the felt's top face is at top_h.
	func _rect_table(size: Vector2, top_h: float, felt: Color) -> void:
		add_box(Vector3(size.x * 0.7, top_h - 0.1, size.y * 0.6), TableProps.WOOD_DARK, Vector3(0.0, (top_h - 0.1) * 0.5, 0.0))
		add_box(Vector3(size.x, 0.08, size.y), TableProps.WOOD, Vector3(0.0, top_h - 0.055, 0.0))
		add_box(Vector3(size.x - 0.1, 0.02, size.y - 0.1), felt, Vector3(0.0, top_h - 0.01, 0.0))

	func _stool(pos: Vector3) -> void:
		add_cylinder(0.17, 0.03, TableProps.CHROME, pos + Vector3(0.0, 0.015, 0.0), null, 12)
		add_cylinder(0.035, TableProps.STOOL_TOP - 0.08, TableProps.CHROME, pos + Vector3(0.0, (TableProps.STOOL_TOP - 0.08) * 0.5 + 0.02, 0.0), null, 8)
		add_cylinder(0.2, 0.07, TableProps.CUSHION, pos + Vector3(0.0, TableProps.STOOL_TOP - 0.035, 0.0), null, 14)


# --- Cards -----------------------------------------------------------------------

## A playing card lying flat (face +Y, text reading from +Z). Rotate it +90°
## about X to stand it up facing +Z.
class Card extends Node3D:
	var size: Vector2
	var face: MeshInstance3D
	var back: MeshInstance3D
	var label: Label3D
	var face_up: bool = false
	var value: int = 0
	var text: String = ""

	func _init(p_size: Vector2, thickness: float = 0.006) -> void:
		size = p_size
		face = Primitives.box(Vector3(size.x, thickness, size.y), TableProps.CARD_FACE)
		add_child(face)
		back = Primitives.box(Vector3(size.x, thickness, size.y), TableProps.CARD_BACK)
		add_child(back)
		var inlay := Primitives.box(Vector3(size.x * 0.74, 0.002, size.y * 0.8), TableProps.GOLD)
		inlay.position.y = thickness * 0.5
		back.add_child(inlay)
		var inner := Primitives.box(Vector3(size.x * 0.6, 0.002, size.y * 0.68), TableProps.CARD_BACK)
		inner.position.y = thickness * 0.5 + 0.0006
		back.add_child(inner)
		label = Label3D.new()
		label.rotation.x = -PI * 0.5
		label.position.y = thickness * 0.5 + 0.0015
		label.outline_size = 0
		label.double_sided = false
		add_child(label)
		set_face_up(false)

	func set_card(p_value: int, p_text: String, red: bool) -> void:
		value = p_value
		text = p_text
		TableProps.fit_label(label, p_text, size.x * 0.9, size.y * 0.56)
		label.modulate = TableProps.CARD_RED if red else TableProps.CARD_BLACK

	func set_face_up(up: bool) -> void:
		face_up = up
		face.visible = up
		label.visible = up
		back.visible = not up


# --- Slots -----------------------------------------------------------------------

class SlotsProp extends Prop:
	const FACES := {
		"cherry": ["CHERRY", Color("d62839")],
		"lemon": ["LEMON", Color("c9a100")],
		"orange": ["ORANGE", Color("e8710a")],
		"plum": ["PLUM", Color("7b2d8e")],
		"bell": ["BELL", Color("b8860b")],
		"bar": ["BAR", Color("1b1b1f")],
		"seven": ["7", Color("d62839")],
	}
	const REEL_Y := 1.22
	const REEL_Z := 0.2
	const REEL_X: Array[float] = [-0.25, 0.0, 0.25]
	const LEVER_PULL := 1.1
	## Reel i stops at STOP_AT + STOP_GAP × i of the spin.
	const STOP_AT := 0.5
	const STOP_GAP := 0.17

	var reels: Array[Label3D] = []
	var lever: Node3D
	var jackpot_light: MeshInstance3D
	var jackpot_mat: StandardMaterial3D
	var _px: Dictionary = {}
	var _shown: Array[String] = ["seven", "bar", "cherry"]
	var _from: Array[String] = []
	var _final: Array[String] = []
	var _seconds := 1.0
	var _offsets: Array[float] = [0.0, 0.0, 0.0]
	var _light_tween: Tween

	func _build() -> void:
		has_dealer = false
		seat_z = 0.95
		top_y = 2.15
		interact_point = Vector3(0.0, 0.9, 0.55)
		light_point = Vector3(0.0, 1.9, 0.7)
		pop_point = Vector3(0.0, 2.5, 0.25)
		burst_point = Vector3(0.0, 1.0, 0.35)
		var cab: Color = Color("8e1b2a").lerp(accent, 0.25)
		add_box(Vector3(0.9, 0.85, 0.7), cab, Vector3(0.0, 0.425, -0.05))
		add_box(Vector3(0.9, 0.85, 0.55), cab.lightened(0.1), Vector3(0.0, 1.275, -0.125))
		add_box(Vector3(0.84, 0.05, 0.24), TableProps.LEATHER, Vector3(0.0, 0.875, 0.2))
		var buttons: Array[Color] = [Color("e74c3c"), Color("f1c40f"), Color("2ecc71")]
		for i in 3:
			add_box(Vector3(0.1, 0.03, 0.06), buttons[i], Vector3(-0.2 + 0.2 * float(i), 0.91, 0.24), null, 1.2)
		add_box(Vector3(0.6, 0.08, 0.16), TableProps.STEEL, Vector3(0.0, 0.32, 0.32))
		# Reel windows in a dark frame on the upper cabinet's face (z = 0.15).
		add_box(Vector3(0.8, 0.42, 0.04), TableProps.SCREEN_DARK, Vector3(0.0, REEL_Y, 0.16))
		for x: float in REEL_X:
			add_box(Vector3(0.22, 0.3, 0.02), TableProps.CARD_FACE, Vector3(x, REEL_Y, 0.185))
		for sym: String in GameResolver.SLOT_SYMBOLS:
			var face: Array = FACES.get(sym, [sym.to_upper(), Color.BLACK])
			_px[sym] = TableProps.fit_pixel_size(str(face[0]), 0.19, 0.12)
		for i in 3:
			var l := Label3D.new()
			l.font_size = 64
			l.outline_size = 6
			l.outline_modulate = Color(1, 1, 1, 0.9)
			l.position = Vector3(REEL_X[i], REEL_Y, REEL_Z)
			add_child(l)
			reels.append(l)
			_show(i, _shown[i])
		# Topper (the name goes on its face) and the jackpot dome.
		add_box(Vector3(0.94, 0.26, 0.6), accent, Vector3(0.0, 1.83, -0.125))
		jackpot_mat = StandardMaterial3D.new()
		jackpot_mat.albedo_color = Color("e02020")
		jackpot_mat.emission_enabled = true
		jackpot_mat.emission = Color("ff3020")
		jackpot_mat.emission_energy_multiplier = 0.5
		jackpot_light = Primitives.sphere(0.13, Color("e02020"), 10)
		jackpot_light.material_override = jackpot_mat
		jackpot_light.position = Vector3(0.0, 2.02, -0.125)
		add_child(jackpot_light)
		# Lever on the right side (+X): the arm swings toward the player when pulled.
		add_box(Vector3(0.06, 0.16, 0.16), TableProps.CHROME, Vector3(0.48, 1.05, -0.05))
		lever = Node3D.new()
		lever.name = "Lever"
		lever.position = Vector3(0.53, 1.05, -0.05)
		add_child(lever)
		add_cylinder(0.022, 0.46, TableProps.CHROME, Vector3(0.0, 0.23, 0.0), lever, 8)
		add_sphere(0.06, Color("d62839"), Vector3(0.0, 0.47, 0.0), lever, 10)
		add_collider(Vector3(0.9, 1.96, 0.7), Vector3(0.0, 0.98, -0.05))

	func place_name(label: Label3D, text: String, color: Color) -> void:
		label.name = "NameLabel"
		label.outline_size = 8
		label.modulate = color.lightened(0.5)
		TableProps.fit_label(label, text, 0.84, 0.16)
		label.position = Vector3(0.0, 1.83, 0.177)
		add_child(label)

	func _show(i: int, sym: String) -> void:
		var face: Array = FACES.get(sym, [sym.to_upper(), Color.BLACK])
		var l := reels[i]
		l.text = str(face[0])
		l.modulate = face[1]
		l.pixel_size = float(_px.get(sym, 0.002))
		_shown[i] = sym

	func prepare(result: Dictionary, seconds: float) -> void:
		var d := TableProps.detail_of(result)
		_from = _shown.duplicate()
		_final.clear()
		var reels_v: Variant = d.get("reels", [])
		if reels_v is Array:
			for s: Variant in reels_v:
				if _final.size() < 3:
					_final.append(str(s))
		while _final.size() < 3:
			_final.append(_from[_final.size()])
		_seconds = maxf(seconds, 0.01)
		for i in 3:
			_offsets[i] = rng.randf_range(0.0, float(GameResolver.SLOT_SYMBOLS.size()))

	func step(t: float) -> void:
		if _final.size() < 3:
			return
		lever.rotation.x = LEVER_PULL * sin(clampf(t / 0.25, 0.0, 1.0) * PI)
		var symbols: Array[String] = GameResolver.SLOT_SYMBOLS
		for i in 3:
			var stop: float = STOP_AT + STOP_GAP * float(i)
			var l := reels[i]
			if t >= stop:
				_show(i, _final[i])
				var u: float = clampf((t - stop) / 0.1, 0.0, 1.0)
				l.position.y = REEL_Y - 0.03 * sin(u * PI)
			elif t < 0.08:
				_show(i, _from[i])
				l.position.y = REEL_Y
			else:
				var flicks: float = (t - 0.08) * _seconds * Tuning.TABLE_REEL_SYMBOLS_PER_SECOND + _offsets[i]
				_show(i, symbols[int(flicks) % symbols.size()])
				l.position.y = REEL_Y + (0.5 - fposmod(flicks, 1.0)) * 0.12

	func on_reveal(result: Dictionary) -> void:
		if bool(result.get("won", false)) and not bool(result.get("jackpot", false)):
			_strobe(0.6, 1)

	func on_loud(seconds: float) -> void:
		_strobe(seconds, Tuning.TABLE_LOUD_FLASH_PULSES * 2)

	func _strobe(seconds: float, pulses: int) -> void:
		if _light_tween != null and _light_tween.is_valid():
			_light_tween.kill()
		if not is_inside_tree():
			return
		_light_tween = create_tween()
		_light_tween.tween_method(_light_step.bind(pulses), 0.0, 1.0, seconds)

	func _light_step(t: float, pulses: int) -> void:
		var wave: float = 0.5 - 0.5 * cos(t * float(pulses) * TAU)
		jackpot_mat.emission_energy_multiplier = 0.5 + 6.0 * wave * (1.0 - t * 0.3)

	func shown() -> Dictionary:
		return {"reels": _shown.duplicate(), "texts": reels.map(func(l: Label3D) -> String: return l.text)}


# --- High-low ----------------------------------------------------------------------

class HighLowProp extends Prop:
	const CARD_SIZE := Vector2(0.36, 0.5)
	const CARD_Y := 1.13
	const CARD_Z := -0.326
	const MAIN_X := -0.24
	const NEXT_X := 0.24

	var main_holder: Node3D
	var next_holder: Node3D
	var main_card: Card
	var next_card: Card
	var arrow: Label3D
	var pot_label: Label3D
	## 0 nothing to animate, 1 a guess reveal, 2 a cash out.
	var _mode := 0
	var _higher := true

	func _build() -> void:
		seat_z = 0.95
		dealer_spot = Vector3(0.0, 0.0, -0.78)
		top_y = 1.9
		interact_point = Vector3(0.0, 0.9, 0.6)
		light_point = Vector3(0.0, 1.7, 0.45)
		burst_point = Vector3(0.0, 0.9, 0.1)
		_rect_table(Vector2(1.6, 0.9), 0.825, TableProps.FELT)
		add_box(Vector3(1.64, 0.07, 0.08), TableProps.LEATHER, Vector3(0.0, 0.845, 0.43))
		# The big card display: an upright board on the dealer's edge.
		add_box(Vector3(1.3, 0.62, 0.05), TableProps.FELT_DARK, Vector3(0.0, 1.135, -0.36))
		add_box(Vector3(1.34, 0.05, 0.07), accent, Vector3(0.0, 1.47, -0.36))
		main_holder = _holder(MAIN_X)
		next_holder = _holder(NEXT_X)
		main_card = Card.new(CARD_SIZE, 0.012)
		main_card.rotation.x = PI * 0.5
		main_holder.add_child(main_card)
		next_card = Card.new(CARD_SIZE, 0.012)
		next_card.rotation.x = PI * 0.5
		next_holder.add_child(next_card)
		arrow = Label3D.new()
		arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		arrow.modulate = TableProps.GOLD
		arrow.outline_size = 10
		TableProps.fit_label(arrow, "▲", 0.1, 0.12)
		arrow.position = Vector3(0.0, CARD_Y, -0.28)
		arrow.visible = false
		add_child(arrow)
		pot_label = add_text("", Vector3(0.0, 0.84, 0.08), 0.6, 0.1, TableProps.GOLD)
		pot_label.rotation.x = -1.1
		add_collider(Vector3(1.6, 0.88, 0.9), Vector3(0.0, 0.44, 0.0))

	func _holder(x: float) -> Node3D:
		var h := Node3D.new()
		h.position = Vector3(x, CARD_Y, CARD_Z)
		add_child(h)
		return h

	func _set_value(card: Card, value: int, index: int) -> void:
		var suit: String = TableProps.suit_for(value, index)
		card.set_card(value, TableProps.rank_text(value) + suit, TableProps.is_red_suit(suit))

	func _set_pot(pot: int) -> void:
		TableProps.fit_label(pot_label, "POT %d" % pot, 0.6, 0.1)

	func show_hand(state: Dictionary) -> void:
		finish_hand()
		var card: int = int(state.get("card", 0))
		var streak: int = int(state.get("streak", 0))
		_set_pot(int(state.get("pot", 0)))
		arrow.visible = false
		next_holder.rotation = Vector3.ZERO
		next_card.scale = Vector3.ONE
		next_card.set_face_up(false)
		if card < HighLowRun.CARD_MIN:
			return
		if main_card.face_up and main_card.text == TableProps.rank_text(card) + TableProps.suit_for(card, streak):
			return
		_run_hand(Tuning.TABLE_DEAL_SECONDS, _flip_main.bind(card, streak))

	func _flip_main(t: float, card: int, streak: int) -> void:
		if t >= 0.5:
			_set_value(main_card, card, streak)
			main_card.set_face_up(true)
		main_card.scale.x = maxf(0.02, absf(1.0 - 2.0 * t))

	func prepare(result: Dictionary, _seconds: float) -> void:
		finish_hand()
		var d := TableProps.detail_of(result)
		var won: bool = bool(result.get("won", false))
		main_card.scale = Vector3.ONE
		next_card.scale = Vector3.ONE
		next_holder.rotation = Vector3.ZERO
		if d.has("next_card"):
			_mode = 1
			var guesses: int = int(d.get("guesses", 0))
			var base_idx: int = guesses - 1 if won else guesses
			_higher = bool(d.get("higher", true))
			_set_value(main_card, int(d.get("card", main_card.value)), base_idx)
			main_card.set_face_up(true)
			_set_value(next_card, int(d["next_card"]), base_idx + 1)
			next_card.set_face_up(false)
			TableProps.fit_label(arrow, "▲" if _higher else "▼", 0.1, 0.12)
			if d.has("pot"):
				_set_pot(int(d["pot"]))
		elif d.has("current_card"):
			_mode = 2
			_set_value(main_card, int(d["current_card"]), int(d.get("guesses", 0)))
			main_card.set_face_up(true)
			next_card.set_face_up(false)
			arrow.visible = false
			_set_pot(int(d.get("pot", 0)))
		else:
			_mode = 0

	func step(t: float) -> void:
		if _mode != 1:
			return
		arrow.visible = true
		arrow.scale = Vector3.ONE * (1.0 + 0.4 * sin(clampf(t / 0.15, 0.0, 1.0) * PI))
		if t < 0.62:
			next_card.set_face_up(false)
			next_card.scale.x = 1.0
			var shake: float = smoothstep(0.12, 0.25, t) * (1.0 - smoothstep(0.5, 0.62, t))
			next_holder.rotation.z = 0.07 * sin(t * 60.0) * shake
		elif t < 0.82:
			var u: float = (t - 0.62) / 0.2
			next_holder.rotation.z = 0.0
			next_card.set_face_up(u >= 0.5)
			next_card.scale.x = maxf(0.02, absf(1.0 - 2.0 * u))
		else:
			next_holder.rotation.z = 0.0
			next_card.set_face_up(true)
			next_card.scale.x = 1.0

	func caption(result: Dictionary) -> String:
		var d := TableProps.detail_of(result)
		if d.has("next_card"):
			if not bool(result.get("won", false)):
				return ""
			return "▲ HIGHER" if bool(d.get("higher", true)) else "▼ LOWER"
		if d.has("cash_out"):
			return "CASH OUT"
		return ""

	func shown() -> Dictionary:
		return {
			"card": main_card.text if main_card.face_up else "",
			"next": next_card.text if next_card.face_up else "",
			"next_face_up": next_card.face_up,
			"pot": pot_label.text,
		}


# --- Big wheel -----------------------------------------------------------------------

class WheelProp extends Prop:
	const CENTER := Vector3(0.0, 1.62, -0.55)
	const RADIUS := 0.95
	const WIN_COLORS: Array[Color] = [Color("f2c230"), Color("2fbf71")]
	const BUST_COLORS: Array[Color] = [Color("b8202f"), Color("3a2448")]

	var wheel: Node3D
	var pointer: Node3D
	var _a0 := 0.0
	var _a1 := 0.0

	func _build() -> void:
		seat_z = 1.15
		dealer_spot = Vector3(1.35, 0.0, -0.1)
		dealer_yaw = atan2(dealer_spot.x - seat_x, -(seat_z - dealer_spot.z))
		top_y = CENTER.y + RADIUS + 0.22
		interact_point = Vector3(0.0, 0.9, 0.8)
		light_point = Vector3(0.0, 1.8, 0.5)
		pop_point = Vector3(0.0, 1.2, 0.75)
		name_lift = 0.25
		swap_dir = Vector3.FORWARD
		burst_point = Vector3(0.0, 1.0, 0.4)
		var n: int = GameResolver.WHEEL_LABELS.size()
		var seg: float = TAU / float(n)
		# Plinth and a post behind the wheel up to the pointer mount.
		add_box(Vector3(1.2, 0.3, 0.7), TableProps.WOOD_DARK, Vector3(0.0, 0.15, -0.6))
		var post_h: float = CENTER.y + RADIUS + 0.2 - 0.3
		add_box(Vector3(0.24, post_h, 0.16), accent.darkened(0.35), Vector3(0.0, 0.3 + post_h * 0.5, -0.7))
		wheel = Node3D.new()
		wheel.name = "Wheel"
		wheel.position = CENTER
		add_child(wheel)
		var rim := Primitives.cylinder(RADIUS + 0.07, 0.06, Color("2a1a3a"), 32)
		rim.rotation.x = PI * 0.5
		rim.position.z = -0.03
		wheel.add_child(rim)
		var h: float = RADIUS * cos(seg * 0.5)
		var w: float = 2.0 * RADIUS * sin(seg * 0.5)
		for i in n:
			var phi: float = seg * float(i)
			var dir := Vector3(sin(phi), cos(phi), 0.0)
			var wins: bool = GameResolver.wheel_segment_wins(i)
			var palette: Array[Color] = WIN_COLORS if wins else BUST_COLORS
			var wedge := Primitives.prism(Vector3(w, h, 0.04), palette[(i >> 1) % palette.size()])
			wedge.position = dir * (h * 0.5) + Vector3(0.0, 0.0, 0.022)
			wedge.rotation.z = PI - phi
			wheel.add_child(wedge)
			var l := Label3D.new()
			l.outline_size = 10
			l.modulate = Color.WHITE
			TableProps.fit_label(l, GameResolver.WHEEL_LABELS[i], 0.26, 0.12)
			l.position = dir * (RADIUS * 0.74) + Vector3(0.0, 0.0, 0.045)
			l.rotation.z = -phi
			wheel.add_child(l)
			var peg_phi: float = phi + seg * 0.5
			add_sphere(0.025, TableProps.GOLD, Vector3(sin(peg_phi), cos(peg_phi), 0.0) * (RADIUS - 0.035) + Vector3(0.0, 0.0, 0.05), wheel, 6)
		var hub := Primitives.cylinder(0.13, 0.06, TableProps.GOLD, 16)
		hub.rotation.x = PI * 0.5
		hub.position.z = 0.06
		wheel.add_child(hub)
		add_sphere(0.06, accent, Vector3(0.0, 0.0, 0.09), wheel, 10)
		# Pointer: a mount on the post and a flapper hanging over the top segment.
		var mount_y: float = CENTER.y + RADIUS + 0.16
		add_box(Vector3(0.2, 0.12, 0.26), TableProps.GOLD, Vector3(0.0, mount_y, CENTER.z - 0.02))
		pointer = Node3D.new()
		pointer.name = "Pointer"
		pointer.position = Vector3(0.0, CENTER.y + RADIUS + 0.12, CENTER.z + 0.1)
		add_child(pointer)
		var flap := Primitives.prism(Vector3(0.16, 0.24, 0.04), Color("d62839"))
		flap.rotation.z = PI
		flap.position.y = -0.1
		pointer.add_child(flap)
		# Betting counter in front of the wheel.
		add_box(Vector3(1.6, 0.8, 0.45), TableProps.WOOD, Vector3(0.0, 0.4, 0.38))
		add_box(Vector3(1.5, 0.02, 0.37), TableProps.FELT, Vector3(0.0, 0.81, 0.38))
		var payout: float = TableGames.profit_multiple(HR.GameType.BIG_WHEEL)
		add_text("WIN PAYS %d TO 1" % int(payout), Vector3(0.0, 0.822, 0.38), 1.1, 0.12, TableProps.FELT_LINE, true)
		add_collider(Vector3(2.1, CENTER.y + RADIUS + 0.1, 0.45), Vector3(0.0, (CENTER.y + RADIUS + 0.1) * 0.5, -0.6))
		add_collider(Vector3(1.6, 0.84, 0.45), Vector3(0.0, 0.42, 0.38))

	func prepare(result: Dictionary, _seconds: float) -> void:
		var n: int = GameResolver.WHEEL_LABELS.size()
		var target_seg: int = clampi(int(TableProps.detail_of(result).get("segment", 0)), 0, n - 1)
		var target: float = TAU / float(n) * float(target_seg)
		_a0 = wheel.rotation.z
		var base: float = _a0 + float(Tuning.TABLE_WHEEL_TURNS) * TAU
		_a1 = base + fposmod(target - base, TAU)

	func step(t: float) -> void:
		var a: float = lerpf(_a0, _a1, TableProps.ease_out(t, 3.0))
		wheel.rotation.z = a
		# The flapper kicks back as each peg passes, less as the wheel slows.
		var phase: float = a / (TAU / float(GameResolver.WHEEL_LABELS.size()))
		var speed: float = minf(1.0, 3.0 * pow(1.0 - t, 2.0))
		pointer.rotation.z = -0.4 * speed * pow(1.0 - fposmod(phase, 1.0), 2.0)

	## The segment under the pointer right now.
	func segment_at_pointer() -> int:
		var n: int = GameResolver.WHEEL_LABELS.size()
		return posmod(roundi(wheel.rotation.z / (TAU / float(n))), n)

	func shown() -> Dictionary:
		var s := segment_at_pointer()
		return {"segment": s, "label": GameResolver.WHEEL_LABELS[s]}


# --- Dice -----------------------------------------------------------------------

class DiceProp extends Prop:
	const DIE := 0.12
	const FELT_TOP := 0.825
	## Face normals by value: 1 up, 6 down, 2 front, 5 back, 3 right, 4 left.
	const FACE_NORMALS := {
		1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.BACK, 5: Vector3.FORWARD, 3: Vector3.RIGHT, 4: Vector3.LEFT,
	}
	const PIPS := {
		1: [Vector2(0, 0)],
		2: [Vector2(-1, -1), Vector2(1, 1)],
		3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
		4: [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)],
		5: [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1), Vector2(0, 0)],
		6: [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)],
	}

	var dice: Array[Node3D] = []
	var _start: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var _wall: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var _end: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
	var _end_basis: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]
	var _axes: Array[Vector3] = [Vector3.UP, Vector3.UP]
	var _spins: Array[float] = [0.0, 0.0]
	var _ready_roll := false

	func _build() -> void:
		seat_z = 1.05
		seat_count = 3
		dealer_spot = Vector3(0.0, 0.0, -0.95)
		top_y = 1.9
		interact_point = Vector3(0.0, 0.9, 0.7)
		light_point = Vector3(0.0, 1.6, 0.4)
		burst_point = Vector3(0.0, 0.95, 0.0)
		_rect_table(Vector2(2.4, 1.2), FELT_TOP, TableProps.FELT)
		var rail: Color = TableProps.WOOD.darkened(0.2)
		for z: float in [-0.55, 0.55]:
			add_box(Vector3(2.4, 0.12, 0.1), rail, Vector3(0.0, FELT_TOP + 0.04, z))
		for x: float in [-1.15, 1.15]:
			add_box(Vector3(0.1, 0.12, 1.0), rail, Vector3(x, FELT_TOP + 0.04, 0.0))
		# Bet areas on the player's side of the felt.
		for side: int in [-1, 1]:
			add_box(Vector3(0.8, 0.004, 0.36), TableProps.FELT_DARK, Vector3(0.6 * float(side), FELT_TOP + 0.002, 0.25))
		add_text("HIGH 8–12", Vector3(-0.6, FELT_TOP + 0.006, 0.25), 0.6, 0.1, TableProps.FELT_LINE, true)
		add_text("LOW 2–6", Vector3(0.6, FELT_TOP + 0.006, 0.25), 0.6, 0.1, TableProps.FELT_LINE, true)
		add_text("7 HOUSE", Vector3(0.0, FELT_TOP + 0.006, 0.3), 0.3, 0.07, TableProps.GOLD, true)
		for i in 2:
			var die := _make_die()
			add_child(die)
			dice.append(die)
		_rest([6, 6])
		add_collider(Vector3(2.4, FELT_TOP + 0.1, 1.2), Vector3(0.0, (FELT_TOP + 0.1) * 0.5, 0.0))

	func _make_die() -> Node3D:
		var die := Node3D.new()
		die.name = "Die"
		die.add_child(Primitives.box(Vector3.ONE * DIE, TableProps.DIE_WHITE))
		var half: float = DIE * 0.5
		var o: float = DIE * 0.27
		for v: int in FACE_NORMALS:
			var n: Vector3 = FACE_NORMALS[v]
			var u: Vector3 = Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
			var w: Vector3 = n.cross(u)
			for p: Vector2 in PIPS[v]:
				var pip := Primitives.sphere(DIE * 0.11, TableProps.PIP, 6)
				pip.position = n * half + u * (p.x * o) + w * (p.y * o)
				die.add_child(pip)
		return die

	## Puts the dice at rest showing `values` (no animation).
	func _rest(values: Array) -> void:
		for i in 2:
			var v: int = clampi(int(values[i]) if i < values.size() else 1, 1, 6)
			dice[i].basis = Basis(Vector3.UP, 0.3 - 0.5 * float(i)) * TableProps.die_face_up(v)
			dice[i].position = Vector3(-0.18 + 0.36 * float(i), FELT_TOP + DIE * 0.5, -0.05 * float(i))

	func prepare(result: Dictionary, _seconds: float) -> void:
		var values: Array[int] = TableProps.ints(TableProps.detail_of(result).get("dice", []))
		_ready_roll = true
		for i in 2:
			var v: int = clampi(values[i] if i < values.size() else 1, 1, 6)
			_end_basis[i] = Basis(Vector3.UP, rng.randf_range(-0.7, 0.7)) * TableProps.die_face_up(v)
			_end[i] = Vector3(-0.2 + 0.4 * float(i) + rng.randf_range(-0.08, 0.08), FELT_TOP + DIE * 0.5, rng.randf_range(-0.2, 0.08))
			_start[i] = Vector3(0.55 + 0.14 * float(i), FELT_TOP + 0.3, 0.38)
			_wall[i] = Vector3(_end[i].x + rng.randf_range(-0.15, 0.25), FELT_TOP + DIE * 0.5, -0.42)
			_axes[i] = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			if _axes[i].length_squared() < 0.5:
				_axes[i] = Vector3.RIGHT
			_spins[i] = TAU * rng.randf_range(3.0, 5.0)

	func step(t: float) -> void:
		if not _ready_roll:
			return
		for i in 2:
			var pos: Vector3
			if t < 0.4:
				var u: float = t / 0.4
				pos = _start[i].lerp(_wall[i], u)
				pos.y += 0.25 * sin(u * PI)
			else:
				var u: float = (t - 0.4) / 0.6
				pos = _wall[i].lerp(_end[i], TableProps.ease_out(u, 2.0))
				pos.y = _end[i].y + 0.16 * absf(sin(u * 3.0 * PI)) * pow(1.0 - u, 2.0)
			dice[i].position = pos
			dice[i].basis = Basis(_axes[i], _spins[i] * (1.0 - TableProps.ease_out(t, 2.0))) * _end_basis[i]

	func caption(result: Dictionary) -> String:
		var d := TableProps.detail_of(result)
		if not d.has("total"):
			return ""
		var total: int = int(d["total"])
		if total == GameResolver.DICE_HOUSE_TOTAL:
			return "%d HOUSE" % total
		return "%d %s" % [total, "HIGH" if total > GameResolver.DICE_HOUSE_TOTAL else "LOW"]

	func shown() -> Dictionary:
		var faces: Array[int] = []
		for d: Node3D in dice:
			faces.append(TableProps.die_value_up(d.basis))
		return {"dice": faces}


# --- Roulette -----------------------------------------------------------------------

class RouletteProp extends Prop:
	## European single-zero pocket order, clockwise from above.
	const ORDER: Array[int] = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
	const FELT_TOP := 0.805
	const WHEEL_C := Vector3(-0.85, 0.9, 0.0)
	const TRACK_R := 0.43
	const POCKET_R := 0.31
	const BALL_R := 0.022
	## The ball drops into its pocket at this share of the spin.
	const LAND := 0.8
	const CELL := Vector2(0.11, 0.14)
	const GRID_X0 := -0.19
	const GRID_Z0 := -0.32

	var rotor: Node3D
	var ball: MeshInstance3D
	var tote: MeshInstance3D
	var tote_label: Label3D
	var dolly: MeshInstance3D
	var _cells: Dictionary = {}
	var _r0 := 0.0
	var _r1 := 0.0
	var _rel0 := 0.0
	var _rel1 := 0.0
	var _ball_angle := 0.0
	var _ball_radius := POCKET_R
	var _number := 0
	var _ready_spin := false

	func _build() -> void:
		seat_x = 0.45
		seat_z = 1.1
		dealer_spot = Vector3(0.45, 0.0, -0.95)
		top_y = 1.9
		interact_point = Vector3(0.3, 0.9, 0.75)
		light_point = Vector3(-0.2, 1.6, 0.4)
		burst_point = Vector3(0.3, 0.9, 0.0)
		_rect_table(Vector2(2.8, 1.3), FELT_TOP, TableProps.FELT)
		_build_layout()
		_build_wheel()
		# Tote board behind the wheel shows the last number.
		add_cylinder(0.025, 1.2, TableProps.CHROME, Vector3(WHEEL_C.x, 0.6, -0.75), null, 8)
		tote = add_box(Vector3(0.36, 0.3, 0.05), TableProps.POCKET_GREEN, Vector3(WHEEL_C.x, 1.32, -0.72))
		add_box(Vector3(0.4, 0.34, 0.04), TableProps.GOLD, Vector3(WHEEL_C.x, 1.32, -0.75))
		tote_label = add_text("--", Vector3(WHEEL_C.x, 1.32, -0.693), 0.3, 0.2, Color.WHITE)
		tote_label.outline_size = 8
		add_collider(Vector3(2.8, FELT_TOP + 0.12, 1.3), Vector3(0.0, (FELT_TOP + 0.12) * 0.5, 0.0))

	func _build_layout() -> void:
		var y: float = FELT_TOP + 0.002
		for c in 12:
			for r in 3:
				var n: int = 3 * c + 3 - r
				var pos := Vector3(GRID_X0 + CELL.x * (float(c) + 0.5), y, GRID_Z0 + CELL.y * (float(r) + 0.5))
				var col: Color = TableProps.POCKET_RED if GameResolver.roulette_color(n) == "red" else TableProps.POCKET_BLACK
				add_box(Vector3(CELL.x - 0.012, 0.004, CELL.y - 0.012), col, pos)
				_cells[n] = pos
		var zero := Vector3(GRID_X0 - 0.055, y, GRID_Z0 + CELL.y * 1.5)
		add_box(Vector3(0.1, 0.004, CELL.y * 3.0 - 0.012), TableProps.POCKET_GREEN, zero)
		_cells[0] = zero
		add_box(Vector3(0.36, 0.004, 0.14), TableProps.POCKET_RED, Vector3(GRID_X0 + 0.36, y, 0.24))
		add_box(Vector3(0.36, 0.004, 0.14), TableProps.POCKET_BLACK, Vector3(GRID_X0 + 0.96, y, 0.24))
		dolly = Primitives.cylinder(0.03, 0.06, TableProps.CARD_FACE, 10)
		dolly.visible = false
		add_child(dolly)

	func _build_wheel() -> void:
		var bowl := WHEEL_C + Vector3(0.0, -0.06, 0.0)
		add_cylinder(0.53, 0.12, TableProps.WOOD_DARK, bowl, null, 24)
		var rim_mesh := TorusMesh.new()
		rim_mesh.inner_radius = 0.47
		rim_mesh.outer_radius = 0.55
		rim_mesh.rings = 24
		rim_mesh.ring_segments = 6
		rim_mesh.material = Primitives.material(TableProps.WOOD)
		var rim := MeshInstance3D.new()
		rim.mesh = rim_mesh
		rim.position = WHEEL_C + Vector3(0.0, 0.01, 0.0)
		add_child(rim)
		add_cylinder(0.47, 0.02, Color("b88a4a"), WHEEL_C + Vector3(0.0, -0.005, 0.0), null, 24)
		rotor = Node3D.new()
		rotor.name = "Rotor"
		rotor.position = WHEEL_C
		add_child(rotor)
		add_cylinder(0.38, 0.02, TableProps.GOLD, Vector3(0.0, 0.005, 0.0), rotor, 24)
		var step_a: float = TAU / float(ORDER.size())
		var width: float = TAU * POCKET_R / float(ORDER.size()) - 0.006
		for k in ORDER.size():
			var n: int = ORDER[k]
			var col: Color = TableProps.POCKET_GREEN
			match GameResolver.roulette_color(n):
				"red":
					col = TableProps.POCKET_RED
				"black":
					col = TableProps.POCKET_BLACK
			var a: float = step_a * float(k)
			var pocket := Primitives.box(Vector3(width, 0.012, 0.1), col)
			pocket.position = Vector3(sin(a) * POCKET_R, 0.016, cos(a) * POCKET_R)
			pocket.rotation.y = a
			rotor.add_child(pocket)
		add_cylinder(0.2, 0.06, TableProps.WOOD, Vector3(0.0, 0.04, 0.0), rotor, 16, 0.07)
		add_cylinder(0.015, 0.08, TableProps.GOLD, Vector3(0.0, 0.1, 0.0), rotor, 6)
		var bar := add_box(Vector3(0.16, 0.012, 0.012), TableProps.GOLD, Vector3(0.0, 0.13, 0.0), rotor)
		bar.rotation.y = PI * 0.25
		var bar2 := add_box(Vector3(0.16, 0.012, 0.012), TableProps.GOLD, Vector3(0.0, 0.13, 0.0), rotor)
		bar2.rotation.y = -PI * 0.25
		ball = Primitives.sphere(BALL_R, Color.WHITE, 8)
		ball.name = "Ball"
		add_child(ball)
		_place_ball(0.0, POCKET_R, 0.03)

	func _place_ball(angle: float, radius: float, h: float) -> void:
		_ball_angle = angle
		_ball_radius = radius
		ball.position = WHEEL_C + Vector3(sin(angle) * radius, h, cos(angle) * radius)

	func prepare(result: Dictionary, _seconds: float) -> void:
		_number = clampi(int(TableProps.detail_of(result).get("number", 0)), 0, GameResolver.ROULETTE_MAX_NUMBER)
		var k: int = maxi(0, ORDER.find(_number))
		var psi: float = TAU / float(ORDER.size()) * float(k)
		_r0 = rotor.rotation.y
		_r1 = _r0 + float(Tuning.TABLE_ROULETTE_TURNS) * TAU + rng.randf() * TAU
		_rel0 = _ball_angle - _r0
		_rel1 = _rel0 - (float(Tuning.TABLE_ROULETTE_BALL_TURNS) * TAU + fposmod(_rel0 - psi, TAU))
		dolly.visible = false
		_ready_spin = true

	func step(t: float) -> void:
		if not _ready_spin:
			return
		var rot: float = lerpf(_r0, _r1, TableProps.ease_out(t, 3.0))
		rotor.rotation.y = rot
		var s: float = clampf(t / LAND, 0.0, 1.0)
		var rel: float = lerpf(_rel0, _rel1, TableProps.ease_out(s, 2.0))
		var radius: float = lerpf(TRACK_R, POCKET_R, smoothstep(0.55, 0.92, s))
		var h: float = 0.028
		if s > 0.6 and s < 1.0:
			var u: float = (s - 0.6) / 0.4
			h += 0.035 * absf(sin(u * 2.0 * PI)) * (1.0 - u)
		_place_ball(rot + rel, radius, h)

	func on_reveal(_result: Dictionary) -> void:
		_show_number(_number)

	func _show_number(n: int) -> void:
		var col: String = GameResolver.roulette_color(n)
		var c: Color = TableProps.POCKET_GREEN
		if col == "red":
			c = TableProps.POCKET_RED
		elif col == "black":
			c = TableProps.POCKET_BLACK
		tote.material_override = Primitives.material(c)
		TableProps.fit_label(tote_label, str(n), 0.3, 0.2)
		var cell: Vector3 = _cells.get(n, _cells[0])
		dolly.position = cell + Vector3(0.0, 0.032, 0.0)
		dolly.visible = true

	func caption(result: Dictionary) -> String:
		var d := TableProps.detail_of(result)
		if not d.has("number"):
			return ""
		return "%d %s" % [int(d["number"]), str(d.get("color", GameResolver.roulette_color(int(d["number"])))).to_upper()]

	## The pocket the ball sits in (or is over) right now.
	func number_at_ball() -> int:
		var rel: float = fposmod(_ball_angle - rotor.rotation.y, TAU)
		var k: int = posmod(roundi(rel / (TAU / float(ORDER.size()))), ORDER.size())
		return ORDER[k]

	func shown() -> Dictionary:
		return {"number": number_at_ball(), "tote": tote_label.text, "ball_radius": _ball_radius}


# --- Blackjack -----------------------------------------------------------------------

class BlackjackProp extends Prop:
	const CENTER_Z := -0.45
	const RADIUS := 1.25
	const WEDGES := 8
	const FELT_TOP := 0.805
	const CARD := Vector2(0.2, 0.28)
	const CARD_Y := 0.809
	const HAND_X0 := -0.32
	const HAND_STEP := 0.21
	const PLAYER_Z := 0.3
	const DEALER_Z := -0.14
	const SHOE := Vector3(0.88, 0.95, -0.3)

	var player_nodes: Array[Card] = []
	var dealer_nodes: Array[Card] = []
	var totals: Array[Label3D] = []
	var _pvals: Array[int] = []
	var _dvals: Array[int] = []
	var _hole_down := false
	var _hand_over := false
	var _salt := 0
	var _events: Array[Dictionary] = []

	func _build() -> void:
		seat_z = 1.2
		dealer_spot = Vector3(0.0, 0.0, -0.85)
		top_y = 1.9
		interact_point = Vector3(0.0, 0.9, 0.85)
		light_point = Vector3(0.0, 1.6, 0.4)
		burst_point = Vector3(0.0, 0.9, 0.2)
		add_box(Vector3(1.4, FELT_TOP - 0.08, 0.6), TableProps.WOOD_DARK, Vector3(0.0, (FELT_TOP - 0.08) * 0.5, -0.05))
		# Felt half-moon: wedges fanned toward the player, a padded rail round the curve.
		var seg: float = PI / float(WEDGES)
		var h: float = RADIUS * cos(seg * 0.5)
		var w: float = 2.0 * RADIUS * sin(seg * 0.5)
		var under_h: float = (RADIUS + 0.06) * cos(seg * 0.5)
		var under_w: float = 2.0 * (RADIUS + 0.06) * sin(seg * 0.5)
		var c := Vector3(0.0, 0.0, CENTER_Z)
		for i in WEDGES:
			var psi: float = -PI * 0.5 + seg * (float(i) + 0.5)
			var dir := Vector3(sin(psi), 0.0, cos(psi))
			var wedge_basis := Basis(Vector3.UP, psi) * Basis(Vector3.RIGHT, -PI * 0.5)
			var felt := Primitives.prism(Vector3(w, h, 0.05), TableProps.FELT)
			felt.basis = wedge_basis
			felt.position = c + dir * (h * 0.5) + Vector3(0.0, FELT_TOP - 0.025, 0.0)
			add_child(felt)
			var wood := Primitives.prism(Vector3(under_w, under_h, 0.05), TableProps.WOOD)
			wood.basis = wedge_basis
			wood.position = c + dir * (under_h * 0.5) + Vector3(0.0, FELT_TOP - 0.06, 0.0)
			add_child(wood)
			var pad := add_box(Vector3(w * (RADIUS + 0.1) / RADIUS + 0.04, 0.08, 0.12), TableProps.LEATHER, c + dir * (RADIUS + 0.06) + Vector3(0.0, FELT_TOP + 0.02, 0.0))
			pad.rotation.y = psi
		add_box(Vector3(2.0 * RADIUS + 0.24, 0.1, 0.1), TableProps.WOOD, Vector3(0.0, FELT_TOP - 0.03, CENTER_Z - 0.05))
		# Betting circles and the dealer's card line.
		for psi: float in [-0.9, 0.0, 0.9]:
			var spot: Vector3 = c + Vector3(sin(psi), 0.0, cos(psi)) * 1.0
			add_cylinder(0.1, 0.004, TableProps.FELT_LINE, spot + Vector3(0.0, FELT_TOP + 0.002, 0.0), null, 16)
			add_cylinder(0.09, 0.004, TableProps.FELT, spot + Vector3(0.0, FELT_TOP + 0.003, 0.0), null, 16)
		add_text("BLACKJACK PAYS 1 TO 1", Vector3(0.0, FELT_TOP + 0.003, 0.08), 0.8, 0.06, TableProps.GOLD, true)
		add_text("DEALER STANDS ON ALL 17s", Vector3(0.0, FELT_TOP + 0.003, -0.34), 0.7, 0.05, TableProps.FELT_LINE, true)
		add_box(Vector3(0.18, 0.12, 0.3), TableProps.CARD_BACK, Vector3(SHOE.x, FELT_TOP + 0.06, SHOE.z))
		for z: float in [PLAYER_Z, DEALER_Z]:
			var l := Label3D.new()
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.outline_size = 10
			l.modulate = Color.WHITE
			TableProps.fit_label(l, "00", 0.2, 0.11)
			l.text = ""
			l.position = Vector3(HAND_X0 - 0.3, 1.0, z)
			add_child(l)
			totals.append(l)
		add_collider(Vector3(2.0 * RADIUS + 0.24, FELT_TOP + 0.1, RADIUS + 0.25), Vector3(0.0, (FELT_TOP + 0.1) * 0.5, CENTER_Z + (RADIUS + 0.15) * 0.5))

	func _nodes(h: int) -> Array[Card]:
		return player_nodes if h == 0 else dealer_nodes

	func _slot(h: int, i: int) -> Vector3:
		var n: int = maxi(_nodes(h).size(), 1)
		var stride: float = minf(HAND_STEP, 1.4 / float(n))
		return Vector3(HAND_X0 + stride * float(i), CARD_Y + 0.0015 * float(i), PLAYER_Z if h == 0 else DEALER_Z)

	func _card(h: int, i: int) -> Card:
		var nodes := _nodes(h)
		while nodes.size() <= i:
			var c := Card.new(CARD)
			c.visible = false
			add_child(c)
			nodes.append(c)
		return nodes[i]

	func _set_value(c: Card, h: int, i: int, v: int) -> void:
		var pick: int = hash(Vector3i(_salt, h, i))
		var suit: String = TableProps.suit_for(v, pick)
		c.set_card(v, TableProps.blackjack_rank(v, pick) + suit, TableProps.is_red_suit(suit))

	func _clear_hand() -> void:
		for c: Card in player_nodes + dealer_nodes:
			c.queue_free()
		player_nodes.clear()
		dealer_nodes.clear()
		_pvals.clear()
		_dvals.clear()
		_hole_down = false
		_hand_over = false
		_salt += 1
		for l: Label3D in totals:
			l.text = ""

	func _event(kind: StringName, h: int, i: int, v: int) -> void:
		var c := _card(h, i)
		if v > 0:
			_set_value(c, h, i, v)
		_events.append({"kind": kind, "h": h, "i": i})

	func _continues(p: Array[int], d: Array[int]) -> bool:
		if _hand_over or _pvals.is_empty() or _pvals.size() > p.size():
			return false
		for i in _pvals.size():
			if _pvals[i] != p[i]:
				return false
		return d.is_empty() or (not _dvals.is_empty() and _dvals[0] == d[0])

	## Opening deal: player, dealer up card, player, dealer hole card (face down).
	func _deal_opening(p: Array[int], d: Array[int]) -> void:
		if p.size() > 0:
			_event(&"deal_up", 0, 0, p[0])
		if d.size() > 0:
			_event(&"deal_up", 1, 0, d[0])
		if p.size() > 1:
			_event(&"deal_up", 0, 1, p[1])
		_event(&"deal_down", 1, 1, d[1] if d.size() > 1 else 0)
		_hole_down = true
		for i in range(2, p.size()):
			_event(&"deal_up", 0, i, p[i])

	func show_hand(state: Dictionary) -> void:
		finish_hand()
		var p: Array[int] = TableProps.ints(state.get("player_cards", []))
		var d: Array[int] = TableProps.ints(state.get("dealer_cards", []))
		_events.clear()
		if _continues(p, d):
			for i in range(_pvals.size(), p.size()):
				_event(&"deal_up", 0, i, p[i])
		else:
			_clear_hand()
			_deal_opening(p, d)
		_pvals = p
		if not d.is_empty():
			_dvals.assign([d[0]])
		_time_events()
		if _events.is_empty():
			return
		_run_hand(Tuning.TABLE_DEAL_SECONDS * float(_events.size()), _apply)

	func prepare(result: Dictionary, _seconds: float) -> void:
		finish_hand()
		var dd := TableProps.detail_of(result)
		var p: Array[int] = TableProps.ints(dd.get("player_cards", []))
		var d: Array[int] = TableProps.ints(dd.get("dealer_cards", []))
		_events.clear()
		if _continues(p, d):
			for i in range(_pvals.size(), p.size()):
				_event(&"deal_up", 0, i, p[i])
		else:
			_clear_hand()
			_deal_opening(p, d)
		if d.size() > 1:
			if _hole_down and dealer_nodes.size() > 1:
				_set_value(dealer_nodes[1], 1, 1, d[1])
				_events.append({"kind": &"flip", "h": 1, "i": 1})
			elif dealer_nodes.size() < 2:
				_event(&"deal_up", 1, 1, d[1])
		for j in range(2, d.size()):
			_event(&"deal_up", 1, j, d[j])
		_pvals = p
		_dvals = d
		_hole_down = false
		_hand_over = true
		_time_events()

	func _time_events() -> void:
		var n: int = _events.size()
		for k in n:
			_events[k]["t0"] = float(k) / float(n)
			_events[k]["t1"] = float(k + 1) / float(n)

	func step(t: float) -> void:
		_apply(t)

	func _apply(t: float) -> void:
		for e: Dictionary in _events:
			var nodes := _nodes(int(e["h"]))
			var i: int = int(e["i"])
			if i >= nodes.size() or not is_instance_valid(nodes[i]):
				continue
			var c: Card = nodes[i]
			var t0: float = e["t0"]
			var t1: float = e["t1"]
			var u: float = clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
			match e["kind"]:
				&"deal_up", &"deal_down":
					c.visible = u > 0.0
					var k: float = TableProps.ease_out(u, 2.0)
					c.position = SHOE.lerp(_slot(int(e["h"]), i), k) + Vector3(0.0, 0.1 * sin(u * PI), 0.0)
					c.rotation = Vector3(0.0, 0.8 * (1.0 - k), 0.0)
					c.scale = Vector3.ONE
					c.set_face_up(e["kind"] == &"deal_up")
				&"flip":
					if u > 0.0:
						c.set_face_up(u >= 0.5)
						c.scale.x = maxf(0.02, absf(1.0 - 2.0 * u))
		_update_totals()

	func _update_totals() -> void:
		for h in 2:
			var vals: Array[int] = []
			for c: Card in _nodes(h):
				if is_instance_valid(c) and c.visible and c.face_up:
					vals.append(c.value)
			totals[h].text = "" if vals.is_empty() else str(BlackjackRound.hand_total(vals))

	func caption(result: Dictionary) -> String:
		var d := TableProps.detail_of(result)
		if not d.has("player_total"):
			return ""
		var p: int = int(d["player_total"])
		var dt: int = int(d.get("dealer_total", 0))
		if bool(d.get("player_bust", false)):
			return "BUST %d" % p
		if bool(d.get("dealer_bust", false)):
			return "DEALER BUST"
		return "%d vs %d" % [p, dt]

	func shown() -> Dictionary:
		var out := {}
		for h in 2:
			var texts: Array[String] = []
			var up := 0
			for c: Card in _nodes(h):
				if not is_instance_valid(c) or not c.visible:
					continue
				texts.append(c.text if c.face_up else "??")
				if c.face_up:
					up += 1
			out["player" if h == 0 else "dealer"] = texts
			out["player_up" if h == 0 else "dealer_up"] = up
		out["player_total"] = totals[0].text
		out["dealer_total"] = totals[1].text
		return out
