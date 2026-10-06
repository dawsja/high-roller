class_name Profile
extends RefCounted
## One player's progression on this machine (design doc "Scoring and
## progression"): lifetime banked chips, the cosmetic unlocks they bought
## (Unlocks), finished runs, best scores and a local leaderboard per crew
## size. Pure data; ProfileStore (world layer) loads and saves it. In co-op
## every peer keeps its own profile.
##
## Leaderboard entries are plain dictionaries: {score, top_banked,
## top_seconds, elapsed_seconds, visits, crew (Array of names), date (String),
## serial}. `serial` numbers entries in the order they were posted; ties on
## score keep the older entry ahead.

const VERSION := 1
## Entries kept on each crew-size board.
const LEADERBOARD_SIZE := 10
const MAX_CREW := 4

var lifetime_banked: int = 0
## Finished runs (practice runs included).
var runs: int = 0
## Best posted score over every crew size.
var best_score: int = 0
## Unlock ids in the order they were unlocked.
var unlocked: Array[StringName] = []
## Unlocked ids the player hasn't looked at yet (the unlocks screen marks them NEW).
var unseen: Array[StringName] = []
## crew size (int, 1..MAX_CREW) -> Array of entries, best first.
var leaderboards: Dictionary = {}
## Serial of the last posted entry (0 = none yet).
var last_serial: int = 0


func _init() -> void:
	refresh_unlocks()
	unseen.clear()


## Adds banked chips (non-positive amounts are ignored) and returns the ids
## this unlocked, in unlock order.
func add_banked(amount: int) -> Array[StringName]:
	if amount <= 0:
		var none: Array[StringName] = []
		return none
	lifetime_banked += amount
	return refresh_unlocks()


## Unlocks every TABLE row at or below lifetime_banked that isn't unlocked
## yet (they also go to `unseen`). Returns them.
func refresh_unlocks() -> Array[StringName]:
	var fresh: Array[StringName] = []
	for id: StringName in Unlocks.unlocked_at(lifetime_banked):
		if not unlocked.has(id):
			unlocked.append(id)
			fresh.append(id)
			if Unlocks.threshold(id) > 0:
				unseen.append(id)
	return fresh


func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)


func unlocked_pieces() -> Array[StringName]:
	return _unlocked_of(Unlocks.KIND_PIECE)


func unlocked_emotes() -> Array[StringName]:
	return _unlocked_of(Unlocks.KIND_EMOTE)


func unlocked_name_packs() -> Array[StringName]:
	return _unlocked_of(Unlocks.KIND_NAME_PACK)


## Chips still to bank before `id` unlocks (0 once unlocked or reached).
func chips_to_unlock(id: StringName) -> int:
	var at := Unlocks.threshold(id)
	if at < 0 or is_unlocked(id):
		return 0
	return maxi(0, at - lifetime_banked)


func mark_seen(id: StringName = &"") -> void:
	if id == &"":
		unseen.clear()
	else:
		unseen.erase(id)


## Records a finished run. Practice runs only count towards `runs`. Otherwise
## the score goes on the board for `crew_size` (clamped to 1..MAX_CREW);
## `entry` adds the other entry keys. Returns the 1-based rank it took on
## that board, or 0 if it didn't make the top LEADERBOARD_SIZE.
func record_run(score: int, crew_size: int, entry: Dictionary = {}, practice: bool = false) -> int:
	runs += 1
	if practice:
		return 0
	return post_score(score, crew_size, entry)


## Puts a score on the crew-size board (best first, older first on ties,
## trimmed to LEADERBOARD_SIZE). Returns its 1-based rank, or 0 if it fell
## off the board.
func post_score(score: int, crew_size: int, entry: Dictionary = {}) -> int:
	var size := clampi(crew_size, 1, MAX_CREW)
	last_serial += 1
	var e := _clean_entry(entry)
	e["score"] = maxi(0, score)
	e["serial"] = last_serial
	best_score = maxi(best_score, int(e["score"]))
	var board: Array = leaderboards.get(size, [])
	var at := board.size()
	for i in board.size():
		if int((board[i] as Dictionary)["score"]) < int(e["score"]):
			at = i
			break
	board.insert(at, e)
	if board.size() > LEADERBOARD_SIZE:
		board.resize(LEADERBOARD_SIZE)
	leaderboards[size] = board
	return at + 1 if at < LEADERBOARD_SIZE else 0


## The board for a crew size, best first (a copy).
func leaderboard(crew_size: int) -> Array:
	return (leaderboards.get(clampi(crew_size, 1, MAX_CREW), []) as Array).duplicate(true)


## Best score on a crew-size board (0 when empty).
func best_for(crew_size: int) -> int:
	var board: Array = leaderboards.get(clampi(crew_size, 1, MAX_CREW), [])
	return int((board[0] as Dictionary)["score"]) if not board.is_empty() else 0


## Where `score` would rank on a crew-size board (1-based; 0 if it would not
## make the board). Ties rank below the entries already there.
func rank_for(score: int, crew_size: int) -> int:
	var board: Array = leaderboards.get(clampi(crew_size, 1, MAX_CREW), [])
	var at := board.size()
	for i in board.size():
		if int((board[i] as Dictionary)["score"]) < score:
			at = i
			break
	return at + 1 if at < LEADERBOARD_SIZE else 0


## Folds in another copy of this player's profile (e.g. the Steam cloud's):
## the higher counters win, unlocks and board entries are combined.
func merge(other: Profile) -> void:
	if other == null:
		return
	lifetime_banked = maxi(lifetime_banked, other.lifetime_banked)
	runs = maxi(runs, other.runs)
	best_score = maxi(best_score, other.best_score)
	for id: StringName in other.unlocked:
		if not unlocked.has(id):
			unlocked.append(id)
	for id: StringName in other.unseen:
		if not unseen.has(id):
			unseen.append(id)
	for size: int in other.leaderboards:
		var board: Array = leaderboards.get(size, [])
		var keys: Dictionary = {}
		for e: Dictionary in board:
			keys[_entry_key(e)] = true
		for e: Dictionary in other.leaderboards[size]:
			if not keys.has(_entry_key(e)):
				board.append(e.duplicate(true))
		leaderboards[size] = _sorted_board(board)
	last_serial = maxi(last_serial, other.last_serial)
	refresh_unlocks()


## Plain data for JSON: string keys, ids as strings.
func to_dict() -> Dictionary:
	var boards: Dictionary = {}
	for size: int in leaderboards:
		boards[str(size)] = (leaderboards[size] as Array).duplicate(true)
	return {
		"version": VERSION,
		"lifetime_banked": lifetime_banked,
		"runs": runs,
		"best_score": best_score,
		"unlocked": _strings(unlocked),
		"unseen": _strings(unseen),
		"leaderboards": boards,
		"last_serial": last_serial,
	}


## Reads to_dict() output (also after a JSON round trip). Bad or missing
## fields fall back to their defaults; boards are re-sorted and trimmed, and
## anything the chips already pay for is unlocked.
static func from_dict(d: Dictionary) -> Profile:
	var p := Profile.new()
	p.unlocked.clear()
	p.unseen.clear()
	p.lifetime_banked = maxi(0, _int(d.get("lifetime_banked", 0)))
	p.runs = maxi(0, _int(d.get("runs", 0)))
	p.best_score = maxi(0, _int(d.get("best_score", 0)))
	p.last_serial = maxi(0, _int(d.get("last_serial", 0)))
	for key: String in ["unlocked", "unseen"]:
		var list: Variant = d.get(key, [])
		if not list is Array:
			continue
		var target: Array[StringName] = p.unlocked if key == "unlocked" else p.unseen
		for id: Variant in list:
			if (id is String or id is StringName) and Unlocks.has(StringName(str(id))) and not target.has(StringName(str(id))):
				target.append(StringName(str(id)))
	var boards: Variant = d.get("leaderboards", {})
	if boards is Dictionary:
		for key: Variant in boards:
			var size := _int(key)
			var list: Variant = boards[key]
			if size < 1 or size > MAX_CREW or not list is Array:
				continue
			var board: Array = []
			for e: Variant in list:
				if e is Dictionary and _is_number((e as Dictionary).get("score")):
					var clean := _clean_entry(e)
					clean["score"] = maxi(0, _int((e as Dictionary)["score"]))
					clean["serial"] = maxi(0, _int((e as Dictionary).get("serial", 0)))
					p.last_serial = maxi(p.last_serial, int(clean["serial"]))
					p.best_score = maxi(p.best_score, int(clean["score"]))
					board.append(clean)
			if not board.is_empty():
				p.leaderboards[size] = _sorted_board(board)
	p.unseen.assign(p.unseen.filter(func(id: StringName) -> bool: return p.unlocked.has(id)))
	p.refresh_unlocks()
	return p


func _unlocked_of(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in unlocked:
		if Unlocks.kind_of(id) == kind:
			out.append(id)
	return out


## Known entry keys with plain types; the caller sets score and serial.
static func _clean_entry(e: Dictionary) -> Dictionary:
	var crew: Array = []
	var raw_crew: Variant = e.get("crew", [])
	if raw_crew is Array:
		for n: Variant in raw_crew:
			crew.append(str(n))
	return {
		"score": 0,
		"top_banked": maxi(0, _int(e.get("top_banked", 0))),
		"top_seconds": maxf(0.0, _float(e.get("top_seconds", 0.0))),
		"elapsed_seconds": maxf(0.0, _float(e.get("elapsed_seconds", 0.0))),
		"visits": maxi(0, _int(e.get("visits", 0))),
		"crew": crew,
		"date": str(e.get("date", "")),
		"serial": 0,
	}


## Best first; equal scores in posting order.
static func _sorted_board(board: Array) -> Array:
	var out := board.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		return int(a["serial"]) < int(b["serial"]))
	if out.size() > LEADERBOARD_SIZE:
		out.resize(LEADERBOARD_SIZE)
	return out


static func _entry_key(e: Dictionary) -> String:
	return "%d|%s|%s" % [int(e.get("score", 0)), str(e.get("date", "")), ",".join(PackedStringArray(e.get("crew", [])))]


static func _strings(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id: StringName in ids:
		out.append(String(id))
	return out


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


static func _int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return int(v)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(v)
			if s.is_valid_int():
				return s.to_int()
			return int(s.to_float()) if s.is_valid_float() else 0
	return 0


static func _float(v: Variant) -> float:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT:
			return float(v)
		TYPE_STRING, TYPE_STRING_NAME:
			var s := str(v)
			return s.to_float() if s.is_valid_float() else 0.0
	return 0.0
