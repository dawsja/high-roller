class_name FloatingSign
extends Label3D
## Big floating game name over a machine ("SLOTS"): Lilita One with a thick
## dark outline, billboarded, bobbing gently, fading out between fade_start
## and fade_end metres from the active camera. Build with ArtKit.floating_sign().

## Font pixels per glyph; large so the text stays crisp up close.
const SIGN_FONT_SIZE := 128

@export var fade_start: float = 9.0
@export var fade_end: float = 16.0
## Bob amplitude (font pixels) and speed (radians per second).
@export var bob_pixels: float = 6.0
@export var bob_speed: float = 1.7

var base_color: Color = Color.WHITE
var _phase: float = 0.0


## Text about `size` metres tall (cap height) in `color`.
func setup(sign_text: String, size: float, color: Color = Color.WHITE) -> void:
	text = sign_text
	name = "Sign"
	font = ArtKit.display_font()
	font_size = SIGN_FONT_SIZE
	outline_size = 34
	outline_modulate = ArtKit.OUTLINE_COLOR
	base_color = color
	modulate = color
	pixel_size = maxf(size, 0.01) / (SIGN_FONT_SIZE * 0.7)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	double_sided = true
	visibility_range_end = fade_end + 1.0
	_phase = randf() * TAU


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * bob_speed, TAU)
	offset = Vector2(0.0, sin(_phase) * bob_pixels)
	var a := fade_alpha()
	modulate = Color(base_color, base_color.a * a)
	outline_modulate = Color(ArtKit.OUTLINE_COLOR, a)


## 1 within fade_start of the active camera, 0 beyond fade_end (1 with no camera).
func fade_alpha() -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null or not is_inside_tree():
		return 1.0
	var d := cam.global_position.distance_to(global_position)
	return 1.0 - smoothstep(fade_start, maxf(fade_end, fade_start + 0.01), d)
