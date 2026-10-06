class_name CasinoLadder
extends RefCounted
## The six-casino ladder from Tuning.CASINOS (design doc "Casino ladder").
## Rung 1 (Tuning.TOP_RUNG) is The Apex; rung 6 (Tuning.BOTTOM_RUNG) is Sal's.
## Climbing means a smaller rung number. Static functions only.
##
## To leave a rung upward the crew spends the buy-in of the casino above it.
## Stretch rule: with Tuning.STRETCH_MULT times that buy-in banked, the crew
## skips a rung (two up) and pays the multiplied amount.


static func rung_count() -> int:
	return Tuning.CASINOS.size()


static func is_valid_rung(rung: int) -> bool:
	return rung >= Tuning.TOP_RUNG and rung <= Tuning.BOTTOM_RUNG


## A copy of the Tuning.CASINOS row for this rung. Empty for an invalid rung.
static func casino(rung: int) -> Dictionary:
	if not is_valid_rung(rung):
		return {}
	return (Tuning.CASINOS[rung - Tuning.TOP_RUNG] as Dictionary).duplicate(true)


## A copy of the casino row with this id. Empty if no casino has it.
static func by_id(id: StringName) -> Dictionary:
	var rung := rung_of(id)
	return casino(rung) if rung > 0 else {}


## The rung of the casino with this id, or -1.
static func rung_of(id: StringName) -> int:
	for row: Dictionary in Tuning.CASINOS:
		if StringName(row["id"]) == id:
			return int(row["rung"])
	return -1


static func casino_id(rung: int) -> StringName:
	return StringName(casino(rung).get("id", &""))


## What the crew must bank on this rung to climb one rung: the buy-in of the
## casino above. 0 at the top (and for an invalid rung): there is no climb.
static func buy_in_to_leave(rung: int) -> int:
	if not is_valid_rung(rung) or rung <= Tuning.TOP_RUNG:
		return 0
	return int(casino(rung - 1)["buy_in"])


## Where `banked` chips can take the crew from `rung`: two rungs up with the
## stretch amount (if that stays on the ladder), one rung up with the buy-in,
## otherwise `rung` itself. Always `rung` at the top.
static func climb_target(rung: int, banked: int) -> int:
	if not is_valid_rung(rung) or rung <= Tuning.TOP_RUNG:
		return rung
	var buy_in := buy_in_to_leave(rung)
	if banked >= Tuning.STRETCH_MULT * buy_in and rung - 2 >= Tuning.TOP_RUNG:
		return rung - 2
	if banked >= buy_in:
		return rung - 1
	return rung


## Chips a climb from `rung` to `target` costs: the buy-in for one rung, the
## stretch amount (STRETCH_MULT x buy-in) for two. 0 for anything that isn't
## a legal one- or two-rung climb (including target == rung).
static func climb_cost(rung: int, target: int) -> int:
	if not is_valid_rung(rung) or not is_valid_rung(target):
		return 0
	var buy_in := buy_in_to_leave(rung)
	if target == rung - 1:
		return buy_in
	if target == rung - 2:
		return Tuning.STRETCH_MULT * buy_in
	return 0


## The rung a throw-out sends the crew to: one down, never below the bottom.
static func drop_target(rung: int) -> int:
	return clampi(rung + 1, Tuning.TOP_RUNG, Tuning.BOTTOM_RUNG)


static func is_top(rung: int) -> bool:
	return rung == Tuning.TOP_RUNG


static func is_bottom(rung: int) -> bool:
	return rung == Tuning.BOTTOM_RUNG
