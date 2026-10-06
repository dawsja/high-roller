class_name TableGames
extends RefCounted
## Static facts about the six table games: their Tuning rows, the list of
## types, and the name each casino rung shows for them.

## Names in the bottom casinos, which reskin the set (design doc "Games").
const RESKIN_NAMES := {
	HR.GameType.SLOTS: "Coin Pusher",
	HR.GameType.HIGH_LOW: "Scratch Cards",
	HR.GameType.BIG_WHEEL: "Prize Wheel",
	HR.GameType.DICE: "Bingo",
	HR.GameType.ROULETTE: "Keno",
	HR.GameType.BLACKJACK: "Penny 21",
}


## A copy of Tuning.GAMES[game_type] plus a "type" key. Empty for an unknown type.
static func def(game_type: int) -> Dictionary:
	if not Tuning.GAMES.has(game_type):
		return {}
	var d: Dictionary = (Tuning.GAMES[game_type] as Dictionary).duplicate(true)
	d["type"] = game_type
	return d


static func all_types() -> Array[int]:
	var out: Array[int] = []
	for t: int in HR.GameType.values():
		out.append(t)
	return out


## The game's name on this rung; the bottom Tuning.TABLE_RESKIN_RUNGS rungs
## use the reskinned names (bingo, scratch cards, coin pusher, ...).
static func display_name(game_type: int, rung: int) -> String:
	if is_reskinned_rung(rung) and RESKIN_NAMES.has(game_type):
		return str(RESKIN_NAMES[game_type])
	return str(def(game_type).get("name", "Unknown"))


static func is_reskinned_rung(rung: int) -> bool:
	return rung > Tuning.BOTTOM_RUNG - Tuning.TABLE_RESKIN_RUNGS


## Profit multiple of a plain win at this game (before payout_bonus).
static func profit_multiple(game_type: int) -> float:
	return float(def(game_type).get("payout", 0.0))


static func is_loud(game_type: int) -> bool:
	return bool(def(game_type).get("loud", false))
