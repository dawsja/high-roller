class_name SteamBackend
extends NetBackend
## Friends-only Steam lobbies with GodotSteam's SteamMultiplayerPeer
## (https://godotsteam.com/tutorials/multiplayer_peer/). Only used when the
## GodotSteam extension is installed: every Steam call goes through
## Engine.get_singleton("Steam").call(...) and the peer is made with
## ClassDB.instantiate(&"SteamMultiplayerPeer"), so the project parses and
## runs without it.
##
## Host: steamInitEx -> createLobby(LOBBY_TYPE_FRIENDS_ONLY, max players) ->
## lobby_created -> SteamMultiplayerPeer.create_host(0). Join (an invite
## accepted in the overlay arrives as join_requested, or `+connect_lobby
## <id>` on the command line): joinLobby -> lobby_joined -> create_client(the
## lobby owner's Steam id, 0). The host is always peer 1; names come from
## each player's Steam persona (sent in the NetSession hello).

## Steam's values, used when the singleton doesn't expose the constants.
const LOBBY_TYPE_FRIENDS_ONLY := 1
const CHAT_ROOM_ENTER_RESPONSE_SUCCESS := 1
const RESULT_OK := 1

var lobby_id: int = 0
var _steam: Object = null
var _started: bool = false
var _max_players: int = 4
var _hosting: bool = false


## True when the GodotSteam extension (singleton and multiplayer peer) is loaded.
static func available() -> bool:
	return Engine.has_singleton(&"Steam") and ClassDB.class_exists(&"SteamMultiplayerPeer")


## The lobby id from `+connect_lobby <id>` on the command line (0 if none).
static func lobby_from_command_line() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size() - 1:
		if args[i] == "+connect_lobby" and args[i + 1].is_valid_int():
			return args[i + 1].to_int()
	return 0


func kind() -> StringName:
	return &"steam"


## Initializes Steam once (steamInitEx) and hooks the lobby signals.
func start() -> bool:
	if _started:
		return true
	if not available():
		return false
	_steam = Engine.get_singleton("Steam")
	var res: Variant = _steam.call("steamInitEx")
	var status: int = int((res as Dictionary).get("status", -1)) if res is Dictionary else -1
	if status != 0:
		var verbal: String = str((res as Dictionary).get("verbal", "unknown error")) if res is Dictionary else "no answer"
		failed.emit("Steam did not start: %s" % verbal)
		return false
	_connect(&"lobby_created", _on_lobby_created)
	_connect(&"lobby_joined", _on_lobby_joined)
	_connect(&"join_requested", _on_join_requested)
	_started = true
	return true


func host(_port: int, max_players: int) -> Error:
	if not start():
		return ERR_UNAVAILABLE
	_hosting = true
	_max_players = max_players
	_steam.call("createLobby", _const(&"LOBBY_TYPE_FRIENDS_ONLY", LOBBY_TYPE_FRIENDS_ONLY), max_players)
	return OK


## `address` is the lobby id.
func join(address: String, _port: int) -> Error:
	if not start():
		return ERR_UNAVAILABLE
	if not address.is_valid_int():
		failed.emit("That isn't a Steam lobby.")
		return ERR_INVALID_PARAMETER
	_hosting = false
	_steam.call("joinLobby", address.to_int())
	return OK


func poll() -> void:
	if _started:
		_steam.call("run_callbacks")


func close() -> void:
	if _started and lobby_id != 0:
		_steam.call("leaveLobby", lobby_id)
	lobby_id = 0


func player_name() -> String:
	return str(_steam.call("getPersonaName")) if _started else ""


func invite_friends() -> bool:
	if not _started or lobby_id == 0:
		return false
	_steam.call("activateGameOverlayInviteDialog", lobby_id)
	return true


func _on_lobby_created(result: Variant, new_lobby_id: Variant) -> void:
	if not _hosting:
		return
	if int(result) != _const(&"RESULT_OK", RESULT_OK):
		failed.emit("Steam could not create the lobby (result %d)." % int(result))
		return
	lobby_id = int(new_lobby_id)
	_steam.call("setLobbyJoinable", lobby_id, true)
	_steam.call("setLobbyData", lobby_id, "name", "%s's crew" % player_name())
	var peer := ClassDB.instantiate(&"SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		failed.emit("SteamMultiplayerPeer is missing.")
		return
	peer.call("create_host", 0)
	peer_ready.emit(peer)


func _on_lobby_joined(joined_id: Variant, _permissions: Variant, _locked: Variant, response: Variant) -> void:
	if _hosting:
		return
	if int(response) != _const(&"CHAT_ROOM_ENTER_RESPONSE_SUCCESS", CHAT_ROOM_ENTER_RESPONSE_SUCCESS):
		failed.emit("Could not join the Steam lobby (response %d)." % int(response))
		return
	lobby_id = int(joined_id)
	var owner_id: int = int(_steam.call("getLobbyOwner", lobby_id))
	if owner_id == int(_steam.call("getSteamID")):
		return
	var peer := ClassDB.instantiate(&"SteamMultiplayerPeer") as MultiplayerPeer
	if peer == null:
		failed.emit("SteamMultiplayerPeer is missing.")
		return
	peer.call("create_client", owner_id, 0)
	peer_ready.emit(peer)


func _on_join_requested(requested_lobby: Variant, _friend_id: Variant) -> void:
	invite_accepted.emit(int(requested_lobby))


func _connect(signal_name: StringName, callable: Callable) -> void:
	if _steam.has_signal(signal_name) and not _steam.is_connected(signal_name, callable):
		_steam.connect(signal_name, callable)


func _const(constant: StringName, fallback: int) -> int:
	if ClassDB.class_has_integer_constant(&"Steam", constant):
		return ClassDB.class_get_integer_constant(&"Steam", constant)
	return fallback
