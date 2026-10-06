class_name ChipStack3D
extends Node3D
## A pile of poker chips showing an amount: broken into denominations
## (largest first), one column per denomination (more when tall), each chip
## colored by its value with white edge spots. Drawn with one MultiMesh per
## denomination and part, so a stack is a handful of draw calls.
## Origin at the table surface under the first column.

## [value, body color, spot color], largest first.
const DENOMINATIONS: Array = [
	[10000000, Color("b6ff3b"), Color("1c1033")],
	[1000000, Color("ffc23d"), Color("7a2bd6")],
	[100000, Color("3ef0ff"), Color("ffffff")],
	[25000, Color("ff3fd2"), Color("ffffff")],
	[5000, Color("ff8a3d"), Color("ffffff")],
	[1000, Color("ffd23f"), Color("2a1640")],
	[500, Color("8e44ff"), Color("ffffff")],
	[100, Color("2a2633"), Color("ffffff")],
	[25, Color("16a05a"), Color("ffffff")],
	[5, Color("e0283c"), Color("ffffff")],
	[1, Color("f4f1ea"), Color("2e86de")],
]
const SPOTS := 6

var amount: int = 0
var chip_radius: float = 0.032
var chip_height: float = 0.009
## At most this many chips are drawn (big amounts lean on big chips anyway).
var max_chips: int = 30
var per_column: int = 10

static var _spot_meshes: Dictionary = {}
var _parts: Node3D
var _count: int = 0
var _columns: int = 0
var _pop_tween: Tween


func setup(p_amount: int = 0, p_chip_radius: float = 0.032, p_chip_height: float = 0.009, p_max_chips: int = 30) -> ChipStack3D:
	chip_radius = maxf(p_chip_radius, 0.005)
	chip_height = maxf(p_chip_height, 0.002)
	max_chips = maxi(1, p_max_chips)
	if name == "":
		name = "Chips"
	amount = -1
	set_amount(p_amount)
	return self


## [[value, count], ...] largest first: the greedy chip breakdown of `value`.
static func breakdown(value: int) -> Array:
	var out: Array = []
	var left := maxi(0, value)
	for d: Array in DENOMINATIONS:
		var v: int = d[0]
		if left >= v:
			var n := left / v
			out.append([v, n])
			left -= n * v
	return out


## Body color of the chip worth `value` (the largest denomination not above it).
static func color_for(value: int) -> Color:
	for d: Array in DENOMINATIONS:
		if value >= int(d[0]):
			return d[1]
	return (DENOMINATIONS.back() as Array)[1]


func set_amount(value: int, pop: bool = false) -> void:
	value = maxi(0, value)
	if value == amount:
		return
	amount = value
	_rebuild()
	if pop and _count > 0 and is_inside_tree():
		if _pop_tween != null and _pop_tween.is_valid():
			_pop_tween.kill()
		_parts.scale = Vector3(1.12, 0.8, 1.12)
		_pop_tween = create_tween()
		_pop_tween.tween_property(_parts, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Chips drawn right now.
func chip_count() -> int:
	return _count


func column_count() -> int:
	return _columns


## Height of the tallest column (m).
func top_height() -> float:
	return float(mini(_count, per_column)) * chip_height if _count > 0 else 0.0


func _rebuild() -> void:
	if _parts != null:
		remove_child(_parts)
		_parts.queue_free()
	_parts = Node3D.new()
	_parts.name = "Parts"
	add_child(_parts)
	_count = 0
	_columns = 0
	var plan := _display_plan(breakdown(amount))
	if plan.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(amount)
	var body_mesh := MeshFactory.rounded_cylinder(chip_radius, chip_height * 0.96, chip_height * 0.3, 20, 2)
	var spot_mesh := _spot_mesh(chip_radius, chip_height)
	var col := 0
	for entry: Array in plan:
		var value: int = entry[0]
		var n: int = entry[1]
		var colors := _colors_of(value)
		var xforms: Array[Transform3D] = []
		var placed := 0
		while placed < n:
			var in_col := mini(per_column, n - placed)
			var base := _column_offset(col)
			for k in in_col:
				var jitter := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * chip_radius * 0.07
				var yaw := rng.randf() * TAU
				xforms.append(Transform3D(Basis(Vector3.UP, yaw), base + jitter + Vector3(0.0, chip_height * (float(k) + 0.5), 0.0)))
			placed += in_col
			col += 1
		_parts.add_child(_multi(body_mesh, ArtKit.toon_material(colors[0], 0.0, false, true, 0.45), xforms, "Body_%d" % value))
		_parts.add_child(_multi(spot_mesh, ArtKit.toon_material(colors[1], 0.0, false, false), xforms, "Spots_%d" % value))
		_count += n
	_columns = col


## Caps the breakdown at max_chips, keeping the big chips.
func _display_plan(parts: Array) -> Array:
	var out: Array = []
	var budget := max_chips
	for p: Array in parts:
		if budget <= 0:
			break
		var n := mini(int(p[1]), budget)
		out.append([p[0], n])
		budget -= n
	return out


## Columns sit in rings around the first one.
func _column_offset(index: int) -> Vector3:
	if index == 0:
		return Vector3.ZERO
	var ring := 1
	var first := 1
	while index >= first + ring * 6:
		first += ring * 6
		ring += 1
	var slot := index - first
	var count := ring * 6
	var a := TAU * float(slot) / float(count) + 0.35 * float(ring)
	var r := chip_radius * 2.15 * float(ring)
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func _colors_of(value: int) -> Array:
	for d: Array in DENOMINATIONS:
		if int(d[0]) == value:
			return [d[1], d[2]]
	return [Color.WHITE, Color.BLACK]


func _multi(mesh: Mesh, material: Material, xforms: Array[Transform3D], node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	return mmi


## SPOTS small blocks around a chip's rim, as one mesh (cached).
static func _spot_mesh(radius: float, height: float) -> ArrayMesh:
	var key := "%.4f|%.4f" % [radius, height]
	if _spot_meshes.has(key):
		return _spot_meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	box.size = Vector3(radius * 0.36, height * 0.8, radius * 0.16)
	for i in SPOTS:
		var a := TAU * float(i) / float(SPOTS)
		var xf := Transform3D(Basis(Vector3.UP, -a + PI * 0.5), Vector3(cos(a), 0.0, sin(a)) * (radius - radius * 0.05))
		st.append_from(box, 0, xf)
	var mesh := st.commit()
	_spot_meshes[key] = mesh
	return mesh
