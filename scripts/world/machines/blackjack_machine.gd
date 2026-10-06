class_name BlackjackMachine
extends GameMachine
## Blackjack (ref: blackjack keys). A half-moon felt table: the dealer stands
## behind a glass shield on the straight side, a card shoe sits at their
## right, the player stands at the curved padded rail. A row of fat rounded
## rail keys (yellow STAND, red HIT, green PLAY = deal with the console bet)
## sits on the rail; the keypad console stands to the side.
##
## Every peer plays the round from the host's events: &"hand" deals the new
## cards (each flies from the shoe to its spot and flips; the dealer's hole
## card stays face down), &"bet" (the round is over) deals any card the hand
## event never showed (a bust from HIT), flips the hole card, draws the
## dealer's cards one by one, then shows the banner (BUST! / YOU WIN! /
## DEALER BUSTS! / BLACKJACK! / DEALER WINS) and the result. Big outlined
## totals float over both hands and the monitor repeats them.
##
## Machine space: floor at y = 0, the player stands at +Z facing -Z.

const TABLE_TOP := 0.88
const TABLE_R := 1.05
## The straight (dealer) edge of the half moon.
const EDGE_Z := -0.45
const FELT_R := 0.97
const RAIL_R := 1.0
const SHOE_POS := Vector3(0.6, TABLE_TOP, -0.27)
const PLAYER_HAND := Vector3(-0.08, TABLE_TOP, 0.2)
const DEALER_HAND := Vector3(-0.08, TABLE_TOP, -0.2)
const CARD_SIZE := Vector2(0.12, 0.17)
const CARD_SPACING := 0.09
const DEAL_SECONDS := 0.32
const FLIP_SECONDS := 0.22
const SWEEP_SECONDS := 0.35
const RESULT_SECONDS := 1.6
const WOOD := Color("6b3420")
const WOOD_DARK := Color("3e1c12")
const RAIL_COLOR := Color("3a1240")
const GOLD := Color("ffc23d")
const GLASS := Color(0.55, 0.95, 1.0, 0.16)
const TOTAL_WHITE := Color("fff8ec")
const TOTAL_GOLD := Color("ffd23f")
const TOTAL_RED := Color("ff4d5e")

## Divides every animation length (tests speed it up).
var anim_speed: float = 1.0
var player_cards: Array[Card3D] = []
var dealer_cards: Array[Card3D] = []
## Values as dealt so far (the hole card is 0 while face down).
var player_values: Array[int] = []
var dealer_values: Array[int] = []
var hit_key: KeyButton3D
var stand_key: KeyButton3D
var rail_keys: Node3D
var player_total_label: Label3D
var dealer_total_label: Label3D
var banner: Label3D
var monitor: MonitorOnStand
var shoe: Node3D
var quick_keys: Dictionary = {}

var _cards_root: Node3D
var _steps: Array = []
var _step_tween: Tween
var _banner_tween: Tween
## Values queued to be dealt (ahead of player_values / dealer_values).
var _planned_player: Array[int] = []
var _planned_dealer: Array[int] = []
var _planned_hole: bool = false
var _round_open: bool = false
var _round_pid: int = 0
var _round_serial: int = 0
var _result_pending: bool = false
var _shown_bet: int = 0


func _build_game() -> void:
	console.setup("PLAY", DiegeticKit.KEY_GREEN, 40.0)
	_build_table()
	_build_shoe()
	_cards_root = Node3D.new()
	_cards_root.name = "Cards"
	visuals.add_child(_cards_root)
	_build_keys()
	player_total_label = _total_label("PlayerTotal")
	player_total_label.position = PLAYER_HAND + Vector3(0.05, 0.24, 0.02)
	dealer_total_label = _total_label("DealerTotal")
	dealer_total_label.position = DEALER_HAND + Vector3(0.05, 0.3, 0.0)
	banner = ArtKit.make_label("", 0.0019, DiegeticKit.TEXT_WIN, 96, true)
	banner.name = "Banner"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector3(0.0, TABLE_TOP + 0.62, -0.05)
	banner.visible = false
	visuals.add_child(banner)
	monitor = add_monitor(Transform3D(Basis(Vector3.UP, 0.42), Vector3(-1.12, 0.0, -0.5)), Vector2(0.84, 0.48), 1.55, 3)
	_show_idle()
	spawn_dealer(Vector3(0.0, 0.0, EDGE_Z - 0.42), PI)
	set_footprint(Vector3(TABLE_R * 2.0 + 0.1, 0.95, TABLE_R + 0.12), Vector3(0.0, 0.475, EDGE_Z + TABLE_R * 0.5))
	set_play_spot(Vector3(0.0, 0.0, 1.02))
	set_label_height(2.6)
	pop_point = Vector3(0.0, 2.1, -0.2)


func is_dealing() -> bool:
	return not _steps.is_empty() or (_step_tween != null and _step_tween.is_valid() and _step_tween.is_running())


## The totals floating over the hands ("" while hidden).
func player_total_text() -> String:
	return player_total_label.text if player_total_label.visible else ""


func dealer_total_text() -> String:
	return dealer_total_label.text if dealer_total_label.visible else ""


func banner_text() -> String:
	return banner.text if banner.visible else ""


## Snaps every queued deal / reveal to its end (tests).
func finish_animations() -> void:
	var guard := 0
	while is_dealing() and guard < 64:
		guard += 1
		if _step_tween != null and _step_tween.is_valid():
			_step_tween.custom_step(1000.0)
		for c: Card3D in player_cards + dealer_cards:
			c.finish()


# --- GameMachine overrides --------------------------------------------------------

func _on_main(bet: int, _throw: bool, pid: int) -> void:
	if in_round(pid) or (_round_open and _round_pid == pid):
		console.show_message("HIT or STAND?", DiegeticKit.TEXT_INFO)
		return
	request_start_round(pid, bet)


func _on_hand(data: Dictionary) -> void:
	super(data)
	var state: Dictionary = data.get("state", {}) if data.get("state") is Dictionary else {}
	if StringName(str(state.get("kind", ""))) != &"blackjack":
		return
	var pid := int(data.get("pid", 0))
	var pc := _ints(state.get("player_cards", []))
	var dc := _ints(state.get("dealer_cards", []))
	if not _round_open:
		_open_round(pid, int(state.get("bet", 0)), pc, dc)
	else:
		for i in range(_planned_player.size(), pc.size()):
			_queue_deal(true, pc[i], true)
	_queue(_after_hand, 0.0)
	_animating = true
	_refresh_lock()
	_run_steps()


func _on_bet(data: Dictionary) -> void:
	var result: Dictionary = data.get("result", {}) if data.get("result") is Dictionary else {}
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	var pc := _ints(detail.get("player_cards", []))
	var dc := _ints(detail.get("dealer_cards", []))
	if not _round_open:
		_open_round(int(result.get("pid", 0)), int(result.get("bet", 0)), pc.slice(0, 2), dc.slice(0, 1))
	for i in range(_planned_player.size(), pc.size()):
		_queue_deal(true, pc[i], true)
	if dc.size() > 1:
		if _planned_hole:
			_queue(_reveal_hole.bind(dc[1]), FLIP_SECONDS + 0.12)
			_planned_hole = false
			_planned_dealer[1] = dc[1]
		for i in range(_planned_dealer.size(), dc.size()):
			_queue_deal(false, dc[i], true)
	_round_open = false
	_result_pending = true
	_queue(_show_result.bind(result), RESULT_SECONDS)
	_queue(_finish_result.bind(result), 0.0)
	_run_steps()


func _on_occupants_changed() -> void:
	_refresh_rail()


func _on_closed_changed(_value: bool) -> void:
	_refresh_rail()


# --- Presses --------------------------------------------------------------------

func _on_hit(pid: int) -> void:
	if not _press_ok(pid, hit_key):
		return
	if not in_round(pid):
		console.show_message("Press PLAY to deal", DiegeticKit.TEXT_INFO)
		hit_key.play_nope()
		return
	request_hit(pid)


func _on_stand(pid: int) -> void:
	if not _press_ok(pid, stand_key):
		return
	if not in_round(pid):
		console.show_message("Press PLAY to deal", DiegeticKit.TEXT_INFO)
		stand_key.play_nope()
		return
	request_hand_stand(pid)


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


# --- Round steps ------------------------------------------------------------------

func _open_round(pid: int, bet: int, pc: Array[int], dc: Array[int]) -> void:
	_round_open = true
	_round_pid = pid
	_round_serial += 1
	_shown_bet = bet
	if not player_cards.is_empty() or not dealer_cards.is_empty():
		_queue(_sweep, SWEEP_SECONDS + 0.05)
	_planned_player.clear()
	_planned_dealer.clear()
	_planned_hole = false
	_queue(_start_round_look, 0.0)
	if pc.size() > 0:
		_queue_deal(true, pc[0], true)
	if dc.size() > 0:
		_queue_deal(false, dc[0], true)
	if pc.size() > 1:
		_queue_deal(true, pc[1], true)
	_queue_deal(false, 0, false)
	_planned_hole = true


func _queue_deal(to_player: bool, value: int, face_up: bool) -> void:
	if to_player:
		_planned_player.append(value)
	else:
		_planned_dealer.append(value)
	_queue(_deal.bind(to_player, value, face_up), DEAL_SECONDS + (FLIP_SECONDS if face_up else 0.0) + 0.04)


func _queue(step: Callable, seconds: float) -> void:
	_steps.append([step, seconds])


func _run_steps() -> void:
	if _step_tween != null and _step_tween.is_valid() and _step_tween.is_running():
		return
	_next_step()


func _next_step() -> void:
	if _steps.is_empty():
		_steps_done()
		return
	var s: Array = _steps.pop_front()
	(s[0] as Callable).call()
	var seconds := float(s[1]) / maxf(anim_speed, 0.01)
	if not is_inside_tree() or seconds <= 0.0:
		_next_step()
		return
	_step_tween = create_tween()
	_step_tween.tween_interval(seconds)
	_step_tween.tween_callback(_next_step)


func _steps_done() -> void:
	if _dealer_ok():
		dealer.set_pose(&"idle")
	if not _result_pending:
		_animating = false
		_refresh_lock()


func _start_round_look() -> void:
	_hide_banner()
	player_values.clear()
	dealer_values.clear()
	_update_totals()
	if _dealer_ok():
		dealer.set_pose(&"wave")
	_set_lines([{"text": "DEALING...", "color": DiegeticKit.TEXT_WHITE, "size": 0.08},
			{"text": "Bet %s" % DiegeticKit.money_short(_shown_bet), "color": DiegeticKit.TEXT_MONEY, "size": 0.055},
			{"text": "Beat the dealer without busting", "color": DiegeticKit.TEXT_INFO, "size": 0.04}])


## One card flies from the shoe to its spot (and flips when face up).
func _deal(to_player: bool, value: int, face_up: bool) -> void:
	var hand: Array[Card3D] = player_cards if to_player else dealer_cards
	var index := hand.size()
	var salt := _round_serial * 31 + index * 7 + (0 if to_player else 500)
	var card := Card3D.new()
	card.setup(Card3D.blackjack_rank(value, salt) if value > 0 else "A", Card3D.suit_for(value, salt), false, CARD_SIZE)
	card.name = ("P%d" if to_player else "D%d") % index
	_cards_root.add_child(card)
	card.transform = _shoe_mouth()
	hand.append(card)
	if to_player:
		player_values.append(value)
	else:
		dealer_values.append(value if face_up else 0)
	var target := _card_spot(to_player, index)
	var seconds := DEAL_SECONDS / maxf(anim_speed, 0.01)
	if not is_inside_tree():
		card.transform = target
		card.set_face_up(face_up)
		_update_totals()
		return
	card.deal_to(global_transform * target, seconds, 0.14)
	if face_up:
		card.dealt.connect(_flip_dealt.bind(card), CONNECT_ONE_SHOT)
	else:
		card.dealt.connect(_update_totals, CONNECT_ONE_SHOT)


func _flip_dealt(card: Card3D) -> void:
	if not is_instance_valid(card):
		return
	card.flip(true, FLIP_SECONDS / maxf(anim_speed, 0.01))
	card.flipped.connect(func(_up: bool) -> void: _update_totals(), CONNECT_ONE_SHOT)


func _reveal_hole(value: int) -> void:
	if dealer_cards.size() < 2:
		_deal(false, value, true)
		return
	var hole := dealer_cards[1]
	var salt := _round_serial * 31 + 7 + 500
	hole.set_card(Card3D.blackjack_rank(value, salt), Card3D.suit_for(value, salt))
	dealer_values[1] = value
	if not is_inside_tree():
		hole.set_face_up(true)
		_update_totals()
		return
	hole.flip(true, FLIP_SECONDS / maxf(anim_speed, 0.01))
	hole.flipped.connect(func(_up: bool) -> void: _update_totals(), CONNECT_ONE_SHOT)


## Old cards slide off toward the dealer and vanish.
func _sweep() -> void:
	var old: Array[Card3D] = []
	old.append_array(player_cards)
	old.append_array(dealer_cards)
	player_cards.clear()
	dealer_cards.clear()
	player_values.clear()
	dealer_values.clear()
	_update_totals()
	for c: Card3D in old:
		if not is_inside_tree():
			c.queue_free()
			continue
		c.finish()
		var tw := c.create_tween()
		tw.tween_property(c, "position", Vector3(0.35, TABLE_TOP + 0.01, EDGE_Z + 0.08), SWEEP_SECONDS / maxf(anim_speed, 0.01)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "scale", Vector3.ONE * 0.3, SWEEP_SECONDS / maxf(anim_speed, 0.01))
		tw.tween_callback(c.queue_free)


func _after_hand() -> void:
	var p := BlackjackRound.hand_total(player_values)
	var d := BlackjackRound.hand_total(dealer_values.filter(func(v: int) -> bool: return v > 0))
	_set_lines([{"text": "YOU %d · DEALER %d" % [p, d], "color": DiegeticKit.TEXT_WHITE, "size": 0.075},
			{"text": "HIT or STAND?", "color": DiegeticKit.TEXT_INFO, "size": 0.06},
			{"text": "Bet %s · Blackjack pays %sx" % [DiegeticKit.money_short(_shown_bet), _mult_text()], "color": DiegeticKit.TEXT_MONEY, "size": 0.04}])


func _show_result(result: Dictionary) -> void:
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	var won := bool(result.get("won", false))
	var p := int(detail.get("player_total", BlackjackRound.hand_total(player_values)))
	var d := int(detail.get("dealer_total", BlackjackRound.hand_total(dealer_values)))
	var text := "DEALER WINS"
	var color := DiegeticKit.TEXT_LOSE
	if bool(detail.get("player_bust", p > 21)):
		text = "BUST!"
	elif won and bool(detail.get("dealer_bust", d > 21)):
		text = "DEALER BUSTS!"
		color = DiegeticKit.TEXT_WIN
	elif won and p == BlackjackRound.BLACKJACK and _ints(detail.get("player_cards", [])).size() == 2:
		text = "BLACKJACK!"
		color = TOTAL_GOLD
	elif won:
		text = "YOU WIN!"
		color = DiegeticKit.TEXT_WIN
	elif int(result.get("net", -1)) == 0:
		text = "PUSH"
		color = DiegeticKit.TEXT_WHITE
	_show_banner(text, color)
	var tc := GameMachine.result_text(result)
	_set_lines([{"text": "YOU %d · DEALER %d" % [p, d], "color": DiegeticKit.TEXT_WHITE, "size": 0.075},
			{"text": str(tc[0]), "color": tc[1], "size": 0.08},
			{"text": text, "color": color, "size": 0.045}])
	monitor.screen.flash(tc[1], 0.6, 0.5)
	if won:
		_burst(Vector3(PLAYER_HAND.x + 0.1, TABLE_TOP + 0.15, PLAYER_HAND.z), text == "BLACKJACK!")
		if _dealer_ok():
			dealer.set_pose(&"shrug")
	else:
		flash(DiegeticKit.TEXT_LOSE, 1.8, 0.5)
		if _dealer_ok():
			dealer.set_pose(&"chip_flip")


func _finish_result(result: Dictionary) -> void:
	_result_pending = false
	_end_result(result)
	if _dealer_ok():
		dealer.set_pose(&"idle")


# --- Look -----------------------------------------------------------------------

func _update_totals() -> void:
	_set_total(player_total_label, player_values)
	_set_total(dealer_total_label, dealer_values.filter(func(v: int) -> bool: return v > 0))


func _set_total(label: Label3D, values: Array) -> void:
	if values.is_empty():
		label.visible = false
		return
	var t := BlackjackRound.hand_total(values)
	label.text = str(t)
	label.modulate = TOTAL_RED if t > BlackjackRound.BLACKJACK else (TOTAL_GOLD if t == BlackjackRound.BLACKJACK else TOTAL_WHITE)
	label.visible = true


func _show_banner(text: String, color: Color) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.text = text
	banner.modulate = color
	banner.visible = true
	if not is_inside_tree():
		return
	banner.scale = Vector3.ONE * 0.2
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "scale", Vector3.ONE * 1.12, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner, "scale", Vector3.ONE, 0.1)


func _hide_banner() -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.visible = false


func _show_idle() -> void:
	_set_lines([{"text": "BLACKJACK", "color": DiegeticKit.TEXT_WHITE, "size": 0.09},
			{"text": "Wins pay %sx" % _mult_text(), "color": DiegeticKit.TEXT_MONEY, "size": 0.06},
			{"text": "Dealer stands on 17", "color": DiegeticKit.TEXT_INFO, "size": 0.04}])


func _set_lines(entries: Array) -> void:
	if monitor != null:
		monitor.set_lines(entries)


func _refresh_rail() -> void:
	if hit_key == null:
		return
	var open := not closed
	hit_key.enabled = open
	stand_key.enabled = open


func _total_label(node_name: String) -> Label3D:
	var l := ArtKit.make_label("", 0.0016, TOTAL_WHITE, 96, true)
	l.name = node_name
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.outline_size = 30
	l.visible = false
	visuals.add_child(l)
	return l


## Where card `index` of a hand lies (machine space, face up).
func _card_spot(to_player: bool, index: int) -> Transform3D:
	var base := PLAYER_HAND if to_player else DEALER_HAND
	var yaw := 0.07 * sin(float(index) * 2.3 + (0.0 if to_player else 1.0))
	var pos := base + Vector3(float(index) * CARD_SPACING, 0.004 + float(index) * 0.0016, 0.012 * float(index % 2))
	return Transform3D(Basis(Vector3.UP, yaw), pos)


func _shoe_mouth() -> Transform3D:
	var local := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 0.1, 0.12))
	return shoe.transform * local


func _build_table() -> void:
	var base := Primitives.mesh_instance(MeshFactory.extrude(_half_disc(TABLE_R - 0.2, 24), TABLE_TOP - 0.12, 0.02), WOOD_DARK)
	base.name = "Base"
	base.rotation.x = PI * 0.5
	base.position = Vector3(0.0, (TABLE_TOP - 0.12) * 0.5, EDGE_Z + 0.06)
	visuals.add_child(base)
	var top := Primitives.mesh_instance(MeshFactory.extrude(_half_disc(TABLE_R, 40), 0.07, 0.02), WOOD)
	top.name = "Top"
	top.rotation.x = PI * 0.5
	top.position = Vector3(0.0, TABLE_TOP - 0.035, EDGE_Z)
	visuals.add_child(top)
	var felt := ArtKit.mesh_instance(_half_disc_mesh(FELT_R, 48),
			ArtKit.felt_material(ArtPalette.FELT_GREEN, GOLD, Vector2(FELT_R, FELT_R) * 1.0, 0.1, 1))
	felt.name = "Felt"
	felt.position = Vector3(0.0, TABLE_TOP + 0.002, EDGE_Z)
	visuals.add_child(felt)
	var rail := Primitives.mesh_instance(_arc_tube(RAIL_R, 0.06, 0.0, PI, 40, 12), RAIL_COLOR)
	rail.name = "Rail"
	rail.position = Vector3(0.0, TABLE_TOP + 0.02, EDGE_Z)
	visuals.add_child(rail)
	for sx: float in [-1.0, 1.0]:
		var cap := Primitives.mesh_instance(MeshFactory.ball(0.06, 3), RAIL_COLOR)
		cap.position = Vector3(sx * RAIL_R, TABLE_TOP + 0.02, EDGE_Z)
		visuals.add_child(cap)
	var trim := Primitives.pill(TABLE_R * 2.0 - 0.1, 0.022, GOLD, 0.15)
	trim.name = "EdgeTrim"
	trim.position = Vector3(0.0, TABLE_TOP + 0.01, EDGE_Z + 0.02)
	visuals.add_child(trim)
	var neon := ArtKit.mesh_instance(_arc_tube(TABLE_R + 0.005, 0.012, 0.0, PI, 40, 6), ArtKit.neon_material(accent.lightened(0.15), 2.2))
	neon.name = "Neon"
	neon.position = Vector3(0.0, TABLE_TOP - 0.075, EDGE_Z)
	visuals.add_child(neon)
	# Instruction plaque printed on the felt, like the reference's sign.
	var plaque := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(0.74, 0.008, 0.075), 0.02, 2), Color("0e5e35"), 0.0, false)
	plaque.name = "Plaque"
	plaque.position = Vector3(-0.02, TABLE_TOP + 0.006, 0.0)
	visuals.add_child(plaque)
	var words := DiegeticKit.text_label("BEAT THE DEALER WITHOUT BUSTING 21", 0.03, Color("ffe08a"), 0)
	words.name = "PlaqueText"
	words.rotation.x = -PI * 0.5
	words.position = Vector3(-0.02, TABLE_TOP + 0.0115, 0.0)
	DiegeticKit.fit_label(words, words.text, 0.03, 0.7)
	visuals.add_child(words)
	var pays := DiegeticKit.text_label("BLACKJACK PAYS %sx · DEALER STANDS ON 17" % _mult_text(), 0.02, Color("ffe08a"), 0)
	pays.name = "PaysText"
	pays.rotation.x = -PI * 0.5
	pays.position = Vector3(-0.02, TABLE_TOP + 0.004, -0.36)
	visuals.add_child(pays)
	# The glass shield the dealer stands behind.
	var glass := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(1.5, 0.78, 0.024), 0.1, 3), GLASS)
	glass.name = "Glass"
	glass.position = Vector3(0.0, TABLE_TOP + 0.3 + 0.39, EDGE_Z - 0.08)
	visuals.add_child(glass)
	var frame := ArtKit.mesh_instance(MeshFactory.stroke(_round_rect(0.75, 0.39, 0.1), 0.024, 0.03), ArtKit.toon_material(GOLD, 0.2, false, true, 0.4))
	frame.name = "GlassFrame"
	frame.position = glass.position
	visuals.add_child(frame)
	for sx: float in [-0.68, 0.68]:
		var post := Primitives.rounded_cylinder(0.02, 0.3, GOLD, 0.008, 12)
		post.position = Vector3(sx, TABLE_TOP + 0.15, EDGE_Z - 0.08)
		visuals.add_child(post)


func _build_shoe() -> void:
	shoe = Node3D.new()
	shoe.name = "Shoe"
	shoe.position = SHOE_POS
	shoe.rotation.y = -0.55
	visuals.add_child(shoe)
	var body_mesh := Primitives.mesh_instance(MeshFactory.wedge(Vector3(0.17, 0.13, 0.26), 0.55, 0.02), Color("8e1630"))
	body_mesh.name = "Body"
	body_mesh.position.y = 0.065
	shoe.add_child(body_mesh)
	var lip := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(0.18, 0.02, 0.05), 0.008, 2), GOLD, 0.15)
	lip.position = Vector3(0.0, 0.075, 0.12)
	shoe.add_child(lip)
	var peek := Card3D.new()
	peek.setup("A", "♠", false, CARD_SIZE * 0.9)
	peek.name = "Peek"
	peek.transform = Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, 0.1, 0.06))
	shoe.add_child(peek)


func _build_keys() -> void:
	rail_keys = Node3D.new()
	rail_keys.name = "RailKeys"
	rail_keys.position = Vector3(0.0, TABLE_TOP + 0.075, EDGE_Z + RAIL_R + 0.05)
	rail_keys.rotation.x = deg_to_rad(16.0)
	visuals.add_child(rail_keys)
	var panel := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(0.82, 0.05, 0.25), 0.035, 3), DiegeticKit.CONSOLE_BODY)
	panel.name = "Panel"
	panel.position.y = 0.0
	rail_keys.add_child(panel)
	var key_size := Vector3(0.23, 0.065, 0.19)
	stand_key = KeyButton3D.new()
	stand_key.setup("STAND", DiegeticKit.KEY_YELLOW, key_size, ACTION_STAND)
	stand_key.position = Vector3(-0.26, 0.025, 0.0)
	stand_key.set_emission(0.15)
	stand_key.pressed.connect(_on_stand)
	rail_keys.add_child(stand_key)
	register_pressable(ACTION_STAND, stand_key)
	hit_key = KeyButton3D.new()
	hit_key.setup("HIT", DiegeticKit.KEY_RED, key_size, ACTION_HIT)
	hit_key.position = Vector3(0.0, 0.025, 0.0)
	hit_key.set_emission(0.15)
	hit_key.pressed.connect(_on_hit)
	rail_keys.add_child(hit_key)
	register_pressable(ACTION_HIT, hit_key)
	_rework_console(rail_keys, Vector3(0.26, 0.025, 0.0), key_size)
	var s := 0.68
	place_console(Transform3D(Basis(Vector3.UP, deg_to_rad(-40.0)).scaled(Vector3.ONE * s), Vector3(0.8, 1.0, 0.52)))
	console.add_stand(1.0 / s)


## The kit console reworked to the console-on-a-stand reference: the main key
## leaves the panel for `main_parent` (the rail) at `main_pos`; the quick
## column becomes MIN ¼ ½ ALL (¼ and ½ of all you can bet now, ALL = all of
## it up to the max). Blackjack throws by hitting past 21, so the THROW key
## gives way to a printed reminder. Returns the main key.
func _rework_console(main_parent: Node3D, main_pos: Vector3, main_size: Vector3) -> KeyButton3D:
	var main := console.main_key
	var slot := main.position
	main.get_parent().remove_child(main)
	main_parent.add_child(main)
	main.setup(console.main_label, DiegeticKit.KEY_GREEN, main_size, &"main")
	main.set_emission(0.15)
	main.position = main_pos
	var tk := console.throw_key
	tk.enabled = false
	tk.visible = false
	tk.collision_layer = 0
	var note := DiegeticKit.text_label("HIT PAST\n21 TO\nTHROW", 0.026, DiegeticKit.TEXT_LOSE, 0)
	note.name = "ThrowNote"
	note.rotation.x = -PI * 0.5
	note.position = slot + Vector3(0.0, 0.002, 0.0)
	console.deck.add_child(note)
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


## Confetti (more on a blackjack) at `at` (machine space) with a green flash.
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


func _dealer_ok() -> bool:
	return dealer != null and is_instance_valid(dealer)


func _mult_text() -> String:
	return ("%.1f" % (1.0 + TableGames.profit_multiple(HR.GameType.BLACKJACK))).trim_suffix(".0")


static func _ints(values: Variant) -> Array[int]:
	var out: Array[int] = []
	if values is Array:
		for v: Variant in values:
			out.append(int(v))
	return out


## A half disc of `radius` in XY (y >= 0), for extruding the table.
static func _half_disc(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments + 1:
		var a := PI * float(i) / float(segments)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts


## A flat half disc on XZ (z >= 0) facing +Y: the felt (object-space XZ for the felt shader).
static func _half_disc_mesh(radius: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array([Vector3.ZERO])
	var normals := PackedVector3Array([Vector3.UP])
	var uvs := PackedVector2Array([Vector2(0.5, 0.0)])
	var indices := PackedInt32Array()
	for i in segments + 1:
		var a := PI * float(i) / float(segments)
		verts.append(Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, sin(a)))
	for i in segments:
		indices.append_array(PackedInt32Array([0, i + 1, i + 2]))
	return _commit(verts, normals, uvs, indices)


## A round tube of radius `tube` along an arc of `radius` on XZ from angle
## a0 to a1 (the padded rail).
static func _arc_tube(radius: float, tube: float, a0: float, a1: float, segments: int, sides: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var a := lerpf(a0, a1, float(i) / float(segments))
		var out := Vector3(cos(a), 0.0, sin(a))
		for j in sides + 1:
			var phi := TAU * float(j) / float(sides)
			var n := out * cos(phi) + Vector3.UP * sin(phi)
			verts.append(out * radius + n * tube)
			normals.append(n)
			uvs.append(Vector2(float(i) / float(segments), float(j) / float(sides)))
	for i in segments:
		for j in sides:
			var a := i * (sides + 1) + j
			var b := a + sides + 1
			indices.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))
	return _commit(verts, normals, uvs, indices)


## Winds every triangle to agree with its normals (Godot's clockwise front faces).
static func _commit(verts: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	for t in range(0, indices.size(), 3):
		var a := verts[indices[t]]
		var cr := (verts[indices[t + 1]] - a).cross(verts[indices[t + 2]] - a)
		var n := normals[indices[t]] + normals[indices[t + 1]] + normals[indices[t + 2]]
		if cr.dot(n) > 0.0:
			var tmp := indices[t + 1]
			indices[t + 1] = indices[t + 2]
			indices[t + 2] = tmp
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _round_rect(hw: float, hh: float, r: float, steps: int = 4) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(hw - r, hh - r), Vector2(-hw + r, hh - r), Vector2(-hw + r, -hh + r), Vector2(hw - r, -hh + r)]
	for i in 4:
		for k in steps + 1:
			var a := PI * 0.5 * float(i) + PI * 0.5 * float(k) / float(steps)
			pts.append((corners[i] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts
