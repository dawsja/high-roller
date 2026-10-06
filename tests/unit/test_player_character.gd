extends TestCase

## Stands in for a guard carrying the player.
class FakeCarrier extends Node3D:
	func get_carry_point() -> Vector3:
		return global_position + Vector3(0, 1.4, 0)


var _world: Node3D


func before_each() -> void:
	InputSetup.ensure_actions()
	_world = Node3D.new()
	_world.name = "PlayerTestWorld"
	tree.root.add_child(_world)
	var floor := Primitives.static_box(Vector3(60, 1, 60), Color.DIM_GRAY)
	floor.position = Vector3(0, -0.5, 0)
	_world.add_child(floor)


func after_each() -> void:
	for action: StringName in InputSetup.ACTIONS:
		Input.action_release(action)
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await tree.process_frame
	_world = null


func _spawn(local: bool = true, pos: Vector3 = Vector3.ZERO) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.setup(1 if local else 2, local, null)
	player.position = pos + Vector3(0, 0.05, 0)
	_world.add_child(player)
	await _frames(12)
	return player


func _frames(n: int) -> void:
	for i in n:
		await tree.physics_frame


func _hold(action: StringName, frames: int) -> void:
	Input.action_press(action)
	await _frames(frames)
	Input.action_release(action)
	await _frames(1)


func _guard(pos: Vector3) -> StaticBody3D:
	var guard := Primitives.static_box(Vector3(0.6, 1.8, 0.6), Color.NAVY_BLUE, 4)
	guard.get_child(0).position.y = 0.9
	guard.get_child(1).position.y = 0.9
	guard.position = pos
	guard.add_to_group(&"guards")
	_world.add_child(guard)
	return guard


func _interactable(kind: StringName, pos: Vector3, hold: float = 0.0) -> Interactable:
	var it := Interactable.create(kind, "Use %s" % kind, 0.4, {}, hold)
	it.position = pos
	_world.add_child(it)
	return it


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


# --- Body and camera ------------------------------------------------------------

func test_builds_body_on_player_layer_with_camera_when_local() -> void:
	var player := await _spawn()
	assert_eq(player.collision_layer, 2)
	assert_eq(player.collision_mask, 1 | 4 | 8, "world + guard + patron")
	assert_not_null(player.model)
	assert_not_null(player.camera_rig, "local player has a camera")
	assert_true(player.camera_rig.camera.is_current())
	assert_true(player.is_on_floor(), "stands on the floor")
	assert_almost_eq(player.global_position.y, 0.0, 0.06)
	assert_eq(player.state, PlayerCharacter.STATE_FREE)
	var remote := await _spawn(false, Vector3(4, 0, 0))
	assert_null(remote.camera_rig, "non-local player has no camera")


func test_camera_sits_behind_and_above_and_zooms() -> void:
	var player := await _spawn()
	var rig := player.camera_rig
	await _frames(10)
	var cam := rig.camera.global_position
	assert_gt(cam.z, player.global_position.z + 2.0, "behind the player (+Z) at yaw 0")
	assert_gt(cam.y, Tuning.PLAYER_CAMERA_HEIGHT, "looks down from above")
	rig.zoom(-100.0)
	assert_almost_eq(rig.distance, Tuning.PLAYER_CAMERA_MIN_DISTANCE, 0.001)
	rig.zoom(100.0)
	assert_almost_eq(rig.distance, Tuning.PLAYER_CAMERA_MAX_DISTANCE, 0.001)
	rig.add_look(0.0, -10.0)
	assert_almost_eq(rig.pitch, deg_to_rad(Tuning.PLAYER_CAMERA_PITCH_MIN_DEGREES), 0.001, "pitch clamped")


func test_camera_spring_arm_pulls_in_at_a_wall() -> void:
	var player := await _spawn()
	var wall := Primitives.static_box(Vector3(6, 4, 0.4), Color.GRAY)
	wall.position = Vector3(0, 2, 1.6)
	_world.add_child(wall)
	await _frames(10)
	assert_lt(player.camera_rig.camera.global_position.z, 1.4, "camera stays in front of the wall")


# --- Movement -----------------------------------------------------------------

func test_forward_moves_away_from_the_camera() -> void:
	var player := await _spawn()
	var start := player.global_position
	await _hold(&"move_forward", 20)
	var moved := player.global_position - start
	assert_lt(moved.z, -0.5, "forward is -Z at camera yaw 0")
	assert_almost_eq(moved.x, 0.0, 0.05)
	assert_almost_eq(player.facing, 0.0, 0.05, "faces where it walks")


func test_movement_is_camera_relative() -> void:
	var player := await _spawn()
	player.camera_rig.add_look(PI * 0.5, 0.0)
	var start := player.global_position
	await _hold(&"move_forward", 20)
	var moved := player.global_position - start
	assert_lt(moved.x, -0.5, "camera turned 90 degrees left: forward is -X")
	assert_almost_eq(moved.z, 0.0, 0.05)
	player.camera_rig.add_look(-PI * 0.5, 0.0)
	start = player.global_position
	await _hold(&"move_right", 20)
	moved = player.global_position - start
	assert_gt(moved.x, 0.5, "right is +X at yaw 0")
	assert_almost_eq(moved.z, 0.0, 0.05)
	await _frames(20)
	assert_almost_eq(player.facing, -PI * 0.5, 0.1, "model turned to face +X")


func test_running_is_faster_than_walking() -> void:
	var walker := await _spawn(true, Vector3(-3, 0, 0))
	var start := walker.global_position
	Input.action_press(&"move_forward")
	await _frames(30)
	assert_false(walker.is_running())
	assert_eq(walker.model.pose, &"walk")
	var walked := (walker.global_position - start).length()
	Input.action_press(&"run")
	start = walker.global_position
	await _frames(30)
	assert_true(walker.is_running())
	assert_eq(walker.model.pose, &"run")
	var ran := (walker.global_position - start).length()
	assert_gt(ran, walked * 1.5, "run %.2f m vs walk %.2f m" % [ran, walked])
	assert_almost_eq(walked, Tuning.PLAYER_WALK_SPEED * 0.5, 0.25, "about walk speed for half a second")


func test_jump_leaves_the_floor_and_lands() -> void:
	var player := await _spawn()
	assert_true(player.is_on_floor())
	await _hold(&"jump", 2)
	var peak := 0.0
	for i in 20:
		await tree.physics_frame
		peak = maxf(peak, player.global_position.y)
	assert_gt(peak, 0.5, "jumped")
	assert_eq(player.model.pose, &"jump")
	await _frames(60)
	assert_true(player.is_on_floor(), "landed")
	assert_almost_eq(player.global_position.y, 0.0, 0.06)


func test_input_disabled_blocks_movement_and_actions() -> void:
	var player := await _spawn()
	var jumps: Array = []
	player.throw_chips_requested.connect(func(p: Vector3) -> void: jumps.append(p))
	player.set_input_enabled(false)
	assert_false(player.is_input_enabled())
	assert_false(player.camera_rig.is_look_enabled())
	var start := player.global_position
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	Input.action_press(&"throw_chips")
	await _frames(15)
	assert_lt((player.global_position - start).length(), 0.01, "no movement while a panel is open")
	assert_eq(jumps.size(), 0)
	for action: StringName in [&"move_forward", &"jump", &"throw_chips"]:
		Input.action_release(action)
	player.set_input_enabled(true)
	await _hold(&"move_forward", 10)
	assert_gt((player.global_position - start).length(), 0.1, "moves again")


func test_non_local_player_ignores_input() -> void:
	var player := await _spawn(false)
	var start := player.global_position
	await _hold(&"move_forward", 15)
	assert_lt((player.global_position - start).length(), 0.01)


# --- Seated, carried, hidden, tumble --------------------------------------------

func test_sit_at_locks_movement_and_stand_up_steps_back() -> void:
	var player := await _spawn()
	var seat := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(2, 0, 2))
	player.sit_at(seat)
	assert_eq(player.state, PlayerCharacter.STATE_SEATED)
	assert_eq(player.collision_layer, 0, "collision off while seated")
	await _frames(2)
	assert_eq(player.model.pose, &"sit")
	assert_true(player.global_position.is_equal_approx(seat.origin))
	assert_almost_eq(player.facing, -PI * 0.5, 0.01, "faces the seat's -Z (+X)")
	var stands: Array = []
	player.stand_requested.connect(func() -> void: stands.append(true))
	Input.action_press(&"move_forward")
	Input.action_press(&"run")
	await _frames(15)
	Input.action_release(&"move_forward")
	Input.action_release(&"run")
	assert_true(player.global_position.is_equal_approx(seat.origin), "can't walk off a seat")
	player.set_playing(true)
	await _frames(1)
	assert_eq(player.model.pose, &"play")
	await _hold(&"jump", 2)
	assert_eq(stands.size(), 1, "jump asks to stand")
	assert_eq(player.state, PlayerCharacter.STATE_SEATED, "only the director stands you up")
	player.stand_up()
	assert_eq(player.state, PlayerCharacter.STATE_FREE)
	assert_eq(player.collision_layer, 2)
	var off := player.global_position - seat.origin
	assert_almost_eq(off.length(), Tuning.PLAYER_STAND_UP_STEP, 0.01)
	assert_lt(off.x, -0.5, "stepped back, away from the table")


func test_set_carried_follows_the_carrier_until_released() -> void:
	var player := await _spawn()
	var carrier := FakeCarrier.new()
	carrier.position = Vector3(1, 0, 1)
	_world.add_child(carrier)
	player.set_carried(carrier)
	assert_eq(player.state, PlayerCharacter.STATE_CARRIED)
	assert_true(player.is_carried())
	assert_eq(player.collision_layer, 0)
	assert_eq(player.collision_mask, 0)
	carrier.position = Vector3(5, 0, -3)
	carrier.rotation.y = PI * 0.5
	await _frames(3)
	assert_true(player.global_position.is_equal_approx(carrier.get_carry_point()), "at the carry point: %s" % player.global_position)
	assert_almost_eq(player.facing, PI * 0.5, 0.01, "takes the carrier's yaw")
	assert_eq(player.model.pose, &"carried")
	Input.action_press(&"move_forward")
	await _frames(5)
	Input.action_release(&"move_forward")
	assert_true(player.global_position.is_equal_approx(carrier.get_carry_point()), "no walking while carried")
	player.release(Vector3(6, 0, 0))
	assert_eq(player.state, PlayerCharacter.STATE_FREE)
	assert_eq(player.collision_layer, 2)
	assert_true(player.global_position.is_equal_approx(Vector3(6, 0, 0)))
	await _frames(5)
	assert_true(player.is_on_floor())
	carrier.queue_free()


func test_carrier_freed_releases_the_player() -> void:
	var player := await _spawn()
	var carrier := FakeCarrier.new()
	_world.add_child(carrier)
	player.set_carried(carrier)
	await _frames(2)
	carrier.queue_free()
	await _frames(3)
	assert_eq(player.state, PlayerCharacter.STATE_FREE)


func test_struggled_fires_on_jump_while_carried() -> void:
	var player := await _spawn()
	var carrier := FakeCarrier.new()
	_world.add_child(carrier)
	var struggles: Array = []
	player.struggled.connect(func() -> void: struggles.append(true))
	player.set_carried(carrier)
	await _hold(&"jump", 3)
	assert_eq(struggles.size(), 1, "one press, one struggle")
	await _hold(&"jump", 3)
	await _hold(&"jump", 3)
	assert_eq(struggles.size(), 3)
	assert_gt(player.global_position.y, 1.0, "still up on the shoulder")


func test_set_hidden_removes_the_player_from_the_floor() -> void:
	var player := await _spawn()
	player.set_hidden(true)
	assert_true(player.is_hidden())
	assert_false(player.model.visible)
	assert_eq(player.collision_layer, 0)
	var start := player.global_position
	await _hold(&"move_forward", 10)
	assert_true(player.global_position.is_equal_approx(start), "no movement while hidden")
	player.teleport(Vector3(3, 0.05, 3))
	player.set_hidden(false)
	assert_eq(player.state, PlayerCharacter.STATE_FREE)
	assert_true(player.model.visible)
	assert_eq(player.collision_layer, 2)
	await _frames(5)
	assert_almost_eq(player.global_position.x, 3.0, 0.01)
	assert_true(player.is_on_floor())


func test_tumble_falls_and_gets_back_up() -> void:
	var player := await _spawn()
	player.tumble()
	assert_eq(player.action, PlayerCharacter.ACTION_TUMBLE)
	assert_eq(player.model.pose, &"tumble")
	var start := player.global_position
	Input.action_press(&"move_forward")
	await _frames(20)
	assert_lt((player.global_position - start).length(), 0.01, "can't walk while knocked down")
	Input.action_release(&"move_forward")
	await _frames(int(Tuning.CHARACTER_TUMBLE_SECONDS * 60.0) + 5)
	assert_eq(player.action, PlayerCharacter.ACTION_NONE)
	assert_ne(player.model.pose, &"tumble")


# --- Interaction ----------------------------------------------------------------

func test_interact_pressed_with_the_interactable_in_front() -> void:
	var player := await _spawn()
	var focus: Array = []
	var pressed: Array = []
	player.focus_changed.connect(func(t: Interactable) -> void: focus.append(t))
	player.interact_pressed.connect(func(t: Interactable) -> void: pressed.append(t))
	var behind := _interactable(&"cashier", Vector3(0, 0.9, 2.5))
	var table := _interactable(&"table", Vector3(0, 0.9, -1.0))
	await _frames(3)
	assert_eq(player.current_interactable(), table, "the one in front, not the one behind")
	assert_eq(focus.size(), 1)
	assert_eq(focus[0], table)
	await _hold(&"interact", 2)
	assert_eq(pressed.size(), 1)
	assert_eq(pressed[0], table)
	table.enabled = false
	await _frames(2)
	assert_null(player.current_interactable(), "disabled interactables are skipped")
	assert_eq(focus.size(), 2)
	assert_null(focus[1])
	await _hold(&"interact", 2)
	assert_eq(pressed.size(), 1, "nothing to use")
	behind.queue_free()


func test_hold_interaction_fires_held_and_a_tap_is_a_press() -> void:
	var player := await _spawn()
	var pressed: Array = []
	var held: Array = []
	player.interact_pressed.connect(func(t: Interactable) -> void: pressed.append(t))
	player.interact_held.connect(func(t: Interactable) -> void: held.append(t))
	var poster := _interactable(&"poster", Vector3(0, 1.0, -1.0), 0.25)
	await _frames(3)
	Input.action_press(&"interact")
	await _frames(8)
	assert_gt(player.interact_hold_progress(), 0.2)
	assert_eq(held.size(), 0)
	await _frames(12)
	assert_eq(held.size(), 1, "held for hold_seconds")
	assert_eq(held[0], poster)
	assert_eq(pressed.size(), 0, "a hold is not a press")
	Input.action_release(&"interact")
	await _frames(2)
	assert_eq(pressed.size(), 0)
	await _hold(&"interact", 3)
	assert_eq(pressed.size(), 1, "a tap is the quick action")
	assert_eq(held.size(), 1)


func test_throw_chips_and_knock_over_tray() -> void:
	var player := await _spawn()
	var thrown: Array = []
	var knocked: Array = []
	player.throw_chips_requested.connect(func(p: Vector3) -> void: thrown.append(p))
	player.knock_over_requested.connect(func(t: Interactable) -> void: knocked.append(t))
	await _hold(&"knock_over", 2)
	assert_eq(knocked.size(), 0, "no tray in reach")
	var tray := _interactable(&"tray", Vector3(0.3, 1.0, -0.9))
	await _frames(3)
	await _hold(&"knock_over", 2)
	assert_eq(knocked.size(), 1)
	assert_eq(knocked[0], tray)
	await _hold(&"throw_chips", 2)
	assert_eq(thrown.size(), 1)
	var expected := player.global_position + Vector3(0, 0, -Tuning.PLAYER_THROW_DISTANCE)
	assert_true((thrown[0] as Vector3).is_equal_approx(expected), "lands in front: %s" % thrown[0])


func test_pause_frees_the_mouse_and_asks_to_pause() -> void:
	var player := await _spawn()
	var pauses: Array = []
	player.pause_requested.connect(func() -> void: pauses.append(true))
	var ev := InputEventAction.new()
	ev.action = &"pause"
	ev.pressed = true
	player._unhandled_input(ev)
	assert_eq(pauses.size(), 1)
	player.set_input_enabled(false)
	player._unhandled_input(ev)
	assert_eq(pauses.size(), 1, "a UI panel handles Esc itself")


# --- Guards -----------------------------------------------------------------------

func test_tackle_requested_for_a_guard_in_front() -> void:
	var player := await _spawn()
	var tackles: Array = []
	player.tackle_requested.connect(func(t: Node3D) -> void: tackles.append(t))
	var behind := _guard(Vector3(0, 0, 1.2))
	await _hold(&"tackle", 2)
	assert_eq(tackles.size(), 0, "a guard behind is not tackled")
	assert_eq(player.action, PlayerCharacter.ACTION_TACKLE, "whiffs anyway")
	assert_eq(player.model.pose, &"tackle")
	await _frames(int((Tuning.PLAYER_TACKLE_SECONDS + Tuning.PLAYER_DIVE_RECOVER_SECONDS) * 60.0) + 15)
	assert_eq(player.action, PlayerCharacter.ACTION_NONE, "back on its feet")
	behind.queue_free()
	player.teleport(Vector3(0, 0.05, 6))
	await _frames(3)
	var front := _guard(Vector3(0.3, 0, 4.6))
	_guard(Vector3(0, 0, 3.0))
	await _hold(&"tackle", 2)
	assert_eq(tackles.size(), 1)
	assert_eq(tackles[0], front, "the nearest guard in front")


func test_dive_lunges_and_tackles_a_guard_in_reach() -> void:
	var player := await _spawn()
	var tackles: Array = []
	player.tackle_requested.connect(func(t: Node3D) -> void: tackles.append(t))
	var guard := _guard(Vector3(0, 0, -4.0))
	var start := player.global_position
	await _hold(&"dive", 2)
	assert_eq(player.action, PlayerCharacter.ACTION_DIVE)
	assert_eq(player.model.pose, &"dive")
	await _frames(20)
	assert_eq(tackles.size(), 1, "dove into the guard")
	assert_eq(tackles[0], guard)
	assert_lt(player.global_position.z, start.z - 1.5, "lunged forward")
	await _frames(int(Tuning.PLAYER_DIVE_RECOVER_SECONDS * 60.0) + 30)
	assert_eq(player.action, PlayerCharacter.ACTION_NONE, "got back up")
	assert_eq(tackles.size(), 1, "once per dive")


func test_running_into_a_guard_bumps_once_per_contact() -> void:
	var player := await _spawn()
	var bumps: Array = []
	player.bumped.connect(func(g: Node3D) -> void: bumps.append(g))
	var guard := _guard(Vector3(0, 0, -2.5))
	Input.action_press(&"move_forward")
	await _frames(40)
	Input.action_release(&"move_forward")
	assert_eq(bumps.size(), 0, "walking into a guard is not a bump")
	player.teleport(Vector3(0, 0.05, 0))
	await _frames(3)
	Input.action_press(&"run")
	Input.action_press(&"move_forward")
	await _frames(45)
	assert_eq(bumps.size(), 1, "pushing against the guard is one contact")
	assert_eq(bumps[0], guard)
	Input.action_release(&"move_forward")
	Input.action_press(&"move_back")
	await _frames(25)
	Input.action_release(&"move_back")
	Input.action_press(&"move_forward")
	await _frames(60)
	assert_eq(bumps.size(), 2, "backing off and running in again is a new bump")
