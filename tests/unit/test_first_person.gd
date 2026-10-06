extends TestCase
## First-person controls: the look ray, pressables, holds, capture, the
## legacy Interactable path, the hands, the ID card and remote bodies.

## A pressable per the shared contract (duck typed, physics layer 5).
class FakePressable extends StaticBody3D:
	signal pressed(user_pid: int)
	signal held(user_pid: int)
	signal hover_changed(hovered: bool)

	var hint := "[LMB] PLAY"
	var enabled := true
	var hold_seconds := 0.0
	var hovered := false
	var presses: Array = []
	var holds: Array = []

	func _init(size: Vector3 = Vector3(0.3, 0.3, 0.1)) -> void:
		collision_layer = 16
		collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)

	func get_hint() -> String:
		return hint

	func set_hovered(value: bool) -> void:
		hovered = value
		hover_changed.emit(value)

	func press(user_pid: int) -> void:
		presses.append(user_pid)
		pressed.emit(user_pid)

	func hold_complete(user_pid: int) -> void:
		holds.append(user_pid)
		held.emit(user_pid)


## Something that captures the primary button (a dice throw).
class FakeOwner extends RefCounted:
	var downs: Array = []
	var ups: Array = []

	func on_primary_pressed(pid: int) -> void:
		downs.append(pid)

	func on_primary_released(pid: int) -> void:
		ups.append(pid)


var _world: Node3D


func before_each() -> void:
	InputSetup.ensure_actions()
	_world = Node3D.new()
	_world.name = "FirstPersonTestWorld"
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


func _spawn(local: bool = true, pos: Vector3 = Vector3.ZERO, id: int = -1) -> PlayerCharacter:
	var player := PlayerCharacter.new()
	player.setup(id if id > 0 else (1 if local else 2), local, null)
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


## A pressable at eye height `distance` m in front of a player at the origin.
func _pressable(distance: float, hold: float = 0.0) -> FakePressable:
	var p := FakePressable.new()
	p.hold_seconds = hold
	p.position = Vector3(0, FpTuning.EYE_HEIGHT, -distance)
	_world.add_child(p)
	return p


# --- Look ray, hover and press ---------------------------------------------------

func test_look_ray_hovers_a_pressable_and_lmb_presses_it() -> void:
	var player := await _spawn()
	var hovers: Array = []
	var pressed: Array = []
	player.hover_changed.connect(func(t: Node, hint: String) -> void: hovers.append([t, hint]))
	player.target_pressed.connect(func(t: Node) -> void: pressed.append(t))
	var key := _pressable(1.2)
	await _frames(3)
	assert_eq(player.current_target(), key, "the key in front is the target")
	assert_true(key.hovered, "it got set_hovered(true)")
	assert_eq(player.current_hint(), "[LMB] PLAY")
	assert_eq(hovers.size(), 1)
	assert_eq(hovers[0][0], key)
	assert_eq(hovers[0][1], "[LMB] PLAY")
	var expect := Vector3(0, player.eye_position().y, -1.15)
	assert_lt(player.target_point().distance_to(expect), 0.03, "ray hit on its face: %s" % player.target_point())
	await _hold(&"primary", 2)
	assert_eq(key.presses, [1], "press(pid) once per click")
	assert_eq(pressed.size(), 1)
	assert_eq(player.hands.current_anim(), &"press", "the right hand jabs")
	# Looking away un-hovers it.
	player.camera_rig.add_look(PI * 0.5, 0.0)
	await _frames(2)
	assert_null(player.current_target())
	assert_false(key.hovered, "set_hovered(false) when the view leaves it")
	assert_eq(hovers.size(), 2)
	assert_null(hovers[1][0])
	await _hold(&"primary", 2)
	assert_eq(key.presses.size(), 1, "nothing pressed when nothing is looked at")


func test_reach_disabled_keys_and_hint_changes() -> void:
	var player := await _spawn()
	var far := _pressable(FpTuning.REACH + 0.6)
	await _frames(3)
	assert_null(player.current_target(), "out of reach")
	assert_false(far.hovered)
	far.queue_free()
	var key := _pressable(1.0)
	key.enabled = false
	await _frames(3)
	assert_null(player.current_target(), "a disabled key is not a target")
	await _hold(&"primary", 2)
	assert_eq(key.presses.size(), 0)
	key.enabled = true
	var hints: Array = []
	player.hover_changed.connect(func(_t: Node, hint: String) -> void: hints.append(hint))
	await _frames(2)
	assert_eq(player.current_target(), key)
	key.hint = "[LMB] PLAY $500"
	await _frames(2)
	assert_eq(hints.back(), "[LMB] PLAY $500", "a changed hint is re-sent")
	assert_eq(player.current_hint(), "[LMB] PLAY $500")


func test_e_presses_too_and_input_off_ignores_presses() -> void:
	var player := await _spawn()
	var key := _pressable(1.0)
	await _frames(3)
	await _hold(&"interact", 2)
	assert_eq(key.presses, [1], "E is an alias for LMB")
	player.set_input_enabled(false)
	await _frames(2)
	assert_null(player.current_target(), "nothing hovered with a panel open")
	assert_false(key.hovered)
	await _hold(&"primary", 2)
	assert_eq(key.presses.size(), 1, "no presses while input is off")
	player.set_input_enabled(true)
	await _frames(2)
	assert_true(key.hovered)


func test_hold_target_reports_progress_and_completes_and_a_tap_presses() -> void:
	var player := await _spawn()
	var key := _pressable(1.0, 0.25)
	var progress: Array = []
	var held: Array = []
	player.hold_progress.connect(func(r: float) -> void: progress.append(r))
	player.target_held.connect(func(t: Node) -> void: held.append(t))
	await _frames(3)
	Input.action_press(&"primary")
	await _frames(8)
	assert_gt(player.interact_hold_progress(), 0.2)
	assert_eq(key.holds.size(), 0)
	await _frames(12)
	assert_eq(key.holds, [1], "hold_complete(pid) after hold_seconds")
	assert_eq(held.size(), 1)
	assert_eq(key.presses.size(), 0, "a hold is not a press")
	assert_gt(progress.size(), 5)
	assert_almost_eq(progress.max(), 1.0, 0.001)
	Input.action_release(&"primary")
	await _frames(2)
	assert_almost_eq(progress.back(), 0.0, 0.001, "progress resets when the hold ends")
	await _hold(&"primary", 3)
	assert_eq(key.presses, [1], "a quick tap is a press")
	assert_eq(key.holds.size(), 1)
	# Looking away mid-hold cancels it.
	Input.action_press(&"primary")
	await _frames(5)
	player.camera_rig.add_look(PI * 0.5, 0.0)
	await _frames(20)
	Input.action_release(&"primary")
	await _frames(2)
	assert_eq(key.holds.size(), 1, "the hold broke when the view left the key")


func test_capture_routes_lmb_to_its_owner() -> void:
	var player := await _spawn()
	var key := _pressable(1.0)
	var owner := FakeOwner.new()
	var downs: Array = []
	var ups: Array = []
	player.primary_pressed.connect(func() -> void: downs.append(true))
	player.primary_released.connect(func() -> void: ups.append(true))
	await _frames(3)
	assert_true(key.hovered)
	player.begin_capture(owner)
	assert_true(player.is_captured())
	assert_eq(player.capture_owner(), owner)
	await _frames(2)
	assert_false(key.hovered, "nothing hovered while captured")
	Input.action_press(&"primary")
	await _frames(3)
	assert_eq(owner.downs, [1], "the owner gets the press")
	assert_eq(downs.size(), 1)
	Input.action_release(&"primary")
	await _frames(2)
	assert_eq(owner.ups, [1], "and the release")
	assert_eq(ups.size(), 1)
	assert_eq(key.presses.size(), 0, "the key was not pressed")
	player.end_capture(FakeOwner.new())
	assert_true(player.is_captured(), "only the owner (or null) ends it")
	player.end_capture(owner)
	assert_false(player.is_captured())
	await _frames(2)
	await _hold(&"primary", 2)
	assert_eq(key.presses, [1], "pressing works again")
	assert_eq(owner.downs.size(), 1)
	# Being carried ends a capture.
	player.begin_capture(owner)
	var carrier := Node3D.new()
	_world.add_child(carrier)
	player.set_carried(carrier)
	assert_false(player.is_captured(), "carried: the capture ends")


func test_input_off_mid_press_releases_the_primary_button() -> void:
	var player := await _spawn()
	var owner := FakeOwner.new()
	player.begin_capture(owner)
	Input.action_press(&"primary")
	await _frames(2)
	assert_eq(owner.downs.size(), 1)
	player.set_input_enabled(false)
	assert_eq(owner.ups.size(), 1, "a panel opening lets go of the button")


func test_legacy_interactable_on_the_ray() -> void:
	var player := await _spawn()
	var it := Interactable.create(&"cashier", "Cash out", 0.3)
	it.position = Vector3(0, FpTuning.EYE_HEIGHT, -1.6)
	_world.add_child(it)
	var used: Array = []
	it.used.connect(func(user: Node3D, _i: Interactable) -> void: used.append(user))
	await _frames(3)
	assert_eq(player.current_target(), it, "the ray finds legacy Interactables too")
	assert_eq(player.current_interactable(), it)
	assert_eq(player.current_hint(), "Cash out")
	await _hold(&"primary", 2)
	assert_eq(used, [player], "nothing listens to interact_pressed: the player calls use() itself")
	var pressed: Array = []
	player.interact_pressed.connect(func(t: Interactable) -> void: pressed.append(t))
	await _hold(&"primary", 2)
	assert_eq(pressed, [it], "the director's flow: interact_pressed")
	assert_eq(used.size(), 1, "and the director calls use(), not the player")


func test_a_pressable_beats_a_legacy_sphere_around_it() -> void:
	var player := await _spawn()
	var it := Interactable.create(&"table", "Sit", 0.5)
	it.position = Vector3(0, FpTuning.EYE_HEIGHT, -1.5)
	_world.add_child(it)
	var key := _pressable(1.5)
	await _frames(3)
	assert_eq(player.current_target(), key, "the key inside the table's sphere wins")


# --- Look and movement ----------------------------------------------------------------

func test_mouse_look_turns_the_view_and_the_body() -> void:
	var player := await _spawn()
	var rig := player.camera_rig
	rig.mouse_sensitivity = 0.1
	rig.apply_mouse_motion(Vector2(100, 0))
	assert_almost_eq(rig.yaw, -deg_to_rad(10.0), 0.001, "100 px right turns 10 degrees right")
	rig.apply_mouse_motion(Vector2(0, -200))
	assert_almost_eq(rig.pitch, deg_to_rad(20.0), 0.001, "mouse up looks up")
	rig.invert_y = true
	rig.apply_mouse_motion(Vector2(0, -100))
	assert_almost_eq(rig.pitch, deg_to_rad(10.0), 0.001, "inverted")
	rig.apply_mouse_motion(Vector2(0, -100000))
	assert_almost_eq(rig.pitch, -deg_to_rad(FpTuning.PITCH_LIMIT_DEGREES), 0.001, "clamped")
	await _frames(2)
	assert_almost_eq(player.facing, rig.yaw, 0.001, "the body faces the view")
	assert_almost_eq(player.look_pitch, rig.pitch, 0.001)
	# Forward now walks along the new heading (10 degrees right of -Z).
	var start := player.global_position
	await _hold(&"move_forward", 20)
	var moved := player.global_position - start
	assert_gt(moved.x, 0.05, "forward bends right with the view")
	assert_lt(moved.z, -0.5)
	# A settings menu sets the defaults once; every new rig (each visit) starts from them.
	CameraRig.default_mouse_sensitivity = 0.25
	CameraRig.default_invert_y = true
	var fresh := CameraRig.new()
	assert_almost_eq(fresh.mouse_sensitivity, 0.25, 0.0001)
	assert_true(fresh.invert_y)
	fresh.free()
	CameraRig.default_mouse_sensitivity = FpTuning.MOUSE_DEGREES_PER_PIXEL
	CameraRig.default_invert_y = false


func test_look_toward_aims_the_view() -> void:
	var player := await _spawn()
	player.look_toward(Vector3(3, FpTuning.EYE_HEIGHT, 0.05))
	await _frames(1)
	var d := player.look_direction()
	assert_gt(d.x, 0.95, "looking along +X: %s" % d)
	assert_almost_eq(player.facing, -PI * 0.5, 0.05)


func test_landing_dips_and_reports_the_fall() -> void:
	var player := await _spawn()
	var landings: Array = []
	player.landed.connect(func(speed: float) -> void: landings.append(speed))
	await _hold(&"jump", 2)
	await _frames(70)
	assert_eq(landings.size(), 1, "one landing")
	assert_gt(landings[0], 2.0, "fell at %.2f m/s" % landings[0])


func test_walking_bobs_the_head_and_steps() -> void:
	var player := await _spawn()
	var steps: Array = []
	player.footstep.connect(func(running: bool) -> void: steps.append(running))
	Input.action_press(&"move_forward")
	var ys: Array = []
	for i in 60:
		await tree.physics_frame
		ys.append(player.camera_rig.camera.position.y)
	Input.action_release(&"move_forward")
	assert_gt(steps.size(), 2, "footsteps while walking")
	assert_gt(ys.max() - ys.min(), 0.01, "the head bobs")
	assert_gt(player.camera_rig.bob_weight(), 0.5)


# --- Hands -----------------------------------------------------------------------

func test_hands_hold_and_release_keep_world_transforms() -> void:
	var player := await _spawn()
	var hands := player.hands
	var item := Primitives.box(Vector3(0.07, 0.07, 0.07), Color.RED)
	item.position = Vector3(0.6, 1.0, -0.5)
	item.rotation = Vector3(0.3, 0.2, 0.1)
	_world.add_child(item)
	var before := item.global_transform
	hands.hold(item, FirstPersonHands.HOLD_BOTH)
	assert_true(hands.is_holding())
	assert_eq(hands.held_item(), item)
	assert_eq(hands.hold_mode(), FirstPersonHands.HOLD_BOTH)
	assert_true(hands.is_ancestor_of(item), "the item rides the hands")
	assert_true(item.global_transform.is_equal_approx(before), "picked up where it was")
	await _frames(40)
	var cam_local := player.camera_rig.camera.global_transform.affine_inverse() * item.global_position
	assert_lt(cam_local.z, -0.2, "now in front of the eye: %s" % cam_local)
	assert_lt(cam_local.y, 0.0, "below the crosshair")
	assert_almost_eq(cam_local.x, 0.0, 0.05, "between both hands")
	var held_at := item.global_transform
	var out := hands.release_held()
	assert_eq(out, item)
	assert_false(hands.is_holding())
	assert_eq(item.get_parent(), _world, "back under its old parent")
	assert_true(item.global_transform.is_equal_approx(held_at), "let go where it was held")
	assert_null(hands.release_held(), "nothing left to release")
	# One-handed grip, then a held item is swapped out cleanly.
	hands.hold(item, FirstPersonHands.HOLD_RIGHT)
	assert_true(hands.hand_node(&"right").is_ancestor_of(item))
	var other := Node3D.new()
	_world.add_child(other)
	hands.hold(other, FirstPersonHands.HOLD_LEFT)
	assert_eq(item.get_parent(), _world, "the first item was released")
	assert_true(hands.hand_node(&"left").is_ancestor_of(other))


func test_hands_press_reaches_the_target_and_fires_contact() -> void:
	var player := await _spawn()
	var hands := player.hands
	hands.set_process(false)
	var target: Vector3 = player.camera_rig.camera.global_transform * Vector3(0.12, -0.2, -0.6)
	for i in 30:
		hands.advance(1.0 / 60.0)
	var rest := hands.fingertip_position()
	var events: Array = []
	hands.anim_event.connect(func(anim: StringName, ev: StringName) -> void: events.append([anim, ev]))
	assert_true(hands.play(&"press", target, true))
	assert_false(hands.play(&"moonwalk"), "unknown animations are ignored")
	for i in 45:
		hands.advance(1.0 / 60.0)
	assert_lt(hands.fingertip_position().distance_to(target), 0.03, "the fingertip is on the button")
	assert_eq(events, [[&"press", &"contact"]])
	assert_true(hands.is_playing(&"press"), "sustained on the button")
	hands.release_sustain()
	var done: Array = []
	hands.anim_finished.connect(func(anim: StringName) -> void: done.append(anim))
	for i in 30:
		hands.advance(1.0 / 60.0)
	assert_eq(done, [&"press"])
	assert_false(hands.is_playing())
	for i in 30:
		hands.advance(1.0 / 60.0)
	assert_lt(hands.fingertip_position().distance_to(rest), 0.04, "the hand came back to rest (give or take its idle sway)")
	assert_gt(rest.distance_to(target), 0.1)


func test_hands_animations_all_play_and_finish() -> void:
	var player := await _spawn()
	var hands := player.hands
	hands.set_process(false)
	var done: Array = []
	hands.anim_finished.connect(func(anim: StringName) -> void: done.append(anim))
	for anim: StringName in FirstPersonHands.ANIMS:
		var start := hands.hand_node(&"right").transform
		var start_l := hands.hand_node(&"left").transform
		assert_true(hands.play(anim), String(anim))
		var moved := false
		for i in int(float(FirstPersonHands.ANIM_SECONDS[anim]) * 60.0) + 3:
			hands.advance(1.0 / 60.0)
			if not hands.hand_node(&"right").transform.is_equal_approx(start) or not hands.hand_node(&"left").transform.is_equal_approx(start_l):
				moved = true
		assert_true(moved, "%s moves a hand" % anim)
	assert_eq(done.size(), FirstPersonHands.ANIMS.size(), "every animation finishes: %s" % [done])


func test_shake_and_flail_move_the_hands() -> void:
	var player := await _spawn()
	var hands := player.hands
	hands.set_process(false)
	var item := Node3D.new()
	_world.add_child(item)
	hands.hold(item)
	for i in 20:
		hands.advance(1.0 / 60.0)
	hands.shake(true)
	var xs: Array = []
	for i in 20:
		hands.advance(1.0 / 60.0)
		xs.append(hands.hand_node(&"right").position.y)
	assert_true(hands.is_shaking())
	assert_gt(xs.max() - xs.min(), 0.01, "cupped hands rattle")
	hands.release_held()
	assert_false(hands.is_shaking(), "letting go stops the shake")


# --- ID card -----------------------------------------------------------------------

func test_tab_raises_the_id_card_and_the_wheel_cycles() -> void:
	var player := await _spawn()
	var toggles: Array = []
	var cycles: Array = []
	player.id_card_toggled.connect(func(raised: bool) -> void: toggles.append(raised))
	player.id_cycle.connect(func(dir: int) -> void: cycles.append(dir))
	player.set_id_card({"name": "Rex Gambino", "birthday": "Jan 1, 1980", "home_state": "Ohio", "grade": 1}, {}, 0, 2)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	player._unhandled_input(wheel)
	assert_eq(cycles.size(), 0, "the wheel does nothing with the card down")
	await _hold(&"show_id", 2)
	assert_true(player.is_id_raised())
	assert_eq(toggles, [true])
	assert_true(player.hands.is_card_raised())
	assert_eq(player.hands.id_card(), player.id_card)
	assert_true(player.id_card.visible)
	player._unhandled_input(wheel)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_WHEEL_UP
	up.pressed = true
	player._unhandled_input(up)
	assert_eq(cycles, [1, -1], "wheel down = next, up = previous")
	assert_eq(player.hands.current_anim(), &"flip_card")
	await _hold(&"show_id", 2)
	assert_false(player.is_id_raised())
	assert_eq(toggles, [true, false])
	await _frames(30)
	assert_false(player.id_card.visible, "hidden once lowered")


func test_id_card_shows_the_id() -> void:
	var card := IdCard3D.new()
	_world.add_child(card)
	card.set_id({"name": "Dizzy McGillicuddy", "birthday": "Mar 3, 1987", "home_state": "Nevada", "grade": HR.IdGrade.SOLID, "cap": 25000, "banked_under": 9800},
		{"hat": "none", "top": "hawaiian_shirt"})
	card.set_index(1, 3)
	var f := card.get_fields()
	assert_eq(f["name"], "Dizzy McGillicuddy")
	assert_eq(f["born"], "Mar 3, 1987")
	assert_eq(f["from"], "Nevada")
	assert_eq(f["grade"], "SOLID")
	assert_eq(f["banked"], "BANKED $9.8K / CAP $25K")
	assert_almost_eq(float(f["ratio"]), 9800.0 / 25000.0, 0.001)
	assert_eq(f["status"], IdCard3D.STATUS_NONE)
	assert_eq(f["index"], "2/3")
	card.set_id({"name": "Lou", "grade": HR.IdGrade.CHEAP, "banked_under": 7000, "flagged": true})
	assert_eq(card.get_fields()["status"], IdCard3D.STATUS_FLAGGED)
	assert_eq(card.get_fields()["banked"], "BANKED $7K / CAP $6K", "a missing cap comes from the grade")
	assert_almost_eq(float(card.get_fields()["ratio"]), 1.0, 0.001)
	card.set_id({"name": "Lou", "flagged": true, "burned": true})
	assert_eq(card.get_fields()["status"], IdCard3D.STATUS_BURNED, "burned wins")
	card.set_index(0, 1)
	assert_eq(card.get_fields()["index"], "")
	assert_eq(IdCard3D.short_chips(950), "$950")
	assert_eq(IdCard3D.short_chips(1500000), "$1.5M")
	assert_eq(IdCard3D.short_chips(-2000), "-$2K")


# --- Bodies and sync ------------------------------------------------------------------

func test_own_body_is_hidden_from_own_camera_and_remote_bodies_show() -> void:
	var me := await _spawn()
	var mate := await _spawn(false, Vector3(2, 0, -2))
	var cull := me.camera_rig.camera.cull_mask
	assert_eq(cull & FpTuning.SELF_BODY_LAYER, 0, "my camera skips the self-body layer")
	var mine := _meshes(me.model)
	assert_gt(mine.size(), 5)
	for vi: VisualInstance3D in mine:
		assert_eq(vi.layers, FpTuning.SELF_BODY_LAYER, "my body: %s" % vi.name)
	for vi: VisualInstance3D in _meshes(mate.model):
		assert_ne(vi.layers & cull, 0, "a teammate's body is visible: %s" % vi.name)
	assert_true(mate.model.visible)
	assert_null(mate.camera_rig)
	assert_null(mate.hands)
	# A new outfit rebuilds meshes: they stay on the self-body layer.
	var outfit := Outfit.new()
	outfit.set_piece(HR.OutfitSlot.HAT, &"top_hat")
	me.set_outfit(outfit)
	await _frames(1)
	for vi: VisualInstance3D in _meshes(me.model):
		assert_eq(vi.layers, FpTuning.SELF_BODY_LAYER, "after re-dressing: %s" % vi.name)


func test_puppet_eases_to_synced_facing_and_pitch() -> void:
	var player := await _spawn(false, Vector3(3, 0, 0))
	player.make_puppet(Vector3(3, 0, 0))
	player.net_position = Vector3(3, 0, -1)
	player.net_facing = 1.0
	player.net_pitch = -0.5
	await _frames(30)
	assert_almost_eq(player.facing, 1.0, 0.01)
	assert_almost_eq(player.look_pitch, -0.5, 0.01)
	assert_lt(player.global_position.distance_to(Vector3(3, 0, -1)), 0.05)


func test_local_player_publishes_its_look() -> void:
	var player := await _spawn()
	player.enable_net_sync()
	var sync := NetSync.of(player)
	assert_not_null(sync)
	var props := sync.replication_config.get_properties()
	assert_has(props, NodePath(".:net_pitch"))
	assert_has(props, NodePath(".:net_facing"))
	player.camera_rig.add_look(0.4, 0.3)
	await _frames(2)
	assert_almost_eq(player.net_facing, player.camera_rig.yaw, 0.001)
	assert_almost_eq(player.net_pitch, 0.3, 0.001)


func test_first_person_input_actions() -> void:
	InputSetup.ensure_actions()
	assert_true(_has_mouse(&"primary", MOUSE_BUTTON_LEFT), "LMB presses")
	assert_true(_has_mouse(&"id_next", MOUSE_BUTTON_WHEEL_DOWN))
	assert_true(_has_mouse(&"id_prev", MOUSE_BUTTON_WHEEL_UP))
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	assert_true(tab.is_action(&"show_id"), "Tab raises the ID")
	for action: StringName in [&"primary", &"show_id", &"id_next", &"id_prev", &"interact", &"ui_quiz_1", &"ui_quiz_2", &"ui_quiz_3"]:
		assert_has(InputSetup.ACTIONS, action)


func _has_mouse(action: StringName, button: MouseButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
			return true
	return false


func _meshes(root: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if root is VisualInstance3D:
		out.append(root)
	for child: Node in root.get_children():
		out.append_array(_meshes(child))
	return out
