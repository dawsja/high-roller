class_name CharacterModel
extends Node3D
## Chunky low-poly person built from Primitives: about 1.8 m tall, feet at the
## origin, facing -Z. Shared by players, guards, dealers and patrons.
##
## apply_outfit() gives every OutfitCatalog piece id its own shape (NONE draws
## nothing); apply_uniform() dresses casino staff; set_pose() picks a procedural
## animation that runs in _process (advance() steps it by hand).
## Purely visual: it never changes chips, Heat, IDs or outfits.

## A one-shot pose (tumble) finished and the model went back to idle.
signal pose_finished(pose: StringName)

const POSES: Array[StringName] = [&"idle", &"walk", &"run", &"sit", &"play", &"celebrate", &"carried", &"carry", &"tackle", &"dive", &"tumble", &"jump"]
const UNIFORMS: Array[StringName] = [&"guard", &"pit_boss", &"head_of_security", &"dealer", &"staff"]

# Body measurements in metres (rest pose, unscaled).
const HIP_Y := 0.86
const THIGH_LEN := 0.42
const SHIN_LEN := 0.36
const SHOE_H := 0.08
const LEG_LEN := THIGH_LEN + SHIN_LEN + SHOE_H
const LEG_X := 0.12
const SPINE_Y := 0.06
const TORSO_SIZE := Vector3(0.5, 0.5, 0.28)
const SHOULDER_POS := Vector3(0.32, 0.42, 0.0)
const UPPER_ARM_LEN := 0.28
const FOREARM_LEN := 0.26
const NECK_Y := 0.48
const HEAD_R := 0.2
const HEAD_Y := 0.2
const HEAD_CENTER_Y := HIP_Y + SPINE_Y + NECK_Y + HEAD_Y
const HEAD_TOP := HEAD_CENTER_Y + HEAD_R
## Hip height while seated: thighs level, shins straight down, soles on the floor.
const SIT_HIP_Y := SHIN_LEN + SHOE_H
## Glasses sit in this plane (head space), in front of the cartoon eyes.
const GLASS_Z := -0.245

const SKIN_TONES := [Color("f6d5b8"), Color("eebf94"), Color("d49e6e"), Color("b07a4c"), Color("8a5636"), Color("5c3922")]
const HAIR_COLORS := [Color("1d1714"), Color("3e2717"), Color("6f4626"), Color("d9b45f"), Color("a7461d"), Color("8c8c8c")]
const SHOE_COLORS := [Color("2a2a2e"), Color("5b3b22"), Color("ececec"), Color("23395b")]
const EYE_WHITE := Color("f7f7f2")
const PUPIL := Color("1a1a1e")
const MOUTH := Color("6b2b2b")
const SHIRT_WHITE := Color("f4f4f0")
const GOLD := Color("d4a72c")
const SILVER := Color("c8ccd2")
const LENS_DARK := Color("1d2026")
const LENS_CLEAR := Color(0.85, 0.93, 1.0, 0.45)
const UNIFORM_SHOES := Color("141416")

# Dressing groups: HR.OutfitSlot values, plus two extra groups for uniform bits.
const _EXTRA_A := 5
const _EXTRA_B := 6

# Joint indices into _joints / _target / _from.
const J_HIPS := 0
const J_SPINE := 1
const J_NECK := 2
const J_SH_L := 3
const J_SH_R := 4
const J_EL_L := 5
const J_EL_R := 6
const J_LEG_L := 7
const J_LEG_R := 8
const J_KNEE_L := 9
const J_KNEE_R := 10
const JOINT_COUNT := 11

## Current pose (read-only; use set_pose).
var pose: StringName = &"idle"
## Copy of the last applied Outfit; null while wearing a non-staff uniform.
var outfit: Outfit = null
## Uniform kind from apply_uniform(), or &"" when wearing an outfit.
var uniform: StringName = &""
## Seeds skin tone, hair and shoes: same seed, same person.
var appearance_seed: int = 0: set = set_appearance_seed
var skin_color: Color = SKIN_TONES[0]

static var _mesh_cache: Dictionary = {}

var _rig: Node3D
var _hips: Node3D
var _spine: Node3D
var _neck: Node3D
var _head: Node3D
var _shoulders: Array[Node3D] = []
var _elbows: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _knees: Array[Node3D] = []
var _joints: Array[Node3D] = []

var _pelvis: MeshInstance3D
var _torso: MeshInstance3D
var _neck_mesh: MeshInstance3D
var _head_mesh: MeshInstance3D
var _nose: MeshInstance3D
var _ears: Array[MeshInstance3D] = []
var _upper_arms: Array[MeshInstance3D] = []
var _forearms: Array[MeshInstance3D] = []
var _hands: Array[MeshInstance3D] = []
var _thighs: Array[MeshInstance3D] = []
var _shins: Array[MeshInstance3D] = []
var _shoes: Array[MeshInstance3D] = []
var _hair: Array[MeshInstance3D] = []
var _hair_cap: MeshInstance3D
var _hair_puff: MeshInstance3D
var _ring: MeshInstance3D
var _disc: MeshInstance3D

var _groups: Dictionary = {}
var _primary: Dictionary = {}
var _dressed: Dictionary = {}
var _hat_hides_hair := false
var _forearms_skin := false
var _thighs_skin := false
var _shins_skin := false
var _shoe_color: Color = SHOE_COLORS[0]
var _head_top_local := HEAD_TOP
var _highlight := Color(0, 0, 0, 0)

var _move_speed := -1.0
var _time := 0.0
var _pose_time := 0.0
var _phase := 0.0
var _blend := 1.0
var _target: Array[Vector3] = []
var _from: Array[Vector3] = []
var _target_offset := Vector3.ZERO
var _from_offset := Vector3.ZERO


func _init() -> void:
	_build_body()
	_build_highlight()
	_target.resize(JOINT_COUNT)
	_target.fill(Vector3.ZERO)
	_from.resize(JOINT_COUNT)
	_from.fill(Vector3.ZERO)
	_apply_appearance()
	apply_outfit(Outfit.new())
	advance(0.0)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		advance(delta)


# --- Public API ---------------------------------------------------------------

## Dresses the model in an outfit: each slot's piece gets its own shape and
## the catalog color. Only slots that changed are rebuilt.
func apply_outfit(new_outfit: Outfit) -> void:
	if new_outfit == null:
		new_outfit = Outfit.new()
	if uniform != &"":
		uniform = &""
		_dress(_EXTRA_A, OutfitCatalog.NONE, Color(0, 0, 0, 0))
		_dress(_EXTRA_B, OutfitCatalog.NONE, Color(0, 0, 0, 0))
		_set_size(1.0)
		_set_shoes(_shoe_color)
	outfit = new_outfit.copy()
	for slot: int in OutfitCatalog.all_slots():
		var id: StringName = outfit.get_piece(slot)
		_dress(slot, id, OutfitCatalog.piece_color(id))
	_after_dress()


## Dresses casino staff: &"guard", &"pit_boss", &"head_of_security",
## &"dealer" or &"staff" (the OutfitCatalog staff uniform).
func apply_uniform(kind: StringName) -> void:
	if not UNIFORMS.has(kind):
		push_warning("CharacterModel: unknown uniform '%s'" % kind)
		return
	if kind == &"staff":
		apply_outfit(OutfitCatalog.staff_uniform())
		uniform = &"staff"
		return
	var none := Color(0, 0, 0, 0)
	var look: Dictionary = {}
	var size := 1.0
	match kind:
		&"guard":
			var navy := Color("1f2b4a")
			look = {
				HR.OutfitSlot.HAT: [&"u_guard_cap", navy],
				HR.OutfitSlot.GLASSES: [OutfitCatalog.NONE, none],
				HR.OutfitSlot.TOP: [&"u_suit", navy],
				HR.OutfitSlot.BOTTOM: [&"u_suit_pants", Color("19223c")],
				HR.OutfitSlot.ACCESSORY: [&"u_earpiece", Color("101012")],
				_EXTRA_A: [&"u_tie", Color("10131c")],
				_EXTRA_B: [OutfitCatalog.NONE, none],
			}
		&"pit_boss":
			look = {
				HR.OutfitSlot.HAT: [OutfitCatalog.NONE, none],
				HR.OutfitSlot.GLASSES: [OutfitCatalog.NONE, none],
				HR.OutfitSlot.TOP: [&"u_suit", Color("3b3e44")],
				HR.OutfitSlot.BOTTOM: [&"u_suit_pants", Color("34373c")],
				HR.OutfitSlot.ACCESSORY: [&"u_tie", Color("c0262d")],
				_EXTRA_A: [&"u_earpiece", Color("101012")],
				_EXTRA_B: [&"u_pocket_square", Color("c0262d")],
			}
		&"head_of_security":
			size = Tuning.HEAD_OF_SECURITY_MODEL_SCALE
			look = {
				HR.OutfitSlot.HAT: [OutfitCatalog.NONE, none],
				HR.OutfitSlot.GLASSES: [&"u_black_shades", Color("0b0b0d")],
				HR.OutfitSlot.TOP: [&"u_suit", Color("15151a")],
				HR.OutfitSlot.BOTTOM: [&"u_suit_pants", Color("121216")],
				HR.OutfitSlot.ACCESSORY: [&"u_badge", GOLD],
				_EXTRA_A: [&"u_tie", Color("0b0b0d")],
				_EXTRA_B: [&"u_earpiece", Color("101012")],
			}
		&"dealer":
			look = {
				HR.OutfitSlot.HAT: [OutfitCatalog.NONE, none],
				HR.OutfitSlot.GLASSES: [OutfitCatalog.NONE, none],
				HR.OutfitSlot.TOP: [&"u_dealer_vest", Color("17171b")],
				HR.OutfitSlot.BOTTOM: [&"u_suit_pants", Color("141418")],
				HR.OutfitSlot.ACCESSORY: [&"bow_tie", Color("141418")],
				_EXTRA_A: [OutfitCatalog.NONE, none],
				_EXTRA_B: [OutfitCatalog.NONE, none],
			}
	outfit = null
	uniform = kind
	_set_size(size)
	_set_shoes(UNIFORM_SHOES)
	for group: int in look:
		var entry: Array = look[group]
		_dress(group, entry[0] as StringName, entry[1] as Color)
	_after_dress()


## Switches the procedural animation (one of POSES). Setting the current pose
## again does nothing, so it is safe to call every frame.
func set_pose(new_pose: StringName) -> void:
	if not POSES.has(new_pose):
		push_warning("CharacterModel: unknown pose '%s'" % new_pose)
		new_pose = &"idle"
	if new_pose == pose:
		return
	pose = new_pose
	_pose_time = 0.0
	_blend = 0.0
	for i in JOINT_COUNT:
		_from[i] = _joints[i].rotation
	_from_offset = _hips.position - Vector3(0, HIP_Y, 0)


## Ground speed in m/s; scales the walk/run/carry limb swing. Until this is
## called those poses use their default speed (walk, run or guard carry).
func set_move_speed(speed: float) -> void:
	_move_speed = maxf(speed, 0.0)


## Tints a ring under the feet. Color(0, 0, 0, 0) (any zero alpha) turns it off.
func set_highlight(color: Color) -> void:
	_highlight = color
	var on := color.a > 0.0
	_ring.visible = on
	_disc.visible = on
	if on:
		_ring.material_override = Primitives.material(Color(color, 0.9), 0.0, true)
		_disc.material_override = Primitives.material(Color(color, 0.22), 0.0, true)


func is_highlighted() -> bool:
	return _highlight.a > 0.0


func get_highlight() -> Color:
	return _highlight


## Height of the top of the head (hat and hair included) above the feet, in
## this node's local space, for indicators above the head. Rest pose.
func get_head_top() -> float:
	return _head_top_local * _rig.scale.y


## Local point on top of the right shoulder: where a carried model's origin goes
## (the carried pose lies across its own origin, belly down).
func get_carry_offset() -> Vector3:
	return Vector3(0.2, HIP_Y + SPINE_Y + TORSO_SIZE.y, 0.02) * _rig.scale.y


## Color a slot renders with (its main mesh), or Color(0, 0, 0, 0) for an empty slot.
func get_slot_color(slot: int) -> Color:
	var mi: MeshInstance3D = _primary.get(slot) as MeshInstance3D
	if mi == null or not is_instance_valid(mi):
		return Color(0, 0, 0, 0)
	return (mi.material_override as StandardMaterial3D).albedo_color


## Piece id the slot is rendering (also uniform-only ids like &"u_suit").
func get_slot_piece(slot: int) -> StringName:
	return _dressed.get(slot, [OutfitCatalog.NONE])[0] as StringName


## The extra meshes built for a slot's piece (base body parts not included).
func get_slot_parts(slot: int) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	for n: Variant in _groups.get(slot, []):
		if is_instance_valid(n):
			parts.append(n as MeshInstance3D)
	return parts


## Bounds of every visible mesh in this node's local space (current pose).
func get_body_aabb() -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _all_meshes(_rig):
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != self and n != null:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * mi.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


## Steps the animation by delta seconds. _process calls it every frame.
func advance(delta: float) -> void:
	_time += delta
	_pose_time += delta
	var rate := minf(_effective_speed() * Tuning.CHARACTER_STRIDE_RADIANS_PER_METER, Tuning.CHARACTER_MAX_STRIDE_RATE)
	_phase = fmod(_phase + delta * rate, TAU)
	_pose_targets()
	if Tuning.CHARACTER_POSE_BLEND_SECONDS > 0.0:
		_blend = minf(1.0, _blend + delta / Tuning.CHARACTER_POSE_BLEND_SECONDS)
	else:
		_blend = 1.0
	var w := smoothstep(0.0, 1.0, _blend)
	for i in JOINT_COUNT:
		_joints[i].rotation = _from[i].lerp(_target[i], w)
	_hips.position = Vector3(0, HIP_Y, 0) + _from_offset.lerp(_target_offset, w)
	if pose == &"tumble" and _pose_time >= Tuning.CHARACTER_TUMBLE_SECONDS:
		set_pose(&"idle")
		pose_finished.emit(&"tumble")


func set_appearance_seed(value: int) -> void:
	appearance_seed = value
	if _rig != null:
		_apply_appearance()


# --- Body ---------------------------------------------------------------------

func _build_body() -> void:
	_rig = _pivot(self, Vector3.ZERO)
	_hips = _pivot(_rig, Vector3(0, HIP_Y, 0))
	_pelvis = _add(_hips, _box_mesh(Vector3(0.44, 0.2, 0.26)), Color.WHITE, Vector3(0, 0.02, 0))
	_spine = _pivot(_hips, Vector3(0, SPINE_Y, 0))
	_torso = _add(_spine, _box_mesh(TORSO_SIZE), Color.WHITE, Vector3(0, TORSO_SIZE.y * 0.5 - 0.01, 0))
	_neck = _pivot(_spine, Vector3(0, NECK_Y, 0))
	_neck_mesh = _add(_neck, _cyl_mesh(0.075, 0.12, 8), Color.WHITE, Vector3(0, 0.03, 0))
	_head = _pivot(_neck, Vector3(0, HEAD_Y, 0))
	_head_mesh = _add(_head, _sphere_mesh(HEAD_R, 12), Color.WHITE, Vector3.ZERO)
	_nose = _add(_head, _box_mesh(Vector3(0.05, 0.06, 0.05)), Color.WHITE, Vector3(0, -0.01, -0.2))
	_add(_head, _box_mesh(Vector3(0.1, 0.022, 0.02)), MOUTH, Vector3(0, -0.085, -0.183))
	for s: float in [-1.0, 1.0]:
		_ears.append(_add(_head, _sphere_mesh(0.05, 6), Color.WHITE, Vector3(s * 0.195, 0.0, 0.0), Vector3.ZERO, -1, 0.0, Vector3(0.6, 1.0, 1.0)))
		_add(_head, _sphere_mesh(0.05, 8), EYE_WHITE, Vector3(s * 0.075, 0.035, -0.162))
		_add(_head, _sphere_mesh(0.027, 6), PUPIL, Vector3(s * 0.075, 0.035, -0.205))

		var shoulder := _pivot(_spine, Vector3(s * SHOULDER_POS.x, SHOULDER_POS.y, 0))
		_upper_arms.append(_add(shoulder, _box_mesh(Vector3(0.15, UPPER_ARM_LEN + 0.06, 0.16)), Color.WHITE, Vector3(0, -UPPER_ARM_LEN * 0.5 + 0.02, 0)))
		var elbow := _pivot(shoulder, Vector3(0, -UPPER_ARM_LEN, 0))
		_forearms.append(_add(elbow, _box_mesh(Vector3(0.13, FOREARM_LEN + 0.03, 0.14)), Color.WHITE, Vector3(0, -FOREARM_LEN * 0.5, 0)))
		_hands.append(_add(elbow, _sphere_mesh(0.075, 8), Color.WHITE, Vector3(0, -FOREARM_LEN - 0.04, 0)))
		_shoulders.append(shoulder)
		_elbows.append(elbow)

		var leg := _pivot(_hips, Vector3(s * LEG_X, 0, 0))
		_thighs.append(_add(leg, _box_mesh(Vector3(0.19, THIGH_LEN + 0.06, 0.21)), Color.WHITE, Vector3(0, -THIGH_LEN * 0.5 + 0.02, 0)))
		var knee := _pivot(leg, Vector3(0, -THIGH_LEN, 0))
		_shins.append(_add(knee, _box_mesh(Vector3(0.17, SHIN_LEN + 0.02, 0.19)), Color.WHITE, Vector3(0, -SHIN_LEN * 0.5, 0)))
		_shoes.append(_add(knee, _box_mesh(Vector3(0.19, SHOE_H, 0.3)), Color.WHITE, Vector3(0, -SHIN_LEN - SHOE_H * 0.5, -0.05)))
		_legs.append(leg)
		_knees.append(knee)
	_joints.assign([_hips, _spine, _neck, _shoulders[0], _shoulders[1], _elbows[0], _elbows[1], _legs[0], _legs[1], _knees[0], _knees[1]])


func _build_highlight() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 4
	_ring = _add(self, torus, Color.WHITE, Vector3(0, 0.03, 0), Vector3.ZERO, -1, 0.0, Vector3(1.0, 0.25, 1.0))
	_disc = _add(self, _cyl_mesh(0.44, 0.01, 24), Color.WHITE, Vector3(0, 0.012, 0))
	for mi: MeshInstance3D in [_ring, _disc]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false


func _apply_appearance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(appearance_seed)
	skin_color = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	var hair_color: Color = HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]
	var hair_style := rng.randi_range(0, 5)
	_shoe_color = SHOE_COLORS[rng.randi_range(0, SHOE_COLORS.size() - 1)]
	_build_hair(hair_style, hair_color)
	_refresh_skin()
	if uniform == &"" or uniform == &"staff":
		_set_shoes(_shoe_color)
	_update_hair()


## Hair styles: 0-1 short, 2 long, 3 bun, 4 afro, 5 bald.
func _build_hair(style: int, color: Color) -> void:
	for mi: MeshInstance3D in _hair:
		if is_instance_valid(mi):
			mi.free()
	_hair.clear()
	_hair_cap = null
	_hair_puff = null
	if style == 5:
		return
	_hair_cap = _add(_head, _hemi_mesh(0.207), color, Vector3(0, 0.03, 0.02), Vector3(0.45, 0, 0))
	_hair.append(_hair_cap)
	match style:
		2:
			_hair.append(_add(_head, _box_mesh(Vector3(0.36, 0.36, 0.1)), color, Vector3(0, -0.07, 0.15)))
		3:
			_hair_puff = _add(_head, _sphere_mesh(0.09, 8), color, Vector3(0, 0.2, 0.13))
			_hair.append(_hair_puff)
		4:
			_hair_puff = _add(_head, _sphere_mesh(0.24, 10), color, Vector3(0, 0.1, 0.09), Vector3.ZERO, -1, 0.0, Vector3(1.0, 0.9, 1.0))
			_hair.append(_hair_puff)


func _update_hair() -> void:
	var has_hat := not OutfitCatalog.is_none(get_slot_piece(HR.OutfitSlot.HAT))
	if _hair_cap != null:
		_hair_cap.visible = not _hat_hides_hair
	if _hair_puff != null:
		_hair_puff.visible = not has_hat
	_update_head_top()


func _update_head_top() -> void:
	var top := HEAD_R
	for child: Node in _head.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not mi.visible:
			continue
		top = maxf(top, (mi.transform * mi.get_aabb()).end.y)
	_head_top_local = HEAD_CENTER_Y + top


func _refresh_skin() -> void:
	for mi: MeshInstance3D in [_head_mesh, _neck_mesh, _ears[0], _ears[1], _hands[0], _hands[1]]:
		_recolor(mi, skin_color)
	_recolor(_nose, skin_color.darkened(0.12))
	for i in 2:
		if _forearms_skin:
			_recolor(_forearms[i], skin_color)
		if _thighs_skin:
			_recolor(_thighs[i], skin_color)
		if _shins_skin:
			_recolor(_shins[i], skin_color)


func _set_shoes(color: Color) -> void:
	for mi: MeshInstance3D in _shoes:
		_recolor(mi, color)


func _set_size(s: float) -> void:
	_rig.scale = Vector3.ONE * s
	_ring.scale = Vector3(s, 0.25, s)
	_disc.scale = Vector3(s, 1.0, s)
	_update_head_top()


# --- Dressing -----------------------------------------------------------------

func _dress(group: int, id: StringName, color: Color) -> void:
	var entry: Array = _dressed.get(group, [])
	if not entry.is_empty() and entry[0] == id and entry[1] == color:
		return
	_clear_group(group)
	_dressed[group] = [id, color]
	match group:
		HR.OutfitSlot.HAT:
			_build_hat(id, color)
		HR.OutfitSlot.GLASSES:
			_build_glasses(id, color)
		HR.OutfitSlot.TOP:
			_build_top(id, color)
		HR.OutfitSlot.BOTTOM:
			_build_bottom(id, color)
		_:
			_build_accessory(id, color, group)


func _after_dress() -> void:
	_update_hair()


func _clear_group(group: int) -> void:
	for n: Variant in _groups.get(group, []):
		if is_instance_valid(n):
			(n as Node).free()
	_groups.erase(group)
	_primary.erase(group)


func _build_hat(id: StringName, c: Color) -> void:
	var g := HR.OutfitSlot.HAT
	var dark := c.darkened(0.4)
	_hat_hides_hair = true
	match id:
		&"lucky_ball_cap":
			_add(_head, _hemi_mesh(0.216), c, Vector3(0, 0.06, 0.01), Vector3(0.1, 0, 0), g)
			_add(_head, _box_mesh(Vector3(0.26, 0.022, 0.2)), c, Vector3(0, 0.1, -0.27), Vector3(-0.12, 0, 0), g)
			_add(_head, _sphere_mesh(0.025, 6), dark, Vector3(0, 0.275, 0.03), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.08, 0.06, 0.02)), Color("fff3c4"), Vector3(0, 0.16, -0.19), Vector3(-0.5, 0, 0), g)
		&"ten_gallon_hat":
			_add(_head, _cyl_mesh(0.19, 0.2, 10, 0.165), c, Vector3(0, 0.21, 0), Vector3.ZERO, g)
			_add(_head, _cyl_mesh(0.36, 0.03, 14), c, Vector3(0, 0.115, 0), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _box_mesh(Vector3(0.08, 0.03, 0.42)), c, Vector3(s * 0.32, 0.15, 0), Vector3(0, 0, s * 0.7), g)
			_add(_head, _cyl_mesh(0.195, 0.04, 10), dark, Vector3(0, 0.145, 0), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.05, 0.04, 0.24)), c.darkened(0.15), Vector3(0, 0.31, 0), Vector3.ZERO, g)
		&"high_roller_fedora":
			_add(_head, _cyl_mesh(0.175, 0.16, 10, 0.15), c, Vector3(0, 0.19, 0), Vector3.ZERO, g)
			_add(_head, _cyl_mesh(0.27, 0.022, 14), c, Vector3(0, 0.115, 0), Vector3(-0.08, 0, 0), g)
			_add(_head, _cyl_mesh(0.18, 0.04, 10), Color("111114"), Vector3(0, 0.14, 0), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.05, 0.03, 0.22)), dark, Vector3(0, 0.265, 0), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.012, 0.06, 0.03)), Color("e8d27a"), Vector3(0.18, 0.15, 0.0), Vector3.ZERO, g)
		&"bucket_hat":
			_add(_head, _cyl_mesh(0.2, 0.14, 10, 0.165), c, Vector3(0, 0.19, 0), Vector3.ZERO, g)
			_add(_head, _cyl_mesh(0.28, 0.07, 12, 0.2), c.darkened(0.1), Vector3(0, 0.1, 0), Vector3.ZERO, g)
		&"top_hat":
			_add(_head, _cyl_mesh(0.155, 0.32, 10), c, Vector3(0, 0.27, 0), Vector3.ZERO, g)
			_add(_head, _cyl_mesh(0.25, 0.025, 14), c, Vector3(0, 0.11, 0), Vector3.ZERO, g)
			_add(_head, _cyl_mesh(0.16, 0.05, 10), Color("b3202a"), Vector3(0, 0.15, 0), Vector3.ZERO, g)
		&"poker_visor":
			_hat_hides_hair = false
			_add(_head, _cyl_mesh(0.222, 0.05, 12), c, Vector3(0, 0.07, 0), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.28, 0.018, 0.19)), Color(c, 0.8), Vector3(0, 0.085, -0.29), Vector3(-0.3, 0, 0), g)
		&"pom_pom_beanie":
			_add(_head, _hemi_mesh(0.222), c, Vector3(0, 0.07, 0), Vector3.ZERO, g, 0.0, Vector3(1.0, 1.15, 1.0))
			_add(_head, _cyl_mesh(0.226, 0.07, 12), c.darkened(0.2), Vector3(0, 0.095, 0), Vector3.ZERO, g)
			_add(_head, _sphere_mesh(0.07, 8), Color("f5f5f5"), Vector3(0, 0.34, 0), Vector3.ZERO, g)
		&"birthday_crown":
			_add(_head, _cyl_mesh(0.17, 0.1, 10), c, Vector3(0, 0.17, 0), Vector3.ZERO, g, 0.15)
			for i in 5:
				var a := TAU * float(i) / 5.0
				_add(_head, _cyl_mesh(0.035, 0.1, 6, 0.0), c, Vector3(sin(a) * 0.15, 0.27, -cos(a) * 0.15), Vector3.ZERO, g, 0.15)
			_add(_head, _sphere_mesh(0.03, 6), Color("e0115f"), Vector3(0, 0.17, -0.172), Vector3.ZERO, g)
		&"staff_hat":
			_add(_head, _cyl_mesh(0.165, 0.12, 10), c, Vector3(0, 0.2, 0), Vector3(0, 0, 0.12), g)
			_add(_head, _cyl_mesh(0.17, 0.03, 10), GOLD, Vector3(-0.005, 0.16, 0), Vector3(0, 0, 0.12), g)
			_add(_head, _sphere_mesh(0.022, 6), GOLD, Vector3(-0.01, 0.265, 0), Vector3.ZERO, g)
		&"u_guard_cap":
			_add(_head, _cyl_mesh(0.2, 0.1, 12, 0.235), c, Vector3(0, 0.21, 0), Vector3.ZERO, g)
			_add(_head, _cyl_mesh(0.2, 0.06, 12), Color("101012"), Vector3(0, 0.14, 0), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.24, 0.02, 0.13)), Color("101012"), Vector3(0, 0.11, -0.23), Vector3(-0.35, 0, 0), g)
			_add(_head, _box_mesh(Vector3(0.05, 0.055, 0.015)), GOLD, Vector3(0, 0.2, -0.214), Vector3(-0.15, 0, 0), g, 0.3)
		_:
			_hat_hides_hair = false
			if not OutfitCatalog.is_none(id):
				_add(_head, _hemi_mesh(0.215), c, Vector3(0, 0.06, 0), Vector3.ZERO, g)
				_hat_hides_hair = true


func _build_glasses(id: StringName, c: Color) -> void:
	var g := HR.OutfitSlot.GLASSES
	var z := GLASS_Z
	match id:
		&"aviator_shades":
			_add(_head, _box_mesh(Vector3(0.3, 0.016, 0.016)), c, Vector3(0, 0.078, z), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _box_mesh(Vector3(0.11, 0.075, 0.018)), LENS_DARK, Vector3(s * 0.076, 0.035, z), Vector3(0, 0, -s * 0.12), g)
				_add(_head, _prism_mesh(Vector3(0.1, 0.045, 0.018)), LENS_DARK, Vector3(s * 0.082, -0.022, z), Vector3(0, 0, PI), g)
				_temple(s, c, g)
			_add(_head, _box_mesh(Vector3(0.05, 0.014, 0.014)), c, Vector3(0, 0.045, z - 0.006), Vector3.ZERO, g)
		&"heart_shades":
			_add(_head, _box_mesh(Vector3(0.05, 0.016, 0.016)), c, Vector3(0, 0.04, z - 0.004), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _box_mesh(Vector3(0.075, 0.075, 0.02)), c, Vector3(s * 0.078, 0.02, z), Vector3(0, 0, PI * 0.25), g)
				for k: float in [-1.0, 1.0]:
					_add(_head, _sphere_mesh(0.034, 6), c, Vector3(s * 0.078 + k * 0.026, 0.05, z), Vector3.ZERO, g, 0.0, Vector3(1.0, 1.0, 0.5))
				_temple(s, c, g)
		&"nerd_frames":
			_add(_head, _box_mesh(Vector3(0.05, 0.022, 0.022)), c, Vector3(0, 0.045, z), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _box_mesh(Vector3(0.12, 0.095, 0.022)), c, Vector3(s * 0.08, 0.035, z), Vector3.ZERO, g)
				_add(_head, _box_mesh(Vector3(0.088, 0.064, 0.012)), LENS_CLEAR, Vector3(s * 0.08, 0.035, z - 0.008), Vector3.ZERO, g)
				_temple(s, c, g)
		&"fancy_monocle":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.038
			ring.outer_radius = 0.052
			ring.rings = 12
			ring.ring_segments = 4
			_add(_head, ring, c, Vector3(0.075, 0.035, z), Vector3(PI * 0.5, 0, 0), g, 0.2)
			_add(_head, _cyl_mesh(0.04, 0.004, 10), LENS_CLEAR, Vector3(0.075, 0.035, z), Vector3(PI * 0.5, 0, 0), g)
			_add(_head, _box_mesh(Vector3(0.008, 0.24, 0.008)), c, Vector3(0.115, -0.1, z + 0.02), Vector3(0, 0, 0.3), g)
		&"ski_goggles":
			_add(_head, _cyl_mesh(0.204, 0.055, 12), c, Vector3(0, 0.035, 0), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.32, 0.12, 0.05)), c.darkened(0.2), Vector3(0, 0.035, -0.215), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.28, 0.085, 0.02)), Color("4c5bd4"), Vector3(0, 0.035, z), Vector3.ZERO, g, 0.35)
		&"star_glasses":
			_add(_head, _box_mesh(Vector3(0.05, 0.016, 0.016)), c, Vector3(0, 0.04, z - 0.004), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _prism_mesh(Vector3(0.12, 0.1, 0.02)), c, Vector3(s * 0.08, 0.045, z), Vector3.ZERO, g)
				_add(_head, _prism_mesh(Vector3(0.12, 0.1, 0.02)), c, Vector3(s * 0.08, 0.02, z - 0.003), Vector3(0, 0, PI), g)
				_temple(s, c, g)
		&"groucho_disguise":
			_add(_head, _sphere_mesh(0.06, 8), c, Vector3(0, -0.005, -0.232), Vector3.ZERO, g, 0.0, Vector3(0.9, 1.1, 1.1))
			var black := Color("121212")
			_add(_head, _box_mesh(Vector3(0.15, 0.04, 0.03)), black, Vector3(0, -0.062, -0.212), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _box_mesh(Vector3(0.085, 0.028, 0.02)), black, Vector3(s * 0.075, 0.105, -0.2), Vector3(0, 0, -s * 0.15), g)
				_add(_head, _box_mesh(Vector3(0.1, 0.085, 0.02)), black, Vector3(s * 0.08, 0.035, z), Vector3.ZERO, g)
				_add(_head, _box_mesh(Vector3(0.07, 0.055, 0.012)), LENS_CLEAR, Vector3(s * 0.08, 0.035, z - 0.008), Vector3.ZERO, g)
				_temple(s, black, g)
		&"u_black_shades":
			_add(_head, _box_mesh(Vector3(0.3, 0.02, 0.02)), c, Vector3(0, 0.07, z), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_head, _box_mesh(Vector3(0.12, 0.07, 0.02)), c, Vector3(s * 0.078, 0.035, z), Vector3(0, 0, s * 0.08), g, 0.05)
				_temple(s, c, g)
		_:
			if not OutfitCatalog.is_none(id):
				_add(_head, _box_mesh(Vector3(0.3, 0.06, 0.02)), c, Vector3(0, 0.035, z), Vector3.ZERO, g)


func _temple(s: float, c: Color, g: int) -> void:
	_add(_head, _box_mesh(Vector3(0.014, 0.014, 0.23)), c, Vector3(s * 0.198, 0.06, -0.125), Vector3.ZERO, g)


func _build_top(id: StringName, c: Color) -> void:
	var g := HR.OutfitSlot.TOP
	var long_sleeves := true
	var sleeve := c
	var emission := 0.0
	_torso.scale = Vector3.ONE
	match id:
		&"plain_tee":
			long_sleeves = false
			_add(_spine, _cyl_mesh(0.1, 0.02, 10), c.darkened(0.12), Vector3(0, 0.49, -0.005), Vector3.ZERO, g)
		&"hawaiian_shirt":
			long_sleeves = false
			_collar_tips(c.lightened(0.3), g)
			var petals := [Color("ffe066"), Color("2ec4b6"), Color("fff8e7")]
			var spots := [Vector3(-0.15, 0.36, -1), Vector3(0.13, 0.4, -1), Vector3(-0.04, 0.2, -1), Vector3(0.16, 0.12, -1),
				Vector3(-0.16, 0.06, -1), Vector3(0.05, 0.04, -1), Vector3(-0.1, 0.3, 1), Vector3(0.12, 0.15, 1), Vector3(-0.05, 0.06, 1)]
			for i in spots.size():
				var p: Vector3 = spots[i]
				_add(_spine, _sphere_mesh(0.042, 6), petals[i % 3] as Color, Vector3(p.x, p.y, p.z * 0.143), Vector3.ZERO, g, 0.0, Vector3(1.0, 1.0, 0.35))
		&"rented_tuxedo":
			_shirt_v(SHIRT_WHITE, g)
			_lapels(Color("0e0e12"), g)
			for y: float in [0.43, 0.36]:
				_add(_spine, _sphere_mesh(0.014, 6), Color("111111"), Vector3(0, y, -0.152), Vector3.ZERO, g)
			_add(_spine, _box_mesh(Vector3(0.07, 0.03, 0.02)), Color("0e0e12"), Vector3(0, 0.475, -0.155), Vector3.ZERO, g)
		&"velour_tracksuit":
			_add(_spine, _cyl_mesh(0.11, 0.07, 10), c, Vector3(0, 0.5, 0), Vector3.ZERO, g)
			_add(_spine, _box_mesh(Vector3(0.014, 0.48, 0.012)), SILVER, Vector3(0, 0.24, -0.146), Vector3.ZERO, g)
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				_add(_shoulders[i], _box_mesh(Vector3(0.012, 0.3, 0.035)), Color.WHITE, Vector3(s * 0.078, -0.12, 0), Vector3.ZERO, g)
				_add(_elbows[i], _box_mesh(Vector3(0.012, 0.26, 0.035)), Color.WHITE, Vector3(s * 0.068, -0.13, 0), Vector3.ZERO, g)
		&"biker_jacket":
			_torso.scale = Vector3(1.04, 1.0, 1.08)
			var trim := c.darkened(0.45)
			_add(_spine, _box_mesh(Vector3(0.014, 0.42, 0.012)), SILVER, Vector3(0.05, 0.25, -0.158), Vector3(0, 0, 0.25), g)
			for s: float in [-1.0, 1.0]:
				_add(_spine, _prism_mesh(Vector3(0.13, 0.12, 0.02)), trim, Vector3(s * 0.085, 0.43, -0.158), Vector3(0, 0, PI), g)
			_add(_spine, _box_mesh(Vector3(0.54, 0.05, 0.32)), trim, Vector3(0, 0.02, 0), Vector3.ZERO, g)
			_add(_spine, _box_mesh(Vector3(0.05, 0.035, 0.012)), SILVER, Vector3(0, 0.02, -0.165), Vector3.ZERO, g)
		&"sequin_blazer":
			emission = 0.35
			_shirt_v(Color("1a1a1f"), g)
			_lapels(c.darkened(0.25), g)
		&"lucky_sweater":
			var leaf := Color("b8f0a8")
			for p: Vector2 in [Vector2(-0.035, 0.31), Vector2(0.035, 0.31), Vector2(0.0, 0.365)]:
				_add(_spine, _sphere_mesh(0.042, 6), leaf, Vector3(p.x, p.y, -0.143), Vector3.ZERO, g, 0.0, Vector3(1.0, 1.0, 0.35))
			_add(_spine, _box_mesh(Vector3(0.014, 0.08, 0.012)), leaf, Vector3(0.012, 0.25, -0.146), Vector3(0, 0, 0.3), g)
			_add(_spine, _box_mesh(Vector3(0.52, 0.06, 0.3)), c.darkened(0.2), Vector3(0, 0.02, 0), Vector3.ZERO, g)
			_add(_spine, _cyl_mesh(0.1, 0.04, 10), c.darkened(0.2), Vector3(0, 0.49, 0), Vector3.ZERO, g)
			for i in 2:
				_add(_elbows[i], _box_mesh(Vector3(0.145, 0.05, 0.155)), c.darkened(0.2), Vector3(0, -FOREARM_LEN + 0.03, 0), Vector3.ZERO, g)
		&"bowling_shirt":
			long_sleeves = false
			var cream := Color("f4ecd6")
			for s: float in [-1.0, 1.0]:
				_add(_spine, _box_mesh(Vector3(0.08, 0.5, 0.012)), cream, Vector3(s * 0.14, 0.24, -0.146), Vector3.ZERO, g)
			_collar_tips(cream, g)
		&"staff_vest", &"u_dealer_vest":
			sleeve = SHIRT_WHITE
			_shirt_v(SHIRT_WHITE, g)
			var button := GOLD if id == &"staff_vest" else Color("3a3a40")
			for y: float in [0.24, 0.16, 0.08]:
				_add(_spine, _sphere_mesh(0.016, 6), button, Vector3(0, y, -0.148), Vector3.ZERO, g)
			for i in 2:
				_add(_elbows[i], _box_mesh(Vector3(0.145, 0.04, 0.155)), SHIRT_WHITE.darkened(0.06), Vector3(0, -FOREARM_LEN + 0.03, 0), Vector3.ZERO, g)
		&"u_suit":
			_shirt_v(SHIRT_WHITE, g)
			_lapels(c.darkened(0.3), g)
	_recolor(_torso, c, emission)
	_primary[g] = _torso
	_forearms_skin = not long_sleeves
	for i in 2:
		_recolor(_upper_arms[i], sleeve, emission)
		_recolor(_forearms[i], skin_color if _forearms_skin else sleeve, 0.0 if _forearms_skin else emission)


func _shirt_v(color: Color, g: int) -> void:
	_add(_spine, _prism_mesh(Vector3(0.18, 0.2, 0.02)), color, Vector3(0, 0.39, -0.146), Vector3(0, 0, PI), g)


func _lapels(color: Color, g: int) -> void:
	for s: float in [-1.0, 1.0]:
		_add(_spine, _box_mesh(Vector3(0.035, 0.23, 0.02)), color, Vector3(s * 0.05, 0.385, -0.152), Vector3(0, 0, -s * 0.42), g)


func _collar_tips(color: Color, g: int) -> void:
	for s: float in [-1.0, 1.0]:
		_add(_spine, _prism_mesh(Vector3(0.1, 0.09, 0.02)), color, Vector3(s * 0.065, 0.45, -0.15), Vector3(0, 0, PI - s * 0.25), g)


func _build_bottom(id: StringName, c: Color) -> void:
	var g := HR.OutfitSlot.BOTTOM
	var thigh := c
	var shin := c
	var emission := 0.0
	var leg_scale := Vector3.ONE
	match id:
		&"blue_jeans":
			_belt(Color("5a3a22"), g)
			for i in 2:
				_add(_knees[i], _box_mesh(Vector3(0.18, 0.05, 0.2)), c.lightened(0.15), Vector3(0, -SHIN_LEN + 0.03, 0), Vector3.ZERO, g)
		&"cargo_shorts":
			shin = skin_color
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				_add(_legs[i], _box_mesh(Vector3(0.03, 0.12, 0.11)), c.darkened(0.18), Vector3(s * 0.1, -0.24, 0), Vector3.ZERO, g)
		&"pressed_slacks", &"u_suit_pants":
			_belt(Color("141414"), g)
			for i in 2:
				_add(_legs[i], _box_mesh(Vector3(0.008, 0.4, 0.01)), c.lightened(0.18), Vector3(0, -0.2, -0.108), Vector3.ZERO, g)
				_add(_knees[i], _box_mesh(Vector3(0.008, 0.34, 0.01)), c.lightened(0.18), Vector3(0, -0.18, -0.098), Vector3.ZERO, g)
		&"track_pants":
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				_add(_legs[i], _box_mesh(Vector3(0.012, 0.44, 0.04)), Color.WHITE, Vector3(s * 0.1, -0.2, 0), Vector3.ZERO, g)
				_add(_knees[i], _box_mesh(Vector3(0.012, 0.36, 0.04)), Color.WHITE, Vector3(s * 0.09, -0.18, 0), Vector3.ZERO, g)
		&"golf_plaid_pants":
			var band := c.darkened(0.35)
			var line := Color("f6e2b8")
			for i in 2:
				for y: float in [-0.1, -0.3]:
					_add(_legs[i], _box_mesh(Vector3(0.2, 0.035, 0.22)), band, Vector3(0, y, 0), Vector3.ZERO, g)
				_add(_legs[i], _box_mesh(Vector3(0.198, 0.012, 0.218)), line, Vector3(0, -0.2, 0), Vector3.ZERO, g)
				for y: float in [-0.08, -0.26]:
					_add(_knees[i], _box_mesh(Vector3(0.18, 0.035, 0.2)), band, Vector3(0, y, 0), Vector3.ZERO, g)
				_add(_knees[i], _box_mesh(Vector3(0.178, 0.012, 0.198)), line, Vector3(0, -0.17, 0), Vector3.ZERO, g)
		&"leopard_leggings":
			leg_scale = Vector3(0.88, 1.0, 0.88)
			var spot := Color("4a2c12")
			for i in 2:
				for p: Vector2 in [Vector2(0.03, -0.08), Vector2(-0.04, -0.22), Vector2(0.02, -0.36)]:
					_add(_legs[i], _box_mesh(Vector3(0.045, 0.04, 0.012)), spot, Vector3(p.x, p.y, -0.094), Vector3(0, 0, 0.5), g)
				for p: Vector2 in [Vector2(-0.03, -0.07), Vector2(0.035, -0.2), Vector2(-0.02, -0.31)]:
					_add(_knees[i], _box_mesh(Vector3(0.04, 0.035, 0.012)), spot, Vector3(p.x, p.y, -0.085), Vector3(0, 0, -0.5), g)
		&"pleated_skirt":
			thigh = skin_color
			shin = skin_color
			_add(_hips, _cyl_mesh(0.31, 0.32, 10, 0.23), c, Vector3(0, -0.09, 0), Vector3.ZERO, g)
			_add(_hips, _cyl_mesh(0.235, 0.04, 10), c.darkened(0.3), Vector3(0, 0.08, 0), Vector3.ZERO, g)
		&"gold_lame_pants":
			emission = 0.4
			for i in 2:
				_add(_knees[i], _cyl_mesh(0.14, 0.15, 8, 0.09), c, Vector3(0, -SHIN_LEN + 0.07, 0), Vector3.ZERO, g, emission)
		&"staff_slacks":
			for i in 2:
				var s := -1.0 if i == 0 else 1.0
				_add(_legs[i], _box_mesh(Vector3(0.012, 0.44, 0.03)), Color("7b1e3a"), Vector3(s * 0.1, -0.2, 0), Vector3.ZERO, g)
				_add(_knees[i], _box_mesh(Vector3(0.012, 0.36, 0.03)), Color("7b1e3a"), Vector3(s * 0.09, -0.18, 0), Vector3.ZERO, g)
	_recolor(_pelvis, c, emission)
	_primary[g] = _pelvis
	_thighs_skin = thigh == skin_color and thigh != c
	_shins_skin = shin == skin_color and shin != c
	for i in 2:
		_recolor(_thighs[i], thigh, 0.0 if _thighs_skin else emission)
		_recolor(_shins[i], shin, 0.0 if _shins_skin else emission)
		_thighs[i].scale = leg_scale
		_shins[i].scale = leg_scale


func _belt(color: Color, g: int) -> void:
	_add(_hips, _box_mesh(Vector3(0.45, 0.045, 0.27)), color, Vector3(0, 0.03, 0), Vector3.ZERO, g)
	_add(_hips, _box_mesh(Vector3(0.05, 0.035, 0.012)), GOLD, Vector3(0, 0.03, -0.138), Vector3.ZERO, g, 0.2)


func _build_accessory(id: StringName, c: Color, g: int) -> void:
	match id:
		&"gold_chain":
			for s: float in [-1.0, 1.0]:
				_add(_spine, _box_mesh(Vector3(0.035, 0.22, 0.03)), c, Vector3(s * 0.06, 0.39, -0.152), Vector3(0, 0, -s * 0.59), g, 0.25)
			_add(_spine, _cyl_mesh(0.055, 0.02, 10), c, Vector3(0, 0.27, -0.158), Vector3(PI * 0.5, 0, 0), g, 0.35)
		&"feather_boa":
			_add(_spine, _sphere_mesh(0.065, 6), c, Vector3(0, 0.5, 0.08), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				for p: Vector3 in [Vector3(0.13, 0.5, 0.02), Vector3(0.16, 0.45, -0.09), Vector3(0.15, 0.36, -0.16), Vector3(0.14, 0.26, -0.17), Vector3(0.16, 0.16, -0.165)]:
					_add(_spine, _sphere_mesh(0.065, 6), c, Vector3(s * p.x, p.y, p.z), Vector3(0.3, s * 0.5, 0), g)
		&"lucky_scarf":
			_add(_spine, _cyl_mesh(0.115, 0.1, 10), c, Vector3(0, 0.53, 0), Vector3.ZERO, g)
			_add(_spine, _sphere_mesh(0.05, 6), c.darkened(0.15), Vector3(0.06, 0.48, -0.12), Vector3.ZERO, g)
			_add(_spine, _box_mesh(Vector3(0.09, 0.28, 0.035)), c, Vector3(0.09, 0.33, -0.162), Vector3(0, 0, 0.12), g)
			_add(_spine, _box_mesh(Vector3(0.08, 0.2, 0.035)), c.darkened(0.1), Vector3(0.02, 0.37, -0.17), Vector3(0, 0, -0.1), g)
			_add(_spine, _box_mesh(Vector3(0.092, 0.025, 0.037)), Color("f5f5f5"), Vector3(0.105, 0.22, -0.162), Vector3(0, 0, 0.12), g)
		&"bow_tie":
			_add(_spine, _prism_mesh(Vector3(0.08, 0.07, 0.03)), c, Vector3(-0.045, 0.44, -0.158), Vector3(0, 0, -PI * 0.5), g)
			_add(_spine, _prism_mesh(Vector3(0.08, 0.07, 0.03)), c, Vector3(0.045, 0.44, -0.158), Vector3(0, 0, PI * 0.5), g)
			_add(_spine, _box_mesh(Vector3(0.035, 0.035, 0.04)), c.darkened(0.2), Vector3(0, 0.44, -0.16), Vector3.ZERO, g)
		&"fanny_pack":
			_add(_spine, _box_mesh(Vector3(0.24, 0.13, 0.09)), c, Vector3(0, 0.03, -0.17), Vector3.ZERO, g, 0.15)
			_add(_spine, _box_mesh(Vector3(0.2, 0.012, 0.01)), Color("222222"), Vector3(0, 0.07, -0.217), Vector3.ZERO, g)
			_add(_spine, _box_mesh(Vector3(0.53, 0.045, 0.31)), Color("222222"), Vector3(0, 0.03, 0), Vector3.ZERO, g)
		&"tourist_camera":
			_add(_spine, _box_mesh(Vector3(0.16, 0.1, 0.07)), c, Vector3(0, 0.24, -0.18), Vector3.ZERO, g)
			_add(_spine, _cyl_mesh(0.04, 0.06, 10), Color("1a1a1a"), Vector3(0, 0.23, -0.235), Vector3(PI * 0.5, 0, 0), g)
			_add(_spine, _box_mesh(Vector3(0.04, 0.025, 0.03)), Color("f2f2f2"), Vector3(-0.05, 0.3, -0.18), Vector3.ZERO, g)
			for s: float in [-1.0, 1.0]:
				_add(_spine, _box_mesh(Vector3(0.025, 0.3, 0.015)), Color("2a2a2a"), Vector3(s * 0.1, 0.38, -0.15), Vector3(0, 0, -s * 0.35), g)
		&"foam_finger":
			var hand := _elbows[1]
			_add(hand, _box_mesh(Vector3(0.17, 0.17, 0.11)), c, Vector3(0, -FOREARM_LEN - 0.08, 0), Vector3.ZERO, g)
			_add(hand, _box_mesh(Vector3(0.06, 0.22, 0.06)), c, Vector3(0, -FOREARM_LEN - 0.27, 0), Vector3.ZERO, g)
			_add(hand, _box_mesh(Vector3(0.05, 0.06, 0.06)), c, Vector3(0, -FOREARM_LEN - 0.06, -0.08), Vector3.ZERO, g)
			_add(hand, _box_mesh(Vector3(0.12, 0.04, 0.115)), Color("f5f5f5"), Vector3(0, -FOREARM_LEN - 0.12, 0), Vector3.ZERO, g)
		&"staff_name_tag":
			_add(_spine, _box_mesh(Vector3(0.11, 0.045, 0.015)), c, Vector3(-0.13, 0.36, -0.148), Vector3.ZERO, g, 0.2)
			_add(_spine, _box_mesh(Vector3(0.08, 0.012, 0.01)), Color("f5f5f5"), Vector3(-0.13, 0.36, -0.157), Vector3.ZERO, g)
		&"u_earpiece":
			_add(_head, _sphere_mesh(0.03, 6), c, Vector3(0.205, 0.0, -0.02), Vector3.ZERO, g)
			_add(_head, _box_mesh(Vector3(0.012, 0.24, 0.012)), Color("cfcfcf"), Vector3(0.18, -0.15, 0.03), Vector3(0.15, 0, 0.1), g)
		&"u_tie":
			_add(_spine, _box_mesh(Vector3(0.06, 0.05, 0.03)), c, Vector3(0, 0.45, -0.16), Vector3.ZERO, g)
			_add(_spine, _box_mesh(Vector3(0.075, 0.28, 0.02)), c, Vector3(0, 0.29, -0.158), Vector3.ZERO, g)
			_add(_spine, _prism_mesh(Vector3(0.075, 0.05, 0.02)), c, Vector3(0, 0.125, -0.158), Vector3(0, 0, PI), g)
		&"u_badge":
			_add(_spine, _box_mesh(Vector3(0.08, 0.08, 0.02)), c, Vector3(-0.14, 0.33, -0.15), Vector3.ZERO, g, 0.3)
			_add(_spine, _prism_mesh(Vector3(0.08, 0.045, 0.02)), c, Vector3(-0.14, 0.268, -0.15), Vector3(0, 0, PI), g, 0.3)
			_add(_spine, _sphere_mesh(0.018, 6), Color("f8f1d0"), Vector3(-0.14, 0.33, -0.162), Vector3.ZERO, g)
		&"u_pocket_square":
			_add(_spine, _prism_mesh(Vector3(0.07, 0.05, 0.015)), c, Vector3(-0.14, 0.37, -0.15), Vector3.ZERO, g)
		_:
			if not OutfitCatalog.is_none(id):
				_add(_spine, _box_mesh(Vector3(0.12, 0.12, 0.05)), c, Vector3(0, 0.25, -0.16), Vector3.ZERO, g)


# --- Animation ----------------------------------------------------------------

func _effective_speed() -> float:
	if _move_speed >= 0.0:
		return _move_speed
	match pose:
		&"walk":
			return Tuning.PLAYER_WALK_SPEED
		&"run":
			return Tuning.PLAYER_RUN_SPEED
		&"carry":
			return Tuning.GUARD_CARRY_SPEED
	return 0.0


func _pose_targets() -> void:
	_target.fill(Vector3.ZERO)
	_target_offset = Vector3.ZERO
	var breath := sin(_time * 2.2)
	match pose:
		&"idle":
			_t(J_SPINE, Vector3(0.02 * breath, 0, 0))
			_t(J_NECK, Vector3(-0.02 * breath, 0, 0))
			_arms(Vector3(0.05, 0, -0.08 - 0.015 * breath), Vector3(0.05, 0, 0.08 + 0.015 * breath), 0.15, 0.15)
			_target_offset.y = 0.004 * breath
		&"walk", &"run":
			_locomotion(breath)
		&"sit":
			_sit_legs()
			_t(J_SPINE, Vector3(-0.04 + 0.02 * breath, 0, 0))
			_arms(Vector3(0.45, 0, -0.12), Vector3(0.45, 0, 0.12), 0.75, 0.75)
		&"play":
			_sit_legs()
			var w := sin(_time * 7.0)
			_t(J_SPINE, Vector3(-0.14, 0, 0))
			_t(J_NECK, Vector3(-0.12 + 0.04 * sin(_time * 3.0), 0, 0))
			_arms(Vector3(1.05 + 0.2 * w, 0, -0.15), Vector3(1.05 - 0.2 * w, 0, 0.15), 0.75 - 0.25 * w, 0.75 + 0.25 * w)
		&"celebrate":
			var k := absf(sin(_time * 6.0))
			_target_offset.y = 0.14 * k - 0.06 * (1.0 - k)
			_legs_to(Vector3(0.35 * (1.0 - k), 0, -0.05), Vector3(0.35 * (1.0 - k), 0, 0.05), -0.7 * (1.0 - k), -0.7 * (1.0 - k))
			var wave := sin(_time * 11.0)
			_arms(Vector3(0.25, 0, -2.55 - 0.2 * wave), Vector3(0.25, 0, 2.55 + 0.2 * wave), 0.25, 0.25)
			_t(J_NECK, Vector3(0.22, 0, 0))
			_t(J_SPINE, Vector3(0.08, 0, 0))
		&"carried":
			var f := sin(_time * 8.0)
			_t(J_HIPS, Vector3(-PI * 0.5, PI, 0))
			_target_offset.y = -HIP_Y + 0.13
			_t(J_SPINE, Vector3(-0.45, 0, 0))
			_t(J_NECK, Vector3(-0.25, 0, 0))
			_arms(Vector3(1.35 + 0.3 * f, 0, -0.2), Vector3(1.35 - 0.3 * f, 0, 0.2), 0.3, 0.3)
			_legs_to(Vector3(0.55 + 0.25 * f, 0, -0.08), Vector3(0.55 - 0.25 * f, 0, 0.08), -0.4 - 0.3 * maxf(0.0, f), -0.4 - 0.3 * maxf(0.0, -f))
		&"carry":
			_locomotion(breath)
			_arms(Vector3(1.1, 0, 0.55), Vector3(1.2, 0, -0.05), 0.9, 1.1)
		&"tackle":
			_t(J_HIPS, Vector3(-1.38, 0, 0))
			_target_offset.y = 0.5 - HIP_Y
			_t(J_SPINE, Vector3(0.05, 0, 0))
			_t(J_NECK, Vector3(0.9, 0, 0))
			_arms(Vector3(2.7, 0, -0.55), Vector3(2.7, 0, 0.55), 0.45, 0.45)
			_legs_to(Vector3(-0.15, 0, -0.1), Vector3(-0.35, 0, 0.1), -0.6, -0.3)
		&"dive":
			var flutter := sin(_time * 14.0) * 0.12
			_t(J_HIPS, Vector3(-1.45, 0, 0))
			_target_offset.y = 0.42 - HIP_Y
			_t(J_NECK, Vector3(1.0, 0, 0))
			_arms(Vector3(3.0, 0, -0.12), Vector3(3.0, 0, 0.12), 0.0, 0.0)
			_legs_to(Vector3(-0.08 + flutter, 0, -0.06), Vector3(-0.08 - flutter, 0, 0.06), -0.15, -0.15)
		&"tumble":
			_tumble()
		&"jump":
			_target_offset.y = 0.1
			_t(J_SPINE, Vector3(-0.1, 0, 0))
			_arms(Vector3(0.5, 0, -1.25), Vector3(0.5, 0, 1.25), 0.5, 0.5)
			_legs_to(Vector3(1.05, 0, -0.1), Vector3(1.05, 0, 0.1), -1.75, -1.75)


func _locomotion(breath: float) -> void:
	var speed := _effective_speed()
	var walk := Tuning.PLAYER_WALK_SPEED
	var amt := clampf(speed / walk, 0.0, 1.0)
	var runness := clampf((speed - walk) / maxf(Tuning.PLAYER_RUN_SPEED - walk, 0.01), 0.0, 1.0)
	var s := sin(_phase)
	var c := cos(_phase)
	var leg_amp := lerpf(0.5, 0.8, runness) * amt
	var knee_amp := lerpf(0.45, 1.3, runness) * amt
	var arm_amp := lerpf(0.4, 0.95, runness) * amt
	var elbow := lerpf(0.2, 1.3, runness)
	_legs_to(Vector3(s * leg_amp, 0, -0.02), Vector3(-s * leg_amp, 0, 0.02), -maxf(0.0, c) * knee_amp, -maxf(0.0, -c) * knee_amp)
	_arms(Vector3(-s * arm_amp, 0, -0.1), Vector3(s * arm_amp, 0, 0.1), elbow, elbow)
	_t(J_SPINE, Vector3(-lerpf(0.04, 0.3, runness) * amt + 0.01 * breath, s * 0.1 * amt, 0))
	_t(J_NECK, Vector3(lerpf(0.0, 0.18, runness) * amt, -s * 0.05 * amt, 0))
	_target_offset.y = -LEG_LEN * (1.0 - cos(leg_amp * s)) + runness * 0.06 * absf(c)


func _sit_legs() -> void:
	_target_offset.y = SIT_HIP_Y - HIP_Y
	_legs_to(Vector3(PI * 0.5, 0, -0.06), Vector3(PI * 0.5, 0, 0.06), -PI * 0.5, -PI * 0.5)


func _tumble() -> void:
	var u := _pose_time / maxf(Tuning.CHARACTER_TUMBLE_SECONDS, 0.01)
	var down := smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.62, 0.95, u))
	var wob := sin(_time * 9.0) * down
	_t(J_HIPS, Vector3(1.45 * down, 0, 0))
	_target_offset.y = (0.17 - HIP_Y) * down
	_t(J_NECK, Vector3(-0.3 * down, 0, 0.25 * wob))
	_arms(Vector3(0.4 * down, 0, -0.1 - 1.2 * down - 0.2 * wob), Vector3(0.4 * down, 0, 0.1 + 1.2 * down + 0.2 * wob), 0.3, 0.3)
	_legs_to(Vector3(0.5 * down + 0.2 * wob, 0, -0.15 * down), Vector3(0.3 * down - 0.2 * wob, 0, 0.15 * down), -0.5 * down, -0.5 * down)


func _t(joint: int, rot: Vector3) -> void:
	_target[joint] = rot


func _arms(left: Vector3, right: Vector3, elbow_l: float, elbow_r: float) -> void:
	_target[J_SH_L] = left
	_target[J_SH_R] = right
	_target[J_EL_L] = Vector3(elbow_l, 0, 0)
	_target[J_EL_R] = Vector3(elbow_r, 0, 0)


func _legs_to(left: Vector3, right: Vector3, knee_l: float, knee_r: float) -> void:
	_target[J_LEG_L] = left
	_target[J_LEG_R] = right
	_target[J_KNEE_L] = Vector3(knee_l, 0, 0)
	_target[J_KNEE_R] = Vector3(knee_r, 0, 0)


# --- Mesh helpers -------------------------------------------------------------

func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


## Adds a mesh part. group >= 0 registers it with that dressing group (the
## first one becomes the group's main mesh for get_slot_color).
func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot: Vector3 = Vector3.ZERO, group: int = -1, emission: float = 0.0, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Primitives.material(color, emission)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	if mesh.get_aabb().get_longest_axis_size() < 0.09:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if group >= 0:
		if not _groups.has(group):
			_groups[group] = []
		(_groups[group] as Array).append(mi)
		if not _primary.has(group):
			_primary[group] = mi
	return mi


func _recolor(mi: MeshInstance3D, color: Color, emission: float = 0.0) -> void:
	mi.material_override = Primitives.material(color, emission)


func _all_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child: Node in root.get_children():
		var mi := child as MeshInstance3D
		if mi != null:
			if mi.visible:
				out.append(mi)
		elif child is Node3D and (child as Node3D).visible:
			out.append_array(_all_meshes(child))
	return out


# Geometry is shared between every model; only the material differs per part.

static func _box_mesh(size: Vector3) -> Mesh:
	var key := "box%s" % size
	if not _mesh_cache.has(key):
		_cache(key, Primitives.box(size, Color.WHITE))
	return _mesh_cache[key]


static func _cyl_mesh(radius: float, height: float, sides: int = 10, top_radius: float = -1.0) -> Mesh:
	var key := "cyl%.3f|%.3f|%d|%.3f" % [radius, height, sides, top_radius]
	if not _mesh_cache.has(key):
		_cache(key, Primitives.cylinder(radius, height, Color.WHITE, sides, top_radius))
	return _mesh_cache[key]


static func _sphere_mesh(radius: float, segments: int = 8) -> Mesh:
	var key := "sph%.3f|%d" % [radius, segments]
	if not _mesh_cache.has(key):
		_cache(key, Primitives.sphere(radius, Color.WHITE, segments))
	return _mesh_cache[key]


static func _hemi_mesh(radius: float) -> Mesh:
	var key := "hemi%.3f" % radius
	if not _mesh_cache.has(key):
		var mi := Primitives.sphere(radius, Color.WHITE, 12)
		(mi.mesh as SphereMesh).is_hemisphere = true
		(mi.mesh as SphereMesh).height = radius
		_cache(key, mi)
	return _mesh_cache[key]


static func _prism_mesh(size: Vector3) -> Mesh:
	var key := "prism%s" % size
	if not _mesh_cache.has(key):
		_cache(key, Primitives.prism(size, Color.WHITE))
	return _mesh_cache[key]


static func _cache(key: String, mi: MeshInstance3D) -> void:
	_mesh_cache[key] = mi.mesh
	mi.free()
