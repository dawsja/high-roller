class_name NetSync
extends RefCounted
## Helpers for the MultiplayerSynchronizers co-op puts on world nodes.
##
## Every peer builds the same visit with the same node names, so the
## synchronizers sync nodes that exist on both sides (no MultiplayerSpawner).
## A synchronizer starts invisible to everyone (public_visibility off): its
## owner shows it to a peer only once that peer reports it has built the visit
## (CasinoDirector's ready handshake), so a sync packet never names a node the
## receiver doesn't have yet.

## The child node every synced world node gets.
const NODE_NAME := &"Sync"


## Adds a MultiplayerSynchronizer named NODE_NAME under `node` for its own
## properties: `always` ones go out every `interval` (unreliable), `on_change`
## ones only when they change (reliable). The synchronizer takes the node's
## multiplayer authority (set that first). Returns the existing one if any.
static func attach(node: Node, always: Array[StringName], on_change: Array[StringName], interval: float) -> MultiplayerSynchronizer:
	var existing := node.get_node_or_null(NodePath(String(NODE_NAME))) as MultiplayerSynchronizer
	if existing != null:
		return existing
	var config := SceneReplicationConfig.new()
	for prop: StringName in always:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_spawn(path, false)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	for prop: StringName in on_change:
		var path := NodePath(".:%s" % prop)
		config.add_property(path)
		config.property_set_spawn(path, false)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var sync := MultiplayerSynchronizer.new()
	sync.name = NODE_NAME
	# The node's owner sends; set it before the synchronizer enters the tree.
	sync.set_multiplayer_authority(node.get_multiplayer_authority())
	sync.replication_config = config
	sync.replication_interval = interval
	sync.delta_interval = interval
	sync.public_visibility = false
	node.add_child(sync)
	return sync


## The synchronizer under `node`, or null.
static func of(node: Node) -> MultiplayerSynchronizer:
	if node == null or not is_instance_valid(node):
		return null
	return node.get_node_or_null(NodePath(String(NODE_NAME))) as MultiplayerSynchronizer


## Lets `peers` (pids; this peer and peers that aren't connected are
## skipped) receive the synchronizer under `node` if this peer owns it.
static func show_to(node: Node, peers: Array, self_pid: int) -> void:
	var sync := of(node)
	if sync == null or not sync.is_inside_tree() or sync.get_multiplayer_authority() != self_pid:
		return
	var connected: PackedInt32Array = sync.multiplayer.get_peers()
	for pid: Variant in peers:
		if int(pid) != self_pid and connected.has(int(pid)):
			sync.set_visibility_for(int(pid), true)


## Stops the synchronizer under `node` (if this peer owns it) from sending to
## `peers`: the visit is ending, and the receivers will free their copies.
static func hide_from(node: Node, peers: Array, self_pid: int) -> void:
	var sync := of(node)
	if sync == null or not sync.is_inside_tree() or sync.get_multiplayer_authority() != self_pid:
		return
	var connected: PackedInt32Array = sync.multiplayer.get_peers()
	for pid: Variant in peers:
		if int(pid) != self_pid and connected.has(int(pid)):
			sync.set_visibility_for(int(pid), false)
