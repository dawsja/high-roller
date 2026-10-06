class_name DiceMachine
extends GameMachine
## Dice (ref: dice in hands). A craps-style tub: a padded rail around a
## sunken felt with a bumper back wall, two monitors on stands behind it
## (WIN ON / LOSE ON for your call, and the multiplier with your bet), a
## LOW / ROLL / HIGH cluster on the front rail and the keypad console on a
## stand at the corner. Up to four players stand along the front rail; bets
## from several of them inside the host's shared-roll window are one roll.
##
## Rolling with your own hands: ROLL puts two Dice3D in the first-person
## player's cupped hands and captures LMB (player.begin_capture(self)).
## Hold LMB to shake (they rattle), release to THROW: the dice fly from the
## hands along the view as rigid bodies, bounce off the felt and the back
## wall, and the bet request goes out at the release. When the host's &"bet"
## event brings the faces, the dice settle_to them in their last moments (or
## right away if they already stopped). Rolls the local hands didn't throw
## (other players, bots, press_by_id) are tossed from that player's spot on
## the rail with the same physics and settle. A crew's shared roll (one
## &"bet" event per bettor, the same dice) plays as ONE pair per peer: the
## local thrower's, else one tossed pair.
##
## Machine space: floor at y = 0, the players stand at +Z facing -Z.

enum HandState { IDLE, HOLDING, SHAKING }

## One pair of dice in play and the results riding on it.
class Roll extends RefCounted:
	var dice: Array[Dice3D] = []
	## BetResult dicts attached so far.
	var results: Array[Dictionary] = []
	var faces: Array[int] = []
	## "d0-d1|crew" for a shared roll ("" until faces are known).
	var key: String = ""
	## The local player threw it and waits for this pid's result (0 = none).
	var waiting_pid: int = 0
	var age: float = 0.0
	## The dice stopped (or flew too long) and froze.
	var landed: bool = false
	var settling: bool = false
	var settled: int = 0
	var done: bool = false
	var shown: bool = false
	var spot: int = 0

	func is_shared() -> bool:
		return key != ""


const FELT_Y := 0.78
## Inner half extents of the tub (felt area).
const HALF := Vector2(1.15, 1.05)
const WALL := 0.15
const WALL_TOP := 1.0
## Invisible walls keep wild throws in the tub.
const GLASS_TOP := 1.9
const RAIL_TUBE := 0.075
const SPOT_Z := 1.62
const SPOTS: Array[Vector3] = [Vector3(0.2, 0.0, SPOT_Z), Vector3(-0.5, 0.0, SPOT_Z), Vector3(-1.2, 0.0, SPOT_Z), Vector3(0.9, 0.0, SPOT_Z)]
const SPOT_RADIUS := 0.32
const DIE_SIZE := 0.1
const DICE_LAYER := 32
const THROW_SPEED := 3.6
const TOSS_SPEED := 3.0
## Dice that are still flying after this long are stopped where they are.
const MAX_FLIGHT := 2.6
## Below these speeds (and after MIN_FLIGHT) the dice settle onto their faces.
const SETTLE_SPEED := 0.55
const MIN_FLIGHT := 0.55
const SETTLE_SECONDS := 0.32
const RESULT_SECONDS := 1.5
## A shared roll's other results join it this long after it started.
const SHARED_JOIN_SECONDS := 6.0
## Held dice are thrown on their own after this long.
const HOLD_LIMIT := 8.0
const FELT_COLOR := Color("4b2a6e")
const WOOD := Color("4a1f3a")
const RAIL_COLOR := Color("c2264a")
const BUMPER := Color("ff5fa8")
const CALL_KEYS := {&"low": GameResolver.DICE_CALL_LOW, &"high": GameResolver.DICE_CALL_HIGH}

## Divides scripted animation lengths (tests speed them up; physics runs as is).
var anim_speed: float = 1.0
## The local player's call: "high" (8-12 wins) or "low" (2-6 wins).
var call: String = GameResolver.DICE_CALL_HIGH
## The local first-person player (found from the play spot or set by the director).
var local_player: Node3D
var hand_state: int = HandState.IDLE
var rolls: Array[Roll] = []
var odds_monitor: MonitorOnStand
var bet_monitor: MonitorOnStand
var low_key: KeyButton3D
var high_key: KeyButton3D
var total_label: Label3D
var quick_keys: Dictionary = {}

var _held_pair: Node3D
var _held_dice: Array[Dice3D] = []
var _held_bet: int = 0
var _held_throw: bool = false
var _held_pid: int = 0
var _hold_seconds: float = 0.0
var _capturer: Node3D
var _rng := RandomNumberGenerator.new()
var _total_tween: Tween


func _build_game() -> void:
	max_occupants = SPOTS.size()
	console.setup("ROLL", DiegeticKit.KEY_GREEN, 40.0)
	_build_tub()
	_build_keys()
	odds_monitor = add_monitor(Transform3D(Basis.IDENTITY, Vector3(-0.55, 0.0, -HALF.y - WALL - 0.32)), Vector2(0.86, 0.5), 1.6, 3)
	bet_monitor = add_monitor(Transform3D(Basis.IDENTITY, Vector3(0.55, 0.0, -HALF.y - WALL - 0.32)), Vector2(0.86, 0.5), 1.6, 3)
	total_label = ArtKit.make_label("", 0.0017, DiegeticKit.TEXT_WIN, 96, true)
	total_label.name = "Total"
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.outline_size = 30
	total_label.visible = false
	visuals.add_child(total_label)
	spawn_dealer(Vector3(-HALF.x - WALL - 0.45, 0.0, -0.35), -PI * 0.5)
	set_footprint(Vector3(HALF.x * 2.0 + WALL * 2.0, FELT_Y, HALF.y * 2.0 + WALL * 2.0), Vector3(0.0, FELT_Y * 0.5, 0.0))
	set_play_spot(SPOTS[0], 0.0, SPOT_RADIUS)
	for i in range(1, SPOTS.size()):
		var extra := CollisionShape3D.new()
		extra.name = "Spot%d" % i
		var cyl := CylinderShape3D.new()
		cyl.radius = SPOT_RADIUS
		cyl.height = 2.0
		extra.shape = cyl
		extra.position = SPOTS[i] - SPOTS[0]
		play_zone.add_child(extra)
	play_zone.body_entered.connect(_on_spot_body)
	set_label_height(2.45)
	pop_point = Vector3(0.0, 2.0, -0.4)
	_set_call(GameResolver.DICE_CALL_HIGH)
	console.bet_changed.connect(func(_bet: int) -> void: _show_bet())


## Where player `index` (0..3) of a crew stands and faces (global).
func get_play_transform_for(index: int) -> Transform3D:
	var spot: Vector3 = SPOTS[clampi(index, 0, SPOTS.size() - 1)]
	return _xform() * Transform3D(Basis.IDENTITY, spot)


func play_spot_count() -> int:
	return SPOTS.size()


## The director can hand over the local first-person player (else it is
## picked up when it walks into a play spot).
func set_local_player(player: Node3D) -> void:
	local_player = player


func is_holding_dice() -> bool:
	return hand_state != HandState.IDLE


## True while any pair is still flying or settling.
func is_rolling() -> bool:
	for r: Roll in rolls:
		if not r.done:
			return true
	return false


## The faces the newest finished roll shows ([] if none).
func shown_faces() -> Array[int]:
	for i in range(rolls.size() - 1, -1, -1):
		var r := rolls[i]
		if r.done:
			var out: Array[int] = []
			for d: Dice3D in r.dice:
				out.append(d.up_face())
			return out
	return []


## Total dice in the tub right now (tests: one pair per shared roll).
func dice_count() -> int:
	var n := 0
	for r: Roll in rolls:
		n += r.dice.size()
	return n


# --- First-person throw (capture) ------------------------------------------------

func on_primary_pressed(pid: int) -> void:
	if pid != _held_pid or hand_state != HandState.HOLDING:
		return
	hand_state = HandState.SHAKING
	var hands := _hands()
	if hands != null:
		hands.call(&"shake", true)


func on_primary_released(pid: int) -> void:
	if pid != _held_pid or hand_state != HandState.SHAKING:
		return
	_throw_from_hands()


# --- GameMachine overrides --------------------------------------------------------

func _on_main(bet: int, throw: bool, pid: int) -> void:
	if hand_state != HandState.IDLE:
		console.show_message("Throw the dice first!", DiegeticKit.TEXT_WARN)
		return
	var choice := {"call": call, "throw": throw}
	if pid == local_pid and _pick_up(pid, bet, throw):
		return
	request_bet(pid, bet, choice)


func _on_bet(data: Dictionary) -> void:
	var result: Dictionary = data.get("result", {}) if data.get("result") is Dictionary else {}
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	var pid := int(result.get("pid", 0))
	var faces := _ints(detail.get("dice", []))
	if faces.size() < 2:
		_end_result(result)
		return
	var shared := bool(detail.get("shared", false)) and int(detail.get("crew", 1)) > 1
	var key := "%d-%d|%d" % [faces[0], faces[1], int(detail.get("crew", 1))] if shared else ""
	var roll := _waiting_roll(pid)
	if roll == null and shared:
		roll = _joinable_roll(key)
	if roll == null:
		roll = _toss(_spot_of(pid))
	_attach(roll, result, faces, key)


func _on_request_result(request: StringName, args: Array, result: Dictionary) -> void:
	if request != &"place_bet" or bool(result.get("ok", false)) or args.is_empty():
		return
	# Refused: dice thrown for this bet fizzle out.
	var roll := _waiting_roll(int(args[0]))
	if roll != null:
		roll.waiting_pid = 0
		if roll.results.is_empty():
			_fizzle(roll)


func _on_occupants_changed() -> void:
	if hand_state != HandState.IDLE and not occupants.has(_held_pid):
		_cancel_hold("")


func _on_closed_changed(value: bool) -> void:
	if value and hand_state != HandState.IDLE:
		_cancel_hold("CLOSED")
	for k: KeyButton3D in [low_key, high_key]:
		if k != null:
			k.enabled = not value


func _process(delta: float) -> void:
	super(delta)
	if hand_state != HandState.IDLE:
		_hold_seconds += delta
		if hand_state == HandState.SHAKING:
			for d: Dice3D in _held_dice:
				if is_instance_valid(d):
					d.rotate_object_local(Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized(), delta * 14.0)
		if _hold_seconds > HOLD_LIMIT:
			_throw_from_hands()


func _physics_process(delta: float) -> void:
	for r: Roll in rolls:
		if r.done or r.landed:
			continue
		r.age += delta
		var slow := true
		for d: Dice3D in r.dice:
			if not is_instance_valid(d):
				continue
			if _out_of_tub(d):
				_rescue(d)
			if d.physics_mode and (d.linear_velocity.length() > SETTLE_SPEED or d.angular_velocity.length() > 9.0):
				slow = false
		if (slow and r.age > MIN_FLIGHT / maxf(anim_speed, 1.0)) or r.age > MAX_FLIGHT:
			_land(r)


# --- Presses --------------------------------------------------------------------

func _on_call_key(pid: int, id: StringName) -> void:
	var key := low_key if id == &"low" else high_key
	if not _press_ok(pid, key):
		return
	_set_call(str(CALL_KEYS[id]))
	console.show_message("Calling %s: wins on %s" % [call.to_upper(), _win_text(call)], DiegeticKit.TEXT_MONEY)


## The console's rules for a key that isn't on it: ignored while locked,
## refused (with the reason on the screen) for anyone but an occupant.
func _press_ok(pid: int, key: Node) -> bool:
	if console.is_locked():
		if key is KeyButton3D:
			(key as KeyButton3D).play_nope()
		return false
	var why := _gate(pid)
	if why != "":
		if key is KeyButton3D:
			(key as KeyButton3D).play_nope()
		console.show_message(why, DiegeticKit.TEXT_WARN)
		console.refused.emit(pid, why)
		return false
	return true


func _on_fraction_key(pid: int, id: StringName, key: KeyButton3D) -> void:
	if not _press_ok(pid, key):
		return
	console.key_pressed.emit(id, pid)
	console.set_bet(maxi(console.min_bet, int(float(console.cap()) * (0.25 if id == &"quarter" else 0.5))))


func _set_call(value: String) -> void:
	call = GameResolver.DICE_CALL_LOW if value == GameResolver.DICE_CALL_LOW else GameResolver.DICE_CALL_HIGH
	if low_key != null:
		low_key.set_lit(call == GameResolver.DICE_CALL_LOW)
		high_key.set_lit(call == GameResolver.DICE_CALL_HIGH)
	_show_odds(call)


# --- Rolls --------------------------------------------------------------------------

## ROLL with hands: two dice appear on the rail and jump into the cupped
## hands; LMB is captured for the shake and throw. False without hands.
func _pick_up(pid: int, bet: int, throw: bool) -> bool:
	var player := _player()
	var hands := _hands()
	if player == null or hands == null or not player.has_method(&"begin_capture"):
		return false
	_clear_old_rolls()
	_show_bet()
	_held_pair = Node3D.new()
	_held_pair.name = "HeldDice"
	visuals.add_child(_held_pair)
	_held_pair.global_position = get_aim_point(&"main") + Vector3.UP * 0.12
	_held_dice.clear()
	for i in 2:
		var d := _make_die()
		d.position = Vector3((float(i) - 0.5) * DIE_SIZE * 1.15, 0.0, 0.0)
		d.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		_held_pair.add_child(d)
		_held_dice.append(d)
	hands.call(&"hold", _held_pair, &"both")
	player.call(&"begin_capture", self)
	_capturer = player
	_held_pid = pid
	_held_bet = bet
	_held_throw = throw
	_hold_seconds = 0.0
	hand_state = HandState.HOLDING
	console.show_message("Hold LMB to shake · release to throw!", DiegeticKit.TEXT_MONEY, 0.0)
	return true


func _throw_from_hands() -> void:
	var hands := _hands()
	var player := _player()
	var pid := _held_pid
	var dir := _throw_direction(player)
	if hands != null:
		hands.call(&"shake", false)
		hands.call(&"play", &"throw")
		var released: Variant = hands.call(&"release_held")
		if released == null and is_instance_valid(_held_pair) and _held_pair.get_parent() != visuals:
			_held_pair.reparent(visuals, true)
	if is_instance_valid(_capturer) and _capturer.has_method(&"end_capture"):
		_capturer.call(&"end_capture", self)
	_capturer = null
	hand_state = HandState.IDLE
	console.clear_message()
	var roll := Roll.new()
	roll.waiting_pid = pid
	roll.spot = _spot_of(pid)
	for d: Dice3D in _held_dice:
		if not is_instance_valid(d):
			continue
		d.reparent(visuals, true)
		var v := dir * THROW_SPEED * _rng.randf_range(0.9, 1.1) + Vector3(_rng.randf_range(-0.25, 0.25), 0.6, 0.0)
		_launch(d, v)
		roll.dice.append(d)
	_held_dice.clear()
	if is_instance_valid(_held_pair):
		_held_pair.queue_free()
	_held_pair = null
	rolls.append(roll)
	request_bet(pid, _held_bet, {"call": call, "throw": _held_throw})


func _cancel_hold(message: String) -> void:
	var hands := _hands()
	if hands != null:
		hands.call(&"shake", false)
		var item: Variant = hands.call(&"release_held")
		if item is Node:
			(item as Node).queue_free()
	if is_instance_valid(_held_pair):
		_held_pair.queue_free()
	_held_pair = null
	_held_dice.clear()
	if is_instance_valid(_capturer) and _capturer.has_method(&"end_capture"):
		_capturer.call(&"end_capture", self)
	_capturer = null
	hand_state = HandState.IDLE
	if message != "":
		console.show_message(message, DiegeticKit.TEXT_LOSE)
	else:
		console.clear_message()


## A pair tossed from spot `spot`'s rail (rolls nobody's hands threw here).
func _toss(spot: int) -> Roll:
	_clear_old_rolls()
	_show_bet()
	var roll := Roll.new()
	roll.spot = spot
	var base: Vector3 = SPOTS[clampi(spot, 0, SPOTS.size() - 1)]
	for i in 2:
		var d := _make_die()
		visuals.add_child(d)
		d.position = Vector3(base.x + (float(i) - 0.5) * 0.14, WALL_TOP + 0.2, HALF.y - 0.05)
		d.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
		var aim := Vector3(-base.x * 0.35 + _rng.randf_range(-0.2, 0.2), 0.35, -1.0).normalized()
		_launch(d, global_basis * aim * TOSS_SPEED * _rng.randf_range(0.9, 1.1) if is_inside_tree() else aim * TOSS_SPEED)
		roll.dice.append(d)
	rolls.append(roll)
	if _dealer_ok():
		_dealer_pose(&"wave", 0.8)
	return roll


func _launch(d: Dice3D, velocity: Vector3) -> void:
	if not is_inside_tree():
		d.set_physics_mode(false)
		return
	d.set_physics_mode(true)
	d.linear_velocity = velocity
	d.angular_velocity = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)) * 16.0


func _attach(roll: Roll, result: Dictionary, faces: Array[int], key: String) -> void:
	roll.results.append(result)
	if int(result.get("pid", 0)) == roll.waiting_pid:
		roll.waiting_pid = 0
	if roll.faces.is_empty():
		roll.faces = faces
		roll.key = key
	if roll.done:
		_finish_one(roll, result)
		return
	if not is_inside_tree():
		_land(roll)
		return
	if roll.landed:
		_settle(roll)


## The dice stopped (or flew too long): freeze them; settle once the faces are known.
func _land(roll: Roll) -> void:
	if roll.landed:
		return
	roll.landed = true
	for d: Dice3D in roll.dice:
		if is_instance_valid(d) and d.physics_mode:
			d.linear_velocity = Vector3.ZERO
			d.angular_velocity = Vector3.ZERO
			d.set_physics_mode(false)
			d.position.y = FELT_Y + DIE_SIZE * 0.5
	if not roll.faces.is_empty():
		_settle(roll)


func _settle(roll: Roll) -> void:
	if roll.settling or roll.faces.size() < 2:
		return
	roll.settling = true
	roll.settled = 0
	for i in roll.dice.size():
		var d := roll.dice[i]
		if not is_instance_valid(d):
			roll.settled += 1
			continue
		d.settled.connect(_die_settled.bind(roll), CONNECT_ONE_SHOT)
		d.settle_to(roll.faces[mini(i, roll.faces.size() - 1)], SETTLE_SECONDS / maxf(anim_speed, 0.01))
	if roll.settled >= roll.dice.size():
		_show_roll(roll)


func _die_settled(_value: int, roll: Roll) -> void:
	roll.settled += 1
	if roll.settled >= roll.dice.size():
		_show_roll(roll)


## Both dice show their faces: total over the dice, monitors, win burst, then
## each result ends (result_shown) after a short hold.
func _show_roll(roll: Roll) -> void:
	if roll.shown:
		return
	roll.shown = true
	var main := _main_result(roll)
	var detail: Dictionary = main.get("detail", {}) if main.get("detail") is Dictionary else {}
	var total := roll.faces[0] + roll.faces[1]
	var won := bool(main.get("won", false))
	var color := DiegeticKit.TEXT_WIN if won else DiegeticKit.TEXT_LOSE
	total_label.text = "%d + %d = %d" % [roll.faces[0], roll.faces[1], total]
	total_label.modulate = color
	total_label.position = _dice_center(roll) + Vector3(0.0, 0.32, 0.0)
	total_label.visible = true
	_pop_total()
	var tc := GameMachine.result_text(main)
	var used_call := str(detail.get("call", call))
	_show_odds(used_call, total)
	bet_monitor.set_lines([{"text": "%d %s" % [total, "SEVEN!" if total == GameResolver.DICE_HOUSE_TOTAL else ("HIGH" if total > GameResolver.DICE_HOUSE_TOTAL else "LOW")], "color": DiegeticKit.TEXT_WHITE, "size": 0.085},
			{"text": str(tc[0]), "color": tc[1], "size": 0.08},
			{"text": "CREW ROLL x%d" % int(detail.get("crew", 1)) if roll.is_shared() else "Bet %s" % DiegeticKit.money_short(int(main.get("bet", 0))), "color": DiegeticKit.TEXT_MONEY, "size": 0.04}])
	bet_monitor.screen.flash(tc[1], 0.6, 0.5)
	if won:
		_burst(_dice_center(roll) + Vector3(0.0, 0.1, 0.0), roll.is_shared())
		_dealer_pose(&"shrug", 1.2)
	else:
		flash(DiegeticKit.TEXT_LOSE, 1.6, 0.5)
		_dealer_pose(&"chip_flip", 1.2)
	if not is_inside_tree():
		_finish_roll(roll)
		return
	var tw := create_tween()
	tw.tween_interval(RESULT_SECONDS / maxf(anim_speed, 0.01))
	tw.tween_callback(_finish_roll.bind(roll))


func _finish_roll(roll: Roll) -> void:
	roll.done = true
	# The local player's result goes last so its caption stays up.
	var ordered: Array[Dictionary] = []
	for r: Dictionary in roll.results:
		if int(r.get("pid", 0)) != local_pid:
			ordered.append(r)
	for r: Dictionary in roll.results:
		if int(r.get("pid", 0)) == local_pid:
			ordered.append(r)
	for r: Dictionary in ordered:
		_end_result(r)


## A result that joins a roll after it finished (late shared result).
func _finish_one(_roll: Roll, result: Dictionary) -> void:
	_end_result(result)


## A thrown pair whose bet was refused rolls to a stop and vanishes.
func _fizzle(roll: Roll) -> void:
	roll.done = true
	for d: Dice3D in roll.dice:
		if is_instance_valid(d):
			_vanish(d, 1.2)
	roll.dice.clear()


func _clear_old_rolls() -> void:
	var keep: Array[Roll] = []
	for r: Roll in rolls:
		if r.done:
			for d: Dice3D in r.dice:
				if is_instance_valid(d):
					_vanish(d, 0.0)
		else:
			keep.append(r)
	rolls = keep
	if total_label != null:
		total_label.visible = false


func _vanish(d: Dice3D, delay: float) -> void:
	d.set_physics_mode(false)
	if not d.is_inside_tree():
		d.queue_free()
		return
	var tw := d.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(d, "scale", Vector3.ONE * 0.05, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(d.queue_free)


func _waiting_roll(pid: int) -> Roll:
	for r: Roll in rolls:
		if r.waiting_pid == pid and pid != 0 and not r.done:
			return r
	return null


## A shared roll this result belongs to: the same dice, started lately, or a
## local throw still waiting for its faces.
func _joinable_roll(key: String) -> Roll:
	for r: Roll in rolls:
		if r.key == key and r.age < SHARED_JOIN_SECONDS:
			return r
	for r: Roll in rolls:
		if r.faces.is_empty() and r.waiting_pid != 0 and not r.done:
			return r
	return null


func _main_result(roll: Roll) -> Dictionary:
	for r: Dictionary in roll.results:
		if int(r.get("pid", 0)) == local_pid:
			return r
	return roll.results[0] if not roll.results.is_empty() else {}


func _out_of_tub(d: Dice3D) -> bool:
	if not d.physics_mode or not d.is_inside_tree():
		return false
	var p := to_local(d.global_position)
	return absf(p.x) > HALF.x + 0.3 or p.z < -HALF.y - 0.3 or p.z > HALF.y + 0.9 or p.y < FELT_Y - 0.25 or p.y > 3.0


## A die that left the tub tumbles back onto the felt.
func _rescue(d: Dice3D) -> void:
	d.set_physics_mode(false)
	var spot := Vector3(_rng.randf_range(-0.5, 0.5), FELT_Y + DIE_SIZE * 0.5, _rng.randf_range(-0.6, 0.0))
	d.position = spot


func _dice_center(roll: Roll) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for d: Dice3D in roll.dice:
		if is_instance_valid(d):
			c += d.position
			n += 1
	return c / float(n) if n > 0 else Vector3(0.0, FELT_Y, 0.0)


func _spot_of(pid: int) -> int:
	var i := occupants.find(pid)
	return clampi(i, 0, SPOTS.size() - 1) if i >= 0 else 0


func _throw_direction(player: Node3D) -> Vector3:
	var fwd := -global_basis.z if is_inside_tree() else Vector3.FORWARD
	var look := fwd
	if player != null and player.has_method(&"look_direction"):
		look = player.call(&"look_direction")
	var flat := Vector3(look.x, 0.0, look.z)
	if flat.length() < 0.01 or flat.normalized().dot(fwd) < 0.35:
		flat = fwd
	flat = flat.normalized().slerp(fwd, 0.25).normalized()
	var pitch := clampf(asin(clampf(look.y, -1.0, 1.0)), deg_to_rad(-30.0), deg_to_rad(10.0))
	return (flat * cos(pitch) + Vector3.UP * (sin(pitch) + 0.35)).normalized()


func _make_die() -> Dice3D:
	var d := Dice3D.new()
	d.setup(DIE_SIZE)
	d.collision_layer = DICE_LAYER
	d.collision_mask = WORLD_LAYER | DICE_LAYER
	d.continuous_cd = true
	d.linear_damp = 0.3
	d.angular_damp = 0.8
	return d


func _player() -> Node3D:
	if is_instance_valid(local_player):
		return local_player
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group(&"players"):
		if n is Node3D and _is_local_body(n as Node3D) and n.has_method(&"begin_capture"):
			local_player = n
			return local_player
	return null


func _hands() -> Node3D:
	var p := _player()
	if p == null:
		return null
	var h: Variant = p.get(&"hands")
	return h if h is Node3D and (h as Node3D).has_method(&"hold") else null


func _on_spot_body(node: Node3D) -> void:
	if _is_local_body(node) and node.has_method(&"begin_capture"):
		local_player = node


# --- Look -----------------------------------------------------------------------

func _show_odds(the_call: String, total: int = 0) -> void:
	if odds_monitor == null:
		return
	var win := _win_text(the_call)
	var lose := "2 - 7" if the_call == GameResolver.DICE_CALL_HIGH else "7 - 12"
	var last := "Calling %s" % the_call.to_upper()
	if total > 0:
		last = "Rolled %d · %s" % [total, "WIN" if GameResolver.dice_call_wins(the_call, total) else "LOSE"]
	odds_monitor.set_lines([{"text": "WIN ON  %s" % win, "color": DiegeticKit.TEXT_WIN, "size": 0.075},
			{"text": "LOSE ON  %s" % lose, "color": DiegeticKit.TEXT_LOSE, "size": 0.075},
			{"text": last, "color": DiegeticKit.TEXT_INFO, "size": 0.045}])


func _show_bet() -> void:
	if bet_monitor == null:
		return
	bet_monitor.set_lines([{"text": "%sx" % _mult_text(), "color": DiegeticKit.TEXT_MONEY, "size": 0.11},
			{"text": DiegeticKit.money_short(console.get_bet()) if console.get_bet() > 0 else "$0", "color": DiegeticKit.TEXT_POCKET, "size": 0.085},
			{"text": "Crew rolls split the Heat", "color": DiegeticKit.TEXT_INFO, "size": 0.035}])


func _win_text(the_call: String) -> String:
	return "8 - 12" if the_call == GameResolver.DICE_CALL_HIGH else "2 - 6"


func _mult_text() -> String:
	return ("%.1f" % (1.0 + TableGames.profit_multiple(HR.GameType.DICE))).trim_suffix(".0")


func _pop_total() -> void:
	if not is_inside_tree():
		return
	if _total_tween != null and _total_tween.is_valid():
		_total_tween.kill()
	total_label.scale = Vector3.ONE * 0.3
	_total_tween = create_tween()
	_total_tween.tween_property(total_label, "scale", Vector3.ONE * 1.15, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_total_tween.tween_property(total_label, "scale", Vector3.ONE, 0.1)


func _build_tub() -> void:
	var outer := Vector2(HALF.x + WALL, HALF.y + WALL)
	var body_mesh := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(outer.x * 2.0, FELT_Y, outer.y * 2.0), 0.1, 3), WOOD)
	body_mesh.name = "Body"
	body_mesh.position.y = FELT_Y * 0.5
	visuals.add_child(body_mesh)
	var felt := ArtKit.mesh_instance(MeshFactory.rounded_box(Vector3(HALF.x * 2.0, 0.012, HALF.y * 2.0), 0.005, 1),
			ArtKit.felt_material(FELT_COLOR, Color("ff8ad8"), HALF, 0.14))
	felt.name = "Felt"
	felt.position.y = FELT_Y
	visuals.add_child(felt)
	var neon := ArtKit.mesh_instance(MeshFactory.stroke(_round_rect(HALF.x - 0.06, HALF.y - 0.06, 0.14), 0.016, 0.008), ArtKit.neon_material(Color("ff7ad9"), 2.2))
	neon.name = "FeltNeon"
	neon.rotation.x = -PI * 0.5
	neon.position.y = FELT_Y + 0.01
	visuals.add_child(neon)
	var wall_h := WALL_TOP - FELT_Y
	var walls := [
		[Vector3(outer.x * 2.0, wall_h, WALL), Vector3(0.0, FELT_Y + wall_h * 0.5, -HALF.y - WALL * 0.5)],
		[Vector3(outer.x * 2.0, wall_h, WALL), Vector3(0.0, FELT_Y + wall_h * 0.5, HALF.y + WALL * 0.5)],
		[Vector3(WALL, wall_h, HALF.y * 2.0), Vector3(-HALF.x - WALL * 0.5, FELT_Y + wall_h * 0.5, 0.0)],
		[Vector3(WALL, wall_h, HALF.y * 2.0), Vector3(HALF.x + WALL * 0.5, FELT_Y + wall_h * 0.5, 0.0)],
	]
	var wall_mesh := Node3D.new()
	wall_mesh.name = "Walls"
	visuals.add_child(wall_mesh)
	for w: Array in walls:
		var mi := Primitives.mesh_instance(MeshFactory.rounded_box(w[0], 0.03, 2), WOOD.lightened(0.08))
		mi.position = w[1]
		wall_mesh.add_child(mi)
	var rail := Primitives.mesh_instance(_tube_loop(_round_rect(HALF.x + WALL * 0.5, HALF.y + WALL * 0.5, 0.3), RAIL_TUBE, 10), RAIL_COLOR)
	rail.name = "Rail"
	rail.position.y = WALL_TOP
	visuals.add_child(rail)
	# Bumper diamonds along the back wall: the dice bounce off them.
	var bumps: Array[Transform3D] = []
	var count := 22
	for i in count:
		var x := lerpf(-HALF.x + 0.06, HALF.x - 0.06, float(i) / float(count - 1))
		for row in 2:
			bumps.append(Transform3D(Basis.from_euler(Vector3(0.0, 0.0, PI * 0.25)), Vector3(x + (0.05 if row == 1 else 0.0), FELT_Y + 0.06 + 0.075 * float(row), -HALF.y + 0.012)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshFactory.rounded_box(Vector3(0.05, 0.05, 0.03), 0.008, 1)
	mm.instance_count = bumps.size()
	for i in bumps.size():
		mm.set_instance_transform(i, bumps[i])
	var bump_mi := MultiMeshInstance3D.new()
	bump_mi.name = "Bumpers"
	bump_mi.multimesh = mm
	bump_mi.material_override = ArtKit.toon_material(BUMPER, 0.15, false, true, 0.4)
	visuals.add_child(bump_mi)
	var plaque := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(1.3, 0.1, 0.03), 0.03, 2), Color("1c1033"))
	plaque.name = "Plaque"
	plaque.position = Vector3(0.0, WALL_TOP + 0.13, -HALF.y - WALL * 0.5)
	visuals.add_child(plaque)
	var words := DiegeticKit.text_label("ROLL THE DICE AND BEAT THE ODDS", 0.042, Color("ffe08a"), 0)
	words.name = "PlaqueText"
	words.position = plaque.position + Vector3(0.0, 0.0, 0.017)
	DiegeticKit.fit_label(words, words.text, 0.042, 1.2)
	visuals.add_child(words)
	for sx: float in [-0.6, 0.6]:
		var post := Primitives.rounded_cylinder(0.02, 0.16, Color("1c1033"), 0.006, 10)
		post.position = Vector3(sx, WALL_TOP + 0.06, -HALF.y - WALL * 0.5)
		visuals.add_child(post)
	# Physics for thrown dice: walls up to rail height, invisible glass above.
	var solid := StaticBody3D.new()
	solid.name = "TubWalls"
	solid.collision_layer = WORLD_LAYER
	solid.collision_mask = 0
	visuals.add_child(solid)
	for w: Array in walls:
		_box_shape(solid, Vector3((w[0] as Vector3).x, WALL_TOP + 0.1 - FELT_Y, (w[0] as Vector3).z), Vector3((w[1] as Vector3).x, (FELT_Y + WALL_TOP + 0.1) * 0.5, (w[1] as Vector3).z))
	var glass := StaticBody3D.new()
	glass.name = "Glass"
	glass.collision_layer = DICE_LAYER
	glass.collision_mask = 0
	visuals.add_child(glass)
	var gh := GLASS_TOP - WALL_TOP
	_box_shape(glass, Vector3(outer.x * 2.0, gh, WALL), Vector3(0.0, WALL_TOP + gh * 0.5, -HALF.y - WALL * 0.5))
	_box_shape(glass, Vector3(WALL, gh, HALF.y * 2.0), Vector3(-HALF.x - WALL * 0.5, WALL_TOP + gh * 0.5, 0.0))
	_box_shape(glass, Vector3(WALL, gh, HALF.y * 2.0), Vector3(HALF.x + WALL * 0.5, WALL_TOP + gh * 0.5, 0.0))


func _box_shape(body_node: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	body_node.add_child(cs)


func _build_keys() -> void:
	var pod := Node3D.new()
	pod.name = "RailKeys"
	pod.position = Vector3(SPOTS[0].x, WALL_TOP + RAIL_TUBE + 0.005, HALF.y + WALL * 0.5 + 0.03)
	pod.rotation.x = deg_to_rad(18.0)
	visuals.add_child(pod)
	var panel := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(0.74, 0.05, 0.22), 0.035, 3), DiegeticKit.CONSOLE_BODY)
	panel.name = "Panel"
	pod.add_child(panel)
	var trim := ArtKit.mesh_instance(MeshFactory.stroke(_round_rect(0.36, 0.1, 0.03), 0.008, 0.006), ArtKit.neon_material(DiegeticKit.NEON_TRIM, 2.0))
	trim.rotation.x = -PI * 0.5
	trim.position.y = 0.026
	pod.add_child(trim)
	var side := Vector3(0.17, 0.05, 0.16)
	low_key = KeyButton3D.new()
	low_key.setup("LOW\n2-6", DiegeticKit.KEY_PURPLE, side, &"low")
	low_key.position = Vector3(-0.24, 0.025, 0.0)
	low_key.pressed.connect(_on_call_key.bind(&"low"))
	pod.add_child(low_key)
	register_pressable(&"low", low_key)
	high_key = KeyButton3D.new()
	high_key.setup("HIGH\n8-12", DiegeticKit.KEY_BLUE, side, &"high")
	high_key.position = Vector3(0.24, 0.025, 0.0)
	high_key.pressed.connect(_on_call_key.bind(&"high"))
	pod.add_child(high_key)
	register_pressable(&"high", high_key)
	_rework_console(pod, Vector3(0.0, 0.025, 0.0), Vector3(0.24, 0.065, 0.18))
	var s := 0.66
	place_console(Transform3D(Basis(Vector3.UP, deg_to_rad(-35.0)).scaled(Vector3.ONE * s), Vector3(HALF.x + WALL + 0.32, 1.0, HALF.y + 0.42)))
	console.add_stand(1.0 / s)


## The kit console reworked to the console-on-a-stand reference: the main key
## leaves the panel for `main_parent` (the rail) at `main_pos`; the quick
## column becomes MIN ¼ ½ ALL (¼ and ½ of all you can bet now, ALL = all of
## it up to the max); THROW fills the slot the main key left.
func _rework_console(main_parent: Node3D, main_pos: Vector3, main_size: Vector3) -> KeyButton3D:
	var main := console.main_key
	var slot := main.position
	main.get_parent().remove_child(main)
	main_parent.add_child(main)
	main.setup(console.main_label, DiegeticKit.KEY_GREEN, main_size, &"main")
	main.set_emission(0.15)
	main.position = main_pos
	var tk := console.throw_key
	tk.setup("THROW", DiegeticKit.KEY_RED, Vector3(0.15, 0.04, 0.17), &"throw")
	tk.position = slot
	var column_x: float = (console.quick_keys[&"min"] as KeyButton3D).position.x
	var top: float = (console.quick_keys[&"min"] as KeyButton3D).position.y
	var depth := console.keypad.get_size().y
	var size := Vector3(BetConsole3D.QUICK_SIZE.x, 0.032, depth / 4.0 - 0.016)
	for hidden: StringName in [&"half", &"double"]:
		var k: KeyButton3D = console.quick_keys[hidden]
		k.enabled = false
		k.visible = false
		k.collision_layer = 0
	var column: Array[KeyButton3D] = []
	var min_key: KeyButton3D = console.quick_keys[&"min"]
	min_key.setup("MIN", DiegeticKit.KEY_ORANGE, size, &"min")
	column.append(min_key)
	for id: StringName in [&"quarter", &"half"]:
		var k := KeyButton3D.new()
		k.setup("¼" if id == &"quarter" else "½", DiegeticKit.KEY_ORANGE, size, id)
		k.set_emission(0.18)
		k.pressed.connect(_on_fraction_key.bind(id, k))
		console.deck.add_child(k)
		register_pressable(id, k)
		quick_keys[id] = k
		column.append(k)
	var all_key: KeyButton3D = console.quick_keys[&"max"]
	all_key.setup("ALL", DiegeticKit.KEY_ORANGE, size, &"max")
	register_pressable(&"all", all_key)
	column.append(all_key)
	for i in column.size():
		column[i].position = Vector3(column_x, top, (float(i) - 1.5) * depth / 4.0)
	return main


func _dealer_ok() -> bool:
	return dealer != null and is_instance_valid(dealer)


func _dealer_pose(pose: StringName, seconds: float) -> void:
	if not _dealer_ok():
		return
	dealer.set_pose(pose)
	if not is_inside_tree():
		return
	var d := dealer
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void:
		if is_instance_valid(d) and d.pose == pose:
			d.set_pose(&"idle"))


## Confetti (more on a crew roll) at `at` (machine space) with a green flash.
func _burst(at: Vector3, big: bool) -> void:
	flash(DiegeticKit.TEXT_WIN, 4.5 if big else 2.5, 0.8)
	if not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.name = "Confetti"
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 110 if big else 60
	p.lifetime = 1.8
	p.mesh = MeshFactory.quad(Vector2(0.03, 0.02))
	p.material_override = _confetti_material()
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.8 if big else 3.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.4
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([ArtPalette.NEON_MAGENTA, ArtPalette.NEON_CYAN, ArtPalette.NEON_LIME, ArtPalette.NEON_SUNFLOWER, ArtPalette.NEON_ORANGE, Color.WHITE])
	p.color_initial_ramp = g
	p.position = at
	visuals.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static var _confetti_mat: StandardMaterial3D


static func _confetti_material() -> StandardMaterial3D:
	if _confetti_mat == null:
		_confetti_mat = StandardMaterial3D.new()
		_confetti_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_confetti_mat.vertex_color_use_as_albedo = true
		_confetti_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _confetti_mat


static func _ints(values: Variant) -> Array[int]:
	var out: Array[int] = []
	if values is Array:
		for v: Variant in values:
			out.append(int(v))
	return out


static func _round_rect(hw: float, hd: float, r: float, steps: int = 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(hw - r, hd - r), Vector2(-hw + r, hd - r), Vector2(-hw + r, -hd + r), Vector2(hw - r, -hd + r)]
	for i in 4:
		for k in steps + 1:
			var a := PI * 0.5 * float(i) + PI * 0.5 * float(k) / float(steps)
			pts.append((corners[i] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


## A round padded tube along a closed loop of XZ points (the tub's rail).
static func _tube_loop(path: PackedVector2Array, tube: float, sides: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var n := path.size()
	for i in n + 1:
		var p := path[i % n]
		var prev := path[(i - 1 + n) % n]
		var next := path[(i + 1) % n]
		var t := (next - prev).normalized()
		var out := Vector3(t.y, 0.0, -t.x)
		var c := Vector3(p.x, 0.0, p.y)
		for j in sides + 1:
			var phi := TAU * float(j) / float(sides)
			var nrm := out * cos(phi) + Vector3.UP * sin(phi)
			verts.append(c + nrm * tube)
			normals.append(nrm)
			uvs.append(Vector2(float(i) / float(n), float(j) / float(sides)))
	for i in n:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			indices.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))
	for k in range(0, indices.size(), 3):
		var a := verts[indices[k]]
		var cr := (verts[indices[k + 1]] - a).cross(verts[indices[k + 2]] - a)
		var nn := normals[indices[k]] + normals[indices[k + 1]] + normals[indices[k + 2]]
		if cr.dot(nn) > 0.0:
			var tmp := indices[k + 1]
			indices[k + 1] = indices[k + 2]
			indices[k + 2] = tmp
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
