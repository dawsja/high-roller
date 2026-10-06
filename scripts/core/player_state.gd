class_name PlayerState
extends RefCounted
## One player's state for the whole run. The current FloorSim owns it and
## mutates it; a new FloorSim (next casino visit) carries it over, keeping the
## pocket, outfit, stash and IDs and resetting the per-visit parts
## (begin_visit). World and UI code read it; they never write to it.

var pid: int = 0
var display_name: String = ""
var heat: HeatMeter = HeatMeter.new()
var wallet: Wallet = Wallet.new()
var outfit: Outfit = Outfit.new()
## Outfits to change into at a restroom (gift-shop buys and stolen pieces land here).
var stash: Array[Outfit] = []
var ids: Array[FakeId] = []
## Index into `ids` of the card the player is playing under (-1 = none).
var id_index: int = -1
## HR.PlayerStatus.
var status: int = HR.PlayerStatus.FREE
## HR.ZoneType of the last zone entered.
var zone: int = HR.ZoneType.ENTRANCE
var area_id: StringName = &""
## Table the player sits at (&"" when standing).
var table_id: StringName = &""
## What security recorded on reaching Suspected in this casino (null if nothing).
var recorded_look: Outfit = null
## Set by the world (FloorSim.set_player_flags): running_in_view, in_camera_view, pit_boss_view.
var flags: Dictionary = {}
## Worn-outfit changes over the run (head of security memory).
var outfit_changes: int = 0

# --- Timers and per-visit bookkeeping (FloorSim only) -------------------------
## Seconds left of DETAINED or ON_CURB.
var status_seconds: float = 0.0
var last_table_id: StringName = &""
## Seconds since standing up from last_table_id (-1 = never sat this visit).
var seconds_since_left_table: float = -1.0
## Last TABLES/SLOTS area entered and seconds since the last area-change cool-off.
var last_game_area: StringName = &""
var seconds_since_area_change: float = INF
## Seconds since a guard last reported seeing this player.
var seconds_unseen: float = INF
## A poster match adds Heat only while armed (once per sighting episode).
var poster_match_armed: bool = true
## Reaching Wanted prints a poster only while armed (once per Wanted episode).
var poster_armed: bool = true
## The pending ID-check question (IdQuiz.make_question), empty when none.
var id_question: Dictionary = {}
var id_check_guard: int = -1
var id_check_seconds: float = 0.0
var steal_cooldown: float = 0.0
## Multi-step rounds in progress (at most one at a time). Read-only for the world.
var high_low: HighLowRun = null
var blackjack: BlackjackRound = null
var round_table_id: StringName = &""


func _init(p_pid: int = 0, p_name: String = "") -> void:
	pid = p_pid
	display_name = p_name
	reset_flags()


## The ID card in use, or null.
func current_id() -> FakeId:
	if id_index < 0 or id_index >= ids.size():
		return null
	return ids[id_index]


## True if any card the player holds still passes a check.
func has_usable_id() -> bool:
	for id: FakeId in ids:
		if id.passes_check():
			return true
	return false


## Index of the first card that passes a check, or -1.
func first_usable_id_index() -> int:
	for i in ids.size():
		if ids[i].passes_check():
			return i
	return -1


## On the floor and grabbable: FREE, SEATED or in an ID check.
func is_available() -> bool:
	return status == HR.PlayerStatus.FREE or status == HR.PlayerStatus.SEATED or status == HR.PlayerStatus.ID_CHECK


## Can make requests that need free hands: FREE or SEATED.
func can_act() -> bool:
	return status == HR.PlayerStatus.FREE or status == HR.PlayerStatus.SEATED


func in_round() -> bool:
	return high_low != null or blackjack != null


## &"high_low", &"blackjack" or &"".
func round_kind() -> StringName:
	if high_low != null:
		return &"high_low"
	if blackjack != null:
		return &"blackjack"
	return &""


func level() -> int:
	return heat.level()


func reset_flags() -> void:
	flags = {"running_in_view": false, "in_camera_view": false, "pit_boss_view": false}


## Per-visit reset when a new casino visit starts: status, place, Heat, what
## security recorded and every timer. Pocket, outfit, stash and IDs stay.
func begin_visit() -> void:
	status = HR.PlayerStatus.FREE
	status_seconds = 0.0
	zone = HR.ZoneType.ENTRANCE
	area_id = &""
	table_id = &""
	recorded_look = null
	reset_flags()
	last_table_id = &""
	seconds_since_left_table = -1.0
	last_game_area = &""
	seconds_since_area_change = INF
	seconds_unseen = INF
	poster_match_armed = true
	poster_armed = true
	id_question = {}
	id_check_guard = -1
	id_check_seconds = 0.0
	steal_cooldown = 0.0
	high_low = null
	blackjack = null
	round_table_id = &""
	heat.reset()


## Disconnects everything listening to this player's Heat and wallet, so the
## FloorSim of a finished visit stops hearing about them.
func release_listeners() -> void:
	for sig: Signal in [heat.changed, heat.level_changed, wallet.changed]:
		for c: Dictionary in sig.get_connections():
			sig.disconnect(c["callable"])


func stash_dicts() -> Array:
	var out: Array = []
	for o: Outfit in stash:
		out.append(o.to_dict())
	return out


func id_dicts() -> Array:
	var out: Array = []
	for id: FakeId in ids:
		out.append(id.to_dict())
	return out
