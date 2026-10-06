class_name Dice3D
extends RigidBody3D
## A chunky rounded die with glowing round pips on all six faces (opposite
## faces add up to 7). It is a RigidBody3D that starts frozen (static,
## animated by tweens); set_physics_mode(true) lets it fly for a real throw.
## set_face_up() orients it instantly, settle_to() rolls it smoothly onto a
## value keeping its heading, roll_to() plays a scripted tumble across the
## table that lands on a value (the same on every peer).
##
## Die space: centred on the origin, `size` metres on a side; face 1 is +Y,
## 6 is -Y, 2 is +Z, 5 is -Z, 3 is +X, 4 is -X.

signal settled(value: int)

const FACE_NORMALS := {
	1: Vector3.UP, 6: Vector3.DOWN, 2: Vector3.BACK, 5: Vector3.FORWARD, 3: Vector3.RIGHT, 4: Vector3.LEFT,
}
## Pip spots per face on a face's (u, v) grid, -1..1.
const PIPS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-1, -1), Vector2(1, 1)],
	3: [Vector2(-1, -1), Vector2(0, 0), Vector2(1, 1)],
	4: [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)],
	5: [Vector2(-1, -1), Vector2(1, -1), Vector2(0, 0), Vector2(-1, 1), Vector2(1, 1)],
	6: [Vector2(-1, -1), Vector2(-1, 0), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1)],
}
const BODY_COLOR := Color("ff2e63")
const PIP_COLOR := Color("ffe1f3")

var size: float = 0.09
var body_color: Color = BODY_COLOR
var pip_color: Color = PIP_COLOR
var physics_mode: bool = false: set = set_physics_mode
var visual: Node3D
var collision: CollisionShape3D
var _tween: Tween
var _target_value: int = 0


func _init() -> void:
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 0
	collision_mask = 1
	mass = 0.05
	can_sleep = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.35
	pm.friction = 0.7
	physics_material_override = pm


func setup(p_size: float = 0.09, p_body_color: Color = BODY_COLOR, p_pip_color: Color = PIP_COLOR) -> Dice3D:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	size = maxf(p_size, 0.01)
	body_color = p_body_color
	pip_color = p_pip_color
	if name == "":
		name = "Die"
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	var cube := ArtKit.mesh_instance(MeshFactory.rounded_box(Vector3.ONE * size, size * 0.2, 3), DiegeticKit.key_material(body_color))
	cube.name = "Cube"
	visual.add_child(cube)
	var pip_mesh := MeshFactory.rounded_cylinder(size * 0.095, size * 0.05, size * 0.02, 16, 2)
	var pip_mat := ArtKit.toon_material(pip_color, 0.6, false, false)
	for value: int in FACE_NORMALS:
		var n: Vector3 = FACE_NORMALS[value]
		var axes := _face_axes(n)
		for spot: Vector2 in PIPS[value]:
			var pip := ArtKit.mesh_instance(pip_mesh, pip_mat)
			pip.name = "Pip%d" % value
			var p: Vector3 = n * (size * 0.5 - size * 0.012) + (axes[0] * spot.x + axes[1] * spot.y) * size * 0.25
			pip.transform = Transform3D(_basis_up_to(n), p)
			visual.add_child(pip)
	collision = CollisionShape3D.new()
	collision.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * size
	collision.shape = box
	add_child(collision)
	return self


## Frozen (false, tween-animated) or a free rigid body (true).
func set_physics_mode(on: bool) -> void:
	physics_mode = on
	if on:
		_kill()
	freeze = not on


## Throws the die as a rigid body (physics mode on).
func throw(impulse: Vector3, torque: Vector3 = Vector3.ZERO) -> void:
	set_physics_mode(true)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	apply_central_impulse(impulse)
	if torque != Vector3.ZERO:
		apply_torque_impulse(torque)


## The value on the face pointing most upward right now.
func up_face() -> int:
	return face_up_of(_world_basis())


## The value facing up for a die with basis `b`.
static func face_up_of(b: Basis) -> int:
	var best := 1
	var best_dot := -INF
	for value: int in FACE_NORMALS:
		var d := (b * (FACE_NORMALS[value] as Vector3)).normalized().dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best = value
	return best


## A basis with `value` up and the die turned `yaw` radians about +Y.
static func face_up_basis(value: int, yaw: float = 0.0) -> Basis:
	var n: Vector3 = FACE_NORMALS.get(clampi(value, 1, 6), Vector3.UP)
	return Basis(Vector3.UP, yaw) * Basis(Quaternion(n, Vector3.UP)) if n != Vector3.DOWN \
			else Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI)


## The smallest rotation of `from` that puts `value` up: it turns about a
## level axis, so the die keeps its heading (yaw).
static func settled_basis(from: Basis, value: int) -> Basis:
	var n: Vector3 = FACE_NORMALS.get(clampi(value, 1, 6), Vector3.UP)
	var r := from.orthonormalized()
	var world_n := (r * n).normalized()
	var d := world_n.dot(Vector3.UP)
	var q: Quaternion
	if d > 0.99999:
		q = Quaternion.IDENTITY
	elif d < -0.99999:
		var axis := Vector3(world_n.z, 0.0, -world_n.x)
		if axis.length() < 0.001:
			axis = (r * _face_axes(n)[0])
			axis.y = 0.0
		if axis.length() < 0.001:
			axis = Vector3.RIGHT
		q = Quaternion(axis.normalized(), PI)
	else:
		q = Quaternion(world_n.cross(Vector3.UP).normalized(), acos(clampf(d, -1.0, 1.0)))
	return (Basis(q) * r).orthonormalized()


## Instantly turns the die so `value` faces up, keeping its heading.
func set_face_up(value: int) -> void:
	_kill()
	_set_world_basis(settled_basis(_world_basis(), value))


## Rolls the die smoothly onto `value` in `seconds` (a small hop on the way),
## keeping its heading; emits `settled` at the end. Leaves physics mode.
func settle_to(value: int, seconds: float = 0.35, hop: float = -1.0) -> void:
	set_physics_mode(false)
	_target_value = clampi(value, 1, 6)
	var from := _world_basis().orthonormalized()
	var to := settled_basis(from, _target_value)
	if not is_inside_tree() or seconds <= 0.0:
		_set_world_basis(to)
		settled.emit(_target_value)
		return
	var h := size * 0.6 if hop < 0.0 else hop
	var base := global_position
	_tween = create_tween()
	_tween.tween_method(_settle_step.bind(from.get_rotation_quaternion(), to.get_rotation_quaternion(), base, h), 0.0, 1.0, seconds)
	_tween.tween_callback(_emit_settled)


## A scripted throw: tumbles from where it is to `target` (global, the die's
## centre at rest) over `seconds`, bouncing `bounces` times, and lands with
## `value` up. Deterministic for the same inputs.
func roll_to(value: int, target: Vector3, seconds: float = 1.1, bounces: int = 2, spins: float = 2.5) -> void:
	set_physics_mode(false)
	_target_value = clampi(value, 1, 6)
	var start := global_position if is_inside_tree() else position
	var travel := target - start
	travel.y = 0.0
	var axis := Vector3(travel.z, 0.0, -travel.x).normalized() if travel.length() > 0.001 else Vector3.RIGHT
	var yaw := atan2(travel.x, travel.z) if travel.length() > 0.001 else 0.0
	var final := face_up_basis(_target_value, yaw)
	if not is_inside_tree() or seconds <= 0.0:
		position = target
		_set_world_basis(final)
		settled.emit(_target_value)
		return
	var from_q := _world_basis().orthonormalized().get_rotation_quaternion()
	_tween = create_tween()
	_tween.tween_method(_roll_step.bind(start, target, from_q, final.get_rotation_quaternion(), axis, spins, bounces), 0.0, 1.0, seconds)
	_tween.tween_callback(_emit_settled)


func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## Snaps a running settle / roll to its end (emits settled).
func finish() -> void:
	if _tween != null and _tween.is_valid():
		_tween.custom_step(1000.0)
		_tween.kill()
	_tween = null


func _settle_step(t: float, from_q: Quaternion, to_q: Quaternion, base: Vector3, h: float) -> void:
	var k := smoothstep(0.0, 1.0, t)
	_set_world_basis(Basis(from_q.slerp(to_q, k)))
	global_position = base + Vector3.UP * sin(t * PI) * h


func _roll_step(t: float, start: Vector3, target: Vector3, from_q: Quaternion, to_q: Quaternion, axis: Vector3, spins: float, bounces: int) -> void:
	var travel_t := 1.0 - pow(1.0 - t, 2.2)
	var p := start.lerp(target, travel_t)
	# Hops that shrink: the first leg is the throw arc, then smaller bounces.
	var legs := bounces + 1
	var leg := minf(floorf(t * float(legs)), float(legs - 1))
	var lt := t * float(legs) - leg
	var height := size * 3.0 * pow(0.42, leg)
	var arc := sin(lt * PI) * height
	p.y = lerpf(start.y, target.y, travel_t) + arc
	var spin := (1.0 - travel_t) * spins * TAU
	var landing := Basis(to_q)
	var tumble := Basis(axis, spin) * landing
	var blend := smoothstep(0.0, 0.25, t)
	var q := from_q.slerp(tumble.get_rotation_quaternion(), blend)
	_set_world_basis(Basis(q))
	if is_inside_tree():
		global_position = p
	else:
		position = p


func _emit_settled() -> void:
	settled.emit(_target_value)


func _world_basis() -> Basis:
	return global_basis if is_inside_tree() else basis


func _set_world_basis(b: Basis) -> void:
	if is_inside_tree():
		global_basis = b.orthonormalized()
	else:
		basis = b.orthonormalized()


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## Two unit axes spanning the face with normal `n`.
static func _face_axes(n: Vector3) -> Array[Vector3]:
	var u := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
	var v := n.cross(u).normalized()
	return [u, v]


## A basis whose +Y is `n` (pips are discs standing on their +Y).
static func _basis_up_to(n: Vector3) -> Basis:
	if n.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	if n.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(Vector3.UP, n))
