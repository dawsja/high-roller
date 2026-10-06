class_name Interactable
extends Area3D
## Something a player can use: a sphere on physics layer 5 that players find
## with their own detector. Purely a trigger: use() emits `used` and the
## director decides what it means (sit, cash out, tear a poster, ...).

signal used(user: Node3D, interactable: Interactable)

## Physics layer 5 (interactable) as a bit value.
const LAYER_BIT := 16

## &"table", &"cashier", &"restroom", &"gift_shop", &"forger", &"poster",
## &"tray", &"fire_alarm", &"laundry_cart", &"staff_locker", &"exit", &"slot_alarm".
var kind: StringName = &""
## Text for the "press E to ..." hint.
var prompt: String = ""
## Kind-specific payload, e.g. {table_id} or {poster_id}.
var data: Dictionary = {}
## 0 = press; otherwise the player holds interact this long (interact_held).
var hold_seconds: float = 0.0
## A disabled interactable ignores use() and is hidden from player detectors.
var enabled: bool = true: set = set_enabled

var shape: CollisionShape3D


func _init() -> void:
	collision_layer = LAYER_BIT
	collision_mask = 0
	monitoring = false
	monitorable = true
	shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Tuning.INTERACT_RADIUS
	shape.shape = sphere
	add_child(shape)


## A ready-made interactable; position it yourself.
static func create(p_kind: StringName, p_prompt: String, radius: float = Tuning.INTERACT_RADIUS, p_data: Dictionary = {}, p_hold_seconds: float = 0.0) -> Interactable:
	var it := Interactable.new()
	it.kind = p_kind
	it.prompt = p_prompt
	it.data = p_data.duplicate()
	it.hold_seconds = p_hold_seconds
	it.set_radius(radius)
	it.name = "Interactable_%s" % String(p_kind)
	return it


func set_radius(radius: float) -> void:
	(shape.shape as SphereShape3D).radius = maxf(0.05, radius)


func get_radius() -> float:
	return (shape.shape as SphereShape3D).radius


func set_enabled(value: bool) -> void:
	enabled = value
	# monitorable can't change while physics is flushing area callbacks.
	if is_inside_tree():
		set_deferred(&"monitorable", value)
	else:
		monitorable = value


## Emits `used` (only while enabled).
func use(user: Node3D) -> void:
	if not enabled:
		return
	used.emit(user, self)
