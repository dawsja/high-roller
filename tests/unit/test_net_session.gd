extends TestCase
## NetSession without a second process: the offline defaults, names, the
## Steam fallback when GodotSteam isn't installed, hosting on a real ENet
## port and leaving again, plus the co-op title, lobby and HUD crew widgets.

var _nodes: Array[Node] = []
var _signals: Array = []


func after_each() -> void:
	for n: Node in _nodes:
		if is_instance_valid(n):
			if n is NetSession:
				(n as NetSession).leave()
			n.queue_free()
	_nodes.clear()
	_signals.clear()
	await tree.process_frame


func _add(node: Node) -> Node:
	tree.root.add_child(node)
	_nodes.append(node)
	return node


func _session() -> NetSession:
	var s := NetSession.new()
	s.name = "TestNetSession"
	_add(s)
	s.connected.connect(func() -> void: _signals.append(["connected"]))
	s.connection_failed.connect(func(reason: String) -> void: _signals.append(["failed", reason]))
	s.roster_changed.connect(func(r: Dictionary) -> void: _signals.append(["roster", r.duplicate()]))
	return s


func test_offline_defaults() -> void:
	var s := _session()
	assert_eq(s.state, NetSession.State.OFFLINE)
	assert_eq(s.local_pid(), 1, "offline is pid 1")
	assert_true(s.is_host(), "and its own host")
	assert_false(s.is_online())
	assert_eq(s.backend_kind(), &"")
	assert_eq(NetSession.steam_available(), Engine.has_singleton(&"Steam") and ClassDB.class_exists(&"SteamMultiplayerPeer"))


func test_names_are_cleaned_and_made_unique() -> void:
	var s := _session()
	assert_eq(s._clean_name("  Lucky\tLou \n"), "Lucky Lou")
	assert_eq(s._clean_name(""), "Player")
	assert_eq(s._clean_name("x".repeat(40)).length(), NetSession.MAX_NAME_LENGTH)
	s.roster = {1: "Ace", 5: "Ace 2"}
	assert_eq(s._unique_name("Deuce"), "Deuce")
	assert_eq(s._unique_name("Ace"), "Ace 3")


func test_steam_without_godotsteam_fails_cleanly() -> void:
	if NetSession.steam_available():
		print("SKIP: GodotSteam is installed here")
		return
	var s := _session()
	assert_ne(s.host_steam(), OK)
	assert_eq(s.state, NetSession.State.OFFLINE)
	assert_eq(_signals.filter(func(e: Array) -> bool: return e[0] == "failed").size(), 1)
	assert_true(str(_signals.back()[1]).contains("Steam"))
	assert_false(SteamBackend.available())
	assert_eq(SteamBackend.lobby_from_command_line(), 0)


func test_host_on_a_port_and_leave() -> void:
	var s := _session()
	s.local_name = "  Hosty  "
	var port: int = 20000 + randi() % 30000
	var err := s.host(port)
	if err != OK:
		print("SKIP test_host_on_a_port_and_leave: could not open UDP port %d here" % port)
		return
	assert_eq(s.state, NetSession.State.HOSTING)
	assert_true(s.is_online() and s.is_host())
	assert_eq(s.local_pid(), 1)
	assert_eq(s.roster, {1: "Hosty"})
	assert_eq(s.backend_kind(), &"enet")
	assert_eq(_signals[0], ["connected"])
	assert_true(tree.root.multiplayer.multiplayer_peer is ENetMultiplayerPeer)
	s.leave()
	assert_eq(s.state, NetSession.State.OFFLINE)
	assert_true(s.roster.is_empty())
	assert_true(tree.root.multiplayer.multiplayer_peer is OfflineMultiplayerPeer, "back to no peer")


func test_title_screen_coop_controls() -> void:
	var title: TitleScreen = _add(TitleScreen.new())
	title.setup(null, 1)
	title.host_requested.connect(func(port: int, n: String) -> void: _signals.append(["host", port, n]))
	title.join_requested.connect(func(a: String, port: int, n: String) -> void: _signals.append(["join", a, port, n]))
	assert_eq(title.address_edit.text, "127.0.0.1")
	assert_eq(title.port(), NetSession.DEFAULT_PORT)
	assert_eq(title.steam_button.visible, NetSession.steam_available(), "Steam only when GodotSteam is installed")
	title.name_edit.text = "Lou"
	title.host_button.pressed.emit()
	title.port_edit.text = "30001"
	title.address_edit.text = "10.0.0.7"
	title.join_button.pressed.emit()
	assert_eq(_signals[0], ["host", NetSession.DEFAULT_PORT, "Lou"])
	assert_eq(_signals[1], ["join", "10.0.0.7", 30001, "Lou"])
	title.port_edit.text = "not a port"
	assert_eq(title.port(), NetSession.DEFAULT_PORT)
	title.show_message("The host left the game.")
	assert_true(title.message_label.visible)
	title.show_message("")
	assert_false(title.message_label.visible)


func test_lobby_panel_shows_the_crew() -> void:
	var s := _session()
	var lobby: LobbyPanel = _add(LobbyPanel.new())
	lobby.set_session(s)
	s.state = NetSession.State.HOSTING
	s.roster = {1: "Ace", 7: "Deuce"}
	lobby.open()
	assert_eq(lobby.roster_box.get_child_count(), 2)
	assert_true(lobby.start_button.visible and lobby.practice_button.visible, "the host starts the run")
	assert_false(lobby.invite_button.visible, "no Steam invite on ENet")
	lobby.start_requested.connect(func(rung: int, practice: bool) -> void: _signals.append(["start", rung, practice]))
	lobby.practice_button.pressed.emit()
	assert_eq(_signals.back(), ["start", Tuning.BOTTOM_RUNG, true])
	s.state = NetSession.State.JOINED
	lobby.refresh()
	assert_false(lobby.start_button.visible, "clients wait for the host")
	s.state = NetSession.State.OFFLINE
	s.roster = {}


func test_hud_lists_the_crew() -> void:
	var host := SimHost.new()
	_add(host)
	host.start_run(Tuning.BOTTOM_RUNG, 5, {1: "Ace", 2: "Deuce"})
	host.start_visit()
	host.paused = true
	var hud: Hud = _add(Hud.new())
	hud.setup(host, 1)
	assert_true(hud.crew_panel.visible, "a teammate is listed")
	assert_eq(hud.crew_box.get_child_count(), 1)
	host.current_sim().player(2).heat.add(30.0, HeatRules.WIN)
	hud.refresh()
	var labels: Array = hud.crew_box.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	assert_has(labels, "Deuce")
	assert_has(labels, "WATCHED")
	var solo := SimHost.new()
	_add(solo)
	solo.start_run(Tuning.BOTTOM_RUNG, 5, {1: "Ace"})
	solo.start_visit()
	hud.setup(solo, 1)
	assert_false(hud.crew_panel.visible, "solo: no crew panel")
