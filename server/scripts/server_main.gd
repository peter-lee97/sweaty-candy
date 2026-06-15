extends Node

const ENEMY_HP: int = 50
const ENEMY_MOVE_SPEED: float = 125.0
const ENEMY_SCORE: int = 100
const PROJ_SPEED: float = 500.0
const PROJ_DAMAGE: int = 25
const PROJ_COOLDOWN: float = 0.25
const HIT_RADIUS: float = 18.0
const ENEMY_COUNT: int = 5
const KNOCKBACK_FORCE: float = 400.0
const ENEMY_KNOCKBACK_DECAY: float = 8.0
const PLAYER_HALF_EXTENT: float = 14.0
const ENEMY_CONTACT_DAMAGE: int = 10
const ENEMY_HIT_RATE: float = 0.5
const CONTACT_RADIUS: float = 28.0

@export var listen_port: int = 7777
@export var max_players: int = 4
@export var move_speed: float = 300.0
@export var arena_half_size: float = 1400.0
@export var snapshot_rate_hz: float = 20.0
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
var _backend_server_id: String = ""
var _is_registering_backend: bool = false
var _player_shoot_timers: Dictionary = {}
var _enemies: Array[Dictionary] = []
var _projectiles: Array[Dictionary] = []
var _next_enemy_id: int = 0
var _next_proj_id: int = 0


func _ready() -> void:
	var started: bool = _start_server()
	if started:
		_register_server_in_backend()
		await get_tree().create_timer(5.0).timeout
		_spawn_enemies()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_server_tick += 1
	_step_player_simulation(delta)
	_step_enemy_simulation(delta)
	_step_projectile_simulation(delta)
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
	_player_shoot_timers[peer_id] = 0.0
	_notify_lobby_state()


func _on_peer_disconnected(peer_id: int) -> void:
	_players.erase(peer_id)
	_pending_inputs.erase(peer_id)
	_player_shoot_timers.erase(peer_id)
	_notify_lobby_state()


@rpc("any_peer", "call_remote", "unreliable")
func receive_server_snapshot(_payload: Dictionary) -> void:
	pass


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
		var limit: float = arena_half_size - PLAYER_HALF_EXTENT
		position.x = clamp(position.x, -limit, limit)
		position.y = clamp(position.y, -limit, limit)

		var aim: Vector2 = state["aim"]
		if intent.has("aim"):
			aim = intent["aim"]

		var weapon_cycle: int = intent.get("weapon_cycle", 0)
		var weapon_index: int = state["weapon_index"]
		if weapon_cycle != 0:
			var weapon_step: int = 1 if weapon_cycle > 0 else -1
			weapon_index = wrapi(weapon_index + weapon_step, 0, 4)

		# Shoot cooldown and projectile spawning
		var shoot_timer: float = _player_shoot_timers.get(peer_id, 0.0)
		shoot_timer -= delta
		if shoot_timer < 0.0:
			shoot_timer = 0.0
		_player_shoot_timers[peer_id] = shoot_timer

		if intent.get("shoot", false) and shoot_timer <= 0.0:
			_player_shoot_timers[peer_id] = PROJ_COOLDOWN
			_spawn_projectile(position, aim.normalized(), peer_id)

		state["position"] = position
		state["velocity"] = velocity
		state["aim"] = aim
		state["weapon_index"] = weapon_index
		state["last_input_tick"] = intent.get("tick", state["last_input_tick"])
		state["wants_shoot"] = intent.get("shoot", false)
		_players[peer_id] = state


func _step_enemy_simulation(delta: float) -> void:
	for enemy: Dictionary in _enemies:
		var target: Dictionary = _find_nearest_player_for(enemy["position"])
		var dir: Vector2 = Vector2.ZERO
		if target:
			dir = enemy["position"].direction_to(target["position"])
		var knockback: Vector2 = enemy.get("knockback", Vector2.ZERO)
		enemy["position"] += dir * ENEMY_MOVE_SPEED * delta + knockback * delta
		knockback = knockback.lerp(Vector2.ZERO, ENEMY_KNOCKBACK_DECAY * delta)
		if knockback.length_squared() < 4.0:
			knockback = Vector2.ZERO
		enemy["knockback"] = knockback
		enemy["position"].x = clamp(enemy["position"].x, -arena_half_size, arena_half_size)
		enemy["position"].y = clamp(enemy["position"].y, -arena_half_size, arena_half_size)

		enemy["damage_timer"] -= delta
		if enemy["damage_timer"] <= 0.0:
			for peer_id: int in _players.keys():
				var ps: Dictionary = _players[peer_id]
				if enemy["position"].distance_to(ps["position"]) < CONTACT_RADIUS:
					ps["health"] -= ENEMY_CONTACT_DAMAGE
					if ps["health"] < 0:
						ps["health"] = 0
					_players[peer_id] = ps
					enemy["damage_timer"] = ENEMY_HIT_RATE
					break


func _step_projectile_simulation(delta: float) -> void:
	var proj_indices_to_remove: Array[int] = []
	var i: int = 0
	while i < _projectiles.size():
		var proj: Dictionary = _projectiles[i]
		proj["position"] += proj["direction"] * PROJ_SPEED * delta

		var should_remove: bool = false

		if abs(proj["position"].x) > arena_half_size or abs(proj["position"].y) > arena_half_size:
			should_remove = true

		if not should_remove:
			for enemy: Dictionary in _enemies:
				if proj["position"].distance_to(enemy["position"]) < HIT_RADIUS:
					enemy["hp"] -= PROJ_DAMAGE
					enemy["knockback"] = proj["direction"] * KNOCKBACK_FORCE
					if enemy["hp"] <= 0:
						enemy["dead"] = true
					should_remove = true
					break

		if should_remove:
			proj_indices_to_remove.append(i)
			_projectiles.remove_at(i)
		else:
			i += 1

	var enemy_indices_to_remove: Array[int] = []
	var j: int = 0
	while j < _enemies.size():
		if _enemies[j].get("dead", false):
			enemy_indices_to_remove.append(j)
			_enemies.remove_at(j)
		else:
			j += 1


func _broadcast_snapshot() -> void:
	var payload: Dictionary = {
		"server_tick": _server_tick,
		"players": _players,
		"enemies": {},
		"projectiles": {},
	}
	for enemy: Dictionary in _enemies:
		payload["enemies"][str(enemy["id"])] = {
			"position": enemy["position"],
			"hp": enemy["hp"],
		}
	for proj: Dictionary in _projectiles:
		payload["projectiles"][str(proj["id"])] = {
			"position": proj["position"],
			"direction": proj["direction"],
		}
	rpc("receive_server_snapshot", payload)


func _find_nearest_player_for(from_pos: Vector2) -> Dictionary:
	var nearest: Dictionary
	var min_dist: float = INF
	for peer_id: int in _players.keys():
		var state: Dictionary = _players[peer_id]
		var dist: float = from_pos.distance_squared_to(state["position"])
		if dist < min_dist:
			min_dist = dist
			nearest = state
	return nearest


func _spawn_enemy(pos: Vector2) -> int:
	var eid: int = _next_enemy_id
	_next_enemy_id += 1
	_enemies.append({
		"id": eid,
		"position": pos,
		"hp": ENEMY_HP,
		"score_value": ENEMY_SCORE,
		"knockback": Vector2.ZERO,
		"damage_timer": 0.0,
	})
	push_warning("SERVER: Spawned enemy [id=%d, pos=%s]" % [eid, pos])
	return eid


func _spawn_projectile(pos: Vector2, dir: Vector2, _owner_peer: int) -> int:
	var pid: int = _next_proj_id
	_next_proj_id += 1
	_projectiles.append({
		"id": pid,
		"position": pos,
		"direction": dir,
	})
	return pid


func _spawn_enemies() -> void:
	var total: int = _enemies.size()
	for pos: Vector2 in [Vector2(-700.0, -700.0), Vector2(700.0, 700.0)]:
		_spawn_enemy(pos)
	push_warning("SERVER: Spawned %d new enemies (total=%d)" % [_enemies.size() - total, _enemies.size()])


func _notify_lobby_state() -> void:
	var payload: Dictionary = {
		"server_tick": _server_tick,
		"players": _players,
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
