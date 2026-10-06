class_name Lever3D
extends Pressable
## A slot-machine pull lever: a chrome hub, a chrome arm and a big glossy
## knob. Pressing it yanks the arm down toward the player (+Z) and it springs
## back with a wobble. `pressed` fires on the click, `pulled` when the arm
## bottoms out (start the reels then).
##
## Lever space: the pivot is the origin, the hub's axle runs along X, the arm
## points up (+Y) leaning back a little at rest.

## The arm reached the bottom of its pull.
signal pulled(user_pid: int)

const REST_DEGREES := -12.0
const PULL_SECONDS := 0.2
const HOLD_SECONDS := 0.06
const RETURN_SECONDS := 0.75

var length: float = 0.42
var knob_radius: float = 0.055
var knob_color: Color = DiegeticKit.KEY_RED
var pull_degrees: float = 105.0
var pull_count: int = 0
var pivot: Node3D
var arm: MeshInstance3D
var knob: MeshInstance3D
var hub: MeshInstance3D
var _tween: Tween


func setup(p_length: float = 0.42, p_knob_color: Color = DiegeticKit.KEY_RED, p_knob_radius: float = 0.055,
		p_id: StringName = &"lever") -> Lever3D:
	for c: Node in get_children():
		if c != shape:
			remove_child(c)
			c.queue_free()
	length = maxf(p_length, 0.1)
	knob_color = p_knob_color
	knob_radius = maxf(p_knob_radius, 0.02)
	id = p_id
	name = "Lever" if name == "" else name
	hint = "[LMB] PULL"
	hand_anim = &"pull"
	hub = Primitives.rounded_cylinder(0.05, 0.08, DiegeticKit.CHROME, 0.015, 20)
	hub.name = "Hub"
	hub.rotation.z = PI * 0.5
	add_child(hub)
	var cap := Primitives.rounded_cylinder(0.034, 0.02, knob_color, 0.008, 16)
	cap.name = "HubCap"
	cap.rotation.z = PI * 0.5
	cap.position.x = 0.048
	add_child(cap)
	pivot = Node3D.new()
	pivot.name = "Pivot"
	pivot.rotation.x = deg_to_rad(REST_DEGREES)
	add_child(pivot)
	arm = Primitives.rounded_cylinder(0.017, length, DiegeticKit.CHROME, 0.008, 12)
	arm.name = "Arm"
	arm.position.y = length * 0.5
	pivot.add_child(arm)
	var collar := Primitives.rounded_cylinder(0.026, 0.03, DiegeticKit.CHROME.darkened(0.15), 0.01, 14)
	collar.name = "Collar"
	collar.position.y = length - 0.015
	pivot.add_child(collar)
	knob = ArtKit.mesh_instance(MeshFactory.ball(knob_radius, 5), DiegeticKit.key_material(knob_color, 0.25))
	knob.name = "Knob"
	knob.position.y = length + knob_radius * 0.8
	pivot.add_child(knob)
	glow_root = pivot
	var reach := length + knob_radius * 1.8
	set_box_shape(Vector3(knob_radius * 2.4, reach, knob_radius * 2.4), Vector3.ZERO)
	shape.position = Basis(Vector3.RIGHT, deg_to_rad(REST_DEGREES)) * Vector3(0.0, reach * 0.5, 0.0)
	shape.rotation.x = deg_to_rad(REST_DEGREES)
	return self


func aim_point() -> Vector3:
	return knob.global_position if knob != null and knob.is_inside_tree() else position + Vector3(0.0, length, 0.0)


func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## The current pull, 0 at rest to 1 at the bottom.
func pull_amount() -> float:
	if pivot == null:
		return 0.0
	return clampf((rad_to_deg(pivot.rotation.x) - REST_DEGREES) / pull_degrees, 0.0, 1.0)


func _on_press(user_pid: int) -> void:
	pull_count += 1
	if pivot == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		pulled.emit(user_pid)
		return
	var rest := deg_to_rad(REST_DEGREES)
	var bottom := deg_to_rad(REST_DEGREES + pull_degrees)
	_tween = create_tween()
	_tween.tween_property(pivot, "rotation:x", bottom, PULL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: pulled.emit(user_pid))
	_tween.tween_interval(HOLD_SECONDS)
	_tween.tween_property(pivot, "rotation:x", rest, RETURN_SECONDS).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
