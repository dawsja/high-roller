class_name Card3D
extends Node3D
## A chunky playing card lying flat: face up shows the rank in two corners
## and a big suit (♠ ♣ black, ♥ ♦ red; suits are extruded shapes, not font
## glyphs); face down shows a colored back with a gold frame and star.
## flip() turns it over with a little hop; deal_to() flies it along an arc
## to a transform (both tweens, signals at the end).
##
## Card space: lying on the XZ plane, face toward +Y when face up, the top of
## the card toward -Z (reads right way up from +Z). Origin at the card's
## centre on the table surface.

signal flipped(face_up: bool)
signal dealt()

const SUITS: Array[String] = ["♠", "♥", "♦", "♣"]
const FACE_COLOR := Color("fffaf0")
const RED := Color("e0283c")
const BLACK := Color("1c1033")
const BACK_COLOR := Color("7b2cbf")
const TRIM_COLOR := Color("ffc23d")

var rank: String = "A"
var suit: String = "♠"
var face_up: bool = false
var size: Vector2 = Vector2(0.09, 0.13)
var thickness: float = 0.005
var back_color: Color = BACK_COLOR
## Turns over around the card's long axis.
var body: Node3D
var _face: Node3D
var _corner_top: Label3D
var _corner_bottom: Label3D
var _suit_meshes: Array[MeshInstance3D] = []
var _flip_tween: Tween
var _deal_tween: Tween

static var _suit_polys: Dictionary = {}


func setup(p_rank: String = "A", p_suit: String = "♠", p_face_up: bool = false,
		p_size: Vector2 = Vector2(0.09, 0.13), p_back_color: Color = BACK_COLOR) -> Card3D:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_suit_meshes.clear()
	size = p_size.max(Vector2(0.02, 0.03))
	thickness = clampf(size.x * 0.055, 0.003, 0.008)
	back_color = p_back_color
	if name == "":
		name = "Card"
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var slab := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(size.x, thickness, size.y), minf(thickness * 0.5, size.x * 0.1), 2), FACE_COLOR)
	slab.name = "Slab"
	slab.position.y = thickness * 0.5
	body.add_child(slab)
	_build_back()
	_face = Node3D.new()
	_face.name = "Face"
	_face.position.y = thickness + 0.0006
	body.add_child(_face)
	_corner_top = DiegeticKit.text_label("", size.x * 0.24, BLACK)
	_corner_top.name = "CornerTop"
	_corner_top.rotation.x = -PI * 0.5
	_corner_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_corner_top.position = Vector3(-size.x * 0.3, 0.0, -size.y * 0.34)
	_face.add_child(_corner_top)
	_corner_bottom = DiegeticKit.text_label("", size.x * 0.24, BLACK)
	_corner_bottom.name = "CornerBottom"
	_corner_bottom.rotation = Vector3(-PI * 0.5, PI, 0.0)
	_corner_bottom.position = Vector3(size.x * 0.3, 0.0, size.y * 0.34)
	_face.add_child(_corner_bottom)
	set_card(p_rank, p_suit)
	set_face_up(p_face_up)
	return self


## "2".."10", "J", "Q", "K", "A" for a high-low card value (2–14; 1 is an ace too).
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


## A blackjack value (2–11; 10 = tens and faces, 11 = ace) as a rank;
## `pick` chooses which ten-value card a 10 shows.
static func blackjack_rank(value: int, pick: int = 0) -> String:
	if value >= 11:
		return "A"
	if value == 10:
		return ["10", "J", "Q", "K"][posmod(pick, 4)]
	return str(clampi(value, 2, 9))


## A stable suit for a card value and a salt (same on every peer).
static func suit_for(value: int, salt: int = 0) -> String:
	return SUITS[posmod(hash(Vector2i(value, salt)), SUITS.size())]


static func is_red(p_suit: String) -> bool:
	var s := normalize_suit(p_suit)
	return s == "♥" or s == "♦"


## "♠"/"S"/"spades" -> "♠" (and so on); unknown -> "♠".
static func normalize_suit(p_suit: String) -> String:
	var s := p_suit.strip_edges().to_lower()
	if s in ["♥", "h", "heart", "hearts"]:
		return "♥"
	if s in ["♦", "d", "diamond", "diamonds"]:
		return "♦"
	if s in ["♣", "c", "club", "clubs"]:
		return "♣"
	return "♠"


func set_card(p_rank: String, p_suit: String) -> void:
	rank = p_rank
	suit = normalize_suit(p_suit)
	var ink := RED if is_red(suit) else BLACK
	for l: Label3D in [_corner_top, _corner_bottom]:
		DiegeticKit.fit_label(l, rank, size.x * 0.22, size.x * 0.42)
		l.modulate = ink
	for m: MeshInstance3D in _suit_meshes:
		m.queue_free()
	_suit_meshes.clear()
	var mesh := MeshFactory.extrude(suit_polygon(suit), 0.0012)
	var mat := ArtKit.toon_material(ink, 0.0, false, false)
	var spots: Array = [
		[Vector3(-size.x * 0.3, 0.0, -size.y * 0.2), size.x * 0.1, 0.0],
		[Vector3(size.x * 0.3, 0.0, size.y * 0.2), size.x * 0.1, PI],
		[Vector3(0.0, 0.0, size.y * 0.02), size.x * 0.27, 0.0],
	]
	for s: Array in spots:
		var mi := ArtKit.mesh_instance(mesh, mat)
		mi.name = "Suit"
		mi.position = s[0]
		mi.rotation = Vector3(-PI * 0.5, float(s[2]), 0.0)
		mi.scale = Vector3.ONE * float(s[1])
		_face.add_child(mi)
		_suit_meshes.append(mi)


func set_face_up(up: bool) -> void:
	_kill(_flip_tween)
	face_up = up
	if body != null:
		body.rotation = Vector3(0.0, 0.0, 0.0 if up else PI)
		body.position = Vector3(0.0, 0.0 if up else thickness, 0.0)


## Turns the card over in `seconds` with a hop (instant outside the tree).
func flip(up: bool, seconds: float = 0.3) -> void:
	_kill(_flip_tween)
	if body == null:
		return
	if not is_inside_tree() or seconds <= 0.0:
		set_face_up(up)
		flipped.emit(up)
		return
	face_up = up
	var from := body.rotation.z
	var to := 0.0 if up else PI
	if is_equal_approx(from, to):
		from = PI - to
	_flip_tween = create_tween()
	_flip_tween.tween_method(_flip_step.bind(from, to), 0.0, 1.0, seconds)
	_flip_tween.tween_callback(func() -> void: flipped.emit(up))


## Flies the card to `target` (global) along an arc in `seconds`, ending
## exactly there. Instant outside the tree.
func deal_to(target: Transform3D, seconds: float = 0.45, arc_height: float = 0.12) -> void:
	_kill(_deal_tween)
	if not is_inside_tree() or seconds <= 0.0:
		if is_inside_tree():
			global_transform = target
		else:
			transform = target
		dealt.emit()
		return
	var start := global_transform
	_deal_tween = create_tween()
	_deal_tween.tween_method(_deal_step.bind(start, target, arc_height), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_deal_tween.tween_callback(func() -> void: dealt.emit())


func is_animating() -> bool:
	return (_flip_tween != null and _flip_tween.is_valid() and _flip_tween.is_running()) \
			or (_deal_tween != null and _deal_tween.is_valid() and _deal_tween.is_running())


## Snaps any flip / deal to its end (signals fire).
func finish() -> void:
	for tw: Tween in [_deal_tween, _flip_tween]:
		if tw != null and tw.is_valid():
			tw.custom_step(1000.0)
			tw.kill()


## True when the face side points up in the world.
func is_showing_face() -> bool:
	if body == null:
		return false
	var up := (body.global_basis if body.is_inside_tree() else transform.basis * body.basis).y
	return up.y > 0.0


## The outline of a suit as a 2D polygon about 2 units tall, centred, point
## up for ♠ ♥ ♦ (♥ lobes up) — cached.
static func suit_polygon(p_suit: String) -> PackedVector2Array:
	var s := normalize_suit(p_suit)
	if _suit_polys.has(s):
		return _suit_polys[s]
	var poly := PackedVector2Array()
	match s:
		"♦":
			poly = PackedVector2Array([Vector2(0, 1), Vector2(0.72, 0), Vector2(0, -1), Vector2(-0.72, 0)])
		"♥":
			poly = _union([_circle(Vector2(-0.46, 0.38), 0.5), _circle(Vector2(0.46, 0.38), 0.5),
					PackedVector2Array([Vector2(-0.93, 0.24), Vector2(0.93, 0.24), Vector2(0, -0.98)])])
		"♣":
			poly = _union([_circle(Vector2(0, 0.5), 0.4), _circle(Vector2(-0.45, -0.08), 0.4), _circle(Vector2(0.45, -0.08), 0.4),
					_circle(Vector2(0, 0.1), 0.25),
					PackedVector2Array([Vector2(-0.1, 0.0), Vector2(0.1, 0.0), Vector2(0.32, -0.98), Vector2(-0.32, -0.98)])])
		_:
			poly = _union([_circle(Vector2(-0.44, -0.12), 0.46), _circle(Vector2(0.44, -0.12), 0.46),
					PackedVector2Array([Vector2(-0.88, 0.0), Vector2(0, 1.0), Vector2(0.88, 0.0)]),
					PackedVector2Array([Vector2(-0.1, -0.2), Vector2(0.1, -0.2), Vector2(0.32, -0.98), Vector2(-0.32, -0.98)])])
	_suit_polys[s] = poly
	return poly


static func _circle(center: Vector2, radius: float, segments: int = 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


static func _union(polys: Array) -> PackedVector2Array:
	var acc: PackedVector2Array = polys[0]
	for i in range(1, polys.size()):
		var merged := Geometry2D.merge_polygons(acc, polys[i])
		var best := PackedVector2Array()
		var best_area := -1.0
		for m: PackedVector2Array in merged:
			if Geometry2D.is_polygon_clockwise(m) and merged.size() > 1:
				continue  # a hole
			var area := absf(_area(m))
			if area > best_area:
				best_area = area
				best = m
		acc = best
	return acc


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func _build_back() -> void:
	var back := Node3D.new()
	back.name = "Back"
	back.rotation.z = PI
	body.add_child(back)
	var plate := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(size.x * 0.84, 0.0012, size.y * 0.88), size.x * 0.04, 2), back_color, 0.0, false)
	plate.name = "Plate"
	plate.position.y = 0.0006
	back.add_child(plate)
	var hw := size.x * 0.34
	var hh := size.y * 0.38
	var frame := ArtKit.mesh_instance(MeshFactory.stroke(PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)]), size.x * 0.03, 0.001),
			ArtKit.toon_material(TRIM_COLOR, 0.2, false, false))
	frame.name = "Frame"
	frame.rotation.x = -PI * 0.5
	frame.position.y = 0.0016
	back.add_child(frame)
	var star := ArtKit.mesh_instance(MeshFactory.star(size.x * 0.2, size.x * 0.09, 5, 0.001), ArtKit.toon_material(TRIM_COLOR, 0.3, false, false))
	star.name = "Star"
	star.rotation.x = -PI * 0.5
	star.position.y = 0.0016
	back.add_child(star)


func _flip_step(t: float, from: float, to: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	body.rotation.z = lerpf(from, to, k)
	var lift := sin(t * PI) * size.x * 0.6
	var settle := lerpf(thickness if from > 0.5 else 0.0, thickness if to > 0.5 else 0.0, k)
	body.position.y = lift + settle


func _deal_step(t: float, start: Transform3D, target: Transform3D, arc_height: float) -> void:
	var p := start.origin.lerp(target.origin, t) + Vector3.UP * sin(t * PI) * arc_height
	var q := start.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), t)
	var s := start.basis.get_scale().lerp(target.basis.get_scale(), t)
	global_transform = Transform3D(Basis(q).scaled(s), p)


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()
