class_name SlotsMachine
extends GameMachine
## A tall rounded slot cabinet (ref: slots). Top to bottom it has:
## - a siren beacon,
## - a glowing marquee with original "LUCKY CHIP" art and chasing bulbs,
## - a paytable / result screen,
## - a 3×3 window onto three physical reel drums with a win line,
## - a wide SPIN key over the bet console,
## - a pull lever on the right side (pulling it presses SPIN).
##
## The host's &"bet" event drives every peer's spin: the reels kick back, spin,
## and stop left to right with a bounce on detail.reels (centre row). A win
## lights the win line and showers confetti; a jackpot also spins the beacon.
## Local presses only send requests.
##
## This file also holds helpers the A machines share (slots, big wheel,
## high-low): MachineConsole, BulbChain, bake() / MeshBaker and burst().

## A reel came to rest (reel index, the symbol on the line).
signal reel_stopped(reel: int, symbol: String)

const SYMBOLS_PER_REEL := 10
const REEL_COUNT := 3
## One reel strip, read top to bottom on the drum. Every GameResolver symbol
## is on it; "diamond" and "chip" are filler art that never lands on the line.
const STRIP: Array[String] = ["seven", "cherry", "lemon", "bar", "diamond", "bell", "orange", "plum", "chip", "cherry"]
## Each reel starts its strip at a different symbol, so the rows above and
## below the line differ.
const REEL_OFFSETS: Array[int] = [0, 3, 6]
const TILE_SIZE := Vector3(0.172, 0.174, 0.018)
## 10 tiles 0.19 m apart around the drum.
const REEL_RADIUS := 0.3024
const REEL_STEP := TAU / 10.0
const REEL_SPACING := 0.205
const WINDOW_Y := 1.48
## The cabinet front (window frame) plane.
const FRONT_Z := 0.06
const REEL_Z := -0.29
const CABINET_WIDTH := 0.9
const CABINET_BACK := -0.64
const HEAD_TOP := 2.0
const SHELL := Color("3a1f63")
const SHELL_DARK := Color("1e1033")
const GOLD := Color("ffc23d")
const TILE_CREAM := Color("fff4e0")
## Meta on part() nodes: the flat color bake() gives them.
const BAKE_COLOR := &"bake_color"

# Spin timing (seconds from the &"bet" event).
const KICK_SECONDS := 0.12
const KICK_ANGLE := 0.12
const FIRST_STOP := 1.0
const STOP_STAGGER := 0.42
const STOP_SECONDS := 0.4
const OVERSHOOT := 0.1
const SETTLE_SECONDS := 0.18
## Result on display before the round ends (console unlocks).
const HOLD_SECONDS := 0.75
const SPIN_SPEED := Tuning.TABLE_REEL_SYMBOLS_PER_SECOND * REEL_STEP
const BEACON_SECONDS := 5.0
const IDLE_SCREEN_SECONDS := 4.0

var reels: Array[Node3D] = []
var drums: Array[Node3D] = []
var lever: Lever3D
var top_screen: Screen3D
var marquee_bulbs: BulbChain
var beacon: Node3D
var jackpot_lamp: Label3D
## Neon frames around the three centre cells, lit on a win.
var win_frames: Array[MeshInstance3D] = []
var win_line: MeshInstance3D
var win_arrows: Array[MeshInstance3D] = []

var _angles: PackedFloat32Array = PackedFloat32Array()
var _from: PackedFloat32Array = PackedFloat32Array()
var _to: PackedFloat32Array = PackedFloat32Array()
var _speed: PackedFloat32Array = PackedFloat32Array()
var _stopped: Array[bool] = []
## Seconds into the current spin; < 0 when idle.
var _spin_time: float = -1.0
var _spin_result: Dictionary = {}
var _revealed: bool = false
var _beacon_seconds: float = 0.0
var _beacon_reflector: Node3D
var _beacon_light: OmniLight3D
var _beacon_dome: MeshInstance3D
var _idle_seconds: float = -1.0
var _win_on: bool = false
## Cached: do vertex colors need linearizing on this renderer (-1 unknown)?
static var _vertex_linear: int = -1
var _win_color: Color = DiegeticKit.TEXT_WIN


func _build_game() -> void:
	_angles.resize(REEL_COUNT)
	_from.resize(REEL_COUNT)
	_to.resize(REEL_COUNT)
	_speed.resize(REEL_COUNT)
	_stopped.clear()
	for j in REEL_COUNT:
		_angles[j] = 0.0
		_stopped.append(true)
	_build_cabinet()
	_build_reels()
	_build_marquee()
	_build_beacon()
	var mc := install_console(self, str(MAIN_LABELS.get(game_type, "SPIN")), DiegeticKit.KEY_GREEN, 24.0)
	place_console(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.875, 0.39)))
	mc.main_key.setup(mc.main_label, DiegeticKit.KEY_GREEN, Vector3(0.46, 0.05, 0.085), &"main")
	mc.main_key.set_emission(0.15)
	mc.relayout_rail()
	mc.mount_rail(visuals, Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(0.0, 1.135, 0.115)))
	lever = Lever3D.new()
	lever.name = "Lever"
	lever.setup(0.44, DiegeticKit.KEY_RED, 0.06)
	lever.position = Vector3(CABINET_WIDTH * 0.5 + 0.05, 1.12, -0.16)
	visuals.add_child(lever)
	lever.pulled.connect(_on_lever_pulled)
	register_pressable(&"lever", lever)
	set_footprint(Vector3(1.04, 2.45, 1.24), Vector3(0.0, 1.225, -0.04))
	set_play_spot(Vector3(0.0, 0.0, 0.95))
	set_label_height(2.82)
	pop_point = Vector3(0.0, 2.25, 0.3)
	_show_paytable()


# --- Public ---------------------------------------------------------------------

## The symbol on reel `reel`'s strip at drum position `index`.
static func reel_symbol(reel: int, index: int) -> String:
	return STRIP[posmod(index + REEL_OFFSETS[posmod(reel, REEL_COUNT)], SYMBOLS_PER_REEL)]


## The symbols on the win line now, read from the drums' angles.
func shown_symbols() -> Array[String]:
	var out: Array[String] = []
	for j in REEL_COUNT:
		out.append(reel_symbol(j, _index_at(_angles[j])))
	return out


## The 3×3 window, rows top to bottom, read from the drums.
func shown_grid() -> Array:
	var rows: Array = []
	for r: int in [1, 0, -1]:
		var row: Array[String] = []
		for j in REEL_COUNT:
			row.append(reel_symbol(j, _index_at(_angles[j]) + r))
		rows.append(row)
	return rows


func is_spinning() -> bool:
	return _spin_time >= 0.0


func is_beacon_on() -> bool:
	return _beacon_seconds > 0.0


func is_win_lit() -> bool:
	return _win_on


func reel_angle(reel: int) -> float:
	return _angles[reel]


## Total return for a win here (bet × this), with the casino's payout bonus.
func win_multiple(jackpot: bool = false) -> float:
	var profit := Tuning.SLOT_JACKPOT_PAYOUT if jackpot else TableGames.profit_multiple(HR.GameType.SLOTS)
	return 1.0 + profit * float(CasinoLadder.casino(rung).get("payout_bonus", 1.0))


## Jumps a running spin to its end (tests, skipping): reveal and result_shown.
func finish_spin() -> void:
	if _spin_time < 0.0:
		return
	_advance_spin(1000.0)


# --- GameMachine overrides --------------------------------------------------------

func _animate_result(result: Dictionary) -> void:
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	var symbols: Array = detail.get("reels", []) if detail.get("reels") is Array else []
	if symbols.size() != REEL_COUNT:
		super(result)
		return
	if _spin_time >= 0.0:
		_advance_spin(1000.0)
	_spin_result = result
	_revealed = false
	_spin_time = 0.0
	_idle_seconds = -1.0
	_set_win(false)
	top_screen.set_lines([{"text": "GOOD LUCK!", "color": DiegeticKit.TEXT_INFO, "size": 0.07}, {"text": "", "size": 0.035}])
	marquee_bulbs.set_mode(BulbChain.Mode.CHASE, 14.0)
	for j in REEL_COUNT:
		_from[j] = fposmod(_angles[j], TAU)
		_stopped[j] = false
		var target := _target_index(j, str(symbols[j])) * REEL_STEP
		var stop_at := FIRST_STOP + STOP_STAGGER * float(j)
		var span := (stop_at - STOP_SECONDS - KICK_SECONDS) + STOP_SECONDS * 0.5
		var nominal := _from[j] + SPIN_SPEED * span - OVERSHOOT
		var to := target + TAU * roundf((nominal - target) / TAU)
		if to < _from[j] + PI:
			to += TAU
		_to[j] = to
		_speed[j] = (to + OVERSHOOT - _from[j]) / span
	if not is_inside_tree():
		_advance_spin(1000.0)


func _end_result(result: Dictionary) -> void:
	super(result)
	_idle_seconds = IDLE_SCREEN_SECONDS


func _on_closed_changed(value: bool) -> void:
	if lever != null:
		lever.enabled = not value
	if marquee_bulbs != null:
		marquee_bulbs.set_mode(BulbChain.Mode.OFF if value else BulbChain.Mode.IDLE)


func _process(delta: float) -> void:
	super(delta)
	if _spin_time >= 0.0:
		_advance_spin(delta)
	if _beacon_seconds > 0.0:
		_beacon_seconds = maxf(0.0, _beacon_seconds - delta)
		_animate_beacon(delta)
	if _win_on:
		var k := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.001 * TAU * 2.5)
		for f: MeshInstance3D in win_frames:
			ArtKit.set_neon_level(f, k)
	if _idle_seconds > 0.0:
		_idle_seconds -= delta
		if _idle_seconds <= 0.0 and _spin_time < 0.0:
			_show_paytable()
			_set_win(false)
			if not closed:
				marquee_bulbs.set_mode(BulbChain.Mode.IDLE)


# --- Spin -------------------------------------------------------------------------

func _advance_spin(delta: float) -> void:
	_spin_time += delta
	var all_done := true
	for j in REEL_COUNT:
		_angles[j] = _angle_at(j, _spin_time)
		drums[j].rotation.x = _angles[j]
		var settled := _spin_time >= FIRST_STOP + STOP_STAGGER * float(j) + SETTLE_SECONDS
		if settled and not _stopped[j]:
			_stopped[j] = true
			_angles[j] = fposmod(_to[j], TAU)
			drums[j].rotation.x = _angles[j]
			reel_stopped.emit(j, reel_symbol(j, _index_at(_angles[j])))
		all_done = all_done and _stopped[j]
	if all_done and not _revealed:
		_revealed = true
		_reveal(_spin_result)
	var end := FIRST_STOP + STOP_STAGGER * float(REEL_COUNT - 1) + SETTLE_SECONDS + HOLD_SECONDS
	if _revealed and _spin_time >= end:
		_spin_time = -1.0
		var result := _spin_result
		_spin_result = {}
		_end_result(result)


func _angle_at(j: int, t: float) -> float:
	var from := _from[j]
	var stop_at := FIRST_STOP + STOP_STAGGER * float(j)
	var lin_end := stop_at - STOP_SECONDS
	if t < KICK_SECONDS:
		return from - KICK_ANGLE * sin(PI * t / KICK_SECONDS)
	if t < lin_end:
		return from + _speed[j] * (t - KICK_SECONDS)
	var a1 := from + _speed[j] * (lin_end - KICK_SECONDS)
	var over := _to[j] + OVERSHOOT
	if t < stop_at:
		var u := (t - lin_end) / STOP_SECONDS
		return a1 + (over - a1) * (1.0 - (1.0 - u) * (1.0 - u))
	if t < stop_at + SETTLE_SECONDS:
		return over - OVERSHOOT * smoothstep(0.0, 1.0, (t - stop_at) / SETTLE_SECONDS)
	return _to[j]


func _index_at(angle: float) -> int:
	return posmod(roundi(angle / REEL_STEP), SYMBOLS_PER_REEL)


## The drum position of `symbol` on reel `j` (the first one on the strip).
func _target_index(j: int, symbol: String) -> int:
	for i in SYMBOLS_PER_REEL:
		if reel_symbol(j, i) == symbol:
			return i
	return 0


func _reveal(result: Dictionary) -> void:
	var won := bool(result.get("won", false)) and int(result.get("payout", 0)) > 0
	var jackpot := bool(result.get("jackpot", false))
	var tc := GameMachine.result_text(result)
	if won:
		_set_win(true, GOLD if jackpot else DiegeticKit.TEXT_WIN)
		var mult := float(result.get("payout", 0)) / maxf(1.0, float(result.get("bet", 1)))
		var sym := str(shown_symbols()[0]).to_upper()
		top_screen.set_lines([{"text": str(tc[0]), "color": tc[1], "size": 0.08},
				{"text": "3 × %s  ·  ×%s" % [sym, _fmt_mult(mult)], "color": DiegeticKit.TEXT_MONEY, "size": 0.036}])
		top_screen.flash(tc[1], 0.6, 0.7)
		var front := Vector3(0.0, WINDOW_Y - 0.1, FRONT_Z + 0.12)
		burst(visuals, front, 120 if jackpot else 46, 4.6 if jackpot else 3.2, false)
		burst(visuals, front, 44 if jackpot else 16, 3.8 if jackpot else 2.8, true)
		marquee_bulbs.set_mode(BulbChain.Mode.FLASH, 10.0)
		if jackpot:
			_beacon_seconds = BEACON_SECONDS
			jackpot_lamp.modulate = Color(GOLD.r * 1.8, GOLD.g * 1.8, GOLD.b * 1.8)
			flash(GOLD, 4.0, 1.6)
	else:
		_set_win(false)
		top_screen.set_lines([{"text": "THROWN" if bool(result.get("intentional_loss", false)) else "NO WIN", "color": DiegeticKit.TEXT_LOSE, "size": 0.08},
				{"text": "-%s" % DiegeticKit.money_short(int(result.get("bet", 0))), "color": DiegeticKit.TEXT_LOSE, "size": 0.036}])
		top_screen.flash(DiegeticKit.TEXT_LOSE, 0.4, 0.5)
		flash(DiegeticKit.TEXT_LOSE, 1.2, 0.5)
		marquee_bulbs.set_mode(BulbChain.Mode.IDLE)


func _fmt_mult(m: float) -> String:
	return ("%.1f" % m).trim_suffix(".0")


## Lights (or dims) the win line, its arrows and the centre-cell frames.
func _set_win(on: bool, color: Color = DiegeticKit.TEXT_WIN) -> void:
	_win_on = on
	_win_color = color
	if win_line == null:
		return
	win_line.visible = on
	for f: MeshInstance3D in win_frames:
		f.visible = on
	for a: MeshInstance3D in win_arrows:
		ArtKit.set_neon_level(a, 1.0 if on else 0.35)


func _show_paytable() -> void:
	if top_screen == null:
		return
	top_screen.set_lines([{"text": "3 ALIKE PAYS ×%s" % _fmt_mult(win_multiple()), "color": DiegeticKit.TEXT_WIN, "size": 0.054},
			{"text": "7 7 7  JACKPOT ×%s" % _fmt_mult(win_multiple(true)), "color": DiegeticKit.TEXT_MONEY, "size": 0.04}])
	if jackpot_lamp != null:
		jackpot_lamp.modulate = GOLD.darkened(0.25)


func _on_lever_pulled(pid: int) -> void:
	if console != null:
		console.press_key(&"main", pid)


func _animate_beacon(delta: float) -> void:
	if _beacon_reflector == null:
		return
	var on := _beacon_seconds > 0.0
	_beacon_reflector.visible = on
	_beacon_reflector.rotation.y += delta * TAU * 1.2
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * 3.0)
	_beacon_light.visible = on
	_beacon_light.light_energy = (1.5 + 3.5 * pulse) if on else 0.0
	ArtKit.set_neon_level(_beacon_dome, (0.55 + 0.45 * pulse) if on else 0.35)
	if not on and jackpot_lamp != null:
		jackpot_lamp.modulate = GOLD.darkened(0.25)


# --- Build ------------------------------------------------------------------------

func _build_cabinet() -> void:
	var shell := Node3D.new()
	shell.name = "Cabinet"
	visuals.add_child(shell)
	var depth := FRONT_Z - CABINET_BACK
	var mid_z := (FRONT_Z + CABINET_BACK) * 0.5
	var win_half_h := REEL_RADIUS * sin(REEL_STEP * 1.5) + 0.005
	var win_half_w := REEL_SPACING * 1.5 + 0.012
	var win_bottom := WINDOW_Y - win_half_h
	var win_top := WINDOW_Y + win_half_h
	# Pedestal (with a chip-and-stripe front panel) and the console shelf.
	_box(shell, Vector3(CABINET_WIDTH - 0.04, 0.84, depth - 0.06), Vector3(0.0, 0.42, mid_z - 0.03), SHELL, 0.06)
	_box(shell, Vector3(CABINET_WIDTH - 0.02, 0.06, depth - 0.02), Vector3(0.0, 0.03, mid_z), SHELL_DARK, 0.03)
	_box(shell, Vector3(CABINET_WIDTH - 0.2, 0.52, 0.02), Vector3(0.0, 0.42, FRONT_Z - 0.05), accent.darkened(0.25), 0.04)
	for k in 3:
		_box(shell, Vector3(CABINET_WIDTH - 0.28, 0.035, 0.02), Vector3(0.0, 0.26 + 0.16 * k, FRONT_Z - 0.035), GOLD, 0.015)
	_box(shell, Vector3(CABINET_WIDTH, 0.07, 0.66), Vector3(0.0, 0.84, 0.25), SHELL_DARK, 0.03)
	_box(shell, Vector3(CABINET_WIDTH - 0.1, 0.1, 0.5), Vector3(0.0, 0.76, 0.24), SHELL, 0.03)
	# Lower head: from the shelf up to the window, with a sloped ledge for the SPIN key.
	_box(shell, Vector3(CABINET_WIDTH, win_bottom - 0.84, depth), Vector3(0.0, (win_bottom + 0.84) * 0.5, mid_z), SHELL, 0.05)
	part(shell, MeshFactory.wedge(Vector3(CABINET_WIDTH - 0.02, 0.2, 0.2), 0.25, 0.01), SHELL_DARK, Vector3(0.0, win_bottom - 0.1, FRONT_Z + 0.08))
	# Window frame: pillars, crown, a dark box behind the drums, gold bezel, dividers.
	var pillar_w := (CABINET_WIDTH - win_half_w * 2.0) * 0.5
	for sx: float in [-1.0, 1.0]:
		_box(shell, Vector3(pillar_w, win_half_h * 2.0 + 0.04, depth), Vector3(sx * (win_half_w + pillar_w * 0.5), WINDOW_Y, mid_z), SHELL, 0.03)
	_box(shell, Vector3(CABINET_WIDTH, HEAD_TOP - win_top, depth), Vector3(0.0, (HEAD_TOP + win_top) * 0.5, mid_z), SHELL, 0.06)
	_box(shell, Vector3(win_half_w * 2.0 + 0.02, win_half_h * 2.0 + 0.04, 0.03), Vector3(0.0, WINDOW_Y, CABINET_BACK + 0.04), SHELL_DARK, 0.0)
	part(shell, MeshFactory.stroke(_rounded_rect(win_half_w + 0.012, win_half_h + 0.012, 0.03), 0.034, 0.04), GOLD, Vector3(0.0, WINDOW_Y, FRONT_Z + 0.012))
	for k: float in [-0.5, 0.5]:
		_box(shell, Vector3(0.016, win_half_h * 2.0, 0.03), Vector3(k * REEL_SPACING, WINDOW_Y, FRONT_Z - 0.02), DiegeticKit.CHROME, 0.006)
	bake(shell, 0.5, "Shell")
	# Win line across the centre row, an arrow at each end, a frame per centre cell.
	win_line = ArtKit.mesh_instance(MeshFactory.pill(win_half_w * 2.0 - 0.02, 0.005), ArtKit.neon_material(Color("fff06a"), 2.6))
	win_line.name = "WinLine"
	win_line.position = Vector3(0.0, WINDOW_Y, FRONT_Z - 0.004)
	visuals.add_child(win_line)
	for sx: float in [-1.0, 1.0]:
		var arrow := MeshInstance3D.new()
		arrow.name = "WinArrow"
		arrow.mesh = MeshFactory.triangle(0.075, 0.02)
		arrow.material_override = ArtKit.neon_material(Color("fff06a"), 2.4)
		arrow.rotation.z = sx * PI * 0.5
		arrow.position = Vector3(sx * (win_half_w + 0.06), WINDOW_Y, FRONT_Z + 0.012)
		visuals.add_child(arrow)
		win_arrows.append(arrow)
	for j in REEL_COUNT:
		var f := MeshInstance3D.new()
		f.name = "WinFrame%d" % j
		f.mesh = MeshFactory.stroke(_rounded_rect(TILE_SIZE.x * 0.5 + 0.004, TILE_SIZE.y * 0.5 + 0.004, 0.02), 0.012, 0.008)
		f.material_override = ArtKit.neon_material(Color("fff06a"), 2.8)
		f.position = Vector3((float(j) - 1.0) * REEL_SPACING, WINDOW_Y, FRONT_Z - 0.008)
		visuals.add_child(f)
		win_frames.append(f)
	_set_win(false)
	# Side neon strips up the front corners.
	for sx: float in [-1.0, 1.0]:
		var strip := ArtKit.mesh_instance(MeshFactory.pill(HEAD_TOP - 0.95, 0.014), ArtKit.neon_material(accent.lightened(0.1), 2.3))
		strip.name = "SideNeon"
		strip.rotation.z = PI * 0.5
		strip.position = Vector3(sx * (CABINET_WIDTH * 0.5 + 0.004), (HEAD_TOP + 0.95) * 0.5, FRONT_Z - 0.01)
		visuals.add_child(strip)
	var shelf_trim := ArtKit.mesh_instance(MeshFactory.pill(CABINET_WIDTH - 0.06, 0.012), ArtKit.neon_material(accent.lightened(0.15), 2.2))
	shelf_trim.name = "ShelfNeon"
	shelf_trim.position = Vector3(0.0, 0.84, 0.585)
	visuals.add_child(shelf_trim)
	# Paytable / result screen in the crown.
	top_screen = Screen3D.new()
	top_screen.name = "TopScreen"
	top_screen.setup(Vector2(0.72, 0.22), 2, accent.lightened(0.2), DiegeticKit.BEZEL, 0.016)
	top_screen.position = Vector3(0.0, (HEAD_TOP + win_top) * 0.5 + 0.005, FRONT_Z + 0.004)
	visuals.add_child(top_screen)


func _build_reels() -> void:
	reels.clear()
	drums.clear()
	var tile_mesh := MeshFactory.rounded_box(TILE_SIZE, 0.022, 2)
	for j in REEL_COUNT:
		var reel := Node3D.new()
		reel.name = "Reel%d" % j
		reel.position = Vector3((float(j) - 1.0) * REEL_SPACING, WINDOW_Y, REEL_Z)
		visuals.add_child(reel)
		reels.append(reel)
		var drum := Node3D.new()
		drum.name = "Drum"
		reel.add_child(drum)
		drums.append(drum)
		part(drum, MeshFactory.rounded_cylinder(REEL_RADIUS - 0.02, TILE_SIZE.x - 0.01, 0.01, 20), SHELL_DARK, Vector3.ZERO, Vector3(0.0, 0.0, PI * 0.5))
		for i in SYMBOLS_PER_REEL:
			var holder := Node3D.new()
			holder.name = "Tile%d" % i
			var b := Basis(Vector3.RIGHT, -float(i) * REEL_STEP)
			holder.transform = Transform3D(b, b * Vector3(0.0, 0.0, REEL_RADIUS))
			drum.add_child(holder)
			part(holder, tile_mesh, TILE_CREAM)
			var sym := build_symbol(reel_symbol(j, i))
			sym.position.z = TILE_SIZE.z * 0.5 + 0.002
			holder.add_child(sym)
		bake(drum, 0.35, "Strip")
		drum.rotation.x = _angles[j]


func _build_marquee() -> void:
	var y0 := 2.02
	var w := CABINET_WIDTH + 0.1
	var h := 0.4
	var mq := Node3D.new()
	mq.name = "Marquee"
	mq.position = Vector3(0.0, y0 + h * 0.5, FRONT_Z - 0.16)
	visuals.add_child(mq)
	var art := Node3D.new()
	art.name = "Art"
	mq.add_child(art)
	part(art, MeshFactory.rounded_box(Vector3(w, h, 0.3), 0.08, 3), accent.darkened(0.15))
	# Original art: a big lucky chip with a star.
	var chip := Node3D.new()
	chip.position = Vector3(-w * 0.5 + 0.2, 0.0, 0.17)
	art.add_child(chip)
	part(chip, MeshFactory.rounded_cylinder(0.13, 0.035, 0.012, 28), DiegeticKit.NEON_TRIM, Vector3.ZERO, Vector3(PI * 0.5, 0.0, 0.0))
	for k in 8:
		var a := TAU * float(k) / 8.0
		part(chip, MeshFactory.rounded_box(Vector3(0.05, 0.03, 0.012), 0.008, 2), TILE_CREAM, Vector3(cos(a) * 0.105, sin(a) * 0.105, 0.02), Vector3(0.0, 0.0, a + PI * 0.5))
	part(chip, MeshFactory.rounded_cylinder(0.07, 0.01, 0.004, 24), TILE_CREAM, Vector3(0.0, 0.0, 0.02), Vector3(PI * 0.5, 0.0, 0.0))
	part(chip, MeshFactory.star(0.058, 0.026, 5, 0.014), GOLD, Vector3(0.0, 0.0, 0.027))
	bake(art, 0.5, "Shell")
	var panel := ArtKit.mesh_instance(MeshFactory.rounded_box(Vector3(w - 0.38, h - 0.09, 0.02), 0.04, 2), ArtKit.toon_material(Color("2a0f4a"), 0.25, false, true))
	panel.name = "Panel"
	panel.position = Vector3(0.12, 0.0, 0.15)
	mq.add_child(panel)
	var title := DiegeticKit.text_label("LUCKY CHIP", 0.085, Color("fff06a"), 18, Color("2a0f4a"))
	title.name = "Title"
	title.position = Vector3(0.12, 0.05, 0.168)
	DiegeticKit.fit_label(title, "LUCKY CHIP", 0.085, w - 0.46)
	mq.add_child(title)
	jackpot_lamp = DiegeticKit.text_label("JACKPOT ×%s" % _fmt_mult(win_multiple(true)), 0.045, GOLD.darkened(0.25), 12, Color("2a0f4a"))
	jackpot_lamp.name = "JackpotLamp"
	jackpot_lamp.position = Vector3(0.12, -0.08, 0.168)
	mq.add_child(jackpot_lamp)
	# Chasing bulbs around the panel.
	var pts := PackedVector3Array()
	var hw := w * 0.5 - 0.025
	var hh := h * 0.5 - 0.025
	for i in 11:
		pts.append(Vector3(lerpf(-hw, hw, float(i) / 10.0), hh, 0.155))
	for i in range(1, 3):
		pts.append(Vector3(hw, lerpf(hh, -hh, float(i) / 3.0), 0.155))
	for i in 11:
		pts.append(Vector3(lerpf(hw, -hw, float(i) / 10.0), -hh, 0.155))
	for i in range(1, 3):
		pts.append(Vector3(-hw, lerpf(-hh, hh, float(i) / 3.0), 0.155))
	marquee_bulbs = BulbChain.new()
	marquee_bulbs.name = "Bulbs"
	marquee_bulbs.setup(pts, 0.017, [Color("fff06a"), DiegeticKit.NEON_TRIM, Color("3ef0ff")])
	mq.add_child(marquee_bulbs)


func _build_beacon() -> void:
	beacon = Node3D.new()
	beacon.name = "Beacon"
	beacon.position = Vector3(0.0, 2.42, FRONT_Z - 0.2)
	visuals.add_child(beacon)
	var base := Primitives.rounded_cylinder(0.11, 0.06, DiegeticKit.CHROME, 0.02, 20)
	base.position.y = 0.03
	beacon.add_child(base)
	_beacon_dome = ArtKit.mesh_instance(MeshFactory.lathe(PackedVector2Array([Vector2(0.095, 0.0), Vector2(0.097, 0.08), Vector2(0.08, 0.135),
			Vector2(0.045, 0.17), Vector2(0.0, 0.178)])), ArtKit.neon_material(DiegeticKit.KEY_RED, 1.6))
	_beacon_dome.name = "Dome"
	_beacon_dome.position.y = 0.06
	beacon.add_child(_beacon_dome)
	ArtKit.set_neon_level(_beacon_dome, 0.35)
	_beacon_reflector = Node3D.new()
	_beacon_reflector.name = "Reflector"
	_beacon_reflector.position.y = 0.13
	beacon.add_child(_beacon_reflector)
	# Two light beams that sweep the room while the siren is on.
	var beam_mesh := MeshFactory.lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.06, 0.05), Vector2(0.22, 1.1), Vector2(0.0, 1.1)]), 16)
	for side: float in [1.0, -1.0]:
		var beam := MeshInstance3D.new()
		beam.name = "Beam"
		beam.mesh = beam_mesh
		beam.material_override = ArtKit.toon_material(Color(1.0, 0.25, 0.2, 0.22), 1.0, true, false)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.rotation.x = side * PI * 0.5
		_beacon_reflector.add_child(beam)
	_beacon_reflector.visible = false
	_beacon_light = OmniLight3D.new()
	_beacon_light.name = "SirenLight"
	_beacon_light.light_color = DiegeticKit.KEY_RED
	_beacon_light.omni_range = 5.0
	_beacon_light.light_energy = 0.0
	_beacon_light.visible = false
	_beacon_light.position = Vector3(0.0, 0.1, 0.25)
	beacon.add_child(_beacon_light)


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, radius: float) -> MeshInstance3D:
	return part(parent, MeshFactory.rounded_box(size, radius, 3), color, pos)


static func _rounded_rect(hw: float, hh: float, r: float, steps: int = 4) -> PackedVector2Array:
	r = clampf(r, 0.0, minf(hw, hh))
	var pts := PackedVector2Array()
	var corners := [Vector2(hw - r, hh - r), Vector2(-hw + r, hh - r), Vector2(-hw + r, -hh + r), Vector2(hw - r, -hh + r)]
	for i in 4:
		for k in steps + 1:
			var a := PI * 0.5 * float(i) + PI * 0.5 * float(k) / float(steps)
			pts.append((corners[i] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


# --- Reel symbol art (original, built from shapes) --------------------------------

## A reel symbol about 0.15 m across, facing +Z: cherry, lemon, orange, plum,
## bell, bar, seven (GameResolver.SLOT_SYMBOLS) plus filler diamond and chip.
static func build_symbol(symbol: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Sym_%s" % symbol
	match symbol:
		"cherry":
			for c: Array in [[Vector3(-0.034, -0.03, 0.02), 0.036], [Vector3(0.03, -0.045, 0.024), 0.034]]:
				part(root, MeshFactory.ball(c[1], 4), Color("e8203a"), c[0])
				_shine(root, (c[0] as Vector3) + Vector3(-0.012, 0.012, 0.02))
			part(root, MeshFactory.stroke(PackedVector2Array([Vector2(-0.032, 0.0), Vector2(-0.01, 0.04), Vector2(0.014, 0.06), Vector2(0.03, -0.015)]), 0.01, 0.01, false),
					Color("2f9e44"), Vector3(0.0, 0.0, 0.01))
			_leaf(root, Vector3(0.04, 0.06, 0.012), 0.5)
		"lemon":
			part(root, MeshFactory.ball(0.05, 4), Color("ffe14d"), Vector3(0.0, 0.0, 0.016), Vector3.ZERO, Vector3(1.32, 0.94, 0.55))
			for sx: float in [-1.0, 1.0]:
				part(root, MeshFactory.ball(0.014, 3), Color("ffd21f"), Vector3(sx * 0.066, sx * 0.008, 0.012))
			_shine(root, Vector3(-0.02, 0.022, 0.046))
		"orange":
			part(root, MeshFactory.ball(0.054, 4), Color("ff8a1f"), Vector3(0.0, -0.008, 0.016), Vector3.ZERO, Vector3(1.0, 1.0, 0.58))
			_leaf(root, Vector3(0.02, 0.05, 0.03), -0.4)
			part(root, MeshFactory.ball(0.008, 3), Color("7a4a1c"), Vector3(0.0, 0.044, 0.036))
			_shine(root, Vector3(-0.022, 0.012, 0.05))
		"plum":
			part(root, MeshFactory.ball(0.05, 4), Color("8e3bd6"), Vector3(0.0, -0.008, 0.016), Vector3.ZERO, Vector3(0.92, 1.1, 0.58))
			_leaf(root, Vector3(0.024, 0.054, 0.024), -0.6)
			_shine(root, Vector3(-0.016, 0.016, 0.048))
		"bell":
			part(root, MeshFactory.lathe(PackedVector2Array([Vector2(0.0, -0.046), Vector2(0.064, -0.046), Vector2(0.066, -0.036),
					Vector2(0.052, -0.018), Vector2(0.044, 0.012), Vector2(0.036, 0.036), Vector2(0.02, 0.05), Vector2(0.0, 0.054)])),
					Color("ffc23d"), Vector3(0.0, 0.0, 0.01), Vector3.ZERO, Vector3(1.0, 1.0, 0.45))
			part(root, MeshFactory.ball(0.016, 3), Color("c98a12"), Vector3(0.0, -0.052, 0.022))
			part(root, MeshFactory.ball(0.011, 3), Color("c98a12"), Vector3(0.0, 0.06, 0.012))
			_shine(root, Vector3(-0.018, 0.012, 0.036))
		"bar":
			part(root, MeshFactory.rounded_box(Vector3(0.15, 0.066, 0.02), 0.016, 2), Color("241a35"), Vector3(0.0, 0.0, 0.01))
			part(root, MeshFactory.stroke(_rounded_rect(0.069, 0.027, 0.012), 0.007, 0.006), Color("ffc23d"), Vector3(0.0, 0.0, 0.022))
			var txt := DiegeticKit.text_label("BAR", 0.036, Color("fff8ec"))
			txt.position.z = 0.0215
			root.add_child(txt)
		"seven":
			var shadow := DiegeticKit.text_label("7", 0.118, Color("1c0f2e"))
			shadow.position = Vector3(0.006, -0.006, 0.006)
			root.add_child(shadow)
			var seven := DiegeticKit.text_label("7", 0.118, Color("ff2a3d"), 22, Color("ffc23d"))
			seven.position.z = 0.01
			root.add_child(seven)
		"diamond":
			part(root, MeshFactory.extrude(PackedVector2Array([Vector2(-0.034, 0.046), Vector2(0.034, 0.046), Vector2(0.066, 0.012), Vector2(0.0, -0.062), Vector2(-0.066, 0.012)]), 0.02),
					Color("3ef0ff"), Vector3(0.0, 0.0, 0.012))
			part(root, MeshFactory.extrude(PackedVector2Array([Vector2(-0.02, 0.04), Vector2(0.02, 0.04), Vector2(0.036, 0.014), Vector2(0.0, -0.03), Vector2(-0.036, 0.014)]), 0.004),
					Color("c9fbff"), Vector3(0.0, 0.0, 0.024))
		"chip":
			part(root, MeshFactory.rounded_cylinder(0.056, 0.016, 0.006, 24), Color("2f7bff"), Vector3(0.0, 0.0, 0.01), Vector3(PI * 0.5, 0.0, 0.0))
			for k in 6:
				var a := TAU * float(k) / 6.0
				part(root, MeshFactory.rounded_box(Vector3(0.022, 0.013, 0.006), 0.004, 2), TILE_CREAM, Vector3(cos(a) * 0.045, sin(a) * 0.045, 0.019), Vector3(0.0, 0.0, a + PI * 0.5))
			var txt := DiegeticKit.text_label("$", 0.046, Color("fff8ec"), 10)
			txt.position.z = 0.0195
			root.add_child(txt)
		_:
			var txt := DiegeticKit.text_label(symbol.to_upper(), 0.03, Color("241a35"))
			txt.position.z = 0.01
			root.add_child(txt)
	return root


static func _leaf(parent: Node3D, pos: Vector3, angle: float) -> void:
	part(parent, MeshFactory.ball(0.022, 3), Color("44c24a"), pos, Vector3(0.0, 0.0, angle), Vector3(1.6, 0.7, 0.45))


static func _shine(parent: Node3D, pos: Vector3) -> void:
	part(parent, MeshFactory.ball(0.008, 3), Color.WHITE, pos)


# --- Shared by the A machines ------------------------------------------------------

## Replaces `m`'s default console with a MachineConsole (ref7 layout), wired
## to the machine exactly like GameMachine wires its own.
static func install_console(m: GameMachine, main_label: String, main_color: Color, tilt_degrees: float = 28.0) -> MachineConsole:
	var old := m.console
	var xf := old.transform if old != null else Transform3D.IDENTITY
	if old != null:
		m.remove_child(old)
		old.queue_free()
	var c := MachineConsole.new()
	c.name = "Console"
	c.setup(main_label, main_color, tilt_degrees)
	c.gate = m._gate
	c.main_pressed.connect(m._on_console_main)
	c.action_pressed.connect(m._on_console_action)
	c.transform = xf
	m.add_child(c)
	m.console = c
	return c


## `color` as a vertex / instance color that renders like the same color in
## a source_color uniform: linear on Forward+ / Mobile, as is on the
## Compatibility renderer (which shades in sRGB space).
static func vertex_color(color: Color) -> Color:
	if _vertex_linear < 0:
		_vertex_linear = 0 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 1
	return color.srgb_to_linear() if _vertex_linear == 1 else color


## A material-less mesh node that only bake() merges (it holds no renderer
## instance data, unlike a toon MeshInstance3D). Returns it.
static func part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO,
		scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_meta(BAKE_COLOR, color)
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


## Merges every toon MeshInstance3D under `root` into one vertex-colored
## mesh (root space) and frees the originals; labels, neon and other nodes
## stay. Each toon instance takes a block of the renderer's small global
## instance-uniform buffer, so static decoration is baked. Returns the mesh.
static func bake(root: Node3D, gloss: float = 0.5, node_name: String = "Baked") -> MeshInstance3D:
	var baker := MeshBaker.new()
	var doomed: Array[MeshInstance3D] = []
	_collect_bake(root, Transform3D.IDENTITY, baker, doomed)
	for i in range(doomed.size() - 1, -1, -1):
		var mi := doomed[i]
		var parent := mi.get_parent()
		for c: Node in mi.get_children():
			mi.remove_child(c)
			parent.add_child(c)
			if c is Node3D:
				(c as Node3D).transform = mi.transform * (c as Node3D).transform
		parent.remove_child(mi)
		mi.free()
	var out := MeshInstance3D.new()
	out.name = node_name
	out.mesh = baker.commit()
	out.material_override = ArtKit.toon_material(Color.WHITE, 0.0, false, true, gloss, true)
	root.add_child(out)
	return out


static func _collect_bake(node: Node, xf: Transform3D, baker: MeshBaker, doomed: Array[MeshInstance3D]) -> void:
	for c: Node in node.get_children():
		if not c is Node3D:
			continue
		var cx := xf * (c as Node3D).transform
		if c is MeshInstance3D and _bakeable(c as MeshInstance3D):
			var mi := c as MeshInstance3D
			var col: Color = mi.get_meta(BAKE_COLOR) if mi.has_meta(BAKE_COLOR) else Primitives.material_color(mi.material_override)
			baker.add(mi.mesh, cx, col)
			doomed.append(mi)
		_collect_bake(c, cx, baker, doomed)


static func _bakeable(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or not mi.visible:
		return false
	if mi.has_meta(BAKE_COLOR):
		return true
	var mat := mi.material_override as ShaderMaterial
	if mat == null:
		return false
	return mat.shader == ArtKit.SHADER_TOON or mat.shader == ArtKit.SHADER_TOON_UNSHADED


## A one-shot shower at `at` (parent space): confetti, or poker chips with
## `chips`. Frees itself when done.
static func burst(parent: Node3D, at: Vector3, amount: int = 40, speed: float = 3.2, chips: bool = false, colors: Array = []) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "ChipBurst" if chips else "Confetti"
	p.one_shot = true
	p.amount = maxi(1, amount)
	p.lifetime = 1.7
	p.explosiveness = 0.9
	p.direction = Vector3(0.0, 1.0, 0.35)
	p.spread = 50.0
	p.initial_velocity_min = speed * 0.55
	p.initial_velocity_max = speed
	p.gravity = Vector3(0.0, -6.5, 0.0)
	p.damping_min = 0.4
	p.damping_max = 1.2
	p.particle_flag_rotate_y = true
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.25
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.08
	if chips:
		p.mesh = MeshFactory.rounded_cylinder(0.024, 0.008, 0.003, 14, 1)
	else:
		p.mesh = MeshFactory.rounded_box(Vector3(0.026, 0.005, 0.042), 0.0, 1)
	var cols: Array = colors
	if cols.is_empty():
		cols = [Color("ff3448"), Color("ffd23f"), Color("98e83a"), Color("47a6ff")] if chips \
				else [Color("ff3fd2"), Color("3ef0ff"), Color("b6ff3b"), Color("ffd23f"), Color("ff8a3d"), Color.WHITE]
	var offs := PackedFloat32Array()
	var ramp := PackedColorArray()
	for i in cols.size():
		offs.append(float(i) / float(cols.size()))
		ramp.append(cols[i])
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = offs
	g.colors = ramp
	p.color_initial_ramp = g
	p.material_override = ArtKit.toon_material(Color.WHITE, 0.15, true, false, 0.0, true)
	p.position = at
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## The ref7 bet console for the A machines: keypad | screen | MIN ¼ ½ ALL +
## THROW on the tilted panel, and the main key plus any action keys on a
## separate key tray (`rail`) that the machine mounts on its table rail.
## ¼ and ½ bet that share of the pocket, ALL the most you may bet (it also
## answers to &"max"); everything else behaves as BetConsole3D.
class MachineConsole extends BetConsole3D:
	const QUARTER := &"quarter"
	const ALL := &"all"
	const PANEL_QUICK: Array[StringName] = [&"min", &"quarter", &"half", &"all"]
	const RAIL_KEY_SIZE := Vector3(0.19, 0.06, 0.16)
	const RAIL_GAP := 0.03
	const RAIL_PAD := 0.035
	const TRAY_HEIGHT := 0.04

	## Rail key ids left to right; ids not listed follow (main first, then
	## action keys in the order they were added).
	var rail_order: Array[StringName] = []
	var rail: Node3D
	var tray: MeshInstance3D
	var tray_trim: MeshInstance3D
	var _rail_size: Vector3 = Vector3.ZERO

	func setup(p_main_label: String = "PLAY", main_color: Color = DiegeticKit.KEY_GREEN, p_tilt_degrees: float = 28.0) -> BetConsole3D:
		rail = null
		super.setup(p_main_label, main_color, p_tilt_degrees)
		for qid: StringName in [&"double", &"max"]:
			var k: KeyButton3D = quick_keys.get(qid)
			if k != null:
				quick_keys.erase(qid)
				k.get_parent().remove_child(k)
				k.queue_free()
		for qid: StringName in [QUARTER, ALL]:
			var q := _make_key("¼" if qid == QUARTER else "ALL", DiegeticKit.KEY_ORANGE, QUICK_SIZE, qid)
			q.set_emission(0.18)
			quick_keys[qid] = q
		main_key.setup(p_main_label, main_color, RAIL_KEY_SIZE, &"main")
		main_key.set_emission(0.12)
		_layout()
		return self

	func add_action_key(id: StringName, label: String, color: Color = DiegeticKit.KEY_YELLOW) -> KeyButton3D:
		var existed := action_keys.has(id)
		var k := super.add_action_key(id, label, color)
		if not existed:
			k.setup(label, color, RAIL_KEY_SIZE, id)
			k.set_emission(0.12)
			_layout()
		return k

	func remove_action_key(id: StringName) -> void:
		if not action_keys.has(id):
			return
		var k: KeyButton3D = action_keys[id]
		action_keys.erase(id)
		_action_order.erase(id)
		if k.get_parent() != null:
			k.get_parent().remove_child(k)
		k.queue_free()
		_layout()

	func get_key(id: StringName) -> KeyButton3D:
		return super.get_key(ALL if id == &"max" else id)

	func key_ids() -> Array[StringName]:
		var out: Array[StringName] = []
		for t: String in Keypad3D.LAYOUT:
			out.append(StringName(t))
		out.append_array(PANEL_QUICK)
		out.append(&"throw")
		for k: KeyButton3D in rail_keys():
			out.append(k.id)
		return out

	## The fat keys on the rail, left to right.
	func rail_keys() -> Array[KeyButton3D]:
		var ids: Array[StringName] = []
		for id: StringName in rail_order:
			if (id == &"main" or action_keys.has(id)) and not ids.has(id):
				ids.append(id)
		if not ids.has(&"main"):
			if rail_order.is_empty():
				ids.insert(0, &"main")
			else:
				ids.append(&"main")
		for id: StringName in _action_order:
			if not ids.has(id):
				ids.append(id)
		var out: Array[KeyButton3D] = []
		for id: StringName in ids:
			var k := get_key(id)
			if k != null:
				out.append(k)
		return out

	## Moves the key tray under `parent` at `xform` (parent space). The tray's
	## origin is its bottom centre; keys face +Y, the player stands at +Z.
	func mount_rail(parent: Node3D, xform: Transform3D) -> void:
		if rail.get_parent() != null:
			rail.get_parent().remove_child(rail)
		parent.add_child(rail)
		rail.transform = xform

	## Size of the key tray (m).
	func rail_size() -> Vector3:
		return _rail_size

	func set_rail_order(ids: Array[StringName]) -> void:
		rail_order = ids.duplicate()
		relayout_rail()

	func relayout_rail() -> void:
		if rail != null:
			_layout_rail()

	func _on_key(user_pid: int, id: StringName) -> void:
		if id != QUARTER and id != &"half" and id != ALL:
			super._on_key(user_pid, id)
			return
		var k := get_key(id)
		if locked:
			if k != null:
				k.play_nope()
			return
		if gate.is_valid():
			var why: Variant = gate.call(user_pid)
			var text := str(why) if why != null else ""
			if text != "":
				if k != null:
					k.play_nope()
				show_message(text, DiegeticKit.TEXT_WARN)
				refused.emit(user_pid, text)
				return
		key_pressed.emit(id, user_pid)
		match id:
			QUARTER:
				_set_bet(clampi(pocket / 4, min_bet, cap()))
			&"half":
				_set_bet(clampi(pocket / 2, min_bet, cap()))
			ALL:
				_set_bet(cap())
		_fresh = true
		_refresh_screen()

	func _layout() -> void:
		if rail == null:
			rail = Node3D.new()
			rail.name = "Rail"
			add_child(rail)
			tray = MeshInstance3D.new()
			tray.name = "Tray"
			rail.add_child(tray)
			tray_trim = MeshInstance3D.new()
			tray_trim.name = "TrayTrim"
			rail.add_child(tray_trim)
		var fat: Array[KeyButton3D] = [main_key]
		for aid: StringName in _action_order:
			fat.append(action_keys[aid])
		for k: KeyButton3D in fat:
			if k != null and k.get_parent() != rail:
				if k.get_parent() != null:
					k.get_parent().remove_child(k)
				rail.add_child(k)
		var kp := keypad.get_size()
		var depth := kp.y + MARGIN * 2.0
		var width := MARGIN + kp.x + GAP + SCREEN_WIDTH + GAP + QUICK_SIZE.x + MARGIN
		var tilt := deg_to_rad(tilt_degrees)
		var rise := depth * sin(tilt)
		var flat_depth := depth * cos(tilt)
		var back_h := FRONT_HEIGHT + rise
		_size = Vector3(width, back_h + DECK_THICKNESS, flat_depth)
		body_mesh.mesh = MeshFactory.wedge(Vector3(width, back_h, flat_depth), FRONT_HEIGHT / back_h, 0.012)
		body_mesh.material_override = DiegeticKit.key_material(DiegeticKit.CONSOLE_BODY)
		body_mesh.position = Vector3(0.0, back_h * 0.5, 0.0)
		ArtKit.set_outline_mode(body_mesh, MeshFactory.OUTLINE_BOX)
		deck.position = Vector3(0.0, FRONT_HEIGHT + rise * 0.5, 0.0)
		deck.rotation = Vector3(tilt, 0.0, 0.0)
		var plate_size := Vector3(width - 0.01, DECK_THICKNESS, depth - 0.01)
		deck_plate.mesh = MeshFactory.rounded_box(plate_size, 0.006, 2)
		deck_plate.material_override = DiegeticKit.key_material(DiegeticKit.CONSOLE_DECK)
		deck_plate.position.y = DECK_THICKNESS * 0.5
		var hw := plate_size.x * 0.5 - 0.004
		var hd := plate_size.z * 0.5 - 0.004
		trim.mesh = MeshFactory.stroke(PackedVector2Array([Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]), 0.007, 0.006)
		trim.material_override = ArtKit.neon_material(DiegeticKit.NEON_TRIM, 2.2)
		trim.rotation.x = -PI * 0.5
		trim.position.y = DECK_THICKNESS + 0.001
		var top := DECK_THICKNESS
		var x := -width * 0.5 + MARGIN
		keypad.position = Vector3(x + kp.x * 0.5, top, 0.0)
		x += kp.x + GAP
		if screen.lines.is_empty():
			screen.setup(Vector2(SCREEN_WIDTH, kp.y - 0.012), 4, Color("ff3fd2"), DiegeticKit.BEZEL, 0.012)
			screen.set_line(0, "", DiegeticKit.TEXT_WHITE, 0.021)
			screen.set_line(1, "", DiegeticKit.TEXT_MONEY, 0.074)
			screen.set_line(2, "", DiegeticKit.TEXT_POCKET, 0.02)
			screen.set_line(3, "", DiegeticKit.TEXT_INFO, 0.021)
		screen.position = Vector3(x + SCREEN_WIDTH * 0.5, top + 0.006, 0.0)
		screen.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		x += SCREEN_WIDTH + GAP
		var column: Array[KeyButton3D] = []
		for qid: StringName in PANEL_QUICK:
			if quick_keys.has(qid):
				column.append(quick_keys[qid])
		column.append(throw_key)
		var pitch := kp.y / float(column.size())
		for i in column.size():
			column[i].position = Vector3(x + QUICK_SIZE.x * 0.5, top, (float(i) - float(column.size() - 1) * 0.5) * pitch)
		_layout_rail()

	func _layout_rail() -> void:
		var keys := rail_keys()
		var w := 0.0
		var d := 0.0
		for k: KeyButton3D in keys:
			w += k.size.x
			d = maxf(d, k.size.z)
		w += RAIL_GAP * float(maxi(keys.size() - 1, 0))
		var x := -w * 0.5
		for k: KeyButton3D in keys:
			k.position = Vector3(x + k.size.x * 0.5, TRAY_HEIGHT, 0.0)
			k.rotation = Vector3.ZERO
			x += k.size.x + RAIL_GAP
		_rail_size = Vector3(w + RAIL_PAD * 2.0, TRAY_HEIGHT, d + RAIL_PAD * 2.0)
		tray.mesh = MeshFactory.rounded_box(_rail_size, minf(0.02, TRAY_HEIGHT * 0.45), 3)
		tray.material_override = DiegeticKit.key_material(DiegeticKit.CONSOLE_DECK)
		tray.position = Vector3(0.0, TRAY_HEIGHT * 0.5, 0.0)
		var hw := _rail_size.x * 0.5 - 0.008
		var hd := _rail_size.z * 0.5 - 0.008
		tray_trim.mesh = MeshFactory.stroke(SlotsMachine._rounded_rect(hw, hd, 0.016), 0.007, 0.006)
		tray_trim.material_override = ArtKit.neon_material(DiegeticKit.NEON_TRIM, 2.2)
		tray_trim.rotation.x = -PI * 0.5
		tray_trim.position.y = TRAY_HEIGHT + 0.001


## Accumulates meshes (transformed, one flat color each) into a single
## ArrayMesh with vertex colors, encoded to match a toon albedo uniform.
class MeshBaker extends RefCounted:
	var _verts := PackedVector3Array()
	var _normals := PackedVector3Array()
	var _colors := PackedColorArray()
	var _uvs := PackedVector2Array()
	var _indices := PackedInt32Array()

	func add(mesh: Mesh, xform: Transform3D, color: Color) -> void:
		if mesh == null:
			return
		var nb := xform.basis.inverse().transposed()
		var lin := SlotsMachine.vertex_color(color)
		for s in mesh.get_surface_count():
			if mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: Variant = arr[Mesh.ARRAY_NORMAL]
			var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			var has_n := n is PackedVector3Array and (n as PackedVector3Array).size() == v.size()
			var has_uv := uv is PackedVector2Array and (uv as PackedVector2Array).size() == v.size()
			var base := _verts.size()
			for i in v.size():
				_verts.append(xform * v[i])
				_normals.append((nb * (n as PackedVector3Array)[i]).normalized() if has_n else Vector3.UP)
				_uvs.append((uv as PackedVector2Array)[i] if has_uv else Vector2.ZERO)
				_colors.append(lin)
			if idx is PackedInt32Array and (idx as PackedInt32Array).size() > 0:
				for i: int in (idx as PackedInt32Array):
					_indices.append(base + i)
			else:
				for i in v.size():
					_indices.append(base + i)

	func is_empty() -> bool:
		return _verts.is_empty()

	func commit() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if _verts.is_empty():
			return mesh
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _verts
		arr[Mesh.ARRAY_NORMAL] = _normals
		arr[Mesh.ARRAY_TEX_UV] = _uvs
		arr[Mesh.ARRAY_COLOR] = _colors
		arr[Mesh.ARRAY_INDEX] = _indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return mesh


## A row of round marquee bulbs that idle-twinkle, chase, flash or stay
## solid: one MultiMesh (a single instance), brightness per bulb through
## HDR instance colors so lit bulbs bloom.
class BulbChain extends Node3D:
	enum Mode { IDLE, CHASE, FLASH, SOLID, OFF }
	const ENERGY := 2.2

	var mode: Mode = Mode.IDLE
	## Chase steps / flashes per second.
	var speed: float = 6.0
	var colors: Array[Color] = []
	var multimesh: MultiMesh
	var mm_instance: MultiMeshInstance3D
	var _t: float = 0.0

	func setup(points: PackedVector3Array, radius: float = 0.02, p_colors: Array = [Color("fff06a")]) -> BulbChain:
		if mm_instance != null:
			mm_instance.queue_free()
		colors.clear()
		for c: Variant in p_colors:
			colors.append(c as Color)
		if colors.is_empty():
			colors.append(Color("fff06a"))
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.mesh = MeshFactory.ball(radius, 3)
		multimesh.instance_count = points.size()
		for i in points.size():
			multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))
		mm_instance = MultiMeshInstance3D.new()
		mm_instance.name = "Bulbs"
		mm_instance.multimesh = multimesh
		mm_instance.material_override = ArtKit.toon_material(Color.WHITE, 0.0, true, false, 0.0, true)
		mm_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mm_instance)
		_apply()
		return self

	func count() -> int:
		return multimesh.instance_count if multimesh != null else 0

	func set_mode(m: Mode, p_speed: float = -1.0) -> void:
		mode = m
		if p_speed > 0.0:
			speed = p_speed
		_t = 0.0
		_apply()

	## Recolors the bulbs (cycling through `p_colors`).
	func set_colors(p_colors: Array) -> void:
		if p_colors.is_empty():
			return
		colors.clear()
		for c: Variant in p_colors:
			colors.append(c as Color)
		_apply()

	## The current brightness of bulb `i` (0..1).
	func level(i: int) -> float:
		match mode:
			Mode.OFF:
				return 0.12
			Mode.SOLID:
				return 1.0
			Mode.FLASH:
				return 1.0 if int(_t * speed) % 2 == 0 else 0.15
			Mode.CHASE:
				return 1.0 if posmod(i - int(_t * speed), 3) == 0 else 0.22
		return 1.0 if posmod(i + int(_t * 1.6), 2) == 0 else 0.45

	func _process(delta: float) -> void:
		_t += delta
		_apply()

	func _apply() -> void:
		if multimesh == null:
			return
		for i in multimesh.instance_count:
			var c := SlotsMachine.vertex_color(colors[i % colors.size()])
			var k := level(i)
			var e := lerpf(0.35, ENERGY, k)
			multimesh.set_instance_color(i, Color(c.r * e, c.g * e, c.b * e, 1.0))
