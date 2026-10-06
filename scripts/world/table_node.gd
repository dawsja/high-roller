class_name TableNode
extends Node3D
## One casino table (or slot machine) on the floor: the per-game prop from
## TableProps, a dealer (a host at the big wheel, nobody at slot machines), the
## game's name, the table Interactable and the result effects. Purely visual:
## the director feeds it the sim's `bet` (play_result), `hand` (show_hand),
## `dealer_swap` and `fire_alarm` (set_closed) events and turns
## `interactable.used` into a sit request.
##
## Table space: floor at y = 0, the seat on the +Z side (a seated player faces
## -Z), the dealer on the -Z side facing the seat. Every animation is a Tween
## bound to this node, so freeing the table mid-animation is safe.

signal result_shown(table_id: StringName)

const WIN_COLOR := Color(0.3, 1.0, 0.45)
const LOSE_COLOR := Color(1.0, 0.25, 0.22)
const LOUD_COLOR := Color(1.0, 0.82, 0.25)
const NEUTRAL_COLOR := Color(0.95, 0.95, 0.9)
const COOL_COLOR := Color(0.45, 0.8, 1.0)
const CLOSED_COLOR := Color(0.95, 0.15, 0.15)
const CHIP_COLORS: Array[Color] = [Color("d62839"), Color("2e86de"), Color("27ae60"), Color("f4f1ea"), Color("1b1b1f"), Color("f2c230")]
## A swapped dealer walks this far sideways off (and the new one on).
const SWAP_WALK := 1.6
## The big wheel's host dresses for the show.
const HOST_LOOK := {"hat": "top_hat", "top": "sequin_blazer", "bottom": "pressed_slacks"}

var table_id: StringName = &""
var game_type: int = HR.GameType.SLOTS
var area_id: StringName = &""
var rung: int = Tuning.TOP_RUNG
## TableGames.display_name for this rung.
var display_name: String = ""
var prop: TableProps.Prop
## Collision on the world layer (layer 1) so players and guards walk around.
var body: StaticBody3D
var interactable: Interactable
## The dealer (the host at the big wheel); null at slot machines.
var dealer: CharacterModel
var name_label: Label3D
var closed: bool = false

var _closed_sign: Node3D
var _flash_light: OmniLight3D
var _pop_label: Label3D
var _fx_root: Node3D
var _rng := RandomNumberGenerator.new()
var _anim_tween: Tween
var _flash_tween: Tween
var _pop_tween: Tween
var _swap_tween: Tween
var _tint_tween: Tween
var _host_tween: Tween
var _current: Dictionary = {}
var _pending_hand: Dictionary = {}
var _has_pending_hand := false
var _dealer_serial := 0


func setup(p_table_id: StringName, p_game_type: int, p_area_id: StringName, p_rung: int) -> void:
	_teardown()
	table_id = p_table_id
	game_type = p_game_type
	area_id = p_area_id
	rung = p_rung
	name = "Table_%s" % String(table_id) if table_id != &"" else "Table"
	_rng.seed = hash(String(table_id))
	var casino: Dictionary = CasinoLadder.casino(rung)
	var accent: Color = casino.get("accent_color", TableProps.GOLD)
	display_name = TableGames.display_name(game_type, rung)
	prop = TableProps.create(game_type, accent, _rng.seed)
	prop.name = "Prop"
	add_child(prop)
	body = prop.body
	interactable = Interactable.create(&"table", "Play %s" % display_name, Tuning.TABLE_INTERACT_RADIUS, {"table_id": table_id})
	interactable.position = prop.interact_point
	add_child(interactable)
	name_label = Label3D.new()
	prop.place_name(name_label, display_name, accent.lightened(0.35))
	if prop.has_dealer:
		dealer = _spawn_dealer()
		dealer.position = prop.dealer_spot
		dealer.rotation.y = prop.dealer_yaw
	_build_fx()
	_build_closed_sign()
	set_closed(false)


## Where a seated player goes (floor point under the stool, facing the
## table), in world space once the table is in the tree. Index > 0 gives the
## extra stools some tables have (see seat_count()).
func seat_transform(index: int = 0) -> Transform3D:
	if prop == null:
		return _xform()
	return _xform() * Transform3D(Basis.IDENTITY, prop.seat_position(index))


func seat_count() -> int:
	return prop.seat_count if prop != null else 0


## Seconds play_result takes for `duration` (<= 0: the default share of the
## game's round time), clamped to at most the round time.
func result_seconds(duration: float = -1.0) -> float:
	var round_s: float = float(TableGames.def(game_type).get("round_seconds", 3.0))
	var s: float = duration if duration > 0.0 else round_s * Tuning.TABLE_RESULT_SHARE
	return clampf(s, Tuning.TABLE_RESULT_MIN_SECONDS, maxf(round_s, Tuning.TABLE_RESULT_MIN_SECONDS))


## Animates a BetResult.to_dict() (reels, wheel, dice, ball, cards), then the
## win/loss flash and caption, and emits result_shown when it ends. A result
## arriving mid-animation snaps the previous one to its end first (which
## emits its result_shown); the crew's copies of one shared dice roll play once.
func play_result(result: Dictionary, duration: float = -1.0) -> void:
	if prop == null:
		return
	if is_animating() and _is_same_roll(result):
		return
	finish_result()
	var seconds: float = result_seconds(duration)
	var spin: float = seconds * Tuning.TABLE_REVEAL_SHARE
	_current = result.duplicate(true)
	prop.prepare(result, spin)
	if not is_inside_tree():
		prop.step(1.0)
		prop.on_reveal(result)
		_finish()
		return
	_anim_tween = create_tween()
	_anim_tween.tween_method(prop.step, 0.0, 1.0, maxf(spin, 0.01))
	_anim_tween.tween_callback(_reveal.bind(result))
	_anim_tween.tween_interval(maxf(seconds - spin, 0.01))
	_anim_tween.tween_callback(_finish)


func is_animating() -> bool:
	return _anim_tween != null and _anim_tween.is_valid()


## A high-low / blackjack round in progress (FloorSim `hand` state). While a
## result is animating the hand waits and is shown when it ends.
func show_hand(state: Dictionary) -> void:
	if prop == null:
		return
	if is_animating():
		_pending_hand = state.duplicate(true)
		_has_pending_hand = true
		return
	prop.show_hand(state)


## The dealer walks off and a differently tinted dealer walks in: the cue
## that the table cooled. At a slot machine it is just a cold flash.
func dealer_swap() -> void:
	if prop == null:
		return
	_finish_tween(_swap_tween)
	_show_pop("NEW DEALER" if dealer != null else "COOLED", COOL_COLOR, false)
	_flash(COOL_COLOR, Tuning.TABLE_FLASH_ENERGY, Tuning.TABLE_FLASH_RANGE, Tuning.TABLE_FLASH_SECONDS, 1)
	if dealer == null:
		return
	_kill(_host_tween)
	var old: CharacterModel = dealer
	_dealer_serial += 1
	var fresh := _spawn_dealer()
	dealer = fresh
	var spot: Vector3 = prop.dealer_spot
	var yaw: float = prop.dealer_yaw
	var side: Vector3 = prop.swap_dir.normalized() * SWAP_WALK
	_tint(fresh)
	if not is_inside_tree():
		old.queue_free()
		fresh.position = spot
		fresh.rotation.y = yaw
		return
	var total: float = Tuning.TABLE_DEALER_SWAP_SECONDS
	var walk: float = total * 0.36
	var speed: float = SWAP_WALK / walk
	var out_yaw: float = atan2(-side.x, -side.z)
	var in_yaw: float = atan2(side.x, side.z)
	old.set_move_speed(speed)
	fresh.set_move_speed(speed)
	fresh.position = spot + side
	fresh.rotation.y = in_yaw
	fresh.scale = Vector3.ONE * 0.01
	fresh.visible = false
	var tw := create_tween()
	_swap_tween = tw
	tw.tween_callback(old.set_pose.bind(&"walk"))
	tw.tween_property(old, "rotation:y", old.rotation.y + wrapf(out_yaw - old.rotation.y, -PI, PI), total * 0.08)
	tw.tween_property(old, "position", old.position + side, walk)
	tw.tween_property(old, "scale", Vector3.ONE * 0.01, total * 0.06)
	tw.tween_callback(old.queue_free)
	tw.tween_callback(_dealer_enters.bind(fresh))
	tw.tween_property(fresh, "scale", Vector3.ONE, total * 0.06)
	tw.tween_property(fresh, "position", spot, walk)
	tw.tween_callback(fresh.set_pose.bind(&"idle"))
	tw.tween_property(fresh, "rotation:y", in_yaw + wrapf(yaw - in_yaw, -PI, PI), total * 0.08)


## Fire alarm: shows a CLOSED sign and rope, and disables the interactable.
func set_closed(value: bool) -> void:
	closed = value
	if interactable != null:
		interactable.enabled = not value
	if _closed_sign != null:
		_closed_sign.visible = value


## The big strobing flash of a loud result (big wheel, slot jackpot).
func flash_loud(color: Color = LOUD_COLOR) -> void:
	_flash(color, Tuning.TABLE_LOUD_FLASH_ENERGY, Tuning.TABLE_LOUD_FLASH_RANGE, Tuning.TABLE_LOUD_FLASH_SECONDS, Tuning.TABLE_LOUD_FLASH_PULSES)
	if prop != null:
		prop.on_loud(Tuning.TABLE_LOUD_FLASH_SECONDS)


## Snaps a running result animation to its end (emits result_shown).
func finish_result() -> void:
	if is_animating():
		var tw := _anim_tween
		tw.custom_step(1000.0)
		tw.kill()
	_anim_tween = null


## Snaps every running table animation (result, hand deal, dealer swap) to its end.
func finish_animations() -> void:
	finish_result()
	if prop != null:
		prop.finish_hand()
	_finish_tween(_swap_tween)


## What the prop shows right now: per game (reels, segment, dice, number,
## cards). For tests and the debug overlay.
func shown_state() -> Dictionary:
	return prop.shown() if prop != null else {}


func get_pop_text() -> String:
	return _pop_label.text if _pop_label != null and _pop_label.visible else ""


func get_flash_energy() -> float:
	return _flash_light.light_energy if _flash_light != null else 0.0


# --- Internals -------------------------------------------------------------------

func _xform() -> Transform3D:
	return global_transform if is_inside_tree() else transform


func _teardown() -> void:
	for tw: Tween in [_anim_tween, _flash_tween, _pop_tween, _swap_tween, _tint_tween, _host_tween]:
		_kill(tw)
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	prop = null
	body = null
	interactable = null
	dealer = null
	name_label = null
	_closed_sign = null
	_flash_light = null
	_pop_label = null
	_fx_root = null
	_has_pending_hand = false
	_pending_hand = {}
	_current = {}


func _spawn_dealer() -> CharacterModel:
	var m := CharacterModel.new()
	if game_type == HR.GameType.BIG_WHEEL:
		m.apply_outfit(Outfit.new(HOST_LOOK))
	else:
		m.apply_uniform(&"dealer")
	m.appearance_seed = hash(String(table_id)) + _dealer_serial * 7919
	m.name = "Dealer_%d" % _dealer_serial
	add_child(m)
	return m


func _dealer_enters(model: CharacterModel) -> void:
	if is_instance_valid(model):
		model.visible = true
		model.set_pose(&"walk")


## The new dealer comes on cold-tinted with a blue ring; both fade out.
func _tint(model: CharacterModel) -> void:
	_kill(_tint_tween)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(COOL_COLOR, 0.45)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = mat
	model.set_highlight(Color(COOL_COLOR, 0.85))
	if not is_inside_tree():
		return
	_tint_tween = create_tween()
	_tint_tween.tween_method(_tint_step.bind(model, mat), 1.0, 0.0, Tuning.TABLE_DEALER_TINT_SECONDS)
	_tint_tween.tween_callback(_clear_tint.bind(model))


func _tint_step(k: float, model: CharacterModel, mat: StandardMaterial3D) -> void:
	mat.albedo_color = Color(COOL_COLOR, 0.45 * k)
	if is_instance_valid(model):
		model.set_highlight(Color(COOL_COLOR, 0.85 * k))


func _clear_tint(model: CharacterModel) -> void:
	if not is_instance_valid(model):
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = null
	model.set_highlight(Color(0, 0, 0, 0))


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for c: Node in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


func _build_fx() -> void:
	_fx_root = Node3D.new()
	_fx_root.name = "Fx"
	add_child(_fx_root)
	_flash_light = OmniLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.position = prop.light_point
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = Tuning.TABLE_FLASH_RANGE
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	_fx_root.add_child(_flash_light)
	_pop_label = Label3D.new()
	_pop_label.name = "Pop"
	_pop_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pop_label.no_depth_test = true
	_pop_label.render_priority = 10
	_pop_label.outline_render_priority = 9
	_pop_label.font_size = 64
	_pop_label.outline_size = 14
	_pop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop_label.position = prop.pop_point
	_pop_label.visible = false
	_fx_root.add_child(_pop_label)


func _build_closed_sign() -> void:
	_closed_sign = Node3D.new()
	_closed_sign.name = "ClosedSign"
	add_child(_closed_sign)
	var seat: Vector3 = prop.seat_position(0)
	var z: float = seat.z + 0.3
	for x: float in [-0.55, 0.55]:
		var post := Primitives.cylinder(0.035, 0.9, TableProps.GOLD, 8)
		post.position = Vector3(seat.x + x, 0.45, z)
		_closed_sign.add_child(post)
		var foot := Primitives.cylinder(0.14, 0.03, TableProps.GOLD, 10)
		foot.position = Vector3(seat.x + x, 0.015, z)
		_closed_sign.add_child(foot)
	var rope := Primitives.cylinder(0.022, 1.1, CLOSED_COLOR.darkened(0.3), 6)
	rope.rotation.z = PI * 0.5
	rope.position = Vector3(seat.x, 0.84, z)
	_closed_sign.add_child(rope)
	var sign_label := Label3D.new()
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.modulate = CLOSED_COLOR
	sign_label.outline_modulate = Color.WHITE
	sign_label.outline_size = 12
	TableProps.fit_label(sign_label, "CLOSED", 1.6, 0.45)
	sign_label.position = Vector3(seat.x, 1.8, seat.z - 0.45)
	_closed_sign.add_child(sign_label)
	_closed_sign.visible = false


func _is_same_roll(result: Dictionary) -> bool:
	if int(result.get("game_type", -1)) != HR.GameType.DICE:
		return false
	var a := TableProps.detail_of(result)
	var b := TableProps.detail_of(_current)
	return bool(a.get("shared", false)) and bool(b.get("shared", false)) and a.get("dice") == b.get("dice")


func _reveal(result: Dictionary) -> void:
	var d := TableProps.detail_of(result)
	var won: bool = bool(result.get("won", false))
	var loud: bool = bool(result.get("loud", false))
	var jackpot: bool = bool(result.get("jackpot", false))
	var net: int = int(result.get("net", 0))
	var bet: int = int(result.get("bet", 0))
	prop.on_reveal(result)
	if bet <= 0 and bool(d.get("finished", false)):
		return  # a no-op result (round already over): nothing to celebrate
	var lines := PackedStringArray()
	var cap: String = prop.caption(result)
	if cap != "":
		lines.append(cap)
	var color: Color
	var cheer := false
	if bool(d.get("cash_out", false)) and not d.has("next_card"):
		lines.append("+%d" % net if net > 0 else "EVEN")
		color = WIN_COLOR if net > 0 else NEUTRAL_COLOR
		cheer = net > 0
	elif won:
		color = WIN_COLOR
		cheer = true
		if jackpot:
			lines.append("JACKPOT! +%d" % net)
			color = LOUD_COLOR
		elif int(result.get("payout", 0)) > 0:
			lines.append(("BIG WIN +%d" if loud else "WIN +%d") % net)
			if loud:
				color = LOUD_COLOR
		elif d.has("pot"):
			lines.append("POT %d" % int(d["pot"]))
		else:
			lines.append("WIN")
	else:
		color = LOSE_COLOR
		lines.append("LOSE -%d" % bet if bet > 0 else "LOSE")
	_show_pop("\n".join(lines), color, loud and won)
	if loud:
		flash_loud(LOUD_COLOR if won else LOSE_COLOR)
	else:
		_flash(color, Tuning.TABLE_FLASH_ENERGY, Tuning.TABLE_FLASH_RANGE, Tuning.TABLE_FLASH_SECONDS, 1)
	if cheer:
		_burst(Tuning.TABLE_LOUD_BURST_CHIPS if loud else Tuning.TABLE_BURST_CHIPS)
		if dealer != null and game_type == HR.GameType.BIG_WHEEL:
			_kill(_host_tween)
			dealer.set_pose(&"celebrate")
			_host_tween = create_tween()
			_host_tween.tween_interval(Tuning.TABLE_POP_HOLD_SECONDS)
			_host_tween.tween_callback(_host_rest)


func _host_rest() -> void:
	if dealer != null and is_instance_valid(dealer):
		dealer.set_pose(&"idle")


func _finish() -> void:
	_anim_tween = null
	_current = {}
	if _has_pending_hand:
		var state := _pending_hand
		_has_pending_hand = false
		_pending_hand = {}
		prop.show_hand(state)
	result_shown.emit(table_id)


func _flash(color: Color, energy: float, reach: float, seconds: float, pulses: int) -> void:
	if _flash_light == null or not is_inside_tree():
		return
	_kill(_flash_tween)
	_flash_light.light_color = color
	_flash_light.omni_range = reach
	_flash_tween = create_tween()
	_flash_tween.tween_method(_flash_step.bind(energy, pulses), 0.0, 1.0, maxf(seconds, 0.01))


func _flash_step(t: float, energy: float, pulses: int) -> void:
	var wave := 1.0
	if pulses > 1:
		wave = 0.55 + 0.45 * cos(t * float(pulses) * TAU)
	var e: float = energy * pow(1.0 - t, 1.5) * wave
	_flash_light.light_energy = e
	_flash_light.visible = e > 0.001


func _show_pop(text: String, color: Color, big: bool) -> void:
	if _pop_label == null:
		return
	_kill(_pop_tween)
	_pop_label.text = text
	_pop_label.pixel_size = 0.0058 if big else 0.0038
	_pop_label.modulate = color
	_pop_label.outline_modulate = Color(0.05, 0.05, 0.06, 1.0)
	_pop_label.position = prop.pop_point
	_pop_label.visible = true
	if not is_inside_tree():
		return
	_pop_label.scale = Vector3.ONE * 0.3
	_pop_tween = create_tween()
	_pop_tween.tween_property(_pop_label, "scale", Vector3.ONE * 1.18, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_pop_label, "scale", Vector3.ONE, 0.1)
	_pop_tween.parallel().tween_property(_pop_label, "position", prop.pop_point + Vector3(0.0, 0.15, 0.0), Tuning.TABLE_POP_HOLD_SECONDS)
	_pop_tween.tween_property(_pop_label, "modulate:a", 0.0, 0.35)
	_pop_tween.parallel().tween_property(_pop_label, "outline_modulate:a", 0.0, 0.35)
	_pop_tween.tween_callback(_pop_label.hide)


func _burst(count: int) -> void:
	if _fx_root == null or not is_inside_tree() or count <= 0:
		return
	var chips: Array = []
	var vel: Array = []
	var origin: Vector3 = prop.burst_point
	for i in count:
		var c := Primitives.cylinder(0.045, 0.014, CHIP_COLORS[i % CHIP_COLORS.size()], 10)
		c.position = origin
		_fx_root.add_child(c)
		chips.append(c)
		var a: float = _rng.randf() * TAU
		var out: float = _rng.randf_range(0.5, 1.5)
		vel.append(Vector3(cos(a) * out, _rng.randf_range(2.2, 3.4), sin(a) * out))
	var tw := create_tween()
	tw.tween_method(_burst_step.bind(chips, vel, origin), 0.0, 1.0, Tuning.TABLE_BURST_SECONDS)
	tw.tween_callback(_free_all.bind(chips))


func _burst_step(t: float, chips: Array, vel: Array, origin: Vector3) -> void:
	var time: float = t * Tuning.TABLE_BURST_SECONDS
	for i in chips.size():
		var c: Node3D = chips[i]
		if not is_instance_valid(c):
			continue
		var v: Vector3 = vel[i]
		var p: Vector3 = origin + v * time + Vector3(0.0, -4.9 * time * time, 0.0)
		p.y = maxf(p.y, 0.01)
		c.position = p
		c.rotation = Vector3(time * 9.0 + float(i), time * 5.0, 0.0)
		c.scale = Vector3.ONE * clampf((1.0 - t) * 4.0, 0.02, 1.0)


func _free_all(nodes: Array) -> void:
	for n: Variant in nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()


func _finish_tween(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.custom_step(1000.0)
		tw.kill()


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()
