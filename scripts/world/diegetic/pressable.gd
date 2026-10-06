class_name Pressable
extends StaticBody3D
## Anything on a machine you press with your hands: a StaticBody3D on physics
## layer 5 (bit 16, mask 0) with its own CollisionShape3D. The first-person
## player ray-casts against layer 5 and duck-types it (has_method(&"press")):
## hint / enabled / hold_seconds, get_hint(), set_hovered(), press(pid) and
## hold_complete(pid). Hovering lights the HoverGlow outline on `glow_root`.
##
## Subclasses override _on_press / _on_hold / _on_hover; `pressed` and `held`
## fire after them. A disabled pressable ignores presses (the player's ray
## still stops on it) and shows no hover glow.

signal pressed(user_pid: int)
signal held(user_pid: int)
signal hover_changed(hovered: bool)

## Physics layer 5 (interactable / pressable) as a bit value.
const LAYER_BIT := 16

## What the player's hint label shows, e.g. "[LMB] PLAY".
var hint: String = "[LMB] Press"
var enabled: bool = true: set = set_enabled
## 0 = a click; otherwise LMB / E must be held this long (hold_complete).
var hold_seconds: float = 0.0
## Hand animation the player plays on a press (FirstPersonHands.ANIMS).
var hand_anim: StringName = &"press"
## Optional id (keys use it: &"main", &"7", &"cash_out"...).
var id: StringName = &""
var hovered: bool = false
## The node whose meshes glow on hover (defaults to this body).
var glow_root: Node3D = null
var shape: CollisionShape3D


func _init() -> void:
	collision_layer = LAYER_BIT
	collision_mask = 0
	shape = CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.05, 0.05)
	shape.shape = box
	add_child(shape)


## Sets the press target to a box of `size` centred at `center` (local).
func set_box_shape(size: Vector3, center: Vector3 = Vector3.ZERO) -> void:
	var box := BoxShape3D.new()
	box.size = size.abs().max(Vector3(0.005, 0.005, 0.005))
	shape.shape = box
	shape.position = center


func get_hint() -> String:
	return hint


func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not value and hovered:
		set_hovered(false)
	_on_enabled_changed(value)


func set_hovered(value: bool) -> void:
	if not enabled:
		value = false
	if value == hovered:
		return
	hovered = value
	HoverGlow.apply(glow_root if glow_root != null else self, value)
	_on_hover(value)
	hover_changed.emit(value)


## A click (or E) from player `user_pid`; ignored while disabled.
func press(user_pid: int) -> void:
	if not enabled:
		return
	_on_press(user_pid)
	pressed.emit(user_pid)


## LMB / E held for hold_seconds by `user_pid`; ignored while disabled.
func hold_complete(user_pid: int) -> void:
	if not enabled:
		return
	_on_hold(user_pid)
	held.emit(user_pid)


## World position to aim at to press this (bots, the hands' reach target).
func aim_point() -> Vector3:
	return shape.global_position if is_inside_tree() else position + shape.position


func _on_press(_user_pid: int) -> void:
	pass


func _on_hold(_user_pid: int) -> void:
	pass


func _on_hover(_value: bool) -> void:
	pass


func _on_enabled_changed(_value: bool) -> void:
	pass
