class_name MachineFactory
extends RefCounted
## Builds the physical machine for a game type: the script
## scripts/world/machines/<game>_machine.gd (the HR.GameType key in lower
## case: slots, high_low, big_wheel, dice, roulette, blackjack, ...) when it
## exists and extends GameMachine, else a TestMachine. Scripts are loaded by
## path at runtime, so a missing machine never breaks parsing.

const MACHINE_DIR := "res://scripts/world/machines/"


## "res://scripts/world/machines/slots_machine.gd" for SLOTS ("" if unknown).
static func script_path(game_type: int) -> String:
	var key: Variant = HR.GameType.find_key(game_type)
	if key == null:
		return ""
	return MACHINE_DIR + "%s_machine.gd" % String(key).to_lower()


## True when the game's own machine script is present.
static func has_machine(game_type: int) -> bool:
	var path := script_path(game_type)
	return path != "" and ResourceLoader.exists(path)


## A new (not set up) machine for `game_type`.
static func create(game_type: int) -> GameMachine:
	var path := script_path(game_type)
	if path != "" and ResourceLoader.exists(path):
		var script := load(path) as Script
		if script != null and script.can_instantiate():
			var inst: Object = script.new()
			if inst is GameMachine:
				return inst as GameMachine
			if inst is Node:
				(inst as Node).free()
			push_warning("MachineFactory: %s does not extend GameMachine" % path)
	return TestMachine.new()


## create() + setup() in one call.
static func build(game_type: int, table_id: StringName, area_id: StringName, rung: int, host: SimHost, local_pid: int) -> GameMachine:
	var m := create(game_type)
	m.setup(table_id, game_type, area_id, rung, host, local_pid)
	return m
