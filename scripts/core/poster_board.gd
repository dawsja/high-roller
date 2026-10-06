class_name PosterBoard
extends RefCounted
## Every wanted poster in the run, grouped by casino id. RunState keeps one for
## the whole run, so posters stay up between visits: come back to a casino and
## your old look is still on the wall. Host-owned.
##
## Poster ids are unique across all casinos and always increase (torn-down ids
## are never reused). Printing the exact look that already hangs, undefaced,
## on a poster for the same player in the same casino returns that poster
## instead of printing a duplicate (no poster_printed signal then).

signal poster_printed(poster: WantedPoster)
signal poster_removed(poster_id: int)
## A slot on a poster was newly drawn over.
signal poster_defaced(poster_id: int, slot: int)

## casino_id (StringName) -> Array[WantedPoster], oldest first.
var _by_casino: Dictionary = {}
var _next_id: int = 1


## Prints a poster of a copy of `outfit` in a casino and returns it (null for a
## null outfit). See the class doc for duplicates.
func print_poster(casino_id: StringName, pid: int, outfit: Outfit) -> WantedPoster:
	if outfit == null:
		return null
	for existing: WantedPoster in _list(casino_id):
		if existing.pid == pid and existing.defaced_slots.is_empty() and existing.outfit.equals(outfit):
			return existing
	var poster := WantedPoster.new(_next_id, casino_id, pid, outfit)
	_next_id += 1
	if not _by_casino.has(casino_id):
		var fresh: Array[WantedPoster] = []
		_by_casino[casino_id] = fresh
	_list(casino_id).append(poster)
	poster_printed.emit(poster)
	return poster


## Posters up in a casino, oldest first. A new array: changing it doesn't
## change the board.
func posters_in(casino_id: StringName) -> Array[WantedPoster]:
	var out: Array[WantedPoster] = []
	out.assign(_list(casino_id))
	return out


## Every poster on the board, in id order.
func all_posters() -> Array[WantedPoster]:
	var out: Array[WantedPoster] = []
	for casino_id: StringName in _by_casino:
		out.append_array(_list(casino_id))
	out.sort_custom(func(a: WantedPoster, b: WantedPoster) -> bool: return a.id < b.id)
	return out


## Posters printed for one player, in any casino, in id order.
func posters_for(pid: int) -> Array[WantedPoster]:
	var out: Array[WantedPoster] = []
	for poster: WantedPoster in all_posters():
		if poster.pid == pid:
			out.append(poster)
	return out


## Number of posters up in a casino, or on the whole board for &"".
func count(casino_id: StringName = &"") -> int:
	if casino_id == &"":
		return all_posters().size()
	return _list(casino_id).size()


func get_poster(poster_id: int) -> WantedPoster:
	for casino_id: StringName in _by_casino:
		for poster: WantedPoster in _list(casino_id):
			if poster.id == poster_id:
				return poster
	return null


## The poster in this casino that recognizes `outfit`, or null. With several,
## the one matching the most readable slots wins, then the newest.
func matching_poster(casino_id: StringName, outfit: Outfit) -> WantedPoster:
	if outfit == null:
		return null
	var best: WantedPoster = null
	var best_count := -1
	for poster: WantedPoster in _list(casino_id):
		if not poster.matches(outfit):
			continue
		var n: int = poster.match_count(outfit)
		if n > best_count or (n == best_count and poster.id > best.id):
			best = poster
			best_count = n
	return best


## Removes a poster. Returns false if there is no such poster.
func tear_down(poster_id: int) -> bool:
	for casino_id: StringName in _by_casino:
		var list: Array[WantedPoster] = _list(casino_id)
		for i in list.size():
			if list[i].id == poster_id:
				list.remove_at(i)
				poster_removed.emit(poster_id)
				return true
	return false


## Draws over one slot of a poster. Returns true if that slot was newly
## defaced; false for an unknown poster, an invalid slot or a slot that was
## already defaced (idempotent).
func deface(poster_id: int, slot: int) -> bool:
	var poster: WantedPoster = get_poster(poster_id)
	if poster == null or not poster.deface(slot):
		return false
	poster_defaced.emit(poster_id, slot)
	return true


## {"next_id": int, "posters": [WantedPoster.to_dict(), ...]} in id order.
func to_dict() -> Dictionary:
	var posters: Array = []
	for poster: WantedPoster in all_posters():
		posters.append(poster.to_dict())
	return {"next_id": _next_id, "posters": posters}


## Reads to_dict() output (also after a JSON round-trip). The next id stays
## above every loaded poster id.
static func from_dict(d: Dictionary) -> PosterBoard:
	var board := PosterBoard.new()
	var posters: Variant = d.get("posters", [])
	if posters is Array:
		for item: Variant in posters:
			if not item is Dictionary:
				continue
			var poster: WantedPoster = WantedPoster.from_dict(item)
			if not board._by_casino.has(poster.casino_id):
				var fresh: Array[WantedPoster] = []
				board._by_casino[poster.casino_id] = fresh
			board._list(poster.casino_id).append(poster)
			board._next_id = maxi(board._next_id, poster.id + 1)
	board._next_id = maxi(board._next_id, int(d.get("next_id", 1)))
	return board


## The board's own array for a casino (empty, unshared array if none).
func _list(casino_id: StringName) -> Array[WantedPoster]:
	if _by_casino.has(casino_id):
		return _by_casino[casino_id]
	var empty: Array[WantedPoster] = []
	return empty
