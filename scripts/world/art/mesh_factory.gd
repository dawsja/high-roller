class_name MeshFactory
extends RefCounted
## Procedural toy-like meshes: rounded boxes, pills, bevelled cylinders,
## lathed blobs, rings, wedges and extruded 2D shapes (stars, lightning bolts,
## triangles) plus neon "stroke" tubes that trace them.
##
## Every mesh is cached by its parameters and shared, so never set a material
## on the returned mesh: color each MeshInstance3D with material_override (or
## use Primitives.mesh_instance / ArtKit.mesh_instance). Meshes with hard edges
## carry `outline_mode` metadata that those helpers pass to the outline shader.

## Mesh metadata key read by Primitives.mesh_instance (see outline.gdshader).
const META_OUTLINE_MODE := &"outline_mode"
const OUTLINE_SMOOTH := 0
const OUTLINE_BOX := 1
const OUTLINE_CYLINDER := 2

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func cache_size() -> int:
	return _cache.size()


## Box with rounded edges and corners (smooth normals, 0..1 UVs per face).
## `radius` is clamped to half the smallest side; 0 gives a plain box.
## `segments` is the number of steps around each rounded edge's quarter.
static func rounded_box(size: Vector3, radius: float = 0.05, segments: int = 3) -> ArrayMesh:
	size = size.abs()
	var r := clampf(radius, 0.0, minf(size.x, minf(size.y, size.z)) * 0.5)
	if r < 0.0005:
		r = 0.0
	segments = clampi(segments, 1, 16)
	var key := "rbox|%.4f|%.4f|%.4f|%.4f|%d" % [size.x, size.y, size.z, r, segments]
	if _cache.has(key):
		return _cache[key]
	var half := size * 0.5
	var inner := half - Vector3(r, r, r)
	var coords: Array[PackedFloat32Array] = []
	for axis in 3:
		coords.append(_rounded_coords(half[axis], inner[axis], r, segments))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# Each face: outward normal, the axis U runs along (+ direction) and the axis V runs along.
	var faces: Array = [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
	]
	for face: Array in faces:
		var n: Vector3 = face[0]
		var du: Vector3 = face[1]
		var dv: Vector3 = face[2]
		var nu := _axis_of(du)
		var nv := _axis_of(dv)
		var nn := _axis_of(n)
		var cu: PackedFloat32Array = coords[nu]
		var cv: PackedFloat32Array = coords[nv]
		var base := verts.size()
		for j in cv.size():
			for i in cu.size():
				var p := Vector3.ZERO
				p[nn] = half[nn] * signf(n[nn])
				p[nu] = cu[i]
				p[nv] = cv[j]
				var clamped := p.clamp(-inner, inner)
				var d := p - clamped
				var normal := n if r == 0.0 else d.normalized()
				verts.append(clamped + normal * r if r > 0.0 else p)
				normals.append(normal)
				var u := (cu[i] * signf(du[nu]) + half[nu]) / (2.0 * half[nu]) if half[nu] > 0.0 else 0.0
				var v := (cv[j] * signf(dv[nv]) + half[nv]) / (2.0 * half[nv]) if half[nv] > 0.0 else 0.0
				uvs.append(Vector2(u, v))
		_grid_indices(indices, base, cu.size(), cv.size())
	var mesh := _commit(verts, normals, uvs, indices)
	_cache[key] = mesh
	return mesh


## A capsule lying along X: total `length` (>= 2 * radius) and `radius`.
static func pill(length: float, radius: float, segments: int = 4) -> ArrayMesh:
	var r := maxf(radius, 0.001)
	return rounded_box(Vector3(maxf(length, 2.0 * r), 2.0 * r, 2.0 * r), r, segments)


## A sphere built from a rounded cube (even triangles, no pole pinching).
static func ball(radius: float, segments: int = 4) -> ArrayMesh:
	var r := maxf(radius, 0.001)
	return rounded_box(Vector3(2.0 * r, 2.0 * r, 2.0 * r), r, segments)


## Upright capsule (Godot's CapsuleMesh), cached.
static func capsule(radius: float, height: float, radial_segments: int = 16, rings: int = 6) -> CapsuleMesh:
	var key := "capsule|%.4f|%.4f|%d|%d" % [radius, height, radial_segments, rings]
	if _cache.has(key):
		return _cache[key]
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	_cache[key] = mesh
	return mesh


## Upright cylinder whose top and bottom edges are rounded by `bevel`
## (chips, buttons, table rims, stools). Smooth normals.
static func rounded_cylinder(radius: float, height: float, bevel: float = 0.02, sides: int = 24, bevel_segments: int = 3) -> ArrayMesh:
	var b := clampf(bevel, 0.0, minf(radius, height * 0.5))
	var key := "rcyl|%.4f|%.4f|%.4f|%d|%d" % [radius, height, b, sides, bevel_segments]
	if _cache.has(key):
		return _cache[key]
	var h := height * 0.5
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	pts.append(Vector2(0.0, -h))
	nrm.append(Vector2(0.0, -1.0))
	if b > 0.0:
		for k in bevel_segments + 1:
			var a := -PI * 0.5 + PI * 0.5 * float(k) / float(bevel_segments)
			var dir := Vector2(cos(a), sin(a))
			pts.append(Vector2(radius - b, -h + b) + dir * b)
			nrm.append(dir)
		for k in bevel_segments + 1:
			var a := PI * 0.5 * float(k) / float(bevel_segments)
			var dir := Vector2(cos(a), sin(a))
			pts.append(Vector2(radius - b, h - b) + dir * b)
			nrm.append(dir)
	else:
		# Hard edges: duplicate the rim points with cap and side normals.
		pts.append_array(PackedVector2Array([Vector2(radius, -h), Vector2(radius, -h), Vector2(radius, h), Vector2(radius, h)]))
		nrm.append_array(PackedVector2Array([Vector2(0, -1), Vector2(1, 0), Vector2(1, 0), Vector2(0, 1)]))
	pts.append(Vector2(0.0, h))
	nrm.append(Vector2(0.0, 1.0))
	var mesh := _lathe_mesh(pts, nrm, sides)
	if b <= 0.0:
		mesh.set_meta(META_OUTLINE_MODE, OUTLINE_CYLINDER)
	_cache[key] = mesh
	return mesh


## Spins a profile around Y. `points` are (radius, height), listed from the
## bottom up (bottom centre -> rim -> top centre for a closed solid). Normals
## come from the profile (averaged at shared points when `smooth`).
static func lathe(points: PackedVector2Array, sides: int = 24, smooth: bool = true) -> ArrayMesh:
	var key := "lathe|%s|%d|%s" % [str(points), sides, smooth]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector2Array()
	var nrm := PackedVector2Array()
	var count := points.size()
	for i in count:
		var prev_n := Vector2.ZERO
		var next_n := Vector2.ZERO
		if i > 0:
			var t := points[i] - points[i - 1]
			prev_n = Vector2(t.y, -t.x).normalized()
		if i < count - 1:
			var t := points[i + 1] - points[i]
			next_n = Vector2(t.y, -t.x).normalized()
		if smooth or i == 0 or i == count - 1:
			pts.append(points[i])
			var n := prev_n + next_n
			nrm.append(n.normalized() if n.length() > 0.0001 else (prev_n if prev_n != Vector2.ZERO else next_n))
		else:
			pts.append(points[i])
			nrm.append(prev_n)
			pts.append(points[i])
			nrm.append(next_n)
	var mesh := _lathe_mesh(pts, nrm, sides)
	_cache[key] = mesh
	return mesh


## A rounded body for cartoon creatures: `height` tall from y = 0, widest
## `bottom_radius` low down, narrowing to `top_radius` near the top
## (equal radii: a bean; small top: a pear).
static func blob(height: float, bottom_radius: float, top_radius: float, sides: int = 24, rings: int = 14) -> ArrayMesh:
	var key := "blob|%.4f|%.4f|%.4f|%d|%d" % [height, bottom_radius, top_radius, sides, rings]
	if _cache.has(key):
		return _cache[key]
	var pts := PackedVector2Array()
	for i in rings + 1:
		# Ease the samples toward the poles so the caps stay round.
		var t := (1.0 - cos(PI * float(i) / float(rings))) * 0.5
		var base := lerpf(bottom_radius, top_radius, smoothstep(0.25, 0.85, t))
		var r := base * pow(maxf(sin(PI * t), 0.0), 0.62)
		pts.append(Vector2(r, t * height))
	var mesh := lathe(pts, sides, true)
	_cache[key] = mesh
	return mesh


## Godot TorusMesh, cached (rings, neon hoops, wheel rims).
static func torus(inner_radius: float, outer_radius: float, rings: int = 32, ring_segments: int = 12) -> TorusMesh:
	var key := "torus|%.4f|%.4f|%d|%d" % [inner_radius, outer_radius, rings, ring_segments]
	if _cache.has(key):
		return _cache[key]
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = rings
	mesh.ring_segments = ring_segments
	_cache[key] = mesh
	return mesh


## A flat quad facing +Z with 0..1 UVs (screens, plaques), cached.
static func quad(size: Vector2) -> QuadMesh:
	var key := "quad|%.4f|%.4f" % [size.x, size.y]
	if _cache.has(key):
		return _cache[key]
	var mesh := QuadMesh.new()
	mesh.size = size
	_cache[key] = mesh
	return mesh


## Sloped console block: `size` box whose top slopes from full height at the
## back (-Z) down to `front_ratio` of it at the front (+Z). Optional bevel.
static func wedge(size: Vector3, front_ratio: float = 0.35, bevel: float = 0.0) -> ArrayMesh:
	var key := "wedge|%.4f|%.4f|%.4f|%.4f|%.4f" % [size.x, size.y, size.z, front_ratio, bevel]
	if _cache.has(key):
		return _cache[key]
	var h := size.y * 0.5
	var d := size.z * 0.5
	# Profile in (z, y), extruded along X.
	var poly := PackedVector2Array([
		Vector2(-d, -h), Vector2(d, -h), Vector2(d, -h + size.y * clampf(front_ratio, 0.0, 1.0)), Vector2(-d, h),
	])
	if front_ratio <= 0.001:
		poly.remove_at(2)
	var arrays := _extrude_arrays(poly, size.x, bevel)
	# Extruded along +Z with the profile in XY: swap X and Z.
	var basis := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(1, 0, 0))
	var mesh := _commit_arrays(_transform_arrays(arrays, basis))
	mesh.set_meta(META_OUTLINE_MODE, OUTLINE_BOX)
	_cache[key] = mesh
	return mesh


## Extrudes a 2D polygon (XY, any winding, no holes) `depth` along Z,
## centred on z = 0, with an optional chamfer `bevel` on the front and back.
static func extrude(polygon: PackedVector2Array, depth: float, bevel: float = 0.0) -> ArrayMesh:
	var key := "extrude|%s|%.4f|%.4f" % [str(polygon), depth, bevel]
	if _cache.has(key):
		return _cache[key]
	var mesh := _commit_arrays(_extrude_arrays(polygon, depth, bevel))
	mesh.set_meta(META_OUTLINE_MODE, OUTLINE_BOX)
	_cache[key] = mesh
	return mesh


## A flat ribbon of `width` and `depth` tracing a polyline in XY (a neon tube
## bent into a shape). Closed by default.
static func stroke(points: PackedVector2Array, width: float, depth: float = 0.03, closed: bool = true) -> ArrayMesh:
	var key := "stroke|%s|%.4f|%.4f|%s" % [str(points), width, depth, closed]
	if _cache.has(key):
		return _cache[key]
	var pts := _ccw(points) if closed else points
	var offs := _miter_offsets(pts, closed)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var hw := width * 0.5
	var hz := depth * 0.5
	var count := pts.size()
	var seg_count := count if closed else count - 1
	for s in seg_count:
		var i0 := s
		var i1 := (s + 1) % count
		var a := pts[i0]
		var b := pts[i1]
		var oa := Vector3(a.x, a.y, 0.0) + Vector3(offs[i0].x, offs[i0].y, 0.0) * hw
		var ob := Vector3(b.x, b.y, 0.0) + Vector3(offs[i1].x, offs[i1].y, 0.0) * hw
		var ia := Vector3(a.x, a.y, 0.0) - Vector3(offs[i0].x, offs[i0].y, 0.0) * hw
		var ib := Vector3(b.x, b.y, 0.0) - Vector3(offs[i1].x, offs[i1].y, 0.0) * hw
		var t := (b - a).normalized()
		var out := Vector3(t.y, -t.x, 0.0)
		var front := Vector3(0, 0, hz)
		_quad(verts, normals, uvs, indices, ia + front, oa + front, ob + front, ib + front, Vector3(0, 0, 1))
		_quad(verts, normals, uvs, indices, ib - front, ob - front, oa - front, ia - front, Vector3(0, 0, -1))
		_quad(verts, normals, uvs, indices, oa + front, oa - front, ob - front, ob + front, out)
		_quad(verts, normals, uvs, indices, ib + front, ib - front, ia - front, ia + front, -out)
	var mesh := _commit(verts, normals, uvs, indices)
	mesh.set_meta(META_OUTLINE_MODE, OUTLINE_BOX)
	_cache[key] = mesh
	return mesh


## Five-ish pointed star: filled (stroke_width 0) or as a neon outline.
static func star(outer_radius: float, inner_radius: float, points: int = 5, depth: float = 0.04, stroke_width: float = 0.0) -> ArrayMesh:
	var poly := star_points(outer_radius, inner_radius, points)
	return stroke(poly, stroke_width, depth) if stroke_width > 0.0 else extrude(poly, depth)


## Lightning bolt `height` tall: filled or as a neon outline.
static func bolt(height: float, depth: float = 0.04, stroke_width: float = 0.0) -> ArrayMesh:
	var poly := bolt_points(height)
	return stroke(poly, stroke_width, depth) if stroke_width > 0.0 else extrude(poly, depth)


## Equilateral triangle with sides `size`, point up: filled or as a neon outline.
static func triangle(size: float, depth: float = 0.04, stroke_width: float = 0.0) -> ArrayMesh:
	var poly := triangle_points(size)
	return stroke(poly, stroke_width, depth) if stroke_width > 0.0 else extrude(poly, depth)


static func star_points(outer_radius: float, inner_radius: float, points: int = 5) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(points, 3)
	for i in n * 2:
		var a := PI * 0.5 + PI * float(i) / float(n)
		var r := outer_radius if i % 2 == 0 else inner_radius
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## An original zig-zag bolt, centred, `height` tall.
static func bolt_points(height: float) -> PackedVector2Array:
	var unit := PackedVector2Array([
		Vector2(0.05, 0.5), Vector2(0.37, 0.5), Vector2(0.13, 0.07), Vector2(0.32, 0.07),
		Vector2(-0.22, -0.5), Vector2(-0.02, -0.07), Vector2(-0.21, -0.07),
	])
	var out := PackedVector2Array()
	for p in unit:
		out.append((p - Vector2(0.075, 0.0)) * height)
	return out


static func triangle_points(size: float) -> PackedVector2Array:
	var r := size / sqrt(3.0)
	var out := PackedVector2Array()
	for i in 3:
		var a := PI * 0.5 + TAU * float(i) / 3.0
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


# --- internals ---------------------------------------------------------------

## Coordinates along one axis of a rounded box face: tan-spaced steps through
## each rounded edge (even angles once projected) and one flat span between.
static func _rounded_coords(half: float, inner: float, r: float, segments: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if r <= 0.0:
		out.append(-half)
		out.append(half)
		return out
	for k in range(segments, 0, -1):
		out.append(-(inner + r * tan(PI * 0.25 * float(k) / float(segments))))
	out.append(-inner)
	if inner > 0.0005:
		out.append(inner)
	for k in range(1, segments + 1):
		out.append(inner + r * tan(PI * 0.25 * float(k) / float(segments)))
	return out


static func _axis_of(v: Vector3) -> int:
	var a := v.abs()
	if a.x >= a.y and a.x >= a.z:
		return 0
	return 1 if a.y >= a.z else 2


static func _grid_indices(indices: PackedInt32Array, base: int, nu: int, nv: int) -> void:
	for j in nv - 1:
		for i in nu - 1:
			var i00 := base + j * nu + i
			var i01 := i00 + nu
			indices.append_array(PackedInt32Array([i00, i00 + 1, i01 + 1, i00, i01 + 1, i01]))


static func _lathe_mesh(pts: PackedVector2Array, nrm: PackedVector2Array, sides: int) -> ArrayMesh:
	sides = maxi(sides, 3)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var total := 0.0
	var lengths := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		lengths.append(total)
	var rows := pts.size()
	for s in sides + 1:
		var a := TAU * float(s) / float(sides)
		var ca := cos(a)
		var sa := sin(a)
		for i in rows:
			var p := pts[i]
			var n := nrm[i]
			verts.append(Vector3(p.x * ca, p.y, p.x * sa))
			normals.append(Vector3(n.x * ca, n.y, n.x * sa).normalized())
			uvs.append(Vector2(float(s) / float(sides), 1.0 - (lengths[i] / total if total > 0.0 else 0.0)))
	for s in sides:
		for i in rows - 1:
			var a0 := s * rows + i
			var a1 := a0 + 1
			var b0 := (s + 1) * rows + i
			var b1 := b0 + 1
			if pts[i].distance_to(pts[i + 1]) < 0.000001:
				continue
			indices.append_array(PackedInt32Array([a0, a1, b1, a0, b1, b0]))
	return _commit(verts, normals, uvs, indices)


static func _extrude_arrays(polygon: PackedVector2Array, depth: float, bevel: float) -> Array:
	var poly := _ccw(polygon)
	var count := poly.size()
	var hz := depth * 0.5
	var b := clampf(bevel, 0.0, hz * 0.9)
	var inset := poly
	if b > 0.0:
		var offs := _miter_offsets(poly, true)
		inset = PackedVector2Array()
		for i in count:
			inset.append(poly[i] - offs[i] * b)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var tris := Geometry2D.triangulate_polygon(inset)
	var bounds := Rect2(inset[0], Vector2.ZERO)
	for p in inset:
		bounds = bounds.expand(p)
	for side in [1.0, -1.0]:
		var base := verts.size()
		for p in inset:
			verts.append(Vector3(p.x, p.y, hz * side))
			normals.append(Vector3(0, 0, side))
			uvs.append((p - bounds.position) / bounds.size.max(Vector2(0.0001, 0.0001)))
		for t in tris:
			indices.append(base + t)
	for i in count:
		var j := (i + 1) % count
		var t := (poly[j] - poly[i]).normalized()
		var out := Vector3(t.y, -t.x, 0.0)
		var pi := Vector3(poly[i].x, poly[i].y, 0.0)
		var pj := Vector3(poly[j].x, poly[j].y, 0.0)
		var zf := hz - b
		_quad(verts, normals, uvs, indices, pi + Vector3(0, 0, zf), pi - Vector3(0, 0, zf), pj - Vector3(0, 0, zf), pj + Vector3(0, 0, zf), out)
		if b > 0.0:
			var ii := Vector3(inset[i].x, inset[i].y, 0.0)
			var ij := Vector3(inset[j].x, inset[j].y, 0.0)
			var nf := (out + Vector3(0, 0, 1)).normalized()
			var nb := (out + Vector3(0, 0, -1)).normalized()
			_quad(verts, normals, uvs, indices, ii + Vector3(0, 0, hz), pi + Vector3(0, 0, zf), pj + Vector3(0, 0, zf), ij + Vector3(0, 0, hz), nf)
			_quad(verts, normals, uvs, indices, pi - Vector3(0, 0, zf), ii - Vector3(0, 0, hz), ij - Vector3(0, 0, hz), pj - Vector3(0, 0, zf), nb)
	return [verts, normals, uvs, indices]


## Adds a quad a-b-c-d with a flat normal (_commit fixes the winding).
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var base := verts.size()
	verts.append_array(PackedVector3Array([a, b, c, d]))
	for k in 4:
		normals.append(normal)
	uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## The polygon wound counter-clockwise (Y up).
static func _ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for i in poly.size():
		var j := (i + 1) % poly.size()
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	if area < 0.0:
		var rev := poly.duplicate()
		rev.reverse()
		return rev
	return poly


## Per-point outward miter directions (length 1 / cos of the half angle, capped)
## for a counter-clockwise polygon or an open polyline.
static func _miter_offsets(pts: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := pts.size()
	for i in count:
		var has_prev := closed or i > 0
		var has_next := closed or i < count - 1
		var n_prev := Vector2.ZERO
		var n_next := Vector2.ZERO
		if has_prev:
			var t := (pts[i] - pts[(i - 1 + count) % count]).normalized()
			n_prev = Vector2(t.y, -t.x)
		if has_next:
			var t := (pts[(i + 1) % count] - pts[i]).normalized()
			n_next = Vector2(t.y, -t.x)
		if not has_prev:
			out.append(n_next)
			continue
		if not has_next:
			out.append(n_prev)
			continue
		var m := (n_prev + n_next)
		if m.length() < 0.0001:
			out.append(n_prev)
			continue
		m = m.normalized()
		var cos_half := maxf(m.dot(n_next), 0.4)
		out.append(m / cos_half)
	return out


static func _transform_arrays(arrays: Array, basis: Basis) -> Array:
	var verts: PackedVector3Array = arrays[0]
	var normals: PackedVector3Array = arrays[1]
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for v in verts:
		out_v.append(basis * v)
	for n in normals:
		out_n.append((basis * n).normalized())
	return [out_v, out_n, arrays[2], arrays[3]]


static func _commit_arrays(arrays: Array) -> ArrayMesh:
	return _commit(arrays[0], arrays[1], arrays[2], arrays[3])


## Builds the mesh, first winding every triangle so its front face agrees
## with its vertex normals (Godot culls counter-clockwise back faces).
static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var cr := (verts[indices[t + 1]] - a).cross(verts[indices[t + 2]] - a)
		var n := normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]
		if cr.dot(n) > 0.0:
			var tmp := indices[t + 1]
			indices[t + 1] = indices[t + 2]
			indices[t + 2] = tmp
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
