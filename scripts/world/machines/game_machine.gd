class_name GameMachine
extends Node3D
## Base of every physical casino game you walk up to and play with your hands
## (slots, high-low, big wheel, dice, roulette, blackjack). It builds what
## every game shares and talks to the sim only through SimHost:
##
## - a world-layer collision footprint (players and guards walk around it),
## - a play spot: a zone Area3D watching the player layer. When THIS peer's
##   player walks in it requests sit; walking out requests stand (unless
##   they walked into another machine's spot meanwhile),
## - a BetConsole3D whose presses are only acted on for a seated occupant
##   (others see "Occupied" / "Step up to play"),
## - the floating game name, an optional dealer (dealer_swap tints a new one
##   in), a CLOSED sign for the fire alarm and a pop-up result label.
##
## It listens to host.sim_event for its table: seated / stood (occupants, for
## every pid), bet -> _on_bet, hand -> _on_hand, dealer_swap, fire_alarm
## (closed: sign + console locked), chips (pocket), and polls host.snapshot()
## at 4 Hz for min / max / pocket while this peer's player sits here. While a
## request is in flight or a result animates the console is locked and pocket
## changes wait, so the screen never spoils a result. Refusals show on the
## console; a sit refused for a passing reason (too far on the host) retries.
##
## Subclasses override _build_game() (geometry; place the console with
## place_console(), size the footprint with set_footprint(), move the play
## spot with set_play_spot()), _on_main / _on_action (turn presses into
## requests with request_bet / request_start_round / request_guess /
## request_cash_out / request_hit / request_hand_stand), _on_bet / _on_hand /
## _animate_result (animate on every peer) and call _end_result(result) when
## a result animation is over (emits result_shown, unlocks the console). The
## defaults make any game type playable with a generic look (TestMachine).
##
## Machine space: floor at y = 0, the player stands at +Z facing -Z.

signal result_shown(table_id: StringName)
## The first seated player changed (0 = free).
signal occupant_changed(pid: int)

const ACTION_HIGHER := &"higher"
const ACTION_LOWER := &"lower"
const ACTION_CASH_OUT := &"cash_out"
const ACTION_HIT := &"hit"
const ACTION_STAND := &"stand"
## Physics layers as bit values: 1 world, 2 player.
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
## Limits / pocket refresh while this peer's player sits here.
const POLL_SECONDS := 0.25
## A request or animation that never finishes stops locking the console after this.
const LOCK_TIMEOUT_SECONDS := 12.0
## A sit refused for a passing reason (too far on the host, busy) is retried
## this often while the local player still stands in the spot.
const SIT_RETRY_SECONDS := 1.0
const SIT_RETRY_REASONS: Array[StringName] = [&"too_far", &"busy", &"not_connected", &"wrong_zone"]
## The default (generic) result reveal.
const RESULT_SECONDS := 0.9
const POP_HOLD_SECONDS := 1.4
const SWAP_WALK := 1.4
const SWAP_SECONDS := 2.2
const COOL_COLOR := Color(0.45, 0.8, 1.0)
const MAIN_LABELS := {
	HR.GameType.SLOTS: "SPIN", HR.GameType.HIGH_LOW: "PLAY", HR.GameType.BIG_WHEEL: "SPIN",
	HR.GameType.DICE: "ROLL", HR.GameType.ROULETTE: "PLAY", HR.GameType.BLACKJACK: "DEAL",
}
## Requests that lock the console until answered.
const ROUND_REQUESTS: Array[StringName] = [&"place_bet", &"start_high_low", &"start_blackjack",
		&"high_low_guess", &"high_low_cash_out", &"blackjack_hit", &"blackjack_stand"]

## "<host id>:<pid>" -> instance id of the machine whose play spot that
## player entered last (so leaving an older spot doesn't stand them up).
static var _last_zone: Dictionary = {}

var table_id: StringName = &""
var game_type: int = HR.GameType.SLOTS
var area_id: StringName = &""
var rung: int = Tuning.TOP_RUNG
var host: SimHost
## This peer's player.
var local_pid: int = 1
## TableGames.display_name for the rung.
var display_name: String = ""
var accent: Color = ArtPalette.GOLD
## Seated pids at this table (sim order).
var occupants: Array[int] = []
## The first seated pid, 0 when free.
var occupant: int: get = get_occupant
## How many players the play spot seats (the zone won't sit more).
var max_occupants: int = 1
var closed: bool = false
## Optional Callable() -> bool: does a guard see the local player now
## (passed as `in_view` to request_sit for the table-jump rule).
var in_view_provider: Callable = Callable()

var visuals: Node3D
var body: StaticBody3D
var footprint: CollisionShape3D
var play_zone: Area3D
var play_spot: Vector3 = Vector3(0.0, 0.0, 0.95)
## Facing at the play spot (0 = looking toward -Z).
var play_yaw: float = 0.0
var play_radius: float = 0.55
var console: BetConsole3D
var floating_label: FloatingLabel
var monitors: Array[MonitorOnStand] = []
## The dealer, if this game has one (spawn_dealer()).
var dealer: CharacterModel
var dealer_spot: Vector3 = Vector3(0.0, 0.0, -0.9)
var dealer_yaw: float = 0.0
## Where pop-up results and the flash appear (machine space).
var pop_point: Vector3 = Vector3(0.0, 1.9, 0.0)

var _rounds: Dictionary = {}
var _awaiting: StringName = &""
var _awaiting_pid: int = 0
var _animating: bool = false
var _lock_seconds: float = 0.0
var _poll_seconds: float = 0.0
var _local_inside: bool = false
var _sit_pending: bool = false
var _sit_retry: bool = false
## This peer's pocket from events that arrived mid-round (shown once the
## result has played, so the screen never spoils it); -1 = none.
var _pending_pocket: int = -1
var _sit_retry_seconds: float = 0.0
var _pressables: Dictionary = {}
var _closed_sign: Node3D
var _pop_label: Label3D
var _pop_tween: Tween
var _swap_tween: Tween
var _tint_tween: Tween
var _flash_light: OmniLight3D
var _flash_tween: Tween
var _dealer_serial: int = 0
var _zone_shape: CollisionShape3D


func setup(p_table_id: StringName, p_game_type: int, p_area_id: StringName, p_rung: int, p_host: SimHost, p_local_pid: int) -> void:
	_teardown()
	table_id = p_table_id
	game_type = p_game_type
	area_id = p_area_id
	rung = p_rung
	host = p_host
	local_pid = p_local_pid
	name = ("Machine_%s" % String(table_id)).validate_node_name() if table_id != &"" else "Machine"
	display_name = TableGames.display_name(game_type, rung)
	var casino: Dictionary = CasinoLadder.casino(rung)
	accent = casino.get("accent_color", ArtPalette.GOLD)
	_build_base()
	_build_game()
	_build_closed_sign()
	_connect_host()
	_read_snapshot()
	_refresh_status()
	_refresh_lock()


func get_occupant() -> int:
	return occupants[0] if not occupants.is_empty() else 0


func is_occupied_by(pid: int) -> bool:
	return occupants.has(pid)


## Where a player should stand to play and which way to face (-Z of the
## basis looks at the machine), in world space once in the tree.
func get_play_transform() -> Transform3D:
	return _xform() * Transform3D(Basis(Vector3.UP, play_yaw), play_spot)


## World position of a console key, a registered pressable or a game cell
## (`id` as in press_by_id) for bots to aim at; the machine's position if unknown.
func get_aim_point(id: StringName) -> Vector3:
	var node := get_pressable(id)
	if node == null:
		return _aim_point_extra(id)
	if node.has_method(&"aim_point"):
		return node.call(&"aim_point")
	return node.global_position if node.is_inside_tree() else node.position


## The pressable for `id`: a console key (&"main", &"7", &"cash_out"...) or
## one registered with register_pressable().
func get_pressable(id: StringName) -> Node3D:
	if _pressables.has(id):
		var p: Variant = _pressables[id]
		if is_instance_valid(p):
			return p
	if console != null:
		return console.get_key(id)
	return null


## Presses `id` as player `pid` (bots, tests): the same path as a hand press.
func press_by_id(id: StringName, pid: int) -> bool:
	var node := get_pressable(id)
	if node == null or not node.has_method(&"press"):
		return false
	node.call(&"press", pid)
	return true


## Makes a game pressable (lever, roulette cell...) reachable by id.
func register_pressable(id: StringName, node: Node3D) -> void:
	_pressables[id] = node


## Sizes the world-layer collision box (machine space).
func set_footprint(size: Vector3, center: Vector3 = Vector3.ZERO) -> void:
	var box := BoxShape3D.new()
	box.size = size.abs().max(Vector3(0.05, 0.05, 0.05))
	footprint.shape = box
	footprint.position = center if center != Vector3.ZERO else Vector3(0.0, size.y * 0.5, 0.0)


## Moves the play spot (floor point, machine space) and its facing.
func set_play_spot(spot: Vector3, yaw: float = 0.0, radius: float = -1.0) -> void:
	play_spot = Vector3(spot.x, 0.0, spot.z)
	play_yaw = yaw
	if radius > 0.0:
		play_radius = radius
	var cyl := CylinderShape3D.new()
	cyl.radius = play_radius
	cyl.height = 2.0
	_zone_shape.shape = cyl
	play_zone.position = play_spot + Vector3(0.0, 1.0, 0.0)


## Puts the console at `xform` (machine space).
func place_console(xform: Transform3D) -> void:
	if console != null:
		console.transform = xform


func set_label_height(height: float) -> void:
	if floating_label != null:
		floating_label.position = Vector3(0.0, height, floating_label.position.z)


## A monitor on a stand at `xform` (machine space), kept in `monitors`.
func add_monitor(xform: Transform3D, screen_size: Vector2 = Vector2(0.56, 0.34), height: float = 1.0, line_count: int = 2) -> MonitorOnStand:
	var m := MonitorOnStand.new()
	m.name = "Monitor%d" % monitors.size()
	m.setup(screen_size, height, line_count, accent.lightened(0.2))
	m.transform = xform
	visuals.add_child(m)
	monitors.append(m)
	return m


## Spawns the dealer (a CharacterModel in the dealer uniform) at `spot`
## facing `yaw`; dealer_swap() replaces it with a tinted one.
func spawn_dealer(spot: Vector3, yaw: float = 0.0) -> CharacterModel:
	dealer_spot = spot
	dealer_yaw = yaw
	if dealer != null:
		dealer.queue_free()
	dealer = _make_dealer()
	dealer.position = spot
	dealer.rotation.y = yaw
	return dealer


## Fire alarm / closed table: CLOSED sign, console locked with a message.
func set_closed(value: bool) -> void:
	closed = value
	if _closed_sign != null:
		_closed_sign.visible = value
	_on_closed_changed(value)
	_refresh_status()
	_refresh_lock()


func in_round(pid: int) -> bool:
	return _rounds.has(pid)


## The round `pid` has going here (a &"hand" state), or {}.
func round_state(pid: int) -> Dictionary:
	return _rounds.get(pid, {})


func is_waiting() -> bool:
	return _awaiting != &""


func is_animating() -> bool:
	return _animating


## The dealer walks off and a cool-tinted dealer walks in (the readable cue
## that the table cooled); without a dealer the machine flashes cold.
func dealer_swap() -> void:
	pop("NEW DEALER" if dealer != null else "COOLED", COOL_COLOR)
	flash(COOL_COLOR, 2.5)
	if console != null:
		console.show_message("Table cooled", COOL_COLOR)
	if dealer == null:
		return
	_finish_tween(_swap_tween)
	var old := dealer
	var fresh := _make_dealer()
	dealer = fresh
	_tint(fresh)
	var side := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, dealer_yaw) * SWAP_WALK
	if not is_inside_tree():
		old.queue_free()
		fresh.position = dealer_spot
		fresh.rotation.y = dealer_yaw
		return
	var walk := SWAP_SECONDS * 0.4
	old.set_move_speed(SWAP_WALK / walk)
	fresh.set_move_speed(SWAP_WALK / walk)
	fresh.position = dealer_spot + side
	fresh.rotation.y = dealer_yaw
	fresh.scale = Vector3.ONE * 0.01
	fresh.visible = false
	var tw := create_tween()
	_swap_tween = tw
	tw.tween_callback(old.set_pose.bind(&"walk"))
	tw.tween_property(old, "position", old.position - side, walk)
	tw.tween_property(old, "scale", Vector3.ONE * 0.01, SWAP_SECONDS * 0.08)
	tw.tween_callback(old.queue_free)
	tw.tween_callback(_dealer_enters.bind(fresh))
	tw.tween_property(fresh, "scale", Vector3.ONE, SWAP_SECONDS * 0.08)
	tw.tween_property(fresh, "position", dealer_spot, walk)
	tw.tween_callback(fresh.set_pose.bind(&"idle"))


## A big billboard caption over the machine ("WIN +$500") that pops and fades.
func pop(text: String, color: Color = DiegeticKit.TEXT_WIN, big: bool = false) -> void:
	if _pop_label == null:
		return
	if _pop_tween != null and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_label.text = text
	_pop_label.pixel_size = 0.0062 if big else 0.0042
	_pop_label.modulate = color
	_pop_label.outline_modulate = ArtKit.OUTLINE_COLOR
	_pop_label.position = pop_point
	_pop_label.visible = true
	if not is_inside_tree():
		return
	_pop_label.scale = Vector3.ONE * 0.3
	_pop_tween = create_tween()
	_pop_tween.tween_property(_pop_label, "scale", Vector3.ONE * 1.15, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tween.tween_property(_pop_label, "scale", Vector3.ONE, 0.1)
	_pop_tween.parallel().tween_property(_pop_label, "position", pop_point + Vector3(0.0, 0.18, 0.0), POP_HOLD_SECONDS)
	_pop_tween.tween_property(_pop_label, "modulate:a", 0.0, 0.3)
	_pop_tween.parallel().tween_property(_pop_label, "outline_modulate:a", 0.0, 0.3)
	_pop_tween.tween_callback(_pop_label.hide)


func get_pop_text() -> String:
	return _pop_label.text if _pop_label != null and _pop_label.visible else ""


## A colored light burst at the pop point.
func flash(color: Color, energy: float = 3.0, seconds: float = 0.6) -> void:
	if _flash_light == null or not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_light.light_color = color
	_flash_light.visible = true
	_flash_light.light_energy = energy
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_light, "light_energy", 0.0, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(_flash_light.hide)


## "WIN +$90" / "LOSE -$10" / "JACKPOT! +$5,000" and its color for a BetResult dict.
static func result_text(result: Dictionary) -> Array:
	var won := bool(result.get("won", false))
	var net := int(result.get("net", 0))
	var bet := int(result.get("bet", 0))
	var detail: Dictionary = result.get("detail", {}) if result.get("detail") is Dictionary else {}
	if bool(detail.get("cash_out", false)) and not detail.has("next_card"):
		return ["CASHED +%s" % DiegeticKit.money_short(net) if net > 0 else "EVEN", DiegeticKit.TEXT_WIN if net > 0 else DiegeticKit.TEXT_WHITE]
	if won:
		if bool(result.get("jackpot", false)):
			return ["JACKPOT! +%s" % DiegeticKit.money_short(net), DiegeticKit.TEXT_MONEY]
		if int(result.get("payout", 0)) > 0:
			return [("BIG WIN +%s" if bool(result.get("loud", false)) else "WIN +%s") % DiegeticKit.money_short(net), DiegeticKit.TEXT_WIN]
		if detail.has("pot"):
			return ["POT %s" % DiegeticKit.money_short(int(detail["pot"])), DiegeticKit.TEXT_WIN]
		return ["WIN", DiegeticKit.TEXT_WIN]
	if bool(result.get("intentional_loss", false)):
		return ["THROWN -%s" % DiegeticKit.money_short(bet), DiegeticKit.TEXT_LOSE]
	return ["LOSE -%s" % DiegeticKit.money_short(bet) if bet > 0 else "LOSE", DiegeticKit.TEXT_LOSE]


# --- Requests (the only way presses reach the sim) ---------------------------

## place_bet for slots, big wheel, dice and roulette.
func request_bet(pid: int, amount: int, choice: Dictionary = {}) -> void:
	if not _begin_wait(&"place_bet", pid):
		return
	host.request_place_bet(pid, table_id, amount, choice)


## start_high_low / start_blackjack by game type.
func request_start_round(pid: int, amount: int) -> void:
	var req := &"start_blackjack" if game_type == HR.GameType.BLACKJACK else &"start_high_low"
	if not _begin_wait(req, pid):
		return
	if req == &"start_blackjack":
		host.request_start_blackjack(pid, table_id, amount)
	else:
		host.request_start_high_low(pid, table_id, amount)


func request_guess(pid: int, higher: bool, throw: bool = false) -> void:
	if _begin_wait(&"high_low_guess", pid):
		host.request_high_low_guess(pid, higher, throw)


func request_cash_out(pid: int) -> void:
	if _begin_wait(&"high_low_cash_out", pid):
		host.request_high_low_cash_out(pid)


func request_hit(pid: int) -> void:
	if _begin_wait(&"blackjack_hit", pid):
		host.request_blackjack_hit(pid)


func request_hand_stand(pid: int) -> void:
	if _begin_wait(&"blackjack_stand", pid):
		host.request_blackjack_stand(pid)


# --- Overridables --------------------------------------------------------------

## Builds the game's geometry under `visuals`; place the console, footprint,
## play spot, label height and any dealer / monitors / action keys here.
func _build_game() -> void:
	pass


## The main key (PLAY / SPIN / ROLL / DEAL) from a seated player.
func _on_main(bet: int, throw: bool, pid: int) -> void:
	match game_type:
		HR.GameType.HIGH_LOW:
			if in_round(pid):
				console.show_message("HIGHER or LOWER?")
			else:
				request_start_round(pid, bet)
		HR.GameType.BLACKJACK:
			if in_round(pid):
				console.show_message("HIT or STAND?")
			else:
				request_start_round(pid, bet)
		_:
			request_bet(pid, bet, default_choice(throw))


## An action key from a seated player.
func _on_action(id: StringName, pid: int) -> void:
	var throw := console.throw_armed
	match id:
		ACTION_HIGHER, ACTION_LOWER:
			if throw:
				console.set_throw(false)
			request_guess(pid, id == ACTION_HIGHER, throw)
		ACTION_CASH_OUT:
			request_cash_out(pid)
		ACTION_HIT:
			request_hit(pid)
		ACTION_STAND:
			request_hand_stand(pid)


## The bet choice for a plain main press (roulette on red, dice on high).
func default_choice(throw: bool) -> Dictionary:
	var c := {"throw": throw}
	match game_type:
		HR.GameType.ROULETTE:
			c["kind"] = "color"
			c["color"] = "red"
		HR.GameType.DICE:
			c["call"] = "high"
	return c


## A `bet` event at this table (any pid): animate it. The default plays the
## generic reveal; call _end_result(result) when your animation ends.
func _on_bet(data: Dictionary) -> void:
	_animate_result(data.get("result", {}))


## A `hand` event at this table (any pid): show the round in progress.
func _on_hand(data: Dictionary) -> void:
	var pid := int(data.get("pid", 0))
	if pid == local_pid or occupants.has(pid):
		_refresh_status()


## Plays a BetResult dict; the default shows it on the screen and the pop label.
func _animate_result(result: Dictionary) -> void:
	if not is_inside_tree():
		_end_result(result)
		return
	var tw := create_tween()
	tw.tween_interval(RESULT_SECONDS)
	tw.tween_callback(_end_result.bind(result))


## A request this machine sent was answered (after the base handled refusals).
func _on_request_result(_request: StringName, _args: Array, _result: Dictionary) -> void:
	pass


## The seated set changed.
func _on_occupants_changed() -> void:
	pass


func _on_closed_changed(_value: bool) -> void:
	pass


## Aim point for ids the machine resolves itself (cells without a pressable).
func _aim_point_extra(_id: StringName) -> Vector3:
	return global_position if is_inside_tree() else position


## Ends a result animation: caption on the screen and pop label, then
## result_shown (which unlocks the console).
func _end_result(result: Dictionary) -> void:
	var tc := result_text(result)
	var pid := int(result.get("pid", 0))
	if pid == local_pid or occupants.has(pid):
		console.show_message(str(tc[0]), tc[1])
	pop(str(tc[0]), tc[1], bool(result.get("loud", false)) and bool(result.get("won", false)))
	if bool(result.get("won", false)) and int(result.get("payout", 0)) > 0:
		flash(tc[1], 4.0 if bool(result.get("loud", false)) else 2.0)
	result_shown.emit(table_id)


# --- Internals -----------------------------------------------------------------

func _xform() -> Transform3D:
	return global_transform if is_inside_tree() else transform


func _teardown() -> void:
	if host != null:
		if host.sim_event.is_connected(_on_sim_event):
			host.sim_event.disconnect(_on_sim_event)
		if host.request_done.is_connected(_on_request_done):
			host.request_done.disconnect(_on_request_done)
	for tw: Tween in [_pop_tween, _swap_tween, _tint_tween, _flash_tween]:
		if tw != null and tw.is_valid():
			tw.kill()
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	occupants.clear()
	monitors.clear()
	_rounds.clear()
	_pressables.clear()
	dealer = null
	_awaiting = &""
	_animating = false
	closed = false


func _build_base() -> void:
	visuals = Node3D.new()
	visuals.name = "Visuals"
	add_child(visuals)
	body = StaticBody3D.new()
	body.name = "Footprint"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	footprint = CollisionShape3D.new()
	footprint.name = "Shape"
	body.add_child(footprint)
	add_child(body)
	set_footprint(Vector3(1.2, 1.4, 0.8))
	play_zone = Area3D.new()
	play_zone.name = "PlayZone"
	play_zone.collision_layer = 0
	play_zone.collision_mask = PLAYER_LAYER
	play_zone.monitoring = true
	play_zone.monitorable = false
	_zone_shape = CollisionShape3D.new()
	_zone_shape.name = "Shape"
	play_zone.add_child(_zone_shape)
	add_child(play_zone)
	play_zone.body_entered.connect(_on_zone_entered)
	play_zone.body_exited.connect(_on_zone_exited)
	set_play_spot(play_spot, play_yaw, play_radius)
	console = BetConsole3D.new()
	console.name = "Console"
	console.setup(str(MAIN_LABELS.get(game_type, "PLAY")))
	console.gate = _gate
	console.main_pressed.connect(_on_console_main)
	console.action_pressed.connect(_on_console_action)
	console.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, 0.42))
	add_child(console)
	floating_label = FloatingLabel.new()
	floating_label.setup(display_name)
	floating_label.position = Vector3(0.0, 2.45, 0.0)
	add_child(floating_label)
	_pop_label = ArtKit.make_label("", 0.0042, DiegeticKit.TEXT_WIN, 64, true)
	_pop_label.name = "Pop"
	_pop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pop_label.visible = false
	add_child(_pop_label)
	_flash_light = OmniLight3D.new()
	_flash_light.name = "Flash"
	_flash_light.omni_range = 4.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	_flash_light.position = pop_point
	add_child(_flash_light)
	if not result_shown.is_connected(_on_self_result_shown):
		result_shown.connect(_on_self_result_shown)


func _build_closed_sign() -> void:
	_closed_sign = Node3D.new()
	_closed_sign.name = "ClosedSign"
	add_child(_closed_sign)
	var z := play_spot.z + 0.15
	for sx: float in [-0.55, 0.55]:
		var post := Primitives.rounded_cylinder(0.035, 0.9, ArtPalette.GOLD, 0.012, 10)
		post.position = Vector3(play_spot.x + sx, 0.45, z)
		_closed_sign.add_child(post)
		var foot := Primitives.rounded_cylinder(0.13, 0.04, ArtPalette.GOLD, 0.012, 14)
		foot.position = Vector3(play_spot.x + sx, 0.02, z)
		_closed_sign.add_child(foot)
	var rope := Primitives.pill(1.12, 0.024, DiegeticKit.KEY_RED.darkened(0.25))
	rope.position = Vector3(play_spot.x, 0.84, z)
	_closed_sign.add_child(rope)
	var plaque := Primitives.mesh_instance(MeshFactory.rounded_box(Vector3(0.5, 0.18, 0.03), 0.03, 2), DiegeticKit.KEY_RED)
	plaque.name = "Plaque"
	plaque.position = Vector3(play_spot.x, 0.72, z + 0.02)
	_closed_sign.add_child(plaque)
	var sign_label := DiegeticKit.text_label("CLOSED", 0.085, DiegeticKit.TEXT_WHITE, 12)
	sign_label.name = "Label"
	sign_label.position = Vector3(0.0, 0.0, 0.017)
	plaque.add_child(sign_label)
	var back_label := DiegeticKit.text_label("CLOSED", 0.085, DiegeticKit.TEXT_WHITE, 12)
	back_label.name = "BackLabel"
	back_label.rotation.y = PI
	back_label.position = Vector3(0.0, 0.0, -0.017)
	plaque.add_child(back_label)
	_closed_sign.visible = closed


func _connect_host() -> void:
	if host == null:
		return
	host.sim_event.connect(_on_sim_event)
	host.request_done.connect(_on_request_done)


func _read_snapshot() -> void:
	if host == null:
		return
	var snap := host.snapshot()
	var tables: Dictionary = snap.get("tables", {}) if snap.get("tables") is Dictionary else {}
	var t: Variant = tables.get(table_id, tables.get(String(table_id)))
	if t is Dictionary:
		for pid: Variant in (t as Dictionary).get("seated", []):
			if not occupants.has(int(pid)):
				occupants.append(int(pid))
		if bool((t as Dictionary).get("closed", false)):
			set_closed(true)
	if bool(snap.get("fire_alarm", false)):
		set_closed(true)
	_apply_limits(snap)


func _poll_limits() -> void:
	if host != null:
		_apply_limits(host.snapshot())


func _apply_limits(snap: Dictionary) -> void:
	var run: Dictionary = snap.get("run", {}) if snap.get("run") is Dictionary else {}
	if run.is_empty():
		return
	var players: Dictionary = snap.get("players", {}) if snap.get("players") is Dictionary else {}
	var ps: Variant = players.get(local_pid)
	var pocket := int((ps as Dictionary).get("pocket", 0)) if ps is Dictionary else console.pocket
	console.set_limits(int(run.get("min_bet", 1)), int(run.get("max_bet", 1)), pocket)


func _process(delta: float) -> void:
	if _awaiting != &"" or _animating:
		_lock_seconds += delta
		if _lock_seconds > LOCK_TIMEOUT_SECONDS:
			_awaiting = &""
			_animating = false
			_refresh_lock()
	if occupants.has(local_pid):
		_sit_retry = false
		_poll_seconds -= delta
		if _poll_seconds <= 0.0 and _awaiting == &"" and not _animating:
			_poll_seconds = POLL_SECONDS
			_poll_limits()
	elif _sit_retry and _local_inside and not _sit_pending:
		_sit_retry_seconds -= delta
		if _sit_retry_seconds <= 0.0:
			_sit_retry = false
			_try_sit(false)


func _gate(pid: int) -> String:
	if closed:
		return "CLOSED"
	if occupants.has(pid):
		return ""
	if occupants.size() >= max_occupants:
		return "Occupied"
	return "Step up to play"


func _begin_wait(request: StringName, pid: int) -> bool:
	if host == null:
		console.show_message("Not open", DiegeticKit.TEXT_LOSE)
		return false
	_awaiting = request
	_awaiting_pid = pid
	_lock_seconds = 0.0
	_refresh_lock()
	return true


func _refresh_lock() -> void:
	if console == null:
		return
	var busy := _awaiting != &"" or _animating
	console.set_locked(closed or busy)
	if not busy and _pending_pocket >= 0:
		console.set_pocket(_pending_pocket)
		_pending_pocket = -1


func _set_local_pocket(value: int) -> void:
	if _awaiting != &"" or _animating:
		_pending_pocket = value
	else:
		console.set_pocket(value)


func _refresh_status() -> void:
	if console == null:
		return
	if closed:
		console.set_status("CLOSED", DiegeticKit.TEXT_LOSE)
		return
	if occupants.has(local_pid):
		var state: Dictionary = _rounds.get(local_pid, {})
		console.set_status(_round_status(state), DiegeticKit.TEXT_INFO)
	elif occupants.size() >= max_occupants:
		console.set_status("Occupied", DiegeticKit.TEXT_WARN)
	else:
		console.set_status("Step up to play", DiegeticKit.TEXT_INFO)


func _round_status(state: Dictionary) -> String:
	match StringName(str(state.get("kind", ""))):
		&"high_low":
			return "Card %s · Pot %s" % [Card3D.rank_text(int(state.get("card", 0))), DiegeticKit.money_short(int(state.get("pot", 0)))]
		&"blackjack":
			var dealer_cards: Array = state.get("dealer_cards", [])
			var up := str(dealer_cards[0]) if not dealer_cards.is_empty() else "?"
			return "You %d · Dealer %s" % [int(state.get("player_total", 0)), up]
	return ""


func _on_console_main(bet: int, throw: bool, pid: int) -> void:
	_on_main(bet, throw, pid)


func _on_console_action(id: StringName, pid: int) -> void:
	_on_action(id, pid)


func _on_self_result_shown(_id: StringName) -> void:
	_animating = false
	_refresh_lock()


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	match kind:
		&"seated":
			var pid := int(data.get("pid", 0))
			if _is_mine(data):
				_add_occupant(pid)
				if pid == local_pid:
					_poll_seconds = 0.0
					if _sit_pending and not _local_inside:
						_sit_pending = false
						host.request_stand(local_pid)
					_sit_pending = false
			elif occupants.has(pid):
				_remove_occupant(pid)
		&"stood":
			if _is_mine(data):
				var pid := int(data.get("pid", 0))
				_rounds.erase(pid)
				_remove_occupant(pid)
		&"player_left":
			_rounds.erase(int(data.get("pid", 0)))
			_remove_occupant(int(data.get("pid", 0)))
		&"bet":
			if _is_mine(data):
				var pid := int(data.get("pid", 0))
				if bool(data.get("round_over", true)):
					_rounds.erase(pid)
				_animating = true
				if pid == local_pid and data.has("pocket"):
					_set_local_pocket(int(data["pocket"]))
				_lock_seconds = 0.0
				_refresh_lock()
				_on_bet(data)
				_refresh_status()
		&"hand":
			if _is_mine(data):
				var pid := int(data.get("pid", 0))
				var state: Dictionary = data.get("state", {}) if data.get("state") is Dictionary else {}
				if bool(state.get("finished", false)):
					_rounds.erase(pid)
				else:
					_rounds[pid] = state.duplicate(true)
				_on_hand(data)
				_refresh_status()
		&"dealer_swap":
			if _is_mine(data):
				dealer_swap()
		&"fire_alarm":
			set_closed(bool(data.get("active", false)))
		&"chips":
			if int(data.get("pid", 0)) == local_pid and data.has("pocket"):
				_set_local_pocket(int(data["pocket"]))
		&"shared_roll":
			if _is_mine(data) and bool(data.get("open", false)):
				console.show_message("CREW ROLL! %ds" % int(ceilf(float(data.get("seconds", 0.0)))), DiegeticKit.TEXT_MONEY)


func _on_request_done(request: StringName, args: Array, result: Dictionary) -> void:
	if args.is_empty():
		return
	var ok := bool(result.get("ok", false))
	var reason := StringName(str(result.get("reason", "")))
	if request == &"sit":
		if int(args[0]) == local_pid and args.size() > 1 and StringName(str(args[1])) == table_id and not ok and reason != SimHost.PENDING:
			_sit_pending = false
			if SIT_RETRY_REASONS.has(reason):
				_sit_retry = true
				_sit_retry_seconds = SIT_RETRY_SECONDS
			else:
				console.show_message(DiegeticKit.reason_text(reason), DiegeticKit.TEXT_LOSE)
		return
	if request != _awaiting or int(args[0]) != _awaiting_pid:
		return
	if reason == SimHost.PENDING:
		return
	_awaiting = &""
	if not ok:
		console.show_message(DiegeticKit.reason_text(reason), DiegeticKit.TEXT_LOSE)
	_refresh_lock()
	_on_request_result(request, args, result)


func _is_mine(data: Dictionary) -> bool:
	return StringName(str(data.get("table_id", ""))) == table_id


func _add_occupant(pid: int) -> void:
	if occupants.has(pid):
		return
	var before := get_occupant()
	occupants.append(pid)
	_on_occupants_changed()
	if get_occupant() != before:
		occupant_changed.emit(get_occupant())
	_refresh_status()


func _remove_occupant(pid: int) -> void:
	if not occupants.has(pid):
		return
	var before := get_occupant()
	occupants.erase(pid)
	_on_occupants_changed()
	if get_occupant() != before:
		occupant_changed.emit(get_occupant())
	_refresh_status()


# --- Play spot -------------------------------------------------------------------

func _zone_key() -> String:
	return "%d:%d" % [host.get_instance_id() if host != null else 0, local_pid]


func _is_local_body(node: Node3D) -> bool:
	var pid: Variant = node.get(&"pid")
	if pid == null and node.has_meta(&"pid"):
		pid = node.get_meta(&"pid")
	if pid == null or int(pid) != local_pid:
		return false
	var is_local: Variant = node.get(&"is_local")
	var puppet: Variant = node.get(&"puppet")
	return (is_local == null or bool(is_local)) and (puppet == null or not bool(puppet))


func _on_zone_entered(node: Node3D) -> void:
	if not _is_local_body(node):
		return
	_local_inside = true
	_last_zone[_zone_key()] = get_instance_id()
	_try_sit(true)


## Asks the host to sit the local player here (if open, free and not already seated).
func _try_sit(announce: bool) -> void:
	if host == null or not _local_inside or int(_last_zone.get(_zone_key(), 0)) != get_instance_id():
		return
	if closed:
		if announce:
			console.show_message("CLOSED", DiegeticKit.TEXT_LOSE)
		return
	if occupants.has(local_pid):
		return
	if occupants.size() >= max_occupants:
		if announce:
			console.show_message("Occupied", DiegeticKit.TEXT_WARN)
		return
	_sit_pending = true
	var in_view := bool(in_view_provider.call()) if in_view_provider.is_valid() else false
	host.request_sit(local_pid, table_id, in_view)


func _on_zone_exited(node: Node3D) -> void:
	if not _is_local_body(node):
		return
	_local_inside = false
	_sit_retry = false
	var key := _zone_key()
	var mine := int(_last_zone.get(key, 0)) == get_instance_id()
	if mine:
		_last_zone.erase(key)
	if host == null or not mine:
		return
	if occupants.has(local_pid):
		host.request_stand(local_pid)


func _exit_tree() -> void:
	var key := _zone_key()
	if int(_last_zone.get(key, 0)) == get_instance_id():
		_last_zone.erase(key)


# --- Dealer ----------------------------------------------------------------------

func _make_dealer() -> CharacterModel:
	var m := CharacterModel.new()
	m.apply_uniform(&"dealer")
	m.appearance_seed = hash(String(table_id)) + _dealer_serial * 7919
	_dealer_serial += 1
	m.name = "Dealer_%d" % _dealer_serial
	visuals.add_child(m)
	return m


func _dealer_enters(model: CharacterModel) -> void:
	if is_instance_valid(model):
		model.visible = true
		model.set_pose(&"walk")


func _tint(model: CharacterModel) -> void:
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(COOL_COLOR, 0.45)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = mat
	model.set_highlight(Color(COOL_COLOR, 0.85))
	if not is_inside_tree():
		return
	_tint_tween = create_tween()
	_tint_tween.tween_method(_tint_step.bind(model, mat), 1.0, 0.0, Tuning.TABLE_DEALER_TINT_SECONDS)
	_tint_tween.tween_callback(_clear_tint.bind(model))


func _tint_step(k: float, model: CharacterModel, mat: StandardMaterial3D) -> void:
	mat.albedo_color = Color(COOL_COLOR, 0.45 * k)
	if is_instance_valid(model):
		model.set_highlight(Color(COOL_COLOR, 0.85 * k))


func _clear_tint(model: CharacterModel) -> void:
	if not is_instance_valid(model):
		return
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	for mi: MeshInstance3D in meshes:
		mi.material_overlay = null
	model.set_highlight(Color(0, 0, 0, 0))


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for c: Node in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)


func _finish_tween(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.custom_step(1000.0)
		tw.kill()
