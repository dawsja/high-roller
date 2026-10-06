class_name BetConsole3D
extends Node3D
## The physical bet console every game is played from (ref: keypad console):
## a tilted dark panel with a neon trim holding, left to right, a Keypad3D,
## a Screen3D (Min / Max, the bet big, Pocket, a message line), a column of
## orange quick keys (MIN ½ ×2 MAX) with a red THROW toggle under them, and
## a big green main key (PLAY / SPIN / ROLL / DEAL) followed by any
## game-specific action keys (CASH OUT, HIT, STAND, HIGHER, ...).
##
## Bet entry: digits type a number (the first digit after a quick key or a
## play starts a new one), C clears, 000 multiplies by 1000; the bet never
## goes above min(max, pocket). The main key sends the bet clamped to
## [min, min(max, pocket)]. THROW arms losing on purpose for the next play
## (lit while armed, disarmed by the play).
##
## Presses go through `gate` (Callable(pid) -> String; "" lets it through,
## anything else is shown on the screen and refused) and are ignored while
## `locked` (a round animating). Purely a view + input device: it never
## talks to the sim; the GameMachine turns its signals into requests.
##
## Console space: origin at the bottom centre of the body, the player stands
## at +Z, the panel tilts up toward them. Key ids: &"0".."9", &"C", &"000",
## &"min", &"half", &"double", &"max", &"throw", &"main", plus action ids.

signal main_pressed(bet: int, throw: bool, pid: int)
signal action_pressed(id: StringName, pid: int)
signal bet_changed(bet: int)
## Any key got through the gate and the lock (sounds, hands, tests).
signal key_pressed(id: StringName, pid: int)
## A press was refused by the gate (`message` is on the screen).
signal refused(pid: int, message: String)

const QUICK_IDS: Array[StringName] = [&"min", &"half", &"double", &"max"]
const QUICK_LEGENDS := {&"min": "MIN", &"half": "½", &"double": "×2", &"max": "MAX"}
const MAX_DIGITS := 15
const MARGIN := 0.03
const GAP := 0.026
const FRONT_HEIGHT := 0.09
const DECK_THICKNESS := 0.014
const KEY_SIZE := Vector3(0.066, 0.034, 0.066)
const KEY_PITCH := 0.08
const SCREEN_WIDTH := 0.3
const QUICK_SIZE := Vector3(0.092, 0.03, 0.052)
const FAT_SIZE := Vector3(0.19, 0.05, 0.21)
const FAT_GAP := 0.028
const MESSAGE_SECONDS := 2.2

var bet: int = 0
var min_bet: int = 0
var max_bet: int = 0
var pocket: int = 0
var throw_armed: bool = false
var locked: bool = false
var main_label: String = "PLAY"
## Disarm THROW after every main press.
var disarm_after_play: bool = true
## Callable(pid: int) -> String: "" allows the press, else the refusal text.
var gate: Callable = Callable()
var tilt_degrees: float = 28.0

var deck: Node3D
var body_mesh: MeshInstance3D
var deck_plate: MeshInstance3D
var trim: MeshInstance3D
var keypad: Keypad3D
var screen: Screen3D
var main_key: KeyButton3D
var throw_key: KeyButton3D
var quick_keys: Dictionary = {}
var action_keys: Dictionary = {}
var stand: Node3D

var _action_order: Array[StringName] = []
var _fresh: bool = true
var _limits_known: bool = false
var _message: String = ""
var _message_color: Color = DiegeticKit.TEXT_INFO
var _status: String = ""
var _status_color: Color = DiegeticKit.TEXT_INFO
var _message_tween: Tween
var _size: Vector3 = Vector3.ZERO


func setup(p_main_label: String = "PLAY", main_color: Color = DiegeticKit.KEY_GREEN, p_tilt_degrees: float = 28.0) -> BetConsole3D:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	quick_keys.clear()
	action_keys.clear()
	_action_order.clear()
	main_label = p_main_label
	tilt_degrees = clampf(p_tilt_degrees, 0.0, 70.0)
	if name == "":
		name = "BetConsole"
	body_mesh = MeshInstance3D.new()
	body_mesh.name = "Body"
	add_child(body_mesh)
	deck = Node3D.new()
	deck.name = "Deck"
	add_child(deck)
	deck_plate = MeshInstance3D.new()
	deck_plate.name = "Plate"
	deck.add_child(deck_plate)
	trim = MeshInstance3D.new()
	trim.name = "Trim"
	deck.add_child(trim)
	keypad = Keypad3D.new()
	keypad.name = "Keypad"
	keypad.setup(KEY_SIZE, KEY_PITCH)
	deck.add_child(keypad)
	for text: String in keypad.keys:
		var k: KeyButton3D = keypad.keys[text]
		k.pressed.connect(_on_key.bind(StringName(text)))
	screen = Screen3D.new()
	screen.name = "Screen"
	deck.add_child(screen)
	for qid: StringName in QUICK_IDS:
		var q := _make_key(QUICK_LEGENDS[qid], DiegeticKit.KEY_ORANGE, QUICK_SIZE, qid)
		q.set_emission(0.18)
		quick_keys[qid] = q
	throw_key = _make_key("THROW", DiegeticKit.KEY_RED, QUICK_SIZE, &"throw")
	main_key = _make_key(main_label, main_color, FAT_SIZE, &"main")
	main_key.set_emission(0.12)
	_layout()
	_refresh_screen()
	return self


## Width, height and depth of the console body (m).
func get_size() -> Vector3:
	return _size


## The casino's limits and this player's pocket. The bet is re-clamped; the
## first call starts the bet at the minimum.
func set_limits(p_min: int, p_max: int, p_pocket: int) -> void:
	var first := not _limits_known
	min_bet = maxi(0, p_min)
	max_bet = maxi(min_bet, p_max)
	pocket = maxi(0, p_pocket)
	_limits_known = true
	if first:
		_set_bet(min_bet)
		_fresh = true
	elif bet > cap():
		_set_bet(cap())
	_refresh_screen()


func set_pocket(p_pocket: int) -> void:
	if _limits_known:
		set_limits(min_bet, max_bet, p_pocket)
	else:
		_set_pocket_only(p_pocket)


## The biggest bet allowed now: min(max, pocket), never below min.
func cap() -> int:
	if not _limits_known:
		return 999999999999999
	return maxi(min_bet, mini(max_bet, pocket))


## What the main key would send: the shown bet clamped to [min, cap()].
func get_bet() -> int:
	return clampi(bet, min_bet, cap())


## Sets the shown bet (clamped to [0, cap()]); the next digit starts fresh.
func set_bet(amount: int) -> void:
	_set_bet(clampi(amount, 0, cap()))
	_fresh = true
	_refresh_screen()


func set_locked(value: bool) -> void:
	locked = value


func is_locked() -> bool:
	return locked


func set_throw(armed: bool) -> void:
	throw_armed = armed
	if throw_key != null:
		throw_key.set_lit(armed)
	_refresh_screen()


## A transient line on the screen ("Occupied", "WIN +$50") for `seconds`
## (<= 0 keeps it until the next message), with a screen flash.
func show_message(text: String, color: Color = DiegeticKit.TEXT_INFO, seconds: float = MESSAGE_SECONDS) -> void:
	_message = text
	_message_color = color
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	if screen != null and text != "":
		screen.flash(color, 0.3, 0.28)
	if seconds > 0.0 and is_inside_tree():
		_message_tween = create_tween()
		_message_tween.tween_interval(seconds)
		_message_tween.tween_callback(clear_message)
	_refresh_screen()


func clear_message() -> void:
	_message = ""
	_refresh_screen()


func get_message() -> String:
	return _message


## A standing line shown whenever no message is up ("Pick HIGHER or LOWER").
func set_status(text: String, color: Color = DiegeticKit.TEXT_INFO) -> void:
	_status = text
	_status_color = color
	_refresh_screen()


## The line the screen's message row shows right now.
func message_line() -> String:
	return screen.get_line(3) if screen != null else ""


func set_main_label(text: String) -> void:
	main_label = text
	if main_key != null:
		main_key.set_legend(text)


func set_main_color(color: Color) -> void:
	if main_key != null:
		main_key.set_color(color)


## A fat game key after the main key (CASH OUT, HIT, STAND, HIGHER...).
## Pressing it emits action_pressed(id, pid). Re-adding an id relabels it.
func add_action_key(id: StringName, label: String, color: Color = DiegeticKit.KEY_YELLOW) -> KeyButton3D:
	if action_keys.has(id):
		var existing: KeyButton3D = action_keys[id]
		existing.set_legend(label)
		existing.set_color(color)
		return existing
	var k := _make_key(label, color, Vector3(FAT_SIZE.x * 0.9, FAT_SIZE.y, FAT_SIZE.z), id)
	k.set_emission(0.12)
	action_keys[id] = k
	_action_order.append(id)
	_layout()
	return k


func remove_action_key(id: StringName) -> void:
	if not action_keys.has(id):
		return
	var k: KeyButton3D = action_keys[id]
	action_keys.erase(id)
	_action_order.erase(id)
	k.queue_free()
	deck.remove_child(k)
	_layout()


func set_action_enabled(id: StringName, on: bool) -> void:
	var k := get_key(id)
	if k != null:
		k.enabled = on


func get_key(id: StringName) -> KeyButton3D:
	if id == &"main":
		return main_key
	if id == &"throw":
		return throw_key
	if quick_keys.has(id):
		return quick_keys[id]
	if action_keys.has(id):
		return action_keys[id]
	if keypad != null:
		return keypad.get_key(String(id))
	return null


func key_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t: String in Keypad3D.LAYOUT:
		out.append(StringName(t))
	out.append_array(QUICK_IDS)
	out.append(&"throw")
	out.append(&"main")
	out.append_array(_action_order)
	return out


## Presses key `id` as player `pid` (bots, tests): same path as a hand press.
func press_key(id: StringName, pid: int) -> bool:
	var k := get_key(id)
	if k == null:
		return false
	k.press(pid)
	return true


## World position of key `id`'s cap (where to aim to press it).
func get_aim_point(id: StringName) -> Vector3:
	var k := get_key(id)
	if k == null:
		return global_position if is_inside_tree() else position
	return k.aim_point()


## A pole and round foot under the console, `height` m down to the floor.
func add_stand(height: float, color: Color = DiegeticKit.CONSOLE_BODY) -> void:
	if stand != null:
		stand.queue_free()
	stand = Node3D.new()
	stand.name = "Stand"
	add_child(stand)
	var h := maxf(height, 0.05)
	var pole := Primitives.rounded_cylinder(0.035, h, color, 0.01, 14)
	pole.name = "Pole"
	pole.position.y = -h * 0.5
	stand.add_child(pole)
	var foot := Primitives.rounded_cylinder(maxf(0.16, _size.x * 0.22), 0.04, color.lightened(0.06), 0.015, 22)
	foot.name = "Foot"
	foot.position.y = -h + 0.02
	stand.add_child(foot)
	var collar := Primitives.rounded_cylinder(0.06, 0.03, color.lightened(0.1), 0.01, 16)
	collar.name = "Collar"
	collar.position.y = -0.015
	stand.add_child(collar)


# --- Input -------------------------------------------------------------------

func _on_key(user_pid: int, id: StringName) -> void:
	var k := get_key(id)
	if locked:
		if k != null:
			k.play_nope()
		return
	if gate.is_valid():
		var why: Variant = gate.call(user_pid)
		var text := str(why) if why != null else ""
		if text != "":
			if k != null:
				k.play_nope()
			show_message(text, DiegeticKit.TEXT_WARN)
			refused.emit(user_pid, text)
			return
	key_pressed.emit(id, user_pid)
	match id:
		&"C":
			_set_bet(0)
			_fresh = false
		&"000":
			var base := bet
			if base > 0:
				_set_bet(mini(_mul_capped(base, 1000), cap()))
			_fresh = false
		&"min":
			_set_bet(min_bet)
			_fresh = true
		&"half":
			_set_bet(maxi(min_bet, bet / 2) if bet > 0 else min_bet)
			_fresh = true
		&"double":
			_set_bet(mini(cap(), _mul_capped(maxi(bet, 1), 2)) if bet > 0 else min_bet)
			_fresh = true
		&"max":
			_set_bet(cap())
			_fresh = true
		&"throw":
			set_throw(not throw_armed)
		&"main":
			var b := get_bet()
			_set_bet(b)
			_fresh = true
			var armed := throw_armed
			if disarm_after_play and armed:
				set_throw(false)
			_refresh_screen()
			main_pressed.emit(b, armed, user_pid)
			return
		_:
			if action_keys.has(id):
				action_pressed.emit(id, user_pid)
				return
			var s := String(id)
			if s.length() == 1 and s.is_valid_int():
				var d := s.to_int()
				if _fresh or bet == 0:
					_set_bet(d)
				elif str(bet).length() < MAX_DIGITS:
					_set_bet(_mul_capped(bet, 10) + d)
				if bet > cap():
					_set_bet(cap())
				_fresh = false
	_refresh_screen()


func _set_bet(value: int) -> void:
	value = maxi(0, value)
	if value == bet:
		return
	bet = value
	bet_changed.emit(bet)


func _set_pocket_only(p_pocket: int) -> void:
	pocket = maxi(0, p_pocket)
	_refresh_screen()


static func _mul_capped(a: int, b: int) -> int:
	if a > 0 and b > 0 and a > 999999999999999 / b:
		return 999999999999999
	return a * b


# --- Look --------------------------------------------------------------------

func _make_key(legend: String, color: Color, key_size: Vector3, id: StringName) -> KeyButton3D:
	var k := KeyButton3D.new()
	k.setup(legend, color, key_size, id)
	k.pressed.connect(_on_key.bind(id))
	deck.add_child(k)
	return k


func _refresh_screen() -> void:
	if screen == null or screen.lines.is_empty():
		return
	var limits := ""
	if _limits_known:
		limits = "Min %s · Max %s" % [DiegeticKit.money_short(min_bet), DiegeticKit.money_short(max_bet)]
	var bet_text := DiegeticKit.money(bet)
	if bet_text.length() > 11:
		bet_text = DiegeticKit.money_short(bet)
	var bet_color := DiegeticKit.TEXT_MONEY
	if _limits_known and (bet < min_bet or bet > pocket):
		bet_color = DiegeticKit.TEXT_WARN if bet < min_bet else DiegeticKit.TEXT_LOSE
	var pocket_text := "Pocket %s" % DiegeticKit.money_short(pocket) if _limits_known else ""
	var msg := _message
	var msg_color := _message_color
	if msg == "":
		if throw_armed:
			msg = "THROW ON: lose on purpose"
			msg_color = DiegeticKit.TEXT_LOSE
		else:
			msg = _status
			msg_color = _status_color
	screen.set_line(0, limits, DiegeticKit.TEXT_WHITE)
	screen.set_line(1, bet_text, bet_color)
	screen.set_line(2, pocket_text, DiegeticKit.TEXT_POCKET)
	screen.set_line(3, msg, msg_color)


func _layout() -> void:
	var kp := keypad.get_size()
	var depth := kp.y + MARGIN * 2.0
	var fat_count := 1 + _action_order.size()
	var fat_w := FAT_SIZE.x + float(fat_count - 1) * (FAT_SIZE.x * 0.9 + FAT_GAP)
	var width := MARGIN + kp.x + GAP + SCREEN_WIDTH + GAP + QUICK_SIZE.x + GAP * 1.4 + fat_w + MARGIN
	var tilt := deg_to_rad(tilt_degrees)
	var rise := depth * sin(tilt)
	var flat_depth := depth * cos(tilt)
	var back_h := FRONT_HEIGHT + rise
	_size = Vector3(width, back_h + DECK_THICKNESS, flat_depth)
	body_mesh.mesh = MeshFactory.wedge(Vector3(width, back_h, flat_depth), FRONT_HEIGHT / back_h, 0.012)
	body_mesh.material_override = DiegeticKit.key_material(DiegeticKit.CONSOLE_BODY)
	body_mesh.position = Vector3(0.0, back_h * 0.5, 0.0)
	ArtKit.set_outline_mode(body_mesh, MeshFactory.OUTLINE_BOX)
	deck.position = Vector3(0.0, FRONT_HEIGHT + rise * 0.5, 0.0)
	deck.rotation = Vector3(tilt, 0.0, 0.0)
	var plate_size := Vector3(width - 0.01, DECK_THICKNESS, depth - 0.01)
	deck_plate.mesh = MeshFactory.rounded_box(plate_size, 0.006, 2)
	deck_plate.material_override = DiegeticKit.key_material(DiegeticKit.CONSOLE_DECK)
	deck_plate.position.y = DECK_THICKNESS * 0.5
	var hw := plate_size.x * 0.5 - 0.004
	var hd := plate_size.z * 0.5 - 0.004
	trim.mesh = MeshFactory.stroke(PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]), 0.007, 0.006)
	trim.material_override = ArtKit.neon_material(DiegeticKit.NEON_TRIM, 2.2)
	trim.rotation.x = -PI * 0.5
	trim.position.y = DECK_THICKNESS + 0.001
	var top := DECK_THICKNESS
	var x := -width * 0.5 + MARGIN
	keypad.position = Vector3(x + kp.x * 0.5, top, 0.0)
	x += kp.x + GAP
	if screen.lines.is_empty():
		screen.setup(Vector2(SCREEN_WIDTH, kp.y - 0.012), 4, Color("ff3fd2"), DiegeticKit.BEZEL, 0.012)
		screen.set_line(0, "", DiegeticKit.TEXT_WHITE, 0.021)
		screen.set_line(1, "", DiegeticKit.TEXT_MONEY, 0.074)
		screen.set_line(2, "", DiegeticKit.TEXT_POCKET, 0.02)
		screen.set_line(3, "", DiegeticKit.TEXT_INFO, 0.021)
	screen.position = Vector3(x + SCREEN_WIDTH * 0.5, top + 0.006, 0.0)
	screen.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	x += SCREEN_WIDTH + GAP
	var column: Array[KeyButton3D] = []
	for qid: StringName in QUICK_IDS:
		column.append(quick_keys[qid])
	column.append(throw_key)
	var pitch := kp.y / float(column.size())
	for i in column.size():
		column[i].position = Vector3(x + QUICK_SIZE.x * 0.5, top, (float(i) - float(column.size() - 1) * 0.5) * pitch)
	x += QUICK_SIZE.x + GAP * 1.4
	main_key.position = Vector3(x + FAT_SIZE.x * 0.5, top, 0.0)
	x += FAT_SIZE.x + FAT_GAP
	for aid: StringName in _action_order:
		var k: KeyButton3D = action_keys[aid]
		k.position = Vector3(x + FAT_SIZE.x * 0.45, top, 0.0)
		x += FAT_SIZE.x * 0.9 + FAT_GAP
