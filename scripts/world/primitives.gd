class_name Primitives
extends RefCounted
## Toon building blocks: primitive meshes with cached toon materials (cel
## bands, rim light and a dark purple inverted-hull outline). See ArtKit for
## pattern / neon / screen materials and MeshFactory for rounded shapes.
## Materials are cached per parameters, so a whole casino shares a handful.


## Cached toon material (a ShaderMaterial on assets/shaders/toon*.gdshader).
## Alpha below 1 makes it see-through without an outline; `outline` false
## drops the outline pass (walls, floors, decals).
static func material(color: Color, emission: float = 0.0, unshaded: bool = false, outline: bool = true) -> ShaderMaterial:
	return ArtKit.toon_material(color, emission, unshaded, outline)


## The albedo color of a material from here or a StandardMaterial3D
## (Color(0, 0, 0, 0) for anything else).
static func material_color(mat: Material) -> Color:
	if mat is ShaderMaterial:
		var v: Variant = (mat as ShaderMaterial).get_shader_parameter(&"albedo")
		if v is Color:
			return v
	elif mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color
	return Color(0, 0, 0, 0)


## A box. With `radius` > 0 its edges are rounded (MeshFactory.rounded_box).
static func box(size: Vector3, color: Color, emission: float = 0.0, radius: float = 0.0) -> MeshInstance3D:
	if radius > 0.0:
		return mesh_instance(MeshFactory.rounded_box(size, radius), color, emission)
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


## Cylinder with rounded top and bottom edges (chips, buttons, stools).
static func rounded_cylinder(radius: float, height: float, color: Color, bevel: float = 0.02, sides: int = 24, emission: float = 0.0) -> MeshInstance3D:
	return mesh_instance(MeshFactory.rounded_cylinder(radius, height, bevel, sides), color, emission)


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
	mesh.radial_segments = 12
	mesh.rings = 3
	return _instance(mesh, color)


## A capsule lying along X (big rounded buttons, rails, pegs).
static func pill(length: float, radius: float, color: Color, emission: float = 0.0) -> MeshInstance3D:
	return mesh_instance(MeshFactory.pill(length, radius), color, emission)


static func prism(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _instance(mesh, color)


## Any mesh with a toon material as its override. Hard-edged meshes (boxes,
## prisms, cylinders, MeshFactory extrusions) get the matching outline mode.
static func mesh_instance(mesh: Mesh, color: Color, emission: float = 0.0, outline: bool = true) -> MeshInstance3D:
	return ArtKit.mesh_instance(mesh, material(color, emission, false, outline))


## A Label3D in the Lilita One display font with a thick dark outline.
static func label(text: String, pixel_size: float = 0.01, color: Color = Color.WHITE, billboard: bool = true) -> Label3D:
	return ArtKit.make_label(text, pixel_size, color, 48, billboard)


## A solid box with matching collision on the given physics layer (world by
## default); `radius` > 0 rounds the visible box (the collision stays a box).
static func static_box(size: Vector3, color: Color, layer: int = 1, radius: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	body.add_child(box(size, color, 0.0, radius))
	return body


static func _instance(mesh: PrimitiveMesh, color: Color, emission: float = 0.0) -> MeshInstance3D:
	mesh.material = material(color, emission)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mode := ArtKit.outline_mode_for(mesh)
	if mode != MeshFactory.OUTLINE_SMOOTH:
		ArtKit.set_outline_mode(mi, mode)
	return mi
