extends TestCase
## Co-op in one process: a host and a client SimHost joined by a fake
## transport, each with its own CasinoDirector (the client's in its own
## World3D so the two maps don't collide). Checks that the client builds the
## same visit from the announcement, with puppets for everything the host
## simulates, and the host -> owner placement, carry and tackle flows. Real
## sockets are covered by test_net_two_process.gd (tools/net_test.sh).

const CLIENT_PID := 2

var host: SimHost
var client: SimHost
var host_dir: CasinoDirector
var client_dir: CasinoDirector
var _nodes: Array[Node] = []
var _ticks: int = 60
var _time_scale: float = 1.0


func before_each() -> void:
	_ticks = Engine.physics_ticks_per_second
	_time_scale = Engine.time_scale
	InputSetup.ensure_actions()


func after_each() -> void:
	Engine.physics_ticks_per_second = _ticks
	Engine.time_scale = _time_scale
	for n: Node in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tree.process_frame
	await tree.physics_frame


func _wire(args: Array) -> Array:
	return bytes_to_var(var_to_bytes(args))


func _add(node: Node, parent: Node = null) -> Node:
	(parent if parent != null else tree.root).add_child(node)
	_nodes.append(node)
	return node


## Host and client hosts, a practice visit at Sal's, both directors built.
func _start() -> void:
	host = SimHost.new()
	host.name = "NetTestHost"
	client = SimHost.new()
	client.name = "NetTestClient"
	_add(host)
	_add(client)
	host.set_network(SimHost.Role.HOST, 1)
	client.set_network(SimHost.Role.CLIENT, CLIENT_PID)
	host.transport = func(to: int, method: StringName, args: Array) -> void:
		if to == 0 or to == CLIENT_PID:
			client.receive(1, method, _wire(args))
	client.transport = func(to: int, method: StringName, args: Array) -> void:
		if to == 1 or to == 0:
			host.receive(CLIENT_PID, method, _wire(args))
	host.start_run(Tuning.BOTTOM_RUNG, 77, {1: "Ace", CLIENT_PID: "Deuce"})
	host.visit_extras = {"practice": true}
	host.start_visit()
	host_dir = CasinoDirector.new()
	_add(host_dir)
	host_dir.setup(host, Tuning.BOTTOM_RUNG, true)
	# The client's visit lives in its own world (same coordinates as the host's).
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(64, 64)
	_add(view)
	client_dir = CasinoDirector.new()
	view.add_child(client_dir)
	client_dir.setup(client, int(client.visit_info()["rung"]), false)


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.physics_frame
	return bool(cond.call())


## Moves the host's copy of the client's player (what its synchronizer would do).
func _sync_client_body(pos: Vector3) -> void:
	var puppet: PlayerCharacter = host_dir.players[CLIENT_PID]
	puppet.net_position = pos
	puppet.global_position = pos


func test_the_client_builds_the_same_visit_with_puppets() -> void:
	_start()
	assert_true(client_dir.online and not client_dir.authority)
	assert_eq(client_dir.rung, host_dir.rung)
	assert_true(client_dir.practice, "practice comes from the visit announcement")
	assert_eq(client_dir.map.table_anchors.size(), host_dir.map.table_anchors.size())
	for id: StringName in host_dir.tables:
		assert_true(client_dir.tables.has(id), "table %s on the client" % id)
	assert_eq(client_dir.guards.size(), host_dir.guards.size())
	for i in host_dir.guards.size():
		assert_eq(String(client_dir.guards[i].name), String(host_dir.guards[i].name), "same guard names")
		assert_true(client_dir.guards[i].puppet, "client guards are puppets")
		assert_false(host_dir.guards[i].puppet)
		assert_not_null(NetSync.of(client_dir.guards[i]), "both sides have the synchronizer")
		assert_not_null(NetSync.of(host_dir.guards[i]))
	assert_eq(client_dir.crowd.patron_count(), host_dir.crowd.patron_count())
	assert_true(client_dir.crowd.puppet)
	for i in host_dir.crowd.patrons.size():
		assert_eq(String(client_dir.crowd.patrons[i].name), String(host_dir.crowd.patrons[i].name))
	# Players: each peer drives its own, the other is a puppet with a nameplate.
	assert_eq(client_dir.player.pid, CLIENT_PID)
	assert_not_null(client_dir.player.camera_rig)
	assert_false(client_dir.player.puppet)
	var host_copy: PlayerCharacter = client_dir.players[1]
	assert_true(host_copy.puppet)
	assert_null(host_copy.camera_rig)
	assert_not_null(host_copy.nameplate)
	assert_eq(host_copy.nameplate.text, "Ace")
	assert_eq(String(host_dir.players[CLIENT_PID].name), "Player_%d" % CLIENT_PID)
	assert_eq(client_dir.players[CLIENT_PID].get_multiplayer_authority(), CLIENT_PID, "the owner sends its player")
	assert_eq(NetSync.of(client_dir.players[CLIENT_PID]).get_multiplayer_authority(), CLIENT_PID)
	# Ready handshake: the client reported in, the host shared the list.
	assert_has(host_dir.ready_peers, CLIENT_PID)
	assert_has(client_dir.ready_peers, CLIENT_PID)
	assert_has(client_dir.ready_peers, 1)


func test_a_client_sits_through_the_host() -> void:
	_start()
	await _frames(2)
	var table: TableNode = null
	for t: TableNode in host_dir.tables.values():
		if t.game_type == HR.GameType.SLOTS:
			table = t
	assert_not_null(table)
	var it: Interactable = client_dir.tables[table.table_id].interactable
	# Far from the table on the host: refused.
	client_dir.interact(CLIENT_PID, it)
	assert_eq(host.current_sim().player(CLIENT_PID).status, HR.PlayerStatus.FREE, "too far on the host's copy")
	_sync_client_body(Vector3(table.interactable.global_position.x, 0.0, table.interactable.global_position.z))
	client_dir.interact(CLIENT_PID, it)
	assert_eq(host.current_sim().player(CLIENT_PID).status, HR.PlayerStatus.SEATED, "the host seated them")
	assert_eq(client_dir.player.state, PlayerCharacter.STATE_SEATED, "the owner sat its own body down")
	assert_lt(client_dir.player.global_position.distance_to(table.seat_transform().origin), 0.01)
	assert_eq(host_dir.players[CLIENT_PID].state, PlayerCharacter.STATE_FREE, "the host's copy waits for the sync")
	client.request_stand(CLIENT_PID)
	assert_eq(client_dir.player.state, PlayerCharacter.STATE_FREE, "stood up by the host's placement")


func test_a_grabbed_client_rides_its_puppet_guard_and_a_tackle_frees_the_host() -> void:
	_fast()
	_start()
	assert_true(await _until(func() -> bool: return host_dir.npcs_active and client_dir.npcs_active, 400))
	var g: GuardNPC = host_dir.guards[0]
	var puppet_guard: GuardNPC = client_dir.guards[0]
	# The host's guard grabs the client: the client's body rides the puppet.
	host_dir._on_guard_grabbed(g, CLIENT_PID)
	assert_eq(host.current_sim().player(CLIENT_PID).status, HR.PlayerStatus.CARRIED)
	assert_true(client_dir.player.is_carried())
	await _frames(2)
	assert_lt(client_dir.player.global_position.distance_to(puppet_guard.get_carry_point()), 0.01, "follows the puppet's carry point")
	host.request_freed(CLIENT_PID, 0)
	assert_false(client_dir.player.is_carried(), "released by the host's placement")
	# Now the guard carries the host player; the client tackles it. (The guard's
	# brain grabs in play; here it is told it carries them.)
	g.set(&"_carrying", 1)
	host_dir._on_guard_grabbed(g, 1)
	assert_true(host_dir.player.is_carried())
	_sync_client_body(g.global_position + Vector3(0.8, 0.0, 0.0))
	client_dir._on_tackle_requested(puppet_guard, client_dir.player)
	var sim := host.current_sim()
	assert_eq(sim.player(1).status, HR.PlayerStatus.FREE, "the client's tackle freed the host")
	assert_false(host_dir.player.is_carried())
	assert_gte(sim.player(CLIENT_PID).heat.value, Tuning.WANTED_AT, "the tackler goes straight to Wanted")
	# A tackle from across the floor is ignored.
	await _frames(2)
	g.set(&"_carrying", 1)
	host_dir._on_guard_grabbed(g, 1)
	_sync_client_body(g.global_position + Vector3(30.0, 0.0, 0.0))
	client_dir._on_tackle_requested(puppet_guard, client_dir.player)
	assert_eq(sim.player(1).status, HR.PlayerStatus.CARRIED, "too far away on the host")


func test_give_chips_needs_a_teammate_in_reach() -> void:
	_start()
	var sim := host.current_sim()
	var host_body: PlayerCharacter = host_dir.player
	var before: int = sim.player(1).wallet.pocket
	_sync_client_body(host_body.global_position + Vector3(20.0, 0.0, 0.0))
	client_dir._on_give_chips_requested(client_dir.players[1], client_dir.player)
	assert_eq(sim.player(1).wallet.pocket, before, "too far apart on the host")
	_sync_client_body(host_body.global_position + Vector3(1.0, 0.0, 0.0))
	var pocket: int = sim.player(CLIENT_PID).wallet.pocket
	client_dir._on_give_chips_requested(client_dir.players[1], client_dir.player)
	assert_gt(sim.player(1).wallet.pocket, before, "handed over")
	assert_lt(sim.player(CLIENT_PID).wallet.pocket, pocket)


func test_the_client_leaving_removes_its_body_everywhere() -> void:
	_start()
	var host_copy: PlayerCharacter = host_dir.players[CLIENT_PID]
	host.remove_player(CLIENT_PID)
	host._flush_events()
	assert_false(host_dir.players.has(CLIENT_PID))
	assert_false(client_dir.players.has(CLIENT_PID))
	await tree.process_frame
	assert_false(is_instance_valid(host_copy), "its body is gone on the host")


func _fast() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
