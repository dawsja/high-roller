class_name NetBackend
extends RefCounted
## How a NetSession gets its MultiplayerPeer. host() and join() start it;
## the peer arrives with `peer_ready` (right away for ENet, after the Steam
## lobby callbacks for Steam) or the attempt ends with `failed`.

signal peer_ready(peer: MultiplayerPeer)
signal failed(reason: String)
## Steam: a friend invited us and we accepted (join it with NetSession.join_steam).
signal invite_accepted(lobby_id: int)


## &"enet" or &"steam".
func kind() -> StringName:
	return &""


## Starts hosting for up to `max_players` (host included).
func host(_port: int, _max_players: int) -> Error:
	return ERR_UNAVAILABLE


## Starts joining a host (`address` is an IP / host name, or a Steam lobby id).
func join(_address: String, _port: int) -> Error:
	return ERR_UNAVAILABLE


## Called every frame while the session lives (Steam callbacks).
func poll() -> void:
	pass


func close() -> void:
	pass


## The player's own name from the platform ("" if it has none).
func player_name() -> String:
	return ""


## Opens the platform's invite dialog (Steam overlay); false if there is none.
func invite_friends() -> bool:
	return false
