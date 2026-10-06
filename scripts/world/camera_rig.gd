class_name CameraRig
extends Node3D
## Third-person orbit camera for the local player: a SpringArm3D that pulls in
## against world geometry (layer 1), mouse look while the mouse is captured,
## gamepad right stick, and mouse-wheel zoom. top_level, so it follows its
## target smoothly instead of inheriting the body's transform.

const WORLD_MASK := 1

## The node it orbits. Uses target.camera_focus() when it has one.
var target: Node3D
## Orbit angles in radians. yaw 0 puts the camera at +Z looking toward -Z.
var yaw: float = 0.0
var pitch: float = deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_DEFAULT_DEGREES)
## Zoom the spring arm eases toward (metres).
var distance: float = Tuning.PLAYER_CAMERA_DISTANCE
var spring_arm: SpringArm3D
var camera: Camera3D

var _look_enabled := true


func _init() -> void:
	top_level = true
	spring_arm = SpringArm3D.new()
	spring_arm.name = "SpringArm"
	spring_arm.collision_mask = WORLD_MASK
	var probe := SphereShape3D.new()
	probe.radius = Tuning.PLAYER_CAMERA_COLLISION_RADIUS
	spring_arm.shape = probe
	spring_arm.spring_length = distance
	spring_arm.margin = 0.05
	add_child(spring_arm)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = Tuning.PLAYER_CAMERA_FOV
	camera.near = 0.05
	spring_arm.add_child(camera)
	_apply_angles()


func _ready() -> void:
	camera.make_current()
	snap()


## Starts following `follow`. Its collision body (if any) never blocks the arm.
func setup(follow: Node3D) -> void:
	target = follow
	if follow is CollisionObject3D:
		spring_arm.add_excluded_object((follow as CollisionObject3D).get_rid())
	if is_inside_tree():
		snap()


## Camera-relative movement frame: yaw only, so "forward" stays on the floor.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


## Turns the orbit by the given angles (radians); pitch is clamped.
func add_look(yaw_delta: float, pitch_delta: float) -> void:
	yaw = wrapf(yaw + yaw_delta, -PI, PI)
	pitch = clampf(pitch + pitch_delta, deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_MIN_DEGREES), deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_MAX_DEGREES))
	_apply_angles()


func zoom(amount: float) -> void:
	distance = clampf(distance + amount, Tuning.PLAYER_CAMERA_MIN_DISTANCE, Tuning.PLAYER_CAMERA_MAX_DISTANCE)


## Mouse look, stick look and wheel zoom on or off (off while UI panels are open).
func set_look_enabled(enabled: bool) -> void:
	_look_enabled = enabled


func is_look_enabled() -> bool:
	return _look_enabled


func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Jumps straight to the target with no easing (after a teleport).
func snap() -> void:
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		global_position = _focus_point()
	spring_arm.spring_length = distance
	_apply_angles()


func _unhandled_input(event: InputEvent) -> void:
	if not _look_enabled:
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		var rel: Vector2 = (event as InputEventMouseMotion).screen_relative
		var k := deg_to_rad(Tuning.PLAYER_CAMERA_MOUSE_DEGREES_PER_PIXEL)
		add_look(-rel.x * k, -rel.y * k)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom(-Tuning.PLAYER_CAMERA_ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom(Tuning.PLAYER_CAMERA_ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				if not is_mouse_captured():
					set_mouse_captured(true)
					get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _look_enabled:
		var stick := _right_stick()
		if stick != Vector2.ZERO:
			var rate := deg_to_rad(Tuning.PLAYER_CAMERA_STICK_DEGREES_PER_SECOND) * delta
			add_look(-stick.x * rate, -stick.y * rate)
	if target != null and is_instance_valid(target) and target.is_inside_tree():
		var goal := _focus_point()
		var w := 1.0 - exp(-Tuning.PLAYER_CAMERA_FOLLOW_SHARPNESS * delta)
		var wy := 1.0 - exp(-Tuning.PLAYER_CAMERA_FOLLOW_SHARPNESS_Y * delta)
		var p := global_position
		global_position = Vector3(lerpf(p.x, goal.x, w), lerpf(p.y, goal.y, wy), lerpf(p.z, goal.z, w))
	spring_arm.spring_length = lerpf(spring_arm.spring_length, distance, 1.0 - exp(-Tuning.PLAYER_CAMERA_ZOOM_SHARPNESS * delta))


func _focus_point() -> Vector3:
	if target.has_method(&"camera_focus"):
		return target.call(&"camera_focus")
	return target.global_position + Vector3.UP * Tuning.PLAYER_CAMERA_HEIGHT


func _apply_angles() -> void:
	rotation = Vector3(0.0, yaw, 0.0)
	spring_arm.rotation = Vector3(pitch, 0.0, 0.0)


## Strongest right-stick deflection over every connected pad, past the deadzone.
func _right_stick() -> Vector2:
	var best := Vector2.ZERO
	for device: int in Input.get_connected_joypads():
		var v := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if v.length() > best.length():
			best = v
	var dz := Tuning.INPUT_STICK_DEADZONE
	if best.length() <= dz:
		return Vector2.ZERO
	return best.normalized() * inverse_lerp(dz, 1.0, minf(best.length(), 1.0))
