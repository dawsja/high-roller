class_name Outfit
extends RefCounted
## A look: one piece id per HR.OutfitSlot. Security records these and compares
## them slot by slot; matching on Tuning.RECOGNIZE_MATCHES slots is recognized.
##
## An empty slot holds OutfitCatalog.NONE and matches like any other piece.
## Ids are not checked against the catalog here (OutfitCatalog.fits does that),
## so any StringName can be worn and compared.

## HR.OutfitSlot (int) -> piece id (StringName). Always has all five slots.
var pieces: Dictionary = {}


## Starts from OutfitCatalog.DEFAULT_PIECES; `initial` overrides slots. It takes
## the same keys as from_dict (HR.OutfitSlot ints or slot keys like "hat").
func _init(initial: Dictionary = {}) -> void:
	for slot: int in OutfitCatalog.all_slots():
		pieces[slot] = OutfitCatalog.default_piece(slot)
	_apply(initial)


## Piece id in a slot; NONE for an empty slot.
func get_piece(slot: int) -> StringName:
	var id: Variant = pieces.get(slot)
	if id == null or str(id) == "":
		return OutfitCatalog.NONE
	return StringName(str(id))


## Puts a piece in a slot; an empty id means NONE. Returns false (and changes
## nothing) for a slot outside HR.OutfitSlot.
func set_piece(slot: int, id: StringName) -> bool:
	if not OutfitCatalog.is_valid_slot(slot):
		return false
	pieces[slot] = OutfitCatalog.NONE if id == &"" else id
	return true


## Number of slots (out of five, minus ignore_slots) wearing the same piece.
func matches(other: Outfit, ignore_slots: Array = []) -> int:
	if other == null:
		return 0
	var count := 0
	for slot: int in OutfitCatalog.all_slots():
		if _slot_listed(ignore_slots, slot):
			continue
		if get_piece(slot) == other.get_piece(slot):
			count += 1
	return count


## Array.has() is type-strict; slot lists that went through JSON hold floats.
static func _slot_listed(slots: Array, slot: int) -> bool:
	for s: Variant in slots:
		if (typeof(s) == TYPE_INT or typeof(s) == TYPE_FLOAT) and float(s) == float(slot):
			return true
	return false


## True if this look matches `record` on at least Tuning.RECOGNIZE_MATCHES of
## the slots not in ignore_slots. Ignoring slots does not lower the bar: with
## one slot ignored it takes 3 of the remaining 4.
func is_recognized_as(record: Outfit, ignore_slots: Array = []) -> bool:
	if record == null:
		return false
	return matches(record, ignore_slots) >= Tuning.RECOGNIZE_MATCHES


## Same piece in every slot.
func equals(other: Outfit) -> bool:
	return other != null and matches(other) == HR.OUTFIT_SLOT_COUNT


func copy() -> Outfit:
	var o := Outfit.new()
	for slot: int in OutfitCatalog.all_slots():
		o.set_piece(slot, get_piece(slot))
	return o


## Staff pass: the top AND the bottom are staff pieces (hat etc. don't matter).
func is_staff_uniform() -> bool:
	return OutfitCatalog.is_staff_piece(get_piece(HR.OutfitSlot.TOP)) \
		and OutfitCatalog.is_staff_piece(get_piece(HR.OutfitSlot.BOTTOM))


## Piece names in slot order, skipping empty slots: "Lucky Ball Cap, Hawaiian Shirt, Blue Jeans".
func describe() -> String:
	var names: PackedStringArray = []
	for slot: int in OutfitCatalog.all_slots():
		var id: StringName = get_piece(slot)
		if not OutfitCatalog.is_none(id):
			names.append(OutfitCatalog.piece_name(id))
	if names.is_empty():
		return "Nothing at all"
	return ", ".join(names)


## {"hat": "none", "glasses": "...", "top": "...", "bottom": "...", "accessory": "..."}
## Plain strings, safe for JSON, saves and RPC.
func to_dict() -> Dictionary:
	var d := {}
	for slot: int in OutfitCatalog.all_slots():
		d[OutfitCatalog.slot_key(slot)] = String(get_piece(slot))
	return d


## Reads to_dict() output. Also accepts int slot keys or numeric string keys
## ("0") so dictionaries that went through JSON still load. Missing slots keep
## their defaults; unknown keys are ignored.
static func from_dict(d: Dictionary) -> Outfit:
	return Outfit.new(d)


func _apply(d: Dictionary) -> void:
	for key: Variant in d:
		var slot := -1
		if typeof(key) == TYPE_INT:
			slot = int(key)
		elif typeof(key) == TYPE_STRING or typeof(key) == TYPE_STRING_NAME:
			var s := str(key)
			slot = int(s) if s.is_valid_int() else OutfitCatalog.slot_from_key(s)
		var value: Variant = d[key]
		if slot < 0 or value == null:
			continue
		set_piece(slot, StringName(str(value)))
