class_name TestMachine
extends GameMachine
## The generic stand-in machine: a rounded cabinet with a result screen and
## the bet console on its front. Plays any game type with GameMachine's
## default requests (high-low and blackjack get their action keys).
## MachineFactory falls back to it when a game's own machine is missing.

var cabinet: MeshInstance3D
var result_screen: Screen3D


func _build_game() -> void:
	var trim := accent
	cabinet = Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(1.25, 1.55, 0.7), 0.1, 3), DiegeticKit.CONSOLE_BODY)
	cabinet.name = "Cabinet"
	cabinet.position = Vector3(0.0, 0.775, -0.15)
	visuals.add_child(cabinet)
	var crown := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(1.32, 0.16, 0.76), 0.07, 3), trim)
	crown.name = "Crown"
	crown.position = Vector3(0.0, 1.62, -0.15)
	visuals.add_child(crown)
	var strip := ArtKit.mesh_instance(MeshFactory.pill(1.2, 0.018), ArtKit.neon_material(trim.lightened(0.2), 2.2))
	strip.name = "Neon"
	strip.position = Vector3(0.0, 1.5, 0.21)
	visuals.add_child(strip)
	result_screen = Screen3D.new()
	result_screen.name = "ResultScreen"
	result_screen.setup(Vector2(0.9, 0.42), 2, trim)
	result_screen.position = Vector3(0.0, 1.22, 0.205)
	visuals.add_child(result_screen)
	result_screen.set_lines([{"text": display_name.to_upper(), "color": DiegeticKit.TEXT_WHITE, "size": 0.07},
			{"text": "Wins pay %sx" % _mult(), "color": DiegeticKit.TEXT_MONEY, "size": 0.045}])
	set_footprint(Vector3(1.35, 1.7, 1.0), Vector3(0.0, 0.85, -0.05))
	set_play_spot(Vector3(0.0, 0.0, 1.25))
	set_label_height(2.25)
	pop_point = Vector3(0.0, 1.95, 0.3)
	match game_type:
		HR.GameType.HIGH_LOW:
			console.add_action_key(ACTION_HIGHER, "HIGHER", DiegeticKit.KEY_BLUE)
			console.add_action_key(ACTION_LOWER, "LOWER", DiegeticKit.KEY_PURPLE)
			console.add_action_key(ACTION_CASH_OUT, "CASH\nOUT", DiegeticKit.KEY_YELLOW)
		HR.GameType.BLACKJACK:
			console.add_action_key(ACTION_HIT, "HIT", DiegeticKit.KEY_RED)
			console.add_action_key(ACTION_STAND, "STAND", DiegeticKit.KEY_YELLOW)
	var s := minf(0.82, 1.3 / maxf(console.get_size().x, 0.01))
	place_console(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(0.0, 0.9, 0.45)))


func _on_hand(data: Dictionary) -> void:
	super(data)
	var state: Dictionary = data.get("state", {}) if data.get("state") is Dictionary else {}
	var text := _round_status(state)
	if text != "":
		result_screen.set_line(1, text, DiegeticKit.TEXT_INFO)


func _end_result(result: Dictionary) -> void:
	var tc := GameMachine.result_text(result)
	result_screen.set_line(1, str(tc[0]), tc[1])
	result_screen.flash(tc[1], 0.4)
	super(result)


func _mult() -> String:
	return ("%.1f" % (1.0 + TableGames.profit_multiple(game_type))).trim_suffix(".0")
