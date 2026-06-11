extends Node2D

@onready var _wave_manager: Node = %WaveManager
@onready var _player_spawn: Marker2D = %PlayerSpawn
@onready var _entity_container: Node2D = %EntityContainer

var _shots_fired: int = 0
var _shots_hit: int = 0
var _local_player: CharacterBody2D
var _network_tick: int = 0
var _remote_player_nodes: Dictionary = {}
var _enemy_scenes: Dictionary = {}


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.all_waves_cleared.connect(_on_all_waves_cleared)
	GameEvents.projectile_fired.connect(_on_projectile_fired)
	GameEvents.projectile_hit.connect(_on_projectile_hit)

	if GameData.multiplayer_session_active:
		_setup_network_mode()
	else:
		_spawn_player()


func _setup_network_mode() -> void:
	_wave_manager.queue_free()
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


func _apply_snapshot(players: Dictionary, enemies: Dictionary) -> void:
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

	var existing_enemy_ids: Array[String] = []
	for enemy in enemies.values():
		var ed: Dictionary = enemy
		var eid: String = str(ed.get("id", ""))
		existing_enemy_ids.append(eid)
		var spawned = get_node_or_null("EntityContainer/Enemies/" + eid)
		if not spawned:
			_spawn_network_enemy(eid, ed)
		else:
			spawned.global_position = spawned.global_position.lerp(ed.get("position", Vector2.ZERO), 0.35)

	for child in _entity_container.get_node("Enemies").get_children():
		if not existing_enemy_ids.has(child.name):
			child.queue_free()


func _spawn_remote_player(id: String, data: Dictionary) -> void:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	var node: CharacterBody2D = scene.instantiate()
	node.name = id
	node.global_position = data.get("position", Vector2.ZERO)
	node.get_node("Sprite").color = Color(0.3, 0.6, 0.9, 1.0)
	node.set_meta("network_id", id)
	add_child(node)
	_remote_player_nodes[id] = node


func _spawn_network_enemy(id: String, data: Dictionary) -> void:
	if not _enemy_scenes.size():
		_enemy_scenes["base"] = load("res://scenes/enemies/enemy.tscn")
		_enemy_scenes["fast"] = load("res://scenes/enemies/enemy_fast.tscn")
		_enemy_scenes["tank"] = load("res://scenes/enemies/enemy_tank.tscn")
	var type: String = str(data.get("type", "base"))
	var scene: PackedScene = _enemy_scenes.get(type, _enemy_scenes["base"])
	var enemy: CharacterBody2D = scene.instantiate()
	enemy.name = id
	enemy.global_position = data.get("position", Vector2.ZERO)
	enemy.network_controlled = true
	_entity_container.get_node("Enemies").add_child(enemy)


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
	if GameData.multiplayer_session_active:
		var accuracy: float = float(_shots_hit) / max(1.0, float(_shots_fired))
		return {"time": 0.0, "accuracy": accuracy, "fired": _shots_fired, "hit": _shots_hit}
	var elapsed: float = 0.0
	if is_instance_valid(_wave_manager):
		elapsed = _wave_manager.get_elapsed_time()
	var accuracy: float = float(_shots_hit) / max(1.0, float(_shots_fired))
	return {"time": elapsed, "accuracy": accuracy, "fired": _shots_fired, "hit": _shots_hit}


func _on_player_died() -> void:
	var stats := _compute_stats()
	if GameData.multiplayer_session_active:
		NetworkClient.disconnect_from_server()
	GameEvents.game_completed.emit(false, stats.time, stats.accuracy, stats.fired, stats.hit)


func _on_all_waves_cleared() -> void:
	var stats := _compute_stats()
	GameEvents.game_completed.emit(true, stats.time, stats.accuracy, stats.fired, stats.hit)
	GameEvents.game_won.emit()
