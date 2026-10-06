class_name WantedPoster
extends RefCounted
## A poster of one player's look, printed when they go Wanted in a casino.
## Guards compare people against it on the slots nobody has drawn over:
## defacing a slot knocks it out, and the recognize bar stays at
## Tuning.RECOGNIZE_MATCHES, so one defaced slot means 3 of the remaining 4.

## Unique within a PosterBoard; later posters have higher ids.
var id: int = 0
var casino_id: StringName = &""
## Player the poster was printed for (a guard matches anyone wearing the look).
var pid: int = 0
## Copy of the look at print time; later outfit changes don't touch it.
var outfit: Outfit
## HR.OutfitSlot values drawn over, kept sorted, no duplicates.
var defaced_slots: Array[int] = []


func _init(poster_id: int = 0, casino: StringName = &"", player_id: int = 0, look: Outfit = null) -> void:
	id = poster_id
	casino_id = casino
	pid = player_id
	outfit = look.copy() if look != null else Outfit.new()


## True if `look` is recognized on the slots that aren't defaced.
func matches(look: Outfit) -> bool:
	if look == null:
		return false
	return look.is_recognized_as(outfit, defaced_slots)


## Number of non-defaced slots `look` matches.
func match_count(look: Outfit) -> int:
	if look == null:
		return 0
	return look.matches(outfit, defaced_slots)


## Draws over one slot. Returns true if it was newly defaced; false if it was
## already defaced or the slot is invalid (idempotent).
func deface(slot: int) -> bool:
	if not OutfitCatalog.is_valid_slot(slot) or defaced_slots.has(slot):
		return false
	defaced_slots.append(slot)
	defaced_slots.sort()
	return true


func is_defaced(slot: int) -> bool:
	return defaced_slots.has(slot)


## Slots still readable on the poster.
func readable_slots() -> int:
	return HR.OUTFIT_SLOT_COUNT - defaced_slots.size()


## True once so many slots are defaced that nobody can match it any more.
func is_ruined() -> bool:
	return readable_slots() < Tuning.RECOGNIZE_MATCHES


func to_dict() -> Dictionary:
	var slots: Array = []
	for slot: int in defaced_slots:
		slots.append(slot)
	return {
		"id": id,
		"casino_id": String(casino_id),
		"pid": pid,
		"outfit": outfit.to_dict(),
		"defaced_slots": slots,
	}


## Reads to_dict() output (also after a JSON round-trip, where ints become floats).
static func from_dict(d: Dictionary) -> WantedPoster:
	var look_data: Variant = d.get("outfit", {})
	var look: Outfit = Outfit.from_dict(look_data if look_data is Dictionary else {})
	var poster := WantedPoster.new(int(d.get("id", 0)), StringName(str(d.get("casino_id", ""))), int(d.get("pid", 0)), look)
	var slots: Variant = d.get("defaced_slots", [])
	if slots is Array:
		for slot: Variant in slots:
			if typeof(slot) == TYPE_INT or typeof(slot) == TYPE_FLOAT:
				poster.deface(int(slot))
	return poster
