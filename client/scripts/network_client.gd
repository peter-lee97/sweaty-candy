extends Node

signal connected_to_server
signal disconnected_from_server
signal connection_failed(reason: String)
signal snapshot_received(players: Dictionary, enemies: Dictionary)

var _peer: WebSocketMultiplayerPeer
var _connected: bool = false
var _server_peer_id: int = 1
var _own_peer_id: int = 0


func connect_to_server(url: String) -> void:
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_client(url)
	if err != OK:
		connection_failed.emit("Failed to create client: %d" % err)
		return
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.multiplayer_peer = _peer


func disconnect_from_server() -> void:
	if _peer and _connected:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_connected = false


func has_connection() -> bool:
	return _connected


func send_player_intent(tick: int, move_dir: Vector2, aim_dir: Vector2, wants_shoot: bool, weapon_cycle: int) -> void:
	if not _connected:
		return
	rpc_id(_server_peer_id, "submit_player_intent", tick, move_dir, aim_dir, wants_shoot, weapon_cycle)


func _process(_delta: float) -> void:
	if not _peer or not _connected:
		return
	_peer.poll()


func _on_peer_connected(peer_id: int) -> void:
	_server_peer_id = peer_id
	_own_peer_id = multiplayer.get_unique_id()
	_connected = true
	connected_to_server.emit()


func _on_peer_disconnected(peer_id: int) -> void:
	_connected = false
	disconnected_from_server.emit()


@rpc("any_peer", "call_remote", "unreliable")
func receive_server_snapshot(snapshot_data: Dictionary) -> void:
	snapshot_received.emit(
		snapshot_data.get("players", {}),
		snapshot_data.get("enemies", {})
	)


@rpc("any_peer", "unreliable")
func submit_player_intent(tick: int, move: Vector2, aim: Vector2, shoot: bool, weapon_cycle: int) -> void:
	pass


func get_own_peer_id() -> int:
	return _own_peer_id


@rpc("any_peer", "call_remote", "reliable")
func receive_lobby_state(_payload: Dictionary) -> void:
	pass
