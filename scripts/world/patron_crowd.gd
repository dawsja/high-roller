class_name PatronCrowd
extends Node3D
## The casino's patrons: spawns Patron bodies in seeded random outfits, some
## seated at slot machines and the rest wandering between patron points.
## rush_to() pulls nearby patrons into a blob around thrown chips. Positions
## are world positions (keep this node at the origin).

var patrons: Array[Patron] = []

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
