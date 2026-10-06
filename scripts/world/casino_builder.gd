class_name CasinoBuilder
extends RefCounted
## Builds the graybox CasinoMap for any Tuning.CASINOS row from a
## CasinoLayouts plan: floors, walls with doorways, room props, game areas
## with table anchors, the street lot, parking garage and loading dock, zones,
## interactables, poster boards, lights, and every point the director needs.
## Colors come from the casino's palette (floor/wall/accent); `seed_value`
## varies decor and picks patrol routes. Static geometry is StaticBody3D boxes
## on physics layer 1 under the map's NavigationRegion3D.

const WORLD_LAYER := 1
const T := Tuning.CASINO_WALL_THICKNESS
const H := Tuning.CASINO_WALL_HEIGHT
## Underside of the pendant lamps over the tables.
const LAMP_Y := 2.45
## Height of the billboard signs over the game areas.
const AREA_SIGN_Y := 2.75
const DOOR_H := Tuning.CASINO_DOOR_HEIGHT
const FENCE_H := Tuning.CASINO_FENCE_HEIGHT
const G := CasinoLayouts.GRID
## Overlays (room floors, carpets) sit in this band above the slab top (y = 0).
const OVERLAY_Y := 0.01
const PATTERN_Y := 0.026

## Door sign text and which side it faces (+1: +Z / +X, -1: -Z / -X).
const DOOR_SIGNS := {
	&"security": ["SECURITY", 1],
	&"staff": ["STAFF ONLY", 1],
	&"restroom": ["RESTROOMS", 1],
	&"cage": ["CAGE", -1],
	&"dock": ["LOADING DOCK", 1],
	&"gift_shop": ["GIFT SHOP", -1],
	&"back_room": ["HOLDING", 1],
	&"entrance": ["EXIT", -1],
}
const AREA_TITLES := {
	&"pit_a": "PIT A", &"pit_b": "PIT B", &"pit_c": "PIT C", &"pit_d": "PIT D",
	&"high_limit": "HIGH LIMIT", &"wheel_stage": "WHEEL STAGE",
}
## Per casino: outside ground, street and background colors.
const OUTSIDE := {
	&"apex": {"sidewalk": Color("8d93a1"), "street": Color("2a2f3a"), "sky": Color("141a33")},
	&"grand_marquee": {"sidewalk": Color("a39a8c"), "street": Color("26252b"), "sky": Color("180d22")},
	&"riverboat_queen": {"sidewalk": Color("8b6b4a"), "street": Color("1f4f66"), "sky": Color("0f1d2b")},
	&"neon_oasis": {"sidewalk": Color("9c96a8"), "street": Color("2b2533"), "sky": Color("241036")},
	&"rusty_spur": {"sidewalk": Color("b08d5f"), "street": Color("8a6a45"), "sky": Color("2e1f16")},
	&"sals_back_room": {"sidewalk": Color("8a8c86"), "street": Color("2c2d2b"), "sky": Color("0e1012")},
}
const CONCRETE := Color("8c8c88")
const CONCRETE_DARK := Color("6b6b68")
const STEEL := Color("4a4f57")
const WOOD := Color("6b4428")
const WOOD_DARK := Color("3f2716")
const WHITE := Color("ececec")
const PAINT_YELLOW := Color("f2c230")
const PLANT := Color("2f7a3c")
const SCREEN := Color("5fd3ff")
const RED := Color("d0312d")
const GLASS := Color(0.75, 0.9, 1.0, 0.35)
const CAR_COLORS := [Color("c0392b"), Color("2e86de"), Color("27ae60"), Color("8e44ad"), Color("d35400"), Color("7f8c8d")]

var _casino: Dictionary = {}
var _plan: Dictionary = {}
var _r: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _map: CasinoMap
var _static: Node3D
var _decor: Node3D
var _floor_c: Color
var _wall_c: Color
var _accent_c: Color
var _rung: int = Tuning.BOTTOM_RUNG
var _x0: float
var _x1: float
var _z0: float
var _fd: float
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}


## Builds the map for a Tuning.CASINOS row. Add it to the tree, then call
## bake_navigation() on it.
static func build(casino: Dictionary, seed_value: int) -> CasinoMap:
	return CasinoBuilder.new()._build(casino, seed_value)


func _build(casino: Dictionary, seed_value: int) -> CasinoMap:
	_casino = casino.duplicate(true)
	_rng.seed = seed_value
	_rung = int(casino.get("rung", Tuning.BOTTOM_RUNG))
	_floor_c = casino.get("floor_color", Color("3d4a3a"))
	_wall_c = casino.get("wall_color", Color("8a8f7a"))
	_accent_c = casino.get("accent_color", Color("d6c98f"))
	_plan = CasinoLayouts.plan(casino)
	_r = _plan["rects"]
	_x0 = _plan["x0"]
	_x1 = _plan["x1"]
	_z0 = _plan["z0"]
	_fd = _plan["front_depth"]

	_map = CasinoMap.new()
	_map.name = "CasinoMap_%s" % String(casino.get("id", &"casino"))
	_map.casino = _casino
	_map.size_class = _plan["size"]
	var lot: Rect2 = _r["lot"]
	var dock: Rect2 = _r["dock"]
	_map.bounds = AABB(Vector3(_x0, 0.0, dock.position.y), Vector3(_plan["w"], H, lot.end.y - dock.position.y))

	_map.nav_region = NavigationRegion3D.new()
	_map.nav_region.name = "Navigation"
	_map.nav_region.navigation_mesh = _make_navmesh()
	_map.add_child(_map.nav_region)
	_static = Node3D.new()
	_static.name = "Static"
	_map.nav_region.add_child(_static)
	_map.props_root = Node3D.new()
	_map.props_root.name = "Props"
	_map.nav_region.add_child(_map.props_root)
	_decor = Node3D.new()
	_decor.name = "Decor"
	_map.add_child(_decor)

	_build_floors()
	_build_walls()
	_build_outside()
	_build_back_of_house()
	_build_front_band()
	_build_game_blocks()
	_build_zones()
	_build_points()
	_build_lighting()
	return _map


# --- navigation ---------------------------------------------------------------

func _make_navmesh() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = WORLD_LAYER
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.cell_size = Tuning.NAV_CELL_SIZE
	nm.cell_height = Tuning.NAV_CELL_SIZE
	# Recast works in whole voxels and rounds these up anyway (with a warning).
	nm.agent_radius = ceilf(Tuning.NAV_AGENT_RADIUS / nm.cell_size - 0.001) * nm.cell_size
	nm.agent_height = ceilf(Tuning.NAV_AGENT_HEIGHT / nm.cell_height - 0.001) * nm.cell_height
	nm.agent_max_climb = nm.cell_height
	# Drop little islands on top of furniture and cars.
	nm.region_min_size = 8.0
	return nm


# --- floors -------------------------------------------------------------------

func _build_floors() -> void:
	var outside: Dictionary = OUTSIDE.get(_casino.get("id", &""), OUTSIDE[&"sals_back_room"])
	_slab(Rect2(_x0, _z0, _plan["w"], _plan["d"]), _floor_c)
	var sidewalk: Rect2 = _r["sidewalk"]
	var garage: Rect2 = _r["garage"]
	_slab(sidewalk, outside["sidewalk"])
	_slab(Rect2(_x0, sidewalk.end.y, garage.position.x - _x0, garage.size.y), outside["street"])
	_slab(garage, CONCRETE_DARK)
	_slab(_r["dock"], CONCRETE)

	var concrete: Color = _floor_c.lerp(CONCRETE, 0.7)
	for key: String in ["corridor", "passage", "back_room", "security"]:
		_overlay(_r[key], concrete)
	_overlay(_r["cashier"], _accent_c.lerp(WHITE, 0.6))
	_overlay(_r["restroom"], Color("c9d6dc"))
	_overlay(_r["gift_shop"], _accent_c.lerp(WHITE, 0.45))
	_overlay(_r["bar"], WOOD)
	_checker(_r["buffet"], _floor_c.lerp(WHITE, 0.55), _floor_c.lerp(WHITE, 0.3), 2.0)
	var lobby: Rect2 = _r["lobby"]
	_overlay(lobby, _floor_c.lerp(WHITE, 0.25))
	var runner := Rect2(_plan["door_x"] - 1.5, lobby.position.y, 3.0, lobby.size.y)
	_pattern_box(runner.grow(-0.05), _accent_c.darkened(0.35))
	var lounge: Rect2 = _r["lounge"]
	if lounge.size.x > 0.0:
		_overlay(lounge, _accent_c.darkened(0.55))

	# Painted curb along the sidewalk edge and a dashed street beyond the fence.
	_vbox(Vector3(garage.position.x - _x0, 0.04, 0.3), Vector3((garage.position.x + _x0) * 0.5, 0.02, sidewalk.end.y - 0.15), Color("d9d4c7"))
	var lot: Rect2 = _r["lot"]
	_vbox(Vector3(_plan["w"] + 40.0, 0.02, 12.0), Vector3(0.0, -0.02, lot.end.y + 6.2), outside["street"].darkened(0.2))
	var x: float = -float(_plan["w"]) * 0.5 - 18.0
	while x < _plan["w"] * 0.5 + 18.0:
		_vbox(Vector3(2.0, 0.02, 0.2), Vector3(x, 0.0, lot.end.y + 6.2), PAINT_YELLOW)
		x += 4.0


## Floor slabs are the lowest geometry, so they set where the nav voxel grid
## starts. Just under one voxel thick keeps the baked navmesh as close above
## the floor as Recast allows (about one voxel).
func _slab(rect: Rect2, color: Color) -> void:
	var t: float = Tuning.NAV_CELL_SIZE * 0.96
	_solid(Vector3(rect.size.x, t, rect.size.y), Vector3(rect.get_center().x, -t * 0.5, rect.get_center().y), color)


func _overlay(rect: Rect2, color: Color) -> void:
	var c: Vector2 = rect.get_center()
	_vbox(Vector3(rect.size.x, 0.02, rect.size.y), Vector3(c.x, OVERLAY_Y, c.y), color)


## A flat decal above the overlays; `lift` stacks decals without z-fighting.
func _pattern_box(rect: Rect2, color: Color, emission: float = 0.0, lift: float = 0.0) -> MeshInstance3D:
	var c: Vector2 = rect.get_center()
	return _vbox(Vector3(rect.size.x, 0.012, rect.size.y), Vector3(c.x, PATTERN_Y + lift, c.y), color, emission)


func _checker(rect: Rect2, a: Color, b: Color, tile: float) -> void:
	_overlay(rect, a)
	var nx: int = int(rect.size.x / tile)
	var nz: int = int(rect.size.y / tile)
	for i in nx:
		for j in nz:
			if (i + j) % 2 == 1:
				_pattern_box(Rect2(rect.position.x + i * tile, rect.position.y + j * tile, tile, tile), b)


# --- walls --------------------------------------------------------------------

func _gx(x: float) -> int:
	return roundi((x - _x0) / G)


func _gz(z: float) -> int:
	return roundi((z - _z0) / G)


func _build_walls() -> void:
	# Unit edges on the grid: Vector3i(ix, iz, 0) runs +X from grid point
	# (ix, iz); Vector3i(ix, iz, 1) runs +Z. Shared room sides collapse.
	var edges := {}
	for rect: Rect2 in _plan["walled"]:
		var ix0: int = _gx(rect.position.x)
		var ix1: int = _gx(rect.end.x)
		var iz0: int = _gz(rect.position.y)
		var iz1: int = _gz(rect.end.y)
		for ix in range(ix0, ix1):
			edges[Vector3i(ix, iz0, 0)] = true
			edges[Vector3i(ix, iz1, 0)] = true
		for iz in range(iz0, iz1):
			edges[Vector3i(ix0, iz, 1)] = true
			edges[Vector3i(ix1, iz, 1)] = true
	for d: Dictionary in _plan["doors"] + _plan["bars"]:
		_erase_segment(edges, d["a"], d["b"])

	var rows := {}
	var cols := {}
	for e: Vector3i in edges:
		if e.z == 0:
			if not rows.has(e.y):
				rows[e.y] = []
			(rows[e.y] as Array).append(e.x)
		else:
			if not cols.has(e.x):
				cols[e.x] = []
			(cols[e.x] as Array).append(e.y)
	for iz: int in rows:
		for run: Vector2i in _runs(rows[iz]):
			var z: float = _z0 + iz * G
			var ext_a: float = T * 0.5 if _has_vertical(edges, run.x, iz) else 0.0
			var ext_b: float = T * 0.5 if _has_vertical(edges, run.y + 1, iz) else 0.0
			_wall(Vector2(_x0 + run.x * G - ext_a, z), Vector2(_x0 + (run.y + 1) * G + ext_b, z))
	for ix: int in cols:
		for run: Vector2i in _runs(cols[ix]):
			var x: float = _x0 + ix * G
			_wall(Vector2(x, _z0 + run.x * G), Vector2(x, _z0 + (run.y + 1) * G))

	for d: Dictionary in _plan["doors"]:
		_door_frame(d)
	for d: Dictionary in _plan["bars"]:
		_cashier_bars(d["a"], d["b"])


func _erase_segment(edges: Dictionary, a: Vector2, b: Vector2) -> void:
	if is_equal_approx(a.y, b.y):
		var iz: int = _gz(a.y)
		for ix in range(_gx(minf(a.x, b.x)), _gx(maxf(a.x, b.x))):
			edges.erase(Vector3i(ix, iz, 0))
	else:
		var ix: int = _gx(a.x)
		for iz in range(_gz(minf(a.y, b.y)), _gz(maxf(a.y, b.y))):
			edges.erase(Vector3i(ix, iz, 1))


func _has_vertical(edges: Dictionary, ix: int, iz: int) -> bool:
	return edges.has(Vector3i(ix, iz - 1, 1)) or edges.has(Vector3i(ix, iz, 1))


## Consecutive integer runs as Vector2i(first, last).
func _runs(values: Array) -> Array[Vector2i]:
	var sorted: Array = values.duplicate()
	sorted.sort()
	var out: Array[Vector2i] = []
	for v: int in sorted:
		if not out.is_empty() and out[-1].y == v - 1:
			var last: Vector2i = out[-1]
			last.y = v
			out[-1] = last
		else:
			out.append(Vector2i(v, v))
	return out


## A straight wall from a to b (XZ), with baseboard and cap trims.
func _wall(a: Vector2, b: Vector2, height: float = H, color: Color = Color(0, 0, 0, 0)) -> void:
	var c: Color = _wall_c if color.a == 0.0 else color
	var horizontal: bool = is_equal_approx(a.y, b.y)
	var length: float = absf(b.x - a.x) if horizontal else absf(b.y - a.y)
	var mid := Vector3((a.x + b.x) * 0.5, height * 0.5, (a.y + b.y) * 0.5)
	var size := Vector3(length, height, T) if horizontal else Vector3(T, height, length)
	_solid(size, mid, c)
	var trim := Vector3(length + 0.04, 0.0, T + 0.04) if horizontal else Vector3(T + 0.04, 0.0, length + 0.04)
	_vbox(Vector3(trim.x, 0.14, trim.z), Vector3(mid.x, 0.07, mid.z), _accent_c.darkened(0.35))
	_vbox(Vector3(trim.x + 0.02, 0.08, trim.z + 0.02), Vector3(mid.x, height + 0.02, mid.z), _accent_c.darkened(0.15))


func _door_frame(d: Dictionary) -> void:
	var a: Vector2 = d["a"]
	var b: Vector2 = d["b"]
	var kind: StringName = d["kind"]
	var horizontal: bool = is_equal_approx(a.y, b.y)
	var length: float = absf(b.x - a.x) if horizontal else absf(b.y - a.y)
	var mid := Vector3((a.x + b.x) * 0.5, 0.0, (a.y + b.y) * 0.5)
	var along := Vector3(1, 0, 0) if horizontal else Vector3(0, 0, 1)
	var normal := Vector3(0, 0, 1) if horizontal else Vector3(1, 0, 0)
	var lintel_h: float = H - DOOR_H
	var lintel_size := Vector3(length, lintel_h, T) if horizontal else Vector3(T, lintel_h, length)
	_solid(lintel_size, mid + Vector3(0, DOOR_H + lintel_h * 0.5, 0), _wall_c)
	var frame_c: Color = _accent_c if kind == &"entrance" else _accent_c.darkened(0.3)
	for s: float in [-1.0, 1.0]:
		var post_size := Vector3(0.14, DOOR_H, T + 0.08) if horizontal else Vector3(T + 0.08, DOOR_H, 0.14)
		_vbox(post_size, mid + along * (s * (length * 0.5 - 0.07)) + Vector3(0, DOOR_H * 0.5, 0), frame_c)
	var top_size := Vector3(length, 0.12, T + 0.08) if horizontal else Vector3(T + 0.08, 0.12, length)
	_vbox(top_size, mid + Vector3(0, DOOR_H + 0.06, 0), frame_c)
	if DOOR_SIGNS.has(kind):
		var door_sign: Array = DOOR_SIGNS[kind]
		var facing: float = float(door_sign[1])
		var color: Color = Color("4cff7a") if kind == &"entrance" else _accent_c.lightened(0.3)
		var label := _label(str(door_sign[0]), mid + normal * (facing * (T * 0.5 + 0.02)) + Vector3(0, DOOR_H + lintel_h * 0.5, 0), 0.0055, color)
		label.rotation.y = _facing_yaw(normal * facing)
	if kind == &"entrance":
		# Glass doors swung open into the lobby.
		for s: float in [-1.0, 1.0]:
			var leaf := _vbox(Vector3(0.06, DOOR_H - 0.1, 0.95), mid + along * (s * (length * 0.5 - 0.1)) + Vector3(0, DOOR_H * 0.5, -0.55), GLASS)
			leaf.name = "GlassDoor"


## Yaw that turns a Label3D (front +Z) to face `dir` (horizontal).
func _facing_yaw(dir: Vector3) -> float:
	return atan2(dir.x, dir.z)


## The cashier counter: solid to full wall height for collision, drawn as a
## counter with bars above it.
func _cashier_bars(a: Vector2, b: Vector2) -> void:
	var length: float = absf(b.x - a.x)
	var mid := Vector3((a.x + b.x) * 0.5, 0.0, a.y)
	var body := StaticBody3D.new()
	body.name = "CashierCounter"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _box_shape(Vector3(length, H, 0.5))
	cs.position = Vector3(0, H * 0.5, 0)
	body.add_child(cs)
	body.position = mid
	_static.add_child(body)
	_vbox(Vector3(length, 1.05, 0.6), mid + Vector3(0, 0.525, 0), _accent_c.darkened(0.45))
	_vbox(Vector3(length + 0.06, 0.06, 0.7), mid + Vector3(0, 1.08, 0), _accent_c.lightened(0.2))
	var bars := int(length / 0.3)
	for i in bars + 1:
		var x: float = -length * 0.5 + length * float(i) / float(bars)
		_vbox(Vector3(0.04, H - 1.1, 0.04), mid + Vector3(x, 1.1 + (H - 1.1) * 0.5, 0.0), _accent_c.lightened(0.1))
	_vbox(Vector3(length, 0.45, 0.12), mid + Vector3(0, H - 0.22, 0.02), _accent_c.darkened(0.25))
	_label("CASHIER", mid + Vector3(0, H - 0.22, 0.1), 0.007, _accent_c.lightened(0.5))


# --- outside -----------------------------------------------------------------

func _build_outside() -> void:
	var lot: Rect2 = _r["lot"]
	var garage: Rect2 = _r["garage"]
	var dock: Rect2 = _r["dock"]
	var fence_c: Color = _wall_c.darkened(0.45)
	# Front lot fence (the garage closes the south-east corner).
	_wall(Vector2(_x0, lot.position.y), Vector2(_x0, lot.end.y), FENCE_H, fence_c)
	_wall(Vector2(_x0, lot.end.y), Vector2(garage.position.x, lot.end.y), FENCE_H, fence_c)
	_wall(Vector2(_x1, lot.position.y), Vector2(_x1, garage.position.y), FENCE_H, fence_c)
	# Parking garage: open toward the sidewalk.
	_wall(Vector2(garage.position.x, garage.position.y + 4.0), Vector2(garage.position.x, garage.end.y), 2.6, CONCRETE)
	_wall(Vector2(garage.position.x - T * 0.5, garage.end.y), Vector2(garage.end.x + T * 0.5, garage.end.y), 2.6, CONCRETE)
	_wall(Vector2(garage.end.x, garage.position.y), Vector2(garage.end.x, garage.end.y), 2.6, CONCRETE)
	for i in 4:
		var sx: float = garage.position.x + 1.5 + 3.0 * float(i)
		_vbox(Vector3(0.12, 0.02, 4.6), Vector3(sx, PATTERN_Y, garage.end.y - 2.5), WHITE)
	var cars := 2 if garage.size.x < 14.0 else 3
	for i in cars:
		_car(Vector3(garage.position.x + 3.0 + 3.0 * float(i), 0.0, garage.end.y - 2.6), 0.0, CAR_COLORS[_rng.randi_range(0, CAR_COLORS.size() - 1)])
	for px: float in [garage.position.x + 0.4, garage.end.x - 0.4]:
		_solid(Vector3(0.5, 3.4, 0.5), Vector3(px, 1.7, garage.position.y + 0.3), CONCRETE)
	_vbox(Vector3(garage.size.x, 0.5, 0.3), Vector3(garage.get_center().x, 3.2, garage.position.y + 0.3), CONCRETE_DARK)
	var park := _label("PARKING", Vector3(garage.get_center().x, 3.2, garage.position.y + 0.1), 0.012, Color("ffffff"))
	park.rotation.y = PI
	var forger_g: Vector3 = _forger_point(&"parking_garage")
	_vbox(Vector3(1.0, 0.8, 0.8), forger_g + Vector3(1.4, 0.4, 1.2), WOOD_DARK)
	_vbox(Vector3(0.1, 0.1, 0.1), forger_g + Vector3(1.4, 2.4, 1.2), Color("fff1a8"), 3.0)

	# Exit pad: a painted taxi stand at the curb.
	var pad: Rect2 = _exit_rect()
	_pattern_box(pad, PAINT_YELLOW)
	var outside: Dictionary = OUTSIDE.get(_casino.get("id", &""), OUTSIDE[&"sals_back_room"])
	_pattern_box(pad.grow(-0.25), (outside["street"] as Color).lightened(0.08), 0.0, 0.006)
	var exit_label := _label("EXIT", Vector3(pad.get_center().x, 0.05, pad.get_center().y), 0.02, PAINT_YELLOW, false)
	exit_label.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	_solid(Vector3(0.12, 2.6, 0.12), Vector3(pad.position.x - 0.3, 1.3, pad.position.y + 0.3), STEEL)
	var taxi_sign := _vbox(Vector3(1.2, 0.5, 0.06), Vector3(pad.position.x - 0.3, 2.4, pad.position.y + 0.3), PAINT_YELLOW, 1.5)
	taxi_sign.name = "TaxiSign"
	var taxi_text := _label("TAXI  /  EXIT", Vector3(pad.position.x - 0.3, 2.4, pad.position.y + 0.25), 0.004, Color("1a1a1a"))
	taxi_text.rotation.y = PI
	_car(Vector3(pad.get_center().x, 0.0, pad.end.y + 2.4), PI * 0.5, PAINT_YELLOW)
	# Small enough that a player can only reach it standing on the pad (the
	# EXIT zone try_climb checks): sensor reach 0.7 + 0.8 m plus this radius
	# stays inside the 2 m half-width plus the body radius.
	var it_exit := Interactable.create(&"exit", "Leave the casino", 0.75, {})
	it_exit.position = Vector3(pad.get_center().x, 1.0, pad.get_center().y)
	_map.add_interactable(it_exit)

	# Loading dock behind the building.
	_wall(Vector2(dock.position.x, dock.position.y), Vector2(dock.position.x, dock.end.y), FENCE_H, fence_c)
	_wall(Vector2(dock.position.x - T * 0.5, dock.position.y), Vector2(dock.end.x + T * 0.5, dock.position.y), FENCE_H, fence_c)
	_wall(Vector2(dock.end.x, dock.position.y), Vector2(dock.end.x, dock.end.y), FENCE_H, fence_c)
	var truck_z: float = dock.position.y + 1.8
	_solid(Vector3(7.0, 3.0, 2.5), Vector3(dock.position.x + 5.0, 2.1, truck_z), WHITE.darkened(0.1))
	for wx: float in [dock.position.x + 2.2, dock.position.x + 3.2, dock.position.x + 7.6, dock.position.x + 9.6]:
		for wz: float in [truck_z - 1.05, truck_z + 1.05]:
			var wheel := _decor_mesh(_cylinder_mesh(0.42, 0.3, Color("161616")), Vector3(wx, 0.42, wz))
			wheel.rotation.x = PI * 0.5
	_solid(Vector3(2.0, 2.4, 2.4), Vector3(dock.position.x + 9.8, 1.7, truck_z), RED.darkened(0.2))
	_vbox(Vector3(1.0, 0.7, 2.42), Vector3(dock.position.x + 10.2, 2.2, truck_z), GLASS)
	_solid(Vector3(1.0, 1.0, 1.0), Vector3(dock.position.x + 1.0, 0.5, dock.end.y - 1.2), WOOD)
	_solid(Vector3(1.0, 1.0, 1.0), Vector3(dock.position.x + 1.0, 0.5, dock.end.y - 2.3), WOOD)
	_vbox(Vector3(0.9, 0.9, 0.9), Vector3(dock.position.x + 1.0, 1.45, dock.end.y - 1.2), WOOD.lightened(0.15))
	_solid(Vector3(1.8, 1.3, 1.0), Vector3(dock.position.x + 1.4, 0.65, dock.position.y + 5.0), Color("2f6b45"))
	var forger_d: Vector3 = _forger_point(&"loading_dock")
	_vbox(Vector3(0.1, 0.1, 0.1), forger_d + Vector3(-1.0, 2.6, 0.0), Color("fff1a8"), 3.0)
	_solid(Vector3(0.1, 2.7, 0.1), forger_d + Vector3(-1.0, 1.35, 0.0), STEEL)

	_neon_sign()


func _car(pos: Vector3, yaw: float, color: Color) -> void:
	var body := _solid(Vector3(1.9, 1.0, 4.2), pos + Vector3(0, 0.55, 0), color)
	body.rotation.y = yaw
	_reparent(_vbox(Vector3(1.6, 0.6, 2.2), Vector3.ZERO, color.lightened(0.15)), body, Vector3(0, 0.75, 0.2))
	_reparent(_vbox(Vector3(1.62, 0.4, 2.0), Vector3.ZERO, Color("1d2a35")), body, Vector3(0, 0.78, 0.2))
	for wx: float in [-0.95, 0.95]:
		for wz: float in [-1.3, 1.3]:
			var wheel := _child_mesh(body, _cylinder_mesh(0.34, 0.25, Color("161616")), Vector3(wx, -0.21, wz))
			wheel.rotation.z = PI * 0.5


## The casino's name in neon over the entrance, outside.
func _neon_sign() -> void:
	var door_x: float = _plan["door_x"]
	var lobby: Rect2 = _r["lobby"]
	var width: float = lobby.size.x - 1.0
	var center := Vector3(door_x, H + 0.7, 0.25)
	_vbox(Vector3(width, 1.6, 0.2), center, _accent_c.darkened(0.7))
	var tube: Color = _accent_c
	_vbox(Vector3(width, 0.06, 0.06), center + Vector3(0, 0.74, 0.12), tube, 4.0)
	_vbox(Vector3(width, 0.06, 0.06), center + Vector3(0, -0.74, 0.12), tube, 4.0)
	_vbox(Vector3(0.06, 1.54, 0.06), center + Vector3(-width * 0.5, 0, 0.12), tube, 4.0)
	_vbox(Vector3(0.06, 1.54, 0.06), center + Vector3(width * 0.5, 0, 0.12), tube, 4.0)
	var text: String = str(_casino.get("name", "Casino")).to_upper()
	var label := _label(text, center + Vector3(0, 0.0, 0.14), minf(0.018, (width - 0.6) / maxf(1.0, float(text.length()) * 96.0 * 0.62)), Color(_accent_c.r * 1.6, _accent_c.g * 1.6, _accent_c.b * 1.6))
	label.font_size = 96
	label.outline_size = 14
	label.outline_modulate = _accent_c.darkened(0.6)
	label.name = "NeonName"
	# Canopy with marquee bulbs over the doors.
	var canopy_c := Vector3(door_x, DOOR_H + 0.25, 1.1)
	_vbox(Vector3(5.6, 0.14, 2.2), canopy_c, _wall_c.darkened(0.2))
	var bulbs := 9
	for i in bulbs:
		var bx: float = door_x - 2.6 + 5.2 * float(i) / float(bulbs - 1)
		_decor_mesh(_sphere_mesh(0.07, Color("fff3c4"), 3.0), Vector3(bx, DOOR_H + 0.12, 2.2))


# --- back of house -----------------------------------------------------------

func _build_back_of_house() -> void:
	var back: Rect2 = _r["back_room"]
	var sec: Rect2 = _r["security"]
	var cash: Rect2 = _r["cashier"]
	var rest: Rect2 = _r["restroom"]
	var corridor: Rect2 = _r["corridor"]

	# Back room: a bench, a table and a bare bulb.
	_solid(Vector3(0.5, 0.45, 2.4), Vector3(back.position.x + 0.45, 0.225, back.get_center().y), STEEL)
	_solid(Vector3(1.0, 0.75, 1.0), Vector3(back.end.x - 1.6, 0.375, back.end.y - 1.2), STEEL.lightened(0.2))
	_decor_mesh(_sphere_mesh(0.12, Color("fff1a8"), 4.0), Vector3(back.get_center().x, 2.5, back.get_center().y))

	# Security office: desk under a wall of monitors.
	var desk_z: float = sec.position.y + 0.8
	_solid(Vector3(3.6, 0.8, 0.9), Vector3(sec.get_center().x, 0.4, desk_z), STEEL)
	for i in 6:
		var col: int = i % 3
		var row: int = floori(i / 3.0)
		_vbox(Vector3(0.9, 0.55, 0.06), Vector3(sec.get_center().x - 1.0 + col * 1.0, 1.35 + row * 0.62, sec.position.y + 0.14), SCREEN.darkened(0.2 * row), 1.2)
	_vbox(Vector3(0.6, 0.9, 0.6), Vector3(sec.get_center().x, 0.45, desk_z + 1.0), Color("202226"))

	# Staff corridor: lockers on the back wall, a laundry cart at the dead end.
	var lockers := 4
	for i in lockers:
		var lx: float = corridor.position.x + 2.6 + 0.95 * float(i)
		_solid(Vector3(0.9, 1.9, 0.3), Vector3(lx, 0.95, corridor.position.y + T * 0.5 + 0.15), STEEL.lightened(0.15 + 0.05 * (i % 2)))
		_vbox(Vector3(0.5, 0.06, 0.02), Vector3(lx, 1.6, corridor.position.y + T * 0.5 + 0.31), CONCRETE_DARK)
	var it_locker := Interactable.create(&"staff_locker", "Rummage through the staff lockers", 1.2)
	it_locker.position = Vector3(corridor.position.x + 2.6 + 0.95 * 1.5, 1.0, corridor.position.y + 1.1)
	_map.add_interactable(it_locker)
	var cart_pos := Vector3(corridor.position.x + 0.8, 0.0, corridor.get_center().y)
	_solid(Vector3(0.8, 0.9, 1.2), cart_pos + Vector3(0, 0.55, 0), Color("9aa3ad"))
	_vbox(Vector3(0.7, 0.25, 1.1), cart_pos + Vector3(0, 1.08, 0), Color("e8e2d0"))
	_vbox(Vector3(0.3, 0.12, 0.4), cart_pos + Vector3(0.1, 1.25, -0.2), Color("7b1e3a"))
	var it_cart := Interactable.create(&"laundry_cart", "Grab something from the laundry cart", 1.2)
	it_cart.position = cart_pos + Vector3(1.0, 1.0, 0)
	_map.add_interactable(it_cart)

	# Cashier cage: chip racks and a safe behind the counter.
	_solid(Vector3(cash.size.x - 2.6, 1.0, 0.6), Vector3(cash.get_center().x - 0.5, 0.5, cash.end.y - 2.0), _accent_c.darkened(0.45))
	for i in int(cash.size.x - 3.0):
		_vbox(Vector3(0.6, 0.18, 0.4), Vector3(cash.position.x + 1.6 + float(i), 1.09, cash.end.y - 2.0), [RED, Color("2e86de"), Color("27ae60"), Color("111111")][i % 4])
	_solid(Vector3(1.2, 1.6, 1.0), Vector3(cash.end.x - 1.0, 0.8, cash.position.y + 0.9), Color("3a3d42"))
	var cashier_x: float = (cash.position.x + cash.end.x - 2.0) * 0.5
	# Reach (this radius + the player's 1.5 m sensor) ends inside the CASHIER zone.
	var it_cash := Interactable.create(&"cashier", "Cash out chips", 0.8)
	it_cash.position = Vector3(cashier_x, 1.0, cash.end.y + 0.9)
	_map.add_interactable(it_cash)

	# Restroom: sinks and mirror on the west wall, stalls on the back wall,
	# a quiet corner at the east end (forger spot).
	_solid(Vector3(0.6, 0.9, 3.0), Vector3(rest.position.x + 0.4, 0.45, rest.get_center().y + 0.5), WHITE)
	_vbox(Vector3(0.04, 1.0, 2.8), Vector3(rest.position.x + T * 0.5 + 0.03, 1.65, rest.get_center().y + 0.5), Color(0.7, 0.85, 0.95), 0.25)
	var it_rest := Interactable.create(&"restroom", "Change outfit", 1.2)
	it_rest.position = Vector3(rest.position.x + 1.3, 1.0, rest.get_center().y + 0.5)
	_map.add_interactable(it_rest)
	var stall_x0: float = rest.position.x + 2.5
	for k in 4:
		_solid(Vector3(0.08, 2.0, 1.6), Vector3(stall_x0 + 1.5 * float(k), 1.0, rest.position.y + 0.8), _accent_c.lerp(WHITE, 0.5))
	for k in 3:
		var sx: float = stall_x0 + 0.75 + 1.5 * float(k)
		_vbox(Vector3(0.45, 0.45, 0.6), Vector3(sx, 0.225, rest.position.y + 0.45), WHITE)
		var stall_door := _vbox(Vector3(0.05, 1.7, 0.7), Vector3(sx - 0.4, 1.0, rest.position.y + 1.95), _accent_c.lerp(WHITE, 0.3))
		stall_door.rotation.y = deg_to_rad(-60.0)
	var forger_r: Vector3 = _forger_point(&"restroom")
	_vbox(Vector3(0.6, 1.2, 0.6), forger_r + Vector3(0.7, 0.6, -1.4), CONCRETE_DARK)

	# Lounge (bigger casinos): couches facing a TV.
	var lounge: Rect2 = _r["lounge"]
	if lounge.size.x > 0.0:
		var lc: Vector2 = lounge.get_center()
		_solid(Vector3(2.4, 0.8, 0.9), Vector3(lc.x, 0.4, lc.y + 1.2), _accent_c.darkened(0.2))
		_solid(Vector3(0.9, 0.8, 1.8), Vector3(lc.x - 2.2, 0.4, lc.y), _accent_c.darkened(0.2))
		_vbox(Vector3(2.2, 1.2, 0.06), Vector3(lc.x, 1.6, lounge.position.y + 0.14), Color("1b2633"), 0.6)
		_plant(Vector3(lounge.end.x - 0.7, 0.0, lounge.position.y + 0.7))
		_plant(Vector3(lounge.position.x + 0.7, 0.0, lounge.position.y + 0.7))

	# Fire alarm pull station on the east wall by the north aisle.
	var h_aisles: Array[float] = _plan["h_aisles"]
	var alarm_z: float = h_aisles[0]
	_vbox(Vector3(0.08, 0.35, 0.25), Vector3(_x1 - T * 0.5 - 0.04, 1.35, alarm_z), RED, 0.8)
	var fire_label := _label("FIRE", Vector3(_x1 - T * 0.5 - 0.09, 1.65, alarm_z), 0.003, WHITE)
	fire_label.rotation.y = -PI * 0.5
	var it_fire := Interactable.create(&"fire_alarm", "Pull the fire alarm", 1.0)
	it_fire.position = Vector3(_x1 - 0.8, 1.0, alarm_z)
	_map.add_interactable(it_fire)

	# Poster boards: security desk and cashier (the entrance one is in the lobby).
	_poster_board(&"security_desk", Vector3(sec.position.x + 2.0, 0.0, sec.end.y + T * 0.5), 0.0)
	_poster_board(&"cashier", Vector3(cash.end.x - 1.0, 0.0, cash.end.y + T * 0.5), 0.0)


func _poster_board(id: StringName, pos: Vector3, yaw: float) -> void:
	var board := PosterBoardNode.new(id)
	board.position = pos
	board.rotation.y = yaw
	_map.add_child(board)
	_map.poster_boards.append(board)


func _plant(pos: Vector3) -> void:
	_solid(Vector3(0.7, 0.6, 0.7), pos + Vector3(0, 0.3, 0), _accent_c.darkened(0.5))
	_decor_mesh(_sphere_mesh(0.5, PLANT, 0.0), pos + Vector3(0, 1.0, 0))


# --- front band --------------------------------------------------------------

func _build_front_band() -> void:
	var gift: Rect2 = _r["gift_shop"]
	var lobby: Rect2 = _r["lobby"]
	var bar: Rect2 = _r["bar"]
	var buffet: Rect2 = _r["buffet"]
	var door_x: float = _plan["door_x"]

	# Gift shop: shelves of merch, a counter by the door.
	var shelf_len: float = gift.size.y - 1.4
	_solid(Vector3(0.5, 0.4, shelf_len), Vector3(gift.position.x + 0.35, 0.2, gift.get_center().y), WOOD)
	_vbox(Vector3(0.1, 1.9, shelf_len), Vector3(gift.position.x + 0.15, 0.95, gift.get_center().y), WOOD_DARK)
	for level in 3:
		_vbox(Vector3(0.45, 0.04, shelf_len), Vector3(gift.position.x + 0.35, 0.82 + 0.45 * level, gift.get_center().y), WOOD)
		for i in int(shelf_len / 0.8):
			var merch: Color = CAR_COLORS[(i + level * 2 + _rng.randi_range(0, 5)) % CAR_COLORS.size()]
			_vbox(Vector3(0.3, 0.26, 0.5), Vector3(gift.position.x + 0.38, 0.97 + 0.45 * level, gift.position.y + 1.1 + 0.8 * float(i)), merch)
	_solid(Vector3(1.4, 1.1, 1.4), Vector3(gift.position.x + 2.6, 0.55, gift.get_center().y), WOOD.lightened(0.15))
	_decor_mesh(_sphere_mesh(0.3, _accent_c, 0.0), Vector3(gift.position.x + 2.6, 1.4, gift.get_center().y))
	var counter_z: float = gift.end.y - 0.9
	_solid(Vector3(2.4, 1.0, 0.7), Vector3(gift.end.x - 2.2, 0.5, counter_z), _accent_c.darkened(0.3))
	# Reach ends inside the shop: not through the wall from the lobby or sidewalk.
	var it_gift := Interactable.create(&"gift_shop", "Browse the gift shop", 0.8)
	it_gift.position = Vector3(gift.end.x - 2.2, 1.0, counter_z - 1.1)
	_map.add_interactable(it_gift)

	# Lobby: planters, the entrance poster board, a chip tower on display.
	_plant(Vector3(lobby.position.x + 0.8, 0.0, lobby.end.y - 0.8))
	_plant(Vector3(lobby.end.x - 0.8, 0.0, lobby.end.y - 3.4))
	for pz: float in [lobby.end.y - 1.0, lobby.end.y - 2.2]:
		_solid(Vector3(0.6, 0.9, 0.9), Vector3(lobby.end.x - 0.4, 0.45, pz), _accent_c.darkened(0.5))
		_decor_mesh(_sphere_mesh(0.35, PLANT, 0.0), Vector3(lobby.end.x - 0.4, 1.1, pz))
	_poster_board(&"entrance", Vector3(door_x + 4.0, 0.0, -T * 0.5), PI)
	_tray(Vector3(lobby.position.x + 1.2, 0.0, lobby.position.y + 1.2), &"chips")

	# Bar: back shelf of bottles, counter, stools.
	var shelf_z: float = bar.end.y - 0.35
	_solid(Vector3(bar.size.x - 1.0, 2.0, 0.4), Vector3(bar.get_center().x, 1.0, shelf_z), WOOD_DARK)
	for level in 2:
		_vbox(Vector3(bar.size.x - 1.2, 0.04, 0.2), Vector3(bar.get_center().x, 1.18 + 0.5 * level, shelf_z - 0.3), WOOD_DARK.lightened(0.2))
	var bottles := int((bar.size.x - 1.4) / 0.35)
	for i in bottles:
		var c: Color = [Color("2ecc71"), Color("e67e22"), Color("3498db"), Color("e74c3c"), Color("f1c40f")][(i + _rng.randi_range(0, 4)) % 5]
		_decor_mesh(_cylinder_mesh(0.06, 0.3, c, 1.2), Vector3(bar.position.x + 0.9 + 0.35 * float(i), 1.35 + 0.5 * float(i % 2), shelf_z - 0.3))
	var counter_len: float = bar.size.x - 2.0
	var bar_z: float = bar.end.y - 2.4
	_solid(Vector3(counter_len, 1.1, 0.7), Vector3(bar.get_center().x, 0.55, bar_z), WOOD)
	_vbox(Vector3(counter_len + 0.1, 0.06, 0.8), Vector3(bar.get_center().x, 1.13, bar_z), _accent_c)
	var stools := int(counter_len / 1.0)
	for i in stools:
		var sx: float = bar.position.x + 1.5 + float(i) * (counter_len - 1.0) / maxf(1.0, float(stools - 1))
		_decor_mesh(_cylinder_mesh(0.22, 0.08, _accent_c.darkened(0.2)), Vector3(sx, 0.75, bar_z - 0.85))
		_decor_mesh(_cylinder_mesh(0.04, 0.72, STEEL), Vector3(sx, 0.36, bar_z - 0.85))
	var bar_sign := _label("BAR", Vector3(bar.get_center().x, 2.55, bar.end.y - T * 0.5 - 0.02), 0.012, _accent_c.lightened(0.3))
	bar_sign.rotation.y = PI
	_tray(Vector3(bar.position.x + 0.6, 0.0, bar.position.y + 0.8), &"drinks")

	# Buffet: a food line along the east wall, little dining tables.
	var line_len: float = buffet.size.y - 2.0
	_solid(Vector3(0.9, 0.9, line_len), Vector3(buffet.end.x - 0.6, 0.45, buffet.get_center().y + 0.4), WHITE.darkened(0.15))
	for i in int(line_len / 0.7):
		var food: Color = [Color("e67e22"), Color("27ae60"), Color("c0392b"), Color("f5cba7")][i % 4]
		_vbox(Vector3(0.5, 0.1, 0.5), Vector3(buffet.end.x - 0.6, 0.95, buffet.get_center().y + 0.4 - line_len * 0.5 + 0.4 + 0.7 * float(i)), food)
	_vbox(Vector3(0.04, 0.5, line_len), Vector3(buffet.end.x - 1.1, 1.25, buffet.get_center().y + 0.4), GLASS)
	for p: Vector3 in _buffet_tables():
		_solid(Vector3(0.9, 0.75, 0.9), p + Vector3(0, 0.375, 0), WHITE.darkened(0.05))
		for s: float in [-1.0, 1.0]:
			_vbox(Vector3(0.45, 0.45, 0.45), p + Vector3(s * 0.75, 0.225, 0), _accent_c.darkened(0.3))
	var buffet_sign := _label("BUFFET", Vector3(buffet.get_center().x, 2.55, buffet.end.y - T * 0.5 - 0.02), 0.012, _accent_c.lightened(0.3))
	buffet_sign.rotation.y = PI


## Dining tables of the buffet (floor positions).
func _buffet_tables() -> Array[Vector3]:
	var buffet: Rect2 = _r["buffet"]
	var out: Array[Vector3] = []
	var cols := 1 if buffet.size.x < 9.0 else 2
	for c in cols:
		for z: float in [buffet.end.y - 1.6, buffet.end.y - 3.8]:
			out.append(Vector3(buffet.position.x + 2.0 + 3.6 * float(c), 0.0, z))
	return out


## A drink tray or chip tower on a stand that can be knocked over.
func _tray(pos: Vector3, prop: StringName) -> void:
	var root := Node3D.new()
	root.name = "Tray"
	root.position = pos
	_decor.add_child(root)
	_child_mesh(root, _cylinder_mesh(0.04, 0.95, STEEL), Vector3(0, 0.475, 0))
	_child_mesh(root, _cylinder_mesh(0.28, 0.03, _accent_c.darkened(0.2)), Vector3(0, 0.96, 0))
	if prop == &"chips":
		var colors: Array[Color] = [RED, Color("2e86de"), Color("27ae60"), Color("111111"), WHITE]
		for i in 6:
			_child_mesh(root, _cylinder_mesh(0.1, 0.09, colors[i % colors.size()]), Vector3(-0.08, 1.02 + 0.09 * float(i), 0.0))
			_child_mesh(root, _cylinder_mesh(0.1, 0.09, colors[(i + 2) % colors.size()]), Vector3(0.12, 1.02 + 0.09 * float(i % 4), 0.06))
	else:
		for i in 4:
			var a: float = TAU * float(i) / 4.0
			_child_mesh(root, _cylinder_mesh(0.05, 0.16, Color(0.8, 0.95, 1.0, 0.6)), Vector3(cos(a) * 0.15, 1.05, sin(a) * 0.15))
	var it := Interactable.create(&"tray", "Knock it over", 0.9, {"prop": prop})
	it.position = Vector3(0, 1.0, 0)
	_map.add_interactable(it, root)


# --- game floor --------------------------------------------------------------

func _build_game_blocks() -> void:
	var counters := {}
	var first_slots := true
	for block: Dictionary in _plan["blocks"]:
		var rect: Rect2 = block["rect"]
		var id: StringName = block["id"]
		if block["kind"] == &"slots":
			_slots_block(block, counters, first_slots)
			first_slots = false
		else:
			_tables_block(block, counters)
		var title: String = AREA_TITLES.get(id, "")
		if title == "":
			title = TableGames.display_name(HR.GameType.SLOTS, _rung).to_upper()
		# Under the wall tops and the floor camera's eye line, so the sign shows
		# on the floor below the HUD's top band (the map fades it by distance).
		var area_sign := _label(title, Vector3(rect.get_center().x, AREA_SIGN_Y, rect.get_center().y), 0.006, _accent_c.lightened(0.4), true)
		area_sign.name = "AreaSign_%s" % String(id)
		_map.area_signs.append(area_sign)


func _next_table_id(game_type: int, counters: Dictionary) -> StringName:
	var n: int = int(counters.get(game_type, 0)) + 1
	counters[game_type] = n
	return StringName("%s_%d" % [str(HR.GameType.find_key(game_type)).to_lower(), n])


func _add_anchor(game_type: int, area_id: StringName, xf: Transform3D, counters: Dictionary) -> void:
	_map.table_anchors.append({
		"id": _next_table_id(game_type, counters),
		"game_type": game_type,
		"area_id": area_id,
		"transform": xf,
	})


func _tables_block(block: Dictionary, counters: Dictionary) -> void:
	var rect: Rect2 = block["rect"]
	var id: StringName = block["id"]
	var carpet: Color = _floor_c.lerp(_accent_c, 0.18).darkened(0.25)
	_carpet(rect, carpet, _accent_c)
	# A pendant lamp over each table: a dark shade with a glowing underside on
	# a thin rod. It hangs below the wall tops so the floor camera sees it
	# against the room, not floating in the open sky (there is no ceiling).
	var shade_c: Color = _accent_c.darkened(0.45)
	for slot: Dictionary in CasinoLayouts.table_slots(block):
		var xf: Transform3D = slot["transform"]
		_add_anchor(int(slot["game_type"]), id, xf, counters)
		_decor_mesh(_cylinder_mesh(0.18, 0.14, shade_c), xf.origin + Vector3(0, LAMP_Y + 0.07, 0))
		_decor_mesh(_cylinder_mesh(0.15, 0.02, _accent_c.lerp(WHITE, 0.6), 1.4), xf.origin + Vector3(0, LAMP_Y - 0.005, 0))
		_vbox(Vector3(0.025, H - LAMP_Y - 0.14, 0.025), xf.origin + Vector3(0, (H + LAMP_Y + 0.14) * 0.5, 0), STEEL)
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.end]:
		var inward := Vector2(signf(rect.get_center().x - corner.x), signf(rect.get_center().y - corner.y)) * 0.45
		_pillar(Vector3(corner.x + inward.x, 0.0, corner.y + inward.y))
	_tray(Vector3(rect.position.x + 0.35, 0.0, rect.get_center().y), &"drinks" if _rng.randf() < 0.5 else &"chips")


func _slots_block(block: Dictionary, counters: Dictionary, with_alarm: bool) -> void:
	var rect: Rect2 = block["rect"]
	var id: StringName = block["id"]
	_carpet(rect, _accent_c.darkened(0.6), _accent_c.darkened(0.1))
	var machines: Dictionary = CasinoLayouts.slot_machines(block)
	for xf: Transform3D in machines["player"]:
		_add_anchor(HR.GameType.SLOTS, id, xf, counters)
	for xf: Transform3D in machines["decor"]:
		_decor_slot_machine(xf)
		var seat := Transform3D(xf.basis, xf.origin + xf.basis.z * 1.0)
		_map.slot_seats.append(seat)
		_decor_mesh(_cylinder_mesh(0.2, 0.06, _accent_c.darkened(0.2)), seat.origin + Vector3(0, 0.5, 0))
		_decor_mesh(_cylinder_mesh(0.04, 0.48, STEEL), seat.origin + Vector3(0, 0.24, 0))
	if with_alarm:
		var post := Vector3(rect.get_center().x - 0.2, 0.0, rect.end.y - 0.35)
		_solid(Vector3(0.25, 1.3, 0.25), post + Vector3(0, 0.65, 0), STEEL)
		_decor_mesh(_sphere_mesh(0.18, RED, 3.0), post + Vector3(0, 1.45, 0))
		var it := Interactable.create(&"slot_alarm", "Trip the jackpot alarm", 0.9)
		it.position = post + Vector3(0, 1.0, -0.4)
		_map.add_interactable(it)


## A patron slot cabinet (players use the TableNode machines across the aisle).
func _decor_slot_machine(xf: Transform3D) -> void:
	var body := _solid(Vector3(0.9, 1.7, 0.7), xf.origin + Vector3(0, 0.85, 0), _accent_c.darkened(0.25))
	body.transform.basis = xf.basis
	var screen := _vbox(Vector3(0.6, 0.45, 0.04), Vector3.ZERO, SCREEN, 1.4)
	_reparent(screen, body, Vector3(0, 0.25, 0.36))
	var topper := _vbox(Vector3(0.85, 0.2, 0.6), Vector3.ZERO, _accent_c, 1.0)
	_reparent(topper, body, Vector3(0, 0.95, 0))
	var tray := _vbox(Vector3(0.7, 0.1, 0.25), Vector3.ZERO, STEEL)
	_reparent(tray, body, Vector3(0, -0.25, 0.45))


func _pillar(pos: Vector3) -> void:
	_solid(Vector3(0.5, H, 0.5), pos + Vector3(0, H * 0.5, 0), _wall_c.darkened(0.1))
	_vbox(Vector3(0.66, 0.25, 0.66), pos + Vector3(0, 0.125, 0), _accent_c.darkened(0.3))
	_vbox(Vector3(0.66, 0.2, 0.66), pos + Vector3(0, H - 0.1, 0), _accent_c)


## Patterned carpet: a base, a border band and a lattice of diamonds.
func _carpet(rect: Rect2, base: Color, trim: Color) -> void:
	var inner: Rect2 = rect.grow(-0.1)
	_overlay(inner, base)
	var bw := 0.18
	_pattern_box(Rect2(inner.position.x, inner.position.y + 0.25, inner.size.x, bw), trim)
	_pattern_box(Rect2(inner.position.x, inner.end.y - 0.25 - bw, inner.size.x, bw), trim)
	_pattern_box(Rect2(inner.position.x + 0.25, inner.position.y, bw, inner.size.y), trim)
	_pattern_box(Rect2(inner.end.x - 0.25 - bw, inner.position.y, bw, inner.size.y), trim)
	var style: int = _rng.randi_range(0, 2)
	var dot: Color = base.lerp(trim, 0.35)
	var nx: int = int(rect.size.x / 2.0)
	var nz: int = int(rect.size.y / 2.0)
	for i in nx:
		for j in nz:
			var c := Vector2(rect.position.x + 1.0 + 2.0 * float(i), rect.position.y + 1.0 + 2.0 * float(j))
			var d := _pattern_box(Rect2(c - Vector2(0.35, 0.35), Vector2(0.7, 0.7)), dot if (i + j) % 2 == 0 or style == 0 else base.lightened(0.12), 0.0, 0.006)
			d.rotation.y = PI * 0.25 if style != 2 else 0.0


# --- zones -------------------------------------------------------------------

func _build_zones() -> void:
	_zone(HR.ZoneType.FLOOR, &"floor", 0, [_r["floor"]])
	_zone(HR.ZoneType.FLOOR, &"outside", 0, [_r["lot"]])
	var lounge: Rect2 = _r["lounge"]
	if lounge.size.x > 0.0:
		_zone(HR.ZoneType.FLOOR, &"lounge", 1, [lounge])
	for block: Dictionary in _plan["blocks"]:
		var type: int = HR.ZoneType.SLOTS if block["kind"] == &"slots" else HR.ZoneType.TABLES
		_zone(type, block["id"], 1, [block["rect"]])
	var cash: Rect2 = _r["cashier"]
	_zone(HR.ZoneType.CASHIER, &"cashier", 1, [Rect2(cash.position.x, cash.end.y, cash.size.x - 2.0, 3.0)])
	_zone(HR.ZoneType.BACK_ROOM, &"back_room", 1, [_r["back_room"]])
	_zone(HR.ZoneType.STAFF_ONLY, &"security", 1, [_r["security"]])
	_zone(HR.ZoneType.STAFF_ONLY, &"staff", 1, [_r["corridor"], _r["passage"], cash])
	_zone(HR.ZoneType.STAFF_ONLY, &"dock", 1, [_r["dock"]])
	_zone(HR.ZoneType.RESTROOM, &"restroom", 1, [_r["restroom"]])
	_zone(HR.ZoneType.GIFT_SHOP, &"gift_shop", 1, [_r["gift_shop"]])
	_zone(HR.ZoneType.ENTRANCE, &"entrance", 1, [_r["lobby"]])
	_zone(HR.ZoneType.BAR, &"bar", 1, [_r["bar"]])
	_zone(HR.ZoneType.BUFFET, &"buffet", 1, [_r["buffet"]])
	_zone(HR.ZoneType.EXIT, &"exit", 2, [_exit_rect()])
	for loc: StringName in Forger.LOCATIONS:
		_zone(HR.ZoneType.FORGER, loc, 2, [_forger_rect(loc)])


func _zone(type: int, area: StringName, priority: int, rects: Array) -> CasinoZone:
	var zone := CasinoZone.create(type, area, priority)
	for r: Rect2 in rects:
		zone.add_rect(r)
	_map.add_zone(zone)
	return zone


func _exit_rect() -> Rect2:
	var door_x: float = _plan["door_x"]
	return Rect2(door_x - 8.0, CasinoLayouts.SIDEWALK_DEPTH, 4.0, 4.0)


func _forger_point(location: StringName) -> Vector3:
	match location:
		&"parking_garage":
			var g: Rect2 = _r["garage"]
			return Vector3(g.end.x - 2.6, 0.0, g.end.y - 3.4)
		&"restroom":
			var rest: Rect2 = _r["restroom"]
			return Vector3(rest.end.x - 1.4, 0.0, rest.position.y + 2.6)
		_:
			var dock: Rect2 = _r["dock"]
			return Vector3(dock.end.x - 6.0, 0.0, dock.end.y - 4.4)


func _forger_rect(location: StringName) -> Rect2:
	var p: Vector3 = _forger_point(location)
	var r := Rect2(p.x - 2.0, p.z - 2.0, 4.0, 4.0)
	if location == &"restroom":
		r = r.intersection(_r["restroom"])
	return r


# --- points ------------------------------------------------------------------

func _build_points() -> void:
	var door_x: float = _plan["door_x"]
	var lobby: Rect2 = _r["lobby"]
	for p: Vector2 in [Vector2(-1.0, -2.0), Vector2(1.0, -2.0), Vector2(-1.0, -3.4), Vector2(1.0, -3.4)]:
		_map.spawn_points.append(Vector3(door_x + p.x, 0.0, lobby.end.y + p.y))
	_map.curb_point = Vector3(_x0 + 2.5, 0.0, 2.0)
	var back: Rect2 = _r["back_room"]
	_map.back_room_point = Vector3(back.get_center().x, 0.0, back.get_center().y)
	var sec: Rect2 = _r["security"]
	_map.back_room_release_point = Vector3(sec.position.x + 5.0, 0.0, sec.end.y + 1.6)
	var pad: Rect2 = _exit_rect()
	_map.exit_point = Vector3(pad.get_center().x, 0.0, pad.get_center().y)
	for loc: StringName in Forger.LOCATIONS:
		var p: Vector3 = _forger_point(loc)
		_map.forger_points[loc] = p
		var it := Interactable.create(&"forger", "Buy a fake ID", 1.4, {"location": loc})
		it.position = p + Vector3(0, 1.0, 0)
		_map.add_interactable(it)

	_patrol_routes()
	var av: float = _plan["aisle_v"]
	for block: Dictionary in _plan["blocks"]:
		if block["kind"] == &"slots":
			continue
		var rect: Rect2 = block["rect"]
		_map.pit_boss_posts.append(Vector3(rect.position.x - minf(0.8, av * 0.5 - 0.2), 0.0, rect.get_center().y))
	_camera_mounts()
	_patron_points()


## One loop per floor guard (plus spares): rectangles around the game blocks
## along the aisles, smallest first so the guards spread over the floor.
func _patrol_routes() -> void:
	var hs: Array[float] = _plan["h_aisles"]
	var vs: Array[float] = _plan["v_aisles"]
	var loops: Array = []
	for a in hs.size():
		for b in range(a + 1, hs.size()):
			for c in vs.size():
				for d in range(c + 1, vs.size()):
					var area: float = (hs[b] - hs[a]) * (vs[d] - vs[c])
					loops.append({"key": area + _rng.randf() * 0.5, "h": Vector2(hs[a], hs[b]), "v": Vector2(vs[c], vs[d])})
	loops.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["key"]) < float(q["key"]))
	var guards: int = maxi(1, int(_casino.get("guards", 1)))
	var want: int = guards + Tuning.EXTRA_PATROL_ROUTES
	for k in mini(want, loops.size()):
		var loop: Dictionary = loops[k]
		var h: Vector2 = loop["h"]
		var v: Vector2 = loop["v"]
		var corners: Array[Vector3] = [
			Vector3(v.x, 0.0, h.x), Vector3(v.y, 0.0, h.x), Vector3(v.y, 0.0, h.y), Vector3(v.x, 0.0, h.y),
		]
		var route: Array[Vector3] = []
		for i in 4:
			var p: Vector3 = corners[(i + k) % 4]
			var q: Vector3 = corners[(i + k + 1) % 4]
			route.append(p)
			var legs: int = int(p.distance_to(q) / 10.0)
			for j in legs:
				route.append(p.lerp(q, float(j + 1) / float(legs + 1)))
		if k % 2 == 1:
			route.reverse()
		_map.patrol_routes.append(route)
	# Never fewer routes than guards: walk existing loops the other way round.
	var i := 0
	while _map.patrol_routes.size() < guards:
		var src: Array[Vector3] = _map.patrol_routes[i % maxi(1, loops.size())]
		var copy: Array[Vector3] = src.duplicate()
		copy.reverse()
		copy.push_front(copy.pop_back())
		_map.patrol_routes.append(copy)
		i += 1


func _camera_mounts() -> void:
	var floor_r: Rect2 = _r["floor"]
	var target := Vector3(floor_r.get_center().x, 0.0, floor_r.get_center().y)
	var y: float = Tuning.CAMERA_MOUNT_HEIGHT
	var inset := 0.35
	var spots: Array[Vector3] = [
		Vector3(floor_r.position.x + inset, y, floor_r.position.y + inset),
		Vector3(floor_r.end.x - inset, y, floor_r.position.y + inset),
		Vector3(floor_r.end.x - inset, y, floor_r.end.y - inset),
		Vector3(floor_r.position.x + inset, y, floor_r.end.y - inset),
	]
	if _plan["size"] == CasinoLayouts.LARGE:
		spots.append(Vector3(floor_r.position.x + inset, y, floor_r.get_center().y))
		spots.append(Vector3(floor_r.end.x - inset, y, floor_r.get_center().y))
	for p: Vector3 in spots:
		var look := Vector3(target.x, 0.0, target.z)
		if absf(p.z - target.z) < 1.0:
			look = Vector3(target.x, 0.0, p.z)
		_map.camera_mounts.append(Transform3D(Basis.looking_at(look - p, Vector3.UP), p))
		_vbox(Vector3(0.3, 0.3, 0.3), p, Color("1b1b1f"))
		_decor_mesh(_sphere_mesh(0.05, RED, 4.0), p + Vector3(0, -0.18, 0))


func _patron_points() -> void:
	var spacing: float = Tuning.PATRON_POINT_SPACING
	var ah: float = _plan["aisle_h"]
	var av: float = _plan["aisle_v"]
	var hs: Array[float] = _plan["h_aisles"]
	var vs: Array[float] = _plan["v_aisles"]
	for z: float in hs:
		var x: float = _x0 + 2.5
		while x < _x1 - 2.0:
			_map.patron_points.append(Vector3(x + _rng.randf_range(-0.6, 0.6), 0.0, z + _rng.randf_range(-1.0, 1.0) * (ah * 0.5 - 1.0)))
			x += spacing
	for block: Dictionary in _plan["blocks"]:
		var rect: Rect2 = block["rect"]
		if block["kind"] == &"slots":
			var mid_x: float = rect.position.x + 4.2
			_map.patron_points.append(Vector3(mid_x, 0.0, rect.position.y + 2.0))
			_map.patron_points.append(Vector3(mid_x, 0.0, rect.end.y - 2.0))
	for x: float in vs:
		for h in range(1, hs.size()):
			var z: float = (hs[h - 1] + hs[h]) * 0.5
			_map.patron_points.append(Vector3(x + _rng.randf_range(-1.0, 1.0) * maxf(0.0, av * 0.5 - 1.0), 0.0, z))
	var bar: Rect2 = _r["bar"]
	for i in int(bar.size.x / 2.5):
		_map.patron_points.append(Vector3(bar.position.x + 1.5 + 2.5 * float(i), 0.0, bar.position.y + 1.4))
	var buffet: Rect2 = _r["buffet"]
	_map.patron_points.append(Vector3(buffet.position.x + 1.0, 0.0, buffet.position.y + 1.0))
	_map.patron_points.append(Vector3(buffet.position.x + 3.8, 0.0, buffet.end.y - 2.7))
	var lobby: Rect2 = _r["lobby"]
	_map.patron_points.append(Vector3(lobby.position.x + 2.5, 0.0, lobby.get_center().y))
	_map.patron_points.append(Vector3(lobby.end.x - 2.5, 0.0, lobby.position.y + 1.5))
	var lounge: Rect2 = _r["lounge"]
	if lounge.size.x > 0.0:
		_map.patron_points.append(Vector3(lounge.get_center().x, 0.0, lounge.end.y - 1.0))


# --- lighting ----------------------------------------------------------------

func _build_lighting() -> void:
	var outside: Dictionary = OUTSIDE.get(_casino.get("id", &""), OUTSIDE[&"sals_back_room"])
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = outside["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = WHITE.lerp(_accent_c, 0.3)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# The compatibility renderer's glow brightens the whole frame, not just
	# the emissive bits, so the bloom is a Forward+ nicety only.
	env.glow_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	_map.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "KeyLight"
	sun.rotation = Vector3(deg_to_rad(-62.0), deg_to_rad(-28.0), 0.0)
	sun.light_energy = 0.65
	sun.light_color = Color("fff1dc")
	sun.shadow_enabled = true
	_map.add_child(sun)

	for block: Dictionary in _plan["blocks"]:
		var rect: Rect2 = block["rect"]
		_omni(Vector3(rect.get_center().x, 3.6, rect.get_center().y), maxf(rect.size.x, rect.size.y) * 0.95, _accent_c.lerp(WHITE, 0.55), 1.1)
	var lobby: Rect2 = _r["lobby"]
	_omni(Vector3(lobby.get_center().x, 4.0, 1.5), 9.0, _accent_c, 1.3)
	var bar: Rect2 = _r["bar"]
	_omni(Vector3(bar.get_center().x, 2.8, bar.get_center().y), bar.size.x * 0.8, Color("ffcf8a"), 1.0)


func _omni(pos: Vector3, range_m: float, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.omni_range = range_m
	light.light_color = color
	light.light_energy = energy
	light.omni_attenuation = 0.8
	_map.add_child(light)


# --- low-level helpers -------------------------------------------------------

func _box_shape(size: Vector3) -> BoxShape3D:
	var key: String = str(size.snapped(Vector3.ONE * 0.001))
	if not _shapes.has(key):
		var s := BoxShape3D.new()
		s.size = size
		_shapes[key] = s
	return _shapes[key]


func _box_mesh(size: Vector3, color: Color, emission: float = 0.0) -> BoxMesh:
	var key: String = "b%s|%s|%.2f" % [str(size.snapped(Vector3.ONE * 0.001)), color.to_html(), emission]
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		m.material = Primitives.material(color, emission)
		_meshes[key] = m
	return _meshes[key]


func _cylinder_mesh(radius: float, height: float, color: Color, emission: float = 0.0) -> CylinderMesh:
	var key: String = "c%.3f|%.3f|%s|%.2f" % [radius, height, color.to_html(), emission]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = radius
		m.bottom_radius = radius
		m.height = height
		m.radial_segments = 10
		m.rings = 1
		m.material = Primitives.material(color, emission)
		_meshes[key] = m
	return _meshes[key]


func _sphere_mesh(radius: float, color: Color, emission: float) -> SphereMesh:
	var key: String = "s%.3f|%s|%.2f" % [radius, color.to_html(), emission]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * 2.0
		m.radial_segments = 10
		m.rings = 5
		m.material = Primitives.material(color, emission)
		_meshes[key] = m
	return _meshes[key]


## A static box on the world layer (part of the navmesh source).
func _solid(size: Vector3, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = _box_shape(size)
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size, color)
	body.add_child(mi)
	body.position = pos
	_static.add_child(body)
	return body


## A visual-only box.
func _vbox(size: Vector3, pos: Vector3, color: Color, emission: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size, color, emission)
	mi.position = pos
	if emission > 0.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_decor.add_child(mi)
	return mi


func _decor_mesh(mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	_decor.add_child(mi)
	return mi


func _child_mesh(parent: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func _reparent(node: Node3D, parent: Node3D, local_pos: Vector3) -> void:
	node.get_parent().remove_child(node)
	parent.add_child(node)
	node.position = local_pos


func _label(text: String, pos: Vector3, pixel_size: float, color: Color, billboard: bool = false) -> Label3D:
	var l := Primitives.label(text, pixel_size, color, billboard)
	l.font_size = 64
	l.position = pos
	_decor.add_child(l)
	return l
