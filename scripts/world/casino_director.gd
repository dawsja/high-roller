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
const COAT_COLOR := Color("9b7b52")
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
## The local player (pid LOCAL_PID).
var player: PlayerCharacter
## pid -> PlayerCharacter for the whole crew.
var players: Dictionary = {}
## table id -> TableNode.
var tables: Dictionary = {}
var guards: Array[GuardNPC] = []
var cameras: Array[SecurityCamera] = []
var crowd: PatronCrowd
## The forger NPC (moves on &"forger_moved") and its interactable.
var forger_npc: Node3D
var forger_model: CharacterModel
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
## pid -> Outfit the node wears.
var _worn: Dictionary = {}
## table id -> true: celebrate when its result has been shown.
var _celebrate: Dictionary = {}
var _input_on: bool = true
var _input_known: bool = false
var _prompt: String = ""
var _focus: Interactable


## Builds the visit. `ui` holds the UI nodes main.gd owns, any of: hud,
## bet_panel, quiz_panel, cashier_panel, wardrobe_panel, forger_panel,
## visit_banner, debug_overlay. Needs this node in the tree (the navmesh is
## baked here) and host.start_visit() already called.
func setup(p_host: SimHost, p_rung: int, p_practice: bool, ui: Dictionary = {}) -> void:
	if not is_inside_tree():
		push_error("CasinoDirector.setup: add the director to the tree first")
		return
	host = p_host
	practice = p_practice
	var sim := _sim()
	if sim == null:
		push_error("CasinoDirector.setup: the host has no visit (call host.start_visit())")
		return
	rung = sim.run.rung
	if p_rung != rung:
		push_warning("CasinoDirector.setup: rung %d asked, the sim is at rung %d" % [p_rung, rung])
	casino = sim.casino()
	name = "CasinoDirector_%s" % String(casino.get("id", &"casino"))
	_take_ui(ui)
	var seed_value: int = hash([String(casino.get("id", &"")), sim.run.visits, rung])

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
	_refresh_poster_matches()
	if sim.fire_alarm_active():
		_set_fire_alarm(true)
	host.sim_event.connect(_on_sim_event)
	_connect_ui()
	_close_panels()
	_sync_input(true)
	_welcome()


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
## staff_uniform, available} per crew member (rebuilt once per physics frame).
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
			"available": ps.is_available(),
		})
	return _provider_cache


## Re-applies the player's input state (main.gd calls this after the pause menu).
func sync_input(force: bool = false) -> void:
	_sync_input(force)


## Uses an interactable as `pid` (what the player's interact press / hold does).
func interact(pid: int, target: Interactable, held: bool = false) -> void:
	if finished or target == null or not is_instance_valid(target) or not target.enabled:
		return
	var node: PlayerCharacter = players.get(pid)
	target.use(node)
	var pos: Vector3 = target.global_position
	match target.kind:
		&"table":
			var table_id: StringName = StringName(str(target.data.get("table_id", "")))
			var ps := _ps(pid)
			if ps != null and ps.table_id == table_id:
				return
			_report_failure(host.request_sit(pid, table_id, _seen_recently(pid)), pid)
		&"cashier":
			if cashier_panel != null and pid == LOCAL_PID:
				cashier_panel.open()
		&"restroom":
			if wardrobe_panel != null and pid == LOCAL_PID:
				wardrobe_panel.open_mode(WardrobePanel.MODE_RESTROOM)
		&"gift_shop":
			if wardrobe_panel != null and pid == LOCAL_PID:
				wardrobe_panel.open_mode(WardrobePanel.MODE_GIFT_SHOP)
		&"laundry_cart", &"staff_locker":
			if wardrobe_panel != null and pid == LOCAL_PID:
				wardrobe_panel.open_mode(WardrobePanel.MODE_STEAL, target.kind)
		&"forger":
			if forger_panel != null and pid == LOCAL_PID:
				forger_panel.open()
		&"poster":
			var poster_id: int = int(target.data.get("poster_id", -1))
			if held:
				_report_failure(host.request_tear_poster(pid, poster_id, pos), pid)
			else:
				var res: Dictionary = host.request_deface_poster(pid, poster_id)
				if bool(res.get("ok", false)):
					_notify(pid, "You drew over the %s on the poster." % OutfitCatalog.slot_name(int(res.get("slot", 0))).to_lower(), UiTheme.WIN_COLOR)
				else:
					_report_failure(res, pid)
		&"tray":
			_knock_over(pid, target)
		&"fire_alarm":
			_report_failure(host.request_distraction(pid, HR.Distraction.FIRE_ALARM, pos), pid)
		&"slot_alarm":
			_report_failure(host.request_distraction(pid, HR.Distraction.SLOT_ALARM, pos), pid)
		&"exit":
			_use_exit(pid)


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
	var sim := _sim()
	var i := 0
	for pid: int in sim.player_ids():
		var ps := sim.player(pid)
		var node := PlayerCharacter.new()
		node.name = "Player%d" % pid
		var spawn: Vector3 = map.spawn_points[i % map.spawn_points.size()] if not map.spawn_points.is_empty() else Vector3.ZERO
		node.position = map.to_global(spawn)
		add_child(node)
		node.setup(pid, pid == LOCAL_PID, ps.outfit.copy())
		_worn[pid] = ps.outfit.copy()
		players[pid] = node
		if pid == LOCAL_PID:
			player = node
			node.focus_changed.connect(_on_focus_changed)
			node.pause_requested.connect(_on_pause_requested)
		node.interact_pressed.connect(_on_interact_pressed.bind(node))
		node.interact_held.connect(_on_interact_held.bind(node))
		node.tackle_requested.connect(_on_tackle_requested.bind(node))
		node.bumped.connect(_on_bumped.bind(node))
		node.throw_chips_requested.connect(_on_throw_chips.bind(node))
		node.knock_over_requested.connect(_on_knock_over_requested.bind(node))
		node.struggled.connect(_on_struggled.bind(node))
		node.stand_requested.connect(_on_stand_requested.bind(node))
		i += 1


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
	for i in int(plan["cameras"]):
		var cam := SecurityCamera.new()
		cam.name = "Camera%d" % (i + 1)
		add_child(cam)
		cam.setup(i + 1, map.global_transform * map.camera_mounts[i], players_info)
		cam.watching.connect(_on_camera_watching)
		cam.spotted.connect(_on_camera_spotted)
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
	npc_root.add_child(g)
	g.setup(id, kind, route, map.to_global(map.back_room_point), players_info)
	g.saw_player.connect(_on_guard_saw)
	g.id_check_requested.connect(_on_guard_id_check)
	g.grabbed.connect(_on_guard_grabbed)
	g.delivered.connect(_on_guard_delivered)
	g.released.connect(_on_guard_released)
	g.radioed.connect(_on_guard_radioed)
	guards.append(g)
	return g


func _spawn_crowd(seed_value: int) -> void:
	crowd = PatronCrowd.new()
	crowd.name = "Crowd"
	npc_root.add_child(crowd)
	var points: Array[Vector3] = []
	for p: Vector3 in map.patron_points:
		points.append(map.to_global(p))
	var seats: Array[Transform3D] = []
	for s: Transform3D in map.slot_seats:
		seats.append(map.global_transform * s)
	var counts: Dictionary = Tuning.DIRECTOR_PATRONS
	crowd.setup(points, seats, int(counts.get(map.size_class, counts[&"small"])), seed_value)


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
	# Small reach (+ the player's 1.5 m sensor): buy_id needs the player inside
	# the forger's 4 m corner zone, and the restroom corner backs onto a wall.
	forger_interactable = Interactable.create(&"forger", "Buy a fake ID", 0.25, {"location": &""})
	forger_interactable.position = Vector3(0, 1.0, 0)
	forger_npc.add_child(forger_interactable)
	_move_forger(_sim().forger.location())


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
	if host != null and host.sim_event.is_connected(_on_sim_event):
		host.sim_event.disconnect(_on_sim_event)
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


# --- Frame update -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if map == null:
		return
	if not npcs_active:
		_nav_frames += 1
		if map.navigation_ready() or _nav_frames >= NAV_WAIT_MAX_FRAMES:
			_activate_npcs()
	_update_flags()
	_sync_outfits()
	_sync_seated_pose()
	_sync_input(false)
	_update_prompt()
	_animate_alarm()
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
	var sim := _sim()
	if sim == null:
		return
	for pid: int in players:
		var ps := sim.player(pid)
		if ps == null:
			continue
		var worn: Outfit = _worn.get(pid)
		if worn == null or not worn.equals(ps.outfit):
			_worn[pid] = ps.outfit.copy()
			(players[pid] as PlayerCharacter).set_outfit(ps.outfit.copy())


func _sync_seated_pose() -> void:
	var sim := _sim()
	for pid: int in players:
		var node: PlayerCharacter = players[pid]
		if node.state != PlayerCharacter.STATE_SEATED:
			continue
		var ps := sim.player(pid) if sim != null else null
		var t: TableNode = tables.get(ps.table_id) if ps != null else null
		node.set_playing((ps != null and ps.in_round()) or (t != null and t.is_animating()))


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
	var ps := _ps(LOCAL_PID)
	if ps == null or ps.status == HR.PlayerStatus.DETAINED or ps.status == HR.PlayerStatus.ON_CURB:
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
	var carried: int = g.carrying_pid()
	g.stun()
	if carried >= 0 and carried != node.pid:
		var res: Dictionary = host.request_freed(carried, node.pid)
		if not bool(res.get("ok", false)):
			_report_failure(res, node.pid)
		return
	host.request_distraction(node.pid, HR.Distraction.BUMP_GUARD, g.global_position)


func _on_bumped(guard: Node3D, node: PlayerCharacter) -> void:
	var g := guard as GuardNPC
	if g == null or finished:
		return
	var res: Dictionary = host.request_distraction(node.pid, HR.Distraction.BUMP_GUARD, g.global_position)
	if bool(res.get("ok", false)):
		g.stun()


func _on_throw_chips(target: Vector3, node: PlayerCharacter) -> void:
	if finished:
		return
	var at := Vector3(target.x, node.global_position.y, target.z)
	var res: Dictionary = host.request_distraction(node.pid, HR.Distraction.THROW_CHIPS, at)
	if bool(res.get("ok", false)):
		_chip_burst(at)
		_notify(node.pid, "Chips everywhere! (-%s)" % UiTheme.chips(int(res.get("cost", 0))), UiTheme.GOLD_LIGHT)
	else:
		_report_failure(res, node.pid)


func _on_knock_over_requested(target: Interactable, node: PlayerCharacter) -> void:
	_knock_over(node.pid, target)


func _on_struggled(node: PlayerCharacter) -> void:
	var g: GuardNPC = _carriers.get(node.pid)
	if g != null and is_instance_valid(g):
		g.on_struggle()


func _on_stand_requested(node: PlayerCharacter) -> void:
	if node.pid == LOCAL_PID and bet_panel != null and bet_panel.is_open():
		return
	host.request_stand(node.pid)


func _on_bet_leave() -> void:
	host.request_stand(LOCAL_PID)


func _on_zone_entered(body: Node3D, zone: CasinoZone) -> void:
	var node := body as PlayerCharacter
	if node == null or not players.has(node.pid) or finished:
		return
	host.request_enter_zone(node.pid, zone.zone_type, zone.area_id)


# --- Guard and camera signals -----------------------------------------------------

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
	_provider_dirty = true
	var node: PlayerCharacter = players.get(pid)
	if node != null:
		node.set_carried(guard)


func _on_guard_delivered(guard: GuardNPC, pid: int) -> void:
	var res: Dictionary = host.request_reach_back_room(pid)
	if not bool(res.get("ok", false)):
		# The sim had already let them go: put the node down.
		var node: PlayerCharacter = players.get(pid)
		if node != null and node.is_carried():
			node.release(_drop_point(guard))
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
	var node: PlayerCharacter = players.get(pid)
	match kind:
		&"status":
			_provider_dirty = true
		&"seated":
			var t: TableNode = tables.get(StringName(str(data.get("table_id", ""))))
			if node != null and t != null:
				node.sit_at(t.seat_transform(_seat_index(pid, t.table_id)))
				_face_camera(node)
				# A seated body stops touching zones (collision off) and a stool
				# may stand in the aisle: sitting puts the player in the table's
				# game area, so its area-change cool-off lands now, not when
				# they stand up again.
				var zone_type: int = HR.ZoneType.SLOTS if t.game_type == HR.GameType.SLOTS else HR.ZoneType.TABLES
				host.request_enter_zone(pid, zone_type, t.area_id)
		&"stood":
			if node != null and node.state == PlayerCharacter.STATE_SEATED:
				node.stand_up()
			if node != null:
				_reset_camera(node)
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
			if crowd != null:
				var at: Variant = data.get("position", Vector3.ZERO)
				crowd.rush_to(at if at is Vector3 else Vector3.ZERO, float(data.get("radius", Tuning.THROW_CHIPS_BLOCK_RADIUS)), float(data.get("seconds", Tuning.THROW_CHIPS_BLOCK_SECONDS)))
		&"poster", &"poster_removed", &"poster_defaced":
			_refresh_posters()
			_refresh_poster_matches()
		&"outfit":
			_refresh_poster_matches()
		&"id_result":
			var g := _guard_by_id(int(data.get("guard_id", -1)))
			if g != null:
				g.set_id_check_result(pid, bool(data.get("passed", false)))
		&"freed":
			_provider_dirty = true
			var carrier: GuardNPC = _carriers.get(pid)
			_carriers.erase(pid)
			if node != null and node.is_carried():
				node.release(_drop_point(carrier) if carrier != null and is_instance_valid(carrier) else _floor_under(node))
		&"detained":
			_carriers.erase(pid)
			if node != null:
				node.set_hidden(true)
				node.teleport(map.to_global(map.back_room_point))
		&"rejoined":
			if node != null:
				var from: StringName = StringName(str(data.get("from", "")))
				var at: Vector3 = map.to_global(map.back_room_release_point)
				if from == &"curb" and not map.spawn_points.is_empty():
					at = map.to_global(map.spawn_points[(pid - 1) % map.spawn_points.size()])
				node.set_hidden(false)
				node.teleport(at)
				# The sim reset the player's zone; let the map announce the real one.
				map.reset_zone(node)
		&"curb":
			_on_curb()
		&"forger_moved":
			_move_forger(StringName(str(data.get("location", ""))))
		&"thrown_out":
			_end_visit(&"thrown_out")
		&"climbed":
			_end_visit(&"climbed")


func _on_bet(pid: int, data: Dictionary) -> void:
	var table_id: StringName = StringName(str(data.get("table_id", "")))
	var t: TableNode = tables.get(table_id)
	var result: Dictionary = data.get("result", {})
	if t == null:
		return
	# play_result also strobes the loud ones (big wheel, jackpot).
	t.play_result(result)
	if pid == LOCAL_PID and bool(data.get("round_over", true)) and bool(result.get("won", false)) and int(result.get("net", 0)) > 0:
		_celebrate[table_id] = true


func _on_result_shown(table_id: StringName) -> void:
	if bet_panel != null and bet_panel.is_open() and bet_panel.table_id == table_id:
		bet_panel.notify_result_shown()
	if _celebrate.has(table_id):
		_celebrate.erase(table_id)
		if player != null:
			player.emote(&"celebrate", Tuning.DIRECTOR_CELEBRATE_SECONDS)


func _on_noise(data: Dictionary) -> void:
	var pos: Variant = data.get("position")
	if not (pos is Vector3):
		return
	for g: GuardNPC in guards:
		g.hear(data)
	var kind: StringName = StringName(str(data.get("kind", "")))
	if kind != &"fire_alarm":
		_noise_ring(pos, minf(float(data.get("radius", 4.0)), Tuning.DIRECTOR_NOISE_RING_MAX_RADIUS))


func _on_curb() -> void:
	var i := 0
	for pid: int in players:
		var node: PlayerCharacter = players[pid]
		_carriers.erase(pid)
		node.set_hidden(false)
		node.teleport(map.to_global(map.curb_point) + Vector3(0.9 * float(i), 0.0, 0.0))
		i += 1
	_provider_dirty = true


func _end_visit(p_outcome: StringName) -> void:
	if finished:
		return
	finished = true
	outcome = p_outcome
	_finish_left = maxf(visit_end_delay, 0.0)
	_sync_input(true)
	if hud != null:
		hud.set_prompt("")


func _set_fire_alarm(active: bool) -> void:
	for t: TableNode in tables.values():
		t.set_closed(active)
	for g: GuardNPC in guards:
		g.set_fire_alarm(active)
	if _alarm_light != null:
		_alarm_light.visible = active
		_alarm_light.light_energy = 0.0


func _refresh_posters() -> void:
	var sim := _sim()
	if sim != null and map != null:
		map.show_posters(sim.posters_here())


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
	var res: Dictionary = host.request_distraction(pid, HR.Distraction.KNOCK_OVER, target.global_position)
	if not bool(res.get("ok", false)):
		_report_failure(res, pid)
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
		_end_visit(OUTCOME_RUN_OVER)
		return
	var res: Dictionary = host.request_try_climb()
	if bool(res.get("ok", false)):
		return
	var reason: StringName = StringName(str(res.get("reason", "")))
	match reason:
		FloorSim.CANT_CLIMB:
			var run: Dictionary = host.snapshot().get("run", {})
			var buy_in: int = int(run.get("buy_in", 0))
			var bank: int = int(run.get("bank", 0))
			_notify(pid, "Bank %s more chips to climb (buy-in %s)." % [UiTheme.chips(maxi(0, buy_in - bank)), UiTheme.chips(buy_in)], UiTheme.LOSS_COLOR)
		FloorSim.NOT_AT_EXIT:
			var ps := _ps(pid)
			if ps != null and ps.zone != HR.ZoneType.EXIT:
				_notify(pid, "Step onto the EXIT pad to leave.", UiTheme.LOSS_COLOR)
			else:
				_notify(pid, "The whole crew has to be at the exit to climb.", UiTheme.LOSS_COLOR)
		_:
			_report_failure(res, pid)


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
	if hud != null and pid == LOCAL_PID and text != "":
		hud.push_notification(text, color)


# --- Effects ----------------------------------------------------------------------

func _chip_burst(at: Vector3) -> void:
	var colors: Array[Color] = [UiTheme.CHIP_RED, UiTheme.CHIP_BLUE, UiTheme.CHIP_GREEN, UiTheme.CHIP_BLACK, UiTheme.GOLD]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var from := player.global_position + Vector3.UP * 1.3 if player != null else at + Vector3.UP * 1.3
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
		out.append("G%d %-10s %-12s carry %d" % [g.guard_id, str(SECURITY_NAMES.get(g.security_type, "?")), g.brain.debug_label, g.carrying_pid()])
	for c: SecurityCamera in cameras:
		out.append("C%d watching %s" % [c.camera_id, str(c.watched_pids())])
	return out
