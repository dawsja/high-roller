class_name CasinoDirector
extends Node3D
## One casino visit in the world: builds the CasinoMap, spawns tables, the
## crew's PlayerCharacters, security, patrons and the forger, and wires them
## to the simulation (docs/ARCHITECTURE.md, "World layer"). Gameplay nodes only
## emit signals; this node turns them into SimHost requests and feeds every
## sim event back to the world and the UI. It never changes chips, Heat, IDs
## or outfits itself.
##
## Lifecycle: add it to the tree, call setup(). Guards and patrons wait
## (process disabled) until the navmesh has synced, then npcs_activated fires.
## When the visit ends (thrown out, climbed, or the run ended at the top
## exit) it stops the player and emits visit_finished(outcome) after
## visit_end_delay seconds; main.gd frees it and starts the next visit.
##
## Co-op (docs/ARCHITECTURE.md, "Networking"): every peer builds the same
## visit from SimHost.visit_info() (same map seed, same node names). The
## `authority` (the host, or offline) runs guards, cameras and patrons and
## sends their state to the clients through MultiplayerSynchronizers; a
## client's copies are puppets. Each peer moves only its own player; the
## others are puppets of their owners. Placements the sim decides (sit,
## stand, carry, release, back room, rejoin, curb) are host -> owner
## &"place" world messages. A client's tackles, bumps, struggles and top-exit
## presses go to the host as world messages; its own zones and interactions
## become requests that the host validates. A client sends &"ready" once it
## has built the visit; synchronizers only send to peers that are ready.

## &"thrown_out", &"climbed" or OUTCOME_RUN_OVER.
signal visit_finished(outcome: StringName)
## The local player pressed pause.
signal pause_requested()
## Guards and patrons started moving (the navmesh is ready).
signal npcs_activated()

const LOCAL_PID := 1
## The crew left the top casino through its exit: the run is over.
const OUTCOME_RUN_OVER := &"run_over"
## Physics frames to wait for the navmesh before starting NPCs anyway.
const NAV_WAIT_MAX_FRAMES := 300
## Co-op host: real seconds to wait for every client to build the visit
## before the guards start anyway.
const READY_WAIT_SECONDS := 10.0
## Co-op host: a client's interaction, tackle or zone this much further
## (flat metres) than the local rules allow is refused (sync lag allowance).
const NET_REACH_SLACK := 2.5
## Give chips (H): this share of the pocket, at least the casino's min bet.
const GIVE_CHIPS_SHARE := 0.5
const NAMEPLATE_REFRESH_SECONDS := 0.25
## --net-log: the host sends guard positions this often (real seconds).
const PROBE_SECONDS := 0.5
const COAT_COLOR := Color("9b7b52")
## The forger's collision capsule (his trench coat's width).
const FORGER_RADIUS := 0.36
const FORGER_HEIGHT := 1.8
const NOISE_COLOR := Color(1.0, 0.85, 0.3, 0.5)
const ALARM_COLOR := Color(1.0, 0.1, 0.05)
const FORGER_LOOK := {"hat": "high_roller_fedora", "glasses": "aviator_shades", "top": "biker_jacket", "bottom": "pressed_slacks", "accessory": "none"}
const SECURITY_NAMES := {
	HR.SecurityType.FLOOR_GUARD: "guard", HR.SecurityType.CAMERA: "camera", HR.SecurityType.PIT_BOSS: "pit boss",
	HR.SecurityType.UNDERCOVER: "undercover", HR.SecurityType.HEAD_OF_SECURITY: "head",
}

var host: SimHost
var rung: int = Tuning.BOTTOM_RUNG
var practice: bool = false
var casino: Dictionary = {}
var map: CasinoMap
## This peer's player.
var player: PlayerCharacter
## pid -> PlayerCharacter for the whole crew.
var players: Dictionary = {}
## table id -> TableNode.
var tables: Dictionary = {}
var guards: Array[GuardNPC] = []
var cameras: Array[SecurityCamera] = []
var crowd: PatronCrowd
## The forger NPC (moves on &"forger_moved"), its body and its interactable.
var forger_npc: Node3D
var forger_model: CharacterModel
## A world-layer capsule so nobody walks through him (built on every peer).
var forger_body: StaticBody3D
var forger_interactable: Interactable
## Parent of guards, patrons and the forger (process disabled until the navmesh is ready).
var npc_root: Node3D
var npcs_active: bool = false
## The visit is over (thrown out, climbed, run over); requests stop.
var finished: bool = false
var outcome: StringName = &""
## Seconds between the end of the visit and visit_finished.
var visit_end_delay: float = Tuning.DIRECTOR_VISIT_END_SECONDS
## Set by main.gd while the pause menu is open: the player gets no input.
var input_blocked: bool = false
## What security_plan() gave for this visit.
var plan: Dictionary = {}
## This peer's pid (host.local_pid; LOCAL_PID offline).
var local_pid: int = LOCAL_PID
## A co-op session (host or client).
var online: bool = false
## Runs guards, cameras, patrons and player flags: offline and on the host.
var authority: bool = true
## Co-op: pids whose peers have built this visit (synchronizers send to them).
var ready_peers: Array[int] = []
## Co-op: the visit ended and this peer's synchronizers stopped sending.
var net_stopped: bool = false

# UI (all optional; tests may leave them out).
var hud: Hud
var bet_panel: BetPanel
var quiz_panel: IdQuizPanel
var cashier_panel: CashierPanel
var wardrobe_panel: WardrobePanel
var forger_panel: ForgerPanel
var visit_banner: VisitBanner
var debug_overlay: DebugOverlay

var _fx_root: Node3D
var _alarm_light: OmniLight3D
var _time: float = 0.0
var _nav_frames: int = 0
var _ready_wait_until_msec: int = 0
var _finish_left: float = -1.0
var _finish_emitted: bool = false
var _provider_cache: Array = []
var _provider_frame: int = -1
var _provider_dirty: bool = true
## pid -> sim matches_poster (refreshed from report_seen and poster/outfit events).
var _poster_match: Dictionary = {}
## pid -> time a guard last saw them / saw them running.
var _seen_at: Dictionary = {}
var _running_seen_at: Dictionary = {}
## pid -> time of the last report_seen.
var _reported_at: Dictionary = {}
## pid -> {camera instance id: true} of cameras watching.
var _camera_watch: Dictionary = {}
## pid -> flags last sent with set_player_flags.
var _flags_sent: Dictionary = {}
## pid -> GuardNPC carrying them.
var _carriers: Dictionary = {}
## pid -> outfit dict the node wears.
var _worn: Dictionary = {}
## table id -> true: celebrate when its result has been shown.
var _celebrate: Dictionary = {}
var _input_on: bool = true
var _input_known: bool = false
var _prompt: String = ""
var _focus: Interactable
## A give-chips press (H) is waiting for its answer.
var _giving: bool = false
var _nameplate_left: float = 0.0
var _probe_due_msec: int = 0
## --net-log, client: [msec, position] of the local player over the last second.
var _trail: Array = []
## --net-log, host: pid -> msec a guard grabbed them.
var _grabbed_at: Dictionary = {}


## Builds the visit. `ui` holds the UI nodes main.gd owns, any of: hud,
## bet_panel, quiz_panel, cashier_panel, wardrobe_panel, forger_panel,
## visit_banner, debug_overlay. Needs this node in the tree (the navmesh is
## baked here) and the visit started: host.start_visit() on the host and
## offline, the host's visit announced on a client.
func setup(p_host: SimHost, p_rung: int, p_practice: bool, ui: Dictionary = {}) -> void:
	if not is_inside_tree():
		push_error("CasinoDirector.setup: add the director to the tree first")
		return
	host = p_host
	authority = host.is_authority()
	online = host.is_online()
	local_pid = host.local_pid
	practice = p_practice
	var info: Dictionary = host.visit_info()
	var sim := _sim()
	if authority:
		if sim == null:
			push_error("CasinoDirector.setup: the host has no visit (call host.start_visit())")
			return
		rung = sim.run.rung
		casino = sim.casino()
	else:
		if info.is_empty():
			push_error("CasinoDirector.setup: no visit announced by the host yet")
			return
		rung = int(info.get("rung", Tuning.BOTTOM_RUNG))
		casino = CasinoLadder.casino(rung)
		practice = bool(info.get("practice", p_practice))
	if p_rung != rung:
		push_warning("CasinoDirector.setup: rung %d asked, the sim is at rung %d" % [p_rung, rung])
	name = "CasinoDirector_%s" % String(casino.get("id", &"casino"))
	_take_ui(ui)
	var seed_value: int = int(info.get("map_seed", 0))
	if not info.has("map_seed") and sim != null:
		seed_value = hash([String(casino.get("id", &"")), sim.run.visits, rung])

	map = CasinoBuilder.build(casino, seed_value)
	add_child(map)
	_spawn_tables()
	map.bake_navigation()
	_fx_root = Node3D.new()
	_fx_root.name = "Effects"
	add_child(_fx_root)
	_build_alarm_light()
	npc_root = Node3D.new()
	npc_root.name = "NPCs"
	npc_root.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(npc_root)

	_spawn_players()
	for zone: CasinoZone in map.zones:
		zone.player_entered.connect(_on_zone_entered)
	plan = security_plan(casino, practice, map.pit_boss_posts.size(), map.camera_mounts.size())
	_spawn_security()
	_spawn_crowd(seed_value)
	_spawn_forger()
	_setup_exit()
	_refresh_posters()
	if authority:
		_refresh_poster_matches()
	if _fire_alarm_active():
		_set_fire_alarm(true)
	host.sim_event.connect(_on_sim_event)
	host.request_done.connect(_on_request_done)
	host.world_message.connect(_on_world_message)
	_connect_ui()
	_close_panels()
	_sync_input(true)
	_welcome()
	if online:
		_start_net()


## Security for a casino row: {floor, undercover, head, pit_boss, cameras}.
## The casino's `guards` count is every walking guard (floor guards plus the
## undercover and the head of security); pit bosses (one per table area post,
## at most DIRECTOR_MAX_PIT_BOSSES) and cameras (one per mount) come on top
## when the casino's security list has them. Practice: one floor guard only.
static func security_plan(casino_row: Dictionary, practice_mode: bool, pit_posts: int, camera_mounts: int) -> Dictionary:
	var out := {"floor": 1, "undercover": 0, "head": 0, "pit_boss": 0, "cameras": 0}
	if practice_mode:
		return out
	var kinds: Array = casino_row.get("security", [])
	var total: int = maxi(1, int(casino_row.get("guards", 1)))
	out["undercover"] = 1 if kinds.has(HR.SecurityType.UNDERCOVER) and total > 1 else 0
	out["head"] = 1 if kinds.has(HR.SecurityType.HEAD_OF_SECURITY) and total - int(out["undercover"]) > 1 else 0
	out["floor"] = total - int(out["undercover"]) - int(out["head"])
	if kinds.has(HR.SecurityType.PIT_BOSS):
		out["pit_boss"] = mini(Tuning.DIRECTOR_MAX_PIT_BOSSES, pit_posts)
	if kinds.has(HR.SecurityType.CAMERA):
		out["cameras"] = camera_mounts
	return out


## players_provider for guards and cameras: {pid, node, heat, matches_poster,
## staff_uniform, available, cleared} per crew member (rebuilt once per
## physics frame; available = PlayerState.is_targetable(), cleared =
## id_cleared()).
## Every player's node counts, so the host's guards see clients' synced bodies.
func players_info() -> Array:
	var frame: int = Engine.get_physics_frames()
	if not _provider_dirty and frame == _provider_frame:
		return _provider_cache
	_provider_frame = frame
	_provider_dirty = false
	_provider_cache = []
	var sim := _sim()
	if sim == null:
		return _provider_cache
	for pid: int in players:
		var ps := sim.player(pid)
		var node: PlayerCharacter = players[pid]
		if ps == null or not is_instance_valid(node):
			continue
		_provider_cache.append({
			"pid": pid,
			"node": node,
			"heat": ps.heat.value,
			"matches_poster": bool(_poster_match.get(pid, false)),
			"staff_uniform": ps.outfit.is_staff_uniform(),
			"available": ps.is_targetable(),
			"cleared": ps.id_cleared(),
		})
	return _provider_cache


## Re-applies the player's input state (main.gd calls this after the pause menu).
func sync_input(force: bool = false) -> void:
	_sync_input(force)


## Uses an interactable as `pid` (what the player's interact press / hold does).
## Results come back as host.request_done.
func interact(pid: int, target: Interactable, held: bool = false) -> void:
	if finished or target == null or not is_instance_valid(target) or not target.enabled:
		return
	var node: PlayerCharacter = players.get(pid)
	target.use(node)
	var pos: Vector3 = target.global_position
	var mine: bool = pid == local_pid
	match target.kind:
		&"table":
			var table_id: StringName = StringName(str(target.data.get("table_id", "")))
			if _p_table(pid) == table_id:
				return
			host.request_sit(pid, table_id, _seen_recently(pid))
		&"cashier":
			if cashier_panel != null and mine:
				cashier_panel.open()
		&"restroom":
			if wardrobe_panel != null and mine:
				wardrobe_panel.open_mode(WardrobePanel.MODE_RESTROOM)
		&"gift_shop":
			if wardrobe_panel != null and mine:
				wardrobe_panel.open_mode(WardrobePanel.MODE_GIFT_SHOP)
		&"laundry_cart", &"staff_locker":
			if wardrobe_panel != null and mine:
				wardrobe_panel.open_mode(WardrobePanel.MODE_STEAL, target.kind)
		&"forger":
			if forger_panel != null and mine:
				forger_panel.open()
		&"poster":
			var poster_id: int = int(target.data.get("poster_id", -1))
			if held:
				host.request_tear_poster(pid, poster_id, pos)
			else:
				host.request_deface_poster(pid, poster_id)
		&"tray":
			_knock_over(pid, target)
		&"fire_alarm":
			host.request_distraction(pid, HR.Distraction.FIRE_ALARM, pos)
		&"slot_alarm":
			host.request_distraction(pid, HR.Distraction.SLOT_ALARM, pos)
		&"exit":
			_use_exit(pid)


## Co-op: drops a player who left the session (their body goes; a guard
## carrying them lets go).
func remove_player(pid: int) -> void:
	var node: PlayerCharacter = players.get(pid)
	players.erase(pid)
	_carriers.erase(pid)
	_worn.erase(pid)
	_flags_sent.erase(pid)
	_camera_watch.erase(pid)
	ready_peers.erase(pid)
	_provider_dirty = true
	if authority:
		for g: GuardNPC in guards:
			if g.carrying_pid() == pid:
				g.stun()
	if node != null and is_instance_valid(node):
		node.queue_free()
	NetLog.line("player_removed", {"pid": pid})


# --- Build --------------------------------------------------------------------

func _take_ui(ui: Dictionary) -> void:
	hud = ui.get("hud") as Hud
	bet_panel = ui.get("bet_panel") as BetPanel
	quiz_panel = ui.get("quiz_panel") as IdQuizPanel
	cashier_panel = ui.get("cashier_panel") as CashierPanel
	wardrobe_panel = ui.get("wardrobe_panel") as WardrobePanel
	forger_panel = ui.get("forger_panel") as ForgerPanel
	visit_banner = ui.get("visit_banner") as VisitBanner
	debug_overlay = ui.get("debug_overlay") as DebugOverlay


func _spawn_tables() -> void:
	for anchor: Dictionary in map.table_anchors:
		var id: StringName = anchor["id"]
		var t := TableNode.new()
		t.setup(id, int(anchor["game_type"]), anchor["area_id"], rung)
		var xf: Transform3D = anchor["transform"]
		t.transform = xf
		map.props_root.add_child(t)
		tables[id] = t
		host.request_register_table(id, int(anchor["game_type"]), anchor["area_id"], map.to_global(xf.origin))
		t.result_shown.connect(_on_result_shown)


func _spawn_players() -> void:
	var i := 0
	for pid: int in host.player_ids():
		_spawn_player(pid, i)
		i += 1


func _spawn_player(pid: int, index: int) -> PlayerCharacter:
	var node := PlayerCharacter.new()
	node.name = "Player_%d" % pid
	var spawn: Vector3 = map.spawn_points[index % map.spawn_points.size()] if not map.spawn_points.is_empty() else Vector3.ZERO
	node.position = map.to_global(spawn)
	var local: bool = pid == local_pid
	if online:
		node.set_multiplayer_authority(pid)
	add_child(node)
	var look := _outfit_dict(pid)
	node.setup(pid, local, Outfit.from_dict(look))
	_worn[pid] = look
	players[pid] = node
	if online:
		node.enable_net_sync()
		if not local:
			node.make_puppet(node.global_position)
			node.set_nameplate(_name_of(pid))
	if local:
		player = node
		node.focus_changed.connect(_on_focus_changed)
		node.pause_requested.connect(_on_pause_requested)
	if local or not online:
		node.interact_pressed.connect(_on_interact_pressed.bind(node))
		node.interact_held.connect(_on_interact_held.bind(node))
		node.tackle_requested.connect(_on_tackle_requested.bind(node))
		node.bumped.connect(_on_bumped.bind(node))
		node.throw_chips_requested.connect(_on_throw_chips.bind(node))
		node.knock_over_requested.connect(_on_knock_over_requested.bind(node))
		node.struggled.connect(_on_struggled.bind(node))
		node.stand_requested.connect(_on_stand_requested.bind(node))
		node.give_chips_requested.connect(_on_give_chips_requested.bind(node))
	NetLog.line("spawned", {"pid": pid, "node": node.name, "local": local})
	return node


func _spawn_security() -> void:
	var route_index := 0
	for i in int(plan["floor"]):
		_spawn_guard(HR.SecurityType.FLOOR_GUARD, _route(route_index))
		route_index += 1
	if int(plan["undercover"]) > 0:
		_spawn_guard(HR.SecurityType.UNDERCOVER, _route(route_index))
		route_index += 1
	if int(plan["head"]) > 0:
		_spawn_guard(HR.SecurityType.HEAD_OF_SECURITY, _route(route_index))
		route_index += 1
	for i in int(plan["pit_boss"]):
		var post: Vector3 = map.to_global(map.pit_boss_posts[i])
		var points: Array[Vector3] = [post]
		var boss := _spawn_guard(HR.SecurityType.PIT_BOSS, points)
		# Posts are on the aisle west of their table area: watch the tables.
		boss.face_toward(post + Vector3.RIGHT * 4.0)
		if boss.puppet:
			boss.net_facing = boss.facing
	for i in int(plan["cameras"]):
		var cam := SecurityCamera.new()
		cam.name = "Camera%d" % (i + 1)
		cam.puppet = not authority
		add_child(cam)
		cam.setup(i + 1, map.global_transform * map.camera_mounts[i], players_info)
		if authority:
			cam.watching.connect(_on_camera_watching)
			cam.spotted.connect(_on_camera_spotted)
		# Both sides need the synchronizer: the host sends, a client applies.
		if online:
			cam.enable_net_sync()
		cameras.append(cam)


func _route(index: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if map.patrol_routes.is_empty():
		out.append(map.to_global(map.spawn_points[0] if not map.spawn_points.is_empty() else Vector3.ZERO))
		return out
	var src: Array = map.patrol_routes[index % map.patrol_routes.size()]
	for p: Vector3 in src:
		out.append(map.to_global(p))
	return out


func _spawn_guard(kind: int, route: Array[Vector3]) -> GuardNPC:
	var g := GuardNPC.new()
	var id: int = guards.size() + 1
	g.name = "Guard%d_%s" % [id, str(SECURITY_NAMES.get(kind, "guard")).replace(" ", "_")]
	g.position = route[0] if not route.is_empty() else Vector3.ZERO
	g.puppet = not authority
	npc_root.add_child(g)
	g.setup(id, kind, route, map.to_global(map.back_room_point), players_info)
	if authority:
		g.saw_player.connect(_on_guard_saw)
		g.id_check_requested.connect(_on_guard_id_check)
		g.grabbed.connect(_on_guard_grabbed)
		g.delivered.connect(_on_guard_delivered)
		g.released.connect(_on_guard_released)
		g.radioed.connect(_on_guard_radioed)
	if online:
		g.enable_net_sync()
	guards.append(g)
	return g


func _spawn_crowd(seed_value: int) -> void:
	crowd = PatronCrowd.new()
	crowd.name = "Crowd"
	crowd.puppet = not authority
	npc_root.add_child(crowd)
	var points: Array[Vector3] = []
	for p: Vector3 in map.patron_points:
		points.append(map.to_global(p))
	var seats: Array[Transform3D] = []
	for s: Transform3D in map.slot_seats:
		seats.append(map.global_transform * s)
	var counts: Dictionary = Tuning.DIRECTOR_PATRONS
	crowd.setup(points, seats, int(counts.get(map.size_class, counts[&"small"])), seed_value)
	if online:
		crowd.enable_net_sync()


func _spawn_forger() -> void:
	# The map has a forger interactable at every spot; the NPC carries its own.
	for it: Interactable in map.interactables_of(&"forger"):
		it.enabled = false
	forger_npc = Node3D.new()
	forger_npc.name = "Forger"
	npc_root.add_child(forger_npc)
	forger_model = CharacterModel.new()
	forger_model.name = "Model"
	forger_model.appearance_seed = 4242
	forger_model.apply_outfit(Outfit.from_dict(FORGER_LOOK))
	forger_npc.add_child(forger_model)
	# A long trench coat over the jacket.
	var coat := Primitives.cylinder(0.36, 0.98, COAT_COLOR, 10, 0.29)
	coat.name = "TrenchCoat"
	coat.position = Vector3(0, 0.93, 0)
	forger_model.add_child(coat)
	var collar := Primitives.box(Vector3(0.5, 0.12, 0.32), COAT_COLOR.darkened(0.15))
	collar.position = Vector3(0, 1.44, 0)
	forger_model.add_child(collar)
	# Solid like a wall (layer 1) for players, guards and patrons. Walking up to
	# him stops a body's width away, well inside the interact reach below.
	# Kept in the physics space while npc_root waits for the navmesh.
	forger_body = StaticBody3D.new()
	forger_body.name = "Body"
	forger_body.collision_layer = CasinoBuilder.WORLD_LAYER
	forger_body.collision_mask = 0
	forger_body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = FORGER_RADIUS
	capsule.height = FORGER_HEIGHT
	shape.shape = capsule
	shape.position = Vector3(0, FORGER_HEIGHT * 0.5, 0)
	forger_body.add_child(shape)
	forger_npc.add_child(forger_body)
	# Guards' avoidance steps round him (he isn't in the baked navmesh).
	var obstacle := NavigationObstacle3D.new()
	obstacle.name = "Obstacle"
	obstacle.radius = FORGER_RADIUS + 0.1
	obstacle.avoidance_enabled = true
	forger_npc.add_child(obstacle)
	# Small reach (+ the player's 1.5 m sensor): buy_id needs the player inside
	# the forger's 4 m corner zone, and the restroom corner backs onto a wall.
	forger_interactable = Interactable.create(&"forger", "Buy a fake ID", 0.25, {"location": &""})
	forger_interactable.position = Vector3(0, 1.0, 0)
	forger_npc.add_child(forger_interactable)
	_move_forger(_forger_location())


func _move_forger(location: StringName) -> void:
	if forger_npc == null or not map.forger_points.has(location):
		return
	var p: Vector3 = map.to_global(map.forger_points[location])
	forger_npc.global_position = p
	forger_interactable.data["location"] = location
	var center: Vector3 = map.to_global(map.bounds.get_center())
	var to := center - p
	to.y = 0.0
	if to.length_squared() > 0.01:
		forger_npc.rotation.y = atan2(-to.x, -to.z)


func _setup_exit() -> void:
	for it: Interactable in map.interactables_of(&"exit"):
		if rung == Tuning.TOP_RUNG:
			it.prompt = "Walk out of The Apex (end the run)"
		else:
			var above: Dictionary = CasinoLadder.casino(rung - 1)
			it.prompt = "Climb to %s" % str(above.get("name", "the next casino"))


func _build_alarm_light() -> void:
	_alarm_light = OmniLight3D.new()
	_alarm_light.name = "FireAlarmLight"
	_alarm_light.light_color = ALARM_COLOR
	_alarm_light.omni_range = maxf(map.bounds.size.x, map.bounds.size.z)
	_alarm_light.light_energy = 0.0
	_alarm_light.visible = false
	_alarm_light.position = map.to_global(map.bounds.get_center()) + Vector3.UP * 4.0
	_fx_root.add_child(_alarm_light)


func _connect_ui() -> void:
	if bet_panel != null:
		bet_panel.leave_requested.connect(_on_bet_leave)
	if debug_overlay != null:
		debug_overlay.set_guard_provider(_guard_lines)


func _disconnect_ui() -> void:
	if host != null:
		if host.sim_event.is_connected(_on_sim_event):
			host.sim_event.disconnect(_on_sim_event)
		if host.request_done.is_connected(_on_request_done):
			host.request_done.disconnect(_on_request_done)
		if host.world_message.is_connected(_on_world_message):
			host.world_message.disconnect(_on_world_message)
		if authority and online:
			for request: StringName in [&"sit", &"give_chips", &"enter_zone"]:
				host.set_validator(request, Callable())
	if bet_panel != null and is_instance_valid(bet_panel) and bet_panel.leave_requested.is_connected(_on_bet_leave):
		bet_panel.leave_requested.disconnect(_on_bet_leave)
	if debug_overlay != null and is_instance_valid(debug_overlay):
		debug_overlay.set_guard_provider(Callable())
	if hud != null and is_instance_valid(hud):
		hud.set_prompt("")


func _close_panels() -> void:
	for p: Variant in [bet_panel, cashier_panel, wardrobe_panel, forger_panel, quiz_panel]:
		if p != null and is_instance_valid(p) and p.has_method(&"close"):
			p.call(&"close")


func _welcome() -> void:
	if hud == null:
		return
	var text := "Welcome to %s." % str(casino.get("name", "the casino"))
	if practice:
		text = "Practice at %s: one sleepy guard. Win, then cool off." % str(casino.get("name", ""))
	if online and players.size() > 1:
		text += " Crew of %d." % players.size()
	hud.push_notification(text, UiTheme.GOLD_LIGHT)
	hud.show_banner(str(casino.get("name", "")).to_upper(), UiTheme.GOLD, Tuning.UI_BANNER_SECONDS)


func _exit_tree() -> void:
	_disconnect_ui()


func _unhandled_input(event: InputEvent) -> void:
	# Seated with the bet panel open the player reads no input, but chips can
	# still be thrown from the table.
	if player == null or finished or input_blocked or player.state != PlayerCharacter.STATE_SEATED:
		return
	if InputMap.has_action(&"throw_chips") and event.is_action_pressed(&"throw_chips"):
		_on_throw_chips(player.global_position + player.front_direction() * Tuning.PLAYER_THROW_DISTANCE, player)
		get_viewport().set_input_as_handled()


# --- Co-op ----------------------------------------------------------------------

func _start_net() -> void:
	if authority:
		ready_peers.assign([local_pid])
		_ready_wait_until_msec = Time.get_ticks_msec() + int(READY_WAIT_SECONDS * 1000.0)
		host.set_validator(&"sit", _validate_sit)
		host.set_validator(&"give_chips", _validate_give_chips)
		host.set_validator(&"enter_zone", _validate_enter_zone)
		_apply_ready(ready_peers)
	else:
		# The host built this visit before announcing it.
		_apply_ready([1, local_pid])
		host.send_world(1, &"ready", {})


## Lets every ready peer receive the synchronizers this peer owns.
func _apply_ready(pids: Array) -> void:
	ready_peers.assign(pids)
	if net_stopped:
		return
	for node: Node in _owned_synced():
		NetSync.show_to(node, ready_peers, local_pid)
	NetLog.line("ready_peers", {"pids": ready_peers})


## The visit is over: stop sending, so nothing is in flight for nodes the
## other peers are about to free when the next visit starts.
func _stop_net_sync() -> void:
	if net_stopped:
		return
	net_stopped = true
	for node: Node in _owned_synced():
		NetSync.hide_from(node, ready_peers, local_pid)
	NetLog.line("sync_stopped", {})


## The synced nodes this peer sends: its own player, plus every NPC on the host.
func _owned_synced() -> Array[Node]:
	var owned: Array[Node] = []
	if players.has(local_pid):
		owned.append(players[local_pid])
	if authority:
		owned.append_array(guards)
		owned.append_array(cameras)
		if crowd != null:
			owned.append(crowd)
	return owned


## Host: every crew member's peer has built the visit (or we gave up waiting).
func _peers_ready() -> bool:
	if not (online and authority):
		return true
	if Time.get_ticks_msec() >= _ready_wait_until_msec:
		return true
	for pid: int in players:
		if not ready_peers.has(pid):
			return false
	return true


func _on_world_message(kind: StringName, data: Dictionary, from_pid: int) -> void:
	var from_host: bool = from_pid == 1
	match kind:
		&"ready":
			if authority and not ready_peers.has(from_pid) and players.has(from_pid):
				var pids: Array = ready_peers.duplicate()
				pids.append(from_pid)
				_apply_ready(pids)
				host.send_world(0, &"ready_peers", {"pids": pids})
		&"ready_peers":
			if not authority and from_host and data.get("pids") is Array:
				_apply_ready(data["pids"])
		&"place":
			if not authority and from_host and int(data.get("pid", 0)) == local_pid:
				_apply_place(local_pid, StringName(str(data.get("mode", ""))), data)
		&"tackle":
			if authority and _can_reach_guard(from_pid, int(data.get("guard_id", -1)), Tuning.TACKLE_RANGE):
				_tackle(from_pid, _guard_by_id(int(data.get("guard_id", -1))))
		&"bump":
			if authority and _can_reach_guard(from_pid, int(data.get("guard_id", -1)), Tuning.TACKLE_RANGE):
				_bump(from_pid, _guard_by_id(int(data.get("guard_id", -1))))
		&"struggle":
			var g: GuardNPC = _carriers.get(from_pid)
			if authority and g != null and is_instance_valid(g):
				g.on_struggle()
		&"exit":
			if authority and rung == Tuning.TOP_RUNG:
				_leave_top(from_pid)
		&"run_over":
			if not authority and from_host:
				_end_visit(OUTCOME_RUN_OVER)
		&"notice":
			if from_host:
				_notify(local_pid, str(data.get("text", "")), UiTheme.LOSS_COLOR)
		&"probe":
			if not authority and from_host:
				_check_probe(data)


## Host: moves `pid`'s body. Its owner applies it (a &"place" message to a
## client; directly for this peer's own player and offline).
func _place_player(pid: int, mode: StringName, data: Dictionary = {}) -> void:
	if not online or pid == local_pid:
		_apply_place(pid, mode, data)
		return
	var msg := data.duplicate()
	msg["pid"] = pid
	msg["mode"] = mode
	host.send_world(pid, &"place", msg)


func _apply_place(pid: int, mode: StringName, data: Dictionary) -> void:
	var node: PlayerCharacter = players.get(pid)
	if node == null or not is_instance_valid(node):
		return
	var at: Variant = data.get("at")
	match mode:
		&"sit":
			var seat: Variant = data.get("seat")
			if seat is Transform3D:
				node.sit_at(seat)
				_face_camera(node)
		&"stand":
			if node.state == PlayerCharacter.STATE_SEATED:
				node.stand_up()
			_reset_camera(node)
		&"carry":
			var g := _guard_by_id(int(data.get("guard_id", -1)))
			if g != null:
				_carriers[pid] = g
				node.set_carried(g)
		&"release":
			if not authority:
				_carriers.erase(pid)
			if node.is_carried() and at is Vector3:
				node.release(at)
		&"hide":
			if not authority:
				_carriers.erase(pid)
			node.set_hidden(true)
			if at is Vector3:
				node.teleport(at)
		&"show":
			node.set_hidden(false)
			if at is Vector3:
				node.teleport(at)
			if bool(data.get("reset_zone", false)):
				# The sim moved the player's zone; let the map announce the real one.
				map.reset_zone(node)
	NetLog.line("placed", {"pid": pid, "mode": mode})


## Host: tells `pid` something (a HUD notification on their screen).
func _notice(pid: int, text: String) -> void:
	if pid == local_pid or not online:
		_notify(pid, text, UiTheme.LOSS_COLOR)
	else:
		host.send_world(pid, &"notice", {"text": text})


## Host: the player's synced body is close enough to guard `guard_id`.
func _can_reach_guard(pid: int, guard_id: int, reach: float) -> bool:
	var node: PlayerCharacter = players.get(pid)
	var g := _guard_by_id(guard_id)
	if node == null or g == null:
		return false
	return Perception.flat_distance(node.global_position, g.global_position) <= reach + NET_REACH_SLACK


func _validate_sit(sender: int, args: Array) -> StringName:
	var node: PlayerCharacter = players.get(sender)
	var t: TableNode = tables.get(args[1])
	if node == null or t == null:
		return FloorSim.NO_REASON
	var reach: float = t.interactable.get_radius() + Tuning.PLAYER_INTERACT_RADIUS + Tuning.PLAYER_INTERACT_REACH + NET_REACH_SLACK
	if Perception.flat_distance(node.global_position, t.interactable.global_position) > reach:
		return &"too_far"
	# Whether a guard saw them jump tables is the host's call.
	args[2] = _seen_recently(sender)
	return FloorSim.NO_REASON


func _validate_give_chips(sender: int, args: Array) -> StringName:
	var from: PlayerCharacter = players.get(sender)
	var to: PlayerCharacter = players.get(int(args[1]))
	if from == null or to == null:
		return FloorSim.UNKNOWN_PLAYER
	if Perception.flat_distance(from.global_position, to.global_position) > PlayerCharacter.GIVE_RANGE + NET_REACH_SLACK:
		return &"too_far"
	return FloorSim.NO_REASON


func _validate_enter_zone(sender: int, args: Array) -> StringName:
	var node: PlayerCharacter = players.get(sender)
	if node == null:
		return FloorSim.UNKNOWN_PLAYER
	var at := map.to_local(node.global_position)
	for zone: CasinoZone in map.zones:
		if zone.zone_type != int(args[1]) or zone.area_id != StringName(args[2]):
			continue
		for r: Rect2 in zone.rects():
			if r.grow(NET_REACH_SLACK).has_point(Vector2(at.x, at.z)):
				return FloorSim.NO_REASON
	return FloorSim.WRONG_ZONE


## Host, top rung: the crew walks out (the run ends) once everyone who isn't
## detained is free on the exit pad.
func _leave_top(pid: int) -> void:
	if finished:
		return
	var sim := _sim()
	if sim != null:
		for other: int in sim.player_ids():
			var ps := sim.player(other)
			if ps.status == HR.PlayerStatus.DETAINED:
				continue
			if ps.status != HR.PlayerStatus.FREE or ps.zone != HR.ZoneType.EXIT:
				_notice(pid, "The whole crew has to be at the exit to walk out.")
				return
	host.send_world(0, &"run_over", {})
	_end_visit(OUTCOME_RUN_OVER)


func _net_tick(delta: float) -> void:
	_nameplate_left -= delta
	if _nameplate_left <= 0.0:
		_nameplate_left = NAMEPLATE_REFRESH_SECONDS
		_refresh_nameplates()
	if not NetLog.enabled or finished:
		return
	var now := Time.get_ticks_msec()
	if not authority and player != null:
		_trail.append([now, player.global_position])
		while not _trail.is_empty() and now - int(_trail[0][0]) > 1000:
			_trail.pop_front()
	if now < _probe_due_msec:
		return
	_probe_due_msec = now + int(PROBE_SECONDS * 1000.0)
	if authority:
		_send_probe()
	elif player != null and player.is_carried():
		var g: GuardNPC = _carriers.get(local_pid)
		if g != null and is_instance_valid(g):
			NetLog.line("carried_follow", {"guard": g.guard_id, "err": player.global_position.distance_to(g.get_carry_point())})


func _refresh_nameplates() -> void:
	for pid: int in players:
		var node: PlayerCharacter = players[pid]
		if pid == local_pid or node.nameplate == null:
			continue
		var level: int = HeatMeter.level_for(_p_heat(pid))
		var text := _name_of(pid)
		match _p_status(pid):
			HR.PlayerStatus.CARRIED:
				text += " (grabbed!)"
			HR.PlayerStatus.ID_CHECK:
				text += " (ID check)"
		node.set_nameplate(text, UiTheme.heat_color(level).lightened(0.25))


## --net-log, host: guard positions and carry points for the clients to check
## their puppets against, and how closely a carried client follows its guard.
func _send_probe() -> void:
	var guard_pos: Dictionary = {}
	for g: GuardNPC in guards:
		guard_pos[g.guard_id] = g.global_position
	var player_pos: Dictionary = {}
	for pid: int in players:
		player_pos[pid] = (players[pid] as PlayerCharacter).global_position
	host.send_world(0, &"probe", {"guards": guard_pos, "players": player_pos}, false)
	for pid: int in _carriers:
		var g: GuardNPC = _carriers[pid]
		var node: PlayerCharacter = players.get(pid)
		# Skip the first half second: the client's body is still on its way up.
		if Time.get_ticks_msec() - int(_grabbed_at.get(pid, 0)) < int(PROBE_SECONDS * 1000.0):
			continue
		if pid != local_pid and node != null and g != null and is_instance_valid(g):
			NetLog.line("carry_track", {"pid": pid, "guard": g.guard_id, "err": node.global_position.distance_to(g.get_carry_point())})


## --net-log, client: how far each puppet guard is from the host's position.
func _check_probe(data: Dictionary) -> void:
	if finished:
		return
	var guard_pos: Variant = data.get("guards")
	if guard_pos is Dictionary:
		for id: Variant in guard_pos:
			var g := _guard_by_id(int(id))
			var at: Variant = guard_pos[id]
			if g != null and at is Vector3:
				NetLog.line("guard_track", {"guard": int(id), "err": Perception.flat_distance(g.global_position, at)})
	# The host's copy of this player against where it was over the last
	# second (the probe and the sync both took a trip over the wire).
	var player_pos: Variant = data.get("players")
	if player_pos is Dictionary and player != null and (player_pos as Dictionary).has(local_pid):
		var seen: Variant = player_pos[local_pid]
		if seen is Vector3:
			var best := Perception.flat_distance(player.global_position, seen)
			for entry: Array in _trail:
				best = minf(best, Perception.flat_distance(entry[1], seen))
			NetLog.line("self_track", {"err": best})


# --- Frame update -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if map == null:
		return
	if not npcs_active:
		_nav_frames += 1
		if (map.navigation_ready() and _peers_ready()) or (_nav_frames >= NAV_WAIT_MAX_FRAMES and _peers_ready()):
			_activate_npcs()
	if authority:
		_update_flags()
	_sync_outfits()
	_sync_seated_pose()
	_sync_input(false)
	_update_prompt()
	_animate_alarm()
	if online:
		_net_tick(delta)
	if _finish_left >= 0.0 and not _finish_emitted:
		_finish_left -= delta
		if _finish_left <= 0.0:
			_finish_emitted = true
			visit_finished.emit(outcome)


func _activate_npcs() -> void:
	npcs_active = true
	npc_root.process_mode = Node.PROCESS_MODE_INHERIT
	npcs_activated.emit()


## running_in_view, in_camera_view and pit_boss_view, sent when they change.
func _update_flags() -> void:
	for pid: int in players:
		var flags := {
			"running_in_view": _time - float(_running_seen_at.get(pid, -INF)) <= Tuning.DIRECTOR_RUN_FLAG_HOLD_SECONDS,
			"in_camera_view": not (_camera_watch.get(pid, {}) as Dictionary).is_empty(),
			"pit_boss_view": _pit_boss_sees(pid),
		}
		if flags != _flags_sent.get(pid, {}):
			_flags_sent[pid] = flags
			host.request_set_player_flags(pid, flags)


func _pit_boss_sees(pid: int) -> bool:
	for g: GuardNPC in guards:
		if g.security_type == HR.SecurityType.PIT_BOSS and g.sees_pid(pid):
			return true
	return false


func _sync_outfits() -> void:
	for pid: int in players:
		var look := _outfit_dict(pid)
		if look.is_empty():
			continue
		if look != _worn.get(pid, {}):
			_worn[pid] = look
			(players[pid] as PlayerCharacter).set_outfit(Outfit.from_dict(look))


func _sync_seated_pose() -> void:
	for pid: int in players:
		var node: PlayerCharacter = players[pid]
		if node.puppet or node.state != PlayerCharacter.STATE_SEATED:
			continue
		var t: TableNode = tables.get(_p_table(pid))
		node.set_playing(_p_in_round(pid) or (t != null and t.is_animating()))


func _sync_input(force: bool) -> void:
	if player == null:
		return
	var want := _input_wanted()
	if force or not _input_known or want != _input_on:
		_input_known = true
		_input_on = want
		player.set_input_enabled(want)


func _input_wanted() -> bool:
	if finished or input_blocked:
		return false
	var status := _p_status(local_pid)
	if status < 0 or status == HR.PlayerStatus.DETAINED or status == HR.PlayerStatus.ON_CURB:
		return false
	if bet_panel != null and bet_panel.is_open():
		return false
	if quiz_panel != null and quiz_panel.is_waiting():
		return false
	for p: Control in [cashier_panel, wardrobe_panel, forger_panel]:
		if p != null and p.visible:
			return false
	return true


func _update_prompt() -> void:
	if hud == null or player == null:
		return
	var text := ""
	var target := player.current_interactable()
	var progress := player.interact_hold_progress()
	if progress > 0.0 and target != null:
		text = "Tearing it down... %d%%" % int(progress * 100.0) if target.kind == &"poster" else "Holding... %d%%" % int(progress * 100.0)
	elif target != null and _input_on and player.state == PlayerCharacter.STATE_FREE:
		text = target.prompt
	if text != _prompt:
		_prompt = text
		hud.set_prompt(text)


func _animate_alarm() -> void:
	if _alarm_light == null or not _alarm_light.visible:
		return
	_alarm_light.light_energy = 0.6 + 1.4 * absf(sin(_time * 6.0))


# --- Player signals -------------------------------------------------------------

func _on_focus_changed(target: Interactable) -> void:
	_focus = target


func _on_pause_requested() -> void:
	pause_requested.emit()


func _on_interact_pressed(target: Interactable, node: PlayerCharacter) -> void:
	interact(node.pid, target, false)


func _on_interact_held(target: Interactable, node: PlayerCharacter) -> void:
	interact(node.pid, target, true)


func _on_tackle_requested(target: Node3D, node: PlayerCharacter) -> void:
	var g := target as GuardNPC
	if g == null or finished:
		return
	if authority:
		_tackle(node.pid, g)
	else:
		host.send_world(1, &"tackle", {"guard_id": g.guard_id})


## Host: `tackler` tackled the guard: it goes down; a teammate it carried is
## free (and the tackler goes straight to Wanted), else it's a bump.
func _tackle(tackler: int, g: GuardNPC) -> void:
	if g == null or finished:
		return
	var carried: int = g.carrying_pid()
	g.stun()
	if carried >= 0 and carried != tackler:
		var res: Dictionary = host.request_freed(carried, tackler)
		if not bool(res.get("ok", false)) and StringName(str(res.get("reason", ""))) != FloorSim.FINISHED:
			_notice(tackler, UiTheme.reason_text(StringName(str(res.get("reason", "")))))
		return
	host.request_distraction(tackler, HR.Distraction.BUMP_GUARD, g.global_position)


func _on_bumped(guard: Node3D, node: PlayerCharacter) -> void:
	var g := guard as GuardNPC
	if g == null or finished:
		return
	if authority:
		_bump(node.pid, g)
	else:
		host.send_world(1, &"bump", {"guard_id": g.guard_id})


func _bump(pid: int, g: GuardNPC) -> void:
	if g == null or finished:
		return
	var res: Dictionary = host.request_distraction(pid, HR.Distraction.BUMP_GUARD, g.global_position)
	if bool(res.get("ok", false)):
		g.stun()


func _on_throw_chips(target: Vector3, node: PlayerCharacter) -> void:
	if finished:
		return
	var at := Vector3(target.x, node.global_position.y, target.z)
	host.request_distraction(node.pid, HR.Distraction.THROW_CHIPS, at)


func _on_knock_over_requested(target: Interactable, node: PlayerCharacter) -> void:
	_knock_over(node.pid, target)


func _on_struggled(node: PlayerCharacter) -> void:
	if not authority:
		host.send_world(1, &"struggle", {})
		return
	var g: GuardNPC = _carriers.get(node.pid)
	if g != null and is_instance_valid(g):
		g.on_struggle()


func _on_stand_requested(node: PlayerCharacter) -> void:
	if node.pid == local_pid and bet_panel != null and bet_panel.is_open():
		return
	host.request_stand(node.pid)


func _on_give_chips_requested(mate: PlayerCharacter, node: PlayerCharacter) -> void:
	if finished or mate == null:
		return
	var run: Dictionary = host.snapshot().get("run", {})
	var pocket: int = int(_pv(node.pid).get("pocket", 0)) if _sim() == null else _sim().player(node.pid).wallet.pocket
	var amount: int = mini(pocket, maxi(int(run.get("min_bet", 1)), int(float(pocket) * GIVE_CHIPS_SHARE)))
	if amount <= 0:
		_notify(node.pid, UiTheme.reason_text(FloorSim.NOT_ENOUGH), UiTheme.LOSS_COLOR)
		return
	_giving = true
	host.request_give_chips(node.pid, mate.pid, amount)


func _on_bet_leave() -> void:
	host.request_stand(local_pid)


func _on_zone_entered(body: Node3D, zone: CasinoZone) -> void:
	var node := body as PlayerCharacter
	if node == null or not players.has(node.pid) or finished:
		return
	# Each peer reports only its own player's zone (the host validates it).
	if online and node.pid != local_pid:
		return
	host.request_enter_zone(node.pid, zone.zone_type, zone.area_id)


# --- Request answers --------------------------------------------------------------

## Feedback for this peer's own requests (on the host and offline during the
## call, on a client when the answer arrives).
func _on_request_done(request: StringName, args: Array, res: Dictionary) -> void:
	if finished:
		return
	var who: int = int(args[0]) if not args.is_empty() and args[0] is int else local_pid
	if who != local_pid:
		return
	var ok: bool = bool(res.get("ok", false))
	match request:
		&"sit", &"tear_poster":
			_report_failure(res, who)
		&"deface_poster":
			if ok:
				_notify(who, "You drew over the %s on the poster." % OutfitCatalog.slot_name(int(res.get("slot", 0))).to_lower(), UiTheme.WIN_COLOR)
			else:
				_report_failure(res, who)
		&"distraction":
			var kind: int = int(args[1]) if args.size() > 1 else -1
			if kind == HR.Distraction.BUMP_GUARD:
				return
			if ok and kind == HR.Distraction.THROW_CHIPS:
				_notify(who, "Chips everywhere! (-%s)" % UiTheme.chips(int(res.get("cost", 0))), UiTheme.GOLD_LIGHT)
			else:
				_report_failure(res, who)
		&"give_chips":
			if not _giving:
				return
			_giving = false
			if ok:
				_notify(who, "Handed %s chips to %s." % [UiTheme.chips(int(args[2])), _name_of(int(args[1]))], UiTheme.WIN_COLOR)
			else:
				_report_failure(res, who)
		&"try_climb":
			_on_climb_answer(res)


func _on_climb_answer(res: Dictionary) -> void:
	if bool(res.get("ok", false)):
		return
	var reason: StringName = StringName(str(res.get("reason", "")))
	match reason:
		FloorSim.CANT_CLIMB:
			var run: Dictionary = host.snapshot().get("run", {})
			var buy_in: int = int(run.get("buy_in", 0))
			var bank: int = int(run.get("bank", 0))
			_notify(local_pid, "Bank %s more chips to climb (buy-in %s)." % [UiTheme.chips(maxi(0, buy_in - bank)), UiTheme.chips(buy_in)], UiTheme.LOSS_COLOR)
		FloorSim.NOT_AT_EXIT:
			if _p_zone(local_pid) != HR.ZoneType.EXIT:
				_notify(local_pid, "Step onto the EXIT pad to leave.", UiTheme.LOSS_COLOR)
			else:
				_notify(local_pid, "The whole crew has to be at the exit to climb.", UiTheme.LOSS_COLOR)
		FloorSim.NO_STAKE:
			_notify(local_pid, no_stake_text(res), UiTheme.LOSS_COLOR)
		_:
			_report_failure(res, local_pid)


## What to tell the crew when try_climb refuses with NO_STAKE ({to, stake}):
## the buy-in would leave nothing to bet with upstairs.
static func no_stake_text(res: Dictionary) -> String:
	var to: int = int(res.get("to", Tuning.TOP_RUNG))
	var stake: int = maxi(1, int(res.get("stake", CasinoLadder.casino(to).get("min_bet", 1))))
	return "Keep at least %s chips in a pocket (or the bank) to cover a bet at %s." % [UiTheme.chips(stake), str(CasinoLadder.casino(to).get("name", "the next casino"))]


# --- Guard and camera signals (authority) ------------------------------------------

func _on_guard_saw(guard: GuardNPC, pid: int, running: bool) -> void:
	_seen_at[pid] = _time
	if running:
		_running_seen_at[pid] = _time
	if _time - float(_reported_at.get(pid, -INF)) < Tuning.DIRECTOR_REPORT_SECONDS:
		return
	_reported_at[pid] = _time
	_report_seen(pid, guard.guard_id, guard.security_type == HR.SecurityType.PIT_BOSS)


func _report_seen(pid: int, guard_id: int, pit_boss: bool) -> void:
	var res: Dictionary = host.request_report_seen(pid, {"guard_id": guard_id, "pit_boss": pit_boss})
	if bool(res.get("ok", false)):
		var matched: bool = bool(res.get("matches_poster", false))
		if matched != bool(_poster_match.get(pid, false)):
			_poster_match[pid] = matched
			_provider_dirty = true


func _on_guard_id_check(guard: GuardNPC, pid: int) -> void:
	var res: Dictionary = host.request_start_id_check(pid, guard.guard_id)
	if not bool(res.get("ok", false)):
		# Busy (another guard's check, carried) or the visit is over: let it go.
		guard.set_id_check_result(pid, true)


func _on_guard_grabbed(guard: GuardNPC, pid: int) -> void:
	var res: Dictionary = host.request_caught(pid, guard.guard_id)
	if not bool(res.get("ok", false)):
		return
	_carriers[pid] = guard
	_grabbed_at[pid] = Time.get_ticks_msec()
	_provider_dirty = true
	_place_player(pid, &"carry", {"guard_id": guard.guard_id})


func _on_guard_delivered(guard: GuardNPC, pid: int) -> void:
	var res: Dictionary = host.request_reach_back_room(pid)
	if not bool(res.get("ok", false)):
		# The sim had already let them go: put the node down.
		_place_player(pid, &"release", {"at": _drop_point(guard)})
		_carriers.erase(pid)


func _on_guard_released(_guard: GuardNPC, pid: int) -> void:
	host.request_freed(pid, 0)


func _on_guard_radioed(boss: GuardNPC, pid: int, where: Vector3) -> void:
	var best: GuardNPC = null
	var best_d := INF
	for g: GuardNPC in guards:
		if g == boss or g.security_type == HR.SecurityType.PIT_BOSS:
			continue
		var d: float = g.global_position.distance_squared_to(where)
		# Floor guards answer the radio first.
		if g.security_type != HR.SecurityType.FLOOR_GUARD:
			d += 1.0e6
		if d < best_d:
			best = g
			best_d = d
	if best != null:
		best.alert(pid, where)


func _on_camera_watching(camera: SecurityCamera, pid: int, active: bool) -> void:
	if not _camera_watch.has(pid):
		_camera_watch[pid] = {}
	var set_: Dictionary = _camera_watch[pid]
	if active:
		set_[camera.get_instance_id()] = true
	else:
		set_.erase(camera.get_instance_id())


func _on_camera_spotted(_camera: SecurityCamera, pid: int) -> void:
	_report_seen(pid, -1, false)


# --- Sim events -------------------------------------------------------------------

func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	var pid: int = int(data.get("pid", 0))
	match kind:
		&"status":
			_provider_dirty = true
		&"seated":
			if not authority:
				return
			var t: TableNode = tables.get(StringName(str(data.get("table_id", ""))))
			if players.has(pid) and t != null:
				_place_player(pid, &"sit", {"seat": t.seat_transform(_seat_index(pid, t.table_id))})
				# A seated body stops touching zones (collision off) and a stool
				# may stand in the aisle: sitting puts the player in the table's
				# game area, so its area-change cool-off lands now, not when
				# they stand up again.
				var zone_type: int = HR.ZoneType.SLOTS if t.game_type == HR.GameType.SLOTS else HR.ZoneType.TABLES
				host.request_enter_zone(pid, zone_type, t.area_id)
		&"stood":
			if authority and players.has(pid):
				_place_player(pid, &"stand")
		&"bet":
			_on_bet(pid, data)
		&"hand":
			var t: TableNode = tables.get(StringName(str(data.get("table_id", ""))))
			if t != null:
				t.show_hand(data.get("state", {}))
		&"dealer_swap":
			var t: TableNode = tables.get(StringName(str(data.get("table_id", ""))))
			if t != null:
				t.dealer_swap()
		&"fire_alarm":
			_set_fire_alarm(bool(data.get("active", false)))
		&"noise":
			_on_noise(data)
		&"crowd_rush":
			if authority and crowd != null:
				var at: Variant = data.get("position", Vector3.ZERO)
				crowd.rush_to(at if at is Vector3 else Vector3.ZERO, float(data.get("radius", Tuning.THROW_CHIPS_BLOCK_RADIUS)), float(data.get("seconds", Tuning.THROW_CHIPS_BLOCK_SECONDS)))
		&"poster", &"poster_removed", &"poster_defaced":
			_refresh_posters()
			if authority:
				_refresh_poster_matches()
		&"outfit":
			if authority:
				_refresh_poster_matches()
		&"id_result":
			if authority:
				var g := _guard_by_id(int(data.get("guard_id", -1)))
				if g != null:
					g.set_id_check_result(pid, bool(data.get("passed", false)))
		&"freed":
			_provider_dirty = true
			if not authority:
				return
			var carrier: GuardNPC = _carriers.get(pid)
			_carriers.erase(pid)
			var node: PlayerCharacter = players.get(pid)
			if node != null:
				var at: Vector3 = _drop_point(carrier) if carrier != null and is_instance_valid(carrier) else _floor_under(node)
				_place_player(pid, &"release", {"at": at})
		&"detained":
			if not authority:
				return
			_carriers.erase(pid)
			if players.has(pid):
				_place_player(pid, &"hide", {"at": map.to_global(map.back_room_point)})
		&"rejoined":
			if authority and players.has(pid):
				var from: StringName = StringName(str(data.get("from", "")))
				var spawn: StringName = StringName(str(data.get("spawn", "")))
				var at: Vector3 = map.to_global(map.back_room_release_point)
				if (from == &"curb" or spawn == &"entrance") and not map.spawn_points.is_empty():
					at = map.to_global(map.spawn_points[posmod(pid - 1, map.spawn_points.size())])
				_place_player(pid, &"show", {"at": at, "reset_zone": true})
		&"curb":
			if authority:
				_on_curb()
		&"forger_moved":
			_move_forger(StringName(str(data.get("location", ""))))
		&"thrown_out":
			_end_visit(&"thrown_out")
		&"climbed":
			_end_visit(&"climbed")
		&"player_left":
			remove_player(pid)


func _on_bet(pid: int, data: Dictionary) -> void:
	var table_id: StringName = StringName(str(data.get("table_id", "")))
	var t: TableNode = tables.get(table_id)
	var result: Dictionary = data.get("result", {})
	if t == null:
		return
	# play_result also strobes the loud ones (big wheel, jackpot).
	t.play_result(result)
	if pid == local_pid and bool(data.get("round_over", true)) and bool(result.get("won", false)) and int(result.get("net", 0)) > 0:
		_celebrate[table_id] = true


func _on_result_shown(table_id: StringName) -> void:
	if bet_panel != null and bet_panel.is_open() and bet_panel.table_id == table_id:
		bet_panel.notify_result_shown()
	if _celebrate.has(table_id):
		_celebrate.erase(table_id)
		if player != null:
			player.emote(&"celebrate", Tuning.DIRECTOR_CELEBRATE_SECONDS)


## Guards in earshot hear it (host); every peer sees the ring, a knocked
## tray falling and thrown chips flying.
func _on_noise(data: Dictionary) -> void:
	var pos: Variant = data.get("position")
	if not (pos is Vector3):
		return
	if authority:
		for g: GuardNPC in guards:
			g.hear(data)
	var kind: StringName = StringName(str(data.get("kind", "")))
	match kind:
		&"knock_over":
			_topple_tray_near(pos)
		&"throw_chips":
			_chip_burst(pos, players.get(int(data.get("pid", 0))))
	if kind != &"fire_alarm":
		_noise_ring(pos, minf(float(data.get("radius", 4.0)), Tuning.DIRECTOR_NOISE_RING_MAX_RADIUS))


func _on_curb() -> void:
	var i := 0
	for pid: int in players:
		_carriers.erase(pid)
		_place_player(pid, &"show", {"at": map.to_global(map.curb_point) + Vector3(0.9 * float(i), 0.0, 0.0)})
		i += 1
	_provider_dirty = true


func _end_visit(p_outcome: StringName) -> void:
	if finished:
		return
	finished = true
	outcome = p_outcome
	_finish_left = maxf(visit_end_delay, 0.0)
	if online:
		_stop_net_sync()
	_sync_input(true)
	if hud != null:
		hud.set_prompt("")
	NetLog.line("visit_end", {"outcome": p_outcome, "rung": rung})


func _set_fire_alarm(active: bool) -> void:
	for t: TableNode in tables.values():
		t.set_closed(active)
	for g: GuardNPC in guards:
		g.set_fire_alarm(active)
	if _alarm_light != null:
		_alarm_light.visible = active
		_alarm_light.light_energy = 0.0


func _refresh_posters() -> void:
	if map == null:
		return
	var sim := _sim()
	if sim != null:
		map.show_posters(sim.posters_here())
	elif host != null:
		map.show_posters(host.snapshot().get("posters", []))


func _refresh_poster_matches() -> void:
	var sim := _sim()
	if sim == null:
		return
	for pid: int in players:
		_poster_match[pid] = sim.matches_poster(pid)
	_provider_dirty = true


# --- Interactions -------------------------------------------------------------

func _knock_over(pid: int, target: Interactable) -> void:
	if finished or target == null or not target.enabled:
		return
	# The &"noise" event knocks the tray over on every peer.
	host.request_distraction(pid, HR.Distraction.KNOCK_OVER, target.global_position)


## Knocks over the enabled tray at `at` (where a knock_over noise came from).
func _topple_tray_near(at: Vector3) -> void:
	var target: Interactable = null
	var best := 1.0
	for it: Interactable in map.interactables_of(&"tray"):
		var d := it.global_position.distance_to(at)
		if it.enabled and d <= best:
			target = it
			best = d
	if target == null:
		return
	target.enabled = false
	var prop := target.get_parent() as Node3D
	if prop == null or prop == map:
		return
	var upright: Vector3 = prop.rotation
	var tw := prop.create_tween()
	tw.tween_property(prop, "rotation", upright + Vector3(0, 0, deg_to_rad(84.0)), 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(Tuning.DIRECTOR_TRAY_RESET_SECONDS)
	tw.tween_property(prop, "rotation", upright, 0.4)
	tw.tween_callback(target.set_enabled.bind(true))


func _use_exit(pid: int) -> void:
	if rung == Tuning.TOP_RUNG:
		if not online:
			_end_visit(OUTCOME_RUN_OVER)
		elif authority:
			_leave_top(pid)
		else:
			host.send_world(1, &"exit", {})
		return
	host.request_try_climb()


## Tells the player why a request failed (a HUD notification).
func _report_failure(res: Dictionary, pid: int) -> void:
	if bool(res.get("ok", false)):
		return
	var reason: StringName = StringName(str(res.get("reason", "")))
	if reason == FloorSim.FINISHED:
		return
	var text: String = UiTheme.reason_text(reason)
	if reason == FloorSim.COOLDOWN and res.has("seconds"):
		text += " (%d s)" % ceili(float(res["seconds"]))
	_notify(pid, text, UiTheme.LOSS_COLOR)


func _notify(pid: int, text: String, color: Color = UiTheme.CREAM) -> void:
	if hud != null and pid == local_pid and text != "":
		hud.push_notification(text, color)


# --- Effects ----------------------------------------------------------------------

func _chip_burst(at: Vector3, thrower: PlayerCharacter = null) -> void:
	var colors: Array[Color] = [UiTheme.CHIP_RED, UiTheme.CHIP_BLUE, UiTheme.CHIP_GREEN, UiTheme.CHIP_BLACK, UiTheme.GOLD]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var from := thrower.global_position + Vector3.UP * 1.3 if thrower != null and is_instance_valid(thrower) else at + Vector3.UP * 1.3
	for i in Tuning.DIRECTOR_THROW_CHIPS:
		var chip := Primitives.cylinder(0.1, 0.035, colors[i % colors.size()], 10)
		_fx_root.add_child(chip)
		var land := Vector3(at.x + rng.randf_range(-1.3, 1.3), 0.03, at.z + rng.randf_range(-1.3, 1.3))
		chip.global_position = from
		chip.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0.0)
		var flight: float = rng.randf_range(0.45, 0.65)
		var tw := chip.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chip, "global_position:x", land.x, flight)
		tw.tween_property(chip, "global_position:z", land.z, flight)
		tw.tween_property(chip, "global_position:y", from.y + 0.9, flight * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(chip, "global_position:y", land.y, flight * 0.6).set_delay(flight * 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(chip, "rotation", Vector3(0.0, rng.randf() * TAU, 0.0), flight)
		tw.chain().tween_interval(Tuning.THROW_CHIPS_BLOCK_SECONDS)
		tw.chain().tween_property(chip, "scale", Vector3.ONE * 0.01, 0.3)
		tw.chain().tween_callback(chip.queue_free)


## A ring on the floor that grows to the noise radius and fades: what the guards heard.
func _noise_ring(at: Vector3, radius: float) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 4
	torus.material = Primitives.material(NOISE_COLOR, 0.6)
	var ring := MeshInstance3D.new()
	ring.name = "NoiseRing"
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(ring)
	ring.global_position = Vector3(at.x, map.global_position.y + 0.08, at.z)
	ring.scale = Vector3(0.3, 0.05, 0.3)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.05, radius), Tuning.DIRECTOR_NOISE_RING_SECONDS).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ring, "transparency", 1.0, Tuning.DIRECTOR_NOISE_RING_SECONDS).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


# --- Helpers ------------------------------------------------------------------------

func _sim() -> FloorSim:
	return host.current_sim() if host != null else null


func _ps(pid: int) -> PlayerState:
	var sim := _sim()
	return sim.player(pid) if sim != null else null


## A client's view of a player: its entry in the host's snapshot ({} if none).
func _pv(pid: int) -> Dictionary:
	if host == null:
		return {}
	return (host.snapshot().get("players", {}) as Dictionary).get(pid, {})


## HR.PlayerStatus of `pid` (−1 if unknown).
func _p_status(pid: int) -> int:
	var ps := _ps(pid)
	if ps != null:
		return ps.status
	var p := _pv(pid)
	return int(p.get("status", HR.PlayerStatus.FREE)) if not p.is_empty() else -1


func _p_table(pid: int) -> StringName:
	var ps := _ps(pid)
	if ps != null:
		return ps.table_id
	return StringName(str(_pv(pid).get("table_id", "")))


func _p_zone(pid: int) -> int:
	var ps := _ps(pid)
	if ps != null:
		return ps.zone
	return int(_pv(pid).get("zone", HR.ZoneType.ENTRANCE))


func _p_heat(pid: int) -> float:
	var ps := _ps(pid)
	if ps != null:
		return ps.heat.value
	return float(_pv(pid).get("heat", 0.0))


func _p_in_round(pid: int) -> bool:
	var ps := _ps(pid)
	if ps != null:
		return ps.in_round()
	return StringName(str(_pv(pid).get("round", ""))) != &""


func _outfit_dict(pid: int) -> Dictionary:
	var ps := _ps(pid)
	if ps != null:
		return ps.outfit.to_dict()
	return _pv(pid).get("outfit", {})


func _name_of(pid: int) -> String:
	var ps := _ps(pid)
	if ps != null:
		return ps.display_name
	return str(_pv(pid).get("name", host.player_names.get(pid, "Player %d" % pid) if host != null else "Player %d" % pid))


func _fire_alarm_active() -> bool:
	var sim := _sim()
	if sim != null:
		return sim.fire_alarm_active()
	return bool(host.snapshot().get("fire_alarm", false)) if host != null else false


func _forger_location() -> StringName:
	var sim := _sim()
	if sim != null:
		return sim.forger.location()
	return StringName(str(host.snapshot().get("forger_location", ""))) if host != null else &""


func _seen_recently(pid: int) -> bool:
	return _time - float(_seen_at.get(pid, -INF)) <= Tuning.DIRECTOR_RUN_FLAG_HOLD_SECONDS


func _seat_index(pid: int, table_id: StringName) -> int:
	var sim := _sim()
	var t: TableState = sim.table(table_id) if sim != null else null
	return maxi(0, t.seated_players().find(pid)) if t != null else 0


func _guard_by_id(id: int) -> GuardNPC:
	for g: GuardNPC in guards:
		if g.guard_id == id:
			return g
	return null


## Where a carried player is put down: behind the guard, where it just walked.
func _drop_point(guard: GuardNPC) -> Vector3:
	if guard == null or not is_instance_valid(guard):
		return Vector3.ZERO
	return guard.global_position - guard.front_direction() * 0.9 + Vector3.UP * 0.05


## Swings a seated player's camera round behind them, looking down at the table.
func _face_camera(node: PlayerCharacter) -> void:
	var rig := node.camera_rig
	if rig == null:
		return
	rig.yaw = node.facing
	rig.add_look(0.0, deg_to_rad(Tuning.DIRECTOR_SEATED_CAMERA_PITCH_DEGREES) - rig.pitch)
	# Lift the view so the table shows above the bet panel.
	rig.camera.v_offset = Tuning.DIRECTOR_SEATED_CAMERA_V_OFFSET


func _reset_camera(node: PlayerCharacter) -> void:
	var rig := node.camera_rig
	if rig == null or is_zero_approx(rig.camera.v_offset):
		return
	rig.camera.v_offset = 0.0
	rig.add_look(0.0, deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_DEFAULT_DEGREES) - rig.pitch)


func _floor_under(node: Node3D) -> Vector3:
	return Vector3(node.global_position.x, 0.05, node.global_position.z)


func _guard_lines() -> Array:
	var out: Array = []
	for g: GuardNPC in guards:
		var label: String = g.brain.debug_label if not g.puppet else GuardBrain.name_of(g.get_state())
		out.append("G%d %-10s %-12s carry %d" % [g.guard_id, str(SECURITY_NAMES.get(g.security_type, "?")), label, g.carrying_pid()])
	for c: SecurityCamera in cameras:
		out.append("C%d watching %s" % [c.camera_id, str(c.watched_pids())])
	return out
