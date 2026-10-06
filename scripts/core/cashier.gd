class_name Cashier
extends RefCounted
## The cashier cage: turns pocket chips into banked chips (design doc "Scoring
## and progression"). Static functions only.
##
## The cashier asks for ID first. An ID that already fails its check (flagged
## or burned) is refused. A cash-out that pushes the ID past its cap still
## goes through, but the name is flagged so its next check fails. A large
## cash-out adds Heat (HeatRules.cash_out_heat); the caller applies that Heat
## with HeatRules.CASH_OUT and adds `banked` to RunState.add_bank.

## Reason on success.
const NO_REASON := &""
const BAD_ID := &"bad_id"
const NOT_ENOUGH := &"not_enough"
## Zero or negative amount requested.
const BAD_AMOUNT := &"bad_amount"


## Returns {ok: bool, reason: StringName, banked: int, heat: float, flagged: bool}.
## Checks in order: ID (bad_id), amount (bad_amount), pocket (not_enough).
## On failure nothing changes and banked/heat/flagged are 0/0.0/false.
static func cash_out(wallet: Wallet, id: FakeId, amount: int, max_bet: int) -> Dictionary:
	if id == null or not id.passes_check():
		return _fail(BAD_ID)
	if amount <= 0:
		return _fail(BAD_AMOUNT)
	if wallet == null or not wallet.bank_out(amount):
		return _fail(NOT_ENOUGH)
	var flagged: bool = id.record_banked(amount)
	return {
		"ok": true,
		"reason": NO_REASON,
		"banked": amount,
		"heat": HeatRules.cash_out_heat(amount, max_bet),
		"flagged": flagged,
	}


## Cashes out the whole pocket. An empty pocket fails with not_enough.
static func cash_out_all(wallet: Wallet, id: FakeId, max_bet: int) -> Dictionary:
	if id == null or not id.passes_check():
		return _fail(BAD_ID)
	var amount: int = wallet.pocket if wallet != null else 0
	if amount <= 0:
		return _fail(NOT_ENOUGH)
	return cash_out(wallet, id, amount, max_bet)


static func _fail(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": reason, "banked": 0, "heat": 0.0, "flagged": false}
