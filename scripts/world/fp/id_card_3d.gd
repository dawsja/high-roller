class_name IdCard3D
extends Node3D
## A chunky laminated fake ID you hold up in first person (Tab). Front face
## toward +Z, centred on the origin, about 20 x 13 cm. The front has a header
## band in the grade colour, a "photo" built from the outfit's colour
## swatches, NAME / BORN / FROM, a grade stamp, a BANKED / CAP bar, a
## hologram sticker and a FLAGGED or BURNED stamp across it when the ID is
## spoiled; the back has a magnetic stripe. set_id() takes FakeId.to_dict()
## and Outfit.to_dict() style dictionaries. Purely visual.

const WIDTH := 0.2
const HEIGHT := 0.128
const THICKNESS := 0.012
const CORNER := 0.018
const INK := Color("2a1640")
const CAPTION := Color("7a4fb0")
## Printed parts are unshaded and kept under the bloom threshold so the text
## reads in any light.
const FACE := Color("eadcc4")
const PHOTO_BG := Color("3b1d5e")
const PHOTO_SKIN := Color("8fe388")
const BAR_BG := Color("2a1640")
const FLAGGED := Color("ff6a1f")
const BURNED := Color("ff2a3a")
## Header / stamp colour per HR.IdGrade.
const GRADE_COLORS := {0: Color("ff8a3d"), 1: Color("3ef0ff"), 2: Color("ffd23f")}
const DISPLAY_FONT := &"display"
const BODY_FONT := &"body"
const STATUS_NONE := &""
const STATUS_FLAGGED := &"flagged"
const STATUS_BURNED := &"burned"

## The last set_id() input.
var id_data: Dictionary = {}
var outfit_data: Dictionary = {}
## &"", &"flagged" or &"burned".
var status: StringName = STATUS_NONE

var _body: MeshInstance3D
var _header: MeshInstance3D
var _grade_plate: MeshInstance3D
var _bar_fill: MeshInstance3D
var _photo_parts: Dictionary = {}
var _title: Label3D
var _name: Label3D
var _born: Label3D
var _from: Label3D
var _grade: Label3D
var _bar_label: Label3D
var _index_label: Label3D
var _stamp: Label3D
var _bar_ratio := 0.0


func _init() -> void:
	name = "IdCard"
	_build()
	set_id({})


## Shows a FakeId.to_dict() (name, birthday, home_state, grade, cap,
## banked_under, flagged, burned) with the outfit's colours as its photo.
func set_id(id_dict: Dictionary, outfit_dict: Dictionary = {}, skin: Color = PHOTO_SKIN) -> void:
	id_data = id_dict.duplicate()
	outfit_data = outfit_dict.duplicate()
	var grade: int = int(id_dict.get("grade", HR.IdGrade.CHEAP))
	var grade_color: Color = GRADE_COLORS.get(grade, GRADE_COLORS[0])
	_recolor(_body, grade_color.darkened(0.25))
	_recolor(_header, grade_color)
	_recolor(_grade_plate, grade_color)
	_set_text(_name, str(id_dict.get("name", "")) if id_dict.has("name") else "NO ID", 0.11)
	_set_text(_born, str(id_dict.get("birthday", "?")), 0.05)
	_set_text(_from, str(id_dict.get("home_state", "?")), 0.05)
	var grade_def: Dictionary = Tuning.ID_GRADES.get(grade, Tuning.ID_GRADES[HR.IdGrade.CHEAP])
	_set_text(_grade, str(grade_def.get("name", "")).to_upper(), 0.044)
	var cap: int = int(id_dict.get("cap", int(grade_def.get("cap", 0))))
	var banked: int = int(id_dict.get("banked_under", 0))
	_bar_ratio = clampf(float(banked) / float(cap), 0.0, 1.0) if cap > 0 else 0.0
	_set_text(_bar_label, "BANKED %s / CAP %s" % [short_chips(banked), short_chips(cap)], WIDTH - 0.04)
	var fill_color := Color("b6ff3b") if _bar_ratio < 0.6 else (Color("ffd23f") if _bar_ratio < 0.9 else BURNED)
	_recolor(_bar_fill, fill_color, 0.4)
	var bar_w := WIDTH - 0.03
	_bar_fill.scale = Vector3(maxf(0.001, _bar_ratio), 1.0, 1.0)
	_bar_fill.position.x = -bar_w * 0.5 + bar_w * maxf(0.001, _bar_ratio) * 0.5
	if bool(id_dict.get("burned", false)):
		status = STATUS_BURNED
	elif bool(id_dict.get("flagged", false)):
		status = STATUS_FLAGGED
	else:
		status = STATUS_NONE
	_stamp.visible = status != STATUS_NONE
	_stamp.text = "BURNED" if status == STATUS_BURNED else "FLAGGED"
	_stamp.modulate = BURNED if status == STATUS_BURNED else FLAGGED
	_paint_photo(outfit_dict, skin)


## "2/3" in the corner when the player carries several IDs ("" for one).
func set_index(index: int, count: int) -> void:
	_index_label.text = "%d/%d" % [index + 1, count] if count > 1 else ""


## What the card shows, for tests and the HUD: name, born, from, grade, banked, status.
func get_fields() -> Dictionary:
	return {
		"name": _name.text, "born": _born.text, "from": _from.text, "grade": _grade.text,
		"banked": _bar_label.text, "ratio": _bar_ratio, "status": status, "index": _index_label.text,
	}


## 1234 -> "$1.2K", 6000 -> "$6K", 1500000 -> "$1.5M".
static func short_chips(amount: int) -> String:
	var a := absi(amount)
	var text := ""
	if a >= 1000000:
		text = ("%.1fM" % (a / 1000000.0)).replace(".0M", "M")
	elif a >= 1000:
		text = ("%.1fK" % (a / 1000.0)).replace(".0K", "K")
	else:
		text = str(a)
	return ("-$" if amount < 0 else "$") + text


# --- Build ------------------------------------------------------------------------

func _build() -> void:
	var front := THICKNESS * 0.5
	_body = _slab(WIDTH, HEIGHT, THICKNESS, CORNER, GRADE_COLORS[0], Vector3.ZERO, true, 0.003)
	_slab(WIDTH - 0.01, HEIGHT - 0.01, 0.002, CORNER - 0.005, FACE, Vector3(0.0, 0.0, front + 0.001))
	_header = _slab(WIDTH - 0.018, 0.026, 0.002, 0.008, GRADE_COLORS[0], Vector3(0.0, HEIGHT * 0.5 - 0.02, front + 0.0025))
	_title = _label("TOTALLY REAL ID", DISPLAY_FONT, 72, INK, Vector3(-0.004, HEIGHT * 0.5 - 0.0195, front + 0.005), 0.0)
	_title.outline_size = 0
	_set_text(_title, "TOTALLY REAL ID", WIDTH - 0.06)
	_index_label = _label("", DISPLAY_FONT, 56, INK, Vector3(WIDTH * 0.5 - 0.02, HEIGHT * 0.5 - 0.0195, front + 0.005), 0.0)
	_index_label.outline_size = 0
	_index_label.pixel_size = 0.00013
	# Photo: deep purple square on the left.
	var photo := Vector3(-0.062, -0.006, front + 0.0025)
	_slab(0.06, 0.068, 0.002, 0.007, PHOTO_BG, photo)
	_build_photo(photo + Vector3(0.0, 0.0, 0.0015))
	# Fields on the right.
	var col := -0.025
	_caption("NAME", Vector3(col, 0.03, front + 0.005))
	_name = _label("", DISPLAY_FONT, 96, INK, Vector3(col, 0.016, front + 0.005), 0.00016)
	_name.outline_size = 0
	_caption("BORN", Vector3(col, -0.002, front + 0.005))
	_born = _label("", BODY_FONT, 72, INK, Vector3(col, -0.013, front + 0.005), 0.00013)
	_born.outline_size = 0
	_caption("FROM", Vector3(col + 0.058, -0.002, front + 0.005))
	_from = _label("", BODY_FONT, 72, INK, Vector3(col + 0.058, -0.013, front + 0.005), 0.00013)
	_from.outline_size = 0
	# Grade stamp, bottom right of the fields.
	var stamp_pos := Vector3(0.07, -0.032, front + 0.003)
	_grade_plate = _slab(0.05, 0.016, 0.002, 0.006, GRADE_COLORS[0], stamp_pos)
	_grade_plate.rotation.z = deg_to_rad(6.0)
	_grade = _label("", DISPLAY_FONT, 72, INK, stamp_pos + Vector3(0.0, 0.0, 0.002), 0.00013)
	_grade.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade.rotation.z = deg_to_rad(6.0)
	_grade.outline_size = 0
	# Hologram sticker.
	var holo := _disc(0.009, Color("ff3fd2"), Vector3(0.017, -0.032, front + 0.003), 0.8)
	holo.scale = Vector3(1.0, 1.0, 1.0)
	_disc(0.0055, Color("3ef0ff"), Vector3(0.017, -0.032, front + 0.0035), 1.2)
	# BANKED / CAP bar along the bottom.
	var bar_w := WIDTH - 0.03
	var bar_pos := Vector3(0.0, -HEIGHT * 0.5 + 0.0145, front + 0.0025)
	_slab(bar_w, 0.014, 0.002, 0.006, BAR_BG, bar_pos)
	_bar_fill = _box(Vector3(bar_w, 0.009, 0.002), Color("b6ff3b"), bar_pos + Vector3(0.0, 0.0, 0.001))
	_bar_label = _label("", DISPLAY_FONT, 64, Color.WHITE, bar_pos + Vector3(0.0, 0.0, 0.003), 0.0001)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.outline_size = 10
	_bar_label.outline_modulate = INK
	# FLAGGED / BURNED stamp across the face.
	_stamp = _label("FLAGGED", DISPLAY_FONT, 128, FLAGGED, Vector3(0.022, -0.006, front + 0.008), 0.00026)
	_stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stamp.rotation.z = deg_to_rad(16.0)
	_stamp.outline_size = 18
	_stamp.outline_modulate = Color("1c1033")
	_stamp.render_priority = 2
	_stamp.outline_render_priority = 1
	# Back: magnetic stripe.
	var back := -THICKNESS * 0.5
	var stripe := _box(Vector3(WIDTH - 0.004, 0.026, 0.002), Color("1c1033"), Vector3(0.0, HEIGHT * 0.5 - 0.03, back - 0.001))
	stripe.name = "Stripe"


func _build_photo(at: Vector3) -> void:
	_photo_parts["bottom"] = _slab(0.05, 0.012, 0.0015, 0.004, Color.GRAY, at + Vector3(0.0, -0.026, 0.0))
	_photo_parts["top"] = _slab(0.044, 0.026, 0.0015, 0.01, Color.GRAY, at + Vector3(0.0, -0.012, 0.0005))
	_photo_parts["accessory"] = _disc(0.0055, Color.GRAY, at + Vector3(0.012, -0.012, 0.0022))
	_photo_parts["head"] = _disc(0.017, PHOTO_SKIN, at + Vector3(0.0, 0.01, 0.001))
	# Big googly eyes.
	for x: float in [-0.0068, 0.0068]:
		_disc(0.0058, Color.WHITE, at + Vector3(x, 0.012, 0.0022))
		_disc(0.0028, Color("1a1a1e"), at + Vector3(x, 0.0115, 0.0028))
	_photo_parts["glasses"] = _box(Vector3(0.03, 0.0045, 0.0012), Color.GRAY, at + Vector3(0.0, 0.0125, 0.0034))
	_photo_parts["hat"] = _slab(0.036, 0.012, 0.0015, 0.004, Color.GRAY, at + Vector3(0.0, 0.027, 0.0015))


func _paint_photo(outfit: Dictionary, skin: Color) -> void:
	_recolor(_photo_parts["head"], skin)
	for key: String in ["hat", "glasses", "top", "bottom", "accessory"]:
		var mi: MeshInstance3D = _photo_parts[key]
		var piece := StringName(str(outfit.get(key, "")))
		var empty := piece == &"" or OutfitCatalog.is_none(piece)
		mi.visible = not empty or key == "top" or key == "bottom"
		_recolor(mi, OutfitCatalog.piece_color(piece) if not empty else Color("5a3a80"))


func _caption(text: String, pos: Vector3) -> Label3D:
	var l := _label(text, DISPLAY_FONT, 56, CAPTION, pos, 0.0001)
	l.outline_size = 0
	return l


func _label(text: String, font: StringName, size: int, color: Color, pos: Vector3, pixel: float) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = ArtKit.display_font() if font == DISPLAY_FONT else ArtKit.body_font(500)
	l.font_size = size
	l.pixel_size = pixel if pixel > 0.0 else 0.00014
	l.modulate = color
	l.outline_size = 8
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.double_sided = false
	l.shaded = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.position = pos
	add_child(l)
	return l


## Sets the text and shrinks the label so it stays under `max_width` metres.
func _set_text(l: Label3D, text: String, max_width: float) -> void:
	l.text = text
	var base: float = l.get_meta(&"base_pixel", l.pixel_size)
	l.set_meta(&"base_pixel", base)
	l.pixel_size = base
	if l.font == null or text == "":
		return
	var w := l.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size).x * base
	if w > max_width and w > 0.0:
		l.pixel_size = base * max_width / w


## A rounded-rectangle slab facing +Z. Only the card body gets an outline;
## the printed details on its face are flat.
func _slab(w: float, h: float, t: float, r: float, color: Color, pos: Vector3, outline: bool = false, bevel: float = 0.0) -> MeshInstance3D:
	var mi := ArtKit.mesh_instance(MeshFactory.extrude(rounded_rect(w, h, r), t, bevel), _material(color, 0.0, outline))
	mi.set_meta(&"outline", outline)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	add_child(mi)
	return mi


func _box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	return _slab(size.x, size.y, size.z, 0.0005, color, pos)


func _disc(radius: float, color: Color, pos: Vector3, emission: float = 0.0) -> MeshInstance3D:
	var mi := _slab(radius * 2.0, radius * 2.0, 0.0012, radius, color, pos)
	if emission > 0.0:
		_recolor(mi, color, emission)
	return mi


func _recolor(mi: MeshInstance3D, color: Color, emission: float = 0.0) -> void:
	mi.material_override = _material(color, emission, bool(mi.get_meta(&"outline", false)))


## The body (outlined) is toon lit; everything printed on it is flat colour.
static func _material(color: Color, emission: float, outline: bool) -> Material:
	if outline:
		return Primitives.material(color, emission)
	return Primitives.material(Color(color.r * 0.92, color.g * 0.92, color.b * 0.92, color.a), emission, true, false)


## Outline of a w x h rectangle with corners rounded by r, centred on 0.
static func rounded_rect(w: float, h: float, r: float, segments: int = 6) -> PackedVector2Array:
	r = clampf(r, 0.0, minf(w, h) * 0.5)
	var corners: Array[Vector2] = [Vector2(w * 0.5 - r, h * 0.5 - r), Vector2(-w * 0.5 + r, h * 0.5 - r), Vector2(-w * 0.5 + r, -h * 0.5 + r), Vector2(w * 0.5 - r, -h * 0.5 + r)]
	var out := PackedVector2Array()
	for c in 4:
		for i in segments + 1:
			var a := PI * 0.5 * c + PI * 0.5 * float(i) / float(segments)
			out.append(corners[c] + Vector2(cos(a), sin(a)) * r)
	return out
