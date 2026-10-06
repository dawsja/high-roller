class_name RouletteMachine
extends GameMachine
## Roulette (refs: toon roulette wheel, roulette board). A long table with a
## toon wheel on the left and a big felt betting board (RouletteBoard) on the
## right. Click a cell to put your chip there: one bet, a color or a single
## number, as the sim takes it; clicking another cell moves it, RESET BETS
## takes it back, and the fat green PLAY key on the rail spins.
##
## Every peer plays the spin from the host's &"bet" event: the chip lands on
## the bet's cell, the dealer behind the wheel flicks it, the rotor (real
## European pocket order and colors) spins up, the white ball orbits the
## track the other way, drops, rattles between pockets and settles in
## detail.number's pocket, then rides the rotor. The winning cell glows, the
## monitor shows the number and WIN / LOSE, chips pay out or get swept.
##
## Machine space: floor at y = 0, the player stands at +Z facing -Z.

const WHEEL_ORDER: Array[int] = [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const POCKET_STEP := TAU / 37.0
const TABLE_TOP := 0.86
const TABLE_SIZE := Vector3(3.5, 0.07, 1.2)
const WHEEL_C := Vector3(-1.08, TABLE_TOP, -0.06)
const BOARD_C := Vector3(0.28, TABLE_TOP + 0.006, -0.08)
const RESET_ID := &"reset"
# Wheel profile (wheel space: y = 0 at the table top).
const RIM_R := 0.535
const TRACK_OUTER_R := 0.475
const TRACK_INNER_R := 0.39
const TRACK_OUTER_Y := 0.078
const TRACK_INNER_Y := 0.044
const NUMBER_R0 := 0.3
const NUMBER_R1 := 0.385
const NUMBER_Y := 0.047
const POCKET_R0 := 0.21
const POCKET_Y := 0.022
const TRACK_R := 0.44
const POCKET_R := 0.255
const BALL_R := 0.019
const IDLE_ROTOR_SPEED := 0.35
const SPIN_ROTOR_SPEED := 2.6
const SPIN_SECONDS := 5.0
const REVEAL_SECONDS := 1.7
const BALL_TURNS := 4
const WOOD := Color("7a3b1f")
const WOOD_DARK := Color("4a2213")
const TRACK_COLOR := Color("f1d9a8")
const GOLD := Color("ffc23d")
const RAIL_COLOR := Color("5a1f4f")

## Divides every animation length (tests speed it up).
var anim_speed: float = 1.0
## The local player's bet cell (&"" = none): RouletteBoard ids.
var selected: StringName = &""
var board: RouletteBoard
var wheel: Node3D
var rotor: Node3D
var ball: MeshInstance3D
var reset_key: KeyButton3D
var key_pod: Node3D
var monitor: MonitorOnStand
## The number the last spin landed on (-1 before any).
var last_number: int = -1
var quick_keys: Dictionary = {}

var _rotor_speed: float = IDLE_ROTOR_SPEED
var _spin_tween: Tween
var _speed_tween: Tween
var _rel0: float = 0.0
var _rel1: float = 0.0
var _spin_number: int = 0
var _spinning: bool = false


func _build_game() -> void:
	console.setup("PLAY", DiegeticKit.KEY_GREEN, 32.0)
	_build_table()
	_build_wheel()
	board = RouletteBoard.new()
	board.setup()
	board.position = BOARD_C
	visuals.add_child(board)
	board.cell_pressed.connect(_on_cell)
	for id: StringName in board.cells:
		register_pressable(id, board.cells[id])
	_build_keys()
	monitor = add_monitor(Transform3D(Basis(Vector3.UP, -0.1), Vector3(0.35, 0.0, -0.92)), Vector2(0.92, 0.5), 1.62, 3)
	_show_odds()
	spawn_dealer(Vector3(WHEEL_C.x, 0.0, -0.98), PI)
	set_footprint(Vector3(TABLE_SIZE.x + 0.1, 1.0, TABLE_SIZE.z + 0.1), Vector3(0.0, 0.5, -0.05))
	set_play_spot(Vector3(0.12, 0.0, 1.02))
	set_label_height(2.55)
	pop_point = Vector3(0.0, 2.05, -0.1)
	console.bet_changed.connect(_on_bet_changed)


## Machine-space point of a cell id's top (aim point outside the tree).
func _aim_point_extra(id: StringName) -> Vector3:
	if board != null and board.get_cell(id) != null:
		return board.get_cell(id).aim_point()
	return super(id)


## The pocket the ball sits in (or is over) right now.
func number_at_ball() -> int:
	var a := _ball_angle() - rotor.rotation.y
	var k := posmod(roundi(fposmod(a, TAU) / POCKET_STEP), WHEEL_ORDER.size())
	return WHEEL_ORDER[k]


## True once the ball rests in a pocket and rides the rotor.
func ball_on_rotor() -> bool:
	return ball != null and ball.get_parent() == rotor


func is_spinning() -> bool:
	return _spinning


## Snaps a running spin to its end (tests, a new spin).
func finish_spin() -> void:
	if _spin_tween != null and _spin_tween.is_valid():
		_spin_tween.custom_step(1000.0)
		if _spin_tween != null and _spin_tween.is_valid():
			_spin_tween.kill()


# --- GameMachine overrides --------------------------------------------------------

func _on_main(bet: int, throw: bool, pid: int) -> void:
	if selected == &"":
		if throw:
			console.set_throw(true)
		console.show_message("Pick a number or color!", DiegeticKit.TEXT_WARN)
		console.main_key.play_nope()
		_nudge_board()
		return
	var choice := RouletteBoard.choice_for(selected)
	choice["throw"] = throw
	board.set_chip_amount(bet)
	request_bet(pid, bet, choice)


func _on_bet(data: Dictionary) -> void:
	var result: Dictionary = data.get("result", {}) if data.get("result") is Dictionary else {}
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	var id := RouletteBoard.id_for_choice(detail)
	if int(result.get("pid", 0)) == local_pid and id != &"":
		selected = id
	if id != &"":
		board.place_chip(id, int(result.get("bet", 0)), board.chip_cell != id)
	_spin(result)


func _on_request_result(_request: StringName, _args: Array, result: Dictionary) -> void:
	if not bool(result.get("ok", false)) and not _spinning:
		_restore_chip()


func _on_occupants_changed() -> void:
	if not occupants.has(local_pid) and selected != &"" and not _spinning:
		selected = &""
		board.clear_chip()
		_show_odds()


func _on_closed_changed(value: bool) -> void:
	if board != null:
		board.set_cells_enabled(not value)


func _process(delta: float) -> void:
	super(delta)
	if rotor != null:
		rotor.rotation.y = fposmod(rotor.rotation.y + _rotor_speed * delta, TAU)


# --- Presses --------------------------------------------------------------------

func _on_cell(id: StringName, pid: int) -> void:
	var cell := board.get_cell(id)
	if not _press_ok(pid, cell):
		return
	selected = id
	board.place_chip(id, console.get_bet())
	console.show_message("Bet on %s · pays %sx" % [RouletteBoard.cell_text(id), _mult_text(id)], DiegeticKit.TEXT_MONEY)
	_show_odds()


func _on_reset(pid: int) -> void:
	if not _press_ok(pid, reset_key):
		return
	selected = &""
	board.clear_chip()
	console.show_message("Bets cleared", DiegeticKit.TEXT_INFO)
	_show_odds()


func _on_bet_changed(bet: int) -> void:
	if selected != &"" and not _spinning and board.chip_cell == selected:
		board.set_chip_amount(bet)


## The console's rules for a key that isn't on it: ignored while locked,
## refused (with the reason on the screen) for anyone but the occupant.
func _press_ok(pid: int, key: Node) -> bool:
	if console.is_locked():
		if key is KeyButton3D:
			(key as KeyButton3D).play_nope()
		return false
	var why := _gate(pid)
	if why != "":
		if key is KeyButton3D:
			(key as KeyButton3D).play_nope()
		console.show_message(why, DiegeticKit.TEXT_WARN)
		console.refused.emit(pid, why)
		return false
	return true


func _on_fraction_key(pid: int, id: StringName, key: KeyButton3D) -> void:
	if not _press_ok(pid, key):
		return
	console.key_pressed.emit(id, pid)
	console.set_bet(maxi(console.min_bet, int(float(console.cap()) * (0.25 if id == &"quarter" else 0.5))))


# --- The spin ---------------------------------------------------------------------

func _spin(result: Dictionary) -> void:
	finish_spin()
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	_spin_number = clampi(int(detail.get("number", 0)), 0, GameResolver.ROULETTE_MAX_NUMBER)
	board.clear_winner()
	if ball.get_parent() != wheel:
		ball.reparent(wheel, true)
	var psi := float(WHEEL_ORDER.find(_spin_number)) * POCKET_STEP
	_rel0 = _ball_angle() - rotor.rotation.y
	_rel1 = _rel0 - (float(BALL_TURNS) * TAU + fposmod(_rel0 - psi, TAU))
	_spinning = true
	_set_lines([{"text": "NO MORE BETS", "color": DiegeticKit.TEXT_WHITE, "size": 0.085},
			{"text": "Bet: %s · %sx" % [_bet_text(detail), _mult_text(RouletteBoard.id_for_choice(detail))], "color": DiegeticKit.TEXT_MONEY, "size": 0.05},
			{"text": "Spinning...", "color": DiegeticKit.TEXT_INFO, "size": 0.045}])
	_dealer_pose(&"wave", 0.9)
	if not is_inside_tree():
		_ball_step(1.0)
		_landed(result)
		_end_result(result)
		return
	var seconds := SPIN_SECONDS / maxf(anim_speed, 0.01)
	_kill(_speed_tween)
	_rotor_speed = SPIN_ROTOR_SPEED
	_speed_tween = create_tween()
	_speed_tween.tween_property(self, "_rotor_speed", IDLE_ROTOR_SPEED, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_spin_tween = create_tween()
	_spin_tween.tween_method(_ball_step, 0.0, 1.0, seconds)
	_spin_tween.tween_callback(_landed.bind(result))
	_spin_tween.tween_interval(REVEAL_SECONDS / maxf(anim_speed, 0.01))
	_spin_tween.tween_callback(_end_result.bind(result))


## Ball position for spin progress t (0..1): orbit on the track, spiral down,
## rattle across a few pockets with shrinking hops, rest in the pocket.
func _ball_step(t: float) -> void:
	var base := lerpf(_rel0, _rel1, 1.0 - pow(1.0 - clampf(t / 0.9, 0.0, 1.0), 2.4))
	var wobble := 0.0
	var hop := 0.0
	if t > 0.58:
		var u := clampf((t - 0.58) / 0.42, 0.0, 1.0)
		var damp := pow(1.0 - u, 1.7)
		wobble = POCKET_STEP * 1.8 * sin(u * PI * 3.5) * damp
		hop = 0.045 * absf(sin(u * PI * 4.0)) * damp
	var r := lerpf(TRACK_R, POCKET_R, smoothstep(0.48, 0.8, t))
	var a := rotor.rotation.y + base + wobble
	ball.position = Vector3(sin(a) * r, _surface_y(r) + BALL_R + hop, cos(a) * r)


func _landed(result: Dictionary) -> void:
	var psi := float(WHEEL_ORDER.find(_spin_number)) * POCKET_STEP
	ball.reparent(rotor, false)
	ball.position = Vector3(sin(psi) * POCKET_R, POCKET_Y + BALL_R, cos(psi) * POCKET_R)
	last_number = _spin_number
	_spinning = false
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	var won := bool(result.get("won", false))
	var color := str(detail.get("color", GameResolver.roulette_color(_spin_number)))
	board.set_winner(RouletteBoard.id_for_number(_spin_number))
	var tc := GameMachine.result_text(result)
	var number_color := RouletteBoard.number_color(_spin_number)
	_set_lines([{"text": "%d %s" % [_spin_number, color.to_upper()], "color": number_color.lightened(0.25) if color != "black" else DiegeticKit.TEXT_WHITE, "size": 0.1},
			{"text": str(tc[0]), "color": tc[1], "size": 0.075},
			{"text": "Bet: %s · %sx" % [_bet_text(detail), _mult_text(RouletteBoard.id_for_choice(detail))], "color": DiegeticKit.TEXT_MONEY, "size": 0.04}])
	monitor.screen.flash(tc[1], 0.6, 0.5)
	var number_bet := str(detail.get("kind", "")) == "number"
	if won:
		board.set_chip_amount(int(result.get("payout", 0)), true)
		_burst(BOARD_C + board.cell_center(board.chip_cell) + Vector3(0.0, 0.1, 0.0), number_bet)
		_dealer_pose(&"shrug", 1.4)
		_send_chips_later(BOARD_C + Vector3(-0.35, 0.0, 0.5))
	else:
		flash(DiegeticKit.TEXT_LOSE, 1.6, 0.5)
		_send_chips_later(Vector3(WHEEL_C.x + 0.3, TABLE_TOP, -0.5))


func _send_chips_later(to_machine: Vector3) -> void:
	if not is_inside_tree():
		board.send_chip(to_machine - BOARD_C)
		return
	var tw := create_tween()
	tw.tween_interval(0.7 / maxf(anim_speed, 0.01))
	tw.tween_callback(board.send_chip.bind(to_machine - BOARD_C, 0.45 / maxf(anim_speed, 0.01)))


func _end_result(result: Dictionary) -> void:
	super(result)
	_restore_chip()


## After a round the local player's bet stays on its cell (bet again with PLAY).
func _restore_chip() -> void:
	if selected != &"" and occupants.has(local_pid):
		board.place_chip(selected, console.get_bet(), true)
	_show_odds_later()


func _show_odds_later() -> void:
	if not is_inside_tree():
		_show_odds()
		return
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func() -> void:
		if not _spinning:
			_show_odds())


# --- Look -----------------------------------------------------------------------

func _show_odds() -> void:
	if monitor == null:
		return
	if selected == &"":
		_set_lines([{"text": "PLACE YOUR BET", "color": DiegeticKit.TEXT_WHITE, "size": 0.08},
				{"text": "Color pays %sx · Number pays %sx" % [_mult_text(&"red"), _mult_text(&"n1")], "color": DiegeticKit.TEXT_MONEY, "size": 0.05},
				{"text": "Click the felt, then PLAY", "color": DiegeticKit.TEXT_INFO, "size": 0.04}])
		return
	var number: bool = RouletteBoard.choice_for(selected).get("kind", "") == "number"
	var heat_class: int = Tuning.ROULETTE_NUMBER_HEAT_CLASS if number else int(TableGames.def(HR.GameType.ROULETTE).get("heat_class", HR.HeatClass.MEDIUM))
	_set_lines([{"text": "%s PAYS %sx" % [RouletteBoard.cell_text(selected), _mult_text(selected)], "color": DiegeticKit.TEXT_MONEY, "size": 0.085},
			{"text": "HEAT: %s" % _heat_name(heat_class), "color": DiegeticKit.TEXT_LOSE if number else DiegeticKit.TEXT_WARN, "size": 0.06},
			{"text": "Big payout, big attention!" if number else "Press PLAY to spin", "color": DiegeticKit.TEXT_INFO, "size": 0.04}])


func _set_lines(entries: Array) -> void:
	if monitor != null:
		monitor.set_lines(entries)


func _build_table() -> void:
	var body_mesh := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(TABLE_SIZE.x - 0.25, TABLE_TOP - 0.1, TABLE_SIZE.z - 0.3), 0.08, 3), WOOD_DARK)
	body_mesh.name = "Base"
	body_mesh.position = Vector3(0.0, (TABLE_TOP - 0.1) * 0.5, -0.05)
	visuals.add_child(body_mesh)
	var top := Primitives.mesh_instance(MeshFactory.rounded_box(TABLE_SIZE, 0.035, 3), WOOD)
	top.name = "Top"
	top.position = Vector3(0.0, TABLE_TOP - TABLE_SIZE.y * 0.5, -0.05)
	visuals.add_child(top)
	var felt_size := Vector3(TABLE_SIZE.x - 0.12, 0.012, TABLE_SIZE.z - 0.16)
	var felt := ArtKit.mesh_instance(MeshFactory.rounded_box(felt_size, 0.005, 1),
			ArtKit.felt_material(ArtPalette.FELT_GREEN, GOLD, Vector2(felt_size.x, felt_size.z) * 0.5, 0.1))
	felt.name = "Felt"
	felt.position = Vector3(0.0, TABLE_TOP + 0.001, -0.05)
	visuals.add_child(felt)
	var rail := Primitives.pill(TABLE_SIZE.x - 0.05, 0.05, RAIL_COLOR)
	rail.name = "Rail"
	rail.position = Vector3(0.0, TABLE_TOP + 0.015, -0.05 + TABLE_SIZE.z * 0.5 + 0.01)
	visuals.add_child(rail)
	var neon := ArtKit.mesh_instance(MeshFactory.stroke(_rect_points(Vector2(TABLE_SIZE.x - 0.04, TABLE_SIZE.z - 0.04)), 0.018, 0.012),
			ArtKit.neon_material(accent.lightened(0.15), 2.2))
	neon.name = "Neon"
	neon.rotation.x = -PI * 0.5
	neon.position = Vector3(0.0, TABLE_TOP - TABLE_SIZE.y - 0.008, -0.05)
	visuals.add_child(neon)
	var plaque := DiegeticKit.text_label("BET ON A NUMBER OR A COLOR", 0.045, Color("ffe08a"), 8)
	plaque.name = "Plaque"
	plaque.rotation.x = -PI * 0.5
	plaque.position = BOARD_C + Vector3(0.0, 0.004, -RouletteBoard.DEPTH * 0.5 - 0.075)
	visuals.add_child(plaque)


func _build_wheel() -> void:
	wheel = Node3D.new()
	wheel.name = "Wheel"
	wheel.position = WHEEL_C
	visuals.add_child(wheel)
	var bowl := Primitives.mesh_instance(MeshFactory.lathe(PackedVector2Array([
		Vector2(0.0, -0.09), Vector2(RIM_R - 0.04, -0.09), Vector2(RIM_R, -0.055), Vector2(RIM_R, 0.06),
		Vector2(RIM_R - 0.018, 0.094), Vector2(TRACK_OUTER_R + 0.012, 0.094), Vector2(TRACK_OUTER_R, TRACK_OUTER_Y),
	]), 48), WOOD)
	bowl.name = "Bowl"
	wheel.add_child(bowl)
	var track := Primitives.mesh_instance(MeshFactory.lathe(PackedVector2Array([
		Vector2(TRACK_OUTER_R, TRACK_OUTER_Y), Vector2(TRACK_INNER_R, TRACK_INNER_Y),
		Vector2(TRACK_INNER_R - 0.004, 0.02), Vector2(0.0, 0.02),
	]), 48, false), TRACK_COLOR, 0.0, false)
	track.name = "Track"
	wheel.add_child(track)
	var gold_mat := ArtKit.toon_material(GOLD, 0.25, false, false, 0.5)
	var deflectors: Array[Transform3D] = []
	for i in 8:
		var a := TAU * float(i) / 8.0 + POCKET_STEP * 0.5
		var r := (TRACK_INNER_R + TRACK_OUTER_R) * 0.5 - 0.012
		var y := lerpf(TRACK_INNER_Y, TRACK_OUTER_Y, (r - TRACK_INNER_R) / (TRACK_OUTER_R - TRACK_INNER_R)) + 0.006
		deflectors.append(Transform3D(Basis.from_euler(Vector3(-0.35, a, 0.0)), Vector3(sin(a) * r, y, cos(a) * r)))
	wheel.add_child(_multi("Deflectors", MeshFactory.rounded_box(Vector3(0.022, 0.014, 0.034), 0.006, 1), gold_mat, deflectors))
	rotor = Node3D.new()
	rotor.name = "Rotor"
	wheel.add_child(rotor)
	var ring := ArtKit.mesh_instance(_pocket_ring_mesh(), ArtKit.toon_material(Color.WHITE, 0.0, false, false, 0.35, true))
	ring.name = "Pockets"
	rotor.add_child(ring)
	var frets: Array[Transform3D] = []
	for k in WHEEL_ORDER.size():
		var a := (float(k) + 0.5) * POCKET_STEP
		var mid := (NUMBER_R0 + POCKET_R0) * 0.5
		frets.append(Transform3D(Basis(Vector3.UP, a), Vector3(sin(a) * mid, POCKET_Y + 0.015, cos(a) * mid)))
	rotor.add_child(_multi("Frets", MeshFactory.rounded_box(Vector3(0.007, 0.03, NUMBER_R0 - POCKET_R0), 0.003, 1),
			ArtKit.toon_material(Color("e0a92e"), 0.1, false, false, 0.5), frets))
	for k in WHEEL_ORDER.size():
		var n: int = WHEEL_ORDER[k]
		var a := float(k) * POCKET_STEP
		var l := DiegeticKit.text_label(str(n), 0.026, DiegeticKit.TEXT_WHITE, 0)
		l.name = "N%d" % n
		l.basis = Basis(Vector3.UP, a + PI) * Basis(Vector3.RIGHT, -PI * 0.5)
		var r := (NUMBER_R0 + NUMBER_R1) * 0.5 + 0.004
		l.position = Vector3(sin(a) * r, NUMBER_Y + 0.0015, cos(a) * r)
		l.visibility_range_end = 12.0
		rotor.add_child(l)
	var cone := Primitives.mesh_instance(MeshFactory.lathe(PackedVector2Array([
		Vector2(POCKET_R0 + 0.002, POCKET_Y), Vector2(0.19, 0.045), Vector2(0.12, 0.074), Vector2(0.05, 0.09), Vector2(0.0, 0.094),
	]), 40), WOOD)
	cone.name = "Cone"
	rotor.add_child(cone)
	var turret := Primitives.mesh_instance(MeshFactory.lathe(PackedVector2Array([
		Vector2(0.0, 0.088), Vector2(0.05, 0.095), Vector2(0.055, 0.12), Vector2(0.03, 0.15), Vector2(0.016, 0.2),
		Vector2(0.036, 0.235), Vector2(0.03, 0.27), Vector2(0.0, 0.285),
	]), 24), Color("ff9a3d"), 0.1)
	turret.name = "Turret"
	rotor.add_child(turret)
	var arms: Array[Transform3D] = []
	var knobs: Array[Transform3D] = []
	for i in 4:
		var a := TAU * float(i) / 4.0
		arms.append(Transform3D(Basis(Vector3.UP, a + PI * 0.5), Vector3(sin(a) * 0.075, 0.16, cos(a) * 0.075)))
		knobs.append(Transform3D(Basis.IDENTITY, Vector3(sin(a) * 0.15, 0.16, cos(a) * 0.15)))
	var arm_mat := ArtKit.toon_material(GOLD, 0.2)
	var arm_mi := _multi("Arms", MeshFactory.pill(0.15, 0.011), arm_mat, arms)
	rotor.add_child(arm_mi)
	rotor.add_child(_multi("Knobs", MeshFactory.ball(0.022, 3), arm_mat, knobs))
	ball = Primitives.mesh_instance(MeshFactory.ball(BALL_R, 3), Color("fffdf6"), 0.35)
	ball.name = "Ball"
	rotor.add_child(ball)
	ball.position = Vector3(0.0, POCKET_Y + BALL_R, POCKET_R)


func _build_keys() -> void:
	key_pod = Node3D.new()
	key_pod.name = "KeyPod"
	key_pod.position = Vector3(-0.12, TABLE_TOP + 0.005, 0.36)
	key_pod.rotation.x = deg_to_rad(14.0)
	visuals.add_child(key_pod)
	var pod := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(0.6, 0.05, 0.23), 0.03, 3), DiegeticKit.CONSOLE_BODY)
	pod.name = "Body"
	pod.position.y = 0.025
	key_pod.add_child(pod)
	var trim := ArtKit.mesh_instance(MeshFactory.stroke(_rect_points(Vector2(0.58, 0.21)), 0.008, 0.006), ArtKit.neon_material(DiegeticKit.NEON_TRIM, 2.0))
	trim.rotation.x = -PI * 0.5
	trim.position.y = 0.051
	key_pod.add_child(trim)
	var main := _rework_console(key_pod, Vector3(-0.12, 0.05, 0.0), Vector3(0.27, 0.06, 0.18))
	main.set_legend("PLAY")
	reset_key = KeyButton3D.new()
	reset_key.setup("RESET\nBETS", DiegeticKit.KEY_RED, Vector3(0.2, 0.05, 0.16), RESET_ID)
	reset_key.set_emission(0.12)
	reset_key.position = Vector3(0.155, 0.05, 0.0)
	reset_key.pressed.connect(_on_reset)
	key_pod.add_child(reset_key)
	register_pressable(RESET_ID, reset_key)
	var s := 0.64
	place_console(Transform3D(Basis(Vector3.UP, deg_to_rad(-30.0)).scaled(Vector3.ONE * s), Vector3(1.36, TABLE_TOP, 0.06)))


## The kit console reworked to the console-on-a-stand reference: the main key
## leaves the panel for `main_parent` (the table rail) at `main_pos`; the
## quick column becomes MIN ¼ ½ ALL (¼ and ½ of all you can bet now, ALL =
## all of it up to the max); THROW fills the slot the main key left.
## Returns the main key. (The kit console has MIN ½ ×2 MAX; see open issues.)
func _rework_console(main_parent: Node3D, main_pos: Vector3, main_size: Vector3) -> KeyButton3D:
	var main := console.main_key
	var slot := main.position
	main.get_parent().remove_child(main)
	main_parent.add_child(main)
	main.setup(console.main_label, DiegeticKit.KEY_GREEN, main_size, &"main")
	main.set_emission(0.15)
	main.position = main_pos
	var tk := console.throw_key
	tk.setup("THROW", DiegeticKit.KEY_RED, Vector3(0.15, 0.04, 0.17), &"throw")
	tk.position = slot
	var column_x: float = (console.quick_keys[&"min"] as KeyButton3D).position.x
	var top: float = (console.quick_keys[&"min"] as KeyButton3D).position.y
	var depth := console.keypad.get_size().y
	var size := Vector3(BetConsole3D.QUICK_SIZE.x, 0.032, depth / 4.0 - 0.016)
	for hidden: StringName in [&"half", &"double"]:
		var k: KeyButton3D = console.quick_keys[hidden]
		k.enabled = false
		k.visible = false
		k.collision_layer = 0
	var column: Array[KeyButton3D] = []
	var min_key: KeyButton3D = console.quick_keys[&"min"]
	min_key.setup("MIN", DiegeticKit.KEY_ORANGE, size, &"min")
	column.append(min_key)
	for id: StringName in [&"quarter", &"half"]:
		var k := KeyButton3D.new()
		k.setup("¼" if id == &"quarter" else "½", DiegeticKit.KEY_ORANGE, size, id)
		k.set_emission(0.18)
		k.pressed.connect(_on_fraction_key.bind(id, k))
		console.deck.add_child(k)
		register_pressable(id, k)
		quick_keys[id] = k
		column.append(k)
	var all_key: KeyButton3D = console.quick_keys[&"max"]
	all_key.setup("ALL", DiegeticKit.KEY_ORANGE, size, &"max")
	register_pressable(&"all", all_key)
	column.append(all_key)
	for i in column.size():
		column[i].position = Vector3(column_x, top, (float(i) - 1.5) * depth / 4.0)
	return main


## A small "look here" bounce of the board (PLAY with no bet).
func _nudge_board() -> void:
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(board, "position:y", BOARD_C.y + 0.025, 0.08)
	tw.tween_property(board, "position:y", BOARD_C.y, 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _dealer_pose(pose: StringName, seconds: float) -> void:
	if dealer == null or not is_instance_valid(dealer):
		return
	dealer.set_pose(pose)
	if not is_inside_tree():
		return
	var d := dealer
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func() -> void:
		if is_instance_valid(d) and d.pose == pose:
			d.set_pose(&"idle"))


## Confetti (and a chip fountain on big wins) at `at` (machine space).
func _burst(at: Vector3, big: bool) -> void:
	flash(DiegeticKit.TEXT_WIN, 4.5 if big else 2.5, 0.8)
	if not is_inside_tree():
		return
	var p := CPUParticles3D.new()
	p.name = "Confetti"
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = 110 if big else 60
	p.lifetime = 1.8
	p.mesh = MeshFactory.quad(Vector2(0.03, 0.02))
	p.material_override = _confetti_material()
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 3.8 if big else 3.0
	p.gravity = Vector3(0.0, -4.0, 0.0)
	p.damping_min = 0.6
	p.damping_max = 1.4
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([ArtPalette.NEON_MAGENTA, ArtPalette.NEON_CYAN, ArtPalette.NEON_LIME, ArtPalette.NEON_SUNFLOWER, ArtPalette.NEON_ORANGE, Color.WHITE])
	p.color_initial_ramp = g
	p.position = at
	visuals.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


static var _confetti_mat: StandardMaterial3D


static func _confetti_material() -> StandardMaterial3D:
	if _confetti_mat == null:
		_confetti_mat = StandardMaterial3D.new()
		_confetti_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_confetti_mat.vertex_color_use_as_albedo = true
		_confetti_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _confetti_mat


func _multi(node_name: String, mesh: Mesh, material: Material, xforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = material
	return mmi


## The wheel's pocket ring: per pocket a colored number band and a darker
## pocket floor (vertex colors, one draw call).
static func _pocket_ring_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var sub := 3
	for k in WHEEL_ORDER.size():
		var c := RouletteBoard.number_color(WHEEL_ORDER[k])
		var floor_c := c.darkened(0.3)
		for s in sub:
			var a0 := (float(k) - 0.5 + float(s) / float(sub)) * POCKET_STEP
			var a1 := (float(k) - 0.5 + float(s + 1) / float(sub)) * POCKET_STEP
			var d0 := Vector3(sin(a0), 0.0, cos(a0))
			var d1 := Vector3(sin(a1), 0.0, cos(a1))
			var up := Vector3.UP
			# Number band top, outer wall, inner wall, pocket floor.
			_quad(verts, normals, colors, indices, d0 * NUMBER_R0 + up * NUMBER_Y, d0 * NUMBER_R1 + up * NUMBER_Y, d1 * NUMBER_R1 + up * NUMBER_Y, d1 * NUMBER_R0 + up * NUMBER_Y, up, c)
			_quad(verts, normals, colors, indices, d0 * NUMBER_R1 + up * NUMBER_Y, d0 * NUMBER_R1 + up * 0.012, d1 * NUMBER_R1 + up * 0.012, d1 * NUMBER_R1 + up * NUMBER_Y, (d0 + d1).normalized(), c.darkened(0.15))
			_quad(verts, normals, colors, indices, d0 * NUMBER_R0 + up * NUMBER_Y, d0 * NUMBER_R0 + up * POCKET_Y, d1 * NUMBER_R0 + up * POCKET_Y, d1 * NUMBER_R0 + up * NUMBER_Y, -(d0 + d1).normalized(), floor_c)
			_quad(verts, normals, colors, indices, d0 * POCKET_R0 + up * POCKET_Y, d0 * NUMBER_R0 + up * POCKET_Y, d1 * NUMBER_R0 + up * POCKET_Y, d1 * POCKET_R0 + up * POCKET_Y, up, floor_c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A flat-shaded quad a-b-c-d facing `n` (Godot's clockwise front faces).
static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color) -> void:
	var base := verts.size()
	verts.append_array(PackedVector3Array([a, b, c, d]))
	var lin := color.srgb_to_linear()
	for i in 4:
		normals.append(n)
		colors.append(lin)
	var tris := [[0, 1, 2], [0, 2, 3]]
	for t: Array in tris:
		var p0: Vector3 = verts[base + int(t[0])]
		var cr := (verts[base + int(t[1])] - p0).cross(verts[base + int(t[2])] - p0)
		if cr.dot(n) > 0.0:
			indices.append_array(PackedInt32Array([base + int(t[0]), base + int(t[2]), base + int(t[1])]))
		else:
			indices.append_array(PackedInt32Array([base + int(t[0]), base + int(t[1]), base + int(t[2])]))


func _surface_y(r: float) -> float:
	if r >= TRACK_INNER_R:
		return lerpf(TRACK_INNER_Y, TRACK_OUTER_Y, clampf((r - TRACK_INNER_R) / (TRACK_OUTER_R - TRACK_INNER_R), 0.0, 1.0))
	if r >= NUMBER_R0:
		return NUMBER_Y
	return POCKET_Y


## The ball's angle around the wheel (wheel space).
func _ball_angle() -> float:
	var p := ball.position
	if ball.get_parent() == rotor:
		p = rotor.transform * p
	return atan2(p.x, p.z)


func _mult_text(id: StringName) -> String:
	var number: bool = RouletteBoard.choice_for(id).get("kind", "") == "number"
	var profit := Tuning.ROULETTE_NUMBER_PAYOUT if number else TableGames.profit_multiple(HR.GameType.ROULETTE)
	return ("%.1f" % (1.0 + profit)).trim_suffix(".0")


static func _bet_text(detail: Dictionary) -> String:
	if str(detail.get("kind", "")) == "number":
		return str(int(detail.get("pick", detail.get("number", 0))))
	return str(detail.get("pick", "red")).to_upper()


static func _heat_name(heat_class: int) -> String:
	match heat_class:
		HR.HeatClass.LOW:
			return "LOW"
		HR.HeatClass.MEDIUM:
			return "MEDIUM"
		HR.HeatClass.HIGH:
			return "HIGH"
	return "VERY HIGH"


static func _rect_points(size: Vector2) -> PackedVector2Array:
	var hw := size.x * 0.5
	var hd := size.y * 0.5
	return PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)])


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()
