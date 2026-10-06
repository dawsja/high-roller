extends TestCase
## Profile (pure progression data), the Unlocks table and ProfileStore
## (versioned JSON on disk, corrupt-file recovery, the cloud hook).

## Records what a cloud copy would hold (stands in for Steam Remote Storage).
class MemoryCloud extends ProfileStore.Cloud:
	var files: Dictionary = {}

	func is_available() -> bool:
		return true

	func read(file_name: String) -> String:
		return str(files.get(file_name, ""))

	func write(file_name: String, text: String) -> bool:
		files[file_name] = text
		return true


var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_profile_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(_dir)
	ProfileStore.cloud = null


func after_each() -> void:
	ProfileStore.cloud = null
	if _dir != "" and DirAccess.dir_exists_absolute(_dir):
		for f: String in DirAccess.get_files_at(_dir):
			DirAccess.remove_absolute(_dir.path_join(f))
		DirAccess.remove_absolute(_dir)


func _path() -> String:
	return _dir.path_join("profile.json")


func _write(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _entry(crew: Array = ["Ace"], date: String = "2026-10-06 12:00:00") -> Dictionary:
	return {"top_banked": 100, "top_seconds": 90.0, "elapsed_seconds": 600.0, "visits": 3, "crew": crew, "date": date}


# --- Unlocks table ---------------------------------------------------------------

func test_unlock_table_has_the_promised_content() -> void:
	var pieces := Unlocks.ids_of(Unlocks.KIND_PIECE)
	var emotes := Unlocks.ids_of(Unlocks.KIND_EMOTE)
	var packs := Unlocks.ids_of(Unlocks.KIND_NAME_PACK)
	assert_gte(pieces.size(), 12, "at least 12 outfit pieces")
	var slots := {}
	for id: StringName in pieces:
		assert_true(OutfitCatalog.is_unlockable(id), "%s is a locked catalog piece" % id)
		slots[OutfitCatalog.slot_of(id)] = true
	assert_eq(slots.size(), HR.OUTFIT_SLOT_COUNT, "pieces across every slot")
	var earned := emotes.filter(func(id: StringName) -> bool: return Unlocks.threshold(id) > 0)
	assert_gte(earned.size(), 4, "at least 4 emotes to earn")
	for id: StringName in emotes:
		assert_has(CharacterModel.EMOTES, id)
		assert_has(CharacterModel.POSES, id)
	assert_eq(packs.size(), 3, "three ID name packs")
	for id: StringName in packs:
		assert_true(IdGenerator.has_name_pack(id), String(id))
	for id: StringName in OutfitCatalog.locked_pieces():
		assert_true(Unlocks.has(id), "%s is in the unlock table" % id)


func test_unlock_thresholds_are_sorted_and_unique() -> void:
	var last := -1
	var seen := {}
	for row: Dictionary in Unlocks.TABLE:
		assert_gte(int(row["at"]), last, "sorted by threshold at %s" % row["id"])
		last = int(row["at"])
		assert_false(seen.has(row["id"]), "duplicate %s" % row["id"])
		seen[row["id"]] = true
		assert_ne(Unlocks.display_name(row["id"]), "", String(row["id"]))
	assert_eq(Unlocks.threshold(&"wave"), 0, "the starter emote is free")
	assert_eq(Unlocks.threshold(&"no_such_unlock"), -1)
	assert_eq(Unlocks.kind_of(&"propeller_beanie"), Unlocks.KIND_PIECE)
	assert_eq(Unlocks.kind_label(&"propeller_beanie"), "Hat")
	assert_eq(Unlocks.display_name(&"space_age"), "Space Age")
	assert_eq(Unlocks.display_name(&"chip_flip"), "Chip Flip")


func test_unlocked_at_crossed_and_next() -> void:
	assert_eq(Unlocks.unlocked_at(0), [&"wave"] as Array[StringName])
	assert_eq(Unlocks.unlocked_at(2500).size(), 3, "wave, shrug, propeller beanie")
	assert_eq(Unlocks.crossed(0, 999).size(), 0)
	assert_eq(Unlocks.crossed(999, 1000), [&"shrug"] as Array[StringName], "the threshold itself unlocks")
	assert_eq(Unlocks.crossed(1000, 4000), [&"propeller_beanie", &"bell_bottoms"] as Array[StringName])
	assert_eq(Unlocks.next_unlock(0)["id"], &"shrug")
	assert_eq(Unlocks.next_unlock(1000)["id"], &"propeller_beanie")
	var last: Dictionary = Unlocks.TABLE.back()
	assert_true(Unlocks.next_unlock(int(last["at"])).is_empty(), "nothing left")


# --- Profile: unlocks ---------------------------------------------------------------

func test_fresh_profile_has_only_the_starter_emote() -> void:
	var p := Profile.new()
	assert_eq(p.lifetime_banked, 0)
	assert_eq(p.unlocked, [&"wave"] as Array[StringName])
	assert_eq(p.unlocked_emotes(), [&"wave"] as Array[StringName])
	assert_true(p.unlocked_pieces().is_empty())
	assert_true(p.unlocked_name_packs().is_empty())
	assert_true(p.unseen.is_empty(), "the starter isn't news")


func test_banked_chips_unlock_at_thresholds() -> void:
	var p := Profile.new()
	assert_true(p.add_banked(999).is_empty())
	assert_false(p.is_unlocked(&"shrug"))
	assert_eq(p.chips_to_unlock(&"shrug"), 1)
	assert_eq(p.add_banked(1), [&"shrug"] as Array[StringName], "exactly at the threshold")
	assert_true(p.is_unlocked(&"shrug"))
	assert_eq(p.chips_to_unlock(&"shrug"), 0)
	assert_true(p.add_banked(0).is_empty())
	assert_true(p.add_banked(-500).is_empty(), "negative amounts are ignored")
	assert_eq(p.lifetime_banked, 1000)
	var fresh := p.add_banked(9000)
	assert_eq(fresh, [&"propeller_beanie", &"bell_bottoms", &"retro_3d_glasses", &"fuzzy_dice", &"high_seas"] as Array[StringName], "one big cash-out unlocks several, in order")
	assert_eq(p.lifetime_banked, 10000)
	assert_has(p.unlocked_pieces(), &"fuzzy_dice")
	assert_eq(p.unlocked_name_packs(), [&"high_seas"] as Array[StringName])
	assert_eq(p.unlocked_emotes(), [&"wave", &"shrug"] as Array[StringName])
	assert_eq(p.unseen.size(), 6, "new unlocks are unseen")
	p.mark_seen(&"shrug")
	assert_false(p.unseen.has(&"shrug"))
	p.mark_seen()
	assert_true(p.unseen.is_empty())
	p.add_banked(10_000_000)
	assert_eq(p.unlocked.size(), Unlocks.TABLE.size(), "everything eventually")


# --- Profile: leaderboards ----------------------------------------------------------

func test_leaderboard_orders_best_first_and_ties_keep_the_older_entry() -> void:
	var p := Profile.new()
	assert_eq(p.post_score(500, 1, _entry(["A"])), 1)
	assert_eq(p.post_score(900, 1, _entry(["B"])), 1, "a better score goes on top")
	assert_eq(p.post_score(700, 1, _entry(["C"])), 2)
	assert_eq(p.post_score(700, 1, _entry(["D"])), 3, "a tie ranks below the older entry")
	var board := p.leaderboard(1)
	var scores: Array = board.map(func(e: Dictionary) -> int: return int(e["score"]))
	assert_eq(scores, [900, 700, 700, 500])
	assert_eq(board[1]["crew"], ["C"])
	assert_eq(board[2]["crew"], ["D"])
	assert_eq(p.best_for(1), 900)
	assert_eq(p.best_score, 900)
	assert_eq(int(board[0]["serial"]), 2, "serials count postings")
	assert_eq(p.last_serial, 4)
	assert_eq(p.rank_for(800, 1), 2)
	assert_eq(p.rank_for(700, 1), 4, "ties rank below")


func test_leaderboard_trims_per_crew_size() -> void:
	var p := Profile.new()
	for i in Profile.LEADERBOARD_SIZE:
		p.post_score(1000 + i * 10, 2, _entry(["A", "B"]))
	assert_eq(p.leaderboard(2).size(), Profile.LEADERBOARD_SIZE)
	assert_eq(p.post_score(5, 2, _entry()), 0, "too low for a full board")
	assert_eq(p.leaderboard(2).size(), Profile.LEADERBOARD_SIZE, "trimmed")
	assert_eq(int(p.leaderboard(2).back()["score"]), 1000, "the old last place stays")
	assert_eq(p.post_score(1095, 2, _entry()), 1)
	assert_eq(p.leaderboard(2).size(), Profile.LEADERBOARD_SIZE)
	assert_eq(int(p.leaderboard(2).back()["score"]), 1010, "the last place fell off")
	assert_eq(p.rank_for(1, 2), 0)
	assert_true(p.leaderboard(1).is_empty(), "boards are per crew size")
	assert_eq(p.best_for(3), 0)
	assert_eq(p.post_score(50, 0, _entry()), 1, "crew size clamps up to solo")
	assert_eq(p.leaderboard(1).size(), 1)
	p.post_score(60, 9, _entry())
	assert_eq(p.leaderboard(Profile.MAX_CREW).size(), 1, "and down to the largest crew")
	p.leaderboard(1).clear()
	assert_eq(p.leaderboard(1).size(), 1, "leaderboard() returns a copy")


func test_record_run_counts_runs_and_skips_practice() -> void:
	var p := Profile.new()
	assert_eq(p.record_run(1234, 1, _entry(), true), 0, "practice isn't posted")
	assert_eq(p.runs, 1)
	assert_true(p.leaderboard(1).is_empty())
	assert_eq(p.record_run(1234, 3, _entry(["A", "B", "C"])), 1)
	assert_eq(p.runs, 2)
	assert_eq(p.leaderboard(3).size(), 1)
	assert_eq(p.record_run(-50, 3, _entry()), 2, "negative scores post as 0")
	assert_eq(int(p.leaderboard(3)[1]["score"]), 0)


# --- Profile: data ------------------------------------------------------------------

func test_round_trip_through_json() -> void:
	var p := Profile.new()
	p.add_banked(26_000)
	p.mark_seen(&"shrug")
	p.record_run(4321, 1, _entry(["You"]))
	p.record_run(9999, 2, _entry(["Ace", "Bea"]))
	p.record_run(10, 1, _entry(), true)
	var text := JSON.stringify(p.to_dict())
	var back := Profile.from_dict(JSON.parse_string(text))
	assert_eq(back.lifetime_banked, 26_000)
	assert_eq(back.runs, 3)
	assert_eq(back.best_score, 9999)
	assert_eq(back.unlocked, p.unlocked)
	assert_eq(back.unseen, p.unseen)
	assert_false(back.unseen.has(&"shrug"))
	assert_eq(back.last_serial, p.last_serial)
	assert_eq(back.leaderboard(1), p.leaderboard(1))
	assert_eq(back.leaderboard(2), p.leaderboard(2))
	assert_eq(back.leaderboard(2)[0]["crew"], ["Ace", "Bea"])
	assert_eq(typeof(back.leaderboard(1)[0]["score"]), TYPE_INT, "numbers come back as ints")


func test_from_dict_tolerates_bad_fields() -> void:
	var p := Profile.from_dict({
		"lifetime_banked": "2600",
		"runs": -4,
		"unlocked": ["shrug", "not_an_unlock", 7, "shrug"],
		"unseen": ["viking_helmet"],
		"leaderboards": {"1": [{"score": 50.0}, "junk", {"no_score": true}], "9": [{"score": 1}], "x": 5},
	})
	assert_eq(p.lifetime_banked, 2600)
	assert_eq(p.runs, 0)
	assert_true(p.is_unlocked(&"wave"), "starter")
	assert_true(p.is_unlocked(&"shrug"))
	assert_true(p.is_unlocked(&"propeller_beanie"), "what the chips pay for is unlocked")
	assert_false(p.is_unlocked(&"not_an_unlock"))
	assert_false(p.unseen.has(&"viking_helmet"), "unseen only lists unlocked ids")
	assert_eq(p.leaderboard(1).size(), 1)
	assert_eq(int(p.leaderboard(1)[0]["score"]), 50)
	assert_true(p.leaderboard(Profile.MAX_CREW).is_empty(), "out-of-range crew sizes are dropped")
	var empty := Profile.from_dict({})
	assert_eq(empty.unlocked, [&"wave"] as Array[StringName])


func test_merge_keeps_the_best_of_both() -> void:
	var a := Profile.new()
	a.add_banked(5000)
	a.record_run(300, 1, _entry(["A"], "d1"))
	var b := Profile.new()
	b.add_banked(14_000)
	b.record_run(700, 1, _entry(["B"], "d2"))
	b.record_run(300, 1, _entry(["A"], "d1"))
	a.merge(b)
	assert_eq(a.lifetime_banked, 14_000)
	assert_true(a.is_unlocked(&"polka_dot_shirt"))
	assert_eq(a.runs, 2)
	var scores: Array = a.leaderboard(1).map(func(e: Dictionary) -> int: return int(e["score"]))
	assert_eq(scores, [700, 300], "the same entry isn't doubled")


# --- ProfileStore ---------------------------------------------------------------------

func test_store_round_trip() -> void:
	var store := ProfileStore.new(_path())
	var fresh := store.load_profile()
	assert_eq(fresh.lifetime_banked, 0, "no file: a fresh profile")
	assert_eq(store.last_error, "")
	fresh.add_banked(3000)
	fresh.record_run(2000, 1, _entry())
	assert_true(store.save(fresh))
	assert_true(FileAccess.file_exists(_path()))
	assert_eq(DirAccess.get_files_at(_dir).size(), 1, "no temp file left behind")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path()))
	assert_eq(data["format"], ProfileStore.FORMAT)
	assert_eq(int(data["version"]), ProfileStore.VERSION, "versioned")
	var back := ProfileStore.new(_path()).load_profile()
	assert_eq(back.lifetime_banked, 3000)
	assert_eq(back.unlocked, fresh.unlocked)
	assert_eq(back.leaderboard(1), fresh.leaderboard(1))
	back.add_banked(1)
	assert_true(store.save(back), "saves over the old file")
	assert_eq(ProfileStore.new(_path()).load_profile().lifetime_banked, 3001)


func test_store_recovers_from_corrupt_files() -> void:
	var cases := {
		"not json": "this is not a profile {{{".to_utf8_buffer(),
		"truncated": "{\"format\": \"high_roller_profile\", \"version\": 1, \"profile\": {\"lifetime".to_utf8_buffer(),
		"wrong shape": "[1, 2, 3]".to_utf8_buffer(),
		"wrong format": JSON.stringify({"format": "something_else", "version": 1, "profile": {}}).to_utf8_buffer(),
		"no version": JSON.stringify({"format": ProfileStore.FORMAT, "profile": {}}).to_utf8_buffer(),
		"empty": PackedByteArray(),
		"binary": PackedByteArray([0xff, 0xfe, 0x00, 0x13, 0xc3, 0x28, 0x80]),
	}
	for label: String in cases:
		_write(_path(), cases[label])
		var store := ProfileStore.new(_path())
		var p := store.load_profile()
		assert_not_null(p, label)
		assert_eq(p.lifetime_banked, 0, "%s: a fresh profile" % label)
		assert_ne(store.last_error, "", label)
		assert_eq(store.corrupt_path, _path() + ".corrupt", label)
		assert_true(FileAccess.file_exists(_path() + ".corrupt"), "%s: kept aside" % label)
		assert_false(FileAccess.file_exists(_path()), "%s: moved, not overwritten" % label)
		p.add_banked(1500)
		assert_true(store.save(p), "%s: saving works again" % label)
		var again := ProfileStore.new(_path())
		assert_eq(again.load_profile().lifetime_banked, 1500, label)
		assert_eq(again.last_error, "", label)
		DirAccess.remove_absolute(_path())


func test_store_accepts_utf8_names() -> void:
	var p := Profile.new()
	p.record_run(10, 2, _entry(["José", "Zoë"]))
	var store := ProfileStore.new(_path())
	assert_true(store.save(p))
	var back := ProfileStore.new(_path()).load_profile()
	assert_eq(back.leaderboard(2)[0]["crew"], ["José", "Zoë"])
	assert_true(ProfileStore.is_utf8("José".to_utf8_buffer()))
	assert_false(ProfileStore.is_utf8(PackedByteArray([0xc3])), "cut off mid-character")


func test_cloud_hook_merges_and_mirrors() -> void:
	var cloud := MemoryCloud.new()
	ProfileStore.cloud = cloud
	var store := ProfileStore.new(_path())
	var p := store.load_profile()
	p.add_banked(2000)
	store.save(p)
	assert_true(cloud.files.has(ProfileStore.CLOUD_FILE), "a save mirrors to the cloud")
	# Another machine banked more and wrote the cloud copy.
	var elsewhere := Profile.new()
	elsewhere.add_banked(20_000)
	elsewhere.record_run(5000, 1, _entry(["Remote"]))
	cloud.files[ProfileStore.CLOUD_FILE] = ProfileStore.serialize(elsewhere)
	var merged := ProfileStore.new(_path()).load_profile()
	assert_eq(merged.lifetime_banked, 20_000)
	assert_eq(merged.leaderboard(1).size(), 1)
	ProfileStore.cloud = ProfileStore.Cloud.new()
	assert_false(ProfileStore.cloud.is_available(), "the stub is never available")
	assert_eq(ProfileStore.new(_path()).load_profile().lifetime_banked, 2000, "local only with the stub")
