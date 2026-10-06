class_name CasinoZone
extends Area3D
## A named part of the casino (HR.ZoneType + area_id) made of one or more
## boxes. Watches physics layer 2 (players) and emits `player_entered` when a
## player is now standing in this zone.
##
## Zones nest and touch: a forger corner sits inside the restroom, the whole
## main floor sits under the game areas. Inside a CasinoMap the map decides
## which zone a player counts as being in (highest `zone_priority`, then the most
## recently entered) and makes only that zone emit, also when the player
## steps back out of a nested zone. A zone outside any map emits on every
## body_entered.

signal player_entered(player: Node3D, zone: CasinoZone)

## Physics layer 2 (player) as a bit value.
const PLAYER_BIT := 2
## Zones reach this high above the floor (and a bit below it).
const HEIGHT := 3.5

var zone_type: int = HR.ZoneType.FLOOR
var area_id: StringName = &""
## Higher wins where zones overlap (main floor 0, rooms and game areas 1,
## forger corners and the exit pad 2).
var zone_priority: int = 1
## True while a CasinoMap decides when this zone emits.
var managed: bool = false


func _init() -> void:
	collision_layer = 0
	collision_mask = PLAYER_BIT
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


static func create(p_zone_type: int, p_area_id: StringName, p_priority: int = 1) -> CasinoZone:
	var zone := CasinoZone.new()
	zone.zone_type = p_zone_type
	zone.area_id = p_area_id
	zone.zone_priority = p_priority
	zone.name = "Zone_%s_%s" % [str(HR.ZoneType.find_key(p_zone_type)), String(p_area_id)]
	return zone


## Adds a box covering a floor rectangle (Rect2 in the XZ plane, map space;
## the zone itself should sit at the origin). Returns the shape.
func add_rect(rect: Rect2) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(rect.size.x, HEIGHT, rect.size.y)
	shape.shape = box
	var c: Vector2 = rect.get_center()
	shape.position = Vector3(c.x, HEIGHT * 0.5 - 0.5, c.y)
	add_child(shape)
	return shape


## The floor rectangles this zone covers (Rect2 in XZ, map space).
func rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for child: Node in get_children():
		var cs := child as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var size: Vector3 = (cs.shape as BoxShape3D).size
		var p: Vector3 = position + cs.position
		out.append(Rect2(p.x - size.x * 0.5, p.z - size.z * 0.5, size.x, size.z))
	return out


## True if the floor point (map space XZ) is inside one of the boxes.
func contains_point(point: Vector3) -> bool:
	for r: Rect2 in rects():
		if r.has_point(Vector2(point.x, point.z)):
			return true
	return false


## Total floor area covered (m²); smaller zones are the more specific ones.
func floor_area() -> float:
	var total := 0.0
	for r: Rect2 in rects():
		total += r.get_area()
	return total


## Emits player_entered for this zone (CasinoMap calls this).
func announce(player: Node3D) -> void:
	player_entered.emit(player, self)


func _on_body_entered(body: Node3D) -> void:
	if not managed:
		announce(body)
