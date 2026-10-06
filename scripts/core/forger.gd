class_name Forger
extends RefCounted
## The ID forger. Never stays put: every Tuning.FORGER_MOVE_SECONDS he moves to
## the next spot in LOCATIONS (parking garage -> restroom -> loading dock -> back
## to the garage) and emits `moved`. Prices and the cards he prints come from
## IdGenerator. Host-owned; one per casino visit.

signal moved(location: StringName)

const PARKING_GARAGE := &"parking_garage"
const RESTROOM := &"restroom"
const LOADING_DOCK := &"loading_dock"
## Visiting order.
const LOCATIONS: Array[StringName] = [PARKING_GARAGE, RESTROOM, LOADING_DOCK]

## Float slack so frame-sized ticks that add up to a full stay still move him.
const _EPS := 0.000001

var _index: int = 0
## Seconds spent at the current location.
var _elapsed: float = 0.0


## Starts at `start` (one of LOCATIONS; anything else means the parking garage).
func _init(start: StringName = PARKING_GARAGE) -> void:
	_index = maxi(0, LOCATIONS.find(start))


func location() -> StringName:
	return LOCATIONS[_index]


## Where he goes next.
func next_location() -> StringName:
	return LOCATIONS[(_index + 1) % LOCATIONS.size()]


func seconds_until_move() -> float:
	return maxf(0.0, Tuning.FORGER_MOVE_SECONDS - _elapsed)


## Advances the clock. A long delta can move him more than once; `moved` fires
## for every stop. Non-positive deltas do nothing.
func tick(delta: float) -> void:
	if delta <= 0.0 or Tuning.FORGER_MOVE_SECONDS <= 0.0:
		return
	_elapsed += delta
	while _elapsed >= Tuning.FORGER_MOVE_SECONDS - _EPS:
		_elapsed = maxf(0.0, _elapsed - Tuning.FORGER_MOVE_SECONDS)
		_index = (_index + 1) % LOCATIONS.size()
		moved.emit(location())


## True if the forger is at this location right now.
func is_at(where: StringName) -> bool:
	return location() == where


## Forger's price for a grade (see IdGenerator.price).
func price(grade: int) -> int:
	return IdGenerator.price(grade)


## Prints a fresh ID of the grade with the given rng (see IdGenerator.generate).
func make_id(grade: int, rng: RandomNumberGenerator, avoid_names: Array = []) -> FakeId:
	return IdGenerator.generate(grade, rng, avoid_names)


## {location: String, seconds_until_move: float} for snapshots and late joiners.
func to_dict() -> Dictionary:
	return {"location": String(location()), "seconds_until_move": seconds_until_move()}
