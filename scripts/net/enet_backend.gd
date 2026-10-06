class_name EnetBackend
extends NetBackend
## Plain UDP with Godot's ENetMultiplayerPeer: LAN play and local testing
## (several game instances on one machine, tools/net_test.sh).


func kind() -> StringName:
	return &"enet"


func host(port: int, max_players: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, maxi(1, max_players - 1))
	if err != OK:
		failed.emit("Could not host on port %d (%s)." % [port, error_string(err)])
		return err
	peer_ready.emit(peer)
	return OK


func join(address: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		failed.emit("Could not reach %s:%d (%s)." % [address, port, error_string(err)])
		return err
	peer_ready.emit(peer)
	return OK
