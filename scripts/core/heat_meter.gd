class_name HeatMeter
extends RefCounted
## One player's Heat, clamped to [0, Tuning.HEAT_MAX]. Host-owned.
##
## `changed` fires once per actual change, after `value` is updated.
## `level_changed` then fires once per level boundary crossed, in order and
## always between adjacent levels: a jump from 0 to 90 emits
## (UNNOTICED, WATCHED), (WATCHED, SUSPECTED), (SUSPECTED, WANTED). Listeners
## that read `value` or `level()` during these signals see the final value.

signal changed(value: float, delta: float, reason: StringName)
signal level_changed(old_level: int, new_level: int)

## Current Heat. Read-only by convention: change it through add/raise_to/reset.
var value: float = 0.0

## The level listeners were last told about through level_changed.
var _announced_level: int = HR.HeatLevel.UNNOTICED


func _init(initial: float = 0.0) -> void:
	value = 0.0 if is_nan(initial) else clampf(initial, 0.0, Tuning.HEAT_MAX)
	_announced_level = level_for(value)


## Adds a signed amount, clamped to [0, HEAT_MAX]. Returns the delta actually
## applied (0 when already at the limit). Emits only if the value changed.
func add(amount: float, reason: StringName) -> float:
	if is_nan(amount):
		return 0.0
	return _set_value(value + amount, reason)


## Raises Heat to at least `min_value` (clamped to HEAT_MAX); never lowers it.
## Returns the applied delta. E.g. a tackler goes straight to Wanted.
func raise_to(min_value: float, reason: StringName) -> float:
	if is_nan(min_value) or min_value <= value:
		return 0.0
	return _set_value(min_value, reason)


## Current HR.HeatLevel.
func level() -> int:
	return level_for(value)


## HR.HeatLevel for a Heat value; a level starts at its threshold (value >= threshold).
static func level_for(heat: float) -> int:
	if heat >= Tuning.WANTED_AT:
		return HR.HeatLevel.WANTED
	if heat >= Tuning.SUSPECTED_AT:
		return HR.HeatLevel.SUSPECTED
	if heat >= Tuning.WATCHED_AT:
		return HR.HeatLevel.WATCHED
	return HR.HeatLevel.UNNOTICED


## Display name for an HR.HeatLevel.
static func level_name(heat_level: int) -> String:
	match heat_level:
		HR.HeatLevel.UNNOTICED:
			return "Unnoticed"
		HR.HeatLevel.WATCHED:
			return "Watched"
		HR.HeatLevel.SUSPECTED:
			return "Suspected"
		HR.HeatLevel.WANTED:
			return "Wanted"
	return "Unknown"


## Back to 0 Heat (reason HeatRules.RESET). Emits like any other drop.
func reset() -> void:
	_set_value(0.0, HeatRules.RESET)


func _set_value(target: float, reason: StringName) -> float:
	var new_value: float = clampf(target, 0.0, Tuning.HEAT_MAX)
	if new_value == value:
		return 0.0
	var delta: float = new_value - value
	value = new_value
	changed.emit(value, delta, reason)
	_announce_level()
	return delta


## Steps level_changed from the last announced level to the current one.
## Re-reads `value` after every emit, so a listener that changes Heat from
## inside `changed` or `level_changed` still leaves an unbroken chain that ends
## on the real level.
func _announce_level() -> void:
	var target: int = level_for(value)
	while _announced_level != target:
		var old_level: int = _announced_level
		_announced_level += 1 if target > old_level else -1
		level_changed.emit(old_level, _announced_level)
		target = level_for(value)
