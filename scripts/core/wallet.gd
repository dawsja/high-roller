class_name Wallet
extends RefCounted
## One player's chips. `pocket` is what they carry on the floor (lost when they
## are caught); `lifetime_banked` counts every chip they ever cashed out, for
## cosmetic unlocks. Banked chips themselves live in RunState. Host-owned.
##
## Amounts are whole chips. Non-positive amounts are ignored by `add` and
## refused by `spend` / `give_to` / `bank_out`, so the pocket never goes negative.

## Fires after every change to `pocket`, with the signed change.
signal changed(pocket: int, delta: int)

var pocket: int = 0
var lifetime_banked: int = 0


func _init(start_pocket: int = 0) -> void:
	pocket = maxi(start_pocket, 0)


func add(amount: int) -> void:
	if amount <= 0:
		return
	_change(amount)


func can_afford(amount: int) -> bool:
	return amount >= 0 and amount <= pocket


## Takes `amount` out of the pocket. False (and no change) if it is short or
## the amount is negative. Spending 0 always succeeds.
func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	if amount > 0:
		_change(-amount)
	return true


## Empties the pocket (caught and carried to the back room). Returns the chips lost.
func lose_pocket() -> int:
	var lost := pocket
	if lost > 0:
		_change(-lost)
	return lost


## Hands chips to a teammate so the hottest player is never the one carrying.
## False for a null or same wallet, a non-positive amount, or a short pocket.
func give_to(other: Wallet, amount: int) -> bool:
	if other == null or other == self or amount <= 0 or amount > pocket:
		return false
	_change(-amount)
	other.add(amount)
	return true


## Moves chips from the pocket into `lifetime_banked` (a cash-out). Cashier
## calls this after checking the ID; it does not check anything else.
func bank_out(amount: int) -> bool:
	if amount <= 0 or amount > pocket:
		return false
	lifetime_banked += amount
	_change(-amount)
	return true


func to_dict() -> Dictionary:
	return {"pocket": pocket, "lifetime_banked": lifetime_banked}


func _change(delta: int) -> void:
	pocket += delta
	changed.emit(pocket, delta)
