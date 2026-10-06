class_name CameraRig
extends Node3D
## First-person head for the local player: a child of the player body at eye
## height. Yaw turns this node, pitch turns `pivot`, and the Camera3D under it
## carries the head bob, landing dip, lunges and roll as local offsets that
## the player feeds it (set_motion, set_effect, land). Mouse look while the
## mouse is captured (`mouse_sensitivity` degrees per pixel), gamepad right
## stick. set_follow() pins the view to a base heading (carried over a guard's
## shoulder) with mouse look as a clamped offset on top.
##
## The old third-person rig's API stays (yaw, pitch, flat_basis, add_look,
## snap, camera, set_look_enabled, set_mouse_captured; zoom and distance are
## no-ops), so existing callers keep working. camera.v_offset / h_offset are
## held at 0: a first-person view never shifts its projection.

## Every look change from input, in radians (the hands sway with it).
signal looked(yaw_delta: float, pitch_delta: float)
## A footstep landed (the head at the bottom of its bob) while walking/running.
signal footstep(running: bool)

const PITCH_LIMIT := FpTuning.PITCH_LIMIT_DEGREES * PI / 180.0

## Settings every new rig starts with (a new one is built each visit): a
## settings menu sets these once, and mouse_sensitivity / invert_y on a live rig.
static var default_mouse_sensitivity: float = FpTuning.MOUSE_DEGREES_PER_PIXEL
static var default_invert_y: bool = false

## The body it rides on (the player). Only used for snap().
var target: Node3D
## Look angles in radians. yaw 0 looks toward -Z; pitch > 0 looks up. While
## following (set_follow) yaw is the offset from the followed heading.
var yaw: float = 0.0
var pitch: float = 0.0
## Unused in first person (kept for old callers).
var distance: float = 0.0
var pivot: Node3D
var camera: Camera3D
## Hands under the camera (local player only); the rig drives their bob/sway.
var hands: Node3D
## Mouse look speed, degrees per pixel of mouse motion.
var mouse_sensitivity: float = FpTuning.MOUSE_DEGREES_PER_PIXEL
var stick_degrees_per_second: float = FpTuning.STICK_DEGREES_PER_SECOND
var invert_y: bool = false
## Local position the head eases to (eye height, the carry offset...).
var head_target: Vector3 = Vector3(0.0, FpTuning.EYE_HEIGHT, 0.0)
var base_fov: float = FpTuning.FOV

var _look_enabled := true
var _following := false
var _follow_yaw := 0.0
var _swallowed_click := false
var _phase := 0.0
var _bob := 0.0
var _bob_goal := 0.0
var _speed := 0.0
var _running := false
var _grounded := true
var _offset := Vector3.ZERO
var _offset_goal := Vector3.ZERO
var _pitch_fx := 0.0
var _pitch_fx_goal := 0.0
var _roll := 0.0
var _roll_goal := 0.0
var _dip := 0.0
var _dip_speed := 0.0
var _fov_bonus := 0.0


func _init() -> void:
	name = "CameraRig"
	mouse_sensitivity = default_mouse_sensitivity
	invert_y = default_invert_y
	position = head_target
	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = base_fov
	camera.near = FpTuning.NEAR
	camera.cull_mask = camera.cull_mask & ~FpTuning.SELF_BODY_LAYER
	pivot.add_child(camera)
	_apply_angles()


func _ready() -> void:
	camera.make_current()
	snap()


## Remembers the body it rides on (kept from the third-person rig's API).
func setup(follow: Node3D) -> void:
	target = follow
	if is_inside_tree():
		snap()


## Movement frame: the look heading only, so "forward" stays on the floor.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, view_yaw())


## World heading of the view (radians, 0 = -Z), following or not.
func view_yaw() -> float:
	return wrapf(_follow_yaw + yaw, -PI, PI) if _following else yaw


## Where the view looks: the camera's -Z in world space.
func look_direction() -> Vector3:
	if camera.is_inside_tree():
		return -camera.global_basis.z
	return Basis.from_euler(Vector3(pitch, view_yaw(), 0.0)) * Vector3.FORWARD


## The eye in world space (without bob or effects when out of the tree).
func eye_position() -> Vector3:
	if camera.is_inside_tree():
		return camera.global_position
	return position


## Turns the view by the given angles (radians); pitch is clamped to
## ±PITCH_LIMIT, and yaw to ±CARRIED_LOOK_LIMIT while following.
func add_look(yaw_delta: float, pitch_delta: float) -> void:
	if _following:
		var limit := deg_to_rad(FpTuning.CARRIED_LOOK_LIMIT_DEGREES)
		yaw = clampf(yaw + yaw_delta, -limit, limit)
	else:
		yaw = wrapf(yaw + yaw_delta, -PI, PI)
	pitch = clampf(pitch + pitch_delta, -PITCH_LIMIT, PITCH_LIMIT)
	_apply_angles()


## Mouse motion in screen pixels (what _unhandled_input feeds; tests too).
func apply_mouse_motion(relative: Vector2) -> void:
	var k := deg_to_rad(mouse_sensitivity)
	var dy := relative.y if invert_y else -relative.y
	var before := Vector2(yaw, pitch)
	add_look(-relative.x * k, dy * k)
	looked.emit(yaw - before.x, pitch - before.y)


## Points the view at a world point (bots, cut-ins, sitting down).
func look_toward(point: Vector3) -> void:
	var to := point - eye_position()
	if to.length_squared() < 0.0001:
		return
	var heading := atan2(-to.x, -to.z)
	var flat := Vector2(to.x, to.z).length()
	pitch = clampf(atan2(to.y, flat), -PITCH_LIMIT, PITCH_LIMIT)
	yaw = wrapf(heading - _follow_yaw, -PI, PI) if _following else heading
	_apply_angles()


## Pins the view to `base_yaw` (radians); yaw becomes a clamped look offset.
## Call it every frame while the base heading moves.
func set_follow(base_yaw: float) -> void:
	if not _following:
		_following = true
		yaw = 0.0
	_follow_yaw = base_yaw
	_apply_angles()


## Back to free look, keeping the current view heading.
func clear_follow() -> void:
	if not _following:
		return
	var heading := view_yaw()
	_following = false
	yaw = heading
	_apply_angles()


func is_following() -> bool:
	return _following


## The third-person zoom; a no-op in first person.
func zoom(_amount: float) -> void:
	pass


## Mouse look and stick look on or off (off while UI panels are open).
func set_look_enabled(enabled: bool) -> void:
	_look_enabled = enabled


func is_look_enabled() -> bool:
	return _look_enabled


func set_mouse_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## True once after a left click only re-captured the mouse (the player must
## not also press what it looks at).
func consume_swallowed_click() -> bool:
	var was := _swallowed_click
	_swallowed_click = false
	return was


## Walking speed (m/s), on the floor or not, running or not: drives the bob
## and the run FOV. Call every physics frame.
func set_motion(speed: float, grounded: bool, running: bool) -> void:
	_speed = speed
	_grounded = grounded
	_running = running
	_bob_goal = clampf(speed / Tuning.PLAYER_WALK_SPEED, 0.0, 1.0) if grounded else 0.0
	if running and speed > Tuning.PLAYER_WALK_SPEED + 0.5:
		_bob_goal *= 1.3


## Extra offset (camera-local metres), pitch and roll (radians) the head eases
## to: dives, tackles, tumbles, the carried wobble. Zero when nothing plays.
func set_effect(offset: Vector3, pitch_offset: float = 0.0, roll: float = 0.0) -> void:
	_offset_goal = offset
	_pitch_fx_goal = pitch_offset
	_roll_goal = roll


## A landing at `fall_speed` m/s: the head dips and springs back.
func land(fall_speed: float) -> void:
	var depth := minf(absf(fall_speed) * FpTuning.LAND_DIP_PER_SPEED, FpTuning.LAND_DIP_MAX)
	# Peak dip of a spring kicked at v0 is about v0 / 16 with these constants.
	_dip_speed -= depth * 16.0


## 0..1 bob strength right now, and the footstep phase (a step every PI).
func bob_weight() -> float:
	return _bob


func step_phase() -> float:
	return _phase


## Current head-bob + effect offset of the camera (camera parent space).
func camera_offset() -> Vector3:
	return camera.position


## Jumps straight to the targets with no easing (after a teleport).
func snap() -> void:
	position = head_target
	_offset = _offset_goal
	_pitch_fx = _pitch_fx_goal
	_roll = _roll_goal
	_dip = 0.0
	_dip_speed = 0.0
	_bob = _bob_goal
	_apply_angles()
	_apply_camera()


func _unhandled_input(event: InputEvent) -> void:
	if not _look_enabled:
		return
	if event is InputEventMouseMotion and is_mouse_captured():
		apply_mouse_motion((event as InputEventMouseMotion).screen_relative)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not is_mouse_captured():
			set_mouse_captured(true)
			_swallowed_click = true
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _look_enabled:
		var stick := _right_stick()
		if stick != Vector2.ZERO:
			var rate := deg_to_rad(stick_degrees_per_second) * delta
			var before := Vector2(yaw, pitch)
			add_look(-stick.x * rate, (stick.y if invert_y else -stick.y) * rate)
			looked.emit(yaw - before.x, pitch - before.y)
	var k_eye := 1.0 - exp(-FpTuning.EYE_SHARPNESS * delta)
	position = position.lerp(head_target, k_eye)
	var k_fx := 1.0 - exp(-FpTuning.EFFECT_SHARPNESS * delta)
	_offset = _offset.lerp(_offset_goal, k_fx)
	_pitch_fx = lerpf(_pitch_fx, _pitch_fx_goal, k_fx)
	_roll = lerpf(_roll, _roll_goal, k_fx)
	_bob = lerpf(_bob, _bob_goal, 1.0 - exp(-FpTuning.BOB_SHARPNESS * delta))
	# The landing dip is a damped spring back to 0.
	_dip_speed += (-FpTuning.LAND_SPRING * _dip - FpTuning.LAND_DAMPING * _dip_speed) * delta
	_dip = clampf(_dip + _dip_speed * delta, -FpTuning.LAND_DIP_MAX, FpTuning.LAND_DIP_MAX * 0.5)
	_advance_steps(delta)
	var fov_goal := FpTuning.RUN_FOV_BONUS if _running and _speed > Tuning.PLAYER_WALK_SPEED + 0.5 else 0.0
	_fov_bonus = lerpf(_fov_bonus, fov_goal, 1.0 - exp(-FpTuning.FOV_SHARPNESS * delta))
	_apply_camera()
	if hands != null and hands.has_method(&"set_locomotion"):
		hands.call(&"set_locomotion", _phase, _bob)


func _advance_steps(delta: float) -> void:
	if not _grounded or _speed < 0.3:
		return
	var run_t := clampf((_speed - Tuning.PLAYER_WALK_SPEED) / maxf(0.01, Tuning.PLAYER_RUN_SPEED - Tuning.PLAYER_WALK_SPEED), 0.0, 1.0)
	var step := lerpf(FpTuning.STEP_WALK, FpTuning.STEP_RUN, run_t)
	var before := floori(_phase / PI)
	_phase += _speed * delta * PI / step
	if floori(_phase / PI) != before:
		footstep.emit(run_t > 0.5)
	if _phase > TAU * 64.0:
		_phase -= TAU * 64.0


func _apply_angles() -> void:
	rotation = Vector3(0.0, view_yaw(), 0.0)
	pivot.rotation = Vector3(pitch, 0.0, 0.0)


func _apply_camera() -> void:
	var w := _bob
	var bob := Vector3(
		cos(_phase) * FpTuning.BOB_SIDE * w,
		-(1.0 - absf(sin(_phase))) * FpTuning.BOB_HEIGHT * w + FpTuning.BOB_HEIGHT * 0.5 * w,
		0.0)
	camera.position = bob + _offset + Vector3(0.0, _dip, 0.0)
	camera.rotation = Vector3(_pitch_fx, 0.0, _roll + cos(_phase) * deg_to_rad(FpTuning.BOB_ROLL_DEGREES) * w)
	camera.fov = base_fov + _fov_bonus
	camera.v_offset = 0.0
	camera.h_offset = 0.0


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
