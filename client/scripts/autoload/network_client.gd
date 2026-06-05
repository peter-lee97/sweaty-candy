extends Node

signal connected_to_server
signal disconnected_from_server
signal connection_failed
signal lobby_state_received(payload: Dictionary)
signal snapshot_received(payload: Dictionary)

var _server_url: String = ""
var _local_input_tick: int = 0


func is_server_connected() -> bool:
	if multiplayer.multiplayer_peer == null:
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func connect_to_server(server_url: String = "ws://127.0.0.1:7777") -> Error:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null

	_server_url = server_url
	var peer := WebSocketMultiplayerPeer.new()
	var error: Error = peer.create_client(server_url)
	if error != OK:
		return error

	multiplayer.multiplayer_peer = peer
	_bind_multiplayer_signals()
	return OK


func disconnect_from_server() -> void:
	if multiplayer.multiplayer_peer == null:
		return
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	disconnected_from_server.emit()


func send_player_intent(move: Vector2, aim: Vector3, shoot: bool, weapon_cycle: int = 0) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	_local_input_tick += 1
	var intent: Dictionary = {
		"tick": _local_input_tick,
		"move": move,
		"aim": aim,
		"shoot": shoot,
		"weapon_cycle": weapon_cycle,
	}
	rpc_id(1, "submit_player_intent", intent)


func _bind_multiplayer_signals() -> void:
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_connected_to_server() -> void:
	connected_to_server.emit()


func _on_connection_failed() -> void:
	connection_failed.emit()


func _on_server_disconnected() -> void:
	disconnected_from_server.emit()


@rpc("authority", "reliable")
func receive_lobby_state(payload: Dictionary) -> void:
	lobby_state_received.emit(payload)


@rpc("authority", "unreliable")
func receive_server_snapshot(payload: Dictionary) -> void:
	snapshot_received.emit(payload)


@rpc("any_peer", "unreliable")
func submit_player_intent(_intent: Dictionary) -> void:
	pass
