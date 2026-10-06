class_name TableState
extends RefCounted
## One table on the floor: who sits there, for how long, each player's win
## streak here, and whether the dealer was swapped on them (cooled). Cooled and
## streak last until that player leaves.

var id: StringName
var game_type: int
var area_id: StringName
## Closed by the fire alarm.
var closed: bool = false

var _seated: Array[int] = []
var _seconds: Dictionary = {}  # pid -> float
var _streaks: Dictionary = {}  # pid -> int
var _cooled: Dictionary = {}  # pid -> true


func _init(p_id: StringName, p_game_type: int, p_area_id: StringName) -> void:
	id = p_id
	game_type = p_game_type
	area_id = p_area_id


## Seats a player. Sitting down again while seated changes nothing.
func seat(pid: int) -> void:
	if _seated.has(pid):
		return
	_seated.append(pid)
	_seconds[pid] = 0.0


## Stands a player up and forgets their seated time, streak and cooled flag.
func leave(pid: int) -> void:
	_seated.erase(pid)
	_seconds.erase(pid)
	_streaks.erase(pid)
	_cooled.erase(pid)


func is_seated(pid: int) -> bool:
	return _seated.has(pid)


func seated_players() -> Array[int]:
	var out: Array[int] = []
	out.assign(_seated)
	return out


## Adds seated time to everyone in a seat.
func tick(delta: float) -> void:
	for pid: int in _seated:
		_seconds[pid] = float(_seconds.get(pid, 0.0)) + delta


func seconds_seated(pid: int) -> float:
	return float(_seconds.get(pid, 0.0))


## Consecutive wins by this player here (0 after a loss or leaving).
func streak(pid: int) -> int:
	return int(_streaks.get(pid, 0))


## Counts a win in the player's streak and returns the new streak.
func record_win(pid: int) -> int:
	var s: int = streak(pid) + 1
	_streaks[pid] = s
	return s


func record_loss(pid: int) -> void:
	_streaks.erase(pid)


## Dealer swap at Watched: the player's win rate here drops until they leave.
func mark_cooled(pid: int) -> void:
	_cooled[pid] = true


func is_cooled(pid: int) -> bool:
	return _cooled.has(pid)


func win_rate_for(pid: int) -> float:
	return Tuning.COOLED_WIN_RATE if is_cooled(pid) else Tuning.WIN_RATE


func to_dict() -> Dictionary:
	var players: Dictionary = {}
	for pid: int in _seated:
		players[pid] = {"seconds": seconds_seated(pid), "streak": streak(pid), "cooled": is_cooled(pid)}
	return {
		"id": id,
		"game_type": game_type,
		"area_id": area_id,
		"closed": closed,
		"players": players,
	}
