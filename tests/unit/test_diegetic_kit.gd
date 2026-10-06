extends TestCase
## The diegetic machine kit: pressables, keys, keypad, bet console, screen,
## monitor, lever, chips, cards, dice and floating labels.

var mains: Array = []
var actions: Array = []
var bets: Array = []


func before_each() -> void:
	mains.clear()
	actions.clear()
	bets.clear()


func _console(min_bet: int = 10, max_bet: int = 500, pocket: int = 1000) -> BetConsole3D:
	var c := BetConsole3D.new()
	c.setup("PLAY")
	c.set_limits(min_bet, max_bet, pocket)
	c.main_pressed.connect(func(bet: int, throw: bool, pid: int) -> void: mains.append([bet, throw, pid]))
	c.action_pressed.connect(func(id: StringName, pid: int) -> void: actions.append([id, pid]))
	c.bet_changed.connect(func(bet: int) -> void: bets.append(bet))
	return c


func _type(c: BetConsole3D, keys: Array, pid: int = 1) -> void:
	for k: Variant in keys:
		c.press_key(StringName(str(k)), pid)


func _wait(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame


func _wait_until(cond: Callable, limit: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(limit * 1000.0)
	while not bool(cond.call()) and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return bool(cond.call())


func _free(node: Node) -> void:
	if node.is_inside_tree():
		node.queue_free()
		await tree.process_frame
	else:
		node.free()


# --- Helpers ------------------------------------------------------------------

func test_money_text() -> void:
	assert_eq(DiegeticKit.money(0), "$0")
	assert_eq(DiegeticKit.money(1250), "$1,250")
	assert_eq(DiegeticKit.money(14000000000), "$14,000,000,000")
	assert_eq(DiegeticKit.money(-75), "-$75")
	assert_eq(DiegeticKit.money_short(950), "$950")
	assert_eq(DiegeticKit.money_short(12500), "$12.5K")
	assert_eq(DiegeticKit.money_short(3200000), "$3.2M")
	assert_eq(DiegeticKit.money_short(610800), "$611K")
	assert_eq(DiegeticKit.reason_text(&"not_enough"), "Not enough chips")
	assert_eq(DiegeticKit.reason_text(&"something_new"), "Something New")


# --- Pressable and keys ---------------------------------------------------------

func test_pressable_contract() -> void:
	var p := Pressable.new()
	assert_eq(p.collision_layer, 16)
	assert_eq(p.collision_mask, 0)
	assert_true(p.shape is CollisionShape3D and p.shape.get_parent() == p)
	for m: StringName in [&"get_hint", &"set_hovered", &"press", &"hold_complete"]:
		assert_true(p.has_method(m), String(m))
	for s: StringName in [&"pressed", &"held", &"hover_changed"]:
		assert_true(p.has_signal(s), String(s))
	assert_eq(p.hold_seconds, 0.0)
	var got: Array = []
	p.pressed.connect(func(pid: int) -> void: got.append(["press", pid]))
	p.held.connect(func(pid: int) -> void: got.append(["hold", pid]))
	p.press(4)
	p.hold_complete(2)
	p.enabled = false
	p.press(4)
	p.hold_complete(4)
	assert_eq(got, [["press", 4], ["hold", 2]])
	p.free()


func test_key_hover_glow_and_disabled() -> void:
	var k := KeyButton3D.new()
	k.setup("PLAY", DiegeticKit.KEY_GREEN, Vector3(0.15, 0.04, 0.16), &"main")
	assert_eq(k.id, &"main")
	assert_eq(k.get_hint(), "[LMB] PLAY")
	var hovers: Array = []
	k.hover_changed.connect(func(h: bool) -> void: hovers.append(h))
	k.set_hovered(true)
	assert_true(HoverGlow.is_on(k.cap), "hover lights the outline")
	k.set_hovered(false)
	assert_false(HoverGlow.is_on(k.cap))
	assert_eq(hovers, [true, false])
	k.enabled = false
	k.set_hovered(true)
	assert_false(k.hovered, "a disabled key never hovers")
	k.press(1)
	assert_eq(k.press_count, 0)
	k.enabled = true
	k.press(1)
	assert_eq(k.press_count, 1)
	k.set_lit(true)
	assert_true(k.lit)
	k.free()


func test_key_press_travel_rebounds() -> void:
	var k := KeyButton3D.new()
	k.setup("7", DiegeticKit.KEY_CREAM)
	tree.root.add_child(k)
	k.press(1)
	assert_true(k.is_animating())
	# Step the tween by hand so a slow frame can't skip the bottom.
	k._tween.custom_step(KeyButton3D.PRESS_SECONDS)
	assert_lt(k.cap.position.y, -0.002, "the cap sinks")
	assert_almost_eq(k.cap.position.y, -k.travel, 0.0005)
	k._tween.custom_step(1.0)
	assert_false(k.is_animating())
	assert_almost_eq(k.cap.position.y, 0.0, 0.0001, "and comes back")
	await _free(k)


func test_keypad_layout_and_signal() -> void:
	var kp := Keypad3D.new()
	kp.setup()
	assert_eq(kp.keys.size(), 12)
	for t: String in ["0", "1", "5", "9", "C", "000"]:
		assert_not_null(kp.get_key(t), t)
	assert_lt(kp.get_key("1").position.z, kp.get_key("0").position.z, "1 2 3 on the far row")
	assert_lt(kp.get_key("1").position.x, kp.get_key("3").position.x)
	var got: Array = []
	kp.key.connect(func(t: String) -> void: got.append(t))
	var by: Array = []
	kp.key_by.connect(func(t: String, pid: int) -> void: by.append([t, pid]))
	kp.press_key("4", 2)
	kp.press_key("000", 2)
	assert_eq(got, ["4", "000"])
	assert_eq(by, [["4", 2], ["000", 2]])
	kp.free()


# --- Bet console ------------------------------------------------------------------

func test_console_starts_at_min_and_types_a_bet() -> void:
	var c := _console()
	assert_eq(c.bet, 10, "starts at the minimum")
	_type(c, [2, 5])
	assert_eq(c.bet, 25, "the first digit starts a new number")
	_type(c, [0])
	assert_eq(c.bet, 250)
	assert_eq(c.get_bet(), 250)
	assert_eq(c.screen.get_line(1), "$250")
	assert_true(c.screen.get_line(0).contains("Min $10") and c.screen.get_line(0).contains("Max $500"))
	assert_eq(c.screen.get_line(2), "Pocket $1,000")
	assert_eq(bets.back(), 250)
	c.free()


func test_console_clear_and_thousands() -> void:
	var c := _console(10, 100000, 50000)
	_type(c, ["C"])
	assert_eq(c.bet, 0)
	assert_eq(c.screen.get_line(1), "$0")
	assert_eq(c.get_bet(), 10, "an empty bet plays the minimum")
	_type(c, ["000"])
	assert_eq(c.bet, 0, "000 on nothing stays 0")
	_type(c, [3, "000"])
	assert_eq(c.bet, 3000)
	_type(c, ["000"])
	assert_eq(c.bet, 50000, "multiplying past the pocket stops at the pocket")
	_type(c, ["C", 7])
	assert_eq(c.bet, 7)
	c.free()


func test_console_clamps_to_max_and_pocket() -> void:
	var c := _console(10, 500, 1000)
	_type(c, [9, 9, 9])
	assert_eq(c.bet, 500, "typing past the max snaps to it")
	c.set_limits(10, 500, 120)
	assert_eq(c.bet, 120, "a smaller pocket re-clamps the bet")
	assert_eq(c.cap(), 120)
	_type(c, ["C", 5])
	assert_eq(c.bet, 5)
	assert_eq(c.get_bet(), 10, "below the min plays the min")
	c.set_limits(10, 500, 4)
	assert_eq(c.cap(), 10, "the cap never drops under the min")
	c.set_bet(99999)
	assert_eq(c.bet, 10)
	c.free()


func test_console_quick_keys() -> void:
	var c := _console(10, 500, 1000)
	_type(c, [4, 0, 0])
	c.press_key(&"half", 1)
	assert_eq(c.bet, 200)
	c.press_key(&"double", 1)
	assert_eq(c.bet, 400)
	c.press_key(&"double", 1)
	assert_eq(c.bet, 500, "×2 stops at the cap")
	c.press_key(&"min", 1)
	assert_eq(c.bet, 10)
	c.press_key(&"half", 1)
	assert_eq(c.bet, 10, "½ never goes under the min")
	c.press_key(&"max", 1)
	assert_eq(c.bet, 500)
	_type(c, [3])
	assert_eq(c.bet, 3, "after a quick key typing starts fresh")
	for id: StringName in [&"min", &"half", &"double", &"max", &"throw", &"main"]:
		assert_not_null(c.get_key(id), String(id))
	assert_eq(c.get_key(&"half").legend, "½")
	assert_eq(c.get_key(&"double").legend, "×2")
	c.free()


func test_console_throw_toggle() -> void:
	var c := _console()
	assert_false(c.throw_armed)
	c.press_key(&"throw", 1)
	assert_true(c.throw_armed)
	assert_true(c.throw_key.lit, "lit while armed")
	assert_true(c.message_line().contains("THROW"))
	c.press_key(&"throw", 1)
	assert_false(c.throw_armed)
	assert_false(c.throw_key.lit)
	c.press_key(&"throw", 1)
	c.press_key(&"main", 3)
	assert_eq(mains, [[10, true, 3]])
	assert_false(c.throw_armed, "a play disarms it")
	assert_false(c.throw_key.lit)
	c.press_key(&"main", 3)
	assert_eq(mains[1], [10, false, 3])
	c.free()


func test_console_main_and_action_signals() -> void:
	var c := _console(10, 500, 1000)
	_type(c, [5])
	c.press_key(&"main", 7)
	assert_eq(mains, [[10, false, 7]], "a sub-min bet is raised to the min")
	assert_eq(c.bet, 10, "and shown")
	var k := c.add_action_key(&"cash_out", "CASH\nOUT", DiegeticKit.KEY_YELLOW)
	assert_true(k is KeyButton3D)
	var w := c.get_size().x
	c.add_action_key(&"hit", "HIT", DiegeticKit.KEY_RED)
	assert_gt(c.get_size().x, w, "action keys widen the console")
	c.press_key(&"cash_out", 7)
	c.press_key(&"hit", 2)
	assert_eq(actions, [[&"cash_out", 7], [&"hit", 2]])
	assert_true(c.key_ids().has(&"cash_out"))
	c.remove_action_key(&"hit")
	assert_null(c.get_key(&"hit"))
	c.set_main_label("SPIN")
	assert_eq(c.main_key.legend, "SPIN")
	c.free()


func test_locked_console_ignores_presses() -> void:
	var c := _console()
	var pressed: Array = []
	c.key_pressed.connect(func(id: StringName, pid: int) -> void: pressed.append(id))
	c.set_locked(true)
	_type(c, [7, 7, "C", "000"])
	for id: StringName in [&"max", &"throw", &"main"]:
		c.press_key(id, 1)
	assert_eq(c.bet, 10)
	assert_false(c.throw_armed)
	assert_true(mains.is_empty())
	assert_true(pressed.is_empty())
	c.set_locked(false)
	_type(c, [7])
	assert_eq(c.bet, 7)
	assert_eq(pressed, [&"7"])
	c.free()


func test_gate_refuses_with_message() -> void:
	var c := _console()
	c.gate = func(pid: int) -> String: return "" if pid == 1 else "Occupied"
	var refusals: Array = []
	c.refused.connect(func(pid: int, msg: String) -> void: refusals.append([pid, msg]))
	c.press_key(&"main", 2)
	_type(c, [5], 2)
	assert_true(mains.is_empty())
	assert_eq(c.bet, 10)
	assert_eq(refusals, [[2, "Occupied"], [2, "Occupied"]])
	assert_eq(c.message_line(), "Occupied")
	c.press_key(&"main", 1)
	assert_eq(mains.size(), 1)
	c.free()


func test_console_messages_and_status() -> void:
	var c := _console()
	c.set_status("Step up to play")
	assert_eq(c.message_line(), "Step up to play")
	c.show_message("WIN +$50", DiegeticKit.TEXT_WIN)
	assert_eq(c.message_line(), "WIN +$50")
	c.clear_message()
	assert_eq(c.message_line(), "Step up to play")
	c.free()


func test_console_aim_points_in_tree() -> void:
	var c := _console()
	c.position = Vector3(2, 0.8, -1)
	tree.root.add_child(c)
	var main_pt := c.get_aim_point(&"main")
	var one_pt := c.get_aim_point(&"1")
	assert_gt(main_pt.x, one_pt.x, "the main key is right of the keypad")
	assert_gt(main_pt.y, 0.8, "keys are on top of the console")
	assert_between(main_pt.distance_to(c.global_position), 0.05, 1.2)
	c.add_stand(0.8)
	assert_not_null(c.stand)
	await _free(c)


# --- Screen, monitor, label --------------------------------------------------------

func test_screen_lines() -> void:
	var s := Screen3D.new()
	s.setup(Vector2(0.5, 0.3), 3)
	assert_eq(s.lines.size(), 3)
	s.set_lines(["Lose on:", {"text": "2 / 3 / 12", "color": DiegeticKit.TEXT_LOSE, "size": 0.05}])
	assert_eq(s.get_line(0), "Lose on:")
	assert_eq(s.get_line(1), "2 / 3 / 12")
	assert_eq(s.get_line(2), "")
	assert_eq(s.get_line_color(1), DiegeticKit.TEXT_LOSE)
	s.set_line(2, "7 / 11", DiegeticKit.TEXT_WIN)
	assert_eq(s.get_lines(), PackedStringArray(["Lose on:", "2 / 3 / 12", "7 / 11"]))
	assert_gt(s.lines[0].position.y, s.lines[2].position.y, "lines stack top down")
	s.set_line(0, "A VERY VERY LONG LINE THAT CANNOT FIT ON THIS GLASS AT ALL")
	var w := DiegeticKit.text_width(s.lines[0], s.get_line(0), s.lines[0].pixel_size)
	assert_lte(w, s.size.x + 0.001, "long text shrinks to fit")
	s.set_line(9, "ignored")
	s.flash(Color.RED)
	s.free()


func test_monitor_and_floating_label() -> void:
	var m := MonitorOnStand.new()
	m.setup(Vector2(0.6, 0.36), 1.1, 2)
	assert_not_null(m.screen)
	assert_eq(m.screen.line_count, 2)
	m.set_lines(["2x", "$610.8K"])
	assert_eq(m.screen.get_line(1), "$610.8K")
	tree.root.add_child(m)
	assert_almost_eq(m.screen.global_position.y, 1.1, 0.05)
	await _free(m)
	var f := FloatingLabel.new()
	f.setup("Slots")
	assert_eq(f.get_text(), "SLOTS")
	f.set_text("roulette")
	assert_eq(f.get_text(), "ROULETTE")
	f.set_text("a very long game name indeed")
	assert_lte(f.get_width(), f.max_width + 0.001, "long names shrink to fit")
	f.set_subtitle("CLOSED", DiegeticKit.TEXT_LOSE)
	assert_true(f.subtitle.visible)
	f.free()


# --- Lever, chips ------------------------------------------------------------------

func test_lever_pulls_and_springs_back() -> void:
	var lever := Lever3D.new()
	lever.setup()
	assert_eq(lever.hand_anim, &"pull")
	assert_eq(lever.collision_layer, 16)
	tree.root.add_child(lever)
	var pulled: Array = []
	lever.pulled.connect(func(pid: int) -> void: pulled.append(pid))
	lever.press(3)
	var bottomed := await _wait_until(func() -> bool: return not pulled.is_empty(), 1.0)
	assert_true(bottomed)
	assert_eq(pulled, [3])
	assert_gt(lever.pull_amount(), 0.9, "at the bottom when pulled fires")
	var back := await _wait_until(func() -> bool: return not lever.is_animating(), 2.0)
	assert_true(back)
	assert_almost_eq(lever.pull_amount(), 0.0, 0.01)
	await _free(lever)


func test_chip_stack_breakdown() -> void:
	assert_eq(ChipStack3D.breakdown(1260), [[1000, 1], [100, 2], [25, 2], [5, 2]])
	assert_eq(ChipStack3D.breakdown(0), [])
	var s := ChipStack3D.new()
	s.setup(1260)
	assert_eq(s.chip_count(), 7)
	assert_eq(s.column_count(), 4)
	s.set_amount(4)
	assert_eq(s.chip_count(), 4)
	assert_eq(s.column_count(), 1)
	s.set_amount(99999999)
	assert_lte(s.chip_count(), s.max_chips)
	s.set_amount(0)
	assert_eq(s.chip_count(), 0)
	assert_eq(s.top_height(), 0.0)
	assert_ne(ChipStack3D.color_for(5), ChipStack3D.color_for(100))
	s.free()


# --- Cards ------------------------------------------------------------------------

func test_card_faces_and_ranks() -> void:
	assert_eq(Card3D.rank_text(14), "A")
	assert_eq(Card3D.rank_text(11), "J")
	assert_eq(Card3D.rank_text(7), "7")
	assert_eq(Card3D.blackjack_rank(10, 2), "Q")
	assert_eq(Card3D.blackjack_rank(11), "A")
	assert_true(Card3D.is_red("♥") and Card3D.is_red("D"))
	assert_false(Card3D.is_red("♣") or Card3D.is_red("spades"))
	assert_eq(Card3D.suit_for(9, 3), Card3D.suit_for(9, 3), "suits are stable")
	for s: String in Card3D.SUITS:
		assert_gte(Card3D.suit_polygon(s).size(), 4, s)
	var c := Card3D.new()
	c.setup("K", "♦", true)
	assert_eq(c.rank, "K")
	assert_eq(c.suit, "♦")
	assert_true(c.is_showing_face())
	c.set_face_up(false)
	assert_false(c.is_showing_face())
	c.free()


func test_card_flip_and_deal_complete() -> void:
	var c := Card3D.new()
	c.setup("10", "♠", false)
	tree.root.add_child(c)
	var events: Array = []
	c.flipped.connect(func(up: bool) -> void: events.append(["flip", up]))
	c.dealt.connect(func() -> void: events.append(["dealt"]))
	var target := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.5, 0.9, -0.3))
	c.deal_to(target, 0.25)
	c.flip(true, 0.2)
	assert_true(c.is_animating())
	var done := await _wait_until(func() -> bool: return events.size() >= 2, 2.0)
	assert_true(done, "both tweens finish")
	assert_true(events.has(["flip", true]) and events.has(["dealt"]))
	assert_true(c.global_position.is_equal_approx(target.origin), "lands on the target")
	assert_true(c.global_basis.is_equal_approx(target.basis))
	assert_true(c.face_up)
	assert_true(c.is_showing_face())
	c.flip(false, 0.2)
	c.finish()
	assert_false(c.is_showing_face(), "finish() snaps to the end")
	await _free(c)


# --- Dice -----------------------------------------------------------------------------

func test_dice_face_basis() -> void:
	for v in range(1, 7):
		assert_eq(Dice3D.face_up_of(Dice3D.face_up_basis(v, 0.7)), v, "face_up_basis(%d)" % v)
	var d := Dice3D.new()
	d.setup()
	assert_true(d.freeze, "starts frozen (tween-driven)")
	d.physics_mode = true
	assert_false(d.freeze)
	d.physics_mode = false
	for v in range(1, 7):
		d.set_face_up(v)
		assert_eq(d.up_face(), v)
	d.free()


func test_dice_settle_to_every_value_from_random_orientations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var d := Dice3D.new()
	d.setup()
	for trial in 12:
		for v in range(1, 7):
			var from := Basis(Quaternion.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)))
			d.basis = from
			var settled := Dice3D.settled_basis(from, v)
			assert_eq(Dice3D.face_up_of(settled), v)
			var up_n: Vector3 = settled * (Dice3D.FACE_NORMALS[v] as Vector3)
			assert_gt(up_n.dot(Vector3.UP), 0.9999, "exactly up")
			# Keeps its heading: the correction turns about a level axis.
			var delta := (settled * from.inverse()).get_rotation_quaternion()
			if absf(delta.get_angle()) > 0.001:
				assert_almost_eq(delta.get_axis().y, 0.0, 0.001, "level axis")
			d.settle_to(v, 0.0)
			assert_eq(d.up_face(), v)
	d.free()


func test_dice_settle_and_roll_tweens() -> void:
	var d := Dice3D.new()
	d.setup()
	d.position = Vector3(0, 0.05, 0)
	tree.root.add_child(d)
	var got: Array = []
	d.settled.connect(func(v: int) -> void: got.append(v))
	d.global_basis = Basis(Quaternion.from_euler(Vector3(0.7, 1.3, 2.1)))
	d.settle_to(5, 0.2)
	var ok := await _wait_until(func() -> bool: return got.size() == 1, 2.0)
	assert_true(ok)
	assert_eq(got, [5])
	assert_eq(d.up_face(), 5)
	assert_almost_eq(d.global_position.y, 0.05, 0.001, "lands back down")
	var target := Vector3(0.8, 0.05, -0.4)
	d.roll_to(2, target, 0.4)
	ok = await _wait_until(func() -> bool: return got.size() == 2, 2.0)
	assert_true(ok)
	assert_eq(got[1], 2)
	assert_eq(d.up_face(), 2)
	assert_true(d.global_position.is_equal_approx(target))
	await _free(d)


func test_dice_physics_mode_falls_then_settles() -> void:
	var floor := Primitives.static_box(Vector3(4, 0.2, 4), Color.DIM_GRAY)
	floor.position = Vector3(20, -0.1, 0)
	tree.root.add_child(floor)
	var d := Dice3D.new()
	d.setup(0.1)
	d.position = Vector3(20, 0.6, 0)
	tree.root.add_child(d)
	await tree.physics_frame
	d.throw(Vector3(0.02, 0.0, 0.0), Vector3(0.001, 0.002, 0.0))
	assert_true(d.physics_mode)
	for i in 60:
		await tree.physics_frame
	assert_lt(d.global_position.y, 0.4, "it falls as a rigid body")
	assert_gt(d.global_position.y, 0.0, "and lands on the floor")
	d.settle_to(4, 0.0)
	assert_false(d.physics_mode, "settling freezes it again")
	assert_true(d.freeze)
	assert_eq(d.up_face(), 4)
	await _free(d)
	await _free(floor)
