extends Node2D

@onready var _player_spawn: Marker2D = %PlayerSpawn

var _shots_fired: int = 0
var _local_player: CharacterBody2D
var _network_tick: int = 0
var _remote_player_nodes: Dictionary = {}
var _server_enemy_nodes: Dictionary = {}
var _server_projectile_nodes: Dictionary = {}


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.projectile_fired.connect(_on_projectile_fired)
	GameEvents.enemy_killed.connect(_on_enemy_killed)

	if not GameData.multiplayer_session_active:
		_spawn_test_enemies()

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
	_spawn_player()


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


const _enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const _projectile_scene: PackedScene = preload("res://scenes/projectiles/projectile.tscn")


func _apply_snapshot(snapshot: Dictionary) -> void:
	var players: Dictionary = snapshot.get("players", {})
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

	var server_enemies: Dictionary = snapshot.get("enemies", {})
	var existing_enemy_ids: Array[String] = []
	for eid_str in server_enemies:
		var ed: Dictionary = server_enemies[eid_str]
		existing_enemy_ids.append(eid_str)
		if not _server_enemy_nodes.has(eid_str):
			var enemy: Node = _enemy_scene.instantiate()
			enemy.global_position = ed.get("position", Vector2.ZERO)
			%EntityContainer/Enemies.add_child(enemy)
			_server_enemy_nodes[eid_str] = enemy
		else:
			var enemy: Node = _server_enemy_nodes[eid_str]
			enemy.global_position = enemy.global_position.lerp(ed.get("position", Vector2.ZERO), 0.35)

	for eid_str in _server_enemy_nodes.keys():
		if not existing_enemy_ids.has(eid_str):
			var enemy: Node = _server_enemy_nodes[eid_str]
			GameEvents.enemy_killed.emit(enemy.global_position, 100)
			enemy.queue_free()
			_server_enemy_nodes.erase(eid_str)

	var server_projectiles: Dictionary = snapshot.get("projectiles", {})
	var existing_proj_ids: Array[String] = []
	for pid_str in server_projectiles:
		var pd: Dictionary = server_projectiles[pid_str]
		existing_proj_ids.append(pid_str)
		if not _server_projectile_nodes.has(pid_str):
			var proj: Node = _projectile_scene.instantiate()
			proj.global_position = pd.get("position", Vector2.ZERO)
			if proj.has_method("set_direction"):
				proj.set_direction(pd.get("direction", Vector2.RIGHT))
			add_child(proj)
			_server_projectile_nodes[pid_str] = proj
		else:
			var proj: Node = _server_projectile_nodes[pid_str]
			proj.global_position = proj.global_position.lerp(pd.get("position", Vector2.ZERO), 0.35)

	for pid_str in _server_projectile_nodes.keys():
		if not existing_proj_ids.has(pid_str):
			var proj: Node = _server_projectile_nodes[pid_str]
			proj.queue_free()
			_server_projectile_nodes.erase(pid_str)


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


func _compute_stats() -> Dictionary:
	return {"time": 0.0, "accuracy": 0.0, "fired": _shots_fired, "hit": 0}


func _spawn_test_enemies() -> void:
	var enemy_scene: PackedScene = load("res://scenes/enemies/enemy_base.tscn")
	for i in range(5):
		var enemy: Node = enemy_scene.instantiate()
		enemy.global_position = Vector2(randf_range(-600.0, 600.0), randf_range(-600.0, 600.0))
		%EntityContainer/Enemies.add_child(enemy)


func _on_enemy_killed(kill_position: Vector2, _score_value: int) -> void:
	if randf() < 0.15:
		var pickup_scene: PackedScene = load("res://scenes/pickups/health_pickup.tscn")
		var pickup: Area2D = pickup_scene.instantiate()
		pickup.global_position = kill_position
		%EntityContainer/Pickups.add_child(pickup)


func _on_player_died() -> void:
	var stats := _compute_stats()
	if GameData.multiplayer_session_active:
		NetworkClient.disconnect_from_server()
	GameEvents.game_completed.emit(false, stats.time, stats.accuracy, stats.fired, stats.hit)
