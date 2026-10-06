class_name NetSession
extends Node
## The co-op session: hosting or joining a crew of up to MAX_PLAYERS over a
## NetBackend (EnetBackend for LAN and local tests; SteamBackend for
## friends-only Steam lobbies when GodotSteam is installed), and the roster.
##
## The host is pid 1 (multiplayer peer ids are the pids). A client says hello
## (its name and PROTOCOL) once connected; the host adds it to the roster and
## sends the roster to everyone, or refuses it (full, game in progress,
## version mismatch). Offline there is no peer (OfflineMultiplayerPeer): this
## peer is pid 1 and the host of its own game. Needs to sit at the same node
## path on every peer (main.gd: /root/Main/NetSession).

signal player_joined(pid: int, player_name: String)
signal player_left(pid: int)
## pid -> name, the host first.
signal roster_changed(roster: Dictionary)
## Hosting has started, or the host accepted us into the crew.
signal connected()
signal connection_failed(reason: String)
## Client: the host went away.
signal server_disconnected()
## A line of progress for the lobby ("Creating the Steam lobby...").
signal status_changed(text: String)

const DEFAULT_PORT := 24565
const MAX_PLAYERS := 4
## Bump when the wire format changes; mismatched peers are refused.
const PROTOCOL := 1
## Host: a connected peer that hasn't said hello by then is dropped.
const HELLO_TIMEOUT_SECONDS := 10.0
const MAX_NAME_LENGTH := 20

enum State { OFFLINE, CONNECTING, HOSTING, JOINED }

var state: int = State.OFFLINE
var backend: NetBackend = null
## This player's name (sent to the host; Steam fills it from the persona).
var local_name: String = "Player"
## pid -> name of the crew, in join order (the host first).
var roster: Dictionary = {}
## Host: new players may join (main.gd closes it while a run is on).
var lobby_open: bool = true
## Why the last attempt failed or ended ("" if it didn't).
var last_error: String = ""

var _hello_deadlines: Dictionary = {}
var _steam: SteamBackend = null
var _hosting_attempt: bool = false
var _max_players: int = MAX_PLAYERS


## True when GodotSteam is installed (Steam lobbies and invites can be used).
static func steam_available() -> bool:
	return SteamBackend.available()


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if steam_available():
		# Accepting an invite in the Steam overlay works from the title screen too.
		_steam = SteamBackend.new()
		if _steam.start():
			_steam.invite_accepted.connect(func(lobby_id: int) -> void: join_steam(lobby_id))
			var lobby := SteamBackend.lobby_from_command_line()
			if lobby != 0:
				join_steam.call_deferred(lobby)
		else:
			_steam = null


func _process(_delta: float) -> void:
	if backend != null:
		backend.poll()
	elif _steam != null:
		_steam.poll()
	if state == State.HOSTING and not _hello_deadlines.is_empty():
		var now := Time.get_ticks_msec()
		for pid: int in _hello_deadlines.keys():
			if now >= int(_hello_deadlines[pid]):
				_hello_deadlines.erase(pid)
				_kick(pid, "No hello from your game.")


## Hosts a LAN / local game (ENet) on `port`.
func host(port: int = DEFAULT_PORT, max_players: int = MAX_PLAYERS) -> Error:
	return _start(EnetBackend.new(), true, "", port, max_players)


## Joins a LAN / local host (ENet).
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	return _start(EnetBackend.new(), false, address, port, MAX_PLAYERS)


## Hosts a friends-only Steam lobby (needs GodotSteam).
func host_steam(max_players: int = MAX_PLAYERS) -> Error:
	if not steam_available():
		return _fail_now("Steam isn't available in this build.")
	status_changed.emit("Creating the Steam lobby...")
	return _start(_steam_backend(), true, "", 0, max_players)


## Joins a Steam lobby (an accepted invite).
func join_steam(lobby_id: int) -> Error:
	if not steam_available():
		return _fail_now("Steam isn't available in this build.")
	if state != State.OFFLINE:
		leave()
	status_changed.emit("Joining the Steam lobby...")
	return _start(_steam_backend(), false, str(lobby_id), 0, MAX_PLAYERS)


## Opens the Steam invite dialog for our lobby (false without one).
func invite_friends() -> bool:
	return backend != null and backend.invite_friends()


## Closes the session (clients see server_disconnected when the host leaves).
func leave() -> void:
	var was: int = state
	state = State.OFFLINE
	_hello_deadlines.clear()
	if multiplayer.has_multiplayer_peer() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if backend != null:
		backend.close()
		backend = null
	roster = {}
	lobby_open = true
	if was != State.OFFLINE:
		NetLog.line("left")
		roster_changed.emit(roster)


func is_online() -> bool:
	return state == State.HOSTING or state == State.JOINED


## True offline and while hosting: this peer runs the game.
func is_host() -> bool:
	return state == State.OFFLINE or state == State.HOSTING


func is_client() -> bool:
	return state == State.JOINED or (state == State.CONNECTING and not _hosting_attempt)


## This peer's pid (1 offline and on the host).
func local_pid() -> int:
	if state == State.JOINED or state == State.CONNECTING:
		var peer := multiplayer.multiplayer_peer
		if peer != null and not (peer is OfflineMultiplayerPeer) and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
			return peer.get_unique_id()
	return 1


## "enet", "steam" or "" offline.
func backend_kind() -> StringName:
	return backend.kind() if backend != null else &""


# --- Internals ------------------------------------------------------------------

func _start(new_backend: NetBackend, hosting: bool, address: String, port: int, max_players: int) -> Error:
	if state != State.OFFLINE:
		leave()
	last_error = ""
	backend = new_backend
	_hosting_attempt = hosting
	_max_players = clampi(max_players, 1, MAX_PLAYERS)
	state = State.CONNECTING
	if not backend.peer_ready.is_connected(_on_peer_ready):
		backend.peer_ready.connect(_on_peer_ready)
		backend.failed.connect(_on_backend_failed)
	var name_from_platform := backend.player_name()
	if name_from_platform != "" and (local_name == "" or local_name == "Player"):
		local_name = name_from_platform
	local_name = _clean_name(local_name)
	NetLog.line("hosting" if hosting else "joining", {"backend": backend.kind(), "address": address, "port": port})
	var err: Error = backend.host(port, _max_players) if hosting else backend.join(address, port)
	if err != OK and state == State.CONNECTING:
		_on_backend_failed("Could not start the session (%s)." % error_string(err))
	return err


func _steam_backend() -> SteamBackend:
	if _steam == null:
		_steam = SteamBackend.new()
		_steam.invite_accepted.connect(func(lobby_id: int) -> void: join_steam(lobby_id))
	return _steam


func _on_peer_ready(peer: MultiplayerPeer) -> void:
	if state != State.CONNECTING:
		peer.close()
		return
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = true
	if _hosting_attempt:
		state = State.HOSTING
		roster = {1: local_name}
		lobby_open = true
		NetLog.pid = 1
		NetLog.line("hosted", {"backend": backend.kind()})
		connected.emit()
		roster_changed.emit(roster)
	else:
		status_changed.emit("Connecting to the host...")


func _on_backend_failed(reason: String) -> void:
	_fail_now(reason)


func _fail_now(reason: String) -> Error:
	last_error = reason
	NetLog.line("failed", {"reason": reason})
	leave()
	connection_failed.emit(reason)
	return FAILED


func _on_peer_connected(pid: int) -> void:
	if state == State.HOSTING:
		_hello_deadlines[pid] = Time.get_ticks_msec() + int(HELLO_TIMEOUT_SECONDS * 1000.0)


func _on_peer_disconnected(pid: int) -> void:
	_hello_deadlines.erase(pid)
	if state != State.HOSTING or not roster.has(pid):
		return
	roster.erase(pid)
	NetLog.line("player_left", {"left": pid, "pids": roster.keys()})
	# Deferred: several peers can drop in one poll; tell only who's still here.
	_send_roster.call_deferred()
	player_left.emit(pid)
	roster_changed.emit(roster)


func _on_connected_to_server() -> void:
	NetLog.pid = local_pid()
	NetLog.line("connected_to_server", {})
	_rpc_hello.rpc_id(1, local_name, PROTOCOL)


func _on_connection_failed() -> void:
	_fail_now("Could not reach the host.")


func _on_server_disconnected() -> void:
	var was_joined: bool = state == State.JOINED
	last_error = "The host left."
	NetLog.line("server_disconnected", {})
	leave()
	if was_joined:
		server_disconnected.emit()
	else:
		connection_failed.emit(last_error)


func _send_roster() -> void:
	if state == State.HOSTING and not multiplayer.get_peers().is_empty():
		_rpc_roster.rpc(roster)


func _kick(pid: int, reason: String) -> void:
	_rpc_refused.rpc_id(pid, reason)
	# Let the refusal go out before the connection drops.
	get_tree().create_timer(0.3, true, false, true).timeout.connect(func() -> void:
		if state == State.HOSTING and multiplayer.get_peers().has(pid):
			multiplayer.multiplayer_peer.disconnect_peer(pid))


func _clean_name(raw: String) -> String:
	var text := raw.strip_edges().replace("\n", " ").replace("\t", " ")
	if text.length() > MAX_NAME_LENGTH:
		text = text.substr(0, MAX_NAME_LENGTH)
	return text if text != "" else "Player"


func _unique_name(wanted: String) -> String:
	var taken: Array = roster.values()
	if not taken.has(wanted):
		return wanted
	var n := 2
	while taken.has("%s %d" % [wanted, n]):
		n += 1
	return "%s %d" % [wanted, n]


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(player_name: Variant, protocol: Variant) -> void:
	var pid := multiplayer.get_remote_sender_id()
	if state != State.HOSTING or roster.has(pid):
		return
	_hello_deadlines.erase(pid)
	if int(protocol) != PROTOCOL:
		_kick(pid, "Version mismatch: the host runs co-op protocol %d, you run %d." % [PROTOCOL, int(protocol)])
		return
	if not lobby_open:
		_kick(pid, "The crew is already in a casino. Join before the run starts.")
		return
	if roster.size() >= _max_players:
		_kick(pid, "The crew is full (%d players)." % _max_players)
		return
	var final_name := _unique_name(_clean_name(str(player_name)))
	roster[pid] = final_name
	NetLog.line("player_joined", {"joined": pid, "name": final_name, "pids": roster.keys()})
	_rpc_roster.rpc(roster)
	player_joined.emit(pid, final_name)
	roster_changed.emit(roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_roster(new_roster: Variant) -> void:
	if not (new_roster is Dictionary) or state == State.OFFLINE or state == State.HOSTING:
		return
	var old := roster
	roster = {}
	for pid: Variant in new_roster:
		roster[int(pid)] = str(new_roster[pid])
	var first: bool = state == State.CONNECTING
	if first:
		state = State.JOINED
		NetLog.pid = local_pid()
		NetLog.line("connected", {"pids": roster.keys()})
		connected.emit()
	for pid: int in roster:
		if not old.has(pid):
			player_joined.emit(pid, str(roster[pid]))
	for pid: int in old:
		if not roster.has(pid):
			player_left.emit(pid)
	NetLog.line("roster", {"pids": roster.keys()})
	roster_changed.emit(roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_refused(reason: Variant) -> void:
	_fail_now(str(reason))
