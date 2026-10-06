class_name PatronCrowd
extends Node3D
## The casino's patrons: spawns Patron bodies in seeded random outfits, some
## seated at slot machines and the rest wandering between patron points.
## rush_to() pulls nearby patrons into a blob around thrown chips. Positions
## are world positions (keep this node at the origin).
##
## Co-op: patrons walk only on the host. enable_net_sync() sends every
## patron's position, facing and pose as one packed array (net_state); a
## client's crowd is a `puppet` and places its (identically seeded) patrons
## from it.

## Floats per patron in net_state: x, y, z, facing, pose index (CharacterModel.POSES).
const NET_FIELDS := 5
const NET_SYNC_INTERVAL := 0.1
const PUPPET_SNAP_DISTANCE := 4.0
const PUPPET_SHARPNESS := 8.0

var patrons: Array[Patron] = []
## Co-op client copy (set before setup()).
var puppet: bool = false
## Synced from the host: NET_FIELDS floats per patron.
var net_state: PackedFloat32Array = PackedFloat32Array()
var _net_sync: bool = false

var _points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


## Spawns `count` patrons (replacing any from an earlier setup).
func setup(points: Array[Vector3], slot_seats: Array[Transform3D], count: int, rng_seed: int) -> void:
	clear()
	_points.assign(points)
	_rng.seed = rng_seed
	var seats: Array[Transform3D] = []
	seats.assign(slot_seats)
	_shuffle(seats)
	var seated := mini(roundi(count * Tuning.PATRON_SEATED_SHARE), seats.size())
	if _points.is_empty():
		seated = mini(count, seats.size())
	var starts: Array[Vector3] = []
	starts.assign(_points)
	_shuffle(starts)
	for i in maxi(count, 0):
		var patron := Patron.new()
		patron.name = "Patron%d" % i
		patron.puppet = puppet
		patron.setup(_points, _rng.randi())
		if i < seated:
			patron.sit_at(seats[i])
		elif not starts.is_empty():
			var start := starts[(i - seated) % starts.size()]
			var jitter := Vector3(_rng.randf_range(-0.6, 0.6), 0.0, _rng.randf_range(-0.6, 0.6))
			patron.position = start + jitter + Vector3(0, 0.05, 0)
		elif seats.is_empty():
			break
		else:
			patron.sit_at(seats[i % seats.size()])
		add_child(patron)
		patrons.append(patron)


## Sends every patron within PATRON_RUSH_RANGE of `position` to crowd inside
## `radius` of it, scramble for `seconds`, then disperse. Returns how many went.
func rush_to(position: Vector3, radius: float, seconds: float) -> int:
	var sent := 0
	var spread := maxf(radius * Tuning.PATRON_RUSH_SPREAD, 0.5)
	for patron: Patron in patrons:
		if not is_instance_valid(patron):
			continue
		var at := patron.global_position if patron.is_inside_tree() else patron.position
		if Perception.flat_distance(at, position) > Tuning.PATRON_RUSH_RANGE:
			continue
		var angle := _rng.randf() * TAU
		var dist := sqrt(_rng.randf()) * spread
		var target := position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		patron.rush(target, position, spread, seconds)
		sent += 1
	return sent


func patron_count() -> int:
	return patrons.size()


## Adds the MultiplayerSynchronizer for net_state (the host sends it, a
## client's puppet crowd applies it; both sides need it).
func enable_net_sync() -> void:
	_net_sync = true
	_publish()
	NetSync.attach(self, [&"net_state"], [], NET_SYNC_INTERVAL)


func _physics_process(delta: float) -> void:
	if puppet:
		_follow(delta)
	elif _net_sync:
		_publish()


func _publish() -> void:
	net_state.resize(patrons.size() * NET_FIELDS)
	for i in patrons.size():
		var p: Patron = patrons[i]
		if not is_instance_valid(p):
			continue
		var at := p.global_position if p.is_inside_tree() else p.position
		var o := i * NET_FIELDS
		net_state[o] = at.x
		net_state[o + 1] = at.y
		net_state[o + 2] = at.z
		net_state[o + 3] = p.facing
		net_state[o + 4] = float(maxi(0, CharacterModel.POSES.find(p.model.pose)))


func _follow(delta: float) -> void:
	var k: float = 1.0 - exp(-PUPPET_SHARPNESS * delta)
	for i in mini(patrons.size(), net_state.size() / NET_FIELDS):
		var p: Patron = patrons[i]
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		var o := i * NET_FIELDS
		var target := Vector3(net_state[o], net_state[o + 1], net_state[o + 2])
		var before := p.global_position
		p.global_position = target if before.distance_to(target) > PUPPET_SNAP_DISTANCE else before.lerp(target, k)
		p.facing = lerp_angle(p.facing, net_state[o + 3], k)
		p.model.rotation = Vector3(0, p.facing, 0)
		var pose_index: int = clampi(int(net_state[o + 4]), 0, CharacterModel.POSES.size() - 1)
		p.model.set_pose(CharacterModel.POSES[pose_index])
		p.model.set_move_speed(Vector2(p.global_position.x - before.x, p.global_position.z - before.z).length() / maxf(delta, 0.0001))


## Patrons sitting at slot machines right now.
func seated_count() -> int:
	var n := 0
	for patron: Patron in patrons:
		if is_instance_valid(patron) and patron.is_seated():
			n += 1
	return n


## Frees every patron.
func clear() -> void:
	for patron: Patron in patrons:
		if is_instance_valid(patron):
			patron.queue_free()
	patrons.clear()


func _shuffle(items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
