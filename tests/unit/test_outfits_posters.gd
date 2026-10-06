extends TestCase
## Outfit, OutfitCatalog, WantedPoster and PosterBoard.

const HAT := HR.OutfitSlot.HAT
const GLASSES := HR.OutfitSlot.GLASSES
const TOP := HR.OutfitSlot.TOP
const BOTTOM := HR.OutfitSlot.BOTTOM
const ACCESSORY := HR.OutfitSlot.ACCESSORY
const NONE := OutfitCatalog.NONE

var printed: Array[WantedPoster] = []
var removed: Array[int] = []
var defaced: Array = []


func before_each() -> void:
	printed.clear()
	removed.clear()
	defaced.clear()


func _rng(seed_value: int = 1234) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


## A look with every slot filled by a real (non-none) civilian piece.
func _look_a() -> Outfit:
	return Outfit.new({
		HAT: &"lucky_ball_cap",
		GLASSES: &"aviator_shades",
		TOP: &"hawaiian_shirt",
		BOTTOM: &"cargo_shorts",
		ACCESSORY: &"gold_chain",
	})


## Differs from _look_a in every slot.
func _look_b() -> Outfit:
	return Outfit.new({
		HAT: &"top_hat",
		GLASSES: &"fancy_monocle",
		TOP: &"rented_tuxedo",
		BOTTOM: &"pressed_slacks",
		ACCESSORY: &"bow_tie",
	})


## _look_a with the given slots swapped to _look_b's pieces.
func _look_a_except(slots: Array) -> Outfit:
	var o := _look_a()
	var b := _look_b()
	for slot: int in slots:
		o.set_piece(slot, b.get_piece(slot))
	return o


func _board() -> PosterBoard:
	var board := PosterBoard.new()
	board.poster_printed.connect(func(p: WantedPoster) -> void: printed.append(p))
	board.poster_removed.connect(func(id: int) -> void: removed.append(id))
	board.poster_defaced.connect(func(id: int, slot: int) -> void: defaced.append([id, slot]))
	return board


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- OutfitCatalog: content -------------------------------------------------

func test_catalog_has_at_least_six_real_pieces_per_slot() -> void:
	for slot: int in OutfitCatalog.all_slots():
		var real := 0
		for id: StringName in OutfitCatalog.pieces_for(slot):
			if not OutfitCatalog.is_none(id):
				real += 1
		assert_gte(real, 6, "slot %s" % OutfitCatalog.slot_name(slot))


func test_all_slots_lists_five_slots_in_order() -> void:
	var slots: Array[int] = OutfitCatalog.all_slots()
	assert_eq(slots.size(), 5)
	assert_eq(slots, [HAT, GLASSES, TOP, BOTTOM, ACCESSORY] as Array[int])


func test_none_only_in_optional_slots() -> void:
	assert_has(OutfitCatalog.pieces_for(HAT), NONE)
	assert_has(OutfitCatalog.pieces_for(GLASSES), NONE)
	assert_has(OutfitCatalog.pieces_for(ACCESSORY), NONE)
	assert_false(OutfitCatalog.pieces_for(TOP).has(NONE), "top is never empty")
	assert_false(OutfitCatalog.pieces_for(BOTTOM).has(NONE), "bottom is never empty")
	assert_eq(OutfitCatalog.pieces_for(HAT)[0], NONE, "none listed first")


func test_pieces_for_invalid_slot_is_empty() -> void:
	assert_eq(OutfitCatalog.pieces_for(-1).size(), 0)
	assert_eq(OutfitCatalog.pieces_for(5).size(), 0)


func test_every_piece_has_name_color_and_matching_slot() -> void:
	for slot: int in OutfitCatalog.all_slots():
		for id: StringName in OutfitCatalog.pieces_for(slot, true):
			assert_true(OutfitCatalog.fits(id, slot), "%s fits %d" % [id, slot])
			assert_true(OutfitCatalog.has_piece(id), String(id))
			assert_ne(OutfitCatalog.piece_name(id), "", String(id))
			if OutfitCatalog.is_none(id):
				continue
			assert_eq(OutfitCatalog.slot_of(id), slot, String(id))
			assert_eq(OutfitCatalog.piece_color(id).a, 1.0, "%s is opaque" % id)


func test_piece_ids_unique_across_slots() -> void:
	var seen := {}
	for slot: int in OutfitCatalog.all_slots():
		for id: StringName in OutfitCatalog.pieces_for(slot, true):
			if id == NONE:
				continue
			assert_false(seen.has(id), "duplicate id %s" % id)
			seen[id] = true
	assert_eq(seen.size(), OutfitCatalog.PIECES.size(), "every catalog piece is reachable from pieces_for")


func test_piece_names_unique() -> void:
	var seen := {}
	for id: StringName in OutfitCatalog.PIECES:
		var n: String = OutfitCatalog.piece_name(id)
		assert_false(seen.has(n), "duplicate name %s" % n)
		seen[n] = true


func test_colors_distinct_within_each_slot() -> void:
	for slot: int in OutfitCatalog.all_slots():
		var ids: Array[StringName] = OutfitCatalog.pieces_for(slot, true)
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				if OutfitCatalog.is_none(ids[i]) or OutfitCatalog.is_none(ids[j]):
					continue
				var d: float = _color_distance(OutfitCatalog.piece_color(ids[i]), OutfitCatalog.piece_color(ids[j]))
				assert_gt(d, 0.08, "%s vs %s too close" % [ids[i], ids[j]])


func test_none_color_is_transparent_and_unknown_is_gray() -> void:
	assert_eq(OutfitCatalog.piece_color(NONE).a, 0.0)
	assert_eq(OutfitCatalog.piece_color(&"no_such_piece"), OutfitCatalog.UNKNOWN_COLOR)


func test_piece_name_values() -> void:
	assert_eq(OutfitCatalog.piece_name(&"hawaiian_shirt"), "Hawaiian Shirt")
	assert_eq(OutfitCatalog.piece_name(NONE), "Nothing")
	assert_eq(OutfitCatalog.piece_name(&"mystery_cape"), "Mystery Cape", "unknown ids fall back to a readable name")


func test_prices_follow_tiers() -> void:
	for id: StringName in OutfitCatalog.PIECES:
		var tier: int = OutfitCatalog.piece_tier(id)
		assert_eq(OutfitCatalog.piece_price(id), int(Tuning.OUTFIT_TIER_PRICES[tier]), String(id))
	assert_eq(OutfitCatalog.piece_price(NONE), 0)
	assert_eq(OutfitCatalog.piece_price(&"no_such_piece"), 0)
	assert_lt(OutfitCatalog.piece_price(&"plain_tee"), OutfitCatalog.piece_price(&"rented_tuxedo"))


func test_shop_sells_civilian_pieces_with_prices() -> void:
	for slot: int in OutfitCatalog.all_slots():
		var shop: Array[StringName] = OutfitCatalog.shop_pieces(slot)
		assert_gte(shop.size(), 6, "slot %d" % slot)
		for id: StringName in shop:
			assert_gt(OutfitCatalog.piece_price(id), 0, String(id))
			assert_true(OutfitCatalog.is_for_sale(id), String(id))
			assert_false(OutfitCatalog.is_staff_piece(id), String(id))
			assert_false(OutfitCatalog.is_none(id), String(id))


func test_staff_pieces_hidden_unless_asked_and_not_for_sale() -> void:
	for slot: int in OutfitCatalog.all_slots():
		for id: StringName in OutfitCatalog.pieces_for(slot):
			assert_false(OutfitCatalog.is_staff_piece(id), "%s in civilian list" % id)
	assert_has(OutfitCatalog.pieces_for(TOP, true), &"staff_vest")
	assert_has(OutfitCatalog.pieces_for(BOTTOM, true), &"staff_slacks")
	assert_has(OutfitCatalog.pieces_for(HAT, true), &"staff_hat")
	assert_true(OutfitCatalog.is_staff_piece(&"staff_vest"))
	assert_false(OutfitCatalog.is_staff_piece(NONE))
	assert_false(OutfitCatalog.is_staff_piece(&"hawaiian_shirt"))
	assert_eq(OutfitCatalog.piece_price(&"staff_vest"), 0)
	assert_false(OutfitCatalog.is_for_sale(&"staff_slacks"))


func test_fits_and_slot_of() -> void:
	assert_true(OutfitCatalog.fits(&"top_hat", HAT))
	assert_false(OutfitCatalog.fits(&"top_hat", TOP))
	assert_true(OutfitCatalog.fits(NONE, GLASSES))
	assert_false(OutfitCatalog.fits(NONE, TOP))
	assert_false(OutfitCatalog.fits(NONE, BOTTOM))
	assert_false(OutfitCatalog.fits(&"no_such_piece", HAT))
	assert_false(OutfitCatalog.fits(&"top_hat", 9))
	assert_eq(OutfitCatalog.slot_of(&"cargo_shorts"), BOTTOM)
	assert_eq(OutfitCatalog.slot_of(NONE), -1)
	assert_eq(OutfitCatalog.slot_of(&"no_such_piece"), -1)


func test_slot_names_and_keys_round_trip() -> void:
	assert_eq(OutfitCatalog.slot_name(HAT), "Hat")
	assert_eq(OutfitCatalog.slot_name(ACCESSORY), "Accessory")
	for slot: int in OutfitCatalog.all_slots():
		assert_eq(OutfitCatalog.slot_from_key(OutfitCatalog.slot_key(slot)), slot)
	assert_eq(OutfitCatalog.slot_from_key("cape"), -1)


# --- OutfitCatalog: generators ----------------------------------------------

func test_staff_uniform_is_staff_and_wearable() -> void:
	var u: Outfit = OutfitCatalog.staff_uniform()
	assert_true(u.is_staff_uniform())
	for slot: int in OutfitCatalog.all_slots():
		assert_true(OutfitCatalog.fits(u.get_piece(slot), slot), "slot %d" % slot)
	assert_eq(u.get_piece(TOP), &"staff_vest")
	assert_eq(u.get_piece(BOTTOM), &"staff_slacks")


func test_staff_uniform_returns_fresh_copies() -> void:
	var u: Outfit = OutfitCatalog.staff_uniform()
	u.set_piece(TOP, &"hawaiian_shirt")
	assert_true(OutfitCatalog.staff_uniform().is_staff_uniform())


func test_random_outfit_never_staff_and_always_valid() -> void:
	var rng := _rng(7)
	for i in 300:
		var o: Outfit = OutfitCatalog.random_outfit(rng)
		assert_false(o.is_staff_uniform(), "outfit %d" % i)
		for slot: int in OutfitCatalog.all_slots():
			var id: StringName = o.get_piece(slot)
			assert_true(OutfitCatalog.fits(id, slot), "%s in slot %d" % [id, slot])
			assert_false(OutfitCatalog.is_staff_piece(id), String(id))


func test_random_outfit_deterministic_by_seed() -> void:
	var a := _rng(99)
	var b := _rng(99)
	for i in 20:
		assert_true(OutfitCatalog.random_outfit(a).equals(OutfitCatalog.random_outfit(b)), "draw %d" % i)


func test_random_outfit_varies_and_uses_every_piece() -> void:
	var rng := _rng(3)
	var seen := {}
	var distinct := {}
	for i in 600:
		var o: Outfit = OutfitCatalog.random_outfit(rng)
		distinct[JSON.stringify(o.to_dict())] = true
		for slot: int in OutfitCatalog.all_slots():
			seen[o.get_piece(slot)] = true
	assert_gt(distinct.size(), 100, "random looks vary")
	for slot: int in OutfitCatalog.all_slots():
		for id: StringName in OutfitCatalog.pieces_for(slot):
			assert_true(seen.has(id), "%s never rolled" % id)


func test_random_piece_respects_exclude() -> void:
	var rng := _rng(11)
	for i in 100:
		var id: StringName = OutfitCatalog.random_piece(TOP, rng, &"plain_tee")
		assert_ne(id, &"plain_tee")
		assert_true(OutfitCatalog.fits(id, TOP))
	assert_eq(OutfitCatalog.random_piece(9, rng), NONE, "invalid slot")


# --- Outfit -----------------------------------------------------------------

func test_new_outfit_has_defaults_in_every_slot() -> void:
	var o := Outfit.new()
	assert_eq(o.pieces.size(), 5)
	for slot: int in OutfitCatalog.all_slots():
		assert_eq(o.get_piece(slot), OutfitCatalog.default_piece(slot))
		assert_true(OutfitCatalog.fits(o.get_piece(slot), slot))
	assert_eq(o.get_piece(HAT), NONE)
	assert_false(OutfitCatalog.is_none(o.get_piece(TOP)))
	assert_false(OutfitCatalog.is_none(o.get_piece(BOTTOM)))
	assert_false(o.is_staff_uniform())


func test_set_and_get_piece() -> void:
	var o := Outfit.new()
	assert_true(o.set_piece(HAT, &"ten_gallon_hat"))
	assert_eq(o.get_piece(HAT), &"ten_gallon_hat")
	assert_true(o.set_piece(HAT, &""), "empty id is allowed")
	assert_eq(o.get_piece(HAT), NONE, "empty id becomes none")
	assert_false(o.set_piece(5, &"top_hat"), "invalid slot rejected")
	assert_false(o.set_piece(-1, &"top_hat"))
	assert_eq(o.pieces.size(), 5, "invalid slots don't add keys")
	assert_eq(o.get_piece(7), NONE, "unknown slot reads as none")


func test_set_piece_accepts_string() -> void:
	var o := Outfit.new()
	o.set_piece(GLASSES, "heart_shades")
	assert_eq(o.get_piece(GLASSES), &"heart_shades")
	assert_eq(typeof(o.get_piece(GLASSES)), TYPE_STRING_NAME)


func test_matches_counts_equal_slots() -> void:
	assert_eq(_look_a().matches(_look_a()), 5)
	assert_eq(_look_a().matches(_look_b()), 0)
	assert_eq(_look_a_except([HAT]).matches(_look_a()), 4)
	assert_eq(_look_a_except([HAT, TOP, ACCESSORY]).matches(_look_a()), 2)
	assert_eq(_look_a().matches(null), 0)


func test_matches_is_symmetric() -> void:
	var x := _look_a_except([GLASSES, BOTTOM])
	assert_eq(x.matches(_look_a()), _look_a().matches(x))


func test_empty_slots_match_each_other() -> void:
	var a := Outfit.new({TOP: &"plain_tee", BOTTOM: &"blue_jeans"})
	var b := Outfit.new({TOP: &"bowling_shirt", BOTTOM: &"track_pants"})
	# Both have no hat, no glasses, no accessory: 3 matching slots.
	assert_eq(a.matches(b), 3)
	assert_true(a.is_recognized_as(b), "three empty slots in common is still a match")


func test_matches_ignores_slots() -> void:
	var a := _look_a()
	assert_eq(a.matches(_look_a(), [HAT]), 4)
	assert_eq(a.matches(_look_a(), [HAT, GLASSES]), 3)
	var typed: Array[int] = [TOP, BOTTOM, ACCESSORY]
	assert_eq(a.matches(_look_a(), typed), 2, "typed Array[int] works too")
	assert_eq(a.matches(_look_a(), [HAT, HAT]), 4, "duplicates count once")


func test_ignore_slots_from_json_still_ignored() -> void:
	# Slot lists that went through JSON come back as floats; Array.has() is
	# type-strict, so 0.0 must still knock out slot 0.
	var parsed: Variant = JSON.parse_string(JSON.stringify([HAT, GLASSES]))
	assert_eq(_look_a().matches(_look_a(), parsed), 3, "JSON floats")
	assert_eq(_look_a().matches(_look_a(), [0.0, 1.0]), 3, "float literals")
	# hat and glasses ignored: top differs, bottom and accessory match = 2 of 3.
	assert_false(_look_a_except([TOP]).is_recognized_as(_look_a(), [0.0, 1.0]))
	assert_eq(_look_a().matches(_look_a(), [0.5, "hat", null]), 5, "non-slot values ignore nothing")


func test_recognized_needs_three_matches() -> void:
	var record := _look_a()
	assert_eq(Tuning.RECOGNIZE_MATCHES, 3)
	assert_true(_look_a().is_recognized_as(record), "5 of 5")
	assert_true(_look_a_except([HAT]).is_recognized_as(record), "4 of 5")
	assert_true(_look_a_except([HAT, GLASSES]).is_recognized_as(record), "3 of 5")
	assert_false(_look_a_except([HAT, GLASSES, TOP]).is_recognized_as(record), "2 of 5")
	assert_false(_look_b().is_recognized_as(record), "0 of 5")
	assert_false(_look_a().is_recognized_as(null))


func test_recognized_bar_stays_with_ignored_slots() -> void:
	var record := _look_a()
	# Ignore the hat: 3 of the remaining 4 still needed.
	assert_true(_look_a_except([GLASSES]).is_recognized_as(record, [HAT]), "3 of 4")
	assert_false(_look_a_except([GLASSES, TOP]).is_recognized_as(record, [HAT]), "2 of 4")
	# A matching ignored slot does not count.
	assert_false(_look_a_except([GLASSES, TOP]).is_recognized_as(record, [HAT, BOTTOM]), "hat and bottom ignored")
	# Ignore three: only two slots left, never recognized.
	assert_false(_look_a().is_recognized_as(record, [HAT, GLASSES, TOP]))


func test_changing_three_pieces_shakes_recognition() -> void:
	var worn := _look_a()
	var record := worn.copy()
	worn.set_piece(HAT, NONE)
	worn.set_piece(TOP, &"lucky_sweater")
	assert_true(worn.is_recognized_as(record), "two changes are not enough")
	worn.set_piece(ACCESSORY, &"feather_boa")
	assert_false(worn.is_recognized_as(record), "three changes are")


func test_copy_is_independent() -> void:
	var a := _look_a()
	var b := a.copy()
	assert_true(a.equals(b))
	assert_ne(a, b)
	b.set_piece(HAT, &"poker_visor")
	assert_eq(a.get_piece(HAT), &"lucky_ball_cap", "original unchanged")
	a.pieces[TOP] = &"biker_jacket"
	assert_eq(b.get_piece(TOP), &"hawaiian_shirt", "copy unchanged")


func test_equals() -> void:
	assert_true(_look_a().equals(_look_a()))
	assert_false(_look_a().equals(_look_a_except([ACCESSORY])))
	assert_false(_look_a().equals(null))


func test_init_takes_initial_pieces() -> void:
	var o := Outfit.new({HAT: &"top_hat", "accessory": "bow_tie"})
	assert_eq(o.get_piece(HAT), &"top_hat")
	assert_eq(o.get_piece(ACCESSORY), &"bow_tie")
	assert_eq(o.get_piece(TOP), OutfitCatalog.default_piece(TOP), "unset slots keep defaults")


func test_staff_uniform_needs_top_and_bottom() -> void:
	var o := Outfit.new()
	o.set_piece(TOP, &"staff_vest")
	assert_false(o.is_staff_uniform(), "top only")
	o.set_piece(TOP, &"plain_tee")
	o.set_piece(BOTTOM, &"staff_slacks")
	assert_false(o.is_staff_uniform(), "bottom only")
	o.set_piece(TOP, &"staff_vest")
	assert_true(o.is_staff_uniform(), "top and bottom")
	o.set_piece(HAT, &"ten_gallon_hat")
	o.set_piece(ACCESSORY, &"feather_boa")
	assert_true(o.is_staff_uniform(), "hat and accessory don't matter")
	var hat_only := _look_a()
	hat_only.set_piece(HAT, &"staff_hat")
	hat_only.set_piece(ACCESSORY, &"staff_name_tag")
	assert_false(hat_only.is_staff_uniform(), "staff hat and tag on civilian clothes")


func test_describe_lists_worn_pieces() -> void:
	assert_eq(_look_a().describe(), "Lucky Ball Cap, Aviator Shades, Hawaiian Shirt, Cargo Shorts, Chunky Gold Chain")
	var o := Outfit.new({TOP: &"hawaiian_shirt", BOTTOM: &"blue_jeans"})
	assert_eq(o.describe(), "Hawaiian Shirt, Blue Jeans", "empty slots skipped")


func test_to_dict_shape() -> void:
	var d: Dictionary = _look_a().to_dict()
	assert_eq(d.size(), 5)
	assert_eq(d["hat"], "lucky_ball_cap")
	assert_eq(d["accessory"], "gold_chain")
	assert_eq(Outfit.new().to_dict()["glasses"], "none")


func test_outfit_dict_round_trip() -> void:
	var rng := _rng(5)
	for i in 30:
		var o: Outfit = OutfitCatalog.random_outfit(rng)
		var back: Outfit = Outfit.from_dict(o.to_dict())
		assert_true(back.equals(o), "draw %d" % i)
		for slot: int in OutfitCatalog.all_slots():
			assert_eq(typeof(back.get_piece(slot)), TYPE_STRING_NAME)
	assert_true(Outfit.from_dict(OutfitCatalog.staff_uniform().to_dict()).is_staff_uniform())


func test_outfit_survives_json() -> void:
	var o := _look_a_except([GLASSES])
	var parsed: Variant = JSON.parse_string(JSON.stringify(o.to_dict()))
	assert_true(parsed is Dictionary)
	assert_true(Outfit.from_dict(parsed).equals(o))


func test_from_dict_accepts_int_and_numeric_keys() -> void:
	var o: Outfit = Outfit.from_dict({HAT: &"top_hat", "1": "monocle_x", "bogus": "x", "3": "track_pants"})
	assert_eq(o.get_piece(HAT), &"top_hat")
	assert_eq(o.get_piece(GLASSES), &"monocle_x", "ids aren't validated against the catalog")
	assert_eq(o.get_piece(BOTTOM), &"track_pants")
	assert_eq(o.get_piece(TOP), OutfitCatalog.default_piece(TOP))
	assert_true(Outfit.from_dict(_look_a().pieces).equals(_look_a()), "raw pieces dict loads too")


func test_from_dict_empty_gives_default() -> void:
	assert_true(Outfit.from_dict({}).equals(Outfit.new()))
	assert_true(Outfit.from_dict({"hat": null}).equals(Outfit.new()), "null values ignored")


# --- WantedPoster -----------------------------------------------------------

func test_poster_fields_and_copy_at_print_time() -> void:
	var look := _look_a()
	var p := WantedPoster.new(4, &"apex", 2, look)
	assert_eq(p.id, 4)
	assert_eq(p.casino_id, &"apex")
	assert_eq(p.pid, 2)
	assert_true(p.outfit.equals(look))
	assert_ne(p.outfit, look, "poster keeps its own copy")
	look.set_piece(HAT, NONE)
	look.set_piece(TOP, &"lucky_sweater")
	look.set_piece(BOTTOM, &"blue_jeans")
	assert_eq(p.outfit.get_piece(HAT), &"lucky_ball_cap", "changing clothes doesn't change the poster")
	assert_false(p.matches(look), "and now the wearer doesn't match it")
	assert_eq(p.defaced_slots.size(), 0)


func test_poster_matches_recognized_look() -> void:
	var p := WantedPoster.new(1, &"apex", 1, _look_a())
	assert_true(p.matches(_look_a()))
	assert_true(p.matches(_look_a_except([HAT, GLASSES])))
	assert_false(p.matches(_look_a_except([HAT, GLASSES, TOP])))
	assert_false(p.matches(null))
	assert_eq(p.match_count(_look_a_except([HAT])), 4)


func test_poster_deface_knocks_out_a_slot() -> void:
	var p := WantedPoster.new(1, &"apex", 1, _look_a())
	var three_with_hat := _look_a_except([GLASSES, TOP])  # matches hat, bottom, accessory
	assert_true(p.matches(three_with_hat))
	assert_true(p.deface(HAT))
	assert_true(p.is_defaced(HAT))
	assert_false(p.matches(three_with_hat), "hat no longer counts: 2 of 4")
	assert_true(p.matches(_look_a_except([HAT, GLASSES])), "3 of the remaining 4 still matches")
	assert_true(p.matches(_look_a_except([GLASSES])), "the defaced slot is ignored even if worn")
	assert_eq(p.match_count(_look_a()), 4)


func test_poster_deface_idempotent() -> void:
	var p := WantedPoster.new(1, &"apex", 1, _look_a())
	assert_true(p.deface(TOP))
	assert_false(p.deface(TOP), "second deface of the same slot")
	assert_eq(p.defaced_slots, [TOP] as Array[int])
	assert_false(p.deface(5), "invalid slot")
	assert_false(p.deface(-1))
	assert_eq(p.defaced_slots.size(), 1)


func test_poster_defaced_slots_sorted() -> void:
	var p := WantedPoster.new(1, &"apex", 1, _look_a())
	p.deface(ACCESSORY)
	p.deface(HAT)
	p.deface(TOP)
	assert_eq(p.defaced_slots, [HAT, TOP, ACCESSORY] as Array[int])


func test_poster_ruined_after_three_defaced() -> void:
	var p := WantedPoster.new(1, &"apex", 1, _look_a())
	p.deface(HAT)
	p.deface(GLASSES)
	assert_false(p.is_ruined())
	assert_true(p.matches(_look_a()), "3 readable slots, all match")
	p.deface(TOP)
	assert_eq(p.readable_slots(), 2)
	assert_true(p.is_ruined())
	assert_false(p.matches(_look_a()), "only 2 slots left: nobody matches")


func test_poster_of_empty_slots_matches_others_with_empty_slots() -> void:
	var p := WantedPoster.new(1, &"apex", 1, Outfit.new({TOP: &"plain_tee", BOTTOM: &"blue_jeans"}))
	var stranger := Outfit.new({TOP: &"biker_jacket", BOTTOM: &"leopard_leggings"})
	assert_true(p.matches(stranger), "no hat, no glasses, no accessory")
	p.deface(GLASSES)
	assert_false(p.matches(stranger))


func test_poster_dict_round_trip() -> void:
	var p := WantedPoster.new(7, &"neon_oasis", 3, _look_a())
	p.deface(ACCESSORY)
	p.deface(GLASSES)
	var back: WantedPoster = WantedPoster.from_dict(p.to_dict())
	assert_eq(back.id, 7)
	assert_eq(back.casino_id, &"neon_oasis")
	assert_eq(typeof(back.casino_id), TYPE_STRING_NAME)
	assert_eq(back.pid, 3)
	assert_true(back.outfit.equals(p.outfit))
	assert_eq(back.defaced_slots, [GLASSES, ACCESSORY] as Array[int])


func test_poster_survives_json() -> void:
	var p := WantedPoster.new(12, &"apex", 4, _look_a())
	p.deface(BOTTOM)
	var parsed: Variant = JSON.parse_string(JSON.stringify(p.to_dict()))
	var back: WantedPoster = WantedPoster.from_dict(parsed)
	assert_eq(back.id, 12)
	assert_eq(back.pid, 4)
	assert_eq(back.defaced_slots, [BOTTOM] as Array[int])
	assert_true(back.outfit.equals(p.outfit))


# --- PosterBoard ------------------------------------------------------------

func test_board_starts_empty() -> void:
	var board := PosterBoard.new()
	assert_eq(board.posters_in(&"apex").size(), 0)
	assert_eq(board.count(), 0)
	assert_null(board.matching_poster(&"apex", _look_a()))
	assert_null(board.get_poster(1))


func test_print_poster_stores_and_signals() -> void:
	var board := _board()
	var p: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	assert_not_null(p)
	assert_eq(p.casino_id, &"apex")
	assert_eq(p.pid, 1)
	assert_true(p.outfit.equals(_look_a()))
	assert_eq(printed.size(), 1)
	assert_eq(printed[0], p)
	assert_eq(board.posters_in(&"apex"), [p] as Array[WantedPoster])
	assert_eq(board.get_poster(p.id), p)
	assert_null(board.print_poster(&"apex", 1, null), "null outfit prints nothing")
	assert_eq(printed.size(), 1)


func test_print_poster_copies_outfit() -> void:
	var board := PosterBoard.new()
	var look := _look_a()
	var p: WantedPoster = board.print_poster(&"apex", 1, look)
	look.set_piece(HAT, &"poker_visor")
	look.set_piece(TOP, &"bowling_shirt")
	look.set_piece(BOTTOM, &"golf_plaid_pants")
	assert_eq(p.outfit.get_piece(HAT), &"lucky_ball_cap")
	assert_null(board.matching_poster(&"apex", look), "changed clothes dodge the poster")


func test_poster_ids_unique_and_increasing_across_casinos() -> void:
	var board := PosterBoard.new()
	var ids: Array[int] = []
	var casinos: Array[StringName] = [&"apex", &"grand_marquee", &"apex", &"rusty_spur", &"grand_marquee"]
	for i in casinos.size():
		var p: WantedPoster = board.print_poster(casinos[i], i + 1, _look_a())
		ids.append(p.id)
	for i in range(1, ids.size()):
		assert_gt(ids[i], ids[i - 1], "ids increase")
	assert_eq(board.count(), 5)
	assert_eq(board.count(&"apex"), 2)
	assert_eq(board.count(&"grand_marquee"), 2)
	assert_eq(board.count(&"rusty_spur"), 1)


func test_ids_not_reused_after_tear_down() -> void:
	var board := PosterBoard.new()
	var a: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var b: WantedPoster = board.print_poster(&"apex", 2, _look_b())
	assert_true(board.tear_down(b.id))
	var c: WantedPoster = board.print_poster(&"apex", 3, _look_b())
	assert_gt(c.id, b.id)
	assert_ne(c.id, a.id)


func test_posters_kept_per_casino() -> void:
	var board := PosterBoard.new()
	var a: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var b: WantedPoster = board.print_poster(&"neon_oasis", 1, _look_b())
	assert_eq(board.posters_in(&"apex"), [a] as Array[WantedPoster])
	assert_eq(board.posters_in(&"neon_oasis"), [b] as Array[WantedPoster])
	assert_eq(board.posters_in(&"rusty_spur").size(), 0)
	assert_null(board.matching_poster(&"neon_oasis", _look_a()), "apex poster isn't up at neon oasis")
	assert_eq(board.matching_poster(&"apex", _look_a()), a)


func test_posters_persist_between_visits() -> void:
	var board := PosterBoard.new()
	board.print_poster(&"grand_marquee", 1, _look_a())
	# Thrown out, visit other casinos, print more there, come back later.
	board.print_poster(&"riverboat_queen", 1, _look_b())
	board.posters_in(&"riverboat_queen").clear()
	assert_not_null(board.matching_poster(&"grand_marquee", _look_a()), "old look still on the wall")
	assert_eq(board.count(&"riverboat_queen"), 1, "clearing the returned array doesn't touch the board")


func test_posters_in_returns_copy() -> void:
	var board := PosterBoard.new()
	board.print_poster(&"apex", 1, _look_a())
	var list: Array[WantedPoster] = board.posters_in(&"apex")
	list.append(WantedPoster.new(99, &"apex", 9, _look_b()))
	assert_eq(board.count(&"apex"), 1)
	assert_null(board.matching_poster(&"apex", _look_b()))


func test_matching_poster_finds_recognized_look() -> void:
	var board := PosterBoard.new()
	var p: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	assert_eq(board.matching_poster(&"apex", _look_a_except([HAT, GLASSES])), p)
	assert_null(board.matching_poster(&"apex", _look_a_except([HAT, GLASSES, TOP])))
	assert_null(board.matching_poster(&"apex", null))


func test_matching_poster_matches_any_wearer() -> void:
	var board := PosterBoard.new()
	var p: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	# A teammate (pid 2) borrowing pid 1's old look gets matched too: guards go by looks.
	assert_eq(board.matching_poster(&"apex", _look_a()), p)


func test_matching_poster_prefers_best_then_newest() -> void:
	var board := PosterBoard.new()
	var partial: WantedPoster = board.print_poster(&"apex", 1, _look_a_except([HAT]))
	var exact: WantedPoster = board.print_poster(&"apex", 2, _look_a())
	var other_partial: WantedPoster = board.print_poster(&"apex", 3, _look_a_except([GLASSES]))
	assert_eq(board.matching_poster(&"apex", _look_a()), exact, "5 matches beats 4")
	assert_true(partial.matches(_look_a()))
	assert_true(other_partial.matches(_look_a()))
	var newest: WantedPoster = board.print_poster(&"apex", 4, _look_a())
	assert_eq(board.matching_poster(&"apex", _look_a()), newest, "tie goes to the newest")


func test_reprinting_same_look_returns_existing_poster() -> void:
	var board := _board()
	var first: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var again: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	assert_eq(again, first)
	assert_eq(board.count(&"apex"), 1)
	assert_eq(printed.size(), 1, "no signal for a duplicate")
	# A different player, casino or look, or a defaced poster, prints a new one.
	assert_ne(board.print_poster(&"apex", 2, _look_a()), first)
	assert_ne(board.print_poster(&"neon_oasis", 1, _look_a()), first)
	assert_ne(board.print_poster(&"apex", 1, _look_a_except([HAT])), first)
	board.deface(first.id, HAT)
	var fresh: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	assert_ne(fresh, first, "security reprints over a defaced poster")
	assert_eq(fresh.defaced_slots.size(), 0)
	assert_eq(printed.size(), 5)


func test_tear_down_removes_and_signals() -> void:
	var board := _board()
	var a: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var b: WantedPoster = board.print_poster(&"apex", 2, _look_b())
	assert_true(board.tear_down(a.id))
	assert_eq(removed, [a.id] as Array[int])
	assert_eq(board.posters_in(&"apex"), [b] as Array[WantedPoster])
	assert_null(board.matching_poster(&"apex", _look_a()))
	assert_null(board.get_poster(a.id))
	assert_false(board.tear_down(a.id), "already gone")
	assert_false(board.tear_down(999), "never existed")
	assert_eq(removed.size(), 1)


func test_tear_down_works_in_any_casino() -> void:
	var board := PosterBoard.new()
	board.print_poster(&"apex", 1, _look_a())
	var far: WantedPoster = board.print_poster(&"rusty_spur", 1, _look_a())
	assert_true(board.tear_down(far.id))
	assert_eq(board.count(&"rusty_spur"), 0)
	assert_eq(board.count(&"apex"), 1)


func test_board_deface_idempotent_and_signals() -> void:
	var board := _board()
	var p: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	assert_true(board.deface(p.id, HAT))
	assert_false(board.deface(p.id, HAT), "same slot again")
	assert_true(board.deface(p.id, GLASSES))
	assert_false(board.deface(p.id, 8), "invalid slot")
	assert_false(board.deface(999, HAT), "unknown poster")
	assert_eq(defaced, [[p.id, HAT], [p.id, GLASSES]])
	assert_eq(p.defaced_slots, [HAT, GLASSES] as Array[int])


func test_board_deface_changes_matching() -> void:
	var board := PosterBoard.new()
	var p: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var look := _look_a_except([GLASSES, TOP])  # hat, bottom, accessory match
	assert_eq(board.matching_poster(&"apex", look), p)
	board.deface(p.id, BOTTOM)
	assert_null(board.matching_poster(&"apex", look), "knocked down to 2 of 4")


func test_posters_for_player_and_all_posters() -> void:
	var board := PosterBoard.new()
	var a: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var b: WantedPoster = board.print_poster(&"neon_oasis", 2, _look_a())
	var c: WantedPoster = board.print_poster(&"neon_oasis", 1, _look_b())
	assert_eq(board.posters_for(1), [a, c] as Array[WantedPoster])
	assert_eq(board.posters_for(2), [b] as Array[WantedPoster])
	assert_eq(board.posters_for(3).size(), 0)
	assert_eq(board.all_posters(), [a, b, c] as Array[WantedPoster])


func test_board_dict_round_trip() -> void:
	var board := PosterBoard.new()
	var a: WantedPoster = board.print_poster(&"apex", 1, _look_a())
	var b: WantedPoster = board.print_poster(&"neon_oasis", 2, _look_b())
	var c: WantedPoster = board.print_poster(&"apex", 3, _look_a_except([TOP]))
	board.deface(c.id, HAT)
	board.tear_down(b.id)
	var back: PosterBoard = PosterBoard.from_dict(board.to_dict())
	assert_eq(back.count(), 2)
	assert_eq(back.count(&"apex"), 2)
	assert_eq(back.count(&"neon_oasis"), 0)
	var c2: WantedPoster = back.get_poster(c.id)
	assert_not_null(c2)
	assert_eq(c2.defaced_slots, [HAT] as Array[int])
	assert_true(c2.outfit.equals(c.outfit))
	assert_eq(back.get_poster(a.id).pid, 1)
	var d: WantedPoster = back.print_poster(&"apex", 4, _look_b())
	assert_gt(d.id, c.id, "ids keep increasing after load, even past torn-down ones")
	assert_gt(d.id, b.id)


func test_board_survives_json() -> void:
	var board := PosterBoard.new()
	board.print_poster(&"apex", 1, _look_a())
	var p: WantedPoster = board.print_poster(&"grand_marquee", 2, _look_b())
	board.deface(p.id, ACCESSORY)
	var parsed: Variant = JSON.parse_string(JSON.stringify(board.to_dict()))
	var back: PosterBoard = PosterBoard.from_dict(parsed)
	assert_eq(back.count(), 2)
	var p2: WantedPoster = back.matching_poster(&"grand_marquee", _look_b())
	assert_not_null(p2)
	assert_eq(p2.id, p.id)
	assert_eq(p2.casino_id, &"grand_marquee")
	assert_eq(p2.defaced_slots, [ACCESSORY] as Array[int])
	assert_gt(back.print_poster(&"apex", 3, _look_b()).id, p.id)


func test_from_dict_next_id_above_loaded_posters() -> void:
	var data := {"next_id": 2, "posters": [WantedPoster.new(10, &"apex", 1, _look_a()).to_dict()]}
	var board: PosterBoard = PosterBoard.from_dict(data)
	assert_eq(board.print_poster(&"apex", 2, _look_b()).id, 11)
	assert_eq(PosterBoard.from_dict({}).count(), 0)
	assert_eq(PosterBoard.from_dict({"posters": ["junk", 3]}).count(), 0, "junk entries skipped")
