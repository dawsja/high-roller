class_name CasinoMap
extends Node3D
## One casino's graybox level, made by CasinoBuilder.build(): geometry under
## the navigation region, zones, interactables, poster boards, and the anchors
## and points the director spawns things at. Add it to the tree, then call
## bake_navigation(). Purely spatial: it never changes chips, Heat, IDs or
## outfits; zones and interactables only emit signals.
##
## Static geometry lives under nav_region and is baked into the navmesh (static
## colliders on layer 1). Put props that should block navigation (table nodes)
## under `props_root` before baking.
##
## Points, transforms and zone rects are in the map's local space, which is
## world space while the map sits at the origin (the director's job). The
## front doors face +Z; the building runs toward -Z (see CasinoLayouts).

## The navmesh was (re)baked.
signal navigation_baked()

var nav_region: NavigationRegion3D
## Parent for extra static props that should be carved out of the navmesh.
var props_root: Node3D
var zones: Array[CasinoZone] = []
var interactables: Array[Interactable] = []
## {id: StringName, game_type: int, area_id: StringName, transform: Transform3D}.
## The transform is the table center on the floor; the seat side is local +Z.
var table_anchors: Array[Dictionary] = []
## Inside the entrance, one per crew member.
var spawn_points: Array[Vector3] = []
## Outside on the sidewalk (Sal's curb timeout).
var curb_point: Vector3
## Guards carry players here (inside the back room).
var back_room_point: Vector3
## Detained players rejoin here, on the floor outside the security office.
var back_room_release_point: Vector3
## Center of the exit pad outside (EXIT zone).
var exit_point: Vector3
## One looping Array[Vector3] per floor guard (at least casino.guards), all distinct.
var patrol_routes: Array = []
var pit_boss_posts: Array[Vector3] = []
## Wall-mounted in the floor's corners; -Z looks at the floor.
var camera_mounts: Array[Transform3D] = []
var patron_points: Array[Vector3] = []
## Patron seats at the decor slot machines; -Z faces the machine.
var slot_seats: Array[Transform3D] = []
## &"parking_garage" | &"restroom" | &"loading_dock" -> Vector3 (Forger.LOCATIONS).
var forger_points: Dictionary = {}
var poster_boards: Array[PosterBoardNode] = []

## The Tuning.CASINOS row this map was built for, and its size class.
var casino: Dictionary = {}
var size_class: StringName = &""
## Floor-space bounds of everything walkable (building, lot, dock).
var bounds: AABB

# Per player instance id: {zone: entry serial} of the zones it overlaps.
var _inside: Dictionary = {}
var _current: Dictionary = {}
var _players: Dictionary = {}
var _dirty: Dictionary = {}
var _serial: int = 0
var _flush_queued: bool = false


## Adds a zone and lets this map decide which zone a player counts as in.
func add_zone(zone: CasinoZone) -> void:
	zone.managed = true
	zone.body_entered.connect(_on_zone_body_entered.bind(zone))
	zone.body_exited.connect(_on_zone_body_exited.bind(zone))
	zones.append(zone)
	if zone.get_parent() == null:
		add_child(zone)


func add_interactable(it: Interactable, parent: Node = null) -> Interactable:
	interactables.append(it)
	if it.get_parent() == null:
		(parent if parent != null else self).add_child(it)
	return it


## Bakes the navmesh synchronously from the static colliders under nav_region.
## The navigation map picks it up a few physics frames later (it syncs
## asynchronously): check navigation_ready() or await await_navigation().
func bake_navigation() -> void:
	nav_region.bake_navigation_mesh(false)
	navigation_baked.emit()


func navigation_map() -> RID:
	return nav_region.get_navigation_map()


## True once the navigation map has synced this map's navmesh (path queries
## work): the floor at the first spawn point belongs to our region.
func navigation_ready() -> bool:
	if nav_region == null or not nav_region.is_inside_tree() or nav_polygon_count() == 0:
		return false
	var nav: RID = navigation_map()
	if not nav.is_valid() or NavigationServer3D.map_get_iteration_id(nav) == 0:
		return false
	var probe: Vector3 = to_global(spawn_points[0]) if not spawn_points.is_empty() else global_position
	if NavigationServer3D.map_get_closest_point_owner(nav, probe) != nav_region.get_rid():
		return false
	var hit: Vector3 = NavigationServer3D.map_get_closest_point(nav, probe)
	return Vector2(hit.x, hit.z).distance_to(Vector2(probe.x, probe.z)) < 0.5 and absf(hit.y - probe.y) < 1.0


## Waits (physics frames) until navigation_ready(); false if it took longer
## than max_frames.
func await_navigation(max_frames: int = 300) -> bool:
	for i in max_frames:
		if navigation_ready():
			return true
		await get_tree().physics_frame
	return navigation_ready()


func nav_polygon_count() -> int:
	if nav_region == null or nav_region.navigation_mesh == null:
		return 0
	return nav_region.navigation_mesh.get_polygon_count()


## The zone a player currently counts as standing in (null before any).
func zone_of(player: Node3D) -> CasinoZone:
	if player == null:
		return null
	var z: Variant = _current.get(player.get_instance_id())
	return z as CasinoZone if is_instance_valid(z) else null


## Forgets the zone `player` counts as in, so the next zone check announces
## where they stand again. For when the sim moved the player itself (a rejoin
## from the back room sets its zone without the world knowing).
func reset_zone(player: Node3D) -> void:
	if player == null:
		return
	var id: int = player.get_instance_id()
	_current.erase(id)
	_players[id] = player
	_mark_dirty(id)


func zones_of_type(zone_type: int) -> Array[CasinoZone]:
	var out: Array[CasinoZone] = []
	for z: CasinoZone in zones:
		if z.zone_type == zone_type:
			out.append(z)
	return out


## The first zone with this area id (and type, if given), or null.
func zone_by_area(area_id: StringName, zone_type: int = -1) -> CasinoZone:
	for z: CasinoZone in zones:
		if z.area_id == area_id and (zone_type < 0 or z.zone_type == zone_type):
			return z
	return null


## The most specific zone covering a floor point (what a player standing there
## would count as in), or null.
func zone_at(point: Vector3) -> CasinoZone:
	var best: CasinoZone = null
	for z: CasinoZone in zones:
		if not z.contains_point(point):
			continue
		if best == null or z.zone_priority > best.zone_priority or (z.zone_priority == best.zone_priority and z.floor_area() < best.floor_area()):
			best = z
	return best


func interactables_of(kind: StringName) -> Array[Interactable]:
	var out: Array[Interactable] = []
	for it: Interactable in interactables:
		if is_instance_valid(it) and it.kind == kind:
			out.append(it)
	return out


func table_anchor(table_id: StringName) -> Dictionary:
	for a: Dictionary in table_anchors:
		if a["id"] == table_id:
			return a
	return {}


func poster_board(board_id: StringName) -> PosterBoardNode:
	for b: PosterBoardNode in poster_boards:
		if b.board_id == board_id:
			return b
	return null


## Redraws every poster board (dicts as FloorSim.posters_here()).
func show_posters(posters: Array) -> void:
	for b: PosterBoardNode in poster_boards:
		b.show_posters(posters)


## Enables only the forger interactable at `location` (the others stay put
## but can't be used).
func set_forger_location(location: StringName) -> void:
	for it: Interactable in interactables_of(&"forger"):
		it.enabled = it.data.get("location", &"") == location


func _on_zone_body_entered(body: Node3D, zone: CasinoZone) -> void:
	var id: int = body.get_instance_id()
	if not _inside.has(id):
		_inside[id] = {}
	_serial += 1
	(_inside[id] as Dictionary)[zone] = _serial
	_players[id] = body
	_mark_dirty(id)


func _on_zone_body_exited(body: Node3D, zone: CasinoZone) -> void:
	var id: int = body.get_instance_id()
	if _inside.has(id):
		(_inside[id] as Dictionary).erase(zone)
	_mark_dirty(id)


func _mark_dirty(id: int) -> void:
	_dirty[id] = true
	if not _flush_queued:
		_flush_queued = true
		_flush_zones.call_deferred()


## Settles each moved player on its best zone: highest priority, then the most
## recently entered. Announces only real changes; a player who left every zone
## keeps the last one.
func _flush_zones() -> void:
	_flush_queued = false
	var ids: Array = _dirty.keys()
	_dirty.clear()
	for id: int in ids:
		var body: Variant = _players.get(id)
		if not is_instance_valid(body):
			_inside.erase(id)
			_current.erase(id)
			_players.erase(id)
			continue
		var entries: Dictionary = _inside.get(id, {})
		var best: CasinoZone = null
		var best_serial := -1
		for z: Variant in entries.keys():
			if not is_instance_valid(z):
				entries.erase(z)
				continue
			var zone := z as CasinoZone
			var serial: int = entries[z]
			if best == null or zone.zone_priority > best.zone_priority or (zone.zone_priority == best.zone_priority and serial > best_serial):
				best = zone
				best_serial = serial
		if best == null or _current.get(id) == best:
			continue
		_current[id] = best
		best.announce(body as Node3D)
