extends TestCase
## The toon art kit: cached materials, procedural meshes, palettes, the world
## Environment, hover outlines, labels, floating signs and UI fonts.

const SHADERS := [
	"res://assets/shaders/toon.gdshader",
	"res://assets/shaders/toon_alpha.gdshader",
	"res://assets/shaders/toon_unshaded.gdshader",
	"res://assets/shaders/toon_unshaded_alpha.gdshader",
	"res://assets/shaders/outline.gdshader",
	"res://assets/shaders/carpet.gdshader",
	"res://assets/shaders/wall_panel.gdshader",
	"res://assets/shaders/felt.gdshader",
	"res://assets/shaders/screen.gdshader",
	"res://assets/shaders/neon.gdshader",
]


# --- materials ---------------------------------------------------------------

func test_toon_materials_are_cached_per_parameters() -> void:
	var a := Primitives.material(Color("ff3fd2"))
	assert_true(a == Primitives.material(Color("ff3fd2")), "same color, same material")
	assert_false(a == Primitives.material(Color("3ef0ff")), "different color")
	assert_false(a == Primitives.material(Color("ff3fd2"), 1.0), "different emission")
	assert_false(a == Primitives.material(Color("ff3fd2"), 0.0, false, false), "outline off")
	assert_true(a == ArtKit.toon_material(Color("ff3fd2")), "Primitives and ArtKit share the cache")
	assert_eq(a.shader, ArtKit.SHADER_TOON)
	assert_eq(a.get_shader_parameter(&"albedo"), Color("ff3fd2"))


func test_outline_pass_is_shared_and_optional() -> void:
	var a := Primitives.material(Color.RED)
	var b := Primitives.material(Color.BLUE)
	assert_true(a.next_pass is ShaderMaterial, "outline next_pass")
	assert_true(a.next_pass == b.next_pass, "one outline material for every color")
	assert_eq((a.next_pass as ShaderMaterial).shader, ArtKit.SHADER_OUTLINE)
	assert_eq((a.next_pass as ShaderMaterial).get_shader_parameter(&"outline_color"), ArtKit.OUTLINE_COLOR)
	assert_true(Primitives.material(Color.RED, 0.0, false, false).next_pass == null, "outline disabled")


func test_alpha_and_unshaded_variants() -> void:
	var glass := Primitives.material(Color(1, 1, 1, 0.4))
	assert_eq(glass.shader, ArtKit.SHADER_TOON_ALPHA)
	assert_true(glass.next_pass == null, "see-through materials have no outline")
	var flat := Primitives.material(Color.GREEN, 0.0, true)
	assert_eq(flat.shader, ArtKit.SHADER_TOON_UNSHADED)
	assert_eq(Primitives.material(Color(0, 1, 0, 0.2), 0.0, true).shader, ArtKit.SHADER_TOON_UNSHADED_ALPHA)
	var lit := Primitives.material(Color.GREEN, 2.5)
	assert_almost_eq(float(lit.get_shader_parameter(&"emission_strength")), 2.5)


func test_material_color_reads_toon_and_standard_materials() -> void:
	assert_eq(Primitives.material_color(Primitives.material(Color("123456"))), Color("123456"))
	var std := StandardMaterial3D.new()
	std.albedo_color = Color("abcdef")
	assert_eq(Primitives.material_color(std), Color("abcdef"))
	assert_eq(Primitives.material_color(null), Color(0, 0, 0, 0))


func test_pattern_materials_are_cached() -> void:
	var pal := ArtKit.palette_for(CasinoLadder.by_id(&"neon_oasis"))
	assert_true(ArtKit.carpet_for(pal) == ArtKit.carpet_for(pal))
	assert_true(ArtKit.wall_for(pal) == ArtKit.wall_for(pal))
	assert_true(ArtKit.ceiling_for(pal) == ArtKit.ceiling_for(pal))
	assert_true(ArtKit.felt_material(Color.GREEN) == ArtKit.felt_material(Color.GREEN))
	assert_true(ArtKit.screen_material() == ArtKit.screen_material())
	assert_true(ArtKit.neon_material(Color.CYAN) == ArtKit.neon_material(Color.CYAN))
	assert_false(ArtKit.neon_material(Color.CYAN) == ArtKit.neon_material(Color.CYAN, 4.0))
	assert_eq(ArtKit.carpet_for(pal).get_shader_parameter(&"color_base"), pal["floor_a"])
	assert_eq(int(ArtKit.carpet_for(pal).get_shader_parameter(&"pattern")), int(pal["carpet_pattern"]))
	var size := ArtKit.material_cache_size()
	ArtKit.carpet_for(pal)
	ArtKit.wall_for(pal)
	assert_eq(ArtKit.material_cache_size(), size, "no new materials for repeated requests")


# --- meshes ------------------------------------------------------------------

func test_rounded_box_is_valid() -> void:
	var size := Vector3(1.0, 0.6, 0.4)
	var mesh := MeshFactory.rounded_box(size, 0.1, 3)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# 6 faces x (2 * segments + 2)^2 grid points.
	assert_eq(verts.size(), 6 * 8 * 8)
	assert_eq(indices.size(), 6 * 7 * 7 * 6)
	_assert_mesh_sane(mesh, "rounded box")
	var aabb := mesh.get_aabb()
	assert_almost_eq(aabb.size.x, size.x, 0.001)
	assert_almost_eq(aabb.size.y, size.y, 0.001)
	assert_almost_eq(aabb.size.z, size.z, 0.001)
	# A convex shape around the origin: every normal points away from the centre.
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in verts.size():
		assert_gt(normals[i].dot(verts[i]), 0.0, "outward normal %d" % i)
		if normals[i].dot(verts[i]) <= 0.0:
			break


func test_rounded_box_without_radius_is_a_plain_box() -> void:
	var mesh := MeshFactory.rounded_box(Vector3(2, 1, 1), 0.0)
	assert_eq((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 24)
	_assert_mesh_sane(mesh, "plain box")


func test_meshes_are_cached_by_parameters() -> void:
	assert_true(MeshFactory.rounded_box(Vector3(1, 1, 1), 0.1) == MeshFactory.rounded_box(Vector3(1, 1, 1), 0.1))
	assert_false(MeshFactory.rounded_box(Vector3(1, 1, 1), 0.1) == MeshFactory.rounded_box(Vector3(1, 1, 1), 0.2))
	assert_true(MeshFactory.pill(1.0, 0.2) == MeshFactory.pill(1.0, 0.2))
	assert_true(MeshFactory.rounded_cylinder(0.3, 0.2, 0.05) == MeshFactory.rounded_cylinder(0.3, 0.2, 0.05))
	assert_true(MeshFactory.star(0.3, 0.12) == MeshFactory.star(0.3, 0.12))
	assert_true(MeshFactory.torus(0.2, 0.3) == MeshFactory.torus(0.2, 0.3))
	var count := MeshFactory.cache_size()
	MeshFactory.bolt(0.5, 0.04, 0.03)
	MeshFactory.bolt(0.5, 0.04, 0.03)
	assert_eq(MeshFactory.cache_size(), count + 1, "second identical bolt came from the cache")


func test_round_shapes_are_valid() -> void:
	var pill := MeshFactory.pill(1.0, 0.2)
	_assert_mesh_sane(pill, "pill")
	assert_almost_eq(pill.get_aabb().size.x, 1.0, 0.001)
	assert_almost_eq(pill.get_aabb().size.y, 0.4, 0.001)
	var ball := MeshFactory.ball(0.5)
	_assert_mesh_sane(ball, "ball")
	var arrays := ball.surface_get_arrays(0)
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		assert_almost_eq(v.length(), 0.5, 0.001, "ball vertex on the sphere")
	var cyl := MeshFactory.rounded_cylinder(0.3, 0.2, 0.05, 20)
	_assert_mesh_sane(cyl, "rounded cylinder")
	assert_almost_eq(cyl.get_aabb().size.y, 0.2, 0.001)
	assert_almost_eq(cyl.get_aabb().size.x, 0.6, 0.002)
	var blob := MeshFactory.blob(1.2, 0.4, 0.25)
	_assert_mesh_sane(blob, "blob")
	assert_almost_eq(blob.get_aabb().size.y, 1.2, 0.001)
	_assert_mesh_sane(MeshFactory.lathe(PackedVector2Array([Vector2(0, 0), Vector2(0.3, 0), Vector2(0.2, 0.5), Vector2(0, 0.5)]), 12, false), "lathe")


func test_flat_shapes_are_valid() -> void:
	for mesh: ArrayMesh in [
		MeshFactory.star(0.4, 0.18, 5, 0.05), MeshFactory.star(0.4, 0.18, 5, 0.05, 0.04),
		MeshFactory.bolt(0.8, 0.05), MeshFactory.bolt(0.8, 0.05, 0.05),
		MeshFactory.triangle(0.6, 0.05), MeshFactory.triangle(0.6, 0.05, 0.04),
		MeshFactory.extrude(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 0.2, 0.03),
		MeshFactory.wedge(Vector3(1.0, 0.4, 0.6), 0.3, 0.02),
	]:
		_assert_mesh_sane(mesh, str(mesh.get_aabb()))
		assert_eq(ArtKit.outline_mode_for(mesh), MeshFactory.OUTLINE_BOX, "hard edges grow per axis")
	var wedge := MeshFactory.wedge(Vector3(1.0, 0.4, 0.6))
	assert_almost_eq(wedge.get_aabb().size.x, 1.0, 0.001)
	assert_almost_eq(wedge.get_aabb().size.y, 0.4, 0.001)
	assert_almost_eq(wedge.get_aabb().size.z, 0.6, 0.001)
	var bolt := MeshFactory.bolt(1.0)
	assert_almost_eq(bolt.get_aabb().size.y, 1.0, 0.001)


func test_triangles_wind_like_godot_primitives() -> void:
	# Whatever Godot's front-face convention is, our meshes must match BoxMesh's.
	var ref := _winding_sign(BoxMesh.new().get_mesh_arrays())
	assert_ne(ref, 0)
	for mesh: ArrayMesh in [MeshFactory.rounded_box(Vector3(1, 1, 1), 0.2), MeshFactory.rounded_cylinder(0.3, 0.3, 0.05),
			MeshFactory.star(0.4, 0.2), MeshFactory.wedge(Vector3(1, 0.5, 0.5)), MeshFactory.bolt(0.5, 0.05, 0.03)]:
		assert_eq(_winding_sign(mesh.surface_get_arrays(0)), ref, str(mesh.get_aabb()))


# --- palette and environment -------------------------------------------------

func test_palette_for_every_casino() -> void:
	var keys := ["wall", "wall_alt", "wall_dark", "wall_line", "ceiling", "floor_a", "floor_b", "floor_c", "floor_d",
		"neon_1", "neon_2", "neon_3", "neon_4", "felt", "felt_border", "wood", "wood_dark", "metal", "gold", "red",
		"text", "outline", "ambient", "fog", "sky"]
	var casinos: Array = Tuning.CASINOS.duplicate()
	casinos.append({})
	for casino: Dictionary in casinos:
		var pal := ArtKit.palette_for(casino)
		var label := str(casino.get("id", "club"))
		for k: String in keys:
			assert_true(pal.get(k) is Color, "%s has color %s" % [label, k])
		assert_true(pal.get("carpet_pattern") is int and pal.get("wall_pattern") is int, label)
		assert_gt(float(pal["ambient_energy"]), 0.0, label)
		# Neon accents are hot; night-club walls stay darker than them.
		for i in range(1, 5):
			assert_gte((pal["neon_%d" % i] as Color).v, 0.9, "%s neon_%d bright" % [label, i])
		if not bool(pal["day"]):
			assert_lt((pal["wall"] as Color).v, (pal["neon_1"] as Color).v, "%s wall darker than neon" % label)
	assert_true(bool(ArtKit.palette_for(CasinoLadder.by_id(&"apex"))["day"]), "the Apex is the sky casino")


func test_palette_pushes_casino_colors_toward_saturation() -> void:
	var dull := {"id": &"test_dull", "floor_color": Color("777766"), "wall_color": Color("888877"), "accent_color": Color("aa9988")}
	var pal := ArtKit.palette_for(dull)
	assert_gte((pal["neon_1"] as Color).s, 0.74, "accent pushed to neon")
	assert_gt((pal["wall"] as Color).s, Color("888877").s, "walls more saturated than the source")
	assert_lt((pal["wall"] as Color).v, Color("888877").v, "walls darker than the source")


func test_environment_has_glow_and_palette_ambient() -> void:
	var pal := ArtKit.palette_for(CasinoLadder.by_id(&"grand_marquee"))
	var env := ArtKit.make_environment(pal)
	assert_true(env.glow_enabled, "glow on")
	assert_gt(env.glow_hdr_threshold, 1.0, "white text and lit surfaces don't bloom")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_FILMIC)
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR)
	assert_eq(env.ambient_light_color, pal["ambient"])
	assert_gt(env.ambient_light_energy, 0.3, "high ambient light")
	assert_true(env.adjustment_enabled and env.adjustment_saturation > 1.0, "saturation boost")
	assert_true(env.fog_enabled)
	assert_false(ArtKit.make_environment(pal, false).fog_enabled)
	var we := ArtKit.make_world_environment(pal)
	assert_true(we.environment.glow_enabled)
	we.free()


# --- instances and hover -----------------------------------------------------

func test_outline_hover_toggles_every_mesh_without_new_materials() -> void:
	var root := Node3D.new()
	var a := Primitives.box(Vector3(1, 1, 1), Color.ORANGE, 0.0, 0.1)
	var b := Primitives.sphere(0.3, Color.ORANGE)
	var holder := Node3D.new()
	holder.add_child(b)
	root.add_child(a)
	root.add_child(holder)
	root.add_child(Primitives.label("PLAY"))
	tree.root.add_child(root)
	var cached := ArtKit.material_cache_size()
	assert_false(ArtKit.is_outline_hovered(root))
	ArtKit.set_outline_hover(root, true)
	assert_true(ArtKit.is_outline_hovered(root))
	assert_almost_eq(float(a.get_instance_shader_parameter(&"outline_hover")), 1.0)
	assert_almost_eq(float(b.get_instance_shader_parameter(&"outline_hover")), 1.0)
	assert_eq(b.get_instance_shader_parameter(&"outline_hover_color"), ArtKit.HOVER_COLOR)
	ArtKit.set_outline_hover(holder, true, Color.CYAN)
	assert_eq(b.get_instance_shader_parameter(&"outline_hover_color"), Color.CYAN)
	await tree.process_frame
	ArtKit.set_outline_hover(root, false)
	assert_false(ArtKit.is_outline_hovered(root))
	assert_almost_eq(float(b.get_instance_shader_parameter(&"outline_hover")), 0.0)
	assert_eq(ArtKit.material_cache_size(), cached, "hover never creates materials")
	assert_true(a.material_override == Primitives.material(Color.ORANGE), "still the shared material")
	root.queue_free()
	await tree.process_frame


func test_hard_edged_primitives_get_outline_modes() -> void:
	var box := Primitives.box(Vector3(1, 1, 1), Color.RED)
	var cyl := Primitives.cylinder(0.3, 1.0, Color.RED)
	var prism := Primitives.prism(Vector3(1, 1, 1), Color.RED)
	var round := Primitives.box(Vector3(1, 1, 1), Color.RED, 0.0, 0.1)
	assert_almost_eq(float(box.get_instance_shader_parameter(&"outline_mode")), MeshFactory.OUTLINE_BOX)
	assert_almost_eq(float(cyl.get_instance_shader_parameter(&"outline_mode")), MeshFactory.OUTLINE_CYLINDER)
	assert_almost_eq(float(prism.get_instance_shader_parameter(&"outline_mode")), MeshFactory.OUTLINE_BOX)
	assert_true(round.get_instance_shader_parameter(&"outline_mode") == null, "smooth meshes keep normal mode")
	assert_true(box.mesh is BoxMesh, "plain boxes are still BoxMesh")
	assert_true(round.mesh is ArrayMesh)
	for n: Node in [box, cyl, prism, round]:
		n.free()


func test_neon_level_is_per_instance() -> void:
	var a := ArtKit.mesh_instance(MeshFactory.pill(1.0, 0.03), ArtKit.neon_material(Color.MAGENTA))
	var b := ArtKit.mesh_instance(MeshFactory.pill(1.0, 0.03), ArtKit.neon_material(Color.MAGENTA))
	ArtKit.set_neon_level(a, 0.2)
	assert_almost_eq(float(a.get_instance_shader_parameter(&"neon_level")), 0.2)
	assert_true(b.get_instance_shader_parameter(&"neon_level") == null)
	assert_true(a.material_override == b.material_override)
	a.free()
	b.free()


# --- labels, signs and fonts -------------------------------------------------

func test_labels_use_display_font_with_thick_outline() -> void:
	var l := Primitives.label("SLOTS", 0.01, Color.WHITE)
	assert_true(l.font == ArtKit.display_font())
	assert_gte(l.outline_size, 10)
	assert_eq(l.outline_modulate, ArtKit.OUTLINE_COLOR)
	assert_eq(l.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
	var flat := Primitives.label("x", 0.01, Color.WHITE, false)
	assert_eq(flat.billboard, BaseMaterial3D.BILLBOARD_DISABLED)
	l.free()
	flat.free()


func test_floating_sign_fades_with_camera_distance() -> void:
	var root := Node3D.new()
	tree.root.add_child(root)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.make_current()
	var sign := ArtKit.floating_sign("SLOTS", 0.5)
	root.add_child(sign)
	assert_eq(sign.text, "SLOTS")
	assert_eq(sign.billboard, BaseMaterial3D.BILLBOARD_ENABLED)
	assert_almost_eq(sign.pixel_size * FloatingSign.SIGN_FONT_SIZE * 0.7, 0.5, 0.001)
	sign.position = Vector3(0, 0, -3)
	await tree.process_frame
	await tree.process_frame
	assert_almost_eq(sign.fade_alpha(), 1.0)
	assert_almost_eq(sign.modulate.a, 1.0, 0.01)
	sign.position = Vector3(0, 0, -(sign.fade_end + 5.0))
	await tree.process_frame
	await tree.process_frame
	assert_almost_eq(sign.fade_alpha(), 0.0)
	assert_almost_eq(sign.modulate.a, 0.0, 0.01)
	sign.position = Vector3(0, 0, -(sign.fade_start + sign.fade_end) * 0.5)
	assert_between(sign.fade_alpha(), 0.05, 0.95)
	root.queue_free()
	await tree.process_frame


func test_fonts_are_the_bundled_ones() -> void:
	var display := ArtKit.display_font()
	assert_true(display is FontFile, "Lilita One loaded")
	assert_true(display.get_font_name().contains("Lilita"), display.get_font_name())
	var body := ArtKit.body_font()
	assert_true(body.base_font is FontFile, "Fredoka loaded")
	assert_true(body.base_font.get_font_name().contains("Fredoka"), body.base_font.get_font_name())
	assert_false(body.variation_opentype.is_empty(), "weight set")
	assert_true(UiTheme.bold_font().base_font == body.base_font, "UI body text is Fredoka")
	assert_true(UiTheme.heavy_font().base_font == display, "UI display text is Lilita One")
	assert_true(UiTheme.make_theme().default_font == UiTheme.bold_font())


# --- shaders -----------------------------------------------------------------

func test_every_shader_loads_and_renders() -> void:
	for path: String in SHADERS:
		var shader := load(path) as Shader
		assert_true(shader != null, path)
		assert_true(shader.code.begins_with("//") and shader.code.contains("shader_type spatial"), path)
	var pal := ArtKit.palette_for(CasinoLadder.by_id(&"grand_marquee"))
	var root := Node3D.new()
	tree.root.add_child(root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1, 4)
	root.add_child(cam)
	cam.make_current()
	root.add_child(ArtKit.make_world_environment(pal))
	root.add_child(ArtKit.make_key_light(pal))
	root.add_child(ArtKit.neon_light(pal["neon_1"]))
	var materials: Array[Material] = [
		Primitives.material(Color.ORANGE), Primitives.material(Color(1, 1, 1, 0.5)),
		Primitives.material(Color.GREEN, 1.0, true), Primitives.material(Color(0, 1, 0, 0.3), 0.0, true),
		ArtKit.toon_material(Color.CYAN, 0.0, false, true, 0.6, true),
		ArtKit.carpet_for(pal), ArtKit.wall_for(pal), ArtKit.ceiling_for(pal),
		ArtKit.carpet_material([], ArtPalette.CARPET_STARS), ArtKit.carpet_material([], ArtPalette.CARPET_CONFETTI),
		ArtKit.felt_material(pal["felt"], pal["felt_border"], Vector2(0.5, 0.5), 0.1, 1),
		ArtKit.screen_material(), ArtKit.neon_material(pal["neon_2"], 2.0, 1.5),
		ArtKit.outline_material(Color.BLACK, 4.0),
	]
	for i in materials.size():
		var mi := ArtKit.mesh_instance(MeshFactory.rounded_box(Vector3(0.5, 0.5, 0.5), 0.1), materials[i])
		mi.position = Vector3(-3.0 + i * 0.5, 0.25, 0)
		root.add_child(mi)
	ArtKit.set_outline_hover(root, true)
	root.add_child(ArtKit.floating_sign("DICE"))
	for i in 4:
		await tree.process_frame
	# Camera, environment, two lights, the meshes and the sign.
	assert_eq(root.get_child_count(), 4 + materials.size() + 1)
	root.queue_free()
	await tree.process_frame


# --- helpers -----------------------------------------------------------------

func _assert_mesh_sane(mesh: ArrayMesh, label: String) -> void:
	assert_eq(mesh.get_surface_count(), 1, label)
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_gt(verts.size(), 0, label)
	assert_eq(normals.size(), verts.size(), label + " normals")
	assert_eq(uvs.size(), verts.size(), label + " uvs")
	assert_eq(indices.size() % 3, 0, label + " triangles")
	var bad := 0
	for n in normals:
		if absf(n.length() - 1.0) > 0.001:
			bad += 1
	assert_eq(bad, 0, label + " normals normalized")
	var out_of_range := 0
	for i in indices:
		if i < 0 or i >= verts.size():
			out_of_range += 1
	assert_eq(out_of_range, 0, label + " indices in range")


## +1 / -1: whether triangles' (b - a) x (c - a) points along or against
## their vertex normals (0 if mixed).
func _winding_sign(arrays: Array) -> int:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var along := 0
	var against := 0
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var cr := (verts[indices[t + 1]] - a).cross(verts[indices[t + 2]] - a)
		if cr.length() < 0.0000001:
			continue
		var d := cr.dot(normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]])
		if d > 0.0:
			along += 1
		else:
			against += 1
	if along > 0 and against == 0:
		return 1
	if against > 0 and along == 0:
		return -1
	return 0
