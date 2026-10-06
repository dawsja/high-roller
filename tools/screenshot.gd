extends SceneTree
## Renders review screenshots of one casino visit. Run it through
## tools/screenshot.sh (a virtual display and the OpenGL renderer), or:
##   godot --path . --rendering-driver opengl3 -s res://tools/screenshot.gd -- --rung=6 --out=/abs/dir
## Args: --rung=N (default 6), --out=DIR (absolute; default user://screenshots),
## --practice, --seed=N. Saves 00_title, 01_player, 02_overhead, 03_table and
## 04_hud PNGs, then quits.
## Co-op (screenshot.sh --coop starts a headless host first): --join=ADDR:PORT
## joins it as a client and saves 05_coop_view (a teammate with a nameplate),
## 06_coop_hud (the crew panel) and 07_lobby.

const MAIN_SCENE := "res://scenes/main.tscn"

var _out: String = "user://screenshots"
var _rung: int = Tuning.BOTTOM_RUNG
var _practice: bool = false
var _seed: int = 7
var _main: Node
var _join: String = ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--rung="):
			_rung = clampi(a.get_slice("=", 1).to_int(), Tuning.TOP_RUNG, Tuning.BOTTOM_RUNG)
		elif a.begins_with("--out="):
			_out = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			_seed = a.get_slice("=", 1).to_int()
		elif a == "--practice":
			_practice = true
		elif a.begins_with("--join="):
			_join = a.substr(7)
	if _join != "":
		_run_coop.call_deferred()
	else:
		_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: PackedScene = load(MAIN_SCENE)
	_main = scene.instantiate()
	_main.set(&"parse_args", false)
	_main.set(&"run_seed", _seed)
	root.add_child(_main)
	await _frames(20)
	await _shot("00_title")

	_main.call(&"start_game", _rung, _practice)
	var director: CasinoDirector = _main.get(&"director")
	for i in 400:
		if director.npcs_active:
			break
		await physics_frame
	await _frames(60)
	var player: PlayerCharacter = director.player
	# Walk a few steps into the casino so the camera sees the floor.
	Input.action_press(&"move_forward")
	await _frames(70)
	Input.action_release(&"move_forward")
	await _frames(40)
	await _shot("01_player")

	await _overhead(director)

	var table := _pick_table(director)
	if table != null:
		player.teleport(table.interactable.global_position + Vector3(0, -1.0, 0))
		await _frames(4)
		director.interact(player.pid, table.interactable)
		await _frames(30)
		var panel: BetPanel = _main.get(&"bet_panel")
		panel.press_main()
		await _seconds(table.result_seconds() * 0.45)
		await _shot("03_table")
		await _seconds(table.result_seconds())
		panel.request_leave()
		await _frames(20)

	await _frames(30)
	# HUD close-up: the top band and the bottom band stacked, at 1.25x.
	var img := await _grab()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var top_h: int = int(h * 0.25)
	var bottom_h: int = int(h * 0.3)
	var hud := Image.create(w, top_h + bottom_h, false, img.get_format())
	hud.blit_rect(img, Rect2i(0, 0, w, top_h), Vector2i.ZERO)
	hud.blit_rect(img, Rect2i(0, h - bottom_h, w, bottom_h), Vector2i(0, top_h))
	hud.resize(int(w * 1.25), int((top_h + bottom_h) * 1.25), Image.INTERPOLATE_BILINEAR)
	_save(hud, "04_hud")
	quit()


## Joins the host given by --join and shoots the client's view of the crew.
func _run_coop() -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: PackedScene = load(MAIN_SCENE)
	_main = scene.instantiate()
	_main.set(&"parse_args", false)
	var colon: int = _join.rfind(":")
	_main.set(&"join_address", _join.substr(0, colon) if colon > 0 else _join)
	_main.set(&"join_port", _join.substr(colon + 1).to_int() if colon > 0 else NetSession.DEFAULT_PORT)
	_main.set(&"player_name", "Deuce")
	root.add_child(_main)
	var director: CasinoDirector = null
	for i in 600:
		director = _main.get(&"director")
		if director != null and director.npcs_active and director.players.size() > 1:
			break
		await process_frame
	if director == null:
		print("screenshot: no co-op visit (is the host up?)")
		quit(1)
		return
	await _frames(60)
	var me: PlayerCharacter = director.player
	var mate: PlayerCharacter = null
	for pid: int in director.players:
		if pid != me.pid:
			mate = director.players[pid]
	# Stand a little behind the teammate and look at them.
	if mate != null:
		var back := mate.global_position + Vector3(1.2, 0.0, 3.2)
		me.teleport(back)
		var to := mate.global_position - back
		me.camera_rig.yaw = atan2(-to.x, -to.z)
		me.camera_rig.snap()
	await _frames(40)
	await _shot("05_coop_view")
	var img := await _grab()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var crop := img.get_region(Rect2i(0, 0, int(w * 0.5), int(h * 0.45)))
	crop.resize(int(crop.get_width() * 1.5), int(crop.get_height() * 1.5), Image.INTERPOLATE_BILINEAR)
	_save(crop, "06_coop_hud")
	# The lobby panel over the running visit (tearing the visit down while
	# the host still sends to it isn't a real flow).
	var lobby: LobbyPanel = _main.get(&"lobby_panel")
	lobby.open()
	await _frames(20)
	await _shot("07_lobby")
	_main.call(&"quit_game")


func _overhead(director: CasinoDirector) -> void:
	var map: CasinoMap = director.map
	var cam := Camera3D.new()
	cam.name = "OverheadCamera"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var b: AABB = map.bounds
	var center: Vector3 = map.to_global(b.get_center())
	var aspect: float = float(root.size.x) / float(maxi(root.size.y, 1))
	cam.size = maxf(b.size.z, b.size.x / aspect) * 1.04
	cam.far = 200.0
	director.add_child(cam)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)), center + Vector3.UP * 60.0)
	var hud_layer: CanvasLayer = _main.get(&"hud_layer")
	hud_layer.visible = false
	var prev := root.get_camera_3d()
	cam.make_current()
	await _frames(6)
	await _shot("02_overhead")
	hud_layer.visible = true
	if prev != null:
		prev.make_current()
	cam.queue_free()
	await _frames(4)


func _pick_table(director: CasinoDirector) -> TableNode:
	var order: Array[int] = [HR.GameType.ROULETTE, HR.GameType.BIG_WHEEL, HR.GameType.DICE, HR.GameType.SLOTS]
	for kind: int in order:
		for t: TableNode in director.tables.values():
			if t.game_type == kind:
				return t
	return null


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _seconds(s: float) -> void:
	await create_timer(s).timeout


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _shot(file_name: String) -> void:
	var img := await _grab()
	_save(img, file_name)


func _save(img: Image, file_name: String) -> void:
	var path := _out.path_join(file_name + ".png")
	var err := img.save_png(path)
	print("screenshot %s -> %s (%s)" % [file_name, path, error_string(err)])
