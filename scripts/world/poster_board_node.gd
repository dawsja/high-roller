class_name PosterBoardNode
extends Node3D
## A cork board of wanted posters, hung on a wall: origin on the floor at the
## wall face, posters on the +Z side. show_posters() redraws it from
## WantedPoster.to_dict()-style dicts: each poster is a little paper doll of
## the look (one color swatch per outfit slot, OutfitCatalog.piece_color),
## defaced slots scribbled over, and its own Interactable (kind &"poster",
## data.poster_id; hold to tear it down, press to draw on it).
## Purely visual: tearing and defacing go through the sim.
##
## One row only: players pick the nearest interactable by floor distance, so
## posters stacked above each other could not be told apart.

const MAX_SHOWN := 4
const BOARD_SIZE := Vector2(2.0, 0.82)
const BOARD_CENTER_Y := 1.5
## Paper size before POSTER_SCALE (SLOT_RECTS are in this unscaled space).
const POSTER_SIZE := Vector2(0.56, 0.72)
const POSTER_SCALE := 0.78
const POSTER_GAP := 0.04
const INTERACT_RADIUS := 0.3

const CORK := Color("9c6b3f")
const FRAME := Color("3b2a1c")
const PAPER := Color("f1e7cf")
const INK := Color("1d1a17")
const WANTED_RED := Color("b3261e")
const FACE := Color("e3c3a0")

## Swatch rectangles on the paper per HR.OutfitSlot: Rect2(center, size) in
## poster space (x right, y up, origin at the paper center).
const SLOT_RECTS := {
	HR.OutfitSlot.HAT: Rect2(Vector2(0.0, 0.19), Vector2(0.24, 0.08)),
	HR.OutfitSlot.GLASSES: Rect2(Vector2(0.0, 0.085), Vector2(0.17, 0.045)),
	HR.OutfitSlot.TOP: Rect2(Vector2(0.0, -0.065), Vector2(0.26, 0.17)),
	HR.OutfitSlot.BOTTOM: Rect2(Vector2(0.0, -0.225), Vector2(0.2, 0.13)),
	HR.OutfitSlot.ACCESSORY: Rect2(Vector2(0.19, -0.05), Vector2(0.08, 0.08)),
}

## &"entrance", &"cashier" or &"security_desk".
var board_id: StringName = &""
## Interactables of the posters on show, in display order.
var interactables: Array[Interactable] = []
## Poster ids on show, in display order (newest first).
var poster_ids: Array[int] = []

var _posters_root: Node3D


func _init(p_board_id: StringName = &"") -> void:
	board_id = p_board_id
	name = "PosterBoard_%s" % String(p_board_id)
	_build_board()


## Redraws the board. `posters` holds WantedPoster.to_dict()-style dicts (as
## FloorSim.posters_here()); the newest MAX_SHOWN are shown.
func show_posters(posters: Array) -> void:
	_clear()
	var parsed: Array[WantedPoster] = []
	for p: Variant in posters:
		if p is Dictionary:
			parsed.append(WantedPoster.from_dict(p))
		elif p is WantedPoster:
			parsed.append(p)
	parsed.sort_custom(func(a: WantedPoster, b: WantedPoster) -> bool: return a.id > b.id)
	for i in mini(parsed.size(), MAX_SHOWN):
		_add_poster(parsed[i], i)


## The interactable of a poster on show, or null.
func interactable_for(poster_id: int) -> Interactable:
	var i: int = poster_ids.find(poster_id)
	return interactables[i] if i >= 0 else null


## Center of display slot `index` (0 = left) in board space.
static func slot_position(index: int) -> Vector3:
	var pitch: float = POSTER_SIZE.x * POSTER_SCALE + POSTER_GAP
	return Vector3((float(index) - float(MAX_SHOWN - 1) * 0.5) * pitch, BOARD_CENTER_Y, 0.075)


func _build_board() -> void:
	var frame := Primitives.box(Vector3(BOARD_SIZE.x + 0.12, BOARD_SIZE.y + 0.12, 0.05), FRAME)
	frame.position = Vector3(0.0, BOARD_CENTER_Y, 0.025)
	add_child(frame)
	var cork := Primitives.box(Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.02), CORK)
	cork.position = Vector3(0.0, BOARD_CENTER_Y, 0.055)
	add_child(cork)
	var header := Primitives.label("MOST WANTED", 0.0045, WANTED_RED, false)
	header.font_size = 64
	header.outline_modulate = PAPER
	header.position = Vector3(0.0, BOARD_CENTER_Y + BOARD_SIZE.y * 0.5 + 0.16, 0.06)
	add_child(header)
	_posters_root = Node3D.new()
	_posters_root.name = "Posters"
	add_child(_posters_root)


func _clear() -> void:
	for child: Node in _posters_root.get_children():
		_posters_root.remove_child(child)
		child.queue_free()
	interactables.clear()
	poster_ids.clear()


func _add_poster(poster: WantedPoster, index: int) -> void:
	var slot_root := Node3D.new()
	slot_root.name = "Slot_%d" % index
	slot_root.position = slot_position(index)
	_posters_root.add_child(slot_root)
	var root := Node3D.new()
	root.name = "Poster_%d" % poster.id
	root.scale = Vector3.ONE * POSTER_SCALE
	# Slight tilt so the board looks pinned up by hand.
	root.rotation.z = deg_to_rad(float((poster.id * 37) % 7) - 3.0)
	slot_root.add_child(root)

	var paper := Primitives.box(Vector3(POSTER_SIZE.x, POSTER_SIZE.y, 0.01), PAPER)
	root.add_child(paper)
	var pin := Primitives.sphere(0.018, WANTED_RED, 6)
	pin.position = Vector3(0.0, POSTER_SIZE.y * 0.5 - 0.018, 0.012)
	root.add_child(pin)
	var title := Primitives.label("WANTED", 0.0024, WANTED_RED, false)
	title.outline_size = 0
	title.position = Vector3(0.0, 0.275, 0.008)
	root.add_child(title)
	var caption := Primitives.label("No. %d" % poster.id, 0.0022, INK, false)
	caption.outline_size = 0
	caption.position = Vector3(0.0, -0.32, 0.008)
	root.add_child(caption)

	var face := Primitives.box(Vector3(0.13, 0.14, 0.006), FACE)
	face.position = Vector3(0.0, 0.085, 0.008)
	root.add_child(face)
	for slot: int in OutfitCatalog.all_slots():
		var r: Rect2 = SLOT_RECTS[slot]
		var piece: StringName = poster.outfit.get_piece(slot)
		if not OutfitCatalog.is_none(piece):
			var swatch := Primitives.box(Vector3(r.size.x, r.size.y, 0.006), OutfitCatalog.piece_color(piece))
			swatch.name = "Swatch_%s" % OutfitCatalog.slot_key(slot)
			swatch.position = Vector3(r.position.x, r.position.y, 0.012)
			root.add_child(swatch)
		if poster.is_defaced(slot):
			_scribble(root, r, slot, poster.id * 7 + slot)

	var it := Interactable.create(&"poster", "Draw on poster (hold: tear down)", INTERACT_RADIUS,
		{"poster_id": poster.id, "board_id": board_id}, Tuning.POSTER_TEAR_SECONDS)
	it.position = Vector3(0.0, 0.0, 0.25)
	slot_root.add_child(it)
	interactables.append(it)
	poster_ids.append(poster.id)


## Marker zig-zags over a slot's swatch (and a bit past it).
func _scribble(root: Node3D, r: Rect2, slot: int, salt: int) -> void:
	var w: float = maxf(r.size.x, 0.12) * 1.25
	var h: float = maxf(r.size.y, 0.07) * 1.1
	var strokes := 4
	for i in strokes:
		var t: float = (float(i) + 0.5) / float(strokes)
		var stroke := Primitives.box(Vector3(w, 0.014, 0.004), INK)
		stroke.name = "Scribble_%s_%d" % [OutfitCatalog.slot_key(slot), i]
		stroke.position = Vector3(r.position.x, r.position.y - h * 0.5 + h * t, 0.018 + 0.001 * i)
		var tilt: float = 18.0 + float((salt * 13 + i * 29) % 17)
		stroke.rotation.z = deg_to_rad(tilt if i % 2 == 0 else -tilt)
		root.add_child(stroke)
