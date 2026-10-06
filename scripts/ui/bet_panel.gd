class_name BetPanel
extends Control
## The table panel shown while seated (open_for_table). Bet size is clamped to
## the casino's min/max bet and the pocket. Per game:
## - slots, big wheel: one Bet button; dice adds a high/low call; roulette a
##   red/black color or a single number (0-36).
## - high-low: Deal -> Higher / Lower -> Cash out or keep going.
## - blackjack: Deal -> Hit / Stand.
## A "Throw it" toggle loses on purpose (blackjack: hit past 21 instead).
## Keys: Space = bet / deal / cash out, 1 / 2 (/ 3) = choices, Esc / Backspace = leave.
##
## Only calls host.request_*; results come back as host.request_done (right
## away on the host and offline, after a round trip on a co-op client) and the
## sim's &"hand" events. While an answer is outstanding the controls wait.
## bet_resolved / hand_updated let the director animate the TableNode. After a
## round ends the bet button locks for the game's round_seconds ×
## Tuning.UI_RESULT_LOCK_SHARE (notify_result_shown() unlocks early). Opens
## itself on this player's &"seated" event and closes itself when they stand
## up (&"stood"). At a dice table with crew mates seated, bets join one shared
## roll (the host's &"shared_roll" events show who is in).
##
## A refused request shows "REFUSED" and why (refusal_text()) in the result
## row; pressing while the table can't take a bet (closed, ID check,
## settling, waiting) says why in the hint line, and so does an answer that
## never comes.

## The panel opened for a table (also on its own, from this player's &"seated" event).
signal opened(table_id: StringName)
signal bet_resolved(result: Dictionary)
signal hand_updated(state: Dictionary)
signal leave_requested()
signal closed()

const _SUITS: Array[String] = ["♠", "♥", "♦", "♣"]
## Requests this panel makes (their request_done answers are handled here).
const _ROUND_REQUESTS: Array[StringName] = [
	&"place_bet", &"start_high_low", &"high_low_guess", &"high_low_cash_out",
	&"start_blackjack", &"blackjack_hit", &"blackjack_stand",
]
## Give up waiting for an answer after this long (a lost connection).
const _AWAIT_SECONDS := SimHost.SHARED_ROLL_SECONDS + 5.0
## Why a press did nothing stays in the hint line this long.
const _REFUSAL_SECONDS := 3.0

var host: SimHost = null
var pid: int = 1
var table_id: StringName = &""
var game_type: int = -1
## Chips the next bet stakes (clamped to the limits and the pocket).
var bet_amount: int = 0

var panel: PanelContainer
var title_label: Label
var limits_label: Label
## "Dealer swapped" warning: shown while this table is cooled for the player.
var cooled_label: Label
var pocket_label: Label
var main_button: Button
## Choice buttons for keys 1, 2, 3: roulette red/black/number, dice high/low,
## high-low higher/lower, blackjack hit/stand.
var choice_buttons: Array[Button] = []
var number_spin: SpinBox
var throw_toggle: CheckButton
var leave_button: Button
var slider: HSlider
var min_button: Button
var minus_button: Button
var plus_button: Button
var max_button: Button
var amount_label: Label
var result_label: Label
var detail_label: Label
var heat_label: Label
var hint_label: Label
var high_low_card_holder: HBoxContainer
var pot_label: Label
var player_cards_holder: HBoxContainer
var dealer_cards_holder: HBoxContainer
var player_total_label: Label

var _bet_row: HBoxContainer
var _result_row: HBoxContainer
var _choice_row: HBoxContainer
var _high_low_box: HBoxContainer
var _blackjack_box: VBoxContainer
var _flavor_label: Label
var _roulette_kind: String = "color"
var _roulette_color: String = "red"
var _dice_call: String = GameResolver.DICE_CALL_HIGH
## Last &"hand" state for this player ({} when no round is in progress).
var _round: Dictionary = {}
var _lock_left: float = 0.0
var _collecting: bool = false
var _collected_heat: float = 0.0
var _status: int = HR.PlayerStatus.SEATED
var _pocket: int = 0
var _min_bet: int = 1
var _max_bet: int = 1
var _rung: int = Tuning.TOP_RUNG
var _payout_bonus: float = 1.0
var _table_closed: bool = false
var _refresh_left: float = 0.0
var _syncing: bool = false
## Seconds left waiting for the answer to our last request (0 = not waiting).
var _await_left: float = 0.0
## The open shared dice roll at this table ({} if none): {seconds, pids}.
var _shared: Dictionary = {}
## Why the last press did nothing (hint line, for _refusal_left seconds).
var _refusal: String = ""
var _refusal_left: float = 0.0


func _init() -> void:
	name = "BetPanel"
	theme = UiTheme.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	visible = false


func setup(p_host: SimHost, p_pid: int) -> void:
	if host != null and host.sim_event.is_connected(_on_sim_event):
		host.sim_event.disconnect(_on_sim_event)
		host.request_done.disconnect(_on_request_done)
	host = p_host
	pid = p_pid
	if host != null:
		host.sim_event.connect(_on_sim_event)
		host.request_done.connect(_on_request_done)


## Shows the panel for the table the player just sat at.
func open_for_table(p_table_id: StringName, p_game_type: int) -> void:
	table_id = p_table_id
	game_type = p_game_type
	_lock_left = 0.0
	_await_left = 0.0
	_shared = {}
	_round = {}
	_refusal_left = 0.0
	_status = HR.PlayerStatus.SEATED
	result_label.text = ""
	detail_label.text = ""
	heat_label.text = ""
	throw_toggle.button_pressed = false
	_read_snapshot()
	_resume_round()
	# Cooling is per player and per table; a client learns it from &"dealer_swap".
	var sim: FloorSim = host.current_sim() if host != null else null
	var t: TableState = sim.table(table_id) if sim != null else null
	cooled_label.visible = t != null and t.is_cooled(pid)
	if bet_amount <= 0:
		bet_amount = _min_bet
	_clamp_bet()
	_configure_game()
	visible = true
	_update_controls()
	opened.emit(table_id)


## Hides the panel and emits closed() (once).
func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func is_locked() -> bool:
	return _lock_left > 0.0


## True while a request is waiting for the host's answer.
func is_waiting() -> bool:
	return _await_left > 0.0


## The table finished animating the result: unlock the bet button now.
func notify_result_shown() -> void:
	_lock_left = 0.0
	_update_controls()


## The round in progress ({} when none): the last &"hand" state.
func round_state() -> Dictionary:
	return _round


func set_bet_amount(amount: int) -> void:
	bet_amount = amount
	_clamp_bet()
	_update_controls()


## Space: bet (single-shot games), deal (high-low, blackjack) or cash out (high-low run).
func press_main() -> void:
	if not _can_play():
		_explain_blocked()
		return
	match game_type:
		HR.GameType.HIGH_LOW:
			if _round.is_empty():
				_start_high_low()
			else:
				_cash_out_high_low()
		HR.GameType.BLACKJACK:
			if _round.is_empty():
				_start_blackjack()
		_:
			_place_bet()


## Keys 1 / 2 / 3: index 0, 1, 2 of the game's choices.
func press_choice(index: int) -> void:
	match game_type:
		HR.GameType.ROULETTE:
			if index == 0 or index == 1:
				_roulette_kind = "color"
				_roulette_color = "red" if index == 0 else "black"
			elif index == 2:
				_roulette_kind = "number"
			_update_controls()
		HR.GameType.DICE:
			if index == 0 or index == 1:
				_dice_call = GameResolver.DICE_CALL_HIGH if index == 0 else GameResolver.DICE_CALL_LOW
			_update_controls()
		HR.GameType.HIGH_LOW:
			if (index == 0 or index == 1) and not _round.is_empty():
				if not _can_play():
					_explain_blocked()
				else:
					_guess(index == 0)
		HR.GameType.BLACKJACK:
			if (index == 0 or index == 1) and not _round.is_empty():
				if not _can_play():
					_explain_blocked()
				elif index == 0:
					_hit()
				else:
					_stand()


func request_leave() -> void:
	leave_requested.emit()


## Keyboard shortcuts; true if the key was used. Ignores keys while the
## player isn't seated (an ID check owns 1/2/3 then).
func handle_key(keycode: Key) -> bool:
	if not visible or _status != HR.PlayerStatus.SEATED:
		return false
	match keycode:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			press_main()
		KEY_1, KEY_KP_1:
			press_choice(0)
		KEY_2, KEY_KP_2:
			press_choice(1)
		KEY_3, KEY_KP_3:
			press_choice(2)
		KEY_ESCAPE, KEY_BACKSPACE:
			request_leave()
		KEY_UP, KEY_RIGHT, KEY_EQUAL, KEY_KP_ADD:
			_step_bet(1)
		KEY_DOWN, KEY_LEFT, KEY_MINUS, KEY_KP_SUBTRACT:
			_step_bet(-1)
		_:
			return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		var code: Key = key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if handle_key(code):
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	advance(delta)


## Lock countdown and periodic snapshot refresh (called from _process).
func advance(delta: float) -> void:
	if not visible:
		return
	if _lock_left > 0.0:
		_lock_left -= delta
		if _lock_left <= 0.0:
			_lock_left = 0.0
			_update_controls()
	if _refusal_left > 0.0:
		_refusal_left -= delta
		if _refusal_left <= 0.0:
			_refusal_left = 0.0
			_update_controls()
	if _await_left > 0.0:
		_await_left -= delta
		if _await_left <= 0.0:
			_await_left = 0.0
			_end_collect()
			_refuse("No answer from the dealer. Try again.")
	if not _shared.is_empty():
		_shared["seconds"] = maxf(0.0, float(_shared.get("seconds", 0.0)) - delta)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = Tuning.UI_REFRESH_SECONDS
		_read_snapshot()
		_update_controls()


# --- Requests -----------------------------------------------------------------

func _place_bet() -> void:
	var choice := {"throw": throw_toggle.button_pressed}
	if game_type == HR.GameType.ROULETTE:
		choice["kind"] = _roulette_kind
		if _roulette_kind == "number":
			choice["number"] = int(number_spin.value)
		else:
			choice["color"] = _roulette_color
	elif game_type == HR.GameType.DICE:
		choice["call"] = _dice_call
	_begin_collect()
	host.request_place_bet(pid, table_id, bet_amount, choice)


func _start_high_low() -> void:
	_begin_collect()
	host.request_start_high_low(pid, table_id, bet_amount)


func _guess(higher: bool) -> void:
	_begin_collect()
	host.request_high_low_guess(pid, higher, throw_toggle.button_pressed)


func _cash_out_high_low() -> void:
	_begin_collect()
	host.request_high_low_cash_out(pid)


func _start_blackjack() -> void:
	_begin_collect()
	host.request_start_blackjack(pid, table_id, bet_amount)


func _hit() -> void:
	_begin_collect()
	host.request_blackjack_hit(pid)


func _stand() -> void:
	_begin_collect()
	host.request_blackjack_stand(pid)


## The host answered one of our table requests (on the host: during the call).
func _on_request_done(request: StringName, args: Array, res: Dictionary) -> void:
	if not _ROUND_REQUESTS.has(request) or args.is_empty() or int(args[0]) != pid:
		return
	var heat := _end_collect()
	if not visible:
		return
	if not bool(res.get("ok", false)):
		_show_error(StringName(str(res.get("reason", ""))))
		_update_controls()
		return
	match request:
		&"place_bet", &"high_low_cash_out", &"blackjack_stand":
			_finish_round(res.get("result", {}), heat)
		&"start_high_low":
			_show_info("Higher or lower than %s?" % UiTheme.high_low_card(int(_round.get("card", 0))))
			_update_controls()
		&"start_blackjack":
			_show_info("Hit or stand?")
			_update_controls()
		&"high_low_guess":
			_on_guess(res, heat)
		&"blackjack_hit":
			if bool(res.get("finished", false)):
				_finish_round(res.get("result", {}), heat)
				return
			_show_info("%s. You have %d. Hit or stand?" % [UiTheme.blackjack_card(int(res.get("card", 0))), int(res.get("total", 0))])
			_lock_left = Tuning.UI_HAND_STEP_LOCK_SECONDS
			_update_controls()


func _on_guess(res: Dictionary, heat: float) -> void:
	var result: Dictionary = res.get("result", {})
	if bool(res.get("finished", false)):
		_finish_round(result, heat)
		return
	var detail: Dictionary = result.get("detail", {})
	result_label.text = "CORRECT!  Pot %s" % UiTheme.chips(int(res.get("pot", 0)))
	result_label.add_theme_color_override(&"font_color", UiTheme.WIN_COLOR)
	var shown := UiTheme.high_low_card(int(detail.get("next_card", 0)))
	if bool(detail.get("redeal", false)):
		detail_label.text = "%s came up! Fresh card: %s. Cash out, or go again for double." % [shown, UiTheme.high_low_card(int(detail.get("current_card", 0)))]
	else:
		detail_label.text = "%s came up. Cash out, or go again for double." % shown
	_show_heat(heat)
	_lock_left = Tuning.UI_HAND_STEP_LOCK_SECONDS
	bet_resolved.emit(result)
	_update_controls()


## A round-ending BetResult: show it, lock for the animation, tell the director.
func _finish_round(result: Dictionary, heat: float) -> void:
	_round = {}
	_show_result(result, heat)
	if game_type == HR.GameType.BLACKJACK:
		var detail: Dictionary = result.get("detail", {})
		_render_blackjack(detail.get("player_cards", []), detail.get("dealer_cards", []), int(detail.get("player_total", 0)), false)
	_lock_left = float(TableGames.def(game_type).get("round_seconds", 1.0)) * Tuning.UI_RESULT_LOCK_SHARE
	bet_resolved.emit(result)
	_update_controls()


## Starts waiting for an answer and adding up the non-passive Heat it brings.
func _begin_collect() -> void:
	_collecting = true
	_collected_heat = 0.0
	_await_left = _AWAIT_SECONDS
	_refusal_left = 0.0
	_update_controls()


func _end_collect() -> float:
	_collecting = false
	_await_left = 0.0
	return _collected_heat


# --- Events -----------------------------------------------------------------

func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if kind == &"fire_alarm":
		if visible:
			_read_snapshot()
			_update_controls()
		return
	if kind == &"shared_roll":
		if StringName(str(data.get("table_id", ""))) == table_id:
			_shared = data.duplicate() if bool(data.get("open", false)) else {}
			_update_controls()
		return
	if int(data.get("pid", -1)) != pid:
		return
	match kind:
		&"seated":
			open_for_table(StringName(str(data.get("table_id", ""))), int(data.get("game_type", HR.GameType.SLOTS)))
		&"hand":
			var state: Dictionary = data.get("state", {})
			_round = state.duplicate(true)
			_render_round()
			hand_updated.emit(_round)
			_update_controls()
		&"heat":
			if _collecting and not HeatRules.is_passive(StringName(str(data.get("reason", "")))):
				_collected_heat += float(data.get("delta", 0.0))
		&"chips":
			_pocket = int(data.get("pocket", _pocket))
			if visible and _round.is_empty():
				_clamp_bet()
			_update_controls()
		&"status":
			_status = int(data.get("status", _status))
			_update_controls()
		&"stood":
			if visible and StringName(str(data.get("table_id", ""))) == table_id:
				_round = {}
				_end_collect()
				close()
		&"dealer_swap":
			if StringName(str(data.get("table_id", ""))) == table_id:
				cooled_label.visible = true


# --- State and rendering ----------------------------------------------------

func _read_snapshot() -> void:
	if host == null:
		return
	var snap: Dictionary = host.snapshot()
	var run: Dictionary = snap.get("run", {})
	var players: Dictionary = snap.get("players", {})
	var me: Dictionary = players.get(pid, {})
	_min_bet = int(run.get("min_bet", 1))
	_max_bet = int(run.get("max_bet", 1))
	_rung = int(run.get("rung", Tuning.TOP_RUNG))
	_payout_bonus = float(CasinoLadder.casino(_rung).get("payout_bonus", 1.0))
	if not me.is_empty():
		_pocket = int(me.get("pocket", 0))
		_status = int(me.get("status", _status))
	var tables: Dictionary = snap.get("tables", {})
	var t: Dictionary = tables.get(table_id, {})
	_table_closed = bool(t.get("closed", false))


## Picks up a round already in progress when the panel opens (read only).
func _resume_round() -> void:
	if host != null:
		_round = host.round_state(pid)


func _clamp_bet() -> void:
	var hi: int = mini(_max_bet, _pocket)
	if hi < _min_bet:
		bet_amount = _min_bet
		return
	bet_amount = clampi(bet_amount, _min_bet, hi)


func _step_bet(direction: int) -> void:
	if not _round.is_empty():
		return
	set_bet_amount(bet_amount + direction * _min_bet)


func _can_play() -> bool:
	return visible and host != null and _lock_left <= 0.0 and _await_left <= 0.0 and _status == HR.PlayerStatus.SEATED and not _table_closed


func _can_afford() -> bool:
	return _pocket >= _min_bet and bet_amount <= _pocket


func _configure_game() -> void:
	title_label.text = TableGames.display_name(game_type, _rung).to_upper()
	limits_label.text = "Min %s  ·  Max %s  ·  Wins pay %sx" % [UiTheme.chips(_min_bet), UiTheme.chips(_max_bet), _mult(TableGames.profit_multiple(game_type))]
	for b: Button in choice_buttons:
		b.visible = false
		b.modulate = Color.WHITE
	number_spin.visible = false
	_high_low_box.visible = game_type == HR.GameType.HIGH_LOW
	_blackjack_box.visible = game_type == HR.GameType.BLACKJACK
	_flavor_label.visible = false
	throw_toggle.visible = game_type != HR.GameType.BLACKJACK
	hint_label.text = ""
	match game_type:
		HR.GameType.ROULETTE:
			_set_choice(0, "RED  [1]", &"RedButton")
			_set_choice(1, "BLACK  [2]", &"BlackButton")
			_set_choice(2, "NUMBER  [3]", &"GreenButton")
			number_spin.visible = true
			_flavor("Color pays %sx. A single number pays %sx, with the Heat to match." % [_mult(TableGames.profit_multiple(game_type)), _mult(Tuning.ROULETTE_NUMBER_PAYOUT)])
		HR.GameType.DICE:
			_set_choice(0, "HIGH: over 7  [1]", &"BlueButton")
			_set_choice(1, "LOW: under 7  [2]", &"BlackButton")
			_flavor("Call the roll. The crew can all bet on the same throw.")
		HR.GameType.HIGH_LOW:
			_set_choice(0, "HIGHER  [1]", &"GreenButton")
			_set_choice(1, "LOWER  [2]", &"RedButton")
			_flavor("Guess the next card. Cash out any time; a wrong guess loses the pot.")
		HR.GameType.BLACKJACK:
			_set_choice(0, "HIT  [1]", &"GreenButton")
			_set_choice(1, "STAND  [2]", &"RedButton")
			_flavor("Hit or stand. To throw a hand on purpose, hit past 21.")
		HR.GameType.SLOTS:
			_flavor("Pull the lever. Sitting at a machine hides you in the crowd.")
		HR.GameType.BIG_WHEEL:
			_flavor("Spin the big wheel. Big payout, and LOUD: everyone in the room hears.")
	_render_round()


func _mult(profit: float) -> String:
	return ("%.2f" % (profit * _payout_bonus)).trim_suffix("0").trim_suffix("0").trim_suffix(".")


func _flavor(text: String) -> void:
	_flavor_label.text = text
	_flavor_label.visible = true


func _set_choice(index: int, text: String, variation: StringName) -> void:
	var b: Button = choice_buttons[index]
	b.text = text
	b.theme_type_variation = variation
	b.visible = true


func _update_controls() -> void:
	if game_type < 0:
		return
	var in_round: bool = not _round.is_empty()
	var playable: bool = _can_play()
	pocket_label.text = "Pocket %s" % UiTheme.chips(_pocket)
	amount_label.text = UiTheme.chips(bet_amount if not in_round else int(_round.get("bet", bet_amount)))
	var hi: int = maxi(_min_bet, mini(_max_bet, _pocket))
	_syncing = true
	slider.min_value = _min_bet
	slider.max_value = hi
	slider.step = maxf(1.0, float(_min_bet))
	slider.set_value_no_signal(bet_amount)
	_syncing = false
	var can_size: bool = playable and not in_round and _pocket >= _min_bet
	slider.editable = can_size
	for b: Button in [min_button, minus_button, plus_button, max_button]:
		b.disabled = not can_size
	_bet_row.visible = not in_round

	match game_type:
		HR.GameType.HIGH_LOW:
			if in_round:
				var streak: int = int(_round.get("streak", 0))
				main_button.text = "CASH OUT %s  [Space]" % UiTheme.chips(int(_round.get("pot", 0))) if streak > 0 else "TAKE STAKE BACK  [Space]"
				main_button.disabled = not playable
			else:
				main_button.text = "DEAL  [Space]"
				main_button.disabled = not playable or not _can_afford()
			choice_buttons[0].disabled = not (playable and in_round)
			choice_buttons[1].disabled = not (playable and in_round)
		HR.GameType.BLACKJACK:
			main_button.text = "DEAL  [Space]"
			main_button.visible = not in_round
			main_button.disabled = not playable or not _can_afford()
			choice_buttons[0].disabled = not (playable and in_round)
			choice_buttons[1].disabled = not (playable and in_round)
		_:
			main_button.visible = true
			main_button.text = _bet_verb() + "  [Space]"
			main_button.disabled = not playable or not _can_afford()
			var can_pick: bool = visible and _status == HR.PlayerStatus.SEATED
			for i in choice_buttons.size():
				var b: Button = choice_buttons[i]
				b.disabled = not can_pick
				b.modulate = Color(1, 1, 1, 1) if _choice_selected(i) else Color(1, 1, 1, 0.4)
			number_spin.editable = can_pick
	if game_type != HR.GameType.BLACKJACK:
		main_button.visible = true
	_sync_readout()
	if _refusal_left > 0.0 and _refusal != "":
		_hint(_refusal, UiTheme.LOSS_COLOR)
	elif _status == HR.PlayerStatus.ID_CHECK:
		_hint("A guard wants to see your ID...", UiTheme.heat_color(HR.HeatLevel.SUSPECTED))
	elif not _shared.is_empty():
		var pids: Array = _shared.get("pids", [])
		_hint("Crew roll in %d s: %d bet%s in%s." % [ceili(float(_shared.get("seconds", 0.0))), pids.size(), "" if pids.size() == 1 else "s", "" if pids.has(pid) else ". Bet to join"], UiTheme.GOLD_LIGHT)
	elif _await_left > 0.0:
		_hint("Waiting for the dealer...", UiTheme.MUTED)
	elif _table_closed:
		_hint("The table is closed (fire alarm).", UiTheme.LOSS_COLOR)
	elif not in_round and _pocket < _min_bet:
		_hint("Not enough chips for the %s minimum." % UiTheme.chips(_min_bet), UiTheme.LOSS_COLOR)
	elif _lock_left > 0.0:
		_hint("The table is settling...", UiTheme.MUTED)
	else:
		_hint(_key_hint(in_round), UiTheme.MUTED)


func _key_hint(in_round: bool) -> String:
	match game_type:
		HR.GameType.ROULETTE:
			return "1 red  ·  2 black  ·  3 number  ·  Space bets  ·  +/- bet size"
		HR.GameType.DICE:
			return "1 high  ·  2 low  ·  Space rolls  ·  +/- bet size"
		HR.GameType.HIGH_LOW:
			return "1 higher  ·  2 lower  ·  Space cashes out" if in_round else "Space deals  ·  +/- bet size"
		HR.GameType.BLACKJACK:
			return "1 hit  ·  2 stand" if in_round else "Space deals  ·  +/- bet size"
	return "Space spins  ·  +/- bet size"


func _hint(text: String, color: Color) -> void:
	hint_label.text = text
	hint_label.add_theme_color_override(&"font_color", color)


func _bet_verb() -> String:
	match game_type:
		HR.GameType.SLOTS:
			return "SPIN"
		HR.GameType.BIG_WHEEL:
			return "SPIN THE WHEEL"
		HR.GameType.DICE:
			return "ROLL"
	return "BET"


func _choice_selected(index: int) -> bool:
	match game_type:
		HR.GameType.ROULETTE:
			if _roulette_kind == "number":
				return index == 2
			return (index == 0 and _roulette_color == "red") or (index == 1 and _roulette_color == "black")
		HR.GameType.DICE:
			return (index == 0) == (_dice_call == GameResolver.DICE_CALL_HIGH)
	return true


func _render_round() -> void:
	if game_type == HR.GameType.HIGH_LOW:
		UiTheme.clear_children(high_low_card_holder)
		if _round.is_empty():
			high_low_card_holder.add_child(_card_widget("?", false, true))
			pot_label.text = "Deal to start a run.\nEach correct guess doubles the pot."
		else:
			var card: int = int(_round.get("card", 0))
			high_low_card_holder.add_child(_card_widget(UiTheme.high_low_card(card), card % 2 == 0))
			var streak: int = int(_round.get("streak", 0))
			pot_label.text = "Stake %s\nPot %s  ·  %d in a row" % [UiTheme.chips(int(_round.get("bet", 0))), UiTheme.chips(int(_round.get("pot", 0))), streak]
	elif game_type == HR.GameType.BLACKJACK:
		if _round.is_empty():
			if player_cards_holder.get_child_count() == 0:
				_render_blackjack([], [], 0, false)
		else:
			_render_blackjack(_round.get("player_cards", []), _round.get("dealer_cards", []), int(_round.get("player_total", 0)), true)


func _render_blackjack(player_cards: Array, dealer_cards: Array, total: int, hole_hidden: bool) -> void:
	UiTheme.clear_children(player_cards_holder)
	UiTheme.clear_children(dealer_cards_holder)
	for i in player_cards.size():
		var v: int = int(player_cards[i])
		player_cards_holder.add_child(_card_widget(UiTheme.blackjack_card(v), (v + i) % 2 == 0, false, i))
	for i in dealer_cards.size():
		var v: int = int(dealer_cards[i])
		dealer_cards_holder.add_child(_card_widget(UiTheme.blackjack_card(v), (v + i) % 2 == 1, false, i + 1))
	if hole_hidden and dealer_cards.size() == 1:
		dealer_cards_holder.add_child(_card_widget("?", false, true))
	if player_cards.is_empty():
		player_cards_holder.add_child(_card_widget("?", false, true))
		dealer_cards_holder.add_child(_card_widget("?", false, true))
	player_total_label.text = "= %d" % total if total > 0 else ""
	player_total_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR if total > BlackjackRound.BLACKJACK else UiTheme.GOLD_LIGHT)


func _card_widget(rank: String, red: bool, face_down: bool = false, seed_index: int = 0) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(66, 92)
	if face_down:
		card.add_theme_stylebox_override(&"panel", UiTheme.flat_box(UiTheme.CHIP_RED.darkened(0.2), UiTheme.CREAM, 4, 8, 4))
	else:
		card.add_theme_stylebox_override(&"panel", UiTheme.flat_box(Color.WHITE, Color("c9c2b0"), 2, 8, 4))
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", UiTheme.heavy_font())
	l.add_theme_font_size_override(&"font_size", 30)
	l.add_theme_constant_override(&"outline_size", 0)
	if face_down:
		l.text = "?"
		l.add_theme_color_override(&"font_color", UiTheme.CREAM)
	else:
		l.text = "%s\n%s" % [rank, _suit_for(red, seed_index)]
		l.add_theme_color_override(&"font_color", UiTheme.CHIP_RED if red else UiTheme.INK)
	card.add_child(l)
	return card


func _suit_for(red: bool, seed_index: int) -> String:
	if red:
		return _SUITS[1] if seed_index % 2 == 0 else _SUITS[2]
	return _SUITS[0] if seed_index % 2 == 0 else _SUITS[3]


func _show_result(result: Dictionary, heat: float) -> void:
	var won: bool = bool(result.get("won", false))
	var net: int = int(result.get("net", 0))
	var bet: int = int(result.get("bet", 0))
	var payout: int = int(result.get("payout", 0))
	var text: String
	var color := UiTheme.LOSS_COLOR
	if bool(result.get("jackpot", false)):
		text = "JACKPOT!  +%s" % UiTheme.chips(net)
		color = UiTheme.GOLD_LIGHT
	elif won and net > 0:
		text = "WIN  +%s" % UiTheme.chips(net)
		color = UiTheme.WIN_COLOR
	elif payout > 0 and net == 0:
		text = "STAKE BACK"
		color = UiTheme.CREAM
	elif bool(result.get("intentional_loss", false)):
		text = "THROWN  -%s" % UiTheme.chips(bet)
		color = UiTheme.heat_color(HR.HeatLevel.WATCHED)
	else:
		text = "LOSS  -%s" % UiTheme.chips(bet)
	result_label.text = text
	result_label.add_theme_color_override(&"font_color", color)
	detail_label.text = _detail_text(result)
	_show_heat(heat)


func _show_heat(heat: float) -> void:
	if absf(heat) < 0.05:
		heat_label.text = "No Heat"
		heat_label.add_theme_color_override(&"font_color", UiTheme.MUTED)
	else:
		heat_label.text = "Heat %s" % UiTheme.signed(heat)
		heat_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR if heat > 0.0 else UiTheme.WIN_COLOR)
	_sync_readout()


func _detail_text(result: Dictionary) -> String:
	var d: Dictionary = result.get("detail", {})
	match int(result.get("game_type", game_type)):
		HR.GameType.SLOTS:
			var reels: Array = d.get("reels", [])
			var names: PackedStringArray = []
			for r: Variant in reels:
				names.append(str(r).to_upper())
			return "  |  ".join(names)
		HR.GameType.BIG_WHEEL:
			return "The wheel stops on %s." % str(d.get("label", "?"))
		HR.GameType.DICE:
			var dice: Array = d.get("dice", [0, 0])
			return "%d + %d = %d  (you called %s)" % [int(dice[0]), int(dice[1]), int(d.get("total", 0)), str(d.get("call", "high")).to_upper()]
		HR.GameType.ROULETTE:
			return "The ball lands on %d %s." % [int(d.get("number", 0)), str(d.get("color", "")).to_upper()]
		HR.GameType.HIGH_LOW:
			if bool(d.get("cash_out", false)):
				return "Cashed out after %d correct guesses." % int(d.get("guesses", 0))
			return "%s came up." % UiTheme.high_low_card(int(d.get("next_card", 0)))
		HR.GameType.BLACKJACK:
			if bool(d.get("player_bust", false)):
				return "Bust with %d." % int(d.get("player_total", 0))
			if bool(d.get("dealer_bust", false)):
				return "Dealer busts with %d." % int(d.get("dealer_total", 0))
			return "You %d  vs  dealer %d." % [int(d.get("player_total", 0)), int(d.get("dealer_total", 0))]
	return ""


## Player-facing text for why the table refused a request, with the
## numbers that matter at this table.
func refusal_text(reason: StringName) -> String:
	match reason:
		FloorSim.BELOW_MIN:
			return "Below the table minimum of %s." % UiTheme.chips(_min_bet)
		FloorSim.ABOVE_MAX:
			return "Above the table maximum of %s." % UiTheme.chips(_max_bet)
		FloorSim.NOT_ENOUGH:
			return "Not enough chips: you have %s." % UiTheme.chips(_pocket)
		FloorSim.IN_ROUND:
			if not _shared.is_empty():
				return "You're already in this roll."
		FloorSim.TABLE_CLOSED:
			return "The table is closed (fire alarm)."
		FloorSim.BUSY:
			if _status == HR.PlayerStatus.ID_CHECK:
				return "Not now: a guard is checking your ID."
	return UiTheme.reason_text(reason)


## The host refused a request: say so and why in the result row.
func _show_error(reason: StringName) -> void:
	result_label.text = "REFUSED"
	result_label.add_theme_color_override(&"font_color", UiTheme.LOSS_COLOR)
	detail_label.text = refusal_text(reason)
	heat_label.text = ""
	_sync_readout()


## A press the panel can't send right now: why, in the hint line.
func _explain_blocked() -> void:
	if not visible or host == null:
		return
	if _status != HR.PlayerStatus.SEATED:
		_refuse("Not now: a guard is checking your ID." if _status == HR.PlayerStatus.ID_CHECK else "You can't play right now.")
	elif _table_closed:
		_refuse(refusal_text(FloorSim.TABLE_CLOSED))
	elif _await_left > 0.0:
		_refuse("Still waiting for the dealer...")
	elif _lock_left > 0.0:
		_refuse("Wait for the table to settle.")


func _refuse(text: String) -> void:
	_refusal = text
	_refusal_left = _REFUSAL_SECONDS
	_update_controls()


func _show_info(text: String) -> void:
	result_label.text = ""
	detail_label.text = text
	heat_label.text = ""
	_sync_readout()


func _sync_readout() -> void:
	_result_row.visible = result_label.text != "" or heat_label.text != ""
	detail_label.visible = detail_label.text != ""


# --- Layout -----------------------------------------------------------------

func _build() -> void:
	panel = UiTheme.make_panel()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -390
	panel.offset_right = 390
	panel.offset_top = -24
	panel.offset_bottom = -24
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	panel.add_child(body)

	var header := HBoxContainer.new()
	body.add_child(header)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	title_label = UiTheme.make_label("", &"HeaderLabel")
	titles.add_child(title_label)
	limits_label = UiTheme.make_label("", &"SmallLabel")
	titles.add_child(limits_label)
	cooled_label = UiTheme.make_label("DEALER SWAPPED: the odds here dropped. Time to move.", &"SmallLabel", 18)
	cooled_label.add_theme_color_override(&"font_color", UiTheme.heat_color(HR.HeatLevel.WATCHED))
	cooled_label.visible = false
	titles.add_child(cooled_label)
	pocket_label = UiTheme.make_label("", &"BigLabel")
	pocket_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(pocket_label)

	_flavor_label = UiTheme.make_label("", &"SmallLabel", 19)
	_flavor_label.add_theme_color_override(&"font_color", UiTheme.CREAM)
	_flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_flavor_label)

	# High-low: the card to beat and the pot.
	_high_low_box = HBoxContainer.new()
	_high_low_box.add_theme_constant_override(&"separation", 18)
	body.add_child(_high_low_box)
	high_low_card_holder = HBoxContainer.new()
	_high_low_box.add_child(high_low_card_holder)
	pot_label = UiTheme.make_label("", &"BigLabel", 26)
	pot_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_high_low_box.add_child(pot_label)

	# Blackjack: dealer and player hands.
	_blackjack_box = VBoxContainer.new()
	body.add_child(_blackjack_box)
	var drow := HBoxContainer.new()
	_blackjack_box.add_child(drow)
	var dl := UiTheme.make_label("DEALER", &"SmallLabel")
	dl.custom_minimum_size = Vector2(90, 0)
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	drow.add_child(dl)
	dealer_cards_holder = HBoxContainer.new()
	drow.add_child(dealer_cards_holder)
	var prow := HBoxContainer.new()
	_blackjack_box.add_child(prow)
	var pl := UiTheme.make_label("YOU", &"SmallLabel")
	pl.custom_minimum_size = Vector2(90, 0)
	pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(pl)
	player_cards_holder = HBoxContainer.new()
	prow.add_child(player_cards_holder)
	player_total_label = UiTheme.make_label("", &"BigLabel", 34)
	player_total_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prow.add_child(player_total_label)

	# Choices (1 / 2 / 3).
	_choice_row = HBoxContainer.new()
	body.add_child(_choice_row)
	for i in 3:
		var b := UiTheme.make_button("", &"", Vector2(0, 54))
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(press_choice.bind(i))
		_choice_row.add_child(b)
		choice_buttons.append(b)
	number_spin = SpinBox.new()
	number_spin.min_value = 0
	number_spin.max_value = GameResolver.ROULETTE_MAX_NUMBER
	number_spin.step = 1
	number_spin.value = 17
	number_spin.custom_minimum_size = Vector2(120, 54)
	number_spin.value_changed.connect(func(_v: float) -> void: press_choice(2))
	_choice_row.add_child(number_spin)

	# Bet size.
	_bet_row = HBoxContainer.new()
	body.add_child(_bet_row)
	var bl := UiTheme.make_label("BET", &"SmallLabel")
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bet_row.add_child(bl)
	min_button = _small_button("MIN", func() -> void: set_bet_amount(_min_bet))
	minus_button = _small_button("-", func() -> void: _step_bet(-1))
	slider = HSlider.new()
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(200, 30)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			set_bet_amount(int(v)))
	_bet_row.add_child(min_button)
	_bet_row.add_child(minus_button)
	_bet_row.add_child(slider)
	plus_button = _small_button("+", func() -> void: _step_bet(1))
	max_button = _small_button("MAX", func() -> void: set_bet_amount(mini(_max_bet, _pocket)))
	_bet_row.add_child(plus_button)
	_bet_row.add_child(max_button)
	amount_label = UiTheme.make_label("0", &"BigLabel", 32)
	amount_label.add_theme_color_override(&"font_color", UiTheme.GOLD_LIGHT)
	amount_label.custom_minimum_size = Vector2(110, 0)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bet_row.add_child(amount_label)

	# Throw toggle + main action.
	var action_row := HBoxContainer.new()
	body.add_child(action_row)
	throw_toggle = CheckButton.new()
	throw_toggle.text = "Throw it (lose on purpose)"
	throw_toggle.focus_mode = Control.FOCUS_NONE
	throw_toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(throw_toggle)
	main_button = UiTheme.make_button("BET  [Space]", &"", Vector2(300, 62))
	main_button.focus_mode = Control.FOCUS_NONE
	main_button.add_theme_font_size_override(&"font_size", 28)
	main_button.pressed.connect(press_main)
	action_row.add_child(main_button)

	# Result readout.
	_result_row = HBoxContainer.new()
	var result_row := _result_row
	body.add_child(result_row)
	result_label = UiTheme.make_label("", &"BigLabel", 34)
	result_row.add_child(result_label)
	heat_label = UiTheme.make_label("", &"BigLabel", 26)
	heat_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heat_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result_row.add_child(heat_label)
	detail_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail_label)

	var footer := HBoxContainer.new()
	body.add_child(footer)
	hint_label = UiTheme.make_label("", &"SmallLabel", 19)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_child(hint_label)
	leave_button = UiTheme.make_button("LEAVE TABLE  [Esc]", &"BlackButton")
	leave_button.focus_mode = Control.FOCUS_NONE
	leave_button.pressed.connect(request_leave)
	footer.add_child(leave_button)


func _small_button(text: String, action: Callable) -> Button:
	var b := UiTheme.make_button(text, &"BlackButton", Vector2(56, 44))
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override(&"font_size", 20)
	b.pressed.connect(action)
	return b
