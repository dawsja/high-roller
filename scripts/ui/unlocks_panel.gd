class_name UnlocksPanel
extends Control
## Cosmetic unlocks (design doc "Scoring and progression"): lifetime banked
## chips, a bar to the next unlock, and every Unlocks row by kind (outfit
## pieces, emotes, ID name packs), unlocked ones with a NEW badge until seen,
## locked ones greyed out with the chips still to bank. Selecting a row
## previews it on a swaying mannequin: a piece worn, an emote played, a name
## pack's sample names. Opened from the title screen; reads the Profile only
## (closing marks everything seen).

signal closed()

const KINDS: Array[StringName] = [Unlocks.KIND_PIECE, Unlocks.KIND_EMOTE, Unlocks.KIND_NAME_PACK]
const KIND_TITLES := {
	Unlocks.KIND_PIECE: "OUTFIT PIECES",
	Unlocks.KIND_EMOTE: "EMOTES",
	Unlocks.KIND_NAME_PACK: "ID NAMES",
}
## What the preview mannequin wears under a previewed piece.
const PREVIEW_BASE := {"hat": "none", "glasses": "none", "top": "plain_tee", "bottom": "blue_jeans", "accessory": "none"}
const PREVIEW_SIZE := Vector2i(300, 340)
## The mannequin sways this far (radians) either side of facing the camera.
const PREVIEW_SWAY := 0.7
const PREVIEW_SWAY_SPEED := 0.7
const LOCKED_ALPHA := 0.45

var profile: Profile = null
## Which kind of unlock the list shows (Unlocks.KIND_*).
var kind: StringName = Unlocks.KIND_PIECE
## The previewed unlock id (&"" for none).
var selected: StringName = &""

var lifetime_label: Label
var stats_label: Label
var progress_bar: ProgressBar
var next_label: Label
var list_box: VBoxContainer
var close_button: Button
## Unlocks.KIND_* -> tab Button.
var tab_buttons: Dictionary = {}
## id -> the row's Button (the list for the current kind).
var rows: Dictionary = {}
## id -> the row's status Label ("UNLOCKED", "Bank 2,500 more").
var status_labels: Dictionary = {}
var preview_model: CharacterModel
var preview_name_label: Label
var preview_detail_label: Label

var _preview_pivot: Node3D
var _preview_time: float = 0.0


func _init() -> void:
	name = "UnlocksPanel"
	theme = UiTheme.make_theme()
	_build()
	visible = false


func set_profile(p: Profile) -> void:
	profile = p
	if visible:
		refresh()


## Opens on a kind (&"" keeps the last one) and previews its first row.
func open(p_kind: StringName = &"") -> void:
	if p_kind in KINDS:
		kind = p_kind
	visible = true
	selected = &""
	refresh()


## Closes; everything shown counts as seen.
func close() -> void:
	if not visible:
		return
	visible = false
	if profile != null:
		profile.mark_seen()
	closed.emit()


func is_open() -> bool:
	return visible


func show_kind(p_kind: StringName) -> void:
	if p_kind in KINDS:
		kind = p_kind
		selected = &""
		refresh()


## Previews an unlock (any kind; switches the list to it).
func select(id: StringName) -> void:
	if not Unlocks.has(id):
		return
	if Unlocks.kind_of(id) != kind:
		kind = Unlocks.kind_of(id)
		selected = id
		refresh()
		return
	selected = id
	_update_preview()
	_mark_rows()


func refresh() -> void:
	var p: Profile = profile if profile != null else Profile.new()
	lifetime_label.text = "LIFETIME BANKED  %s" % UiTheme.chips(p.lifetime_banked)
	var total := Unlocks.TABLE.size()
	stats_label.text = "%d of %d unlocked  ·  Runs %d  ·  Best score %s" % [p.unlocked.size(), total, p.runs, UiTheme.chips(p.best_score)]
	var nxt: Dictionary = Unlocks.next_unlock(p.lifetime_banked)
	if nxt.is_empty():
		progress_bar.value = 1.0
		next_label.text = "Everything unlocked. High roller!"
	else:
		var id: StringName = nxt["id"]
		var at: int = int(nxt["at"])
		var from: int = _previous_threshold(at)
		progress_bar.value = clampf(float(p.lifetime_banked - from) / float(maxi(1, at - from)), 0.0, 1.0)
		next_label.text = "Next: %s (%s) at %s banked  ·  %s to go" % [Unlocks.display_name(id), Unlocks.kind_label(id), UiTheme.chips(at), UiTheme.chips(at - p.lifetime_banked)]
	for k: StringName in tab_buttons:
		var b: Button = tab_buttons[k]
		var have := 0
		var ids := Unlocks.ids_of(k)
		for id: StringName in ids:
			if p.is_unlocked(id):
				have += 1
		b.text = "%s  %d/%d" % [str(KIND_TITLES[k]), have, ids.size()]
		b.modulate = Color.WHITE if k == kind else Color(1, 1, 1, 0.5)
	_rebuild_list(p)
	if selected == &"" or Unlocks.kind_of(selected) != kind:
		var ids := Unlocks.ids_of(kind)
		selected = ids[0] if not ids.is_empty() else &""
	_update_preview()
	_mark_rows()


func _process(delta: float) -> void:
	if visible and _preview_pivot != null:
		_preview_time += delta
		# CharacterModel faces -Z; the camera looks at it from +Z.
		_preview_pivot.rotation.y = PI + PREVIEW_SWAY * sin(_preview_time * PREVIEW_SWAY_SPEED)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _rebuild_list(p: Profile) -> void:
	UiTheme.clear_children(list_box)
	rows.clear()
	status_labels.clear()
	for id: StringName in Unlocks.ids_of(kind):
		var unlocked: bool = p.is_unlocked(id)
		var row := Button.new()
		row.theme_type_variation = &"BlackButton"
		row.custom_minimum_size = Vector2(0, 64)
		row.toggle_mode = true
		row.pressed.connect(select.bind(id))
		list_box.add_child(row)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 12
		h.offset_right = -12
		h.add_theme_constant_override(&"separation", 12)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var icon := _icon(id)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(icon)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_theme_constant_override(&"separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(v)
		var title := UiTheme.make_label(Unlocks.display_name(id), &"", UiTheme.FONT_BODY)
		v.add_child(title)
		v.add_child(UiTheme.make_label(Unlocks.kind_label(id), &"SmallLabel", 15))
		var status := UiTheme.make_label("", &"", 18)
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if unlocked:
			var fresh: bool = p.unseen.has(id)
			status.text = "NEW!" if fresh else "UNLOCKED"
			status.add_theme_color_override(&"font_color", UiTheme.GOLD_LIGHT if fresh else UiTheme.WIN_COLOR)
		else:
			status.text = "Bank %s  ·  %s to go" % [UiTheme.chips(Unlocks.threshold(id)), UiTheme.chips(p.chips_to_unlock(id))]
			status.add_theme_color_override(&"font_color", UiTheme.MUTED)
			icon.modulate = Color(1, 1, 1, LOCKED_ALPHA)
			title.modulate = Color(1, 1, 1, 0.6)
		h.add_child(status)
		UiTheme.ignore_mouse(h)
		rows[id] = row
		status_labels[id] = status


func _mark_rows() -> void:
	for id: StringName in rows:
		(rows[id] as Button).set_pressed_no_signal(id == selected)


func _icon(id: StringName) -> Control:
	match Unlocks.kind_of(id):
		Unlocks.KIND_PIECE:
			return UiTheme.make_swatch(OutfitCatalog.piece_color(id), Vector2(40, 40))
		Unlocks.KIND_EMOTE:
			return _badge_icon("EMO", UiTheme.CHIP_BLUE)
	return _badge_icon("ID", UiTheme.CHIP_GREEN)


func _badge_icon(text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(40, 40)
	p.add_theme_stylebox_override(&"panel", UiTheme.flat_box(color, UiTheme.CREAM, 2, 20, 2))
	var l := UiTheme.make_label(text, &"", 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _update_preview() -> void:
	var p: Profile = profile if profile != null else Profile.new()
	if selected == &"":
		preview_name_label.text = ""
		preview_detail_label.text = ""
		return
	var unlocked: bool = p.is_unlocked(selected)
	preview_name_label.text = Unlocks.display_name(selected)
	var look := Outfit.from_dict(PREVIEW_BASE)
	var pose := &"idle"
	var detail := ""
	match Unlocks.kind_of(selected):
		Unlocks.KIND_PIECE:
			look.set_piece(OutfitCatalog.slot_of(selected), selected)
			detail = "%s  ·  gift shop %s" % [OutfitCatalog.slot_name(OutfitCatalog.slot_of(selected)), UiTheme.chips(OutfitCatalog.piece_price(selected))]
			if unlocked:
				detail += "\nOn sale at every gift shop."
		Unlocks.KIND_EMOTE:
			pose = selected
			detail = "Emote: press T (or R-stick click) on the floor."
		Unlocks.KIND_NAME_PACK:
			detail = "New names on your fake IDs:\n%s..." % IdGenerator.name_pack_sample(selected)
	if not unlocked:
		detail += "\nLOCKED: bank %s more chips." % UiTheme.chips(p.chips_to_unlock(selected))
	preview_detail_label.text = detail
	preview_model.apply_outfit(look)
	preview_model.set_pose(pose)


func _previous_threshold(at: int) -> int:
	var prev := 0
	for row: Dictionary in Unlocks.TABLE:
		var t := int(row["at"])
		if t < at:
			prev = maxi(prev, t)
	return prev


func _build() -> void:
	var body := UiTheme.build_modal(self, 1180.0, 0.7)
	close_button = UiTheme.make_button("CLOSE  [Esc]", &"BlackButton")
	close_button.pressed.connect(close)
	body.add_child(UiTheme.make_header("UNLOCKS", close_button))

	var top := HBoxContainer.new()
	body.add_child(top)
	lifetime_label = UiTheme.make_label("", &"BigLabel", 30, UiTheme.GOLD_LIGHT)
	lifetime_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lifetime_label)
	stats_label = UiTheme.make_label("", &"SmallLabel", 18)
	stats_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(stats_label)
	progress_bar = ProgressBar.new()
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0, 22)
	body.add_child(progress_bar)
	next_label = UiTheme.make_label("", &"", 20)
	body.add_child(next_label)

	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	for k: StringName in KINDS:
		var b := UiTheme.make_button(str(KIND_TITLES[k]), &"BlueButton", Vector2(0, 46))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override(&"font_size", 20)
		b.pressed.connect(show_kind.bind(k))
		tabs.add_child(b)
		tab_buttons[k] = b

	var split := HBoxContainer.new()
	split.add_theme_constant_override(&"separation", 16)
	body.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override(&"separation", 6)
	scroll.add_child(list_box)
	split.add_child(_build_preview())

	var foot := UiTheme.make_label("Bank chips at any cashier to unlock more. Unlocks are cosmetic and never sold for real money.", &"SmallLabel", 17)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(foot)


func _build_preview() -> Control:
	var panel := UiTheme.make_panel(&"InsetPanel")
	panel.custom_minimum_size = Vector2(PREVIEW_SIZE.x + 20, 0)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(PREVIEW_SIZE)
	v.add_child(holder)
	var vp := SubViewport.new()
	vp.size = PREVIEW_SIZE
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	holder.add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.72, 0.65)
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.08, 4.7)
	vp.add_child(cam)
	var floor_disc := Primitives.cylinder(0.75, 0.04, UiTheme.FELT_LIGHT, 24)
	floor_disc.position = Vector3(0, -0.02, 0)
	vp.add_child(floor_disc)
	_preview_pivot = Node3D.new()
	_preview_pivot.rotation.y = PI
	vp.add_child(_preview_pivot)
	preview_model = CharacterModel.new()
	preview_model.name = "PreviewModel"
	preview_model.appearance_seed = 3
	_preview_pivot.add_child(preview_model)
	preview_name_label = UiTheme.make_label("", &"BigLabel", 26, UiTheme.GOLD_LIGHT)
	preview_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(preview_name_label)
	preview_detail_label = UiTheme.make_label("", &"SmallLabel", 17)
	preview_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_detail_label.custom_minimum_size = Vector2(PREVIEW_SIZE.x, 0)
	v.add_child(preview_detail_label)
	return panel
