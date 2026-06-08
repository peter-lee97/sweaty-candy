extends Node3D

enum State { MENU, PLAYING, PAUSED, GAME_OVER }

@export var player_scene: PackedScene
@export var weapon_scenes: Array[PackedScene] = []
@export var enable_multiplayer_test_mode: bool = false
@export var multiplayer_server_url: String = "ws://127.0.0.1:7777"
@export var snapshot_smoothing: float = 0.35

var current_state: State = State.MENU
var _player: Node3D = null
var _is_network_mode: bool = false
var _pending_weapon_cycle: int = 0
var _network_players: Dictionary = {}
var _network_enemies: Dictionary = {}
var _local_aim_direction: Vector3 = Vector3.FORWARD

@onready var camera: Camera3D = %Camera3D
@onready var entity_manager: Node = %EntityManager
@onready var wave_manager: Node = %WaveManager
@onready var score_manager: Node = %ScoreManager


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.pause_toggle_requested.connect(_on_pause_toggle_requested)
	GameEvents.exit_to_menu_requested.connect(_on_exit_to_menu_requested)
	GameEvents.guest_session_expired.connect(_on_guest_session_expired)
	wave_manager.set_entity_manager(entity_manager)
	_setup_network_mode()
	await _warmup_rendering()
	_start_game()


func _input(event: InputEvent) -> void:
	if current_state != State.PLAYING:
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("weapon_next"):
		if _is_network_mode:
			_pending_weapon_cycle = 1
		elif _player:
			_player.cycle_weapon(1)
	elif event.is_action_pressed("weapon_prev"):
		if _is_network_mode:
			_pending_weapon_cycle = -1
		elif _player:
			_player.cycle_weapon(-1)


func _physics_process(_delta: float) -> void:
	if current_state != State.PLAYING or not _is_network_mode:
		return
	if not NetworkClient.is_server_connected():
		return
	var move_input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	var move_dir := Vector3(move_input.x, 0.0, move_input.y).normalized()
	if move_dir != Vector3.ZERO:
		_local_aim_direction = move_dir
	var shoot: bool = Input.is_action_pressed("shoot")
	NetworkClient.send_player_intent(move_input, _local_aim_direction, shoot, _pending_weapon_cycle)
	_pending_weapon_cycle = 0


func _start_game() -> void:
	current_state = State.PLAYING
	GameEvents.pause_state_changed.emit(false)
	score_manager.reset()
	if _is_network_mode:
		return
	_spawn_player_local()
	camera.set_target(_player)
	wave_manager.start_waves()


func _spawn_player_local() -> void:
	var player_node = player_scene.instantiate()
	player_node.accepts_local_input = true
	player_node.emits_global_events = true
	_player = player_node
	_player.add_to_group("players")
	entity_manager.get_node("Players").add_child(_player)
	_player.global_position = Vector3(0.0, 0.0, 0.0)
	_player.set_weapon_scenes(weapon_scenes)

	if weapon_scenes.size() > 0:
		var weapon: Node3D = weapon_scenes[0].instantiate()
		weapon.set_entity_manager(entity_manager)
		_player.equip_weapon(weapon)


func _setup_network_mode() -> void:
	var should_use_network: bool = enable_multiplayer_test_mode or GameData.multiplayer_session_active
	if not should_use_network:
		return
	_is_network_mode = true
	if not NetworkClient.snapshot_received.is_connected(_on_snapshot_received):
		NetworkClient.snapshot_received.connect(_on_snapshot_received)
	if not NetworkClient.lobby_state_received.is_connected(_on_lobby_state_received):
		NetworkClient.lobby_state_received.connect(_on_lobby_state_received)
	if not NetworkClient.connected_to_server.is_connected(_on_connected_to_server):
		NetworkClient.connected_to_server.connect(_on_connected_to_server)
	if not NetworkClient.connection_failed.is_connected(_on_connection_failed):
		NetworkClient.connection_failed.connect(_on_connection_failed)
	if not NetworkClient.disconnected_from_server.is_connected(_on_disconnected_from_server):
		NetworkClient.disconnected_from_server.connect(_on_disconnected_from_server)
	var target_server_url: String = multiplayer_server_url
	if GameData.multiplayer_session_active and not GameData.multiplayer_server_url.is_empty():
		target_server_url = GameData.multiplayer_server_url
	var connect_error: Error = NetworkClient.connect_to_server(target_server_url)
	if connect_error != OK:
		_is_network_mode = false
		push_error("Failed to connect multiplayer mode to %s (error %d)." % [target_server_url, connect_error])


func _on_connected_to_server() -> void:
	pass


func _on_connection_failed() -> void:
	_is_network_mode = false
	push_error("Connection to multiplayer server failed.")
	_fallback_to_singleplayer()


func _on_disconnected_from_server() -> void:
	current_state = State.MENU
	GameData.clear_multiplayer_session()
	NetworkClient.disconnect_from_server()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_exit_to_menu_requested() -> void:
	if not GameData.multiplayer_lobby_id.is_empty() and BackendApi.is_authenticated():
		await BackendApi.leave_lobby(GameData.multiplayer_lobby_id)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	GameData.clear_multiplayer_session()
	NetworkClient.disconnect_from_server()
	current_state = State.MENU
	GameEvents.pause_state_changed.emit(false)
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_player_died() -> void:
	current_state = State.GAME_OVER
	NetworkClient.disconnect_from_server()
	GameData.clear_multiplayer_session()
	get_tree().paused = true
	await get_tree().create_timer(2.0).timeout
	if not is_instance_valid(self) or not is_inside_tree():
		return
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/game_over.tscn")


func _on_guest_session_expired() -> void:
	current_state = State.MENU
	GameData.clear_multiplayer_session()
	NetworkClient.disconnect_from_server()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_snapshot_received(payload: Dictionary) -> void:
	if not payload.has("players"):
		return
	if not payload.has("enemies"):
		return
	var players: Dictionary = payload.players
	var enemies: Dictionary = payload.enemies
	_sync_players(players)
	_sync_enemies(enemies)


func _on_lobby_state_received(payload: Dictionary) -> void:
	if not payload.has("isReady"):
		return
	var is_ready: bool = payload.isReady
	if is_ready and _is_network_mode:
		NetworkClient.send_player_intent(Vector2.ZERO, Vector3.FORWARD, false, 0)


func _sync_players(players: Dictionary) -> void:
	var player_ids: Array = players.keys()
	var local_id: int = multiplayer.get_unique_id()
	for peer_id in _network_players:
		if not player_ids.has(peer_id):
			if peer_id == local_id:
				camera.set_target(null)
			_network_players[peer_id].queue_free()
			_network_players.erase(peer_id)
	for peer_id in player_ids:
		var player_data: Dictionary = players[peer_id]
		if not _network_players.has(peer_id):
			var new_player = player_scene.instantiate()
			new_player.add_to_group("players")
			entity_manager.get_node("Players").add_child(new_player)
			_network_players[peer_id] = new_player
		var network_player: Node3D = _network_players[peer_id]
		var target_pos: Vector3 = _parse_position(player_data.get("position"))
		network_player.global_position = network_player.global_position.lerp(target_pos, snapshot_smoothing)
		if peer_id == local_id:
			camera.set_target(network_player)


func _sync_enemies(enemies: Dictionary) -> void:
	var enemy_ids: Array = enemies.keys()
	for enemy_id in _network_enemies:
		if not enemy_ids.has(enemy_id):
			_network_enemies[enemy_id].queue_free()
			_network_enemies.erase(enemy_id)
	for enemy_id in enemy_ids:
		var enemy_data: Dictionary = enemies[enemy_id]
		if not _network_enemies.has(enemy_id):
			var enemy_type: String = enemy_data.get("type", "base")
			var scene: PackedScene = _pick_enemy_scene(enemy_type)
			if scene == null:
				continue
			var new_enemy = scene.instantiate()
			entity_manager.get_node("Enemies").add_child(new_enemy)
			_network_enemies[enemy_id] = new_enemy
		var network_enemy: Node3D = _network_enemies[enemy_id]
		var target_pos: Vector3 = _parse_position(enemy_data.get("position"))
		network_enemy.global_position = network_enemy.global_position.lerp(target_pos, snapshot_smoothing)


func _parse_position(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO


func _on_pause_toggle_requested() -> void:
	_toggle_pause_state()


func _toggle_pause_state() -> void:
	if current_state != State.PLAYING and current_state != State.PAUSED:
		return
	if not _can_control_game_state():
		return
	var should_pause: bool = current_state == State.PLAYING
	current_state = State.PAUSED if should_pause else State.PLAYING
	get_tree().paused = should_pause
	GameEvents.pause_state_changed.emit(should_pause)


func _warmup_rendering() -> void:
	var scenes_to_warm: Array[PackedScene] = []
	_collect_warmup_scenes(scenes_to_warm)
	if scenes_to_warm.is_empty():
		return

	var warmup_root := Node3D.new()
	add_child(warmup_root)

	var spacing: float = 1.2
	var col_count: int = 4
	for i in range(scenes_to_warm.size()):
		var scene: PackedScene = scenes_to_warm[i]
		var instance: Node = scene.instantiate()
		instance.process_mode = Node.PROCESS_MODE_DISABLED
		warmup_root.add_child(instance)
		if instance is Node3D:
			var row: int = i / col_count
			var col: int = i % col_count
			var node3d: Node3D = instance
			node3d.position = Vector3((col - 1.5) * spacing, 0.5, -4.0 - row * spacing)
		_trigger_warmup_behaviors(instance)

	await get_tree().process_frame
	await get_tree().process_frame
	warmup_root.queue_free()


func _collect_warmup_scenes(scenes_to_warm: Array[PackedScene]) -> void:
	_append_unique_scene(scenes_to_warm, player_scene)
	for scene: PackedScene in weapon_scenes:
		_append_unique_scene(scenes_to_warm, scene)
	_collect_weapon_projectile_scenes(scenes_to_warm)

	_append_unique_scene(scenes_to_warm, wave_manager.get("enemy_scene"))
	_append_unique_scene(scenes_to_warm, wave_manager.get("enemy_fast_scene"))
	_append_unique_scene(scenes_to_warm, wave_manager.get("enemy_tank_scene"))
	_append_unique_scene(scenes_to_warm, wave_manager.get("health_pickup_scene"))


func _append_unique_scene(scenes_to_warm: Array[PackedScene], candidate: Variant) -> void:
	if candidate == null or not (candidate is PackedScene):
		return
	var packed: PackedScene = candidate
	if scenes_to_warm.has(packed):
		return
	scenes_to_warm.append(packed)


func _collect_weapon_projectile_scenes(scenes_to_warm: Array[PackedScene]) -> void:
	for weapon_scene: PackedScene in weapon_scenes:
		if weapon_scene == null:
			continue
		var weapon_instance: Node = weapon_scene.instantiate()
		var projectile_scene: Variant = weapon_instance.get("projectile_scene")
		_append_unique_scene(scenes_to_warm, projectile_scene)
		weapon_instance.free()


func _trigger_warmup_behaviors(node: Node) -> void:
	var health_component: HealthComponent = _find_first_health_component(node)
	if health_component and health_component.max_health > 1:
		health_component.take_damage(1)


func _find_first_health_component(node: Node) -> HealthComponent:
	if node is HealthComponent:
		return node
	for child in node.get_children():
		var found: HealthComponent = _find_first_health_component(child)
		if found:
			return found
	return null


func _fallback_to_singleplayer() -> void:
	if GameData.multiplayer_session_active:
		return
	if current_state != State.PLAYING:
		return
	if _player != null:
		return
	_spawn_player_local()
	camera.set_target(_player)
	wave_manager.start_waves()


func _pick_enemy_scene(enemy_type: String) -> PackedScene:
	var base_scene: PackedScene = wave_manager.get("enemy_scene")
	var fast_scene: PackedScene = wave_manager.get("enemy_fast_scene")
	var tank_scene: PackedScene = wave_manager.get("enemy_tank_scene")
	if enemy_type == "tank" and tank_scene != null:
		return tank_scene
	if enemy_type == "fast" and fast_scene != null:
		return fast_scene
	return base_scene


func _can_control_game_state() -> bool:
	if not _is_network_mode:
		return true
	var owner_id: String = GameData.multiplayer_owner_user_id
	var user_id: String = BackendApi.current_user.get("id", "")
	return not owner_id.is_empty() and user_id == owner_id
