class_name VisionCone
extends MeshInstance3D
## A flat translucent fan that shows what a guard or camera can see: apex at
## the origin, opening along local -Z, `reach` long and `fov_degrees` wide.
## Place it just above the floor. clip() shortens each ray at the first wall
## so the fan stops where sight does.

## Rays across the fan (the mesh has SEGMENTS + 1 rim points).
const SEGMENTS := 18
## Alpha at the apex and at the rim; the tint's alpha multiplies both.
const APEX_ALPHA := 1.0
const RIM_ALPHA := 0.25
## A ray must change by more than this before the mesh is rebuilt.
const CLIP_EPSILON := 0.05

static var _materials: Dictionary = {}

var reach: float = Tuning.VISION_RANGE
var fov_degrees: float = Tuning.VISION_FOV_DEGREES
## Current tint (alpha included). Use set_color().
var color: Color = Color(0.3, 0.95, 0.4, 0.22)

var _lengths: PackedFloat32Array = PackedFloat32Array()
var _array_mesh: ArrayMesh


func _init(cone_reach: float = Tuning.VISION_RANGE, cone_fov_degrees: float = Tuning.VISION_FOV_DEGREES, tint: Color = Color(0.3, 0.95, 0.4, 0.22)) -> void:
	name = "VisionCone"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_array_mesh = ArrayMesh.new()
	mesh = _array_mesh
	color = tint
	material_override = _material_for(tint)
	set_shape(cone_reach, cone_fov_degrees)


func set_color(tint: Color) -> void:
	if tint == color:
		return
	color = tint
	material_override = _material_for(tint)


## Changes the fan's length and angle; forgets any wall clipping.
func set_shape(cone_reach: float, cone_fov_degrees: float) -> void:
	reach = maxf(cone_reach, 0.01)
	fov_degrees = clampf(cone_fov_degrees, 1.0, 360.0)
	_lengths.resize(SEGMENTS + 1)
	_lengths.fill(reach)
	_rebuild()


## Local direction of ray `i` (0 = the left edge seen from behind, SEGMENTS = right).
func ray_direction(i: int) -> Vector3:
	var half := deg_to_rad(fov_degrees) * 0.5
	var a := lerpf(half, -half, float(i) / float(SEGMENTS))
	return Vector3(-sin(a), 0.0, -cos(a))


## Current length of ray `i` after clipping.
func ray_length(i: int) -> float:
	return _lengths[clampi(i, 0, SEGMENTS)]


## The shortest ray (reach when nothing is in the way).
func min_ray_length() -> float:
	var shortest := reach
	for l: float in _lengths:
		shortest = minf(shortest, l)
	return shortest


## Casts every ray horizontally from `ray_height` above the apex against
## `mask` and cuts it at the first hit. Needs the node in the tree.
func clip(space: PhysicsDirectSpaceState3D, ray_height: float, mask: int = 1) -> void:
	if space == null or not is_inside_tree():
		return
	var origin := global_position + Vector3.UP * ray_height
	var frame := global_basis.orthonormalized()
	var changed := false
	for i in SEGMENTS + 1:
		var dir := frame * ray_direction(i)
		dir.y = 0.0
		if dir.length_squared() < 0.000001:
			continue
		dir = dir.normalized()
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, mask)
		var hit := space.intersect_ray(query)
		var length := reach
		if not hit.is_empty():
			var hit_pos: Vector3 = hit["position"]
			length = Vector2(hit_pos.x - origin.x, hit_pos.z - origin.z).length()
		if absf(length - _lengths[i]) > CLIP_EPSILON:
			_lengths[i] = length
			changed = true
	if changed:
		_rebuild()


func _rebuild() -> void:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	colors.append(Color(1, 1, 1, APEX_ALPHA))
	for i in SEGMENTS + 1:
		verts.append(ray_direction(i) * _lengths[i])
		colors.append(Color(1, 1, 1, RIM_ALPHA))
	for i in SEGMENTS:
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	_array_mesh.clear_surfaces()
	_array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _material_for(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html(true)
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	mat.disable_receive_shadows = true
	_materials[key] = mat
	return mat
