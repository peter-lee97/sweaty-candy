extends Node

@export var listen_port: int = 7777
@export var max_players: int = 4
@export var move_speed: float = 300.0
@export var arena_half_size: float = 1400.0
@export var snapshot_rate_hz: float = 20.0
@export var initial_wave_enemy_count: int = 6
@export var enemy_spawn_interval: float = 0.8
@export var enemy_move_speed: float = 125.0
@export var wave_cooldown_sec: float = 3.0
@export var backend_base_url: String = "http://127.0.0.1:8787"
@export var backend_server_name: String = "Godot 2D Server"
@export var advertised_host: String = "127.0.0.1"
@export var heartbeat_interval_sec: float = 10.0
@export var registration_retry_interval_sec: float = 3.0

var _server_tick: int = 0
var _snapshot_timer: float = 0.0
var _heartbeat_timer: float = 0.0
var _registration_retry_timer: float = 0.0
var _players: Dictionary = {}
var _pending_inputs: Dictionary = {}
var _enemies: Dictionary = {}
var _next_enemy_id: int = 1
var _current_wave: int = 0
var _enemies_to_spawn: int = 0
var _enemy_spawn_timer: float = 0.0
var _wave_cooldown_timer: float = 0.0
var _is_spawning_wave: bool = false
var _backend_server_id: String = ""
var _is_registering_backend: bool = false


func _ready() -> void:
	var started: bool = _start_server()
	if started:
		_register_server_in_backend()
		_start_next_wave()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_server_tick += 1
	_step_player_simulation(delta)
	_update_wave_state(delta)
	_simulate_enemies(delta)
	_snapshot_timer += delta
	if _snapshot_timer >= (1.0 / snapshot_rate_hz):
		_snapshot_timer = 0.0
		_broadcast_snapshot()
	if _backend_server_id.is_empty():
		_registration_retry_timer += delta
		if _registration_retry_timer >= registration_retry_interval_sec and not _is_registering_backend:
			_registration_retry_timer = 0.0
			_register_server_in_backend()
	if not _backend_server_id.is_empty():
		_heartbeat_timer += delta
		if _heartbeat_timer >= heartbeat_interval_sec:
			_heartbeat_timer = 0.0
			_send_backend_heartbeat()


func _start_server() -> bool:
	var peer := WebSocketMultiplayerPeer.new()
	var error: Error = peer.create_server(listen_port)
	if error != OK:
		push_error("Failed to start WebSocket server on port %d (error %d)." % [listen_port, error])
		return false
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	push_warning("Server listening on ws://0.0.0.0:%d" % listen_port)
	return true


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
func submit_player_intent(tick: int, move: Vector2, aim: Vector2, shoot: bool, weapon_cycle: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id: int = multiplayer.get_remote_sender_id()
	if not _players.has(peer_id):
		return
	_pending_inputs[peer_id] = {
		"tick": tick,
		"move": move,
		"aim": aim,
		"shoot": shoot,
		"weapon_cycle": weapon_cycle
	}


func _step_player_simulation(delta: float) -> void:
	for peer_id: int in _players.keys():
		var state: Dictionary = _players[peer_id]
		var intent: Dictionary = _pending_inputs.get(peer_id, {})

		var move_input: Vector2 = intent.get("move", Vector2.ZERO)
		var velocity: Vector2 = move_input.normalized() * move_speed
		var position: Vector2 = state["position"] + velocity * delta
		position.x = clamp(position.x, -arena_half_size, arena_half_size)
		position.y = clamp(position.y, -arena_half_size, arena_half_size)

		var aim: Vector2 = state["aim"]
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
		"enemies": _enemies,
		"wave": _current_wave,
	}
	rpc("receive_server_snapshot", payload)


func _notify_lobby_state() -> void:
	var payload: Dictionary = {
		"server_tick": _server_tick,
		"players": _players,
		"enemies": _enemies,
		"wave": _current_wave,
	}
	rpc("receive_lobby_state", payload)


func _spawn_position_for_peer(peer_id: int) -> Vector2:
	var spawn_points: Array[Vector2] = [
		Vector2(-200.0, -200.0),
		Vector2(200.0, -200.0),
		Vector2(-200.0, 200.0),
		Vector2(200.0, 200.0),
	]
	return spawn_points[(peer_id - 1) % spawn_points.size()]


func _new_player_state(spawn_position: Vector2) -> Dictionary:
	return {
		"position": spawn_position,
		"velocity": Vector2.ZERO,
		"aim": Vector2.DOWN,
		"health": 100,
		"weapon_index": 0,
		"last_input_tick": 0,
		"wants_shoot": false,
	}


func _update_wave_state(delta: float) -> void:
	if _is_spawning_wave:
		_enemy_spawn_timer -= delta
		if _enemy_spawn_timer <= 0.0 and _enemies_to_spawn > 0:
			_spawn_enemy()
			_enemies_to_spawn -= 1
			_enemy_spawn_timer = enemy_spawn_interval
		if _enemies_to_spawn <= 0:
			_is_spawning_wave = false
		return
	if _enemies.is_empty():
		_wave_cooldown_timer += delta
		if _wave_cooldown_timer >= wave_cooldown_sec:
			_start_next_wave()


func _start_next_wave() -> void:
	_current_wave += 1
	_enemies_to_spawn = initial_wave_enemy_count + ((_current_wave - 1) * 2)
	_enemy_spawn_timer = 0.0
	_wave_cooldown_timer = 0.0
	_is_spawning_wave = true


func _spawn_enemy() -> void:
	var enemy_id: String = "e%d" % _next_enemy_id
	_next_enemy_id += 1
	_enemies[enemy_id] = {
		"id": enemy_id,
		"type": "base",
		"position": _get_random_edge_position(),
		"health": 50
	}


func _simulate_enemies(delta: float) -> void:
	if _enemies.is_empty():
		return
	for enemy_id: String in _enemies.keys():
		var enemy_state: Dictionary = _enemies[enemy_id]
		var position: Vector2 = enemy_state.get("position", Vector2.ZERO)
		var target_position: Vector2 = _find_nearest_player_position(position)
		var direction: Vector2 = target_position - position
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()
			position += direction * enemy_move_speed * delta
			position.x = clamp(position.x, -arena_half_size, arena_half_size)
			position.y = clamp(position.y, -arena_half_size, arena_half_size)
			enemy_state["position"] = position
			_enemies[enemy_id] = enemy_state


func _find_nearest_player_position(from_position: Vector2) -> Vector2:
	if _players.is_empty():
		return from_position
	var closest_position: Vector2 = from_position
	var closest_distance_sq: float = INF
	for player_state: Dictionary in _players.values():
		var player_position: Vector2 = player_state.get("position", from_position)
		var distance_sq: float = from_position.distance_squared_to(player_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_position = player_position
	return closest_position


func _get_random_edge_position() -> Vector2:
	var side: int = randi() % 4
	var t: float = randf_range(-arena_half_size, arena_half_size)
	var offset: float = arena_half_size - 100.0
	match side:
		0: return Vector2(-offset, t)
		1: return Vector2(offset, t)
		2: return Vector2(t, -offset)
		_: return Vector2(t, offset)


@rpc("any_peer", "call_remote", "unreliable")
func receive_server_snapshot(_payload: Dictionary) -> void:
	pass


@rpc("any_peer", "call_remote", "reliable")
func receive_lobby_state(_payload: Dictionary) -> void:
	pass


func _register_server_in_backend() -> void:
	if _is_registering_backend:
		return
	_is_registering_backend = true
	var target_url: String = backend_base_url.strip_edges().trim_suffix("/")
	var payload: Dictionary = {
		"name": backend_server_name,
		"host": advertised_host,
		"port": listen_port,
		"capacity": max_players
	}
	var result: Dictionary = await _http_json("POST", "%s/v1/servers/register" % target_url, payload)
	_is_registering_backend = false
	if not result.get("ok", false):
		push_warning("Backend register failed: %s" % result.get("error", "Unknown error"))
		return
	var body: Dictionary = result.get("body", {})
	_backend_server_id = body.get("id", "")
	if _backend_server_id.is_empty():
		push_warning("Backend register returned empty server id.")
		return
	push_warning("Registered backend server id %s" % _backend_server_id)
	_heartbeat_timer = 0.0
	_send_backend_heartbeat()


func _send_backend_heartbeat() -> void:
	if _backend_server_id.is_empty():
		return
	var result: Dictionary = await _http_json(
		"POST",
		"%s/v1/servers/%s/heartbeat" % [backend_base_url.strip_edges().trim_suffix("/"), _backend_server_id],
		{}
	)
	if not result.get("ok", false):
		push_warning("Backend heartbeat failed: %s" % result.get("error", "Unknown error"))


func _http_json(method: String, url: String, payload: Dictionary) -> Dictionary:
	var request := HTTPRequest.new()
	add_child(request)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var request_body: String = JSON.stringify(payload)
	var method_id: int = HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET
	var err: Error = request.request(url, headers, method_id, request_body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "request error %d" % err}
	var completed: Array = await request.request_completed
	request.queue_free()
	var request_result: int = completed[0]
	var status_code: int = completed[1]
	if request_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": status_code, "error": "HTTP request failed (result %d, status %d)" % [request_result, status_code]}
	var text: String = PackedByteArray(completed[3]).get_string_from_utf8()
	var parsed: Variant = {}
	if not text.is_empty():
		var json_result: Variant = JSON.parse_string(text)
		if json_result != null:
			parsed = json_result
	var ok: bool = status_code >= 200 and status_code < 300
	var error_message: String = ""
	if not ok:
		error_message = parsed.get("error", "HTTP %d" % status_code)
	return {"ok": ok, "status": status_code, "body": parsed, "error": error_message}