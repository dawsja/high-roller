class_name WardrobePanel
extends Control
## Outfits, in three modes (open_mode):
## - MODE_RESTROOM: the stash as swatch rows; Wear swaps into one (request_change_to_stash).
## - MODE_GIFT_SHOP: pieces per slot with prices (request_buy_outfit_piece); a
##   bought piece lands in the stash as a copy of the worn look with that piece.
##   Locked pieces (cosmetic unlocks) are for sale once this player's profile
##   (set_profile) has unlocked them; the others show greyed out with the
##   lifetime banked chips they need.
## - MODE_STEAL: a laundry cart or staff locker (request_steal_outfit_piece).
## Always shows the worn outfit and whether it matches a wanted poster.
## Results arrive as host.request_done.

signal closed()

const MODE_RESTROOM := &"restroom"
const MODE_GIFT_SHOP := &"gift_shop"
const MODE_STEAL := &"steal"

var host: SimHost = null
var pid: int = 1
var mode: StringName = MODE_RESTROOM
## HR.OutfitSlot shown in the gift shop.
var shop_slot: int = HR.OutfitSlot.HAT
## MODE_STEAL: the Interactable kind being raided (&"laundry_cart" or &"staff_locker").
var steal_source: StringName = &"laundry_cart"

var title_label: Label
var outfit_holder: HBoxContainer
var outfit_text_label: Label
var look_badge_label: Label
var list_box: VBoxContainer
var result_label: Label
var close_button: Button
## Restroom: one Wear button per stash outfit (index = stash index).
var wear_buttons: Array[Button] = []
## Gift shop: one Buy button per piece of shop_slot this player can buy
## (piece id -> Button).
var buy_buttons: Dictionary = {}
## Gift shop: locked pieces of shop_slot (piece id -> the "bank N more" Label).
var locked_labels: Dictionary = {}
## This player's progression (unlocked pieces, lifetime banked); null = none.
var profile: Profile = null
var slot_buttons: Array[Button] = []
var steal_button: Button

var _me: Dictionary = {}
var _hint_label: Label
var _slot_row: HBoxContainer
var _scroll: ScrollContainer


func _init() -> void:
	name = "WardrobePanel"
	theme = UiTheme.make_theme()
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


## The local player's profile: which locked pieces the gift shop sells.
func set_profile(p: Profile) -> void:
	profile = p
	if visible:
		refresh()


## Opens in MODE_RESTROOM, MODE_GIFT_SHOP or MODE_STEAL (`source`: the
## interactable kind, &"laundry_cart" or &"staff_locker").
func open_mode(p_mode: StringName, source: StringName = &"laundry_cart") -> void:
	mode = p_mode if p_mode in [MODE_RESTROOM, MODE_GIFT_SHOP, MODE_STEAL] else MODE_RESTROOM
	steal_source = source
	result_label.text = ""
	visible = true
	refresh()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func is_open() -> bool:
	return visible


func select_slot(slot: int) -> void:
	if OutfitCatalog.is_valid_slot(slot):
		shop_slot = slot
		refresh()


func wear(index: int) -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	return host.request_change_to_stash(pid, index)


func buy(slot: int, piece: StringName) -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	return host.request_buy_outfit_piece(pid, slot, piece)


func steal() -> Dictionary:
	if host == null:
		return {"ok": false, "reason": SimHost.NO_SIM}
	return host.request_steal_outfit_piece(pid)


func _on_request_done(request: StringName, args: Array, res: Dictionary) -> void:
	if args.is_empty() or int(args[0]) != pid or not (request in [&"change_to_stash", &"buy_outfit_piece", &"steal_outfit_piece"]):
		return
	var ok: bool = bool(res.get("ok", false))
	match request:
		&"change_to_stash":
			if ok:
				_result("New look! Heat %s" % UiTheme.signed(float(res.get("heat", 0.0))), UiTheme.WIN_COLOR)
			else:
				_fail(res)
		&"buy_outfit_piece":
			if ok:
				var piece := StringName(str(args[2])) if args.size() > 2 else &""
				_result("Bought %s for %s. It's in your stash: change at a restroom." % [OutfitCatalog.piece_name(piece), UiTheme.chips(int(res.get("price", 0)))], UiTheme.WIN_COLOR)
			else:
				_fail(res)
		&"steal_outfit_piece":
			if ok:
				if bool(res.get("uniform", false)):
					_result("You swiped a full STAFF UNIFORM! Guards ignore staff, but staff can't sit at tables.", UiTheme.GOLD_LIGHT)
				else:
					_result("You swiped %s. It's in your stash." % OutfitCatalog.piece_name(StringName(str(res.get("piece", "")))), UiTheme.WIN_COLOR)
			elif StringName(str(res.get("reason", ""))) == FloorSim.COOLDOWN:
				_result("Someone's watching. Try again in %d s." % ceili(float(res.get("seconds", 0.0))), UiTheme.heat_color(HR.HeatLevel.WATCHED))
			else:
				_fail(res)
	if visible:
		refresh()


func refresh() -> void:
	_me = UiTheme.player_snapshot(host, pid)
	var outfit: Dictionary = _me.get("outfit", {})
	UiTheme.clear_children(outfit_holder)
	if not outfit.is_empty():
		outfit_holder.add_child(UiTheme.make_outfit_row(outfit, Vector2(42, 42)))
	outfit_text_label.text = Outfit.from_dict(outfit).describe() if not outfit.is_empty() else ""
	if bool(_me.get("matches_poster", false)):
		_badge("MATCHES A WANTED POSTER. Change before a guard sees you!", UiTheme.heat_color(HR.HeatLevel.WANTED))
	elif bool(_me.get("recognized", false)):
		_badge("Security recorded this look. Change it.", UiTheme.heat_color(HR.HeatLevel.SUSPECTED))
	elif bool(_me.get("staff_uniform", false)):
		_badge("Staff uniform: walk past guards (no table games).", UiTheme.GOLD_LIGHT)
	else:
		_badge("No poster matches this look.", UiTheme.WIN_COLOR)
	match mode:
		MODE_GIFT_SHOP:
			title_label.text = "GIFT SHOP"
		MODE_STEAL:
			title_label.text = "STAFF LOCKER" if steal_source == &"staff_locker" else "LAUNDRY CART"
		_:
			title_label.text = "RESTROOM"
	_slot_row.visible = mode == MODE_GIFT_SHOP
	# The steal view is short: let it size to its content instead of scrolling.
	_scroll.custom_minimum_size = Vector2(0, 0 if mode == MODE_STEAL else 360)
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if mode == MODE_STEAL else ScrollContainer.SCROLL_MODE_AUTO
	_rebuild_list()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_sim_event(kind: StringName, data: Dictionary) -> void:
	if not visible:
		return
	if UiTheme.ends_panel(kind, data, pid):
		close()
		return
	if kind in [&"outfit", &"chips", &"status"] and int(data.get("pid", -1)) == pid:
		refresh()
	elif kind in [&"poster", &"poster_removed", &"poster_defaced", &"look_recorded"]:
		refresh()


func _rebuild_list() -> void:
	UiTheme.clear_children(list_box)
	wear_buttons.clear()
	buy_buttons.clear()
	locked_labels.clear()
	steal_button = null
	match mode:
		MODE_GIFT_SHOP:
			_build_shop()
		MODE_STEAL:
			_build_steal()
		_:
			_build_stash()


func _build_stash() -> void:
	var stash: Array = _me.get("stash", [])
	_hint_label.text = "Changing outfits cools you off (%s Heat). Mix pieces at the gift shop." % UiTheme.signed(Tuning.CHANGE_OUTFIT_HEAT)
	if stash.is_empty():
		list_box.add_child(UiTheme.make_label("Your stash is empty. Buy pieces at the gift shop or swipe some from a laundry cart.", &"SmallLabel"))
		return
	var free: bool = int(_me.get("status", HR.PlayerStatus.FREE)) == HR.PlayerStatus.FREE
	for i in stash.size():
		var look: Dictionary = stash[i]
		var row := _row()
		var n := UiTheme.make_label("%d" % (i + 1), &"BigLabel")
		n.custom_minimum_size = Vector2(30, 0)
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(n)
		row.add_child(UiTheme.make_outfit_row(look, Vector2(36, 36)))
		var d := UiTheme.make_label(Outfit.from_dict(look).describe(), &"SmallLabel", 17)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(d)
		var b := UiTheme.make_button("WEAR", &"GreenButton", Vector2(110, 48))
		b.disabled = not free
		b.pressed.connect(wear.bind(i))
		row.add_child(b)
		wear_buttons.append(b)


func _build_shop() -> void:
	for i in slot_buttons.size():
		slot_buttons[i].modulate = Color.WHITE if i == shop_slot else Color(1, 1, 1, 0.45)
	var pocket: int = int(_me.get("pocket", 0))
	var worn: Outfit = Outfit.from_dict(_me.get("outfit", {}))
	_hint_label.text = "Pocket %s. Bought pieces go to your stash: change at a restroom." % UiTheme.chips(pocket)
	var unlocked: Array[StringName] = []
	if profile != null:
		unlocked = profile.unlocked_pieces()
	for piece: StringName in OutfitCatalog.shop_pieces(shop_slot, unlocked, true):
		if OutfitCatalog.is_locked(piece, unlocked):
			_locked_row(piece)
			continue
		var row := _row()
		row.add_child(UiTheme.make_swatch(OutfitCatalog.piece_color(piece), Vector2(36, 36)))
		var n := UiTheme.make_label(OutfitCatalog.piece_name(piece), &"", UiTheme.FONT_BODY)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if OutfitCatalog.is_unlockable(piece):
			# One of this player's unlocks.
			n.add_theme_color_override(&"font_color", UiTheme.GOLD_LIGHT)
			n.tooltip_text = "Unlocked with lifetime banked chips"
		row.add_child(n)
		var price: int = OutfitCatalog.piece_price(piece)
		var p := UiTheme.make_label(UiTheme.chips(price), &"BigLabel", 24)
		p.add_theme_color_override(&"font_color", UiTheme.GOLD_LIGHT if pocket >= price else UiTheme.LOSS_COLOR)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(p)
		var wearing: bool = worn.get_piece(shop_slot) == piece
		var b := UiTheme.make_button("WEARING" if wearing else "BUY", &"BlackButton" if wearing else &"", Vector2(130, 46))
		b.disabled = wearing or pocket < price
		b.pressed.connect(buy.bind(shop_slot, piece))
		row.add_child(b)
		buy_buttons[piece] = b


## A locked piece: greyed out, with the lifetime banked chips it needs.
func _locked_row(piece: StringName) -> void:
	var row := _row()
	row.modulate = Color(1, 1, 1, 0.5)
	row.add_child(UiTheme.make_swatch(OutfitCatalog.piece_color(piece), Vector2(36, 36)))
	var n := UiTheme.make_label(OutfitCatalog.piece_name(piece), &"", UiTheme.FONT_BODY, UiTheme.MUTED)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)
	var at: int = maxi(0, Unlocks.threshold(piece))
	var to_go: int = profile.chips_to_unlock(piece) if profile != null else at
	var l := UiTheme.make_label("LOCKED  ·  bank %s more" % UiTheme.chips(to_go), &"", 19, UiTheme.MUTED)
	l.tooltip_text = "Unlocks at %s lifetime banked chips" % UiTheme.chips(at)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	locked_labels[piece] = l


func _build_steal() -> void:
	_hint_label.text = "%d%% chance of a full staff uniform. Otherwise one random piece, into your stash." % roundi(Tuning.STEAL_UNIFORM_CHANCE * 100.0)
	var what := "the staff locker" if steal_source == &"staff_locker" else "the laundry"
	var l := UiTheme.make_label("Rummage through %s. Nobody's looking... probably." % what, &"", UiTheme.FONT_BODY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	list_box.add_child(l)
	steal_button = UiTheme.make_button("SWIPE SOMETHING", &"RedButton", Vector2(0, 64))
	steal_button.add_theme_font_size_override(&"font_size", 30)
	steal_button.disabled = int(_me.get("status", HR.PlayerStatus.FREE)) != HR.PlayerStatus.FREE
	steal_button.pressed.connect(steal)
	list_box.add_child(steal_button)


func _row() -> HBoxContainer:
	var panel := UiTheme.make_panel(&"InsetPanel")
	list_box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	panel.add_child(row)
	return row


func _badge(text: String, color: Color) -> void:
	look_badge_label.text = text
	look_badge_label.add_theme_color_override(&"font_color", color)


func _result(text: String, color: Color) -> void:
	result_label.text = text
	result_label.add_theme_color_override(&"font_color", color)


func _fail(res: Dictionary) -> void:
	_result(UiTheme.reason_text(StringName(str(res.get("reason", "")))), UiTheme.LOSS_COLOR)


func _build() -> void:
	var body := UiTheme.build_modal(self, 820.0)
	close_button = UiTheme.make_button("CLOSE  [Esc]", &"BlackButton")
	close_button.pressed.connect(close)
	var header := UiTheme.make_header("RESTROOM", close_button)
	title_label = header.get_child(0) as Label
	body.add_child(header)

	var look := UiTheme.make_panel(&"InsetPanel")
	body.add_child(look)
	var lv := VBoxContainer.new()
	look.add_child(lv)
	var lrow := HBoxContainer.new()
	lv.add_child(lrow)
	var wl := UiTheme.make_label("WEARING", &"SmallLabel")
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lrow.add_child(wl)
	outfit_holder = HBoxContainer.new()
	lrow.add_child(outfit_holder)
	outfit_text_label = UiTheme.make_label("", &"SmallLabel", 18)
	outfit_text_label.add_theme_color_override(&"font_color", UiTheme.CREAM)
	outfit_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(outfit_text_label)
	look_badge_label = UiTheme.make_label("", &"", UiTheme.FONT_BODY)
	lv.add_child(look_badge_label)

	_slot_row = HBoxContainer.new()
	body.add_child(_slot_row)
	for slot: int in OutfitCatalog.all_slots():
		var b := UiTheme.make_button(OutfitCatalog.slot_name(slot).to_upper(), &"BlueButton", Vector2(0, 44))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override(&"font_size", 20)
		b.pressed.connect(select_slot.bind(slot))
		_slot_row.add_child(b)
		slot_buttons.append(b)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 360)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	body.add_child(_scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override(&"separation", 6)
	_scroll.add_child(list_box)

	_hint_label = UiTheme.make_label("", &"SmallLabel", 18)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_hint_label)
	result_label = UiTheme.make_label("", &"BigLabel", 24)
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(result_label)
