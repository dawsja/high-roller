class_name FirstPersonHands
extends Node3D
## The local player's two big soft mitten hands, a child of the first-person
## camera (camera space: -Z forward, +Y up, origin at the eye). Each hand is a
## round palm, a chunky thumb and three fat two-joint sausage fingers on a
## forearm stub that runs off the bottom of the screen, built from Primitives
## materials in the skin colour from set_skin().
##
## Every frame each hand eases to a target pose: the base pose (idle sway, the
## footstep bob from set_locomotion(), look sway, cupped round a held item,
## the raised ID card, flailing while carried, pulled back from a close wall)
## with the current one-shot animation blended over it. play(anim, target)
## runs one of ANIMS; a world-space `target` (press, point, grab, pull) makes
## the right hand reach for that point so the finger visibly lands on it.
## anim_event fires at the key moment of an animation (press &"contact", grab
## &"close", throw &"release", pull &"pulled", shove &"contact").
## Purely visual: it never presses anything itself.

signal anim_event(anim: StringName, event: StringName)
signal anim_finished(anim: StringName)

const ANIMS: Array[StringName] = [&"press", &"point", &"grab", &"throw", &"shake", &"wave", &"shove", &"pull", &"flip_card", &"celebrate"]
const ANIM_SECONDS := {
	&"press": 0.34, &"point": 0.8, &"grab": 0.5, &"throw": 0.55, &"shake": 0.9,
	&"wave": 1.3, &"shove": 0.38, &"pull": 0.7, &"flip_card": 0.55, &"celebrate": 1.3,
}
## Anim moment (0..1 of its length) and the anim_event it fires.
const ANIM_EVENTS := {
	&"press": [0.42, &"contact"], &"grab": [0.5, &"close"], &"throw": [0.5, &"release"],
	&"pull": [0.95, &"pulled"], &"shove": [0.35, &"contact"],
}
const HOLD_BOTH := &"both"
const HOLD_RIGHT := &"right"
const HOLD_LEFT := &"left"
const DEFAULT_SKIN := Color("ff8f73")

## Every hand measurement below is multiplied by this (cartoon-big hands).
const SIZE := 1.5
# Hand geometry (hand space, before SIZE: wrist at the origin, fingers along
# -Z, the back of the hand +Y, thumb toward -X on the right hand).
const PALM_RADIUS := 0.068
const PALM_SCALE := Vector3(1.14, 0.64, 1.02)
const PALM_CENTER := Vector3(0.0, 0.0, -0.068)
const FINGER_RADIUS := 0.0255
const FINGER_SEGMENT := 0.056
const FINGER_KNUCKLE_Z := -0.12
## Index, middle, ring (x for the right hand; the index sits by the thumb).
const FINGER_X: Array[float] = [-0.045, 0.0, 0.045]
const FINGER_LENGTH_SCALE: Array[float] = [1.0, 1.07, 0.9]
## Fingers fan out this much (radians, index outward) when open.
const FINGER_SPREAD: Array[float] = [0.14, 0.0, -0.14]
const THUMB_ROOT := Vector3(-0.058, -0.012, -0.045)
const THUMB_RADIUS := 0.029
const THUMB_LENGTH := 0.07
const FOREARM_RADIUS := 0.05
const FOREARM_LENGTH := 0.26
const GRIP_POINT := Vector3(0.0, -0.075, -0.075)
## Shoulder in camera space (right hand), the root of every reach.
const SHOULDER := Vector3(0.22, -0.42, 0.1)
## Where a held item sits between both cupped hands (camera space).
const CUP_CENTER := Vector3(0.0, -0.2, -0.44)
const MAX_REACH := 1.0
const HAND_SHARPNESS := 24.0

## A hand pose in camera space: wrist position, rotation, finger curls 0..1.
class Pose extends RefCounted:
	var pos := Vector3.ZERO
	var rot := Quaternion.IDENTITY
	var curl := 0.0
	var index := 0.0
	var thumb := 0.0

	func _init(p: Vector3 = Vector3.ZERO, r: Quaternion = Quaternion.IDENTITY, c: float = 0.0, i: float = -1.0, t: float = -1.0) -> void:
		pos = p
		rot = r
		curl = c
		index = c if i < 0.0 else i
		thumb = c * 0.6 if t < 0.0 else t

	func copy() -> Pose:
		return Pose.new(pos, rot, curl, index, thumb)

	func blend(other: Pose, w: float) -> Pose:
		if w <= 0.0:
			return copy()
		if w >= 1.0:
			return other.copy()
		return Pose.new(pos.lerp(other.pos, w), rot.slerp(other.rot, w), lerpf(curl, other.curl, w), lerpf(index, other.index, w), lerpf(thumb, other.thumb, w))


## One hand's nodes and its current (eased) pose.
class Hand extends RefCounted:
	var side := 1.0
	var root: Node3D
	var grip: Node3D
	var knuckles: Array[Node3D] = []
	var middles: Array[Node3D] = []
	var thumb: Node3D
	var tip: Node3D
	## The extended index fingertip in hand (root) space.
	var tip_local := Vector3.ZERO
	var meshes: Array[MeshInstance3D] = []
	var pose := Pose.new()


var skin: Color = DEFAULT_SKIN
## The node released items go to when their old parent is gone (the world).
var drop_parent: Node

var _right: Hand
var _left: Hand
var _cup_anchor: Node3D
var _card_anchor: Node3D
var _card: Node3D
var _card_raised := false
var _card_raise := 0.0
var _card_spin := 0.0
var _held: Node3D
var _held_mode: StringName = &""
var _held_parent: Node
var _shaking := false
var _flailing := false
var _anim: StringName = &""
var _anim_t := 0.0
var _anim_len := 1.0
var _anim_fired := false
var _anim_sustain := false
var _anim_target := Vector3.ZERO
var _anim_has_target := false
var _anim_two_hand_throw := false
var _phase := 0.0
var _bob := 0.0
var _sway := Vector2.ZERO
var _clearance := 10.0
var _retract := 0.0
var _hover_ready := 0.0
var _hover_goal := 0.0
var _time := 0.0
var _cup_half := 0.1


func _init() -> void:
	name = "Hands"
	_right = _build_hand(1.0)
	_left = _build_hand(-1.0)
	_cup_anchor = Node3D.new()
	_cup_anchor.name = "CupAnchor"
	add_child(_cup_anchor)
	_card_anchor = Node3D.new()
	_card_anchor.name = "CardAnchor"
	_left.root.add_child(_card_anchor)
	# The card sits where card_view() says when the left hand is in its card pose.
	var hand_at := _pose_transform(_mirror(_card_pose(), -1.0))
	_card_anchor.transform = hand_at.affine_inverse() * card_view()
	for hand: Hand in [_right, _left]:
		hand.pose = _rest(hand)
		_apply(hand)


# --- Public API -------------------------------------------------------------------

## Skin colour of both hands.
func set_skin(color: Color) -> void:
	skin = color
	for hand: Hand in [_right, _left]:
		for mi: MeshInstance3D in hand.meshes:
			mi.material_override = Primitives.material(color)


## Plays one of ANIMS (restarting it if it is already playing). `target` is an
## optional world-space point (Vector3) for the right hand to reach: the
## index finger lands on it for press / point, the palm for grab / pull.
## `sustain` holds the animation at its key moment (a press held down on the
## button) until release_sustain(). Unknown names are ignored (false).
func play(anim: StringName, target: Variant = null, sustain: bool = false) -> bool:
	if not ANIM_SECONDS.has(anim):
		return false
	_anim = anim
	_anim_sustain = sustain
	_anim_t = 0.0
	_anim_len = float(ANIM_SECONDS[anim])
	_anim_fired = false
	_anim_has_target = target is Vector3
	_anim_target = target if target is Vector3 else Vector3.ZERO
	_anim_two_hand_throw = anim == &"throw" and _held != null and _held_mode == HOLD_BOTH
	return true


## Lets a sustained animation (play(..., true)) finish.
func release_sustain() -> void:
	_anim_sustain = false


## The animation playing now, or &"".
func current_anim() -> StringName:
	return _anim


func is_playing(anim: StringName = &"") -> bool:
	return _anim != &"" and (anim == &"" or anim == _anim)


## Puts `item` in the hands: between both cupped hands (HOLD_BOTH, like a
## pair of dice before a throw) or in one palm (HOLD_RIGHT / HOLD_LEFT). The
## item is re-parented under the hands keeping its world transform, then eases
## into the grip. A held item is released first. Freeze physics bodies before.
func hold(item: Node3D, mode: StringName = HOLD_BOTH) -> void:
	if item == null or not is_instance_valid(item):
		return
	if _held != null:
		release_held()
	if mode != HOLD_RIGHT and mode != HOLD_LEFT:
		mode = HOLD_BOTH
	_held = item
	_held_mode = mode
	_held_parent = item.get_parent()
	_cup_half = clampf(_half_width(item) + PALM_RADIUS * SIZE * PALM_SCALE.y + 0.004, 0.085, 0.24)
	var anchor := _anchor_for(mode)
	if item.is_inside_tree() and anchor.is_inside_tree():
		item.reparent(anchor, true)
	else:
		if _held_parent != null:
			_held_parent.remove_child(item)
		anchor.add_child(item)


## Lets go of the held item and returns it (null if none). It keeps its world
## transform, back under its old parent (or drop_parent / the scene).
func release_held() -> Node3D:
	var item := _held
	_held = null
	_held_mode = &""
	_shaking = false
	if item == null or not is_instance_valid(item):
		return null
	var parent := _held_parent
	_held_parent = null
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		parent = drop_parent if drop_parent != null and is_instance_valid(drop_parent) else null
	if parent == null and is_inside_tree():
		parent = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	if parent == null:
		item.get_parent().remove_child(item)
		return item
	if item.is_inside_tree() and parent.is_inside_tree():
		item.reparent(parent, true)
	else:
		item.get_parent().remove_child(item)
		parent.add_child(item)
	return item


static func _set_layers(node: Node, layer: int) -> void:
	var vi := node as VisualInstance3D
	if vi != null:
		vi.layers = layer
	for child: Node in node.get_children():
		_set_layers(child, layer)


## Half the width (local X) of an item's meshes, at its current scale.
static func _half_width(item: Node3D) -> float:
	var box := _local_aabb(item, Transform3D.IDENTITY)
	if box.size == Vector3.ZERO:
		return 0.04
	return maxf(absf(box.position.x), absf(box.end.x)) * absf(item.scale.x)


static func _local_aabb(node: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var vi := node as VisualInstance3D
	if vi != null:
		out = xform * vi.get_aabb()
	for child: Node in node.get_children():
		var c3 := child as Node3D
		if c3 == null:
			continue
		var sub := _local_aabb(child, xform * c3.transform)
		if sub.size != Vector3.ZERO:
			out = sub if out.size == Vector3.ZERO else out.merge(sub)
	return out


func is_holding() -> bool:
	return _held != null and is_instance_valid(_held)


func held_item() -> Node3D:
	return _held if is_holding() else null


func hold_mode() -> StringName:
	return _held_mode if is_holding() else &""


## Both cupped hands rattle what they hold (dice) until shake(false).
func shake(active: bool) -> void:
	_shaking = active


func is_shaking() -> bool:
	return _shaking


## Arms up and waving (carried over a guard's shoulder).
func set_flail(active: bool) -> void:
	_flailing = active


func is_flailing() -> bool:
	return _flailing


## Puts `card` (an IdCard3D, any Node3D) in the left hand and raises it into
## view. null or hide_id_card() lowers it again (the card stays in the hand,
## hidden once it is down).
func show_id_card(card: Node3D) -> void:
	if card == null:
		hide_id_card()
		return
	if card != _card:
		if _card != null and is_instance_valid(_card) and _card.get_parent() == _card_anchor:
			_card_anchor.remove_child(_card)
		_card = card
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		_card_anchor.add_child(card)
		card.transform = Transform3D.IDENTITY
		_set_layers(card, FpTuning.VIEW_LAYER)
	_card.visible = true
	_card_raised = true


func hide_id_card() -> void:
	_card_raised = false


func is_card_raised() -> bool:
	return _card_raised


## The card in the left hand (raised or not), or null.
func id_card() -> Node3D:
	return _card


## Where the raised card's centre sits in camera space (front toward the eye).
static func card_view() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(0.08, 0.14, 0.03)), Vector3(-0.025, -0.04, -0.31))


## The footstep phase (a step every PI) and bob strength 0..1, from the head.
func set_locomotion(phase: float, weight: float) -> void:
	_phase = phase
	_bob = weight


## The view turned by these angles (radians): the hands lag behind a little.
func add_look_sway(yaw_delta: float, pitch_delta: float) -> void:
	_sway += Vector2(yaw_delta, pitch_delta)
	_sway = _sway.limit_length(0.35)


## Distance from the eye to the nearest wall straight ahead: closer than
## FpTuning.HANDS_CLEARANCE the hands pull back so they don't poke through.
func set_clearance(distance: float) -> void:
	_clearance = distance


## Something pressable is in reach: the right index finger gets ready.
func set_ready_to_press(ready: bool) -> void:
	_hover_goal = 1.0 if ready else 0.0


## Right index fingertip in world space (camera space when out of the tree).
func fingertip_position() -> Vector3:
	if _right.tip.is_inside_tree():
		return _right.tip.global_position
	return _pose_transform(_right.pose) * _right.tip_local


## Root (wrist) node of a hand: &"right" or &"left".
func hand_node(which: StringName) -> Node3D:
	return _left.root if which == HOLD_LEFT else _right.root


## Jumps every hand straight to its target pose (no easing).
func snap() -> void:
	for hand: Hand in [_right, _left]:
		hand.pose = _target_pose(hand)
		_apply(hand)


## Steps the hands by `delta` seconds (what _process does; tests call it).
func advance(delta: float) -> void:
	_time += delta
	_card_raise = move_toward(_card_raise, 1.0 if _card_raised else 0.0, delta * 4.5)
	if not _card_raised and _card_raise <= 0.0 and _card != null and is_instance_valid(_card):
		_card.visible = false
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-7.0 * delta))
	var goal := clampf((FpTuning.HANDS_CLEARANCE - _clearance) / FpTuning.HANDS_CLEARANCE * 1.8, 0.0, 1.0)
	_retract = lerpf(_retract, goal, 1.0 - exp(-12.0 * delta))
	_hover_ready = lerpf(_hover_ready, _hover_goal, 1.0 - exp(-10.0 * delta))
	if _anim != &"":
		_anim_t += delta
		if _anim_sustain:
			var hold_at := float(ANIM_EVENTS[_anim][0]) if ANIM_EVENTS.has(_anim) else 0.5
			_anim_t = minf(_anim_t, hold_at * _anim_len + 0.0001)
		var u := _anim_t / _anim_len
		if ANIM_EVENTS.has(_anim) and not _anim_fired and u >= float(ANIM_EVENTS[_anim][0]):
			_anim_fired = true
			anim_event.emit(_anim, ANIM_EVENTS[_anim][1])
		if u >= 1.0:
			var done := _anim
			_anim = &""
			_card_spin = 0.0
			anim_finished.emit(done)
	var k := 1.0 - exp(-HAND_SHARPNESS * delta)
	for hand: Hand in [_right, _left]:
		hand.pose = hand.pose.blend(_target_pose(hand), k)
		_apply(hand)
	_update_anchors(delta)


func _process(delta: float) -> void:
	advance(delta)


# --- Poses (right hand; _mirror() makes the left) -------------------------------

## A rotation whose fingers (-Z) point along `fingers` with the back of the
## hand (+Y) toward `back`.
static func aim(fingers: Vector3, back: Vector3) -> Quaternion:
	var z := -fingers.normalized()
	var y := (back - z * back.dot(z))
	y = y.normalized() if y.length_squared() > 0.000001 else Vector3.UP
	var x := y.cross(z)
	return Basis(x, y, z).get_rotation_quaternion()


## A right-hand pose from where the palm's centre should be (camera space),
## the finger direction and the back-of-hand direction.
static func palm_pose(palm: Vector3, fingers: Vector3, back: Vector3, curl: float, index: float = -1.0, thumb: float = -1.0) -> Pose:
	var rot := aim(fingers, back)
	return Pose.new(palm - Basis(rot) * (PALM_CENTER * SIZE), rot, curl, index, thumb)


static func _rest_pose() -> Pose:
	return palm_pose(Vector3(0.43, -0.3, -0.45), Vector3(-0.36, 0.84, -0.4), Vector3(0.3, 0.25, 0.92), 0.25, 0.18, 0.1)


## The right hand cupped round an item centred at CUP_CENTER, its palm
## `half_width` to the side.
static func _cup_pose_raw(half_width: float) -> Pose:
	return palm_pose(CUP_CENTER + Vector3(half_width + 0.012, 0.03, 0.02), Vector3(-0.3, 0.28, -0.91), Vector3(0.82, 0.48, 0.3), 0.42, 0.38, 0.45)


static func _one_hand_pose() -> Pose:
	return palm_pose(Vector3(0.24, -0.27, -0.45), Vector3(-0.3, 0.35, -0.9), Vector3(0.15, -1.0, 0.2), 0.5, 0.45, 0.3)


## The left hand pinching the card's corner (written as the right hand, mirrored).
static func _card_pose() -> Pose:
	return palm_pose(Vector3(0.2, -0.205, -0.335), Vector3(-0.5, 0.82, -0.3), Vector3(0.85, 0.05, 0.5), 0.5, 0.42, 0.0)


func _target_pose(hand: Hand) -> Pose:
	var p := _base_pose(hand)
	if _anim != &"":
		var u := clampf(_anim_t / _anim_len, 0.0, 1.0)
		p = _anim_pose(hand, p, u)
	# Pull back from a wall in front.
	p.pos += Vector3(0.03 * hand.side, -0.1, 0.15) * _retract
	return p


func _base_pose(hand: Hand) -> Pose:
	var s := hand.side
	var p := _rest(hand)
	var w := _bob
	var step := 1.0 - absf(sin(_phase))
	# Footstep bob: both dip on each step and swing a little against each other.
	p.pos += Vector3(cos(_phase) * 0.012 * w, -step * 0.028 * w + 0.012 * w, sin(_phase) * 0.03 * w * s)
	p.rot = p.rot * Quaternion(Vector3.RIGHT, sin(_phase) * 0.07 * w * s)
	# Idle breathing.
	p.pos.y += sin(_time * 1.7 + s) * 0.005
	p.rot = p.rot * Quaternion(Vector3.RIGHT, sin(_time * 1.3 + s * 0.6) * 0.03)
	# Look sway: the hands trail the view.
	p.pos += Vector3(_sway.x * 0.09, -_sway.y * 0.09, 0.0)
	if hand == _right:
		p.index = lerpf(p.index, 0.0, _hover_ready)
		p.pos += Vector3(-0.015, 0.02, -0.025) * _hover_ready
	if is_holding():
		if _held_mode == HOLD_BOTH:
			p = _cup_pose(hand)
		elif (_held_mode == HOLD_RIGHT and hand == _right) or (_held_mode == HOLD_LEFT and hand == _left):
			p = _mirror(_one_hand_pose(), s)
			p.pos.y += -step * 0.02 * w
	if hand == _left and _card_raise > 0.0:
		var raised := _mirror(_card_pose(), -1.0)
		raised.pos += Vector3(_sway.x * 0.05, -step * 0.012 * w - _sway.y * 0.05, 0.0)
		var lowered := raised.copy()
		lowered.pos += Vector3(0.0, -0.36, 0.1)
		var e := _ease_in_out(_card_raise)
		p = lowered.blend(raised, e) if _card_raised else p.blend(lowered.blend(raised, e), minf(1.0, _card_raise * 3.0))
	if _flailing:
		var t := _time
		var sw := sin(t * 12.0 + s * 1.3)
		p = _mirror(Pose.new(
			Vector3(0.28 + sin(t * 9.0 + s) * 0.05, -0.1 + sin(t * 12.5 + s * 1.7) * 0.08, -0.42),
			aim(Vector3(sw * 0.6, 1.0, -0.3), Vector3(0.2, 0.0, 1.0)),
			0.12 + 0.12 * sin(t * 17.0 + s)), s)
	return p


func _rest(hand: Hand) -> Pose:
	return _mirror(_rest_pose(), hand.side)


func _cup_pose(hand: Hand) -> Pose:
	var p := _mirror(_cup_pose_raw(_cup_half), hand.side)
	p.pos += Vector3(0.0, -(1.0 - absf(sin(_phase))) * 0.018 * _bob, 0.0)
	if _shaking:
		p.pos += _shake_offset()
	return p


func _shake_offset() -> Vector3:
	return Vector3(sin(_time * 33.0) * 0.018, sin(_time * 41.0) * 0.024 + 0.012, sin(_time * 27.0) * 0.008)


## Mirrors a right-hand pose for side -1 (the left hand).
static func _mirror(p: Pose, side: float) -> Pose:
	if side > 0.0:
		return p
	var q := p.rot
	return Pose.new(Vector3(-p.pos.x, p.pos.y, p.pos.z), Quaternion(q.x, -q.y, -q.z, q.w), p.curl, p.index, p.thumb)


func _anim_pose(hand: Hand, base: Pose, u: float) -> Pose:
	var s := hand.side
	var right := hand == _right
	match _anim:
		&"press":
			if not right:
				return base
			var reach := _reach_pose(hand, _target_or(Vector3(0.02, -0.08, -0.6)), hand.tip_local)
			reach.curl = 1.0
			reach.index = 0.0
			reach.thumb = 0.85
			# The pointing shape forms first, then the jab lands and comes back.
			var shaped := base.copy()
			var sw := _env(u, 0.18, 0.8)
			shaped.curl = lerpf(base.curl, 1.0, sw)
			shaped.index = lerpf(base.index, 0.0, sw)
			shaped.thumb = lerpf(base.thumb, 0.85, sw)
			return shaped.blend(reach, _env(u, 0.42, 0.56))
		&"point":
			if not right:
				return base
			var aim_pose := _reach_pose(hand, _target_or(Vector3(0.0, 0.0, -1.5)), hand.tip_local, 0.62)
			aim_pose.curl = 1.0
			aim_pose.index = 0.0
			aim_pose.thumb = 0.8
			return base.blend(aim_pose, _env(u, 0.25, 0.75))
		&"grab":
			if not right:
				return base
			var g := _reach_pose(hand, _target_or(Vector3(0.05, -0.14, -0.6)), GRIP_POINT * SIZE)
			var close := smoothstep(0.42, 0.6, u)
			g.curl = close
			g.index = close
			g.thumb = 0.2 + 0.6 * close
			return base.blend(g, _env(u, 0.45, 0.62))
		&"throw":
			if not right and not _anim_two_hand_throw:
				return base
			var wind := _mirror(Pose.new(Vector3(0.27, -0.1, -0.24), aim(Vector3(0.0, 1.0, 0.2), Vector3(0.6, 0.0, 0.8)), 0.8), s)
			var fling := _mirror(Pose.new(Vector3(0.06, -0.08, -0.74), aim(Vector3(-0.1, 0.3, -1.0), Vector3(0.2, 1.0, 0.2)), 0.0), s)
			if _anim_two_hand_throw:
				wind = _mirror(Pose.new(Vector3(0.1, -0.21, -0.26), aim(Vector3(-0.2, 0.7, -0.6), Vector3(0.85, 0.2, 0.5)), 0.68), s)
				fling = _mirror(Pose.new(Vector3(0.12, -0.06, -0.74), aim(Vector3(-0.1, 0.4, -0.9), Vector3(0.7, 0.6, 0.3)), 0.0), s)
			if u < 0.38:
				return base.blend(wind, _ease_in_out(u / 0.38))
			if u < 0.6:
				return wind.blend(fling, _ease_out((u - 0.38) / 0.22))
			return fling.blend(base, _ease_in_out((u - 0.6) / 0.4))
		&"shake":
			var c := _cup_pose(hand)
			c.pos += _shake_offset()
			return base.blend(c, _env(u, 0.15, 0.85))
		&"wave":
			if not right:
				return base
			var a := sin(u * 13.0) * 0.5
			var wv := Pose.new(Vector3(0.26, -0.06, -0.46), aim(Vector3(sin(a), cos(a), -0.15), Vector3(0.0, 0.1, 1.0)), 0.0, 0.0, 0.0)
			return base.blend(wv, _env(u, 0.15, 0.85))
		&"shove":
			var sh := _mirror(Pose.new(Vector3(0.22, -0.17, -0.6), aim(Vector3(0.05, 1.0, -0.15), Vector3(-0.1, 0.15, 1.0)), 0.05, 0.05, 0.45), s)
			return base.blend(sh, _env(u, 0.3, 0.55, true))
		&"pull":
			if not right:
				return base
			var up := _reach_pose(hand, _target_or(Vector3(0.16, 0.06, -0.62)), GRIP_POINT * SIZE)
			up.curl = smoothstep(0.25, 0.4, u)
			up.index = up.curl
			up.thumb = 0.3 + 0.5 * up.curl
			var down := Pose.new(Vector3(0.2, -0.32, -0.44), aim(Vector3(-0.3, 0.2, -0.93), Vector3(0.2, 1.0, 0.1)), 1.0, 1.0, 0.8)
			if u < 0.35:
				return base.blend(up, _ease_out(u / 0.35))
			if u < 0.9:
				return up.blend(down, _ease_in_out((u - 0.35) / 0.55))
			return down.blend(base, (u - 0.9) / 0.1)
		&"flip_card":
			if right:
				return base
			_card_spin = TAU * _ease_in_out(u) if _card_raised else 0.0
			var f := base.copy()
			f.rot = f.rot * Quaternion(Vector3.BACK, sin(u * PI) * (0.25 if _card_raised else 1.2) * s)
			f.pos.y += sin(u * PI) * 0.03
			return f
		&"celebrate":
			var cel := _mirror(Pose.new(Vector3(0.24, -0.04 + absf(sin(u * PI * 4.0)) * 0.07, -0.48), aim(Vector3(-0.1, 1.0, -0.2), Vector3(0.3, 0.0, 1.0)), 1.0, 1.0, 0.75), s)
			return base.blend(cel, _env(u, 0.12, 0.85))
	return base


## A right-hand pose reaching from the shoulder so that `tip` (hand space)
## lands on `point` (camera space), at most MAX_REACH (or `max_reach`) away;
## the back of the hand stays up.
func _reach_pose(_hand: Hand, point: Vector3, tip: Vector3, max_reach: float = MAX_REACH) -> Pose:
	var to := point - SHOULDER
	var dist := to.length()
	var dir := to / dist if dist > 0.001 else Vector3.FORWARD
	var goal := SHOULDER + dir * minf(dist, max_reach)
	var rot := aim(dir, Vector3(0.3, 1.0, 0.3))
	return Pose.new(goal - Basis(rot) * tip, rot, 0.0)


## The anim's world target in camera space, or `fallback` when it has none.
func _target_or(fallback: Vector3) -> Vector3:
	if not _anim_has_target:
		return fallback
	if is_inside_tree():
		return global_transform.affine_inverse() * _anim_target
	return _anim_target


## Envelope: eases 0 -> 1 by `rise`, holds, eases back to 0 from `fall`.
func _env(u: float, rise: float, fall: float, snappy: bool = false) -> float:
	if u < rise:
		var r := u / rise
		return _ease_out(r) if snappy else _ease_in_out(r)
	if u < fall:
		return 1.0
	return _ease_in_out(1.0 - (u - fall) / maxf(0.001, 1.0 - fall))


static func _ease_in_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


# --- Nodes ------------------------------------------------------------------------

static func _pose_transform(p: Pose) -> Transform3D:
	return Transform3D(Basis(p.rot), p.pos)


func _apply(hand: Hand) -> void:
	var p := hand.pose
	hand.root.transform = _pose_transform(p)
	for i in hand.knuckles.size():
		var c := p.index if i == 0 else p.curl
		hand.knuckles[i].rotation = Vector3(-c * 1.25, hand.side * FINGER_SPREAD[i] * (1.0 - c * 0.7), 0.0)
		hand.middles[i].rotation = Vector3(-c * 1.35, 0.0, 0.0)
	hand.thumb.rotation = Vector3(-0.1 - p.thumb * 0.8, hand.side * (0.85 - p.thumb * 0.75), hand.side * 0.15)


func _update_anchors(delta: float) -> void:
	# The cup centre follows the two hands (bob, shake, throw).
	var mid := (_right.pose.pos + _left.pose.pos) * 0.5
	var rest_mid := (_cup_pose_raw(_cup_half).pos * Vector3(0.0, 1.0, 1.0))
	_cup_anchor.position = CUP_CENTER + (mid - rest_mid)
	_cup_anchor.quaternion = Quaternion.IDENTITY
	if _card != null and is_instance_valid(_card):
		_card.rotation = Vector3(0.0, _card_spin, 0.0)
	if is_holding():
		var k := 1.0 - exp(-14.0 * delta)
		_held.position = _held.position.lerp(Vector3.ZERO, k)


func _anchor_for(mode: StringName) -> Node3D:
	match mode:
		HOLD_RIGHT:
			return _right.grip
		HOLD_LEFT:
			return _left.grip
	return _cup_anchor


func _build_hand(side: float) -> Hand:
	var hand := Hand.new()
	hand.side = side
	hand.root = Node3D.new()
	hand.root.name = "RightHand" if side > 0.0 else "LeftHand"
	add_child(hand.root)
	var palm := _part(hand, _sphere_mesh(PALM_RADIUS * SIZE), hand.root, PALM_CENTER * SIZE)
	palm.scale = PALM_SCALE
	# A knuckle ridge so the mitten reads as a hand from above.
	var ridge := _part(hand, _sphere_mesh(PALM_RADIUS * 0.72 * SIZE), hand.root, Vector3(0.0, 0.004, FINGER_KNUCKLE_Z + 0.014) * SIZE)
	ridge.scale = Vector3(1.5, 0.62, 0.62)
	# Wrist and forearm stub, running back and down off the screen.
	var wrist := _part(hand, _sphere_mesh(FOREARM_RADIUS * 1.1 * SIZE), hand.root, Vector3(0.0, -0.004, 0.008) * SIZE)
	wrist.scale = Vector3(1.05, 0.85, 1.0)
	var arm := _part(hand, _capsule_mesh(FOREARM_RADIUS * SIZE, FOREARM_LENGTH * SIZE), hand.root, Vector3(0.0, -0.01, FOREARM_LENGTH * 0.5 - 0.01) * SIZE)
	arm.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	arm.scale = Vector3(1.0, 1.0, 0.85)
	for i in FINGER_X.size():
		var length := FINGER_SEGMENT * FINGER_LENGTH_SCALE[i] * SIZE
		var radius := FINGER_RADIUS * SIZE
		var knuckle := Node3D.new()
		knuckle.name = "Finger%d" % i
		knuckle.position = Vector3(FINGER_X[i] * side, 0.0, FINGER_KNUCKLE_Z) * SIZE
		hand.root.add_child(knuckle)
		var base_seg := _part(hand, _capsule_mesh(radius, length + radius * 2.0), knuckle, Vector3(0.0, 0.0, -length * 0.5))
		base_seg.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		var middle := Node3D.new()
		middle.name = "Tip"
		middle.position = Vector3(0.0, 0.0, -length)
		knuckle.add_child(middle)
		var tip_seg := _part(hand, _capsule_mesh(radius * 0.96, length + radius * 2.0), middle, Vector3(0.0, 0.0, -length * 0.5))
		tip_seg.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		hand.knuckles.append(knuckle)
		hand.middles.append(middle)
		if i == 0:
			hand.tip = Node3D.new()
			hand.tip.name = "IndexTip"
			hand.tip.position = Vector3(0.0, 0.0, -length - radius)
			middle.add_child(hand.tip)
			# Extended and spread, in hand space.
			var spread := Basis(Vector3.UP, side * FINGER_SPREAD[0])
			hand.tip_local = knuckle.position + spread * (middle.position + hand.tip.position)
	hand.thumb = Node3D.new()
	hand.thumb.name = "Thumb"
	hand.thumb.position = Vector3(THUMB_ROOT.x * side, THUMB_ROOT.y, THUMB_ROOT.z) * SIZE
	hand.root.add_child(hand.thumb)
	var thumb_len := THUMB_LENGTH * SIZE
	var thumb_mesh := _part(hand, _capsule_mesh(THUMB_RADIUS * SIZE, thumb_len + THUMB_RADIUS * SIZE * 2.0), hand.thumb, Vector3(0.0, 0.0, -thumb_len * 0.5))
	thumb_mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	hand.grip = Node3D.new()
	hand.grip.name = "Grip"
	hand.grip.position = GRIP_POINT * SIZE
	hand.root.add_child(hand.grip)
	return hand


func _part(hand: Hand, mesh: Mesh, parent: Node3D, pos: Vector3) -> MeshInstance3D:
	var mi := Primitives.mesh_instance(mesh, skin)
	mi.position = pos
	mi.layers = FpTuning.VIEW_LAYER
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	hand.meshes.append(mi)
	return mi


static func _sphere_mesh(radius: float) -> Mesh:
	return MeshFactory.ball(radius, 5)


static func _capsule_mesh(radius: float, height: float) -> Mesh:
	return MeshFactory.capsule(radius, maxf(height, radius * 2.0), 14, 4)
