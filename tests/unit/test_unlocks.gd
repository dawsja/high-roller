extends TestCase
## Cosmetic unlocks in the simulation: locked catalog pieces never show up in
## random outfits, patrons or laundry carts; the gift shop only sells a locked
## piece to the player who unlocked it (RunState.set_unlocks); ID name packs
## join the names on new fake IDs.


func _sim(rung: int = 3, crew: Dictionary = {1: "Ace"}, unlocks: Dictionary = {}) -> FloorSim:
	var run := RunState.new(rung)
	for pid: int in unlocks:
		run.set_unlocks(pid, unlocks[pid].get("pieces", []), unlocks[pid].get("name_packs", []))
	var sim := FloorSim.new(run, 11)
	for pid: int in crew:
		sim.add_player(pid, str(crew[pid]))
		sim.player(pid).wallet.add(5000)
	return sim


func _all_names(packs: Array) -> Dictionary:
	var out := {}
	for pack: StringName in packs:
		var data: Dictionary = IdGenerator.NAME_PACKS[pack]
		for n: Variant in data["first"]:
			out[str(n)] = "first"
		for n: Variant in data["last"]:
			out[str(n)] = "last"
	return out


# --- Catalog ----------------------------------------------------------------------------

func test_locked_pieces_are_in_the_catalog_but_not_civilian_lists() -> void:
	var locked := OutfitCatalog.locked_pieces()
	assert_gte(locked.size(), 12)
	for id: StringName in locked:
		var slot := OutfitCatalog.slot_of(id)
		assert_true(OutfitCatalog.has_piece(id), String(id))
		assert_true(OutfitCatalog.fits(id, slot), String(id))
		assert_gt(OutfitCatalog.piece_price(id), 0, "%s has a gift-shop price" % id)
		assert_false(OutfitCatalog.pieces_for(slot).has(id), "%s not in the civilian list" % id)
		assert_has(OutfitCatalog.pieces_for(slot, true), id)
		assert_true(OutfitCatalog.is_locked(id))
		assert_false(OutfitCatalog.is_locked(id, [id]))
		assert_false(OutfitCatalog.is_locked(id, [String(id)]), "string ids from JSON count too")
		assert_false(OutfitCatalog.is_for_sale(id), "locked: not for sale")
		assert_true(OutfitCatalog.is_for_sale(id, [id]), "unlocked: for sale")
	assert_false(OutfitCatalog.is_unlockable(&"hawaiian_shirt"))
	assert_false(OutfitCatalog.is_locked(&"hawaiian_shirt"))
	assert_false(OutfitCatalog.is_unlockable(&"staff_vest"))


func test_random_outfits_never_hand_out_locked_pieces() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in 3000:
		var o := OutfitCatalog.random_outfit(rng)
		for slot: int in OutfitCatalog.all_slots():
			assert_false(OutfitCatalog.is_unlockable(o.get_piece(slot)), "draw %d slot %d: %s" % [i, slot, o.get_piece(slot)])
			if OutfitCatalog.is_unlockable(o.get_piece(slot)):
				return
		var piece := OutfitCatalog.random_piece(rng.randi_range(0, HR.OUTFIT_SLOT_COUNT - 1), rng)
		assert_false(OutfitCatalog.is_unlockable(piece), String(piece))


func test_new_players_patrons_and_laundry_never_get_locked_pieces() -> void:
	var sim := _sim(3, {1: "Ace", 2: "Bea", 3: "Cy"}, {1: {"pieces": OutfitCatalog.locked_pieces()}})
	for pid: int in sim.player_ids():
		var ps := sim.player(pid)
		for o: Outfit in [ps.outfit] + ps.stash:
			for slot: int in OutfitCatalog.all_slots():
				assert_false(OutfitCatalog.is_unlockable(o.get_piece(slot)), "player %d starts in civilian pieces" % pid)
	var ps1 := sim.player(1)
	sim.enter_zone(1, HR.ZoneType.STAFF_ONLY, &"laundry")
	for i in 60:
		ps1.steal_cooldown = 0.0
		var res: Dictionary = sim.steal_outfit_piece(1)
		assert_true(bool(res["ok"]), str(res))
		if not bool(res["uniform"]):
			assert_false(OutfitCatalog.is_unlockable(StringName(str(res["piece"]))), "laundry cart gave %s" % res["piece"])


func test_shop_pieces_with_and_without_unlocks() -> void:
	for slot: int in OutfitCatalog.all_slots():
		var base := OutfitCatalog.shop_pieces(slot)
		for id: StringName in base:
			assert_false(OutfitCatalog.is_unlockable(id), "%s is locked but listed" % id)
		var everything := OutfitCatalog.shop_pieces(slot, [], true)
		var locked_here := OutfitCatalog.locked_pieces().filter(func(id: StringName) -> bool: return OutfitCatalog.slot_of(id) == slot)
		assert_eq(everything.size(), base.size() + locked_here.size(), "slot %d lists the locked ones on request" % slot)
		if locked_here.is_empty():
			continue
		var with_one := OutfitCatalog.shop_pieces(slot, [locked_here[0]])
		assert_eq(with_one.size(), base.size() + 1)
		assert_has(with_one, locked_here[0])


# --- Gift shop (FloorSim) -------------------------------------------------------------

func test_gift_shop_sells_a_locked_piece_only_to_who_unlocked_it() -> void:
	var sim := _sim(3, {1: "Ace", 2: "Bea"}, {1: {"pieces": [&"viking_helmet", "fuzzy_dice"]}})
	for pid: int in [1, 2]:
		sim.enter_zone(pid, HR.ZoneType.GIFT_SHOP, &"gift_shop")
	var res: Dictionary = sim.buy_outfit_piece(2, HR.OutfitSlot.HAT, &"viking_helmet")
	assert_false(bool(res["ok"]))
	assert_eq(res["reason"], FloorSim.BAD_PIECE, "Bea hasn't unlocked it")
	res = sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"propeller_beanie")
	assert_eq(res["reason"], FloorSim.BAD_PIECE, "Ace didn't unlock the beanie")
	var pocket := sim.player(1).wallet.pocket
	res = sim.buy_outfit_piece(1, HR.OutfitSlot.HAT, &"viking_helmet")
	assert_true(bool(res["ok"]), str(res))
	assert_eq(sim.player(1).stash.back().get_piece(HR.OutfitSlot.HAT), &"viking_helmet")
	assert_eq(sim.player(1).wallet.pocket, pocket - OutfitCatalog.piece_price(&"viking_helmet"))
	res = sim.buy_outfit_piece(1, HR.OutfitSlot.ACCESSORY, &"fuzzy_dice")
	assert_true(bool(res["ok"]), "string ids from a profile work: %s" % res)
	res = sim.buy_outfit_piece(1, HR.OutfitSlot.TOP, &"viking_helmet")
	assert_eq(res["reason"], FloorSim.BAD_PIECE, "still has to fit the slot")
	var hat := &"bucket_hat" if sim.player(2).outfit.get_piece(HR.OutfitSlot.HAT) != &"bucket_hat" else &"top_hat"
	res = sim.buy_outfit_piece(2, HR.OutfitSlot.HAT, hat)
	assert_true(bool(res["ok"]), "civilian pieces are for everyone")
	# Wearing it: the bought piece is owned now (restroom mix and match).
	sim.enter_zone(1, HR.ZoneType.RESTROOM, &"restroom")
	var look := sim.player(1).outfit.copy()
	look.set_piece(HR.OutfitSlot.HAT, &"viking_helmet")
	res = sim.change_outfit(1, look)
	assert_true(bool(res["ok"]), str(res))
	assert_eq(sim.player(1).outfit.get_piece(HR.OutfitSlot.HAT), &"viking_helmet")


func test_unlocks_carry_to_the_next_visit() -> void:
	var sim := _sim(3, {1: "Ace"}, {1: {"pieces": [&"tartan_kilt"]}})
	var next := FloorSim.new(sim.run, 12, sim.players.values())
	next.enter_zone(1, HR.ZoneType.GIFT_SHOP, &"gift_shop")
	assert_true(bool(next.buy_outfit_piece(1, HR.OutfitSlot.BOTTOM, &"tartan_kilt")["ok"]), "the run keeps them")


func test_run_state_set_unlocks_keeps_only_real_unlocks() -> void:
	var run := RunState.new()
	assert_true(run.unlocked_pieces(1).is_empty())
	assert_true(run.name_packs(1).is_empty())
	run.set_unlocks(1, ["viking_helmet", &"viking_helmet", "hawaiian_shirt", "staff_vest", "nonsense", 5], ["space_age", "space_age", "nope"])
	assert_eq(run.unlocked_pieces(1), [&"viking_helmet"] as Array[StringName], "only locked catalog pieces, once")
	assert_eq(run.name_packs(1), [&"space_age"] as Array[StringName])
	assert_true(run.unlocked_pieces(2).is_empty(), "per player")
	run.set_unlocks(1, [], [])
	assert_true(run.unlocked_pieces(1).is_empty(), "replaced, not added")
	run.unlocked_pieces(1).append(&"x")
	assert_true(run.unlocked_pieces(1).is_empty(), "a copy")


# --- Name packs --------------------------------------------------------------------------

func test_name_packs_are_one_word_and_new() -> void:
	var seen := {}
	for n: String in IdGenerator.FIRST_NAMES + IdGenerator.LAST_NAMES:
		seen[n] = true
	for pack: StringName in IdGenerator.NAME_PACKS:
		var data: Dictionary = IdGenerator.NAME_PACKS[pack]
		assert_ne(IdGenerator.name_pack_name(pack), "")
		assert_gte((data["first"] as Array).size(), 8)
		assert_gte((data["last"] as Array).size(), 8)
		for n: Variant in (data["first"] as Array) + (data["last"] as Array):
			assert_false(str(n).contains(" "), "%s is one word" % n)
			assert_false(seen.has(str(n)), "%s is already used" % n)
			seen[str(n)] = true
	assert_eq(IdGenerator.first_names().size(), IdGenerator.FIRST_NAMES.size())
	assert_eq(IdGenerator.first_names([&"space_age", "high_seas", "bogus"]).size(), IdGenerator.FIRST_NAMES.size() + 20)
	assert_ne(IdGenerator.name_pack_sample(&"space_age"), "")


func test_no_packs_gives_the_old_names_and_rng_sequence() -> void:
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 77
	b.seed = 77
	for i in 50:
		var x := IdGenerator.generate(HR.IdGrade.CHEAP, a)
		var y := IdGenerator.generate(HR.IdGrade.CHEAP, b, [], [])
		assert_eq(x.name, y.name)
		var parts := IdGenerator.split_name(x.name)
		assert_has(IdGenerator.FIRST_NAMES, parts[0])
		assert_has(IdGenerator.LAST_NAMES, parts[1])
	var c := RandomNumberGenerator.new()
	c.seed = 5
	IdGenerator.generate(HR.IdGrade.SOLID, c, [], [&"space_age"])
	var d := RandomNumberGenerator.new()
	d.seed = 5
	IdGenerator.generate(HR.IdGrade.SOLID, d)
	assert_eq(c.randi(), d.randi(), "a pack doesn't shift the rng stream")


func test_name_packs_show_up_on_generated_ids() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pack_words := _all_names([&"silver_screen"])
	var hits := 0
	for i in 200:
		var id := IdGenerator.generate(HR.IdGrade.CHEAP, rng, [], [&"silver_screen"])
		var parts := IdGenerator.split_name(id.name)
		assert_eq(parts.size(), 2, id.name)
		if pack_words.has(parts[0]) or pack_words.has(parts[1]):
			hits += 1
	assert_gt(hits, 40, "pack names are drawn")
	assert_lt(hits, 200, "base names too")


func test_floor_sim_prints_ids_with_the_players_name_packs() -> void:
	var packs := [&"high_seas", &"silver_screen", &"space_age"]
	var sim := _sim(3, {1: "Ace", 2: "Bea"}, {1: {"name_packs": packs}})
	var words := _all_names(packs)
	var hits := {1: 0, 2: 0}
	for pid: int in [1, 2]:
		sim.player(pid).wallet.add(100_000)
		sim.enter_zone(pid, HR.ZoneType.FORGER, sim.forger.location())
	for i in 40:
		for pid: int in [1, 2]:
			var res: Dictionary = sim.buy_id(pid, HR.IdGrade.CHEAP)
			assert_true(bool(res["ok"]), str(res))
			var parts := IdGenerator.split_name(str(res["id"]["name"]))
			if words.has(parts[0]) or words.has(parts[1]):
				hits[pid] += 1
	assert_gt(hits[1], 5, "Ace's cards use her packs")
	assert_eq(hits[2], 0, "Bea has none")
