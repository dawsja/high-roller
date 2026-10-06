class_name BetResult
extends RefCounted
## The host's outcome for one bet. `detail` tells the table what to animate so
## the shown result matches `won`.

var pid: int = 0
var table_id: StringName = &""
var game_type: int = 0
var bet: int = 0
var won: bool = false
## Chips returned to the pocket (bet + profit on a win, 0 on a loss).
var payout: int = 0
## payout - bet.
var net: int = 0
## Signed: win Heat on a win, Tuning.LOSE_ON_PURPOSE_HEAT on a thrown loss, 0 on an honest loss.
var heat: float = 0.0
## The player's win streak at the table after this bet (0 after a loss).
var streak: int = 0
var intentional_loss: bool = false
var loud: bool = false
var jackpot: bool = false
var detail: Dictionary = {}


func to_dict() -> Dictionary:
	return {
		"pid": pid,
		"table_id": table_id,
		"game_type": game_type,
		"bet": bet,
		"won": won,
		"payout": payout,
		"net": net,
		"heat": heat,
		"streak": streak,
		"intentional_loss": intentional_loss,
		"loud": loud,
		"jackpot": jackpot,
		"detail": detail.duplicate(true),
	}


static func from_dict(d: Dictionary) -> BetResult:
	var r := BetResult.new()
	r.pid = int(d.get("pid", 0))
	r.table_id = StringName(str(d.get("table_id", "")))
	r.game_type = int(d.get("game_type", 0))
	r.bet = int(d.get("bet", 0))
	r.won = bool(d.get("won", false))
	r.payout = int(d.get("payout", 0))
	r.net = int(d.get("net", 0))
	r.heat = float(d.get("heat", 0.0))
	r.streak = int(d.get("streak", 0))
	r.intentional_loss = bool(d.get("intentional_loss", false))
	r.loud = bool(d.get("loud", false))
	r.jackpot = bool(d.get("jackpot", false))
	var det: Variant = d.get("detail", {})
	r.detail = (det as Dictionary).duplicate(true) if det is Dictionary else {}
	return r
