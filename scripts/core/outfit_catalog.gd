class_name OutfitCatalog
extends RefCounted
## Every outfit piece in the game, five slots (HR.OutfitSlot). Static only.
##
## Piece ids are StringNames. Hat, glasses and accessory can be empty: that is
## the shared piece NONE, and it matches like any other piece (two people with
## no hat match on the hat slot). Top and bottom are never empty.
## Colors tint the low-poly piece meshes; NONE's color is fully transparent so
## the world layer can hide that mesh. Prices come from Tuning.OUTFIT_TIER_PRICES
## by each piece's tier; tier 0 (NONE and staff pieces) is not sold.
## Staff pieces come from staff lockers, not the gift shop, and are left out of
## pieces_for() unless asked for; random outfits never use them.

const NONE := &"none"

const SLOT_KEYS := {
	HR.OutfitSlot.HAT: "hat",
	HR.OutfitSlot.GLASSES: "glasses",
	HR.OutfitSlot.TOP: "top",
	HR.OutfitSlot.BOTTOM: "bottom",
	HR.OutfitSlot.ACCESSORY: "accessory",
}

const SLOT_NAMES := {
	HR.OutfitSlot.HAT: "Hat",
	HR.OutfitSlot.GLASSES: "Glasses",
	HR.OutfitSlot.TOP: "Top",
	HR.OutfitSlot.BOTTOM: "Bottom",
	HR.OutfitSlot.ACCESSORY: "Accessory",
}

## Slots that may hold NONE.
const OPTIONAL_SLOTS := [HR.OutfitSlot.HAT, HR.OutfitSlot.GLASSES, HR.OutfitSlot.ACCESSORY]

## What a fresh Outfit.new() wears.
const DEFAULT_PIECES := {
	HR.OutfitSlot.HAT: NONE,
	HR.OutfitSlot.GLASSES: NONE,
	HR.OutfitSlot.TOP: &"plain_tee",
	HR.OutfitSlot.BOTTOM: &"blue_jeans",
	HR.OutfitSlot.ACCESSORY: NONE,
}

## The full staff set: what staff_uniform() returns.
const STAFF_PIECES := {
	HR.OutfitSlot.HAT: &"staff_hat",
	HR.OutfitSlot.GLASSES: NONE,
	HR.OutfitSlot.TOP: &"staff_vest",
	HR.OutfitSlot.BOTTOM: &"staff_slacks",
	HR.OutfitSlot.ACCESSORY: &"staff_name_tag",
}

## id -> {slot, name, color, tier, staff}. Order within a slot is display order.
const PIECES := {
	# --- Hats ---
	&"lucky_ball_cap": {"slot": HR.OutfitSlot.HAT, "name": "Lucky Ball Cap", "color": Color("d7263d"), "tier": 1, "staff": false},
	&"ten_gallon_hat": {"slot": HR.OutfitSlot.HAT, "name": "Ten-Gallon Hat", "color": Color("a0673a"), "tier": 2, "staff": false},
	&"high_roller_fedora": {"slot": HR.OutfitSlot.HAT, "name": "High-Roller Fedora", "color": Color("4a4e69"), "tier": 2, "staff": false},
	&"bucket_hat": {"slot": HR.OutfitSlot.HAT, "name": "Fishing Bucket Hat", "color": Color("7a8b3c"), "tier": 1, "staff": false},
	&"top_hat": {"slot": HR.OutfitSlot.HAT, "name": "Midnight Top Hat", "color": Color("1c1c22"), "tier": 3, "staff": false},
	&"poker_visor": {"slot": HR.OutfitSlot.HAT, "name": "Poker Visor", "color": Color("2ecc71"), "tier": 1, "staff": false},
	&"pom_pom_beanie": {"slot": HR.OutfitSlot.HAT, "name": "Pom-Pom Beanie", "color": Color("8e44ad"), "tier": 1, "staff": false},
	&"birthday_crown": {"slot": HR.OutfitSlot.HAT, "name": "Birthday Crown", "color": Color("f4c430"), "tier": 2, "staff": false},
	&"staff_hat": {"slot": HR.OutfitSlot.HAT, "name": "Staff Cap", "color": Color("7b1e3a"), "tier": 0, "staff": true},
	# --- Glasses ---
	&"aviator_shades": {"slot": HR.OutfitSlot.GLASSES, "name": "Aviator Shades", "color": Color("c9a227"), "tier": 2, "staff": false},
	&"heart_shades": {"slot": HR.OutfitSlot.GLASSES, "name": "Heart Shades", "color": Color("ff5fa2"), "tier": 1, "staff": false},
	&"nerd_frames": {"slot": HR.OutfitSlot.GLASSES, "name": "Thick Nerd Frames", "color": Color("4b3621"), "tier": 1, "staff": false},
	&"fancy_monocle": {"slot": HR.OutfitSlot.GLASSES, "name": "Fancy Monocle", "color": Color("c0c0c8"), "tier": 3, "staff": false},
	&"ski_goggles": {"slot": HR.OutfitSlot.GLASSES, "name": "Ski Goggles", "color": Color("ff8c1a"), "tier": 2, "staff": false},
	&"star_glasses": {"slot": HR.OutfitSlot.GLASSES, "name": "Superstar Glasses", "color": Color("1e90ff"), "tier": 2, "staff": false},
	&"groucho_disguise": {"slot": HR.OutfitSlot.GLASSES, "name": "Nose-and-Mustache Disguise", "color": Color("f1c27d"), "tier": 1, "staff": false},
	# --- Tops ---
	&"plain_tee": {"slot": HR.OutfitSlot.TOP, "name": "Plain White Tee", "color": Color("f2f2f2"), "tier": 1, "staff": false},
	&"hawaiian_shirt": {"slot": HR.OutfitSlot.TOP, "name": "Hawaiian Shirt", "color": Color("ff7f50"), "tier": 1, "staff": false},
	&"rented_tuxedo": {"slot": HR.OutfitSlot.TOP, "name": "Rented Tuxedo", "color": Color("22222a"), "tier": 3, "staff": false},
	&"velour_tracksuit": {"slot": HR.OutfitSlot.TOP, "name": "Velour Tracksuit Top", "color": Color("6c3fa0"), "tier": 2, "staff": false},
	&"biker_jacket": {"slot": HR.OutfitSlot.TOP, "name": "Biker Jacket", "color": Color("6b4226"), "tier": 2, "staff": false},
	&"sequin_blazer": {"slot": HR.OutfitSlot.TOP, "name": "Sequin Blazer", "color": Color("e6c229"), "tier": 3, "staff": false},
	&"lucky_sweater": {"slot": HR.OutfitSlot.TOP, "name": "Lucky Clover Sweater", "color": Color("2e8b57"), "tier": 1, "staff": false},
	&"bowling_shirt": {"slot": HR.OutfitSlot.TOP, "name": "Bowling Shirt", "color": Color("1f6fb2"), "tier": 1, "staff": false},
	&"staff_vest": {"slot": HR.OutfitSlot.TOP, "name": "Dealer Vest", "color": Color("7b1e3a"), "tier": 0, "staff": true},
	# --- Bottoms ---
	&"blue_jeans": {"slot": HR.OutfitSlot.BOTTOM, "name": "Blue Jeans", "color": Color("3b5998"), "tier": 1, "staff": false},
	&"cargo_shorts": {"slot": HR.OutfitSlot.BOTTOM, "name": "Cargo Shorts", "color": Color("c3b091"), "tier": 1, "staff": false},
	&"pressed_slacks": {"slot": HR.OutfitSlot.BOTTOM, "name": "Pressed Slacks", "color": Color("5c5c66"), "tier": 2, "staff": false},
	&"track_pants": {"slot": HR.OutfitSlot.BOTTOM, "name": "Swishy Track Pants", "color": Color("9b59b6"), "tier": 1, "staff": false},
	&"golf_plaid_pants": {"slot": HR.OutfitSlot.BOTTOM, "name": "Golf Plaid Pants", "color": Color("e67e22"), "tier": 2, "staff": false},
	&"leopard_leggings": {"slot": HR.OutfitSlot.BOTTOM, "name": "Leopard Leggings", "color": Color("d9a441"), "tier": 2, "staff": false},
	&"pleated_skirt": {"slot": HR.OutfitSlot.BOTTOM, "name": "Red Pleated Skirt", "color": Color("c0392b"), "tier": 2, "staff": false},
	&"gold_lame_pants": {"slot": HR.OutfitSlot.BOTTOM, "name": "Gold Lame Disco Pants", "color": Color("ffd34d"), "tier": 3, "staff": false},
	&"staff_slacks": {"slot": HR.OutfitSlot.BOTTOM, "name": "Staff Slacks", "color": Color("15151a"), "tier": 0, "staff": true},
	# --- Accessories ---
	&"gold_chain": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Chunky Gold Chain", "color": Color("d4a017"), "tier": 3, "staff": false},
	&"feather_boa": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Feather Boa", "color": Color("ff4fb4"), "tier": 2, "staff": false},
	&"lucky_scarf": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Lucky Red Scarf", "color": Color("e74c3c"), "tier": 1, "staff": false},
	&"bow_tie": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Teal Bow Tie", "color": Color("16a085"), "tier": 1, "staff": false},
	&"fanny_pack": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Neon Fanny Pack", "color": Color("7fff00"), "tier": 1, "staff": false},
	&"tourist_camera": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Tourist Camera", "color": Color("7f8c8d"), "tier": 2, "staff": false},
	&"foam_finger": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Big Foam Finger", "color": Color("2f80ed"), "tier": 1, "staff": false},
	&"staff_name_tag": {"slot": HR.OutfitSlot.ACCESSORY, "name": "Staff Name Tag", "color": Color("b08d57"), "tier": 0, "staff": true},
}

## Color of NONE: transparent, meaning "hide this slot's mesh".
const NONE_COLOR := Color(0.0, 0.0, 0.0, 0.0)
## Color for an id the catalog does not know.
const UNKNOWN_COLOR := Color("9e9e9e")


static func all_slots() -> Array[int]:
	var slots: Array[int] = []
	for i in HR.OUTFIT_SLOT_COUNT:
		slots.append(i)
	return slots


static func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < HR.OUTFIT_SLOT_COUNT


## True for hat, glasses and accessory, which may be left empty (NONE).
static func is_optional_slot(slot: int) -> bool:
	return OPTIONAL_SLOTS.has(slot)


## Display name of an HR.OutfitSlot ("Hat").
static func slot_name(slot: int) -> String:
	return str(SLOT_NAMES.get(slot, "Unknown"))


## Save/network key of an HR.OutfitSlot ("hat").
static func slot_key(slot: int) -> String:
	return str(SLOT_KEYS.get(slot, ""))


## HR.OutfitSlot for a key from slot_key(), or -1.
static func slot_from_key(key: String) -> int:
	for slot: int in SLOT_KEYS:
		if SLOT_KEYS[slot] == key:
			return slot
	return -1


## Catalog piece ids for a slot, in display order. Optional slots start with
## NONE. Staff pieces are included only when include_staff is true.
static func pieces_for(slot: int, include_staff: bool = false) -> Array[StringName]:
	var ids: Array[StringName] = []
	if not is_valid_slot(slot):
		return ids
	if is_optional_slot(slot):
		ids.append(NONE)
	for id: StringName in PIECES:
		var data: Dictionary = PIECES[id]
		if int(data["slot"]) != slot:
			continue
		if bool(data["staff"]) and not include_staff:
			continue
		ids.append(id)
	return ids


## Pieces the gift shop sells in a slot: everything with a price (no NONE, no staff).
static func shop_pieces(slot: int) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in pieces_for(slot):
		if piece_price(id) > 0:
			ids.append(id)
	return ids


## True if the id is NONE or a catalog piece.
static func has_piece(id: StringName) -> bool:
	return id == NONE or PIECES.has(id)


static func is_none(id: StringName) -> bool:
	return id == NONE or id == &""


static func is_staff_piece(id: StringName) -> bool:
	if not PIECES.has(id):
		return false
	var data: Dictionary = PIECES[id]
	return bool(data["staff"])


## HR.OutfitSlot a piece belongs to, or -1 for NONE (fits several) and unknown ids.
static func slot_of(id: StringName) -> int:
	if not PIECES.has(id):
		return -1
	var data: Dictionary = PIECES[id]
	return int(data["slot"])


## True if the piece can be worn in that slot (NONE only in optional slots).
static func fits(id: StringName, slot: int) -> bool:
	if not is_valid_slot(slot):
		return false
	if is_none(id):
		return is_optional_slot(slot)
	return slot_of(id) == slot


static func piece_name(id: StringName) -> String:
	if is_none(id):
		return "Nothing"
	if PIECES.has(id):
		var data: Dictionary = PIECES[id]
		return str(data["name"])
	return String(id).capitalize()


## Mesh tint. NONE is transparent (hide the mesh); unknown ids are gray.
static func piece_color(id: StringName) -> Color:
	if is_none(id):
		return NONE_COLOR
	if PIECES.has(id):
		var data: Dictionary = PIECES[id]
		return data["color"] as Color
	return UNKNOWN_COLOR


## Catalog tier: 0 = free / not sold, higher = pricier.
static func piece_tier(id: StringName) -> int:
	if not PIECES.has(id):
		return 0
	var data: Dictionary = PIECES[id]
	return int(data["tier"])


## Gift-shop price. 0 means not for sale (NONE, staff pieces, unknown ids).
static func piece_price(id: StringName) -> int:
	var tier: int = piece_tier(id)
	if tier < 0 or tier >= Tuning.OUTFIT_TIER_PRICES.size():
		return 0
	return int(Tuning.OUTFIT_TIER_PRICES[tier])


static func is_for_sale(id: StringName) -> bool:
	return piece_price(id) > 0


## What a fresh outfit wears in a slot.
static func default_piece(slot: int) -> StringName:
	return DEFAULT_PIECES.get(slot, NONE) as StringName


## A random civilian piece for the slot (NONE possible in optional slots).
## Never a staff piece. `exclude` is skipped when there is another choice.
static func random_piece(slot: int, rng: RandomNumberGenerator, exclude: StringName = &"") -> StringName:
	var ids: Array[StringName] = pieces_for(slot)
	if ids.is_empty():
		return NONE
	if ids.size() > 1 and ids.has(exclude):
		ids.erase(exclude)
	return ids[rng.randi_range(0, ids.size() - 1)]


## A random civilian look for patrons and new players. Never a staff uniform
## (it never uses staff pieces at all).
static func random_outfit(rng: RandomNumberGenerator) -> Outfit:
	var outfit := Outfit.new()
	for slot: int in all_slots():
		outfit.set_piece(slot, random_piece(slot, rng))
	return outfit


## The full staff set (cap, no glasses, dealer vest, slacks, name tag).
static func staff_uniform() -> Outfit:
	var outfit := Outfit.new()
	for slot: int in STAFF_PIECES:
		outfit.set_piece(slot, STAFF_PIECES[slot] as StringName)
	return outfit
