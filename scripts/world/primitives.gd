class_name Primitives
extends RefCounted
## Graybox building blocks: low-poly primitive meshes with flat colors.
## Materials are cached per color so a whole casino shares a handful of them.

static var _materials: Dictionary = {}


static func material(color: Color, emission: float = 0.0, unshaded: bool = false) -> StandardMaterial3D:
	var key := "%s|%.2f|%s" % [color.to_html(), emission, unshaded]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials[key] = mat
	return mat


static func box(size: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, color, emission)


static func cylinder(radius: float, height: float, color: Color, sides: int = 10, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = sides
	mesh.rings = 1
	return _instance(mesh, color)


static func sphere(radius: float, color: Color, segments: int = 8, emission: float = 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = maxi(3, segments / 2)
	return _instance(mesh, color, emission)


static func capsule(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 2
	return _instance(mesh, color)


static func prism(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _instance(mesh, color)


static func label(text: String, pixel_size: float = 0.01, color: Color = Color.WHITE, billboard: bool = true) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = pixel_size
	l.modulate = color
	l.outline_size = 8
	l.font_size = 48
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


## A solid box with matching collision on the given physics layer (world by default).
static func static_box(size: Vector3, color: Color, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(box(size, color))
	return body


static func _instance(mesh: PrimitiveMesh, color: Color, emission: float = 0.0) -> MeshInstance3D:
	mesh.material = material(color, emission)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi
