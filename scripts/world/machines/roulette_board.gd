class_name RouletteBoard
extends Node3D
## The roulette betting felt (ref: roulette board): a green 0 down the left,
## 1-36 in twelve columns of three (1 nearest the player, 3 farthest, as on a
## real layout) in red and black, and a RED / BLACK row along the near edge.
## Every cell is a Pressable (physics layer 5), so the first-person ray
## hovers and presses it; a hovered cell lifts and gets a yellow neon frame.
## One ChipStack3D shows the player's single bet (a number or a color) and
## slides between cells; the winning cell gets a pulsing gold frame and a
## marker puck. Purely a view + input device: RouletteMachine turns
## cell_pressed into requests.
##
## Board space: lies on XZ at y = 0 (the felt), centred on the origin, the
## player at +Z. Cell ids: &"n0".."n36", &"red", &"black".

signal cell_pressed(id: StringName, user_pid: int)
signal cell_hovered(id: StringName, hovered: bool)

## One betting cell: a press target over its tile in the board's merged
## tile mesh, with its label (which pops on hover).
class Cell extends Pressable:
	var board: RouletteBoard
	var label: Label3D
	var size: Vector2 = Vector2.ONE
	var base_color: Color = Color.WHITE
	var _tween: Tween

	func _on_press(user_pid: int) -> void:
		if board != null:
			board._cell_pressed(self, user_pid)

	func _on_hover(value: bool) -> void:
		if board != null:
			board._cell_hover(self, value)
		if label == null:
			return
		if _tween != null and _tween.is_valid():
			_tween.kill()
		var s := Vector3.ONE * (1.3 if value else 1.0)
		if not is_inside_tree():
			label.scale = s
			return
		_tween = create_tween()
		_tween.tween_property(label, "scale", s, 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


const CELL := Vector2(0.1, 0.115)
const ZERO_WIDTH := 0.1
const OUTSIDE_DEPTH := 0.13
const GAP := 0.009
const TILE_HEIGHT := 0.014
const COLUMNS := 12
const WIDTH := ZERO_WIDTH + CELL.x * COLUMNS
const DEPTH := CELL.y * 3.0 + OUTSIDE_DEPTH
const RED := Color("e0283c")
const BLACK := Color("2a2236")
const GREEN := Color("19b25e")
const LINE_COLOR := Color("fff1cf")
const HOVER_COLOR := Color("ffc300")
const PICK_COLOR := Color("3ef0ff")
const WIN_COLOR := Color("ffd23f")
const CHIP_SLIDE_SECONDS := 0.22

## id -> Cell
var cells: Dictionary = {}
## The cell the chip sits on (&"" = no bet).
var chip_cell: StringName = &""
var chips: ChipStack3D
## The cell lit as the last winner (&"" = none).
var winner: StringName = &""
## Every cell's tile in one vertex-colored mesh (one draw, one instance).
var tiles: MeshInstance3D
var hover_frame: MeshInstance3D
var pick_frame: MeshInstance3D
var win_frame: MeshInstance3D
var marker: Node3D
var _chip_tween: Tween
var _win_tween: Tween


func setup() -> RouletteBoard:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	cells.clear()
	if name == "":
		name = "RouletteBoard"
	var lines := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(WIDTH + 0.03, 0.01, DEPTH + 0.03), 0.012, 2), LINE_COLOR, 0.0, false)
	lines.name = "Lines"
	lines.position.y = 0.005
	add_child(lines)
	var top := 0.01
	var tile_list: Array = []
	for c in COLUMNS:
		for r in 3:
			var n := 3 * c + 3 - r
			_add_cell(id_for_number(n), str(n), number_color(n), Vector2(CELL.x, CELL.y),
					Vector3(-WIDTH * 0.5 + ZERO_WIDTH + CELL.x * (float(c) + 0.5), top, -DEPTH * 0.5 + CELL.y * (float(r) + 0.5)), 0.05, tile_list)
	_add_cell(&"n0", "0", GREEN, Vector2(ZERO_WIDTH, CELL.y * 3.0),
			Vector3(-WIDTH * 0.5 + ZERO_WIDTH * 0.5, top, -DEPTH * 0.5 + CELL.y * 1.5), 0.06, tile_list)
	var out_z := -DEPTH * 0.5 + CELL.y * 3.0 + OUTSIDE_DEPTH * 0.5
	var half_w := CELL.x * 6.0
	_add_cell(&"red", "RED", RED, Vector2(half_w, OUTSIDE_DEPTH), Vector3(-WIDTH * 0.5 + ZERO_WIDTH + half_w * 0.5, top, out_z), 0.06, tile_list)
	_add_cell(&"black", "BLACK", BLACK, Vector2(half_w, OUTSIDE_DEPTH), Vector3(-WIDTH * 0.5 + ZERO_WIDTH + half_w * 1.5, top, out_z), 0.06, tile_list)
	tiles = ArtKit.mesh_instance(_tiles_mesh(tile_list), _tiles_material(true))
	tiles.name = "Tiles"
	add_child(tiles)
	hover_frame = _frame(Vector2(CELL.x, CELL.y), HOVER_COLOR, 1.8)
	hover_frame.name = "HoverFrame"
	pick_frame = _frame(Vector2(CELL.x, CELL.y), PICK_COLOR, 1.6)
	pick_frame.name = "PickFrame"
	win_frame = _frame(Vector2(CELL.x, CELL.y), WIN_COLOR, 2.4)
	win_frame.name = "WinFrame"
	marker = Node3D.new()
	marker.name = "Marker"
	var puck := Primitives.rounded_cylinder(0.026, 0.05, Color("fff8ec"), 0.012, 18)
	puck.position.y = 0.025
	marker.add_child(puck)
	var cap := Primitives.rounded_cylinder(0.02, 0.012, WIN_COLOR, 0.005, 18, 0.6)
	cap.position.y = 0.054
	marker.add_child(cap)
	marker.visible = false
	add_child(marker)
	chips = ChipStack3D.new()
	chips.setup(0, 0.036, 0.011, 24)
	chips.name = "Chips"
	chips.visible = false
	add_child(chips)
	return self


## "n17" for a number.
static func id_for_number(n: int) -> StringName:
	return StringName("n%d" % clampi(n, 0, GameResolver.ROULETTE_MAX_NUMBER))


## The cell of a sim choice / result detail ({kind: "number", number|pick} or
## {kind: "color", color|pick}); &"" if it names none.
static func id_for_choice(choice: Dictionary) -> StringName:
	match str(choice.get("kind", "")):
		"number":
			var n: Variant = choice.get("number", choice.get("pick", -1))
			return id_for_number(int(n)) if int(n) >= 0 else &""
		"color":
			return &"black" if str(choice.get("color", choice.get("pick", "red"))) == "black" else &"red"
	return &""


## The place_bet choice for a cell id ({} for an unknown id).
static func choice_for(id: StringName) -> Dictionary:
	var s := String(id)
	if id == &"red" or id == &"black":
		return {"kind": "color", "color": s}
	if s.begins_with("n") and s.substr(1).is_valid_int():
		return {"kind": "number", "number": clampi(s.substr(1).to_int(), 0, GameResolver.ROULETTE_MAX_NUMBER)}
	return {}


## Pocket / cell color of a number.
static func number_color(n: int) -> Color:
	match GameResolver.roulette_color(n):
		"red":
			return RED
		"black":
			return BLACK
	return GREEN


## "17", "RED", "BLACK" for a cell id.
static func cell_text(id: StringName) -> String:
	var c := choice_for(id)
	if c.get("kind", "") == "number":
		return str(int(c["number"]))
	return String(id).to_upper()


func get_cell(id: StringName) -> Cell:
	return cells.get(id, null)


## The cell's top centre (board space).
func cell_center(id: StringName) -> Vector3:
	var c := get_cell(id)
	return c.position if c != null else Vector3.ZERO


func set_cells_enabled(on: bool) -> void:
	for c: Cell in cells.values():
		c.enabled = on
	if tiles != null:
		tiles.material_override = _tiles_material(on)


## Puts the bet chip on `id` showing `amount` (slides there if it sat on
## another cell; pops if it was off the board).
func place_chip(id: StringName, amount: int, animate: bool = true) -> void:
	var c := get_cell(id)
	if c == null:
		clear_chip(false)
		return
	_kill(_chip_tween)
	var target := c.position + Vector3(0.0, TILE_HEIGHT * 0.5, 0.0)
	var was := chip_cell
	chip_cell = id
	_fit_frame(pick_frame, c.size)
	pick_frame.position = c.position + Vector3(0.0, TILE_HEIGHT + 0.006, 0.0)
	pick_frame.visible = true
	chips.set_amount(maxi(amount, 0))
	chips.visible = true
	chips.scale = Vector3.ONE
	if not animate or not is_inside_tree():
		chips.position = target
		return
	_chip_tween = create_tween()
	if was == &"" or was == id:
		chips.position = target + Vector3(0.0, 0.08, 0.0)
		chips.scale = Vector3.ONE * 0.4
		_chip_tween.tween_property(chips, "position", target, 0.16).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		_chip_tween.parallel().tween_property(chips, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		var from := chips.position
		_chip_tween.tween_method(_chip_arc.bind(from, target), 0.0, 1.0, CHIP_SLIDE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_chip_amount(amount: int, pop: bool = false) -> void:
	if chips != null:
		chips.set_amount(maxi(amount, 0), pop)


## Takes the chip off the board (shrinks away when animated).
func clear_chip(animate: bool = true) -> void:
	chip_cell = &""
	if pick_frame != null:
		pick_frame.visible = false
	_kill(_chip_tween)
	if chips == null:
		return
	if not animate or not is_inside_tree() or not chips.visible:
		chips.visible = false
		return
	_chip_tween = create_tween()
	_chip_tween.tween_property(chips, "scale", Vector3.ONE * 0.05, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_chip_tween.tween_callback(chips.hide)


## Slides the chip to `to` (board space) and hides it there: paid out to the
## player or swept by the dealer.
func send_chip(to: Vector3, seconds: float = 0.45) -> void:
	chip_cell = &""
	if pick_frame != null:
		pick_frame.visible = false
	_kill(_chip_tween)
	if chips == null or not chips.visible:
		return
	if not is_inside_tree():
		chips.visible = false
		return
	_chip_tween = create_tween()
	_chip_tween.tween_method(_chip_arc.bind(chips.position, to), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_chip_tween.tween_property(chips, "scale", Vector3.ONE * 0.05, 0.12)
	_chip_tween.tween_callback(chips.hide)


func is_chip_moving() -> bool:
	return _chip_tween != null and _chip_tween.is_valid() and _chip_tween.is_running()


## Lights the winning number's cell (gold pulsing frame + marker puck).
func set_winner(id: StringName) -> void:
	_kill(_win_tween)
	winner = id
	var c := get_cell(id)
	if c == null:
		clear_winner()
		return
	_fit_frame(win_frame, c.size)
	win_frame.position = c.position + Vector3(0.0, TILE_HEIGHT + 0.004, 0.0)
	win_frame.visible = true
	marker.position = c.position + Vector3(0.0, TILE_HEIGHT, -c.size.y * 0.18)
	marker.visible = true
	if is_inside_tree():
		_win_tween = create_tween().set_loops(6)
		_win_tween.tween_method(_win_pulse, 1.0, 0.35, 0.22)
		_win_tween.tween_method(_win_pulse, 0.35, 1.0, 0.22)


func clear_winner() -> void:
	_kill(_win_tween)
	winner = &""
	if win_frame != null:
		win_frame.visible = false
	if marker != null:
		marker.visible = false


func _add_cell(id: StringName, text: String, color: Color, size: Vector2, pos: Vector3, text_height: float, tile_list: Array) -> void:
	var c := Cell.new()
	c.name = "Cell_%s" % String(id)
	c.id = id
	c.board = self
	c.size = size
	c.base_color = color
	c.hint = "[LMB] Bet %s" % (("on " + text) if text.is_valid_int() else text)
	c.position = pos
	tile_list.append([Vector3(size.x - GAP, TILE_HEIGHT, size.y - GAP), pos + Vector3(0.0, TILE_HEIGHT * 0.5, 0.0), color])
	c.label = DiegeticKit.text_label(text, text_height, DiegeticKit.TEXT_WHITE, 10)
	c.label.name = "Label"
	c.label.rotation.x = -PI * 0.5
	c.label.position.y = TILE_HEIGHT + 0.0012
	if text.length() <= 2 and size.y > size.x * 1.5:
		# The tall 0 cell reads sideways, like a real layout.
		c.label.rotation = Vector3(-PI * 0.5, PI * 0.5, 0.0)
	DiegeticKit.fit_label(c.label, text, text_height, minf(size.x, size.y) * 0.8 if text.length() <= 2 else size.x * 0.7)
	c.add_child(c.label)
	c.glow_root = c.label
	c.set_box_shape(Vector3(size.x - GAP * 0.5, TILE_HEIGHT + 0.02, size.y - GAP * 0.5), Vector3(0.0, (TILE_HEIGHT + 0.02) * 0.5, 0.0))
	add_child(c)
	cells[id] = c


## [size, centre, color] tiles as one rounded-box mesh with vertex colors.
static func _tiles_mesh(tile_list: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for t: Array in tile_list:
		var src := MeshFactory.rounded_box(t[0], 0.006, 2).surface_get_arrays(0)
		var base := verts.size()
		var v: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
		var lin: Color = (t[2] as Color).srgb_to_linear()
		for p: Vector3 in v:
			verts.append(p + (t[1] as Vector3))
			colors.append(lin)
		normals.append_array(src[Mesh.ARRAY_NORMAL])
		for i: int in src[Mesh.ARRAY_INDEX]:
			indices.append(base + i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _tiles_material(on: bool) -> Material:
	return ArtKit.toon_material(Color.WHITE if on else Color(0.45, 0.43, 0.5), 0.0, false, false, 0.25, true)


func _frame(size: Vector2, color: Color, energy: float) -> MeshInstance3D:
	var mi := ArtKit.mesh_instance(MeshFactory.stroke(_rect(size), 0.012, 0.006), ArtKit.neon_material(color, energy))
	mi.rotation.x = -PI * 0.5
	mi.visible = false
	mi.set_meta(&"size", size)
	add_child(mi)
	return mi


func _fit_frame(frame: MeshInstance3D, size: Vector2) -> void:
	if frame.get_meta(&"size", Vector2.ZERO) != size:
		frame.mesh = MeshFactory.stroke(_rect(size), 0.012, 0.006)
		frame.set_meta(&"size", size)


static func _rect(size: Vector2) -> PackedVector2Array:
	var hw := size.x * 0.5 - 0.002
	var hd := size.y * 0.5 - 0.002
	return PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)])


func _cell_pressed(c: Cell, user_pid: int) -> void:
	cell_pressed.emit(c.id, user_pid)


func _cell_hover(c: Cell, on: bool) -> void:
	if hover_frame != null:
		if on:
			_fit_frame(hover_frame, c.size)
			hover_frame.position = c.position + Vector3(0.0, TILE_HEIGHT + 0.012, 0.0)
		hover_frame.visible = on
	cell_hovered.emit(c.id, on)


func _chip_arc(t: float, from: Vector3, to: Vector3) -> void:
	chips.position = from.lerp(to, t) + Vector3(0.0, sin(t * PI) * 0.06, 0.0)


func _win_pulse(level: float) -> void:
	if win_frame != null:
		ArtKit.set_neon_level(win_frame, level)


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()
