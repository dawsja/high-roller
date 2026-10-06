extends TestCase

## A stand-in player body the guard can see (and collide with).
class FakePlayer extends CharacterBody3D:
	var running := false

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.75
		shape.shape = capsule
		shape.position = Vector3(0, 0.875, 0)
		add_child(shape)

	func is_running() -> bool:
		return running


var _world: Node3D
var _region: NavigationRegion3D
var _players: Array = []
var _events: Array = []


func before_each() -> void:
	_players = []
	_events = []
	_world = Node3D.new()
	_world.name = "GuardTestWorld"
	tree.root.add_child(_world)
	_region = NavigationRegion3D.new()
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_collision_mask = 1
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 2.0
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	_region.navigation_mesh = nav_mesh
	_world.add_child(_region)
	var floor := Primitives.static_box(Vector3(40, 1, 40), Color.DIM_GRAY)
	floor.position = Vector3(0, -0.5, 0)
	_region.add_child(floor)


func after_each() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await tree.process_frame
		await tree.physics_frame
	_world = null
	_players = []


# --- Helpers ------------------------------------------------------------------

func _provider() -> Array:
	return _players


func _wall(pos: Vector3, size: Vector3) -> void:
	var wall := Primitives.static_box(size, Color.GRAY)
	wall.position = pos
	_region.add_child(wall)


func _bake() -> void:
	_region.bake_navigation_mesh(false)
	var map := _region.get_navigation_map()
	for i in 60:
		await tree.physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_path(map, Vector3(-1, 0, 1), Vector3(1, 0, 1), true).is_empty():
			break
	await _frames(1)


func _player(pid: int, pos: Vector3, heat: float) -> FakePlayer:
	var p := FakePlayer.new()
	p.position = pos
	_world.add_child(p)
	_players.append({"pid": pid, "node": p, "heat": heat, "matches_poster": false, "staff_uniform": false, "available": true})
	return p


func _entry(pid: int) -> Dictionary:
	for e: Dictionary in _players:
		if e["pid"] == pid:
			return e
	return {}


func _guard(type: int, pos: Vector3, patrol: Array[Vector3] = [], back_room: Vector3 = Vector3(15, 0, 15)) -> GuardNPC:
	var guard := GuardNPC.new()
	guard.position = pos
	_world.add_child(guard)
	var route: Array[Vector3] = []
	route.assign(patrol)
	if route.is_empty():
		route.append(pos)
	guard.setup(1, type, route, back_room, _provider)
	guard.saw_player.connect(func(_g: GuardNPC, pid: int, _running: bool) -> void: _events.append(["saw_player", pid]))
	guard.id_check_requested.connect(func(_g: GuardNPC, pid: int) -> void: _events.append(["id_check_requested", pid]))
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _events.append(["grabbed", pid]))
	guard.delivered.connect(func(_g: GuardNPC, pid: int) -> void: _events.append(["delivered", pid]))
	guard.released.connect(func(_g: GuardNPC, pid: int) -> void: _events.append(["released", pid]))
	guard.radioed.connect(func(_g: GuardNPC, pid: int, _pos: Vector3) -> void: _events.append(["radioed", pid]))
	return guard


func _count(sig: String, pid: int = -1) -> int:
	var n := 0
	for e: Array in _events:
		if e[0] == sig and (pid < 0 or e[1] == pid):
			n += 1
	return n


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


## Waits up to `max_frames` for `cond` to hold; returns whether it did.
func _until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await tree.physics_frame
	return bool(cond.call())


# --- Build --------------------------------------------------------------------

func test_builds_guard_body_agent_and_visuals() -> void:
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	await _frames(2)
	assert_eq(guard.collision_layer, 4, "guard layer 3")
	assert_eq(guard.collision_mask, 1 | 2 | 8, "world + player + patron")
	assert_true(guard.is_in_group(&"guards"))
	assert_not_null(guard.nav_agent)
	assert_true(guard.nav_agent.avoidance_enabled)
	assert_almost_eq(guard.nav_agent.path_desired_distance, 0.5, 0.001)
	assert_almost_eq(guard.nav_agent.target_desired_distance, 0.8, 0.001)
	assert_eq(guard.model.uniform, &"guard")
	assert_not_null(guard.vision_cone)
	assert_true(guard.vision_cone.visible)
	assert_almost_eq(guard.vision_cone.reach, Tuning.VISION_RANGE, 0.001)
	assert_eq(guard.get_state(), HR.GuardState.PATROL)
	var carry := guard.get_carry_point()
	assert_gt(carry.y, 1.3, "carry point is on the shoulder")
	assert_lt(carry.y, 1.8)


func test_security_types_dress_differently() -> void:
	var pit := _guard(HR.SecurityType.PIT_BOSS, Vector3(-4, 0, 0))
	var head := _guard(HR.SecurityType.HEAD_OF_SECURITY, Vector3(0, 0, 0))
	var under := _guard(HR.SecurityType.UNDERCOVER, Vector3(4, 0, 0))
	await _frames(2)
	assert_eq(pit.model.uniform, &"pit_boss")
	assert_eq(head.model.uniform, &"head_of_security")
	assert_gt(head.model.get_head_top(), pit.model.get_head_top(), "head of security is bigger")
	assert_eq(under.model.uniform, &"", "undercover wears a patron outfit")
	assert_not_null(under.model.outfit)
	assert_false(under.model.outfit.is_staff_uniform())
	assert_false(under.vision_cone.visible, "undercover hides its cone while patrolling")


# --- Patrol and sight ---------------------------------------------------------

func test_guard_patrols_between_points() -> void:
	await _bake()
	var a := Vector3(-2.5, 0, 0)
	var b := Vector3(2.5, 0, 0)
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, a, [a, b])
	var reached_b := await _until(func() -> bool: return guard.global_position.distance_to(b) < 1.0, 240)
	assert_true(reached_b, "walked to the second point: %s" % guard.global_position)
	assert_eq(guard.model.pose, &"walk")
	var back := await _until(func() -> bool: return guard.global_position.distance_to(a) < 1.0, 240)
	assert_true(back, "looped back to the first point: %s" % guard.global_position)
	assert_eq(guard.get_state(), HR.GuardState.PATROL)
	assert_true(guard.vision_cone.color.is_equal_approx(GuardNPC.CONE_GREEN), "green cone on patrol")


func test_wanted_player_in_view_is_chased_and_grabbed() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -5), 90.0)
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _entry(pid)["available"] = false)
	await _frames(2)
	assert_gt(_count("saw_player", 1), 0, "saw the player in front")
	assert_true(guard.sees_pid(1))
	assert_eq(guard.get_state(), HR.GuardState.CHASE)
	assert_true(guard.vision_cone.color.is_equal_approx(GuardNPC.CONE_RED), "red cone while chasing")
	assert_eq(guard.icon.text, "!")
	var got := await _until(func() -> bool: return _count("grabbed", 1) > 0, 180)
	assert_true(got, "grabbed when close")
	assert_eq(guard.carrying_pid(), 1)
	assert_eq(guard.get_state(), HR.GuardState.CARRY)
	await _frames(3)
	assert_eq(guard.model.pose, &"carry")
	assert_eq(guard.carrying_pid(), 1, "still carrying (grab confirmed)")


func test_wall_blocks_sight() -> void:
	_wall(Vector3(0, 1.5, -2.5), Vector3(6, 3, 0.4))
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -5), 90.0)
	await _frames(10)
	assert_eq(_count("saw_player"), 0, "no sight through the wall")
	assert_false(guard.sees_pid(1))
	assert_eq(guard.get_state(), HR.GuardState.PATROL)
	assert_lt(guard.vision_cone.min_ray_length(), 3.0, "the drawn cone stops at the wall")


func test_player_behind_is_not_seen() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, 5), 90.0)
	await _frames(5)
	assert_false(guard.sees_pid(1), "outside the cone")
	assert_eq(guard.get_state(), HR.GuardState.PATROL)


func test_running_flag_comes_from_the_player() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	var p := _player(1, Vector3(3, 0, -8), 10.0)
	p.running = true
	var running_seen := []
	guard.saw_player.connect(func(_g: GuardNPC, _pid: int, running: bool) -> void: running_seen.append(running))
	await _frames(3)
	assert_false(running_seen.is_empty())
	assert_true(running_seen.all(func(r: bool) -> bool: return r), "running reported")
	assert_eq(guard.get_state(), HR.GuardState.PATROL, "an Unnoticed player is never approached")


# --- ID check -----------------------------------------------------------------

func test_suspected_player_gets_an_id_check_then_pass_returns_to_patrol() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -4.5), 60.0)
	await _frames(2)
	assert_eq(guard.get_state(), HR.GuardState.CHECK_ID, "walks over to check")
	var asked := await _until(func() -> bool: return _count("id_check_requested", 1) > 0, 150)
	assert_true(asked, "asked for ID within talk range")
	var player_pos: Vector3 = (_entry(1)["node"] as Node3D).global_position
	assert_lte(Perception.flat_distance(guard.global_position, player_pos), Tuning.TALK_RANGE + 0.05)
	assert_eq(guard.icon.text, "ID")
	assert_true(guard.vision_cone.color.is_equal_approx(GuardNPC.CONE_ORANGE), "orange cone while checking")
	await _frames(20)
	assert_eq(guard.get_state(), HR.GuardState.CHECK_ID, "waits for the answer")
	assert_eq(_count("id_check_requested"), 1, "asks once")
	assert_gt(guard.front_direction().dot(Vector3(player_pos.x - guard.global_position.x, 0, player_pos.z - guard.global_position.z).normalized()), 0.95, "faces the player")
	guard.set_id_check_result(1, true)
	await _frames(2)
	assert_eq(guard.get_state(), HR.GuardState.PATROL, "passed: back to patrol")
	await _frames(10)
	assert_eq(_count("id_check_requested"), 1, "not asked again after passing")


func test_failed_id_check_leads_to_a_grab() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -1.8), 60.0)
	# The sim may fail a check on the spot (burned card): answer inside the signal.
	guard.id_check_requested.connect(func(g: GuardNPC, pid: int) -> void: g.set_id_check_result(pid, false))
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _entry(pid)["available"] = false)
	# Check, ID_FAIL_REACTION_SECONDS of shouting, then the approach.
	var got := await _until(func() -> bool: return _count("grabbed", 1) > 0, 150)
	assert_true(got, "failed check -> grabbed")
	assert_eq(_count("id_check_requested", 1), 1)


func test_failed_id_check_shouts_before_the_chase() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -1.8), 60.0)
	var shouts: Array = []
	guard.shouted.connect(func(_g: GuardNPC, pid: int) -> void: shouts.append(pid))
	guard.id_check_requested.connect(func(g: GuardNPC, pid: int) -> void: g.set_id_check_result(pid, false))
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _entry(pid)["available"] = false)
	assert_true(await _until(func() -> bool: return not shouts.is_empty(), 60), "a failed check shouts")
	assert_eq(shouts, [1], "at the player who failed")
	await _frames(1)
	assert_true(guard.is_reacting())
	assert_eq(guard.get_state(), HR.GuardState.CHASE)
	assert_eq(guard.icon.text, GuardNPC.SHOUT_TEXT, "HEY! over the head")
	assert_true(guard.icon.visible)
	var start := guard.global_position
	await _frames(int(Tuning.ID_FAIL_REACTION_SECONDS * 60.0 * 0.6))
	assert_true(guard.is_reacting(), "still shouting")
	assert_eq(_count("grabbed"), 0, "no grab during the reaction")
	assert_lt(Perception.flat_distance(start, guard.global_position), 0.15, "stands while it shouts")
	var player_pos: Vector3 = (_entry(1)["node"] as Node3D).global_position
	assert_gt(guard.front_direction().dot((player_pos - guard.global_position).normalized()), 0.9, "faces the player")
	assert_true(await _until(func() -> bool: return not guard.is_reacting(), 60), "the reaction ends")
	assert_ne(guard.icon.text, GuardNPC.SHOUT_TEXT)
	assert_almost_eq(guard.icon.scale.x, 1.0, 0.001, "the pulse stops with the bark")
	assert_true(await _until(func() -> bool: return _count("grabbed", 1) > 0, 120), "then it runs and grabs")
	assert_eq(shouts.size(), 1, "shouts once")


func test_cleared_player_is_left_alone_until_wanted() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -4.5), 60.0)
	_entry(1)["cleared"] = true
	await _frames(20)
	assert_gt(_count("saw_player", 1), 0)
	assert_eq(guard.get_state(), HR.GuardState.PATROL, "passed a check with another guard: no walk-over")
	assert_eq(_count("id_check_requested"), 0)
	_entry(1)["heat"] = 90.0
	assert_true(await _until(func() -> bool: return guard.get_state() == HR.GuardState.CHASE, 10), "Wanted is still chased")


# --- Carry, struggle, stun ----------------------------------------------------

func test_carrying_heads_to_the_back_room_and_delivers() -> void:
	await _bake()
	var back_room := Vector3(4, 0, 0)
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO, [], back_room)
	var p := _player(1, Vector3(0, 0, -1.0), 90.0)
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void:
		_entry(pid)["available"] = false
		p.visible = false)
	var got := await _until(func() -> bool: return _count("grabbed", 1) > 0, 20)
	assert_true(got, "grabbed a Wanted player in reach")
	var start := Perception.flat_distance(guard.global_position, back_room)
	await _frames(40)
	assert_lt(Perception.flat_distance(guard.global_position, back_room), start - 0.5, "walks toward the back room")
	guard.on_struggle()
	guard.on_struggle()
	assert_almost_eq(guard.struggle_multiplier(), 1.0 - 2.0 * Tuning.STRUGGLE_SLOW_PER_PRESS, 0.02, "struggling slows the carry")
	for i in 20:
		guard.on_struggle()
	assert_almost_eq(guard.struggle_multiplier(), Tuning.STRUGGLE_MIN_SPEED_MULT, 0.001, "down to the floor")
	await _frames(30)
	assert_gt(guard.struggle_multiplier(), Tuning.STRUGGLE_MIN_SPEED_MULT, "recovers over time")
	var done := await _until(func() -> bool: return _count("delivered", 1) > 0, 300)
	assert_true(done, "delivered at the back room")
	assert_eq(guard.carrying_pid(), -1)
	assert_eq(guard.get_state(), HR.GuardState.PATROL)


func test_stun_while_carrying_releases_and_tumbles() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -1.0), 90.0)
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _entry(pid)["available"] = false)
	assert_true(await _until(func() -> bool: return _count("grabbed", 1) > 0, 20))
	await _frames(3)
	guard.stun()
	assert_eq(guard.model.pose, &"tumble")
	await _frames(2)
	assert_eq(_count("released", 1), 1, "released the carried player")
	assert_eq(guard.carrying_pid(), -1)
	assert_eq(guard.get_state(), HR.GuardState.STUNNED)
	assert_eq(guard.icon.text, "...")
	var pos := guard.global_position
	await _frames(20)
	assert_lt(guard.global_position.distance_to(pos), 0.05, "stands still while stunned")


func test_player_freed_by_the_sim_is_not_released_twice() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -1.0), 90.0)
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _entry(pid)["available"] = false)
	assert_true(await _until(func() -> bool: return _count("grabbed", 1) > 0, 20))
	await _frames(3)
	# A teammate's tackle: the director stuns the guard and frees the player.
	guard.stun()
	_entry(1)["available"] = true
	await _frames(3)
	assert_eq(_count("released"), 0, "the sim already freed them")
	assert_eq(guard.carrying_pid(), -1)
	assert_eq(guard.get_state(), HR.GuardState.STUNNED)


func test_fire_alarm_while_carrying_releases() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO, [Vector3(-3, 0, 3)])
	_player(1, Vector3(0, 0, -1.0), 90.0)
	guard.grabbed.connect(func(_g: GuardNPC, pid: int) -> void: _entry(pid)["available"] = false)
	assert_true(await _until(func() -> bool: return _count("grabbed", 1) > 0, 20))
	guard.set_fire_alarm(true)
	await _frames(2)
	assert_eq(_count("released", 1), 1)
	assert_true(guard.brain.is_evacuating())


# --- Hearing and radio --------------------------------------------------------

func test_heard_noise_makes_it_investigate() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	guard.hear({"position": Vector3(30, 0, 30), "radius": 5.0, "kind": &"knock_over"})
	await _frames(2)
	assert_eq(guard.get_state(), HR.GuardState.PATROL, "too far to hear")
	var spot := Vector3(4, 0, 3)
	guard.hear({"position": spot, "radius": Tuning.NOISE_RADIUS[&"knock_over"], "kind": &"knock_over"})
	await _frames(2)
	assert_eq(guard.get_state(), HR.GuardState.INVESTIGATE)
	assert_eq(guard.icon.text, "?")
	assert_true(guard.vision_cone.color.is_equal_approx(GuardNPC.CONE_YELLOW), "yellow cone")
	var there := await _until(func() -> bool: return Perception.flat_distance(guard.global_position, spot) < 1.0, 200)
	assert_true(there, "walked to the noise: %s" % guard.global_position)


func test_alert_sends_a_guard_after_an_unseen_player() -> void:
	_wall(Vector3(0, 1.5, -3), Vector3(8, 3, 0.4))
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -6), 60.0)
	await _frames(3)
	assert_eq(guard.get_state(), HR.GuardState.PATROL)
	guard.alert(1, Vector3(0, 0, -6))
	await _frames(2)
	assert_ne(guard.get_state(), HR.GuardState.PATROL, "radio tip acted on")
	assert_false(guard.sees_pid(1), "a tip is not a sighting")
	assert_eq(_count("saw_player"), 0)
	var moving := await _until(func() -> bool: return guard.global_position.distance_to(Vector3.ZERO) > 0.8, 120)
	assert_true(moving, "heads off toward the tip")


func test_pit_boss_radios_and_stays_at_its_post() -> void:
	await _bake()
	var post := Vector3.ZERO
	var boss := _guard(HR.SecurityType.PIT_BOSS, post, [post])
	_player(1, Vector3(0, 0, -7), 90.0)
	await _frames(3)
	assert_true(boss.sees_pid(1), "pit boss view (pit_boss_view flag)")
	assert_eq(_count("radioed", 1), 1, "radioed once")
	await _frames(30)
	assert_eq(_count("radioed", 1), 1, "cooldown between radio calls")
	assert_eq(_count("grabbed"), 0, "never grabs")
	assert_eq(_count("id_check_requested"), 0, "never checks ID")
	assert_lte(Perception.flat_distance(boss.global_position, post), Tuning.PIT_BOSS_POST_RADIUS + 0.1)
	assert_true(boss.vision_cone.color.is_equal_approx(GuardNPC.CONE_RED), "red cone on a Wanted player")
	boss.hear({"position": Vector3(10, 0, 0), "radius": 20.0, "kind": &"knock_over"})
	await _frames(150)
	assert_lte(Perception.flat_distance(boss.global_position, post), Tuning.PIT_BOSS_POST_RADIUS + 0.2, "clamped to the post radius")


func test_pit_boss_ignores_unnoticed_players() -> void:
	await _bake()
	var boss := _guard(HR.SecurityType.PIT_BOSS, Vector3.ZERO)
	_player(1, Vector3(0, 0, -5), 30.0)
	await _frames(5)
	assert_true(boss.sees_pid(1))
	assert_eq(_count("radioed"), 0, "Watched is below the radio threshold")


func test_unanswered_id_check_gives_up() -> void:
	await _bake()
	var guard := _guard(HR.SecurityType.FLOOR_GUARD, Vector3.ZERO)
	_player(1, Vector3(0, 0, -1.8), 60.0)
	assert_true(await _until(func() -> bool: return _count("id_check_requested", 1) > 0, 30), "asked")
	var wait := Tuning.ID_QUIZ_SECONDS + Tuning.ID_QUIZ_GRACE_SECONDS + Tuning.GUARD_ID_RESULT_EXTRA_SECONDS
	await _frames(int(wait * 60.0) - 30)
	assert_eq(guard.get_state(), HR.GuardState.CHECK_ID, "still waiting during the quiz")
	var gave_up := await _until(func() -> bool: return guard.get_state() == HR.GuardState.PATROL, 60)
	assert_true(gave_up, "no answer ever came (the sim refused the check): lets them go")
	assert_eq(_count("grabbed"), 0)


func test_puppet_shows_the_hosts_bark() -> void:
	var guard := GuardNPC.new()
	guard.puppet = true
	_world.add_child(guard)
	var route: Array[Vector3] = [Vector3.ZERO]
	guard.setup(1, HR.SecurityType.FLOOR_GUARD, route, Vector3(15, 0, 15), _provider)
	guard.net_state = HR.GuardState.CHASE
	guard.net_icon = GuardNPC.SHOUT_TEXT
	guard.net_icon_color = GuardNPC.SHOUT_COLOR
	await _frames(12)
	assert_true(guard.is_reacting(), "a client's copy knows the guard is shouting")
	assert_eq(guard.icon.text, GuardNPC.SHOUT_TEXT)
	assert_true(guard.icon.visible)
	assert_gt(guard.icon.scale.x, 1.0, "the bark pulses")
	guard.net_icon = "!"
	await _frames(2)
	assert_false(guard.is_reacting())
	assert_almost_eq(guard.icon.scale.x, 1.0, 0.001)
