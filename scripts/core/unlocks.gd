class_name Unlocks
extends RefCounted
## The cosmetic unlock table (design doc "Scoring and progression"): lifetime
## banked chips unlock outfit pieces, emotes and ID name packs. Unlocks are
## cosmetic only; nothing is sold for real money. Static only.
##
## Ids: an outfit piece's catalog id (OutfitCatalog, "locked": true), an
## emote's CharacterModel pose name, a name pack's IdGenerator.NAME_PACKS id.
## TABLE is sorted by `at` (lifetime banked chips); an entry at 0 is a
## starter everyone has. Profile keeps what a player has unlocked.

const KIND_PIECE := &"piece"
const KIND_EMOTE := &"emote"
const KIND_NAME_PACK := &"name_pack"

## Emote id -> display name. Every id is also a CharacterModel pose.
const EMOTE_NAMES := {
	&"wave": "Wave",
	&"shrug": "Shrug",
	&"chip_flip": "Chip Flip",
	&"dance": "Disco Dance",
	&"bow": "Grand Bow",
}

## {id, kind, at}: unlocked once lifetime banked chips reach `at`.
const TABLE: Array[Dictionary] = [
	{"id": &"wave", "kind": KIND_EMOTE, "at": 0},
	{"id": &"shrug", "kind": KIND_EMOTE, "at": 1000},
	{"id": &"propeller_beanie", "kind": KIND_PIECE, "at": 2500},
	{"id": &"bell_bottoms", "kind": KIND_PIECE, "at": 4000},
	{"id": &"retro_3d_glasses", "kind": KIND_PIECE, "at": 6000},
	{"id": &"fuzzy_dice", "kind": KIND_PIECE, "at": 8000},
	{"id": &"high_seas", "kind": KIND_NAME_PACK, "at": 10000},
	{"id": &"polka_dot_shirt", "kind": KIND_PIECE, "at": 13000},
	{"id": &"chip_flip", "kind": KIND_EMOTE, "at": 16000},
	{"id": &"pirate_tricorn", "kind": KIND_PIECE, "at": 20000},
	{"id": &"eye_patch", "kind": KIND_PIECE, "at": 25000},
	{"id": &"shoulder_parrot", "kind": KIND_PIECE, "at": 30000},
	{"id": &"tartan_kilt", "kind": KIND_PIECE, "at": 36000},
	{"id": &"silver_screen", "kind": KIND_NAME_PACK, "at": 43000},
	{"id": &"dance", "kind": KIND_EMOTE, "at": 50000},
	{"id": &"trench_coat", "kind": KIND_PIECE, "at": 60000},
	{"id": &"viking_helmet", "kind": KIND_PIECE, "at": 72000},
	{"id": &"pinstripe_trousers", "kind": KIND_PIECE, "at": 85000},
	{"id": &"space_age", "kind": KIND_NAME_PACK, "at": 100000},
	{"id": &"diamond_shades", "kind": KIND_PIECE, "at": 120000},
	{"id": &"velvet_cape", "kind": KIND_PIECE, "at": 145000},
	{"id": &"bow", "kind": KIND_EMOTE, "at": 175000},
	{"id": &"gold_tuxedo", "kind": KIND_PIECE, "at": 210000},
]


static func has(id: StringName) -> bool:
	return _index(id) >= 0


## The TABLE row for an id ({} if unknown), as a copy.
static func entry(id: StringName) -> Dictionary:
	var i := _index(id)
	return TABLE[i].duplicate() if i >= 0 else {}


## KIND_PIECE, KIND_EMOTE, KIND_NAME_PACK, or &"" for an unknown id.
static func kind_of(id: StringName) -> StringName:
	var i := _index(id)
	return TABLE[i]["kind"] as StringName if i >= 0 else &""


## Lifetime banked chips that unlock the id (-1 for an unknown id).
static func threshold(id: StringName) -> int:
	var i := _index(id)
	return int(TABLE[i]["at"]) if i >= 0 else -1


## Every id of a kind, in unlock order.
static func ids_of(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in TABLE:
		if row["kind"] == kind:
			out.append(row["id"] as StringName)
	return out


## Every id unlocked at `lifetime_banked` chips, in unlock order.
static func unlocked_at(lifetime_banked: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in TABLE:
		if int(row["at"]) <= lifetime_banked:
			out.append(row["id"] as StringName)
	return out


## Ids that going from `before` to `after` lifetime banked chips unlocks.
static func crossed(before: int, after: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for row: Dictionary in TABLE:
		var at := int(row["at"])
		if at > before and at <= after:
			out.append(row["id"] as StringName)
	return out


## The next row still locked at `lifetime_banked` ({} once everything is unlocked).
static func next_unlock(lifetime_banked: int) -> Dictionary:
	for row: Dictionary in TABLE:
		if int(row["at"]) > lifetime_banked:
			return row.duplicate()
	return {}


## "Propeller Beanie", "Shrug", "Space Age"; the id capitalized if unknown.
static func display_name(id: StringName) -> String:
	match kind_of(id):
		KIND_PIECE:
			return OutfitCatalog.piece_name(id)
		KIND_EMOTE:
			return str(EMOTE_NAMES.get(id, String(id).capitalize()))
		KIND_NAME_PACK:
			return IdGenerator.name_pack_name(id)
	return String(id).capitalize()


## "Hat", "Emote", "ID names".
static func kind_label(id: StringName) -> String:
	match kind_of(id):
		KIND_PIECE:
			return OutfitCatalog.slot_name(OutfitCatalog.slot_of(id))
		KIND_EMOTE:
			return "Emote"
		KIND_NAME_PACK:
			return "ID names"
	return ""


static func _index(id: StringName) -> int:
	for i in TABLE.size():
		if TABLE[i]["id"] == id:
			return i
	return -1
