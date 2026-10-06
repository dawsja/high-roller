class_name KeyButton3D
extends Pressable
## A chunky rounded key cap sitting in a dark socket, with its legend printed
## on top (Label3D). Pressing it sinks the cap and springs it back with a
## little overshoot. `set_lit(true)` makes the cap glow (toggle keys);
## disabled keys go dark grey and ignore presses.
##
## Key space: origin at the bottom of the socket on the panel surface, the cap
## rises along +Y, the legend reads along +X with its top toward -Z.

const SOCKET_GROW := 0.009
const SOCKET_HEIGHT := 0.008
const PRESS_SECONDS := 0.05
const REBOUND_SECONDS := 0.16
## Emission of a lit cap (blooms) and of a plain "emissive" cap.
const LIT_EMISSION := 0.9
## The hover ring: a saturated yellow that stays yellow when it blooms.
const RING_COLOR := Color("ffc300")

var legend: String = ""
var color: Color = DiegeticKit.KEY_CREAM
var size: Vector3 = Vector3(0.066, 0.034, 0.066)
var legend_color: Color = DiegeticKit.LEGEND_DARK
## Base self-glow of the cap (0 = none); lit keys use LIT_EMISSION.
var emission: float = 0.0
var lit: bool = false
## How far the cap sinks when pressed (m).
var travel: float = 0.012
## Times pressed (tests, feedback).
var press_count: int = 0

var cap: Node3D
var cap_mesh: MeshInstance3D
var socket: MeshInstance3D
var legend_label: Label3D
## Glowing frame around the cap while hovered.
var hover_ring: MeshInstance3D
var _legend_auto: bool = true
var _tween: Tween
var _hover_tween: Tween


## Builds the key. `p_legend_color` with alpha 0 picks a readable ink for the
## cap color. Returns self for chaining.
func setup(p_legend: String, p_color: Color = DiegeticKit.KEY_CREAM, p_size: Vector3 = Vector3(0.066, 0.034, 0.066),
		p_id: StringName = &"", p_legend_color: Color = Color(0, 0, 0, 0)) -> KeyButton3D:
	for c: Node in get_children():
		if c != shape:
			remove_child(c)
			c.queue_free()
	legend = p_legend
	color = p_color
	size = p_size.abs().max(Vector3(0.01, 0.008, 0.01))
	id = p_id if p_id != &"" else StringName(p_legend.to_lower().replace("\n", "_").replace(" ", "_"))
	_legend_auto = p_legend_color.a <= 0.0
	legend_color = DiegeticKit.legend_color_for(color) if _legend_auto else p_legend_color
	travel = clampf(size.y * 0.45, 0.004, 0.02)
	name = "Key_%s" % String(id).validate_node_name()
	var radius := minf(size.y * 0.42, minf(size.x, size.z) * 0.3)
	socket = Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(size.x + SOCKET_GROW, SOCKET_HEIGHT, size.z + SOCKET_GROW), SOCKET_HEIGHT * 0.45, 2), DiegeticKit.BEZEL)
	socket.name = "Socket"
	socket.position.y = SOCKET_HEIGHT * 0.5
	add_child(socket)
	cap = Node3D.new()
	cap.name = "Cap"
	add_child(cap)
	cap_mesh = ArtKit.mesh_instance(MeshFactory.rounded_box(size, radius, 3), DiegeticKit.key_material(color))
	cap_mesh.name = "CapMesh"
	cap_mesh.position.y = size.y * 0.5 + SOCKET_HEIGHT * 0.35
	cap.add_child(cap_mesh)
	legend_label = DiegeticKit.text_label("", 0.02, legend_color)
	legend_label.name = "Legend"
	legend_label.rotation.x = -PI * 0.5
	legend_label.position.y = cap_mesh.position.y + size.y * 0.5 + 0.0008
	cap.add_child(legend_label)
	var rw := size.x * 0.5 + 0.006
	var rd := size.z * 0.5 + 0.006
	hover_ring = ArtKit.mesh_instance(MeshFactory.stroke(_rounded_rect(rw, rd, radius + 0.004), 0.009, 0.007), ArtKit.neon_material(RING_COLOR, 1.7))
	hover_ring.name = "HoverRing"
	hover_ring.rotation.x = -PI * 0.5
	hover_ring.position.y = cap_mesh.position.y + size.y * 0.25
	hover_ring.visible = false
	cap.add_child(hover_ring)
	glow_root = cap
	set_box_shape(Vector3(size.x + SOCKET_GROW, size.y + SOCKET_HEIGHT, size.z + SOCKET_GROW), Vector3(0.0, (size.y + SOCKET_HEIGHT) * 0.5, 0.0))
	set_legend(p_legend)
	_refresh_look()
	return self


func set_legend(text: String) -> void:
	legend = text
	hint = "[LMB] %s" % text.replace("\n", " ")
	if legend_label == null:
		return
	var lines := maxi(1, text.split("\n").size())
	var h := minf(size.z * (0.42 if lines == 1 else 0.26), 0.05)
	DiegeticKit.fit_label(legend_label, text, h, size.x * 0.8)
	legend_label.outline_size = 0 if legend_color.get_luminance() < 0.5 else 12


func set_color(p_color: Color) -> void:
	color = p_color
	if _legend_auto:
		legend_color = DiegeticKit.legend_color_for(color)
		set_legend(legend)
	_refresh_look()


func set_lit(on: bool) -> void:
	if lit == on:
		return
	lit = on
	_refresh_look()


func set_emission(value: float) -> void:
	emission = maxf(value, 0.0)
	_refresh_look()


## World position of the cap's top centre.
func aim_point() -> Vector3:
	var local := Vector3(0.0, SOCKET_HEIGHT + size.y, 0.0)
	return to_global(local) if is_inside_tree() else position + local


func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## The press-in and rebound, without any press logic (feedback for refused presses too).
func play_press(depth: float = 1.0) -> void:
	if cap == null:
		return
	_kill(_tween)
	cap.position.y = 0.0
	if not is_inside_tree():
		return
	var down := -travel * clampf(depth, 0.0, 1.0)
	_tween = create_tween()
	_tween.tween_property(cap, "position:y", down, PRESS_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(cap, "scale", Vector3(1.05, 0.9, 1.05), PRESS_SECONDS)
	_tween.tween_property(cap, "position:y", travel * 0.18, REBOUND_SECONDS * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(cap, "scale", _rest_scale() * 1.02, REBOUND_SECONDS * 0.45)
	_tween.tween_property(cap, "position:y", 0.0, REBOUND_SECONDS * 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.parallel().tween_property(cap, "scale", _rest_scale(), REBOUND_SECONDS * 0.55)


## A short sideways shake (a refused press).
func play_nope() -> void:
	if cap == null or not is_inside_tree():
		return
	_kill(_tween)
	cap.position = Vector3.ZERO
	_tween = create_tween()
	var w := size.x * 0.06
	for x: float in [w, -w, w * 0.6, -w * 0.4, 0.0]:
		_tween.tween_property(cap, "position:x", x, 0.035)


func _on_press(_user_pid: int) -> void:
	press_count += 1
	play_press()


func _on_hover(value: bool) -> void:
	if cap == null:
		return
	_refresh_ring()
	_kill(_hover_tween)
	if not is_inside_tree() or is_animating():
		cap.scale = _rest_scale()
		return
	_hover_tween = create_tween()
	_hover_tween.tween_property(cap, "scale", _rest_scale(), HoverGlow.POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_enabled_changed(_value: bool) -> void:
	_refresh_look()


## The ring glows yellow while hovered, in the key's own color while lit.
func _refresh_ring() -> void:
	if hover_ring == null:
		return
	hover_ring.visible = hovered or (lit and enabled)
	var c := RING_COLOR if hovered else color.lightened(0.1)
	hover_ring.material_override = ArtKit.neon_material(c, 1.7 if hovered else 1.5)


func _rest_scale() -> Vector3:
	return Vector3.ONE * (HoverGlow.POP_SCALE if hovered else 1.0)


func _refresh_look() -> void:
	if cap_mesh == null:
		return
	var c := color if enabled else DiegeticKit.disabled_color(color)
	var e := (LIT_EMISSION if lit else emission) if enabled else 0.0
	cap_mesh.material_override = DiegeticKit.key_material(c, e)
	var lc := legend_color
	if not enabled:
		lc = Color(lc, 0.45)
	elif lit and legend_color.get_luminance() > 0.5:
		lc = Color(lc.r * 1.6, lc.g * 1.6, lc.b * 1.6, 1.0)
	legend_label.modulate = lc
	_refresh_ring()


## A rounded rectangle outline (half extents hw x hd) for the hover ring.
static func _rounded_rect(hw: float, hd: float, r: float, steps: int = 4) -> PackedVector2Array:
	r = clampf(r, 0.0, minf(hw, hd))
	var pts := PackedVector2Array()
	var corners := [Vector2(hw - r, hd - r), Vector2(-hw + r, hd - r), Vector2(-hw + r, -hd + r), Vector2(hw - r, -hd + r)]
	for i in 4:
		for k in steps + 1:
			var a := PI * 0.5 * float(i) + PI * 0.5 * float(k) / float(steps)
			pts.append((corners[i] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()
