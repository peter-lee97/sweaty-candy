extends Node2D

const PROJ_POOL_SIZE: int = 50
const ENEMY_POOL_SIZE: int = 10
const FAST_ENEMY_POOL_SIZE: int = 10
const TANK_ENEMY_POOL_SIZE: int = 5
const PICKUP_POOL_SIZE: int = 20
const SMOOTH_RATE: float = 12.0
const INTENT_SEND_HZ: float = 20.0
const WAVE_DELAY: float = 3.0
const ARENA_HALF_SIZE: float = 1400.0
const SPAWN_STAGGER: float = 0.35
const SPAWN_INSET: float = 80.0
const SPAWN_BAND_WIDTH: float = 200.0
const MAX_ENEMIES_PER_WAVE: int = 100

@onready var _player_spawn: Marker2D = %PlayerSpawn
@onready var _projectiles_container: Node2D = %EntityContainer/Projectiles
@onready var _enemies_container: Node2D = %EntityContainer/Enemies
@onready var _pickups_container: Node2D = %EntityContainer/Pickups

var _shots_fired: int = 0
var _shots_hit: int = 0
var _local_player: CharacterBody2D
var _network_tick: int = 0
var _remote_player_nodes: Dictionary = {}
var _server_enemy_nodes: Dictionary = {}
var _server_projectile_nodes: Dictionary = {}
var _projectile_pool: Array[Node] = []
var _enemy_pool: Array[Node] = []
var _fast_enemy_pool: Array[Node] = []
var _tank_enemy_pool: Array[Node] = []
var _pickup_pool: Array[Node] = []
var _sp_enemy_nodes: Array[Node] = []
var _sp_projectile_nodes: Array[Node] = []
var _sp_pickup_nodes: Array[Node] = []
var _remote_targets: Dictionary = {}
var _enemy_targets: Dictionary = {}
var _intent_timer: float = 0.0
var _spawn_countdown: float = 5.0
var _last_countdown_tick: int = 5
var _current_wave: int = 0
var _wave_enemies_alive: int = 0

var _is_respawning: bool = false
var _is_spawning: bool = false
var _game_ended: bool = false

const _enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_base.tscn")
const _enemy_fast_scene: PackedScene = preload("res://scenes/enemies/enemy_fast.tscn")
const _enemy_tank_scene: PackedScene = preload("res://scenes/enemies/enemy_tank.tscn")
const _projectile_scene: PackedScene = preload("res://scenes/projectiles/projectile.tscn")
const _player_scene: PackedScene = preload("res://scenes/player/player.tscn")
const _pickup_scene: PackedScene = preload("res://scenes/pickups/health_pickup.tscn")


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.projectile_fired.connect(_on_projectile_fired)
	GameEvents.projectile_hit.connect(_on_projectile_hit)
	GameEvents.enemy_killed.connect(_on_enemy_killed)
	GameEvents.countdown_finished.connect(_on_countdown_finished)
	GameEvents.spawn_projectile_requested.connect(_on_spawn_projectile_requested)
	GameEvents.projectile_expired.connect(_on_projectile_expired)
	GameEvents.enemy_released.connect(_on_enemy_released)
	GameEvents.pickup_collected.connect(_on_pickup_collected)
	GameEvents.pickup_expired.connect(_on_pickup_expired)

	_populate_pools()
	if GameData.multiplayer_session_active and GameData.multiplayer_server_url != "":
		_setup_network_mode()
	else:
		GameData.multiplayer_session_active = false
		_spawn_player()


func _on_countdown_finished() -> void:
	if not GameData.multiplayer_session_active:
		_start_wave(1)


func _get_wave_base_count(wave: int) -> int:
	if wave < 3:
		return 5
	elif wave < 5:
		return 6
	elif wave < 7:
		return 8
	else:
		return 8 + (wave - 7) / 2


func _get_wave_composition(wave: int, count: int) -> Array[String]:
	var available: Array[String] = ["base"]
	if wave >= 3:
		available.append("fast")
	if wave >= 5:
		available.append("tank")
	var result: Array[String] = []
	for i in count:
		result.append(available[i % available.size()])
	return result


func _get_player_count() -> int:
	if GameData.multiplayer_session_active:
		return _remote_player_nodes.size() + 1
	return 1


func _get_random_spawn_position() -> Vector2:
	var shapes: Array[Node] = %EnemySpawnZone.get_children()
	var shape: CollisionShape2D = shapes[randi() % shapes.size()]
	var rect: RectangleShape2D = shape.shape
	var origin: Vector2 = shape.global_position
	var hs: Vector2 = rect.size * 0.5
	return origin + Vector2(randf_range(-hs.x, hs.x), randf_range(-hs.y, hs.y))


func _start_wave(wave: int) -> void:
	if _game_ended:
		return
	_current_wave = wave
	var player_count: int = _get_player_count()
	var base_count: int = _get_wave_base_count(wave)
	var multiplier: float = 1.0 + (player_count - 1) * 0.5
	var total: int = clampi(ceili(base_count * multiplier), 1, MAX_ENEMIES_PER_WAVE)
	_wave_enemies_alive = total
	_is_spawning = true
	var types: Array[String] = _get_wave_composition(wave, total)
	GameEvents.wave_started.emit(wave)
	push_warning("CLIENT: Wave %d started (%d enemies)" % [wave, total])
	for i in total:
		var enemy: Node = _acquire_enemy(types[i])
		if enemy:
			enemy.global_position = _get_random_spawn_position()
			if enemy.has_method("activate"):
				enemy.activate(enemy.global_position)
			_sp_enemy_nodes.append(enemy)
		await get_tree().create_timer(SPAWN_STAGGER).timeout
	_is_spawning = false
	if _wave_enemies_alive <= 0:
		GameEvents.wave_completed.emit(_current_wave)
		_current_wave += 1
		await get_tree().create_timer(WAVE_DELAY).timeout
		_start_wave(_current_wave)


func _populate_pools() -> void:
	for i in range(PROJ_POOL_SIZE):
		var proj: Node = _projectile_scene.instantiate()
		proj.hide()
		proj.process_mode = Node.PROCESS_MODE_DISABLED
		_projectiles_container.add_child(proj)
		_projectile_pool.append(proj)

	for i in range(ENEMY_POOL_SIZE):
		var enemy: Node = _enemy_scene.instantiate()
		enemy.hide()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.set_meta("_pooled", true)
		enemy.set_meta("_managed_by_pool", true)
		_enemies_container.add_child(enemy)
		_enemy_pool.append(enemy)

	for i in range(FAST_ENEMY_POOL_SIZE):
		var enemy: Node = _enemy_fast_scene.instantiate()
		enemy.hide()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.set_meta("_pooled", true)
		enemy.set_meta("_managed_by_pool", true)
		_enemies_container.add_child(enemy)
		_fast_enemy_pool.append(enemy)

	for i in range(TANK_ENEMY_POOL_SIZE):
		var enemy: Node = _enemy_tank_scene.instantiate()
		enemy.hide()
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.set_meta("_pooled", true)
		enemy.set_meta("_managed_by_pool", true)
		_enemies_container.add_child(enemy)
		_tank_enemy_pool.append(enemy)

	for i in range(PICKUP_POOL_SIZE):
		var pickup: Node = _pickup_scene.instantiate()
		pickup.hide()
		pickup.process_mode = Node.PROCESS_MODE_DISABLED
		pickup.set_meta("_pooled", true)
		_pickups_container.add_child(pickup)
		_pickup_pool.append(pickup)


func _acquire_proj() -> Node:
	if _projectile_pool.is_empty():
		return null
	var proj: Node = _projectile_pool.pop_back()
	if proj.get_parent() == null:
		_projectiles_container.add_child(proj)
	proj.show()
	proj.process_mode = Node.PROCESS_MODE_INHERIT
	return proj


func _release_proj(proj: Node) -> void:
	if proj in _projectile_pool:
		return
	if proj.has_method("deactivate"):
		proj.deactivate()
	_projectile_pool.append(proj)


func _acquire_enemy(type: String = "base") -> Node:
	var scene: PackedScene = _enemy_scene
	var pool: Array[Node] = _enemy_pool
	match type:
		"fast":
			scene = _enemy_fast_scene
			pool = _fast_enemy_pool
		"tank":
			scene = _enemy_tank_scene
			pool = _tank_enemy_pool
	var enemy: Node
	if not pool.is_empty():
		enemy = pool.pop_back()
	else:
		enemy = scene.instantiate()
		if enemy.get_parent() == null:
			_enemies_container.add_child(enemy)
		enemy.set_meta("_pooled", false)
		enemy.set_meta("_managed_by_pool", false)
	enemy.show()
	enemy.process_mode = Node.PROCESS_MODE_INHERIT
	enemy.set_physics_process(false)
	enemy.set_meta("_enemy_type", type)
	return enemy


func _release_enemy(enemy: Node) -> void:
	if enemy in _enemy_pool or enemy in _fast_enemy_pool or enemy in _tank_enemy_pool:
		return
	if enemy.has_method("deactivate"):
		enemy.deactivate()
	if enemy.get_meta("_pooled", false):
		var type: String = enemy.get_meta("_enemy_type", "base")
		match type:
			"fast":
				_fast_enemy_pool.append(enemy)
			"tank":
				_tank_enemy_pool.append(enemy)
			_:
				_enemy_pool.append(enemy)
	else:
		enemy.queue_free()


func _acquire_pickup() -> Node:
	if _pickup_pool.is_empty():
		return null
	var pickup: Node = _pickup_pool.pop_back()
	if pickup.get_parent() == null:
		_pickups_container.add_child(pickup)
	return pickup


func _release_pickup(pickup: Node) -> void:
	if pickup in _pickup_pool:
		return
	if pickup.has_method("deactivate"):
		pickup.deactivate()
	_pickup_pool.append(pickup)


func _on_spawn_projectile_requested(pos: Vector2, dir: Vector2) -> void:
	if _game_ended:
		return
	if GameData.multiplayer_session_active:
		return
	var proj: Node = _acquire_proj()
	if proj == null:
		return
	if proj.has_method("activate"):
		proj.activate(pos, dir)
	_sp_projectile_nodes.append(proj)


func _on_projectile_expired(proj: Node) -> void:
	_sp_projectile_nodes.erase(proj)
	_release_proj(proj)


func _on_enemy_released(enemy: Node) -> void:
	_sp_enemy_nodes.erase(enemy)
	_release_enemy(enemy)


func _on_pickup_collected(pickup: Node) -> void:
	_sp_pickup_nodes.erase(pickup)
	_release_pickup(pickup)


func _on_pickup_expired(pickup: Node) -> void:
	_sp_pickup_nodes.erase(pickup)
	_release_pickup(pickup)


func _setup_network_mode() -> void:
	NetworkClient.snapshot_received.connect(_apply_snapshot)
	NetworkClient.connected_to_server.connect(_on_connected_to_server)
	NetworkClient.disconnected_from_server.connect(_on_disconnected_from_server)
	NetworkClient.connection_failed.connect(_on_connection_failed)
	NetworkClient.connect_to_server(GameData.multiplayer_server_url)


func _on_connected_to_server() -> void:
	_spawn_player()


func _physics_process(delta: float) -> void:
	if GameData.multiplayer_session_active:
		for node_id in _remote_targets:
			var node: CharacterBody2D = _remote_player_nodes.get(node_id)
			if node:
				node.global_position = node.global_position.lerp(
					_remote_targets[node_id], 1.0 - exp(-delta * SMOOTH_RATE))
		for eid_str in _enemy_targets:
			var node: Node = _server_enemy_nodes.get(eid_str)
			if node:
				node.global_position = node.global_position.lerp(
					_enemy_targets[eid_str], 1.0 - exp(-delta * SMOOTH_RATE))

	if _spawn_countdown > 0.0:
		_spawn_countdown -= delta
		var seconds: int = ceili(_spawn_countdown)
		if seconds != _last_countdown_tick:
			_last_countdown_tick = seconds
			GameEvents.countdown_tick.emit(seconds)
		if _spawn_countdown <= 0.0:
			_spawn_countdown = 0.0
			GameEvents.countdown_finished.emit()

	if not GameData.multiplayer_session_active or not _local_player:
		return
	if _is_respawning:
		return
	if not NetworkClient.has_connection():
		return
	_network_tick += 1

	var move_dir: Vector2 = _local_player.velocity.normalized() if _local_player.velocity.length_squared() > 0.01 else Vector2.ZERO
	var aim_dir: Vector2 = _local_player._aim_direction
	var wants_shoot: bool = Input.is_action_pressed("shoot") and not GameEvents.ui_blocking_input
	var weapon_cycle: int = 0
	if Input.is_action_just_pressed("cycle_next"):
		weapon_cycle = 1
	elif Input.is_action_just_pressed("cycle_prev"):
		weapon_cycle = -1

	_intent_timer += delta
	if _intent_timer >= 1.0 / INTENT_SEND_HZ:
		_intent_timer -= 1.0 / INTENT_SEND_HZ
		NetworkClient.send_player_intent(_network_tick, move_dir, aim_dir, wants_shoot, weapon_cycle)


func _apply_snapshot(snapshot: Dictionary) -> void:
	if _game_ended:
		return
	if snapshot.get("game_over", false) and is_instance_valid(_local_player):
		_local_player._die()
		return

	var players: Dictionary = snapshot.get("players", {})
	var existing_ids: Array[String] = []
	for id in players:
		var pd: Dictionary = players[id]
		existing_ids.append(str(id))
		if id == NetworkClient.get_own_peer_id():
			if _local_player:
				var server_pos: Vector2 = pd.get("position", _local_player.global_position)
				var error: float = _local_player.global_position.distance_to(server_pos)
				if error > 48.0:
					_local_player.global_position = server_pos
				elif error > 4.0:
					_local_player.global_position = _local_player.global_position.lerp(server_pos, 0.3)
				var server_health: int = pd.get("health", _local_player.health)
				if server_health < _local_player.health and not _is_respawning:
					_local_player.health = server_health
					GameEvents.player_health_changed.emit(_local_player.health, _local_player.max_health)
				var respawn_timer: float = pd.get("respawn_timer", 0.0)
				if respawn_timer > 0.0:
					_is_respawning = true
					_local_player.hide()
					GameEvents.respawn_tick.emit(respawn_timer)
				elif _is_respawning and server_health > 0:
					_is_respawning = false
					_local_player.show()
					_local_player.health = server_health
					_local_player.global_position = pd.get("position", Vector2.ZERO)
					GameEvents.player_health_changed.emit(_local_player.health, _local_player.max_health)
					GameEvents.respawn_complete.emit()
				elif not _is_respawning and server_health <= 0:
					var has_survivors: bool = false
					for pid in players:
						if players[pid].get("health", 0) > 0:
							has_survivors = true
							break
					if not has_survivors:
						_local_player._die()
			continue
		if not _remote_player_nodes.has(str(id)):
			_spawn_remote_player(str(id), pd)
		var node: Node = _remote_player_nodes.get(str(id))
		if node:
			var is_dead: bool = pd.get("health", 0) <= 0
			node.visible = not is_dead
			_remote_targets[str(id)] = pd.get("position", Vector2.ZERO)

	for id in _remote_player_nodes.keys():
		if not existing_ids.has(id):
			var node: Node = _remote_player_nodes[id]
			_remote_targets.erase(id)
			node.queue_free()
			_remote_player_nodes.erase(id)

	var server_enemies: Dictionary = snapshot.get("enemies", {})
	var existing_enemy_ids: Array[String] = []
	for eid_str in server_enemies:
		var ed: Dictionary = server_enemies[eid_str]
		existing_enemy_ids.append(eid_str)
		if not _server_enemy_nodes.has(eid_str):
			var enemy_type: String = ed.get("type", "base")
			var enemy: Node = _acquire_enemy(enemy_type)
			if enemy:
				enemy.global_position = ed.get("position", Vector2.ZERO)
				_server_enemy_nodes[eid_str] = enemy
		_enemy_targets[eid_str] = ed.get("position", Vector2.ZERO)

	for eid_str in _server_enemy_nodes.keys():
		if not existing_enemy_ids.has(eid_str):
			var enemy: Node = _server_enemy_nodes[eid_str]
			_enemy_targets.erase(eid_str)
			GameEvents.enemy_killed.emit(enemy.global_position, 100)
			_release_enemy(enemy)
			_server_enemy_nodes.erase(eid_str)

	var server_projectiles: Dictionary = snapshot.get("projectiles", {})
	var existing_proj_ids: Array[String] = []
	for pid_str in server_projectiles:
		var pd: Dictionary = server_projectiles[pid_str]
		existing_proj_ids.append(pid_str)
		if not _server_projectile_nodes.has(pid_str):
			var proj: Node = _acquire_proj()
			if proj:
				proj.global_position = pd.get("position", Vector2.ZERO)
				if proj.has_method("set_direction"):
					proj.set_direction(pd.get("direction", Vector2.RIGHT))
				_server_projectile_nodes[pid_str] = proj

	for pid_str in _server_projectile_nodes.keys():
		if not existing_proj_ids.has(pid_str):
			var proj: Node = _server_projectile_nodes[pid_str]
			_release_proj(proj)
			_server_projectile_nodes.erase(pid_str)

	var wave: int = snapshot.get("wave", 0)
	if wave > _current_wave:
		_current_wave = wave
		GameEvents.wave_started.emit(wave)


func _spawn_remote_player(id: String, data: Dictionary) -> void:
	var node: CharacterBody2D = _player_scene.instantiate()
	node.name = id
	node.global_position = data.get("position", Vector2.ZERO)
	node.get_node("%Sprite").color = Color(0.3, 0.6, 0.9, 1.0)
	node.set_meta("network_id", id)
	node.set_physics_process(false)
	add_child(node)
	_remote_player_nodes[id] = node
	_remote_targets[id] = data.get("position", Vector2.ZERO)


func _spawn_player() -> void:
	_local_player = _player_scene.instantiate()
	var spawn_offset: Vector2 = Vector2(randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))
	_local_player.global_position = _player_spawn.global_position + spawn_offset
	add_child(_local_player)

	var camera: Node = %Camera2D
	if camera:
		camera.get_parent().remove_child(camera)
		_local_player.add_child(camera)
		camera.position = Vector2.ZERO


func _cleanup_mp_resources() -> void:
	for id in _remote_player_nodes.keys():
		var node: Node = _remote_player_nodes[id]
		_remote_targets.erase(id)
		if is_instance_valid(node):
			node.queue_free()
	_remote_player_nodes.clear()
	_remote_targets.clear()

	for eid_str in _server_enemy_nodes.keys():
		var node: Node = _server_enemy_nodes[eid_str]
		_enemy_targets.erase(eid_str)
		if is_instance_valid(node):
			node.queue_free()
	_server_enemy_nodes.clear()
	_enemy_targets.clear()

	for pid_str in _server_projectile_nodes.keys():
		var node: Node = _server_projectile_nodes[pid_str]
		if is_instance_valid(node):
			_release_proj(node)
	_server_projectile_nodes.clear()

	for proj in _projectile_pool:
		if is_instance_valid(proj):
			proj.queue_free()
	_projectile_pool.clear()

	for enemy in _enemy_pool:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_enemy_pool.clear()

	for enemy in _fast_enemy_pool:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_fast_enemy_pool.clear()

	for enemy in _tank_enemy_pool:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_tank_enemy_pool.clear()

	for pickup in _pickup_pool:
		if is_instance_valid(pickup):
			pickup.queue_free()
	_pickup_pool.clear()

	_sp_enemy_nodes.clear()
	_sp_projectile_nodes.clear()
	_sp_pickup_nodes.clear()
	_local_player = null


func _on_disconnected_from_server() -> void:
	if _game_ended:
		return
	_game_ended = true
	_cleanup_mp_resources()
	GameEvents.game_completed.emit(false, 0.0, 0.0, 0, 0)


func _on_connection_failed(_reason: String) -> void:
	if _game_ended:
		return
	_game_ended = true
	_cleanup_mp_resources()
	GameEvents.game_completed.emit(false, 0.0, 0.0, 0, 0)


func _on_projectile_fired() -> void:
	_shots_fired += 1


func _on_projectile_hit() -> void:
	_shots_hit += 1


func _compute_stats() -> Dictionary:
	return {"time": 0.0, "accuracy": 0.0, "fired": _shots_fired, "hit": _shots_hit}


func _on_enemy_killed(kill_position: Vector2, _score_value: int) -> void:
	if _game_ended:
		return
	if GameData.multiplayer_session_active:
		return
	_wave_enemies_alive -= 1
	if _wave_enemies_alive <= 0 and not _is_spawning:
		GameEvents.wave_completed.emit(_current_wave)
		_current_wave += 1
		await get_tree().create_timer(WAVE_DELAY).timeout
		_start_wave(_current_wave)
	if randf() < 0.15:
		var pickup: Node = _acquire_pickup()
		if pickup:
			if pickup.has_method("activate"):
				pickup.activate(kill_position)
			_sp_pickup_nodes.append(pickup)


func _exit_tree() -> void:
	_game_ended = true
	_cleanup_mp_resources()


func _on_player_died() -> void:
	if _game_ended:
		return
	_game_ended = true
	var stats := _compute_stats()
	if GameData.multiplayer_session_active:
		NetworkClient.stop_processing()
		_cleanup_mp_resources()
		NetworkClient.disconnect_from_server.call_deferred()
	GameEvents.game_completed.emit(false, stats.time, stats.accuracy, stats.fired, stats.hit)
