class_name Keypad3D
extends Node3D
## A numeric keypad of KeyButton3D keys laid out like a phone:
##   1 2 3 / 4 5 6 / 7 8 9 / C 0 000
## on the local XZ plane (+Y up; the "1 2 3" row at -Z, away from the
## player). Cream keys with dark legends, a red C. Emits `key` with the
## legend text ("0".."9", "C", "000") on every press.

## A key was pressed (any player).
signal key(text: String)
## Same, with the pressing player's pid.
signal key_by(text: String, user_pid: int)

const LAYOUT: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "000"]
const COLUMNS := 3

var key_size: Vector3 = Vector3(0.066, 0.034, 0.066)
var pitch: float = 0.08
var keys: Dictionary = {}  # legend -> KeyButton3D


func setup(p_key_size: Vector3 = Vector3(0.066, 0.034, 0.066), p_pitch: float = 0.08,
		key_color: Color = DiegeticKit.KEY_CREAM, clear_color: Color = DiegeticKit.KEY_RED) -> Keypad3D:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	keys.clear()
	key_size = p_key_size
	pitch = maxf(p_pitch, maxf(p_key_size.x, p_key_size.z))
	name = "Keypad" if name == "" else name
	var rows := LAYOUT.size() / COLUMNS
	for i in LAYOUT.size():
		var text: String = LAYOUT[i]
		var col := i % COLUMNS
		var row := i / COLUMNS
		var k := KeyButton3D.new()
		k.setup(text, clear_color if text == "C" else key_color, key_size, StringName(text))
		k.position = Vector3((float(col) - float(COLUMNS - 1) * 0.5) * pitch, 0.0, (float(row) - float(rows - 1) * 0.5) * pitch)
		k.pressed.connect(_on_key_pressed.bind(text))
		add_child(k)
		keys[text] = k
	return self


## Footprint on XZ (metres).
func get_size() -> Vector2:
	return Vector2(float(COLUMNS) * pitch, float(LAYOUT.size() / COLUMNS) * pitch)


func get_key(text: String) -> KeyButton3D:
	return keys.get(text, null)


## Presses a key as player `user_pid` (bots, tests).
func press_key(text: String, user_pid: int) -> void:
	var k := get_key(text)
	if k != null:
		k.press(user_pid)


func set_keys_enabled(on: bool) -> void:
	for k: KeyButton3D in keys.values():
		k.enabled = on


func _on_key_pressed(user_pid: int, text: String) -> void:
	key.emit(text)
	key_by.emit(text, user_pid)
