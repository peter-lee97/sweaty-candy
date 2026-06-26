extends Node

signal connected_to_server
signal disconnected_from_server
signal connection_failed(reason: String)
signal snapshot_received(snapshot_data: Dictionary)
signal rtt_updated(rtt_ms: int)

const PING_INTERVAL_SEC: float = 2.0
const RTT_HISTORY_SIZE: int = 5

var _peer: WebSocketMultiplayerPeer
var _connected: bool = false
var _server_peer_id: int = 1
var _own_peer_id: int = 0
var _ping_timer: float = 0.0
var _last_ping_send: int = 0
var _rtt_ms: int = 0
var _rtt_history: Array[int] = []


func connect_to_server(url: String) -> void:
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_client(url)
	if err != OK:
		connection_failed.emit("Failed to create client: %d" % err)
		return
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.multiplayer_peer = _peer


func stop_processing() -> void:
	_connected = false
	multiplayer.multiplayer_peer = null


func disconnect_from_server() -> void:
	_connected = false
	multiplayer.multiplayer_peer = null
	if _peer:
		if _peer.peer_connected.is_connected(_on_peer_connected):
			_peer.peer_connected.disconnect(_on_peer_connected)
		if _peer.peer_disconnected.is_connected(_on_peer_disconnected):
			_peer.peer_disconnected.disconnect(_on_peer_disconnected)
		if _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			_peer.close()
		_peer = null
	_server_peer_id = 1
	_own_peer_id = 0
	_ping_timer = 0.0
	_last_ping_send = 0
	_rtt_ms = 0
	_rtt_history.clear()
	GameData.game_server_ping_ms = 0


func has_connection() -> bool:
	return _connected


func send_player_intent(tick: int, move_dir: Vector2, aim_dir: Vector2, wants_shoot: bool, weapon_cycle: int) -> void:
	if not _connected or not _peer:
		return
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	rpc_id(_server_peer_id, "submit_player_intent", tick, move_dir, aim_dir, wants_shoot, weapon_cycle, _rtt_ms)


func _process(delta: float) -> void:
	if not _peer or not _connected:
		return
	_peer.poll()
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL_SEC:
		_ping_timer = 0.0
		_send_ping()


func _send_ping() -> void:
	if not _connected or not _peer:
		return
	if _peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_last_ping_send = Time.get_ticks_msec()
	ping_server.rpc_id(_server_peer_id, _last_ping_send)


func send_ping_now() -> void:
	_ping_timer = 0.0
	_send_ping()


func get_rtt() -> int:
	return _rtt_ms


func _record_rtt(rtt: int) -> void:
	_rtt_history.append(rtt)
	if _rtt_history.size() > RTT_HISTORY_SIZE:
		_rtt_history.pop_front()
	var total: int = 0
	for v in _rtt_history:
		total += v
	_rtt_ms = int(total / float(_rtt_history.size()))
	GameData.game_server_ping_ms = _rtt_ms
	rtt_updated.emit(_rtt_ms)


@rpc("any_peer", "unreliable")
func ping_server(t: int) -> void:
	pass


@rpc("authority", "unreliable")
func pong_client(t: int) -> void:
	var rtt: int = Time.get_ticks_msec() - t
	_record_rtt(rtt)


func _on_peer_connected(peer_id: int) -> void:
	_server_peer_id = peer_id
	_own_peer_id = multiplayer.get_unique_id()
	_connected = true
	_ping_timer = 0.0
	_rtt_ms = 0
	_rtt_history.clear()
	connected_to_server.emit()
	call_deferred("_send_ping")


func _on_peer_disconnected(peer_id: int) -> void:
	_connected = false
	disconnected_from_server.emit()


@rpc("any_peer", "call_remote", "unreliable")
func receive_server_snapshot(snapshot_data: Dictionary) -> void:
	snapshot_received.emit(snapshot_data)


@rpc("any_peer", "unreliable")
func submit_player_intent(tick: int, move: Vector2, aim: Vector2, shoot: bool, weapon_cycle: int, rtt: int) -> void:
	pass


func get_own_peer_id() -> int:
	return _own_peer_id


@rpc("any_peer", "call_remote", "reliable")
func receive_lobby_state(_payload: Dictionary) -> void:
	pass


