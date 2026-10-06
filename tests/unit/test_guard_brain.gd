extends TestCase
## Perception geometry and GuardBrain transitions, driven by scripted ctx frames.

const PATROL := HR.GuardState.PATROL
const INVESTIGATE := HR.GuardState.INVESTIGATE
const CHECK_ID := HR.GuardState.CHECK_ID
const CHASE := HR.GuardState.CHASE
const SEARCH := HR.GuardState.SEARCH
const CARRY := HR.GuardState.CARRY
const STUNNED := HR.GuardState.STUNNED

const DT := 0.25
const P0 := Vector3(0, 0, 0)
const P1 := Vector3(10, 0, 0)
const P2 := Vector3(10, 0, 10)
const BACK := Vector3(-20, 0, -5)
const GUARD_AT := Vector3(0, 0, 0)

const UNNOTICED_HEAT := 10.0
const WATCHED_HEAT := 30.0
const SUSPECTED_HEAT := 60.0
const WANTED_HEAT := 85.0

## [old_state, new_state] pairs from state_changed.
var transitions: Array = []


func before_each() -> void:
	transitions.clear()


func _brain(security_type: int = HR.SecurityType.FLOOR_GUARD) -> GuardBrain:
	var points: Array[Vector3] = [P0, P1, P2]
	var brain := GuardBrain.new(points, security_type, BACK)
	brain.state_changed.connect(_on_state_changed)
	return brain


func _on_state_changed(old_state: int, new_state: int) -> void:
	transitions.append([old_state, new_state])


func _ctx(pos: Vector3, seen: Array = [], extra: Dictionary = {}) -> Dictionary:
	var ctx := {
		"position": pos, "seen": seen, "noises": [], "id_check": 0,
		"reached_destination": false, "at_back_room": false, "stunned": false,
		"freed": false, "fire_alarm": false,
	}
	ctx.merge(extra, true)
	return ctx


func _p(pid: int, pos: Vector3, heat: float, extra: Dictionary = {}) -> Dictionary:
	var d := {
		"pid": pid, "position": pos, "heat": heat, "matches_poster": false,
		"running": false, "staff_uniform": false, "available": true,
	}
	d.merge(extra, true)
	return d


func _noise(pos: Vector3, radius: float, kind: StringName = &"knock_over") -> Dictionary:
	return {"position": pos, "radius": radius, "kind": kind}


## Runs `frames` updates with the same ctx and returns the last intent.
func _run(brain: GuardBrain, frames: int, ctx: Dictionary, delta: float = DT) -> Dictionary:
	var intent := {}
	for i in frames:
		intent = brain.update(delta, ctx)
	return intent


## Number of updates of `delta` that add up to at least `seconds`.
func _frames_for(seconds: float, delta: float = DT) -> int:
	return int(ceil(seconds / delta - 0.0001))


## Brain in CHECK_ID on pid 1 standing next to them, quiz asked.
func _brain_mid_quiz(player_pos: Vector3 = Vector3(1.5, 0, 0), heat: float = SUSPECTED_HEAT) -> GuardBrain:
	var brain := _brain()
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, player_pos, heat)]))
	assert_eq(intent["action"], &"ask_id", "setup: quiz asked")
	assert_eq(brain.state, CHECK_ID, "setup: checking ID")
	return brain


## Brain in CARRY holding pid 1.
func _brain_carrying(security_type: int = HR.SecurityType.FLOOR_GUARD) -> GuardBrain:
	var brain := _brain(security_type)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1, 0, 0), WANTED_HEAT)]))
	assert_eq(intent["action"], &"grab", "setup: grabbed")
	assert_eq(brain.state, CARRY, "setup: carrying")
	return brain


# --- Perception ---------------------------------------------------------------

func test_cone_sees_straight_ahead_in_range() -> void:
	assert_true(Perception.in_vision_cone(P0, Vector3.FORWARD, Vector3(0, 0, -5), 110.0, 14.0))


func test_cone_does_not_see_behind() -> void:
	assert_false(Perception.in_vision_cone(P0, Vector3.FORWARD, Vector3(0, 0, 5), 110.0, 14.0))


func test_cone_range_is_inclusive() -> void:
	assert_true(Perception.in_vision_cone(P0, Vector3.FORWARD, Vector3(0, 0, -14), 110.0, 14.0), "at range")
	assert_false(Perception.in_vision_cone(P0, Vector3.FORWARD, Vector3(0, 0, -14.01), 110.0, 14.0), "past range")


func test_cone_fov_is_full_angle() -> void:
	# fov 90 => 45 degrees each side.
	var fwd := Vector3(1, 0, 0)
	assert_true(Perception.in_vision_cone(P0, fwd, Vector3(5, 0, 5).rotated(Vector3.UP, deg_to_rad(1.0)), 90.0, 20.0), "44 deg")
	assert_true(Perception.in_vision_cone(P0, fwd, Vector3(5, 0, 5), 90.0, 20.0), "45 deg edge")
	assert_false(Perception.in_vision_cone(P0, fwd, Vector3(5, 0, 5).rotated(Vector3.UP, deg_to_rad(-2.0)), 90.0, 20.0), "47 deg")
	assert_true(Perception.in_vision_cone(P0, fwd, Vector3(1, 0, 5), 170.0, 20.0), "wide cone")


func test_cone_target_at_origin_is_visible() -> void:
	assert_true(Perception.in_vision_cone(P1, Vector3.FORWARD, P1, 10.0, 1.0))
	assert_true(Perception.in_vision_cone(P1, Vector3.FORWARD, P1 + Vector3(0, 2, 0), 10.0, 1.0), "straight above")


func test_cone_ignores_height() -> void:
	# A target high above but ahead counts by floor distance; a tilted forward still works.
	assert_true(Perception.in_vision_cone(P0, Vector3.FORWARD, Vector3(0, 10, -5), 60.0, 6.0))
	assert_true(Perception.in_vision_cone(Vector3(0, 4, 0), Vector3(0, -1, -1), Vector3(0, 0, -5), 60.0, 6.0))
	assert_false(Perception.in_vision_cone(P0, Vector3.FORWARD, Vector3(0, 0, -7), 60.0, 6.0), "range is horizontal")


func test_cone_straight_down_sees_all_around_in_range() -> void:
	assert_true(Perception.in_vision_cone(Vector3(0, 5, 0), Vector3.DOWN, Vector3(3, 0, 3), 50.0, 18.0))
	assert_false(Perception.in_vision_cone(Vector3(0, 5, 0), Vector3.DOWN, Vector3(30, 0, 0), 50.0, 18.0))


func test_can_hear_within_radius_inclusive() -> void:
	assert_true(Perception.can_hear(P0, Vector3(3, 0, 4), 5.0), "edge")
	assert_true(Perception.can_hear(P0, Vector3(1, 0, 1), 5.0))
	assert_false(Perception.can_hear(P0, Vector3(3, 0, 4.1), 5.0))


func test_pick_target_highest_heat() -> void:
	assert_eq(Perception.pick_target({1: 30.0, 2: 75.5, 3: 60.0}), 2)


func test_pick_target_ties_go_to_lowest_pid() -> void:
	assert_eq(Perception.pick_target({4: 50.0, 2: 50.0, 3: 10.0}), 2)


func test_pick_target_empty_is_minus_one() -> void:
	assert_eq(Perception.pick_target({}), -1)


func test_flat_distance_ignores_height() -> void:
	assert_almost_eq(Perception.flat_distance(P0, Vector3(3, 9, 4)), 5.0)


# --- Patrol -------------------------------------------------------------------

func test_starts_in_patrol_walking_to_first_point() -> void:
	var brain := _brain()
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)
	assert_eq(brain.security_type, HR.SecurityType.FLOOR_GUARD)
	var intent := brain.update(DT, _ctx(Vector3(-3, 0, 0)))
	assert_eq(intent["move_to"], P0)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_WALK_SPEED)
	assert_null(intent["face"])
	assert_eq(intent["action"], &"")


func test_patrol_advances_on_reached_and_loops() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(P0))
	assert_eq(brain.update(DT, _ctx(P0, [], {"reached_destination": true}))["move_to"], P1)
	assert_eq(brain.update(DT, _ctx(Vector3(5, 0, 0)))["move_to"], P1, "keeps going until reached")
	assert_eq(brain.update(DT, _ctx(P1, [], {"reached_destination": true}))["move_to"], P2)
	assert_eq(brain.update(DT, _ctx(P2, [], {"reached_destination": true}))["move_to"], P0, "loops")
	assert_eq(brain.update(DT, _ctx(P0, [], {"reached_destination": true}))["move_to"], P1)
	assert_eq(brain.state, PATROL)
	assert_eq(transitions.size(), 0)


func test_patrol_ignores_reached_flag_meant_for_another_destination() -> void:
	var brain := _brain()
	# Nothing was asked yet, so a reached flag can't be for P0.
	assert_eq(brain.update(DT, _ctx(P0, [], {"reached_destination": true}))["move_to"], P0)


func test_patrol_without_points_stands() -> void:
	var none: Array[Vector3] = []
	var brain := GuardBrain.new(none)
	var intent := brain.update(DT, _ctx(P1, [], {"reached_destination": true}))
	assert_null(intent["move_to"])
	assert_eq(intent["speed"], 0.0)
	assert_eq(brain.state, PATROL)


func test_unnoticed_and_watched_are_never_approached() -> void:
	var brain := _brain()
	var seen := [_p(1, Vector3(3, 0, 0), UNNOTICED_HEAT), _p(2, Vector3(4, 0, 0), WATCHED_HEAT), _p(3, Vector3(5, 0, 0), Tuning.SUSPECTED_AT - 0.01)]
	var intent := _run(brain, 8, _ctx(GUARD_AT, seen))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)
	assert_eq(intent["move_to"], P0)
	assert_eq(brain.known_heat().size(), 3, "still remembered")


# --- Check ID -----------------------------------------------------------------

func test_suspected_player_gets_walked_over_to() -> void:
	var brain := _brain()
	var player := Vector3(6, 0, 0)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, player, Tuning.SUSPECTED_AT)]))
	assert_eq(brain.state, CHECK_ID)
	assert_eq(brain.target_pid, 1)
	assert_eq(intent["move_to"], player)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_WALK_SPEED)
	assert_eq(intent["action"], &"")
	assert_eq(transitions, [[PATROL, CHECK_ID]])


func test_check_id_asks_once_within_talk_range_by_distance() -> void:
	var brain := _brain()
	var player := Vector3(6, 0, 0)
	# reached_destination is ignored: only the distance to the player counts.
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)], {"reached_destination": true}))
	intent = brain.update(DT, _ctx(Vector3(3, 0, 0), [_p(1, player, SUSPECTED_HEAT)], {"reached_destination": true}))
	assert_eq(intent["action"], &"", "3 m away: still walking")
	assert_eq(intent["move_to"], player)
	var near := player - Vector3(Tuning.TALK_RANGE - 0.05, 0, 0)
	intent = brain.update(DT, _ctx(near, [_p(1, player, SUSPECTED_HEAT)]))
	assert_eq(intent["action"], &"ask_id")
	assert_null(intent["move_to"], "stops to talk")
	assert_eq(intent["face"], player)
	var asks := 1
	for i in 10:
		intent = brain.update(DT, _ctx(near, [_p(1, player, SUSPECTED_HEAT)], {"reached_destination": true}))
		if intent["action"] == &"ask_id":
			asks += 1
	assert_eq(asks, 1, "ask_id exactly once")
	assert_eq(brain.state, CHECK_ID)
	assert_null(intent["move_to"])
	assert_eq(intent["face"], player)


func test_check_id_needs_target_in_view_to_ask() -> void:
	var brain := _brain()
	var player := Vector3(1.5, 0, 0)
	brain.update(DT, _ctx(Vector3(5, 0, 0), [_p(1, player, SUSPECTED_HEAT)]))
	var intent := brain.update(DT, _ctx(GUARD_AT, []))
	assert_eq(intent["action"], &"", "close, but not in view")
	intent = brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)]))
	assert_eq(intent["action"], &"ask_id")


func test_id_pass_returns_to_patrol_and_is_not_rechecked_at_same_level() -> void:
	var brain := _brain_mid_quiz()
	var player := Vector3(1.5, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)]))
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)], {"id_check": 1}))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)
	# Still Suspected, even a bit hotter: left alone.
	var intent := _run(brain, 6, _ctx(GUARD_AT, [_p(1, player, Tuning.WANTED_AT - 1.0)]))
	assert_eq(brain.state, PATROL)
	assert_ne(intent["action"], &"ask_id")
	# Rising to Wanted is a new level: chase.
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(3, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 1)


func test_passed_player_rechecked_after_cooling_and_rising_again() -> void:
	var brain := _brain_mid_quiz()
	var player := Vector3(1.5, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)], {"id_check": 1}))
	assert_eq(brain.state, PATROL)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, WATCHED_HEAT)]))
	assert_eq(brain.state, PATROL)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, Tuning.SUSPECTED_AT + 1.0)]))
	assert_eq(brain.state, CHECK_ID, "rose from Watched back to Suspected")


func test_passed_player_rechecked_on_new_poster_match() -> void:
	var brain := _brain_mid_quiz()
	var player := Vector3(1.5, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)], {"id_check": 1}))
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)]))
	assert_eq(brain.state, PATROL)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT, {"matches_poster": true})]))
	assert_eq(brain.state, CHECK_ID, "new poster match")


func test_passed_with_poster_match_not_rechecked_for_same_match() -> void:
	var brain := _brain()
	var player := Vector3(1.5, 0, 0)
	var seen := [_p(1, player, UNNOTICED_HEAT, {"matches_poster": true})]
	assert_eq(brain.update(DT, _ctx(GUARD_AT, seen))["action"], &"ask_id")
	brain.update(DT, _ctx(GUARD_AT, seen, {"id_check": 1}))
	assert_eq(brain.state, PATROL)
	_run(brain, 5, _ctx(GUARD_AT, seen))
	assert_eq(brain.state, PATROL, "same poster match, already cleared")
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, UNNOTICED_HEAT)]))
	brain.update(DT, _ctx(GUARD_AT, seen))
	assert_eq(brain.state, CHECK_ID, "matched again after not matching")


func test_id_fail_within_grab_range_grabs() -> void:
	var brain := _brain_mid_quiz(Vector3(1.0, 0, 0))
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1.0, 0, 0), SUSPECTED_HEAT)], {"id_check": 2}))
	assert_eq(intent["action"], &"grab")
	assert_eq(brain.state, CARRY)
	assert_eq(brain.target_pid, 1)
	assert_eq(intent["move_to"], BACK)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_CARRY_SPEED)


func test_id_fail_outside_grab_range_chases() -> void:
	var player := Vector3(Tuning.GRAB_RANGE + 0.5, 0, 0)
	var brain := _brain_mid_quiz(player)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)], {"id_check": 2}))
	assert_eq(brain.state, CHASE)
	assert_eq(intent["action"], &"")
	assert_eq(intent["move_to"], player)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_RUN_SPEED)
	# Next frame, caught up: grab.
	intent = brain.update(DT, _ctx(player - Vector3(1, 0, 0), [_p(1, player, SUSPECTED_HEAT)]))
	assert_eq(intent["action"], &"grab")
	assert_eq(brain.state, CARRY)


func test_walking_away_from_check_starts_chase() -> void:
	var brain := _brain_mid_quiz()
	var stay := Vector3(Tuning.ID_CHECK_WALKAWAY_DISTANCE - 0.1, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, stay, SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHECK_ID, "inside walk-away distance")
	var gone := Vector3(Tuning.ID_CHECK_WALKAWAY_DISTANCE + 0.1, 0, 0)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, gone, SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 1)
	assert_eq(intent["move_to"], gone)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_RUN_SPEED)


func test_vanishing_during_check_counts_as_walking_away() -> void:
	var brain := _brain_mid_quiz()
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS) - 1, _ctx(GUARD_AT, []))
	assert_eq(brain.state, CHECK_ID)
	brain.update(DT, _ctx(GUARD_AT, []))
	# Fled out of sight: chase gives way to a search of the last spot.
	assert_eq(brain.state, SEARCH)
	assert_has(transitions, [CHECK_ID, CHASE])


func test_target_cooling_off_before_ask_drops_check() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHECK_ID)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WATCHED_HEAT)]))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)


func test_suspected_target_turning_wanted_during_check_is_chased() -> void:
	var brain := _brain_mid_quiz()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1.5, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)


func test_poster_match_checks_id_even_at_low_heat() -> void:
	var brain := _brain()
	var seen := [_p(2, Vector3(5, 0, 0), 40.0), _p(1, Vector3(6, 0, 0), UNNOTICED_HEAT, {"matches_poster": true})]
	brain.update(DT, _ctx(GUARD_AT, seen))
	assert_eq(brain.state, CHECK_ID)
	assert_eq(brain.target_pid, 1)


# --- Chase, grab, carry -------------------------------------------------------

func test_wanted_player_is_chased_at_run_speed() -> void:
	var brain := _brain()
	var player := Vector3(8, 0, 2)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, player, Tuning.WANTED_AT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 1)
	assert_eq(intent["move_to"], player)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_RUN_SPEED)
	assert_eq(intent["action"], &"")
	assert_eq(transitions, [[PATROL, CHASE]])


func test_head_of_security_runs_faster() -> void:
	var brain := _brain(HR.SecurityType.HEAD_OF_SECURITY)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_almost_eq(float(intent["speed"]), Tuning.HEAD_OF_SECURITY_RUN_SPEED)


func test_chase_follows_player_and_grabs_in_range() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	var intent := brain.update(DT, _ctx(Vector3(2, 0, 0), [_p(1, Vector3(9, 0, 1), WANTED_HEAT)]))
	assert_eq(intent["move_to"], Vector3(9, 0, 1), "follows the player")
	assert_eq(intent["action"], &"")
	var at := Vector3(9, 0, 1) - Vector3(Tuning.GRAB_RANGE - 0.05, 0, 0)
	intent = brain.update(DT, _ctx(at, [_p(1, Vector3(9, 0, 1), WANTED_HEAT)]))
	assert_eq(intent["action"], &"grab")
	assert_eq(brain.state, CARRY)
	assert_eq(brain.target_pid, 1)
	assert_eq(intent["move_to"], BACK)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_CARRY_SPEED)


func test_chase_runs_to_last_known_position_while_briefly_unseen() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	var intent := brain.update(DT, _ctx(Vector3(1, 0, 0), []))
	assert_eq(brain.state, CHASE)
	assert_eq(intent["move_to"], Vector3(8, 0, 0))
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_RUN_SPEED)


func test_lose_sight_then_search_then_patrol() -> void:
	var brain := _brain()
	var last_seen := Vector3(8, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, last_seen, WANTED_HEAT)]))
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS) - 1, _ctx(Vector3(2, 0, 0), []))
	assert_eq(brain.state, CHASE, "not lost yet")
	var intent := brain.update(DT, _ctx(Vector3(3, 0, 0), []))
	assert_eq(brain.state, SEARCH)
	assert_eq(intent["move_to"], last_seen)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_WALK_SPEED)
	# Still walking: the search timer doesn't run yet.
	_run(brain, _frames_for(Tuning.SEARCH_SECONDS) + 4, _ctx(Vector3(5, 0, 0), []))
	assert_eq(brain.state, SEARCH)
	intent = brain.update(DT, _ctx(last_seen, [], {"reached_destination": true}))
	assert_null(intent["move_to"], "looks around at the spot")
	assert_not_null(intent["face"])
	var first_face: Vector3 = intent["face"]
	intent = _run(brain, _frames_for(Tuning.SEARCH_SECONDS) - 1, _ctx(last_seen, [], {"reached_destination": true}))
	assert_eq(brain.state, SEARCH)
	assert_ne(intent["face"], first_face, "turns while looking around")
	intent = brain.update(DT, _ctx(last_seen, [], {"reached_destination": true}))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)
	assert_not_null(intent["move_to"])
	assert_eq(transitions, [[PATROL, CHASE], [CHASE, SEARCH], [SEARCH, PATROL]])


func test_search_finds_player_again() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS), _ctx(GUARD_AT, []))
	assert_eq(brain.state, SEARCH)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(12, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 1)


func test_suspected_player_interrupts_search() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS), _ctx(GUARD_AT, []))
	assert_eq(brain.state, SEARCH)
	brain.update(DT, _ctx(GUARD_AT, [_p(2, Vector3(5, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHECK_ID)
	assert_eq(brain.target_pid, 2)


func test_carry_drops_at_back_room_then_patrols() -> void:
	var brain := _brain_carrying()
	var intent := _run(brain, 5, _ctx(Vector3(-5, 0, 0), [_p(1, Vector3(-5, 0, 0), WANTED_HEAT, {"available": false})]))
	assert_eq(brain.state, CARRY)
	assert_eq(intent["move_to"], BACK)
	assert_eq(intent["action"], &"")
	intent = brain.update(DT, _ctx(BACK, [], {"at_back_room": true}))
	assert_eq(intent["action"], &"drop_at_back_room")
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)
	assert_false(brain.known_heat().has(1), "dropped player forgotten")
	intent = brain.update(DT, _ctx(BACK, [], {"at_back_room": true}))
	assert_eq(intent["action"], &"", "drop only once")


func test_back_room_is_settable() -> void:
	var brain := _brain_carrying()
	brain.back_room = Vector3(50, 0, 50)
	assert_eq(brain.update(DT, _ctx(GUARD_AT))["move_to"], Vector3(50, 0, 50))


func test_carry_ignores_hotter_players_and_noises() -> void:
	var brain := _brain_carrying()
	var seen := [_p(1, Vector3(1, 0, 0), WANTED_HEAT, {"available": false}), _p(2, Vector3(2, 0, 0), 99.0)]
	var intent := _run(brain, 4, _ctx(GUARD_AT, seen, {"noises": [_noise(Vector3(3, 0, 0), 30.0)]}))
	assert_eq(brain.state, CARRY)
	assert_eq(brain.target_pid, 1)
	assert_eq(intent["move_to"], BACK)
	assert_eq(intent["action"], &"")


func test_freed_while_carrying_stuns_then_searches_where_it_stands() -> void:
	var brain := _brain_carrying()
	var here := Vector3(-4, 0, -1)
	var intent := brain.update(DT, _ctx(here, [], {"freed": true}))
	assert_eq(brain.state, STUNNED)
	assert_eq(intent["action"], &"", "already free: no release")
	assert_null(intent["move_to"])
	assert_eq(intent["speed"], 0.0)
	intent = _run(brain, _frames_for(Tuning.STUN_SECONDS) - 1, _ctx(here))
	assert_eq(brain.state, STUNNED)
	assert_eq(intent["speed"], 0.0)
	intent = brain.update(DT, _ctx(here))
	assert_eq(brain.state, SEARCH)
	assert_null(intent["move_to"], "searches at its own position")
	_run(brain, _frames_for(Tuning.SEARCH_SECONDS) - 1, _ctx(here))
	assert_eq(brain.state, SEARCH)
	brain.update(DT, _ctx(here))
	assert_eq(brain.state, PATROL)


func test_freed_player_is_chased_after_the_stun() -> void:
	var brain := _brain_carrying()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1, 0, 0), SUSPECTED_HEAT, {"available": false})]))
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(2, 0, 0), SUSPECTED_HEAT)], {"freed": true, "stunned": true}))
	assert_eq(brain.state, STUNNED)
	_run(brain, _frames_for(Tuning.STUN_SECONDS), _ctx(GUARD_AT, [_p(1, Vector3(3, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHASE, "escapee chased, not asked for ID")
	assert_eq(brain.target_pid, 1)


func test_stunned_while_carrying_releases() -> void:
	var brain := _brain_carrying()
	var intent := brain.update(DT, _ctx(GUARD_AT, [], {"stunned": true}))
	assert_eq(brain.state, STUNNED)
	assert_eq(intent["action"], &"release")


# --- Stun ---------------------------------------------------------------------

func test_stun_from_any_state_stands_still() -> void:
	for setup in ["patrol", "check", "chase", "investigate"]:
		var brain := _brain()
		if setup == "check":
			brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(6, 0, 0), SUSPECTED_HEAT)]))
		elif setup == "chase":
			brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(6, 0, 0), WANTED_HEAT)]))
		elif setup == "investigate":
			brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(Vector3(4, 0, 0), 10.0)]}))
		var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1, 0, 0), WANTED_HEAT)], {"stunned": true}))
		assert_eq(brain.state, STUNNED, setup)
		assert_null(intent["move_to"], setup)
		assert_eq(intent["speed"], 0.0, setup)
		assert_eq(intent["action"], &"", setup)
		# A Wanted player right next to it doesn't matter while stunned.
		intent = brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1, 0, 0), WANTED_HEAT)]))
		assert_eq(brain.state, STUNNED, setup)
		assert_eq(intent["action"], &"", setup)


func test_new_stun_restarts_timer() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [], {"stunned": true}))
	_run(brain, _frames_for(Tuning.STUN_SECONDS) - 2, _ctx(GUARD_AT))
	brain.update(DT, _ctx(GUARD_AT, [], {"stunned": true}))
	_run(brain, _frames_for(Tuning.STUN_SECONDS) - 1, _ctx(GUARD_AT))
	assert_eq(brain.state, STUNNED)
	brain.update(DT, _ctx(GUARD_AT))
	assert_eq(brain.state, SEARCH)


func test_after_stun_chases_wanted_in_view() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(6, 0, 0), WANTED_HEAT)]))
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1, 0, 0), WANTED_HEAT)], {"stunned": true}))
	_run(brain, _frames_for(Tuning.STUN_SECONDS), _ctx(GUARD_AT, [_p(1, Vector3(5, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_has(transitions, [STUNNED, SEARCH])


# --- Targeting ----------------------------------------------------------------

func test_picks_highest_heat_first() -> void:
	var brain := _brain()
	var seen := [_p(1, Vector3(3, 0, 0), 82.0), _p(2, Vector3(9, 0, 0), 95.0), _p(3, Vector3(4, 0, 0), SUSPECTED_HEAT)]
	var intent := brain.update(DT, _ctx(GUARD_AT, seen))
	assert_eq(brain.target_pid, 2)
	assert_eq(brain.state, CHASE)
	assert_eq(intent["move_to"], Vector3(9, 0, 0))


func test_equal_heat_picks_lowest_pid() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(7, Vector3(3, 0, 0), WANTED_HEAT), _p(4, Vector3(9, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.target_pid, 4)


func test_chase_retargets_when_teammate_heat_passes() -> void:
	var brain := _brain()
	var a := Vector3(8, 0, 0)
	var b := Vector3(0, 0, 8)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, a, 85.0), _p(2, b, 84.0)]))
	assert_eq(brain.target_pid, 1)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, a, 85.0), _p(2, b, 85.0)]))
	assert_eq(brain.target_pid, 1, "a tie doesn't steal the chase")
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, a, 85.0), _p(2, b, 86.0)]))
	assert_eq(brain.target_pid, 2)
	assert_eq(brain.state, CHASE)
	assert_eq(intent["move_to"], b)


func test_chase_retargets_to_hotter_suspect_with_id_check() -> void:
	# Chasing someone who fled a check at Suspected; a hotter Suspected teammate
	# takes priority and gets walked over to.
	var brain := _brain_mid_quiz()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(6, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(7, 0, 0), SUSPECTED_HEAT), _p(2, Vector3(0, 0, 5), SUSPECTED_HEAT + 5.0)]))
	assert_eq(brain.target_pid, 2)
	assert_eq(brain.state, CHECK_ID)


func test_check_walk_retargets_to_hotter_suspect() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), 55.0)]))
	assert_eq(brain.target_pid, 1)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), 55.0), _p(2, Vector3(0, 0, 6), 65.0)]))
	assert_eq(brain.state, CHECK_ID)
	assert_eq(brain.target_pid, 2)
	assert_eq(intent["move_to"], Vector3(0, 0, 6))
	intent = brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), 55.0), _p(2, Vector3(0, 0, 6), 90.0)]))
	assert_eq(brain.state, CHASE, "now Wanted")
	assert_eq(brain.target_pid, 2)


func test_quiz_in_progress_only_yields_to_someone_to_chase() -> void:
	var brain := _brain_mid_quiz()
	var a := Vector3(1.5, 0, 0)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, a, SUSPECTED_HEAT), _p(2, Vector3(0, 0, 6), 75.0)]))
	assert_eq(brain.state, CHECK_ID)
	assert_eq(brain.target_pid, 1, "hotter suspect waits until the quiz ends")
	assert_null(intent["move_to"])
	brain.update(DT, _ctx(GUARD_AT, [_p(1, a, SUSPECTED_HEAT), _p(2, Vector3(0, 0, 6), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 2)


func test_no_retarget_while_carrying() -> void:
	var brain := _brain_carrying()
	brain.update(DT, _ctx(GUARD_AT, [_p(2, Vector3(1, 0, 0), 100.0)]))
	assert_eq(brain.state, CARRY)
	assert_eq(brain.target_pid, 1)


func test_hidden_target_keeps_priority_over_lower_visible_player() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), 95.0), _p(2, Vector3(0, 0, 8), 85.0)]))
	assert_eq(brain.target_pid, 1)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(2, Vector3(0, 0, 8), 85.0)]))
	assert_eq(brain.target_pid, 1, "remembered target still hotter")
	assert_eq(intent["move_to"], Vector3(8, 0, 0))
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS), _ctx(GUARD_AT, [_p(2, Vector3(0, 0, 8), 85.0)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 2, "lost the hidden one: takes the one in view")


func test_unavailable_players_are_ignored() -> void:
	var brain := _brain()
	var seen := [_p(1, Vector3(1, 0, 0), 100.0, {"available": false}), _p(2, Vector3(3, 0, 0), SUSPECTED_HEAT, {"available": false})]
	_run(brain, 4, _ctx(GUARD_AT, seen))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)


func test_target_becoming_unavailable_ends_chase() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT), _p(2, Vector3(0, 0, 8), SUSPECTED_HEAT)]))
	assert_eq(brain.target_pid, 1)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT, {"available": false}), _p(2, Vector3(0, 0, 8), SUSPECTED_HEAT)]))
	assert_eq(brain.target_pid, 2, "someone else grabbed them: next one")
	assert_eq(brain.state, CHECK_ID)
	brain.update(DT, _ctx(GUARD_AT, [_p(2, Vector3(0, 0, 8), SUSPECTED_HEAT, {"available": false})]))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)


func test_memory_expires_after_guard_memory_seconds() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(3, Vector3(30, 0, 0), WATCHED_HEAT)]))
	assert_eq(brain.known_heat(), {3: WATCHED_HEAT})
	_run(brain, _frames_for(Tuning.GUARD_MEMORY_SECONDS), _ctx(GUARD_AT))
	assert_true(brain.known_heat().has(3), "remembered for GUARD_MEMORY_SECONDS")
	brain.update(DT, _ctx(GUARD_AT))
	assert_false(brain.known_heat().has(3), "forgotten after")


func test_fled_player_chased_on_sight_while_remembered() -> void:
	var brain := _brain_mid_quiz()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(6, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS), _ctx(GUARD_AT))
	assert_eq(brain.state, SEARCH)
	# Cooled to Watched, but the guard still remembers them running off.
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(4, 0, 0), WATCHED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 1)


func test_fled_player_forgotten_after_memory_expires() -> void:
	var brain := _brain_mid_quiz()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(6, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	var frames := _frames_for(Tuning.GUARD_MEMORY_SECONDS) + 1
	_run(brain, frames, _ctx(GUARD_AT, [], {"reached_destination": true}))
	assert_false(brain.known_heat().has(1))
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(4, 0, 0), WATCHED_HEAT)]))
	assert_ne(brain.state, CHASE)
	assert_ne(brain.state, CHECK_ID)


# --- Staff uniform and undercover ---------------------------------------------

func test_staff_uniform_ignored_below_wanted() -> void:
	var brain := _brain()
	var staff := {"staff_uniform": true, "matches_poster": true}
	_run(brain, 4, _ctx(GUARD_AT, [_p(1, Vector3(3, 0, 0), Tuning.WANTED_AT - 0.5, staff)]))
	assert_eq(brain.state, PATROL)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(3, 0, 0), Tuning.WANTED_AT, staff)]))
	assert_eq(brain.state, CHASE, "Wanted staff still chased")


func test_changing_into_staff_uniform_ends_check_walk() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHECK_ID)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), SUSPECTED_HEAT, {"staff_uniform": true})]))
	assert_eq(brain.state, PATROL)


func test_undercover_grabs_suspected_without_asking() -> void:
	var brain := _brain(HR.SecurityType.UNDERCOVER)
	var player := Vector3(6, 0, 0)
	var intent := brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(intent["action"], &"")
	assert_eq(intent["move_to"], player)
	var actions: Array = []
	for step in 6:
		var guard_pos := Vector3(1.0 + step, 0, 0)
		intent = brain.update(DT, _ctx(guard_pos, [_p(1, player, SUSPECTED_HEAT)]))
		actions.append(intent["action"])
		if brain.state == CARRY:
			break
	assert_false(actions.has(&"ask_id"), "never asks for ID")
	assert_eq(actions.back(), &"grab")
	assert_eq(brain.state, CARRY)


func test_undercover_chases_poster_match() -> void:
	var brain := _brain(HR.SecurityType.UNDERCOVER)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(5, 0, 0), UNNOTICED_HEAT, {"matches_poster": true})]))
	assert_eq(brain.state, CHASE)


func test_undercover_ignores_watched() -> void:
	var brain := _brain(HR.SecurityType.UNDERCOVER)
	_run(brain, 4, _ctx(GUARD_AT, [_p(1, Vector3(2, 0, 0), WATCHED_HEAT)]))
	assert_eq(brain.state, PATROL)


# --- Investigate ----------------------------------------------------------------

func test_heard_noise_investigated_then_patrol() -> void:
	var brain := _brain()
	var spot := Vector3(6, 0, 3)
	var intent := brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(spot, 10.0)]}))
	assert_eq(brain.state, INVESTIGATE)
	assert_eq(intent["move_to"], spot)
	assert_almost_eq(float(intent["speed"]), Tuning.GUARD_WALK_SPEED)
	intent = _run(brain, 20, _ctx(Vector3(3, 0, 1)))
	assert_eq(brain.state, INVESTIGATE, "the wait starts on arrival")
	assert_eq(intent["move_to"], spot)
	intent = brain.update(DT, _ctx(spot, [], {"reached_destination": true}))
	assert_null(intent["move_to"])
	_run(brain, _frames_for(Tuning.INVESTIGATE_SECONDS) - 1, _ctx(spot, [], {"reached_destination": true}))
	assert_eq(brain.state, INVESTIGATE)
	intent = brain.update(DT, _ctx(spot, [], {"reached_destination": true}))
	assert_eq(brain.state, PATROL)
	assert_eq(intent["move_to"], P0, "resumes the route")
	assert_eq(transitions, [[PATROL, INVESTIGATE], [INVESTIGATE, PATROL]])


func test_reached_flag_for_patrol_point_is_not_arrival_at_noise() -> void:
	var brain := _brain()
	var spot := Vector3(0, 0, 6)
	brain.update(DT, _ctx(Vector3(-1, 0, 0)))
	var intent := brain.update(DT, _ctx(P0, [], {"reached_destination": true, "noises": [_noise(spot, 10.0)]}))
	assert_eq(brain.state, INVESTIGATE)
	assert_eq(intent["move_to"], spot, "still has to walk there")


func test_noise_out_of_earshot_ignored() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(Vector3(20, 0, 0), 10.0)]}))
	assert_eq(brain.state, PATROL)


func test_loudest_noise_wins_and_latest_breaks_ties() -> void:
	var brain := _brain()
	var noises := [_noise(Vector3(2, 0, 0), 10.0), _noise(Vector3(5, 0, 0), 25.0, &"slot_jackpot"), _noise(Vector3(3, 0, 0), 12.0)]
	assert_eq(brain.update(DT, _ctx(GUARD_AT, [], {"noises": noises}))["move_to"], Vector3(5, 0, 0))
	var other := _brain()
	var ties := [_noise(Vector3(2, 0, 0), 10.0), _noise(Vector3(0, 0, 4), 10.0)]
	assert_eq(other.update(DT, _ctx(GUARD_AT, [], {"noises": ties}))["move_to"], Vector3(0, 0, 4))


func test_newer_noise_redirects_investigation() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(Vector3(5, 0, 0), 10.0)]}))
	brain.update(DT, _ctx(Vector3(5, 0, 0), [], {"reached_destination": true}))
	_run(brain, 4, _ctx(Vector3(5, 0, 0), [], {"reached_destination": true}))
	var intent := brain.update(DT, _ctx(Vector3(5, 0, 0), [], {"noises": [_noise(Vector3(5, 0, 6), 8.0)]}))
	assert_eq(brain.state, INVESTIGATE)
	assert_eq(intent["move_to"], Vector3(5, 0, 6))
	# A stale reached flag for the old spot doesn't count as arriving.
	intent = brain.update(DT, _ctx(Vector3(5, 0, 1), [], {"reached_destination": false}))
	assert_eq(intent["move_to"], Vector3(5, 0, 6))


func test_wanted_overrides_investigate_but_suspected_does_not() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(Vector3(6, 0, 0), 10.0)]}))
	_run(brain, 3, _ctx(GUARD_AT, [_p(1, Vector3(3, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, INVESTIGATE, "the noise distracts from a suspect")
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(3, 0, 0), SUSPECTED_HEAT), _p(2, Vector3(0, 0, 3), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	assert_eq(brain.target_pid, 2)


func test_suspect_approached_after_investigation_ends() -> void:
	var brain := _brain()
	var spot := Vector3(6, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(spot, 10.0)]}))
	brain.update(DT, _ctx(spot, [], {"reached_destination": true}))
	_run(brain, _frames_for(Tuning.INVESTIGATE_SECONDS), _ctx(spot, [_p(1, Vector3(3, 0, 0), SUSPECTED_HEAT)], {"reached_destination": true}))
	assert_eq(brain.state, CHECK_ID)
	assert_eq(brain.target_pid, 1)


func test_noise_pulls_guard_off_check_before_asking_only() -> void:
	var brain := _brain()
	var noise := {"noises": [_noise(Vector3(-5, 0, 0), 10.0)]}
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(brain.state, CHECK_ID)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), SUSPECTED_HEAT)], noise))
	assert_eq(brain.state, INVESTIGATE, "distracted on the way over")
	assert_eq(brain.target_pid, -1)
	var quizzing := _brain_mid_quiz()
	quizzing.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(1.5, 0, 0), SUSPECTED_HEAT)], noise))
	assert_eq(quizzing.state, CHECK_ID, "not during the quiz")


func test_chase_ignores_noise() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)], {"noises": [_noise(Vector3(1, 0, 0), 30.0)]}))
	assert_eq(brain.state, CHASE)


func test_noise_interrupts_search() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	_run(brain, _frames_for(Tuning.LOSE_SIGHT_TO_SEARCH_SECONDS), _ctx(GUARD_AT))
	assert_eq(brain.state, SEARCH)
	var intent := brain.update(DT, _ctx(GUARD_AT, [], {"noises": [_noise(Vector3(0, 0, -4), 8.0)]}))
	assert_eq(brain.state, INVESTIGATE)
	assert_eq(intent["move_to"], Vector3(0, 0, -4))


# --- Fire alarm -----------------------------------------------------------------

func test_fire_alarm_clears_guard_off_the_floor() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)]))
	assert_eq(brain.state, CHASE)
	var alarm := {"fire_alarm": true, "noises": [_noise(Vector3(1, 0, 0), 30.0)]}
	var intent := brain.update(DT, _ctx(P2, [_p(1, Vector3(8, 0, 0), WANTED_HEAT)], alarm))
	assert_eq(brain.state, PATROL)
	assert_eq(brain.target_pid, -1)
	assert_true(brain.is_evacuating())
	assert_eq(brain.state_name(), "EVACUATE")
	assert_eq(intent["move_to"], P0)
	assert_eq(intent["action"], &"")
	# Even at the first point and with Wanted players everywhere, it stays put.
	alarm["reached_destination"] = true
	intent = _run(brain, 10, _ctx(P0, [_p(1, Vector3(0.5, 0, 0), 100.0)], alarm))
	assert_eq(brain.state, PATROL)
	assert_eq(intent["move_to"], P0)
	assert_eq(intent["action"], &"")
	# Alarm over: back to work.
	brain.update(DT, _ctx(P0, [_p(1, Vector3(0.5, 0, 0), 100.0)]))
	assert_false(brain.is_evacuating())
	assert_eq(brain.state, CARRY, "grabs the Wanted player next to it")


func test_patrol_resumes_from_first_point_after_fire_alarm() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(P1))
	brain.update(DT, _ctx(P0, [], {"reached_destination": true}))
	brain.update(DT, _ctx(P1, [], {"fire_alarm": true}))
	brain.update(DT, _ctx(P0, [], {"fire_alarm": true, "reached_destination": true}))
	var intent := brain.update(DT, _ctx(P0, [], {"reached_destination": true}))
	assert_eq(intent["move_to"], P1, "at the first point: on to the next")
	assert_eq(brain.state_name(), "PATROL")


func test_fire_alarm_while_carrying_releases() -> void:
	var brain := _brain_carrying()
	var intent := brain.update(DT, _ctx(GUARD_AT, [], {"fire_alarm": true}))
	assert_eq(intent["action"], &"release")
	assert_eq(brain.state, PATROL)
	assert_eq(intent["move_to"], P0)
	intent = brain.update(DT, _ctx(GUARD_AT, [], {"fire_alarm": true}))
	assert_eq(intent["action"], &"", "released once")


func test_fire_alarm_ignores_new_sightings() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT, [_p(5, Vector3(3, 0, 0), WANTED_HEAT)], {"fire_alarm": true}))
	assert_false(brain.known_heat().has(5))


func test_stun_during_fire_alarm_then_evacuates_again() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(P1, [], {"fire_alarm": true}))
	brain.update(DT, _ctx(P1, [], {"fire_alarm": true, "stunned": true}))
	assert_eq(brain.state, STUNNED)
	var intent := _run(brain, _frames_for(Tuning.STUN_SECONDS), _ctx(P1, [], {"fire_alarm": true}))
	assert_eq(brain.state, PATROL)
	assert_true(brain.is_evacuating())
	assert_eq(intent["move_to"], P0)


# --- Signals and debug ----------------------------------------------------------

func test_state_changed_signal_and_debug_label() -> void:
	var brain := _brain()
	brain.update(DT, _ctx(GUARD_AT))
	assert_eq(brain.state_name(), "PATROL")
	assert_eq(brain.debug_label, "PATROL")
	brain.update(DT, _ctx(GUARD_AT, [_p(3, Vector3(5, 0, 0), WANTED_HEAT)]))
	assert_eq(transitions, [[PATROL, CHASE]])
	assert_eq(brain.state_name(), "CHASE")
	assert_eq(brain.debug_label, "CHASE #3")
	assert_eq(GuardBrain.name_of(HR.GuardState.STUNNED), "STUNNED")


func test_full_run_patrol_check_fail_chase_grab_carry_drop() -> void:
	var brain := _brain()
	var player := Vector3(6, 0, 0)
	brain.update(DT, _ctx(GUARD_AT, [_p(1, player, SUSPECTED_HEAT)]))
	var intent := brain.update(DT, _ctx(Vector3(4.5, 0, 0), [_p(1, player, SUSPECTED_HEAT)]))
	assert_eq(intent["action"], &"ask_id")
	brain.update(DT, _ctx(Vector3(4.5, 0, 0), [_p(1, Vector3(7, 0, 0), SUSPECTED_HEAT)], {"id_check": 2}))
	assert_eq(brain.state, CHASE)
	intent = brain.update(DT, _ctx(Vector3(6.5, 0, 0), [_p(1, Vector3(7, 0, 0), SUSPECTED_HEAT)]))
	assert_eq(intent["action"], &"grab")
	brain.update(DT, _ctx(Vector3(0, 0, 0), [_p(1, Vector3(0, 0, 0), SUSPECTED_HEAT, {"available": false})]))
	intent = brain.update(DT, _ctx(BACK, [], {"at_back_room": true}))
	assert_eq(intent["action"], &"drop_at_back_room")
	assert_eq(transitions, [[PATROL, CHECK_ID], [CHECK_ID, CHASE], [CHASE, CARRY], [CARRY, PATROL]])
