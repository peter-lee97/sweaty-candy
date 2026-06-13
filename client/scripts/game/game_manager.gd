extends Node2D

@onready var _player_spawn: Marker2D = %PlayerSpawn

var _shots_fired: int = 0
var _shots_hit: int = 0
var _local_player: CharacterBody2D
var _network_tick: int = 0
var _remote_player_nodes: Dictionary = {}


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.projectile_fired.connect(_on_projectile_fired)
	GameEvents.projectile_hit.connect(_on_projectile_hit)

	if GameData.multiplayer_session_active:
		_setup_network_mode()
	else:
		_spawn_player()


func _setup_network_mode() -> void:
	NetworkClient.snapshot_received.connect(_apply_snapshot)
	NetworkClient.connected_to_server.connect(_on_connected_to_server)
	NetworkClient.disconnected_from_server.connect(_on_disconnected_from_server)
	NetworkClient.connect_to_server(GameData.multiplayer_server_url)


func _on_connected_to_server() -> void:
	_spawn_local_player()


func _spawn_local_player() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	_local_player = player_scene.instantiate()
	_local_player.global_position = _player_spawn.global_position
	add_child(_local_player)


func _physics_process(_delta: float) -> void:
	if not GameData.multiplayer_session_active or not _local_player:
		return
	if not NetworkClient.has_connection():
		return
	_network_tick += 1
	var move_dir: Vector2 = _local_player.velocity.normalized() if _local_player.velocity.length_squared() > 0.01 else Vector2.ZERO
	var aim_dir: Vector2 = _local_player._aim_direction
	var wants_shoot: bool = Input.is_action_pressed("shoot") and not GameEvents.ui_blocking_input
	NetworkClient.send_player_intent(_network_tick, move_dir, aim_dir, wants_shoot, 0)


func _apply_snapshot(players: Dictionary) -> void:
	var existing_ids: Array[String] = []
	for id in players:
		var pd: Dictionary = players[id]
		existing_ids.append(str(id))
		if id == NetworkClient.get_own_peer_id():
			continue
		if not _remote_player_nodes.has(str(id)):
			_spawn_remote_player(str(id), pd)
		else:
			var node: CharacterBody2D = _remote_player_nodes[str(id)]
			node.global_position = node.global_position.lerp(pd.get("position", Vector2.ZERO), 0.35)

	for id in _remote_player_nodes.keys():
		if not existing_ids.has(id):
			var node: Node = _remote_player_nodes[id]
			node.queue_free()
			_remote_player_nodes.erase(id)


func _spawn_remote_player(id: String, data: Dictionary) -> void:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var node: CharacterBody2D = scene.instantiate()
	node.name = id
	node.global_position = data.get("position", Vector2.ZERO)
	node.get_node("Sprite").color = Color(0.3, 0.6, 0.9, 1.0)
	node.set_meta("network_id", id)
	add_child(node)
	_remote_player_nodes[id] = node


func _spawn_player() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	_local_player = player_scene.instantiate()
	_local_player.global_position = _player_spawn.global_position
	add_child(_local_player)


func _on_disconnected_from_server() -> void:
	GameEvents.game_completed.emit(false, 0.0, 0.0, 0, 0)


func _on_projectile_fired() -> void:
	_shots_fired += 1


func _on_projectile_hit() -> void:
	_shots_hit += 1


func _compute_stats() -> Dictionary:
	var accuracy: float = float(_shots_hit) / max(1.0, float(_shots_fired))
	return {"time": 0.0, "accuracy": accuracy, "fired": _shots_fired, "hit": _shots_hit}


func _on_player_died() -> void:
	var stats := _compute_stats()
	if GameData.multiplayer_session_active:
		NetworkClient.disconnect_from_server()
	GameEvents.game_completed.emit(false, stats.time, stats.accuracy, stats.fired, stats.hit)
