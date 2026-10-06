class_name GuardBrain
extends RefCounted
## One guard's decision making: a pure state machine with no physics or
## navigation. Each frame the guard node calls update() with what it perceives
## (ctx keys in docs/ARCHITECTURE.md, "Guards") and carries out the returned
## intent: go to `move_to` (null = stand) at `speed`, turn toward the point
## `face` (null = face the way it walks), and perform `action` once.
##
## Priorities, highest first:
## 1. Stunned (ctx.stunned, or ctx.freed while carrying): stand still for
##    STUN_SECONDS (a new stun restarts it), then SEARCH where it stands.
## 2. Fire alarm: patrol paused, walk to patrol_points[0], ignore players and
##    noises until the alarm ends. `state` stays PATROL; state_name() says
##    "EVACUATE".
## 3. CARRY: walk the grabbed player to `back_room`; nothing else matters.
## 4. CHASE / CHECK_ID the target. Retargets when another visible candidate
##    has strictly more Heat (Perception.pick_target). Once the ID quiz has
##    started it only yields to someone it would chase.
## 5. INVESTIGATE the loudest heard noise (latest wins ties and later frames).
##    Only players it would chase interrupt it.
## 6. SEARCH / PATROL: any approachable player in view interrupts them.
## Noises also pull a guard off a CHECK_ID it hasn't asked yet, so a teammate
## can distract it; they never interrupt CHASE.
##
## Who is approached: Wanted → chase. Suspected or matching a poster → walk
## over and ask for ID (UNDERCOVER chases and grabs instead). Someone who
## failed or walked away from a check, or was being chased or carried, stays
## chase-worthy while remembered. Staff uniforms are ignored below Wanted.
## Unavailable players (carried, detained, on the curb) are never targets.
## Unnoticed and Watched players are never approached. A player who passed a
## check is left alone until their Heat level rises above the lowest level
## seen since, or they newly match a poster.
##
## Starting on, or switching to, a target needs it in view this frame. The
## current target is followed from memory to its last seen position and given
## up for SEARCH after LOSE_SIGHT_TO_SEARCH_SECONDS out of view. Players are
## remembered for GUARD_MEMORY_SECONDS after last being seen.
##
## Actions: `ask_id` once per check (needs the target in view within
## TALK_RANGE), `grab` (target in view within GRAB_RANGE), `drop_at_back_room`
## on ctx.at_back_room, and `release` when the guard lets go of a carried
## player itself (stunned without ctx.freed, or the fire alarm). At most one
## action per frame; a second one waits for the next frame.

signal state_changed(old_state: int, new_state: int)

const ACT_NONE := &""
const ACT_ASK_ID := &"ask_id"
const ACT_GRAB := &"grab"
const ACT_DROP := &"drop_at_back_room"
const ACT_RELEASE := &"release"

## ctx.id_check values.
const ID_PENDING := 0
const ID_PASSED := 1
const ID_FAILED := 2

const PATROL := HR.GuardState.PATROL
const INVESTIGATE := HR.GuardState.INVESTIGATE
const CHECK_ID := HR.GuardState.CHECK_ID
const CHASE := HR.GuardState.CHASE
const SEARCH := HR.GuardState.SEARCH
const CARRY := HR.GuardState.CARRY
const STUNNED := HR.GuardState.STUNNED

## How a guard would approach a remembered player.
enum Approach { NONE, CHECK, CHASE }

## What the guard remembers about one player.
class Known:
	var pid: int = -1
	var heat: float = 0.0
	var position: Vector3 = Vector3.ZERO
	var last_seen: float = 0.0
	var seen_tick: int = -1
	var matches_poster: bool = false
	var staff_uniform: bool = false
	var running: bool = false
	var available: bool = true
	## Failed or fled an ID check, or was chased or carried: chase on sight.
	var must_chase: bool = false

## HR.GuardState.
var state: int = PATROL
## Player being checked, chased, carried or searched for; −1 for none.
var target_pid: int = -1
## HR.SecurityType.
var security_type: int = HR.SecurityType.FLOOR_GUARD
## Where a grabbed player is carried.
var back_room: Vector3 = Vector3.ZERO
var patrol_points: Array[Vector3] = []
## State and target for the debug HUD, refreshed every update.
var debug_label: String = "PATROL"

## pid -> Known.
var _memory: Dictionary = {}
## pid -> {"level": int, "poster": bool} for players who passed an ID check.
var _cleared: Dictionary = {}
var _time: float = 0.0
var _tick: int = 0
var _patrol_index: int = 0
var _evacuating: bool = false
var _asked: bool = false
## INVESTIGATE / SEARCH spot and the wait there.
var _dest: Vector3 = Vector3.ZERO
var _arrived: bool = false
var _arrived_tick: int = -1
var _wait_left: float = 0.0
var _look_angle: float = 0.0
var _stun_left: float = 0.0
## move_to of the last intent, so a reached_destination meant for an old
## destination doesn't count for a new one.
var _last_move_to: Variant = null
var _prev_position: Vector3 = Vector3.ZERO
## Action chosen this frame.
var _action: StringName = ACT_NONE
## Position of the noise to investigate this frame, or null.
var _noise: Variant = null


func _init(points: Array[Vector3], guard_type: int = HR.SecurityType.FLOOR_GUARD, back_room_position: Vector3 = Vector3.ZERO) -> void:
	patrol_points.assign(points)
	security_type = guard_type
	back_room = back_room_position


## Advances the brain by `delta` seconds with this frame's perception and
## returns the intent {move_to, speed, face, action}.
func update(delta: float, ctx: Dictionary) -> Dictionary:
	_tick += 1
	_time += maxf(delta, 0.0)
	_action = ACT_NONE
	var pos := _vec(ctx.get("position"), _prev_position)
	var fire_alarm := bool(ctx.get("fire_alarm", false))
	if not fire_alarm:
		_ingest(ctx.get("seen", []))
	_expire_memory()
	_noise = null if fire_alarm else _loudest_noise(pos, ctx.get("noises", []))
	var intent := _decide(maxf(delta, 0.0), ctx, pos, fire_alarm)
	intent["action"] = _action
	_last_move_to = intent["move_to"]
	_prev_position = pos
	debug_label = state_name() if target_pid == -1 else "%s #%d" % [state_name(), target_pid]
	return intent


## Current state for display; "EVACUATE" while the fire alarm clears the floor.
func state_name() -> String:
	if _evacuating and state == PATROL:
		return "EVACUATE"
	return name_of(state)


## Name of an HR.GuardState value.
static func name_of(guard_state: int) -> String:
	var key: Variant = HR.GuardState.find_key(guard_state)
	return "UNKNOWN" if key == null else str(key)


## True while the fire alarm keeps this guard off the floor.
func is_evacuating() -> bool:
	return _evacuating


## Remembered players and their last seen Heat (pid -> float).
func known_heat() -> Dictionary:
	var out := {}
	for pid: int in _memory:
		var k: Known = _memory[pid]
		out[pid] = k.heat
	return out


## Drops everything remembered about a player (memory and passed checks).
func forget(pid: int) -> void:
	_memory.erase(pid)
	_cleared.erase(pid)


# --- Frame flow ---------------------------------------------------------------

func _decide(delta: float, ctx: Dictionary, pos: Vector3, fire_alarm: bool) -> Dictionary:
	var freed := bool(ctx.get("freed", false))
	if bool(ctx.get("stunned", false)) or (freed and state == CARRY):
		if state == CARRY:
			var carried: Known = _memory.get(target_pid)
			if carried != null:
				carried.must_chase = true
			if not freed:
				_action = ACT_RELEASE
		_stun_left = Tuning.STUN_SECONDS
		_asked = false
		_set_state(STUNNED)
		return _stand()
	if state == STUNNED:
		_stun_left -= delta
		if _stun_left > 0.0:
			return _stand()
		if not fire_alarm:
			_start_search(pos, true, pos)
	if fire_alarm:
		if state == CARRY:
			_action = ACT_RELEASE
		_evacuating = true
		_to_patrol()
		if patrol_points.is_empty():
			return _stand()
		return _move(patrol_points[0], Tuning.GUARD_WALK_SPEED)
	if _evacuating:
		_evacuating = false
		_patrol_index = 0
	# A state handler returns {} after switching state so the new state runs
	# this same frame.
	for _i in 8:
		var intent: Dictionary
		match state:
			PATROL:
				intent = _patrol(ctx)
			INVESTIGATE:
				intent = _go_and_look(delta, ctx, pos, true)
			CHECK_ID:
				intent = _check_id(ctx, pos)
			CHASE:
				intent = _chase(pos)
			SEARCH:
				intent = _go_and_look(delta, ctx, pos, false)
			CARRY:
				intent = _carry(ctx)
			_:
				intent = _stand()
		if not intent.is_empty():
			return intent
	return _stand()


func _patrol(ctx: Dictionary) -> Dictionary:
	var best := _best(false)
	if best != -1:
		_engage(best)
		return {}
	if _take_noise():
		return {}
	if patrol_points.is_empty():
		return _stand()
	_patrol_index = posmod(_patrol_index, patrol_points.size())
	if _reached(ctx, patrol_points[_patrol_index]):
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
	return _move(patrol_points[_patrol_index], Tuning.GUARD_WALK_SPEED)


## INVESTIGATE (noise) and SEARCH (last known spot): walk there, look around
## for a while, then patrol.
func _go_and_look(delta: float, ctx: Dictionary, pos: Vector3, investigating: bool) -> Dictionary:
	var best := _best(investigating)
	if best != -1:
		_engage(best)
		return {}
	if _take_noise():
		return {}
	if not _arrived and _reached(ctx, _dest):
		_arrive(pos, Tuning.INVESTIGATE_SECONDS if investigating else Tuning.SEARCH_SECONDS)
	if not _arrived:
		return _move(_dest, Tuning.GUARD_WALK_SPEED)
	var dt := 0.0 if _arrived_tick == _tick else delta
	_wait_left -= dt
	if _wait_left <= 0.0:
		_to_patrol()
		return {}
	_look_angle = wrapf(_look_angle + deg_to_rad(Tuning.GUARD_LOOK_AROUND_DEGREES_PER_SECOND) * dt, -PI, PI)
	return _stand(pos + Vector3(cos(_look_angle), 0.0, sin(_look_angle)))


func _check_id(ctx: Dictionary, pos: Vector3) -> Dictionary:
	var k: Known = _memory.get(target_pid)
	if k == null or not k.available:
		return _drop_target()
	var mode := _approach(k)
	if mode == Approach.CHASE:
		_start_chase(k)
		return {}
	var dist := Perception.flat_distance(pos, k.position)
	if not _asked:
		if mode == Approach.NONE:
			return _drop_target()
		var rival := _rival(k, false)
		if rival != -1:
			_engage(rival)
			return {}
		if _take_noise():
			return {}
		if _unseen_for(k) >= Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS:
			_start_search(k.position, false, pos)
			return {}
		if dist <= Tuning.TALK_RANGE and _visible(k) and _action == ACT_NONE:
			_asked = true
			_action = ACT_ASK_ID
			return _stand(k.position)
		return _move(k.position, Tuning.GUARD_WALK_SPEED)
	# Quiz under way: wait for the answer unless someone worth chasing shows up.
	var chase_rival := _rival(k, true)
	if chase_rival != -1:
		_engage(chase_rival)
		return {}
	var result := int(ctx.get("id_check", ID_PENDING))
	if result == ID_PASSED:
		_cleared[k.pid] = {"level": _level_for(k.heat), "poster": k.matches_poster}
		_to_patrol()
		return {}
	if result == ID_FAILED:
		k.must_chase = true
		if _visible(k) and dist <= Tuning.GRAB_RANGE and _action == ACT_NONE:
			_grab()
		else:
			_start_chase(k)
		return {}
	if dist > Tuning.ID_CHECK_WALKAWAY_DISTANCE or _unseen_for(k) >= Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS:
		_start_chase(k)
		return {}
	return _stand(k.position)


func _chase(pos: Vector3) -> Dictionary:
	var k: Known = _memory.get(target_pid)
	if k == null or _approach(k) == Approach.NONE:
		return _drop_target()
	var rival := _rival(k, false)
	if rival != -1:
		_engage(rival)
		return {}
	if _visible(k) and Perception.flat_distance(pos, k.position) <= Tuning.GRAB_RANGE and _action == ACT_NONE:
		_grab()
		return {}
	if _unseen_for(k) >= Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS:
		_start_search(k.position, false, pos)
		return {}
	var speed := Tuning.HEAD_OF_SECURITY_RUN_SPEED if security_type == HR.SecurityType.HEAD_OF_SECURITY else Tuning.GUARD_RUN_SPEED
	return _move(k.position, speed, k.position)


func _carry(ctx: Dictionary) -> Dictionary:
	if bool(ctx.get("at_back_room", false)) and _action == ACT_NONE:
		_action = ACT_DROP
		forget(target_pid)
		_to_patrol()
		return {}
	return _move(back_room, Tuning.GUARD_CARRY_SPEED)


# --- Transitions --------------------------------------------------------------

func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_changed.emit(old, new_state)


func _engage(pid: int) -> void:
	var k: Known = _memory.get(pid)
	if k == null:
		return
	if _approach(k) == Approach.CHASE:
		_start_chase(k)
		return
	target_pid = pid
	_asked = false
	_set_state(CHECK_ID)


func _start_chase(k: Known) -> void:
	target_pid = k.pid
	k.must_chase = true
	_asked = false
	_set_state(CHASE)


func _grab() -> void:
	_action = ACT_GRAB
	_asked = false
	_set_state(CARRY)


func _start_search(spot: Vector3, arrived: bool, pos: Vector3) -> void:
	_asked = false
	_dest = spot
	_arrived = false
	if arrived:
		_arrive(pos, Tuning.SEARCH_SECONDS)
	_set_state(SEARCH)


func _to_patrol() -> void:
	target_pid = -1
	_asked = false
	_set_state(PATROL)


## Gives up the current target for the best visible candidate, else patrols.
func _drop_target() -> Dictionary:
	target_pid = -1
	var best := _best(false)
	if best != -1:
		_engage(best)
	else:
		_to_patrol()
	return {}


## Starts (or redirects) an investigation if a noise was heard this frame.
func _take_noise() -> bool:
	if _noise == null:
		return false
	_dest = _noise
	_noise = null
	_arrived = false
	_asked = false
	target_pid = -1
	_set_state(INVESTIGATE)
	return true


func _arrive(pos: Vector3, seconds: float) -> void:
	_arrived = true
	_arrived_tick = _tick
	_wait_left = seconds
	var heading := pos - _prev_position
	if not Vector2(heading.x, heading.z).is_zero_approx():
		_look_angle = atan2(heading.z, heading.x)


# --- Perception bookkeeping ---------------------------------------------------

func _ingest(seen: Variant) -> void:
	if not (seen is Array):
		return
	for entry: Variant in seen:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var pid := int(d.get("pid", -1))
		if pid < 0:
			continue
		var k: Known = _memory.get(pid)
		if k == null:
			k = Known.new()
			k.pid = pid
			_memory[pid] = k
		k.heat = float(d.get("heat", 0.0))
		k.position = _vec(d.get("position"), k.position)
		k.matches_poster = bool(d.get("matches_poster", false))
		k.staff_uniform = bool(d.get("staff_uniform", false))
		k.running = bool(d.get("running", false))
		k.available = bool(d.get("available", true))
		k.last_seen = _time
		k.seen_tick = _tick
		if not k.available and not (state == CARRY and pid == target_pid):
			# In someone else's custody: a clean slate once they are back.
			k.must_chase = false
		_update_cleared(k)


func _update_cleared(k: Known) -> void:
	if not _cleared.has(k.pid):
		return
	var entry: Dictionary = _cleared[k.pid]
	var level := _level_for(k.heat)
	if level > int(entry["level"]) or (k.matches_poster and not bool(entry["poster"])):
		_cleared.erase(k.pid)
		return
	entry["level"] = mini(int(entry["level"]), level)
	entry["poster"] = k.matches_poster


func _expire_memory() -> void:
	for pid: int in _memory.keys():
		var k: Known = _memory[pid]
		if _time - k.last_seen > Tuning.GUARD_MEMORY_SECONDS:
			_memory.erase(pid)


func _approach(k: Known) -> int:
	if not k.available:
		return Approach.NONE
	var level := _level_for(k.heat)
	if level >= HR.HeatLevel.WANTED:
		return Approach.CHASE
	if k.staff_uniform:
		return Approach.NONE
	if k.must_chase:
		return Approach.CHASE
	if _cleared.has(k.pid):
		return Approach.NONE
	if level == HR.HeatLevel.SUSPECTED or k.matches_poster:
		return Approach.CHASE if security_type == HR.SecurityType.UNDERCOVER else Approach.CHECK
	return Approach.NONE


## Highest-Heat player in view this frame worth approaching (only ones worth
## chasing if `chase_only`), or −1.
func _best(chase_only: bool) -> int:
	var heat_by_pid := {}
	for pid: int in _memory:
		var k: Known = _memory[pid]
		if not _visible(k):
			continue
		var mode := _approach(k)
		if mode == Approach.NONE or (chase_only and mode != Approach.CHASE):
			continue
		heat_by_pid[pid] = k.heat
	return Perception.pick_target(heat_by_pid)


## Highest-Heat player in view with strictly more Heat than the target, or −1.
func _rival(target: Known, chase_only: bool) -> int:
	var heat_by_pid := {}
	for pid: int in _memory:
		var k: Known = _memory[pid]
		if pid == target.pid or not _visible(k) or k.heat <= target.heat:
			continue
		var mode := _approach(k)
		if mode == Approach.NONE or (chase_only and mode != Approach.CHASE):
			continue
		heat_by_pid[pid] = k.heat
	return Perception.pick_target(heat_by_pid)


func _visible(k: Known) -> bool:
	return k.seen_tick == _tick


func _unseen_for(k: Known) -> float:
	return _time - k.last_seen


## Loudest noise heard this frame (largest radius; the later one on a tie).
func _loudest_noise(pos: Vector3, noises: Variant) -> Variant:
	if not (noises is Array):
		return null
	var best: Variant = null
	var best_radius := -INF
	for entry: Variant in noises:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var noise_pos := _vec(d.get("position"), pos)
		var radius := float(d.get("radius", 0.0))
		if Perception.can_hear(pos, noise_pos, radius) and radius >= best_radius:
			best = noise_pos
			best_radius = radius
	return best


## True if the world says we arrived and we were actually heading to `dest`.
func _reached(ctx: Dictionary, dest: Vector3) -> bool:
	if not bool(ctx.get("reached_destination", false)) or not (_last_move_to is Vector3):
		return false
	var last: Vector3 = _last_move_to
	return last.is_equal_approx(dest)


# --- Helpers ------------------------------------------------------------------

func _move(dest: Vector3, speed: float, face: Variant = null) -> Dictionary:
	return {"move_to": dest, "speed": speed, "face": face, "action": _action}


func _stand(face: Variant = null) -> Dictionary:
	return {"move_to": null, "speed": 0.0, "face": face, "action": _action}


## HR.HeatLevel for a Heat value (same thresholds as HeatMeter.level_for).
static func _level_for(heat: float) -> int:
	if heat >= Tuning.WANTED_AT:
		return HR.HeatLevel.WANTED
	if heat >= Tuning.SUSPECTED_AT:
		return HR.HeatLevel.SUSPECTED
	if heat >= Tuning.WATCHED_AT:
		return HR.HeatLevel.WATCHED
	return HR.HeatLevel.UNNOTICED


static func _vec(value: Variant, fallback: Vector3) -> Vector3:
	if value is Vector3:
		return value
	return fallback
