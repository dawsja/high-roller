class_name ProfileStore
extends RefCounted
## Loads and saves a Profile as versioned JSON (user://profile.json by
## default): {"format": FORMAT, "version": VERSION, "profile": {...}}.
##
## Corrupt-file safe: a file that isn't a readable profile (not UTF-8, not
## JSON, the wrong shape) is moved aside to <path>.corrupt and a fresh profile
## is used, so a bad file never stops the game or gets silently overwritten.
## A save writes a temp file next to it and then replaces the file, so a
## crash mid-save leaves the old one. Older versions are migrated on load (_migrate); files
## from a newer build load what this build understands.
##
## Steam cloud (later): ProfileStore.cloud is the hook. Set it to a Cloud
## whose read/write go to Steam Remote Storage; load then merges the cloud
## copy in (Profile.merge: the higher counters win, unlocks and boards
## combine) and save writes both. The base Cloud is a stub that is never
## available, so today everything stays local.

const DEFAULT_PATH := "user://profile.json"
const FORMAT := "high_roller_profile"
const VERSION := 1
## File name of the profile in the cloud.
const CLOUD_FILE := "profile.json"


## A remote copy of the profile. Override all three (e.g. with GodotSteam's
## Steam.fileRead / fileWrite) and assign an instance to ProfileStore.cloud.
class Cloud:
	extends RefCounted

	func is_available() -> bool:
		return false

	## The file's text, or "" when there is none.
	func read(_file_name: String) -> String:
		return ""

	func write(_file_name: String, _text: String) -> bool:
		return false


## The cloud copy, or null (local only).
static var cloud: Cloud = null

var path: String = DEFAULT_PATH
## Why the last load_profile() started a fresh profile from a bad file
## ("" when it didn't).
var last_error: String = ""
## Where the last load_profile() moved a corrupt file ("" when it didn't).
var corrupt_path: String = ""


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


## The saved profile (merged with the cloud copy when there is one); a fresh
## one when there is no file or it was corrupt (see last_error).
func load_profile() -> Profile:
	last_error = ""
	corrupt_path = ""
	var profile: Profile = null
	if FileAccess.file_exists(path):
		profile = parse_bytes(FileAccess.get_file_as_bytes(path))
		if profile == null:
			last_error = "unreadable profile"
			_move_aside()
	if profile == null:
		profile = Profile.new()
	if cloud != null and cloud.is_available():
		var remote := parse(cloud.read(CLOUD_FILE))
		if remote != null:
			profile.merge(remote)
	return profile


## Writes the profile (and the cloud copy). False if the local write failed.
func save(profile: Profile) -> bool:
	if profile == null:
		return false
	var text := serialize(profile)
	var ok := _write_local(text)
	if cloud != null and cloud.is_available():
		cloud.write(CLOUD_FILE, text)
	return ok


## Deletes the saved file (a fresh start next load).
func erase() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func serialize(profile: Profile) -> String:
	return JSON.stringify({"format": FORMAT, "version": VERSION, "profile": profile.to_dict()}, "\t")


## A Profile from serialize() text, or null if the text isn't one.
static func parse(text: String) -> Profile:
	if text.strip_edges() == "":
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	var data: Variant = json.data
	if not data is Dictionary:
		return null
	var d: Dictionary = data
	if str(d.get("format", "")) != FORMAT:
		return null
	var version: Variant = d.get("version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return null
	var body: Variant = d.get("profile")
	if not body is Dictionary:
		return null
	return Profile.from_dict(_migrate(body, int(version)))


## parse() for raw file bytes; null for bytes that aren't valid UTF-8 (checked
## first, so a garbage file never reaches the engine's string decoder).
static func parse_bytes(bytes: PackedByteArray) -> Profile:
	if bytes.is_empty() or not is_utf8(bytes):
		return null
	return parse(bytes.get_string_from_utf8())


## True if the bytes are well-formed UTF-8 without NUL bytes.
static func is_utf8(bytes: PackedByteArray) -> bool:
	var i := 0
	var n := bytes.size()
	while i < n:
		var b: int = bytes[i]
		var extra := 0
		if b == 0:
			return false
		elif b < 0x80:
			extra = 0
		elif b >= 0xC2 and b <= 0xDF:
			extra = 1
		elif b >= 0xE0 and b <= 0xEF:
			extra = 2
		elif b >= 0xF0 and b <= 0xF4:
			extra = 3
		else:
			return false
		if i + extra >= n and extra > 0:
			return false
		for k in range(1, extra + 1):
			if (bytes[i + k] & 0xC0) != 0x80:
				return false
		i += extra + 1
	return true


## Upgrades an older file's profile dictionary to VERSION (none needed yet).
static func _migrate(body: Dictionary, _from_version: int) -> Dictionary:
	return body


func _write_local(text: String) -> bool:
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	# Per process, so two local co-op instances never write the same temp file.
	var tmp := "%s.%d.tmp" % [path, OS.get_process_id()]
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(tmp, path) == OK:
		return true
	# Some platforms won't rename over an existing file.
	DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


func _move_aside() -> void:
	var to := path + ".corrupt"
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	if DirAccess.rename_absolute(path, to) == OK:
		corrupt_path = to
