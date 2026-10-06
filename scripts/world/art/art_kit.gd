class_name ArtKit
extends RefCounted
## The toon art kit every world module builds on (docs/ART_DIRECTION.md):
## cached toon / pattern / neon / screen materials, the world Environment,
## per-casino palettes, glowing hover outlines, fonts and floating signs.
##
## Materials are cached by their parameters and shared: never edit one you
## got from here. Per-object tweaks go through instance uniforms instead:
## set_outline_hover(), set_outline_mode() and set_neon_level().

const SHADER_TOON := preload("res://assets/shaders/toon.gdshader")
const SHADER_TOON_ALPHA := preload("res://assets/shaders/toon_alpha.gdshader")
const SHADER_TOON_UNSHADED := preload("res://assets/shaders/toon_unshaded.gdshader")
const SHADER_TOON_UNSHADED_ALPHA := preload("res://assets/shaders/toon_unshaded_alpha.gdshader")
const SHADER_OUTLINE := preload("res://assets/shaders/outline.gdshader")
const SHADER_CARPET := preload("res://assets/shaders/carpet.gdshader")
const SHADER_WALL := preload("res://assets/shaders/wall_panel.gdshader")
const SHADER_FELT := preload("res://assets/shaders/felt.gdshader")
const SHADER_SCREEN := preload("res://assets/shaders/screen.gdshader")
const SHADER_NEON := preload("res://assets/shaders/neon.gdshader")

const DISPLAY_FONT_PATH := "res://assets/fonts/LilitaOne-Regular.ttf"
const BODY_FONT_PATH := "res://assets/fonts/Fredoka.ttf"

## Dark purple ink for outlines and text outlines.
const OUTLINE_COLOR := Color("1c0f2e")
## Outline width in pixels at a 900 px tall viewport.
const OUTLINE_WIDTH := 2.6
## The bright hover outline (HDR-boosted in the shader so it blooms).
const HOVER_COLOR := Color("fff06a")

static var _materials: Dictionary = {}
static var _fonts: Dictionary = {}


# --- materials ---------------------------------------------------------------

## Cached toon material: cel bands + rim (or flat with `unshaded`), emission
## = color * `emission`, alpha below 1 makes it see-through (and drops the
## outline). `outline` adds the inverted-hull pass; `gloss` a toon highlight.
static func toon_material(color: Color, emission: float = 0.0, unshaded: bool = false, outline: bool = true,
		gloss: float = 0.0, vertex_color: bool = false) -> ShaderMaterial:
	var alpha := color.a < 0.999
	var key := "toon|%s|%.3f|%s|%s|%.3f|%s" % [color.to_html(), emission, unshaded, outline and not alpha, gloss, vertex_color]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	if unshaded:
		mat.shader = SHADER_TOON_UNSHADED_ALPHA if alpha else SHADER_TOON_UNSHADED
	else:
		mat.shader = SHADER_TOON_ALPHA if alpha else SHADER_TOON
	mat.set_shader_parameter(&"albedo", color)
	if emission > 0.0:
		mat.set_shader_parameter(&"emission_strength", emission)
	if gloss > 0.0 and not unshaded:
		mat.set_shader_parameter(&"gloss", gloss)
	if vertex_color:
		mat.set_shader_parameter(&"use_vertex_color", true)
	if outline and not alpha:
		mat.next_pass = outline_material()
	_materials[key] = mat
	return mat


## The shared inverted-hull outline pass (a different color/width is a separate cached material).
static func outline_material(color: Color = OUTLINE_COLOR, width: float = OUTLINE_WIDTH) -> ShaderMaterial:
	var key := "outline|%s|%.3f" % [color.to_html(), width]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_OUTLINE
	mat.set_shader_parameter(&"outline_color", color)
	mat.set_shader_parameter(&"outline_width", width)
	_materials[key] = mat
	return mat


## Loud carpet in four colors (base, then three motif colors); `pattern` is
## ArtPalette.CARPET_*; `tile` metres per motif.
static func carpet_material(colors: Array, pattern: int = ArtPalette.CARPET_EYES, tile: float = 1.3) -> ShaderMaterial:
	var c := _four(colors, [Color("17123d"), ArtPalette.NEON_ORANGE, ArtPalette.CASINO_RED, ArtPalette.NEON_SUNFLOWER])
	var key := "carpet|%s|%s|%s|%s|%d|%.3f" % [c[0].to_html(), c[1].to_html(), c[2].to_html(), c[3].to_html(), pattern, tile]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_CARPET
	mat.set_shader_parameter(&"color_base", c[0])
	mat.set_shader_parameter(&"color_1", c[1])
	mat.set_shader_parameter(&"color_2", c[2])
	mat.set_shader_parameter(&"color_3", c[3])
	mat.set_shader_parameter(&"pattern", pattern)
	mat.set_shader_parameter(&"tile", tile)
	_materials[key] = mat
	return mat


## The casino's carpet (palette floor colors and carpet pattern).
static func carpet_for(palette: Dictionary, tile: float = 1.3) -> ShaderMaterial:
	return carpet_material(ArtPalette.carpet_colors(palette), int(palette.get("carpet_pattern", 0)), tile)


## Patterned wall panels; `pattern` is ArtPalette.WALL_*. `line_glow` > 0
## makes the pattern lines glow like neon piping. `rail_height` < 0 drops the dado rail.
static func wall_material(base: Color, alt: Color, line: Color, pattern: int = ArtPalette.WALL_DIAMONDS,
		tile: float = 0.9, line_glow: float = 0.0, rail_height: float = 1.1) -> ShaderMaterial:
	var key := "wall|%s|%s|%s|%d|%.3f|%.3f|%.3f" % [base.to_html(), alt.to_html(), line.to_html(), pattern, tile, line_glow, rail_height]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_WALL
	mat.set_shader_parameter(&"color_base", base)
	mat.set_shader_parameter(&"color_alt", alt)
	mat.set_shader_parameter(&"color_line", line)
	mat.set_shader_parameter(&"pattern", pattern)
	mat.set_shader_parameter(&"tile", tile)
	mat.set_shader_parameter(&"line_glow", line_glow)
	mat.set_shader_parameter(&"rail_height", rail_height)
	_materials[key] = mat
	return mat


## The casino's walls (palette wall colors, pattern, tile size and line glow).
static func wall_for(palette: Dictionary) -> ShaderMaterial:
	return wall_material(palette["wall"], palette["wall_alt"], palette["wall_line"], int(palette.get("wall_pattern", 0)),
			float(palette.get("wall_tile", 0.9)), float(palette.get("wall_glow", 0.15)))


## The casino's ceiling: the wall pattern in darker tones, no rail.
static func ceiling_for(palette: Dictionary, line_glow: float = 0.4, tile: float = 1.6) -> ShaderMaterial:
	var base: Color = palette["ceiling"]
	return wall_material(base, base.lightened(0.08), palette["neon_2"], ArtPalette.WALL_SQUARES, tile, line_glow, -1.0)


## Table felt. `half_size` is the felt's half extents in its mesh's XZ
## (metres), `shape` 0 rounded rectangle or 1 ellipse.
static func felt_material(color: Color, border: Color = Color("ffe08a"), half_size: Vector2 = Vector2(0.5, 0.5),
		corner_radius: float = 0.12, shape: int = 0) -> ShaderMaterial:
	var key := "felt|%s|%s|%.3f|%.3f|%.3f|%d" % [color.to_html(), border.to_html(), half_size.x, half_size.y, corner_radius, shape]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_FELT
	mat.set_shader_parameter(&"felt_color", color)
	mat.set_shader_parameter(&"border_color", border)
	mat.set_shader_parameter(&"half_size", half_size)
	mat.set_shader_parameter(&"corner_radius", corner_radius)
	mat.set_shader_parameter(&"shape", shape)
	_materials[key] = mat
	return mat


## Dark glowing monitor glass (put Label3D text just in front of it).
static func screen_material(color: Color = Color("0b0614"), glow: Color = Color("8c4dff"), brightness: float = 1.0) -> ShaderMaterial:
	var key := "screen|%s|%s|%.3f" % [color.to_html(), glow.to_html(), brightness]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_SCREEN
	mat.set_shader_parameter(&"screen_color", color)
	mat.set_shader_parameter(&"glow_color", glow)
	mat.set_shader_parameter(&"brightness", brightness)
	_materials[key] = mat
	return mat


## Neon tube glow; energy above ~1.4 blooms. Optional slow pulse.
static func neon_material(color: Color, energy: float = 2.0, pulse_speed: float = 0.0) -> ShaderMaterial:
	var key := "neon|%s|%.3f|%.3f" % [color.to_html(), energy, pulse_speed]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER_NEON
	mat.set_shader_parameter(&"color", color)
	mat.set_shader_parameter(&"energy", energy)
	mat.set_shader_parameter(&"pulse_speed", pulse_speed)
	_materials[key] = mat
	return mat


## Number of cached materials (tests, debugging).
static func material_cache_size() -> int:
	return _materials.size()


# --- instances, hover and per-object tweaks ---------------------------------

## A MeshInstance3D with `material` as its override, passing the mesh's
## outline_mode to the outline shader (hard-edged meshes grow per axis).
static func mesh_instance(mesh: Mesh, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	var mode := outline_mode_for(mesh)
	if mode != MeshFactory.OUTLINE_SMOOTH:
		set_outline_mode(mi, mode)
	return mi


## MeshFactory.OUTLINE_* the outline shader should use for `mesh`.
static func outline_mode_for(mesh: Mesh) -> int:
	if mesh == null:
		return MeshFactory.OUTLINE_SMOOTH
	if mesh.has_meta(MeshFactory.META_OUTLINE_MODE):
		return int(mesh.get_meta(MeshFactory.META_OUTLINE_MODE))
	if mesh is BoxMesh or mesh is PrismMesh:
		return MeshFactory.OUTLINE_BOX
	if mesh is CylinderMesh:
		return MeshFactory.OUTLINE_CYLINDER
	return MeshFactory.OUTLINE_SMOOTH


static func set_outline_mode(geometry: GeometryInstance3D, mode: int) -> void:
	geometry.set_instance_shader_parameter(&"outline_mode", float(mode))


## Turns the bright glowing hover outline on or off for every mesh under
## `root` (root included). Cheap: per-instance uniforms, no new materials.
static func set_outline_hover(root: Node, on: bool, color: Color = HOVER_COLOR) -> void:
	if root == null:
		return
	if root is MeshInstance3D or root is MultiMeshInstance3D:
		var gi := root as GeometryInstance3D
		gi.set_instance_shader_parameter(&"outline_hover", 1.0 if on else 0.0)
		if on:
			gi.set_instance_shader_parameter(&"outline_hover_color", color)
	for child: Node in root.get_children():
		set_outline_hover(child, on, color)


## True if the first mesh under `root` (root included) is hovered.
static func is_outline_hovered(root: Node) -> bool:
	var gi := _first_mesh(root)
	if gi == null:
		return false
	var v: Variant = gi.get_instance_shader_parameter(&"outline_hover")
	return v != null and float(v) > 0.5


static func _first_mesh(root: Node) -> GeometryInstance3D:
	if root == null:
		return null
	if root is MeshInstance3D or root is MultiMeshInstance3D:
		return root as GeometryInstance3D
	for child: Node in root.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


## Dims or brightens a neon mesh (0 = off, 1 = full) without touching its shared material.
static func set_neon_level(geometry: GeometryInstance3D, level: float) -> void:
	geometry.set_instance_shader_parameter(&"neon_level", level)


# --- palette and environment -------------------------------------------------

## Named colors for a casino (a Tuning.CASINOS entry); see ArtPalette.
static func palette_for(casino: Dictionary) -> Dictionary:
	return ArtPalette.for_casino(casino)


## World Environment for a palette: bright colored ambient light, filmic
## tonemap, a saturation boost, glow that blooms neon (emission/energy above
## ~1.4) but not lit surfaces or white text, and optional light depth fog.
static func make_environment(palette: Dictionary, fog: bool = true) -> Environment:
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	var sky: Color = palette.get("sky", ArtPalette.CLUB_CEILING)
	# The compatibility renderer converts the clear color to sRGB twice once
	# post-processing (glow) is on; pre-linearize it so it lands as intended.
	env.background_color = sky.srgb_to_linear() if compat else sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = palette.get("ambient", Color(0.8, 0.75, 0.9))
	env.ambient_light_energy = float(palette.get("ambient_energy", 0.6))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Filmic with a white point of 2 keeps palette colors close to what was
	# picked (white 1 lifts mid-tones ~25%) while neon above 1 rolls off.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 2.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	for i in 7:
		env.set_glow_level(i, [0.0, 1.0, 1.0, 0.7, 0.4, 0.0, 0.0][i])
	# Lit surfaces stay around 1.2 at most, so only emission (neon at energy
	# ~1.6+, hover outlines) blooms. Compatibility tops out near 2.0.
	env.glow_hdr_threshold = 1.3 if compat else 1.25
	env.glow_hdr_scale = 0.5 if compat else 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	env.adjustment_brightness = 1.0
	if fog:
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = palette.get("fog", Color(0.2, 0.1, 0.3))
		env.fog_light_energy = 1.0
		env.fog_density = 0.006 if bool(palette.get("day", false)) else 0.012
		env.fog_sky_affect = 0.0
	return env


static func make_world_environment(palette: Dictionary, fog: bool = true) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = make_environment(palette, fog)
	return we


## A soft key light for a casino floor (warm, high, slight angle, shadows on).
static func make_key_light(palette: Dictionary, energy: float = 0.7) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation = Vector3(deg_to_rad(-58.0), deg_to_rad(-32.0), 0.0)
	sun.light_energy = energy
	sun.light_color = Color("fff3e6").lerp(palette.get("neon_1", Color.WHITE), 0.08)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.55
	sun.directional_shadow_max_distance = 40.0
	return sun


## A colored area light (neon spill over a game area).
static func neon_light(color: Color, energy: float = 1.0, light_range: float = 6.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	return light


# --- fonts, labels and signs ------------------------------------------------

## Lilita One (display: signs, titles, keys, big numbers).
static func display_font() -> Font:
	if not _fonts.has(&"display"):
		_fonts[&"display"] = _load_font(DISPLAY_FONT_PATH)
	return _fonts[&"display"]


## Fredoka at `weight` (300-700; body text).
static func body_font(weight: int = 600) -> FontVariation:
	var key := StringName("body_%d" % weight)
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = _load_font(BODY_FONT_PATH)
		var ts := TextServerManager.get_primary_interface()
		if ts != null:
			fv.variation_opentype = {ts.name_to_tag("wght"): clampi(weight, 300, 700)}
		_fonts[key] = fv
	return _fonts[key]


## Big billboarded game name ("SLOTS") about `size` metres tall in Lilita One
## with a thick dark outline. Bobs gently and fades out with camera distance.
static func floating_sign(text: String, size: float = 0.45, color: Color = Color.WHITE) -> FloatingSign:
	var fs := FloatingSign.new()
	fs.setup(text, size, color)
	return fs


## A Label3D in the display font with a thick dark outline.
static func make_label(text: String, pixel_size: float = 0.01, color: Color = Color.WHITE, font_size: int = 48,
		billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = display_font()
	l.font_size = font_size
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_modulate = OUTLINE_COLOR
	l.outline_size = maxi(4, int(round(font_size * 0.28)))
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


## Loads a font: the imported resource when the project has been imported,
## else the raw TTF straight from disk, else Godot's fallback font.
static func _load_font(path: String) -> Font:
	if FileAccess.file_exists(path + ".import"):
		var f := load(path) as Font
		if f != null:
			return f
	if FileAccess.file_exists(path):
		var ff := FontFile.new()
		if ff.load_dynamic_font(path) == OK:
			return ff
	return ThemeDB.fallback_font


static func _four(colors: Array, fallback: Array) -> Array[Color]:
	var out: Array[Color] = []
	for i in 4:
		out.append(colors[i] if i < colors.size() and colors[i] is Color else fallback[i])
	return out
