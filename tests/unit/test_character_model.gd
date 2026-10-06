extends TestCase

const NO_COLOR := Color(0, 0, 0, 0)


func _outfit(hat: StringName, glasses: StringName, top: StringName, bottom: StringName, accessory: StringName) -> Outfit:
	var o := Outfit.new()
	o.set_piece(HR.OutfitSlot.HAT, hat)
	o.set_piece(HR.OutfitSlot.GLASSES, glasses)
	o.set_piece(HR.OutfitSlot.TOP, top)
	o.set_piece(HR.OutfitSlot.BOTTOM, bottom)
	o.set_piece(HR.OutfitSlot.ACCESSORY, accessory)
	return o


func _signature(model: CharacterModel, slot: int) -> String:
	var sizes: PackedStringArray = []
	for mi: MeshInstance3D in model.get_slot_parts(slot):
		sizes.append("%s%s" % [mi.mesh.get_class(), mi.mesh.get_aabb().size.snapped(Vector3.ONE * 0.001)])
	sizes.sort()
	return ",".join(sizes)


func test_default_model_is_person_sized_and_faces_minus_z() -> void:
	var model := CharacterModel.new()
	var box := model.get_body_aabb()
	assert_almost_eq(box.position.y, 0.0, 0.03, "feet at origin")
	assert_almost_eq(box.end.y, CharacterModel.HEAD_TOP, 0.12, "about 1.8 m tall")
	assert_almost_eq(model.get_head_top(), 1.8, 0.1)
	assert_lt(box.position.z, -box.end.z, "nose and toes stick out toward -Z")
	assert_eq(model.pose, &"idle")
	model.free()


func test_apply_outfit_colors_each_slot() -> void:
	var model := CharacterModel.new()
	var a := _outfit(&"top_hat", &"aviator_shades", &"hawaiian_shirt", &"blue_jeans", &"gold_chain")
	var b := _outfit(&"lucky_ball_cap", &"heart_shades", &"lucky_sweater", &"golf_plaid_pants", &"feather_boa")
	model.apply_outfit(a)
	for slot: int in OutfitCatalog.all_slots():
		assert_eq(model.get_slot_color(slot), OutfitCatalog.piece_color(a.get_piece(slot)), "outfit a slot %d" % slot)
		assert_eq(model.get_slot_piece(slot), a.get_piece(slot))
	model.apply_outfit(b)
	for slot: int in OutfitCatalog.all_slots():
		assert_eq(model.get_slot_color(slot), OutfitCatalog.piece_color(b.get_piece(slot)), "outfit b slot %d" % slot)
		assert_ne(model.get_slot_color(slot), OutfitCatalog.piece_color(a.get_piece(slot)), "slot %d changed" % slot)
	assert_true(model.outfit.equals(b))
	model.free()


func test_none_pieces_render_nothing() -> void:
	var model := CharacterModel.new()
	model.apply_outfit(_outfit(&"top_hat", &"nerd_frames", &"plain_tee", &"cargo_shorts", &"bow_tie"))
	model.apply_outfit(_outfit(OutfitCatalog.NONE, OutfitCatalog.NONE, &"plain_tee", &"cargo_shorts", OutfitCatalog.NONE))
	for slot: int in OutfitCatalog.OPTIONAL_SLOTS:
		assert_eq(model.get_slot_parts(slot).size(), 0, "slot %d empty" % slot)
		assert_eq(model.get_slot_color(slot), NO_COLOR)
	assert_almost_eq(model.get_head_top(), 1.8, 0.12, "no hat, head top back down")
	model.free()


func test_every_catalog_piece_builds_its_own_shape() -> void:
	var model := CharacterModel.new()
	for slot: int in OutfitCatalog.all_slots():
		var seen: Dictionary = {}
		for id: StringName in OutfitCatalog.pieces_for(slot, true):
			var o := Outfit.new()
			o.set_piece(slot, id)
			model.apply_outfit(o)
			assert_eq(model.get_slot_piece(slot), id)
			assert_eq(model.get_slot_color(slot), OutfitCatalog.piece_color(id), String(id))
			if OutfitCatalog.is_none(id):
				assert_eq(model.get_slot_parts(slot).size(), 0, String(id))
				continue
			assert_gt(model.get_slot_parts(slot).size(), 0, "%s has a shape" % id)
			var sig := _signature(model, slot)
			assert_false(seen.has(sig), "%s looks the same as %s" % [id, seen.get(sig, "")])
			seen[sig] = id
	model.free()


func test_hats_raise_head_top() -> void:
	var model := CharacterModel.new()
	var bare := model.get_head_top()
	model.apply_outfit(_outfit(&"top_hat", OutfitCatalog.NONE, &"plain_tee", &"blue_jeans", OutfitCatalog.NONE))
	assert_gt(model.get_head_top(), bare + 0.15)
	model.free()


func test_every_uniform_builds() -> void:
	var model := CharacterModel.new()
	var guard_top := 0.0
	for kind: StringName in CharacterModel.UNIFORMS:
		model.apply_uniform(kind)
		assert_eq(model.uniform, kind)
		assert_ne(model.get_slot_color(HR.OutfitSlot.TOP), NO_COLOR, String(kind))
		assert_ne(model.get_slot_color(HR.OutfitSlot.BOTTOM), NO_COLOR, String(kind))
		if kind == &"guard":
			guard_top = model.get_head_top()
			assert_gt(model.get_slot_parts(HR.OutfitSlot.HAT).size(), 0, "guard cap")
			assert_gt(model.get_slot_parts(HR.OutfitSlot.ACCESSORY).size(), 0, "earpiece")
		if kind == &"head_of_security":
			assert_gt(model.get_body_aabb().end.y, CharacterModel.HEAD_TOP * 1.05, "bigger")
			assert_gt(model.get_slot_parts(HR.OutfitSlot.GLASSES).size(), 0, "sunglasses")
		if kind == &"staff":
			assert_true(model.outfit.is_staff_uniform())
			assert_eq(model.get_slot_color(HR.OutfitSlot.TOP), OutfitCatalog.piece_color(&"staff_vest"))
	assert_gt(guard_top, 1.8)
	model.apply_outfit(OutfitCatalog.random_outfit(RandomNumberGenerator.new()))
	assert_eq(model.uniform, &"")
	assert_almost_eq(model.get_body_aabb().end.y, CharacterModel.HEAD_TOP, 0.5, "back to normal size")
	assert_eq(model.get_slot_parts(5).size() + model.get_slot_parts(6).size(), 0, "uniform extras removed")
	model.free()


func test_random_outfits_build() -> void:
	var model := CharacterModel.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		model.appearance_seed = i
		model.apply_outfit(OutfitCatalog.random_outfit(rng))
		model.advance(0.1)
	var box := model.get_body_aabb()
	assert_between(box.end.y, 1.7, 2.3)
	model.free()


func test_every_pose_sets_and_animates() -> void:
	var model := CharacterModel.new()
	for p: StringName in CharacterModel.POSES:
		model.set_pose(p)
		assert_eq(model.pose, p)
		for i in 8:
			model.advance(0.05)
		assert_eq(model.pose, p, "%s still running" % p)
		var box := model.get_body_aabb()
		assert_true(box.size.is_finite() and box.position.is_finite(), String(p))
		model.set_pose(&"idle")
		for i in 10:
			model.advance(0.05)
	model.free()


func test_pose_shapes() -> void:
	var model := CharacterModel.new()
	var heights: Dictionary = {}
	for p: StringName in [&"idle", &"sit", &"celebrate", &"dive", &"tackle", &"carried", &"jump"]:
		model.set_pose(p)
		for i in 15:
			model.advance(1.0 / 30.0)
		var top := 0.0
		for i in 30:
			model.advance(1.0 / 30.0)
			top = maxf(top, model.get_body_aabb().end.y)
		heights[p] = top
		if p == &"carried":
			var box := model.get_body_aabb()
			assert_gt(box.size.z, 1.2, "carried lies along Z")
			assert_lt(box.end.y, 0.7, "nothing far above the carry point")
			assert_gt(box.position.y, -1.0, "limbs dangle, body does not drop")
		if p == &"jump":
			assert_gt(model.get_body_aabb().position.y, 0.25, "legs tucked")
	assert_almost_eq(heights[&"idle"], CharacterModel.HEAD_TOP, 0.1)
	assert_lt(heights[&"sit"], 1.45, "sitting is lower")
	assert_gt(heights[&"celebrate"], 2.0, "arms up")
	assert_lt(heights[&"dive"], 1.0, "dive is horizontal")
	assert_lt(heights[&"tackle"], 1.2, "tackle lunges low")
	model.free()


func test_walk_swing_scales_with_speed() -> void:
	var model := CharacterModel.new()
	model.set_pose(&"walk")
	model.set_move_speed(0.0)
	var still := _max_depth(model)
	model.set_move_speed(Tuning.PLAYER_WALK_SPEED)
	var walking := _max_depth(model)
	model.set_pose(&"run")
	model.set_move_speed(Tuning.PLAYER_RUN_SPEED)
	var running := _max_depth(model)
	assert_lt(still, 0.5, "no swing standing still")
	assert_gt(walking, still + 0.2)
	assert_gt(running, walking)
	model.free()


func _max_depth(model: CharacterModel) -> float:
	var depth := 0.0
	for i in 60:
		model.advance(1.0 / 60.0)
		depth = maxf(depth, model.get_body_aabb().size.z)
	return depth


func test_tumble_recovers_to_idle() -> void:
	var model := CharacterModel.new()
	var finished: Array[StringName] = []
	model.pose_finished.connect(func(p: StringName) -> void: finished.append(p))
	model.set_pose(&"tumble")
	var lowest := 9.0
	var t := 0.0
	while t < Tuning.CHARACTER_TUMBLE_SECONDS + 0.2:
		model.advance(0.05)
		t += 0.05
		lowest = minf(lowest, model.get_body_aabb().end.y)
	assert_lt(lowest, 1.0, "fell over")
	assert_eq(model.pose, &"idle")
	assert_eq(finished, [&"tumble"] as Array[StringName])
	for i in 10:
		model.advance(0.05)
	assert_gt(model.get_body_aabb().end.y, 1.7, "back on its feet")
	model.free()


func test_highlight_toggles() -> void:
	var model := CharacterModel.new()
	assert_false(model.is_highlighted())
	model.set_highlight(Color.YELLOW)
	assert_true(model.is_highlighted())
	assert_eq(model.get_highlight(), Color.YELLOW)
	model.set_highlight(Color(0, 0, 0, 0))
	assert_false(model.is_highlighted())
	model.free()


func test_appearance_seed_is_deterministic() -> void:
	var a := CharacterModel.new()
	var b := CharacterModel.new()
	a.appearance_seed = 42
	b.appearance_seed = 42
	assert_eq(a.skin_color, b.skin_color)
	var tones: Dictionary = {}
	for i in 30:
		a.appearance_seed = i
		tones[a.skin_color] = true
	assert_gte(tones.size(), 4, "seeds vary the skin tone")
	a.free()
	b.free()


func test_short_sleeves_follow_skin_tone() -> void:
	var model := CharacterModel.new()
	model.apply_outfit(_outfit(OutfitCatalog.NONE, OutfitCatalog.NONE, &"plain_tee", &"cargo_shorts", OutfitCatalog.NONE))
	var found_other := false
	for i in 30:
		model.appearance_seed = i
		var forearm: MeshInstance3D = model._forearms[0]
		var shin: MeshInstance3D = model._shins[0]
		assert_eq((forearm.material_override as StandardMaterial3D).albedo_color, model.skin_color)
		assert_eq((shin.material_override as StandardMaterial3D).albedo_color, model.skin_color)
		found_other = found_other or i > 0
	assert_true(found_other)
	model.free()


func test_animates_in_tree() -> void:
	var model := CharacterModel.new()
	tree.root.add_child(model)
	model.set_pose(&"run")
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	assert_eq(model.pose, &"run")
	assert_true(model.get_carry_offset().y > 1.3)
	model.queue_free()
	await tree.process_frame
