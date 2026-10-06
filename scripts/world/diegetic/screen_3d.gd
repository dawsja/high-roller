class_name Screen3D
extends Node3D
## A machine's monitor: a rounded dark bezel, glowing glass (ArtKit screen
## material) and up to N lines of bright text, each with its own color and
## size, stacked and centred. Text shrinks to fit the glass width.
## flash() pulses the glass (wins, refusals).
##
## Screen space: the glass faces +Z, centred on the origin; the bezel sits
## behind it (-Z).

## Line spacing as a multiple of a line's cap height.
const LINE_SPACING := 1.45
const BEZEL_DEPTH := 0.03

var size: Vector2 = Vector2(0.4, 0.25)
var line_count: int = 3
var glow_color: Color = Color("8c4dff")
## Text brightness multiplier (> 1 makes text bloom a little).
var text_energy: float = 1.15
var bezel: MeshInstance3D
var glass: MeshInstance3D
var lines: Array[Label3D] = []

var _texts: PackedStringArray = PackedStringArray()
var _colors: Array[Color] = []
var _heights: PackedFloat32Array = PackedFloat32Array()
var _flash: MeshInstance3D
var _flash_mat: StandardMaterial3D
var _flash_tween: Tween


## `bezel_border` is the frame width around the glass (m).
func setup(p_size: Vector2 = Vector2(0.4, 0.25), p_line_count: int = 3, p_glow: Color = Color("8c4dff"),
		bezel_color: Color = DiegeticKit.BEZEL, bezel_border: float = 0.022) -> Screen3D:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	lines.clear()
	size = p_size.max(Vector2(0.02, 0.02))
	line_count = maxi(1, p_line_count)
	glow_color = p_glow
	if name == "":
		name = "Screen"
	var outer := Vector3(size.x + bezel_border * 2.0, size.y + bezel_border * 2.0, BEZEL_DEPTH)
	bezel = Primitives.mesh_instance(MeshFactory.rounded_box(outer, minf(bezel_border * 0.9, BEZEL_DEPTH * 0.45), 3), bezel_color)
	bezel.name = "Bezel"
	bezel.position.z = -BEZEL_DEPTH * 0.5 + 0.002
	add_child(bezel)
	glass = ArtKit.mesh_instance(MeshFactory.quad(size), ArtKit.screen_material(Color("0b0614"), glow_color, 1.0))
	glass.name = "Glass"
	glass.position.z = 0.0035
	add_child(glass)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	_flash_mat.render_priority = -1
	_flash = MeshInstance3D.new()
	_flash.name = "Flash"
	_flash.mesh = MeshFactory.quad(size)
	_flash.material_override = _flash_mat
	_flash.position.z = 0.0045
	_flash.visible = false
	add_child(_flash)
	_texts.resize(line_count)
	_colors.clear()
	_heights.resize(line_count)
	var default_h := size.y / (float(line_count) * LINE_SPACING * 1.25)
	for i in line_count:
		_texts[i] = ""
		_colors.append(DiegeticKit.TEXT_WHITE)
		_heights[i] = default_h
		var l := DiegeticKit.text_label("", default_h, DiegeticKit.TEXT_WHITE, 10)
		l.name = "Line%d" % i
		l.visibility_range_end = 40.0
		l.position.z = 0.006
		add_child(l)
		lines.append(l)
	_layout()
	return self


## Replaces every line. Entries are a String or {text, color?, size?} (size
## = cap height in metres); missing entries clear their line.
func set_lines(entries: Array) -> void:
	for i in line_count:
		if i < entries.size():
			var e: Variant = entries[i]
			if e is Dictionary:
				var d := e as Dictionary
				_texts[i] = str(d.get("text", ""))
				if d.get("color") is Color:
					_colors[i] = d["color"]
				if d.has("size"):
					_heights[i] = maxf(0.0, float(d["size"]))
			else:
				_texts[i] = str(e)
		else:
			_texts[i] = ""
	_layout()


## Sets one line; a color with alpha 0 or a negative size keeps the current one.
func set_line(index: int, text: String, color: Color = Color(0, 0, 0, 0), height: float = -1.0) -> void:
	if index < 0 or index >= line_count:
		return
	_texts[index] = text
	if color.a > 0.0:
		_colors[index] = color
	if height >= 0.0:
		_heights[index] = height
	_layout()


func get_line(index: int) -> String:
	return _texts[index] if index >= 0 and index < line_count else ""


func get_line_color(index: int) -> Color:
	return _colors[index] if index >= 0 and index < line_count else Color()


func get_lines() -> PackedStringArray:
	return _texts.duplicate()


## Pulses the glass with `color` for `seconds`.
func flash(color: Color = Color.WHITE, seconds: float = 0.35, strength: float = 0.55) -> void:
	if _flash == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.visible = true
	_flash_mat.albedo_color = Color(color, strength)
	if not is_inside_tree():
		_flash.visible = false
		return
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, maxf(seconds, 0.02)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flash_tween.tween_callback(_flash.hide)


func is_flashing() -> bool:
	return _flash != null and _flash.visible


func set_glow_color(color: Color) -> void:
	glow_color = color
	if glass != null:
		glass.material_override = ArtKit.screen_material(Color("0b0614"), color, 1.0)


func _layout() -> void:
	var total := 0.0
	for i in line_count:
		total += _heights[i] * LINE_SPACING
	var y := total * 0.5
	for i in line_count:
		var l := lines[i]
		var h := _heights[i]
		var c := _colors[i]
		l.visible = h > 0.0 and _texts[i] != ""
		DiegeticKit.fit_label(l, _texts[i], maxf(h, 0.001), size.x * 0.92)
		l.modulate = Color(c.r * text_energy, c.g * text_energy, c.b * text_energy, c.a)
		l.outline_size = maxi(6, int(round(10.0 * minf(1.0, h / 0.03))))
		l.position = Vector3(0.0, y - h * LINE_SPACING * 0.5, 0.006)
		y -= h * LINE_SPACING
