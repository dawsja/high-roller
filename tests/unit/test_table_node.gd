extends TestCase

const FAST := 0.3


func _table(game_type: int, id: StringName = &"t1", rung: int = 3) -> TableNode:
	var t := TableNode.new()
	t.setup(id, game_type, &"pit_a", rung)
	return t


func _in_tree(game_type: int, id: StringName = &"t1", xf: Transform3D = Transform3D.IDENTITY) -> TableNode:
	var t := _table(game_type, id)
	t.transform = xf
	tree.root.add_child(t)
	return t


func _drop(node: Node) -> void:
	node.queue_free()
	await tree.process_frame


func _state(game_type: int) -> TableState:
	return TableState.new(&"t1", game_type, &"pit_a")


func _rng(value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = value
	return r


## Plays a result in real time and waits (up to `limit` s) for result_shown.
func _play(t: TableNode, result: Dictionary, seconds: float = FAST, limit: float = 3.0) -> Array:
	var got: Array = []
	var cb := func(id: StringName) -> void: got.append(id)
	t.result_shown.connect(cb)
	t.play_result(result, seconds)
	var deadline: int = Time.get_ticks_msec() + int(limit * 1000.0)
	while got.is_empty() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	t.result_shown.disconnect(cb)
	return got


func _wait(seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame


func _prop_front_z(t: TableNode) -> float:
	var front := -INF
	for c: Node in t.body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var cs := c as CollisionShape3D
			var size: Vector3 = (cs.shape as BoxShape3D).size
			if cs.position.z < 0.0 and cs.position.y + size.y * 0.5 < 1.3 and absf(cs.position.x) > 0.5:
				continue  # dealer / host standing area
			front = maxf(front, cs.position.z + size.z * 0.5)
	return front


# --- Building ---------------------------------------------------------------------

func test_each_game_type_builds() -> void:
	for gt: int in TableGames.all_types():
		var t := _table(gt, StringName("table_%d" % gt))
		assert_not_null(t.prop, "prop for %d" % gt)
		assert_not_null(t.interactable)
		assert_eq(t.interactable.kind, &"table")
		assert_eq(t.interactable.data.get("table_id"), StringName("table_%d" % gt))
		assert_eq(t.interactable.prompt, "Play %s" % TableGames.display_name(gt, 3))
		assert_true(t.interactable.enabled)
		assert_eq(t.body.collision_layer, 1, "table collides on the world layer")
		assert_eq(t.body.collision_mask, 0)
		assert_gt(t.body.get_child_count(), 0, "table has collision shapes")
		assert_eq(t.name_label.text, TableGames.display_name(gt, 3))
		match gt:
			HR.GameType.SLOTS:
				assert_null(t.dealer, "slot machines have no dealer")
			HR.GameType.BIG_WHEEL:
				assert_not_null(t.dealer, "the wheel has a host")
				assert_eq(t.dealer.uniform, &"", "the host wears an outfit")
			_:
				assert_not_null(t.dealer)
				assert_eq(t.dealer.uniform, &"dealer")
		t.free()


func test_reskinned_rungs_use_reskin_names() -> void:
	var t := _table(HR.GameType.DICE, &"d", Tuning.BOTTOM_RUNG)
	assert_eq(t.display_name, "Bingo")
	assert_eq(t.interactable.prompt, "Play Bingo")
	t.free()


func test_seat_is_in_front_of_the_prop_facing_it() -> void:
	var xf := Transform3D(Basis(Vector3.UP, 0.7), Vector3(4.0, 0.0, -3.0))
	for gt: int in TableGames.all_types():
		var t := _in_tree(gt, StringName("s_%d" % gt), xf)
		var seat: Transform3D = t.seat_transform()
		var local: Transform3D = t.global_transform.affine_inverse() * seat
		assert_almost_eq(local.origin.y, 0.0, 0.001, "seat on the floor (%d)" % gt)
		assert_gt(local.origin.z, _prop_front_z(t), "seat in front of the prop (%d)" % gt)
		assert_lt(local.origin.z, 2.0, "seat inside the 4 m table slot (%d)" % gt)
		var forward: Vector3 = -local.basis.z
		assert_almost_eq(forward.z, -1.0, 0.001, "seated player faces the table (%d)" % gt)
		var world_forward: Vector3 = -seat.basis.z
		var to_table: Vector3 = t.global_position - seat.origin
		assert_gt(world_forward.dot(to_table), 0.0, "world seat faces the table (%d)" % gt)
		var it_local: Vector3 = t.interactable.position
		assert_lt(Vector2(it_local.x, it_local.z).distance_to(Vector2(local.origin.x, local.origin.z)), Tuning.TABLE_INTERACT_RADIUS + 0.8, "interactable reachable from the seat (%d)" % gt)
		if t.dealer != null:
			assert_lt(t.dealer.position.z, local.origin.z - 0.5, "dealer on the far side (%d)" % gt)
			var dealer_forward: Vector3 = -t.dealer.basis.z
			var to_seat: Vector3 = (local.origin - t.dealer.position).normalized()
			assert_gt(dealer_forward.dot(to_seat), 0.7, "dealer faces the seat (%d)" % gt)
		await _drop(t)


func test_dice_table_has_extra_stools() -> void:
	var t := _table(HR.GameType.DICE)
	assert_eq(t.seat_count(), 3)
	var a: Vector3 = t.seat_transform(0).origin
	var b: Vector3 = t.seat_transform(1).origin
	var c: Vector3 = t.seat_transform(2).origin
	assert_gt(absf(a.x - b.x), 0.5)
	assert_gt(absf(a.x - c.x), 0.5)
	assert_almost_eq(a.z, b.z, 0.001)
	assert_eq(_table_seat_clamped(t), t.seat_transform(2).origin)
	t.free()


func _table_seat_clamped(t: TableNode) -> Vector3:
	return t.seat_transform(99).origin


func test_default_duration_is_a_share_of_round_time() -> void:
	for gt: int in TableGames.all_types():
		var t := _table(gt)
		var round_s: float = float(TableGames.def(gt)["round_seconds"])
		assert_almost_eq(t.result_seconds(), round_s * Tuning.TABLE_RESULT_SHARE, 0.001)
		assert_almost_eq(t.result_seconds(99.0), round_s, 0.001, "never longer than a round")
		assert_almost_eq(t.result_seconds(0.01), Tuning.TABLE_RESULT_MIN_SECONDS, 0.001)
		t.free()


# --- Results ----------------------------------------------------------------------

func test_slots_result_spins_to_the_reels() -> void:
	var t := _in_tree(HR.GameType.SLOTS)
	var ts := _state(HR.GameType.SLOTS)
	var rng := _rng(11)
	for i in 3:
		var r: Dictionary = GameResolver.resolve(ts, 1, 50, {"throw": i == 2}, rng, 500).to_dict()
		var got: Array = await _play(t, r)
		assert_eq(got, [&"t1"], "result_shown once")
		var shown: Dictionary = t.shown_state()
		var reels: Array = r["detail"]["reels"]
		assert_eq(shown["reels"], reels, "reels stop on the result")
		assert_false(t.is_animating())
	await _drop(t)


func test_slots_jackpot_flashes_loud() -> void:
	var t := _in_tree(HR.GameType.SLOTS)
	var r := BetResult.new()
	r.table_id = &"t1"
	r.game_type = HR.GameType.SLOTS
	r.bet = 50
	r.won = true
	r.jackpot = true
	r.loud = true
	r.payout = 1050
	r.net = 1000
	r.detail = {"reels": ["seven", "seven", "seven"]}
	t.play_result(r.to_dict(), FAST)
	await _wait(FAST * Tuning.TABLE_REVEAL_SHARE + 0.12)
	assert_gt(t.get_flash_energy(), 0.0, "loud flash is on")
	assert_true(t.get_pop_text().contains("JACKPOT"), t.get_pop_text())
	t.finish_animations()
	assert_eq(t.shown_state()["reels"], ["seven", "seven", "seven"])
	await _drop(t)


func test_big_wheel_lands_on_the_segment() -> void:
	var t := _in_tree(HR.GameType.BIG_WHEEL)
	var ts := _state(HR.GameType.BIG_WHEEL)
	var rng := _rng(5)
	for i in 3:
		var r: Dictionary = GameResolver.resolve(ts, 1, 50, {"throw": i == 1}, rng, 500).to_dict()
		var got: Array = await _play(t, r)
		assert_eq(got.size(), 1)
		var shown: Dictionary = t.shown_state()
		assert_eq(shown["segment"], r["detail"]["segment"], "pointer on the rolled segment")
		assert_eq(shown["label"], r["detail"]["label"])
		assert_eq(GameResolver.wheel_segment_wins(int(shown["segment"])), bool(r["won"]))
	await _drop(t)


func test_dice_show_the_rolled_faces() -> void:
	var t := _in_tree(HR.GameType.DICE)
	var ts := _state(HR.GameType.DICE)
	var rng := _rng(21)
	for call: String in ["high", "low"]:
		var r: Dictionary = GameResolver.resolve(ts, 1, 50, {"call": call}, rng, 500).to_dict()
		var got: Array = await _play(t, r)
		assert_eq(got.size(), 1)
		assert_eq(t.shown_state()["dice"], r["detail"]["dice"], "dice settle on the rolled faces")
	await _drop(t)


func test_shared_dice_roll_plays_once_for_the_crew() -> void:
	var t := _in_tree(HR.GameType.DICE)
	var ts := _state(HR.GameType.DICE)
	var results: Dictionary = GameResolver.resolve_shared_roll(ts, [{"pid": 1, "bet": 50}, {"pid": 2, "bet": 50}], _rng(3), 500)
	var count: Array = []
	var cb := func(_id: StringName) -> void: count.append(1)
	t.result_shown.connect(cb)
	t.play_result((results[1] as BetResult).to_dict(), FAST)
	t.play_result((results[2] as BetResult).to_dict(), FAST)
	await _wait(FAST + 0.4)
	assert_eq(count.size(), 1, "one roll, one animation")
	assert_eq(t.shown_state()["dice"], (results[1] as BetResult).detail["dice"])
	await _drop(t)


func test_roulette_ball_lands_on_the_number() -> void:
	var t := _in_tree(HR.GameType.ROULETTE)
	var ts := _state(HR.GameType.ROULETTE)
	var rng := _rng(8)
	var choices: Array[Dictionary] = [{"kind": "color", "color": "red"}, {"kind": "number", "number": 17}, {"kind": "color", "color": "black", "throw": true}]
	for choice: Dictionary in choices:
		var r: Dictionary = GameResolver.resolve(ts, 1, 50, choice, rng, 500).to_dict()
		var got: Array = await _play(t, r)
		assert_eq(got.size(), 1)
		var shown: Dictionary = t.shown_state()
		assert_eq(shown["number"], r["detail"]["number"], "ball in the right pocket")
		assert_eq(shown["tote"], str(r["detail"]["number"]), "tote board shows the number")
		assert_almost_eq(float(shown["ball_radius"]), TableProps.RouletteProp.POCKET_R, 0.001, "ball dropped into the pocket ring")
	await _drop(t)


func test_high_low_guesses_and_cash_out() -> void:
	var t := _in_tree(HR.GameType.HIGH_LOW)
	var ts := _state(HR.GameType.HIGH_LOW)
	var run := HighLowRun.new(ts, 1, 50, _rng(4), 500)
	t.show_hand({"kind": &"high_low", "bet": 50, "pot": run.pot, "card": run.current_card, "streak": 0, "finished": false})
	t.finish_animations()
	assert_true(str(t.shown_state()["card"]).begins_with(TableProps.rank_text(run.current_card)), "show_hand puts up the card")
	assert_false(bool(t.shown_state()["next_face_up"]))
	var g: BetResult = run.guess(true)
	var r: Dictionary = g.to_dict()
	var got: Array = await _play(t, r)
	assert_eq(got.size(), 1)
	var shown: Dictionary = t.shown_state()
	assert_true(str(shown["next"]).begins_with(TableProps.rank_text(int(r["detail"]["next_card"]))), "next card revealed: %s" % shown)
	assert_true(str(shown["card"]).begins_with(TableProps.rank_text(int(r["detail"]["card"]))))
	if not run.finished:
		var c: Dictionary = run.cash_out().to_dict()
		got = await _play(t, c)
		assert_eq(got.size(), 1)
		assert_true(str(t.shown_state()["card"]).begins_with(TableProps.rank_text(int(c["detail"]["current_card"]))))
	# A losing (thrown) guess also animates and reports.
	var lose_run := HighLowRun.new(ts, 1, 50, _rng(9), 500)
	var lost: Dictionary = lose_run.guess(false, true).to_dict()
	got = await _play(t, lost)
	assert_eq(got.size(), 1)
	assert_true(str(t.shown_state()["next"]).begins_with(TableProps.rank_text(int(lost["detail"]["next_card"]))))
	await _drop(t)


func test_hand_during_a_result_waits_for_it() -> void:
	var t := _in_tree(HR.GameType.HIGH_LOW)
	var ts := _state(HR.GameType.HIGH_LOW)
	var run: HighLowRun
	var g: Dictionary = {}
	for n in 50:
		run = HighLowRun.new(ts, 1, 50, _rng(n), 500)
		g = run.guess(true).to_dict()
		if bool(g["won"]):
			break
	assert_true(bool(g["won"]), "found a winning first guess")
	t.play_result(g, FAST)
	t.show_hand({"kind": &"high_low", "bet": 50, "pot": run.pot, "card": run.current_card, "streak": run.streak, "finished": false})
	await tree.process_frame
	assert_true(str(t.shown_state()["card"]).begins_with(TableProps.rank_text(int(g["detail"]["card"]))), "the guessed card stays up while revealing")
	t.finish_animations()
	assert_true(str(t.shown_state()["card"]).begins_with(TableProps.rank_text(run.current_card)), "then the new hand shows")
	assert_false(bool(t.shown_state()["next_face_up"]))
	await _drop(t)


func test_blackjack_hole_card_stays_down_until_stand() -> void:
	var t := _in_tree(HR.GameType.BLACKJACK)
	var ts := _state(HR.GameType.BLACKJACK)
	var bj := BlackjackRound.new(ts, 1, 50, _rng(2), 500)
	var state := {"kind": &"blackjack", "bet": 50, "player_cards": bj.player_cards.duplicate(), "dealer_cards": bj.dealer_cards.duplicate(), "player_total": bj.player_total(), "finished": false}
	t.show_hand(state)
	await _wait(Tuning.TABLE_DEAL_SECONDS * 4.0 + 0.2)
	var shown: Dictionary = t.shown_state()
	assert_eq((shown["player"] as Array).size(), 2)
	assert_eq(shown["player_up"], 2)
	assert_eq((shown["dealer"] as Array).size(), 2, "up card and hole card")
	assert_eq(shown["dealer_up"], 1, "hole card face down")
	assert_eq(shown["player_total"], str(bj.player_total()))
	if bj.player_total() < 17:
		bj.hit()
		if not bj.finished:
			t.show_hand({"kind": &"blackjack", "bet": 50, "player_cards": bj.player_cards.duplicate(), "dealer_cards": [bj.dealer_cards[0]], "player_total": bj.player_total(), "finished": false})
			t.finish_animations()
			assert_eq((t.shown_state()["player"] as Array).size(), bj.player_cards.size(), "hit card dealt")
			assert_eq(t.shown_state()["dealer_up"], 1)
	var r: Dictionary = (bj.result if bj.finished else bj.stand()).to_dict()
	var got: Array = await _play(t, r, 0.5)
	assert_eq(got.size(), 1)
	shown = t.shown_state()
	assert_eq((shown["player"] as Array).size(), (r["detail"]["player_cards"] as Array).size())
	assert_eq((shown["dealer"] as Array).size(), (r["detail"]["dealer_cards"] as Array).size())
	assert_eq(shown["dealer_up"], (r["detail"]["dealer_cards"] as Array).size(), "hole card revealed")
	assert_eq(shown["player_total"], str(r["detail"]["player_total"]))
	assert_eq(shown["dealer_total"], str(r["detail"]["dealer_total"]))
	await _drop(t)


func test_blackjack_bust_and_fallback_results() -> void:
	var t := _in_tree(HR.GameType.BLACKJACK)
	var ts := _state(HR.GameType.BLACKJACK)
	var bj := BlackjackRound.new(ts, 1, 50, _rng(6), 500)
	var forfeit: Dictionary = bj.forfeit().to_dict()
	var got: Array = await _play(t, forfeit)
	assert_eq(got.size(), 1)
	assert_eq((t.shown_state()["player"] as Array).size(), (forfeit["detail"]["player_cards"] as Array).size())
	assert_true(t.get_pop_text().contains("BUST"), t.get_pop_text())
	# GameResolver's one-shot blackjack (stands on the deal) on a fresh table.
	var one: Dictionary = GameResolver.resolve(ts, 1, 50, {}, _rng(7), 500).to_dict()
	got = await _play(t, one)
	assert_eq(got.size(), 1)
	assert_eq(t.shown_state()["dealer_up"], (one["detail"]["dealer_cards"] as Array).size())
	await _drop(t)


func test_high_low_one_shot_fallback() -> void:
	var t := _in_tree(HR.GameType.HIGH_LOW)
	var r: Dictionary = GameResolver.resolve(_state(HR.GameType.HIGH_LOW), 1, 50, {"higher": true}, _rng(12), 500).to_dict()
	var got: Array = await _play(t, r)
	assert_eq(got.size(), 1)
	assert_true(str(t.shown_state()["next"]).begins_with(TableProps.rank_text(int(r["detail"]["next_card"]))))
	await _drop(t)


func test_win_and_loss_captions() -> void:
	var t := _in_tree(HR.GameType.ROULETTE)
	var ts := _state(HR.GameType.ROULETTE)
	var win: Dictionary = GameResolver.resolve(ts, 1, 50, {"kind": "color", "color": "red"}, _rng(1), 500).to_dict()
	var lose: Dictionary = GameResolver.resolve(ts, 1, 50, {"kind": "color", "color": "red", "throw": true}, _rng(1), 500).to_dict()
	assert_true(bool(win["won"]))
	t.play_result(win, FAST)
	await _wait(FAST * Tuning.TABLE_REVEAL_SHARE + 0.1)
	assert_true(t.get_pop_text().contains("WIN +%d" % int(win["net"])), t.get_pop_text())
	t.finish_animations()
	t.play_result(lose, FAST)
	await _wait(FAST * Tuning.TABLE_REVEAL_SHARE + 0.1)
	assert_true(t.get_pop_text().contains("LOSE"), t.get_pop_text())
	await _drop(t)


func test_a_new_result_snaps_the_previous_one() -> void:
	var t := _in_tree(HR.GameType.BIG_WHEEL)
	var ts := _state(HR.GameType.BIG_WHEEL)
	var rng := _rng(14)
	var a: Dictionary = GameResolver.resolve(ts, 1, 50, {}, rng, 500).to_dict()
	var b: Dictionary = GameResolver.resolve(ts, 1, 50, {"throw": true}, rng, 500).to_dict()
	var count: Array = []
	var cb := func(_id: StringName) -> void: count.append(1)
	t.result_shown.connect(cb)
	t.play_result(a, 1.0)
	await tree.process_frame
	t.play_result(b, FAST)
	assert_eq(count.size(), 1, "interrupted result still reports")
	await _wait(FAST + 0.3)
	assert_eq(count.size(), 2)
	assert_eq(t.shown_state()["segment"], b["detail"]["segment"])
	await _drop(t)


func test_out_of_tree_result_snaps_and_emits() -> void:
	var t := _table(HR.GameType.DICE)
	var r: Dictionary = GameResolver.resolve(_state(HR.GameType.DICE), 1, 50, {}, _rng(2), 500).to_dict()
	var got: Array = []
	t.result_shown.connect(func(id: StringName) -> void: got.append(id))
	t.play_result(r)
	assert_eq(got, [&"t1"])
	assert_eq(t.shown_state()["dice"], r["detail"]["dice"])
	t.free()


func test_freeing_mid_animation_is_safe() -> void:
	var t := _in_tree(HR.GameType.ROULETTE)
	t.play_result(GameResolver.resolve(_state(HR.GameType.ROULETTE), 1, 50, {}, _rng(3), 500).to_dict(), 1.0)
	t.dealer_swap()
	await tree.process_frame
	t.queue_free()
	await _wait(0.2)
	assert_false(is_instance_valid(t))


# --- Closed / dealer swap -------------------------------------------------------------

func test_set_closed_toggles_the_interactable() -> void:
	var t := _in_tree(HR.GameType.BLACKJACK)
	assert_true(t.interactable.enabled)
	t.set_closed(true)
	assert_true(t.closed)
	assert_false(t.interactable.enabled)
	assert_true(t._closed_sign.visible, "CLOSED sign up")
	await tree.process_frame
	assert_false(t.interactable.monitorable, "players can't find a closed table")
	t.set_closed(false)
	assert_true(t.interactable.enabled)
	assert_false(t._closed_sign.visible)
	await _drop(t)


func test_dealer_swap_brings_in_a_new_dealer() -> void:
	for gt: int in [HR.GameType.BLACKJACK, HR.GameType.BIG_WHEEL]:
		var t := _in_tree(gt)
		var old: CharacterModel = t.dealer
		t.dealer_swap()
		var fresh: CharacterModel = t.dealer
		assert_ne(fresh, old, "a new dealer")
		assert_ne(fresh.appearance_seed, old.appearance_seed, "looks different")
		assert_true(fresh.is_highlighted(), "tinted while cold")
		assert_eq(t.get_pop_text(), "NEW DEALER")
		await _wait(Tuning.TABLE_DEALER_SWAP_SECONDS * 0.3)
		assert_eq(old.pose, &"walk", "old dealer walks off")
		await _wait(Tuning.TABLE_DEALER_SWAP_SECONDS * 0.75 + 0.1)
		assert_false(is_instance_valid(old), "old dealer gone")
		assert_true(fresh.visible)
		assert_almost_eq(fresh.position.distance_to(t.prop.dealer_spot), 0.0, 0.01, "new dealer at the post")
		assert_almost_eq(wrapf(fresh.rotation.y - t.prop.dealer_yaw, -PI, PI), 0.0, 0.01, "facing the seat")
		assert_eq(fresh.pose, &"idle")
		# A second swap straight away snaps the first.
		t.dealer_swap()
		t.dealer_swap()
		t.finish_animations()
		assert_almost_eq(t.dealer.position.distance_to(t.prop.dealer_spot), 0.0, 0.01)
		await _drop(t)
	var slots := _in_tree(HR.GameType.SLOTS)
	slots.dealer_swap()
	assert_null(slots.dealer)
	assert_eq(slots.get_pop_text(), "COOLED")
	await _drop(slots)
