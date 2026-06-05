extends Node

@export var listen_port: int = 7777
@export var max_players: int = 4
@export var move_speed: float = 6.0
@export var arena_half_size: float = 14.0
@export var snapshot_rate_hz: float = 20.0

var _server_tick: int = 0
var _snapshot_timer: float = 0.0
var _players: Dictionary = {}
var _pending_inputs: Dictionary = {}


func _ready() -> void:
	_start_server()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_server_tick += 1
	_step_player_simulation(delta)
	_snapshot_timer += delta
	if _snapshot_timer >= (1.0 / snapshot_rate_hz):
		_snapshot_timer = 0.0
		_broadcast_snapshot()


func _start_server() -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var error: Error = peer.create_server(listen_port)
	if error != OK:
		push_error("Failed to start WebSocket server on port %d (error %d)." % [listen_port, error])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Server listening on ws://0.0.0.0:%d" % listen_port)


func _on_peer_connected(peer_id: int) -> void:
	if _players.size() >= max_players:
		var net_peer: MultiplayerPeer = multiplayer.multiplayer_peer
		net_peer.disconnect_peer(peer_id, true)
		return
	_players[peer_id] = _new_player_state(_spawn_position_for_peer(peer_id))
	_pending_inputs[peer_id] = {}
	_notify_lobby_state()


func _on_peer_disconnected(peer_id: int) -> void:
	_players.erase(peer_id)
	_pending_inputs.erase(peer_id)
	_notify_lobby_state()


@rpc("any_peer", "unreliable")
func submit_player_intent(intent: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _players.has(peer_id):
		return
	_pending_inputs[peer_id] = _sanitize_intent(intent)


func _step_player_simulation(delta: float) -> void:
	for peer_id: int in _players.keys():
		var state: Dictionary = _players[peer_id]
		var intent: Dictionary = _pending_inputs.get(peer_id, {})

		var move_input: Vector2 = intent.get("move", Vector2.ZERO)
		var move_dir := Vector3(move_input.x, 0.0, move_input.y)
		if move_dir.length_squared() > 1.0:
			move_dir = move_dir.normalized()
		var velocity: Vector3 = move_dir * move_speed
		var position: Vector3 = state["position"] + velocity * delta
		position.x = clamp(position.x, -arena_half_size, arena_half_size)
		position.z = clamp(position.z, -arena_half_size, arena_half_size)

		var aim: Vector3 = state["aim"]
		if intent.has("aim"):
			aim = intent["aim"]

		var weapon_cycle: int = intent.get("weapon_cycle", 0)
		var weapon_index: int = state["weapon_index"]
		if weapon_cycle != 0:
			var weapon_step: int = 1 if weapon_cycle > 0 else -1
			weapon_index = wrapi(weapon_index + weapon_step, 0, 4)

		state["position"] = position
		state["velocity"] = velocity
		state["aim"] = aim
		state["weapon_index"] = weapon_index
		state["last_input_tick"] = intent.get("tick", state["last_input_tick"])
		state["wants_shoot"] = intent.get("shoot", false)
		_players[peer_id] = state


func _broadcast_snapshot() -> void:
	var payload: Dictionary = {
		"server_tick": _server_tick,
		"players": _players,
	}
	rpc("receive_server_snapshot", payload)


func _notify_lobby_state() -> void:
	var payload: Dictionary = {
		"server_tick": _server_tick,
		"players": _players,
	}
	rpc("receive_lobby_state", payload)


func _sanitize_intent(intent: Dictionary) -> Dictionary:
	var sanitized: Dictionary = {}
	sanitized["tick"] = int(intent.get("tick", 0))
	sanitized["shoot"] = bool(intent.get("shoot", false))
	sanitized["weapon_cycle"] = int(intent.get("weapon_cycle", 0))
	sanitized["move"] = _sanitize_move(intent.get("move", Vector2.ZERO))
	sanitized["aim"] = _sanitize_aim(intent.get("aim", Vector3.FORWARD))
	return sanitized


func _sanitize_move(raw: Variant) -> Vector2:
	if raw is Vector2:
		var move: Vector2 = raw
		if move.length_squared() > 1.0:
			move = move.normalized()
		return move
	if raw is Array and raw.size() >= 2:
		var move := Vector2(float(raw[0]), float(raw[1]))
		if move.length_squared() > 1.0:
			move = move.normalized()
		return move
	return Vector2.ZERO


func _sanitize_aim(raw: Variant) -> Vector3:
	if raw is Vector3:
		var aim: Vector3 = raw
		aim.y = 0.0
		if aim.length_squared() <= 0.0001:
			return Vector3.FORWARD
		return aim.normalized()
	if raw is Array and raw.size() >= 3:
		var aim_array := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
		aim_array.y = 0.0
		if aim_array.length_squared() <= 0.0001:
			return Vector3.FORWARD
		return aim_array.normalized()
	return Vector3.FORWARD


func _spawn_position_for_peer(peer_id: int) -> Vector3:
	var spawn_points: Array[Vector3] = [
		Vector3(-2.0, 0.0, -2.0),
		Vector3(2.0, 0.0, -2.0),
		Vector3(-2.0, 0.0, 2.0),
		Vector3(2.0, 0.0, 2.0),
	]
	return spawn_points[(peer_id - 1) % spawn_points.size()]


func _new_player_state(spawn_position: Vector3) -> Dictionary:
	return {
		"position": spawn_position,
		"velocity": Vector3.ZERO,
		"aim": Vector3.FORWARD,
		"health": 100,
		"weapon_index": 0,
		"last_input_tick": 0,
		"wants_shoot": false,
	}


@rpc("authority", "unreliable")
func receive_server_snapshot(_payload: Dictionary) -> void:
	pass


@rpc("authority", "reliable")
func receive_lobby_state(_payload: Dictionary) -> void:
	pass
