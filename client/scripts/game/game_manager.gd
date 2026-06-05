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
var _local_peer_id: int = -1
var _pending_weapon_cycle: int = 0
var _network_players: Dictionary = {}
var _local_aim_direction: Vector3 = Vector3.FORWARD

@onready var camera: Camera3D = %Camera3D
@onready var entity_manager: Node = %EntityManager
@onready var wave_manager: Node = %WaveManager
@onready var score_manager: Node = %ScoreManager


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	wave_manager.set_entity_manager(entity_manager)
	_setup_network_mode()
	await _warmup_rendering()
	_start_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and current_state == State.PLAYING:
		current_state = State.PAUSED
		get_tree().paused = true
	elif event.is_action_pressed("pause") and current_state == State.PAUSED:
		current_state = State.PLAYING
		get_tree().paused = false
	elif current_state == State.PLAYING:
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
	_local_peer_id = multiplayer.get_unique_id()


func _on_connection_failed() -> void:
	_is_network_mode = false
	push_error("Connection to multiplayer server failed.")
	_fallback_to_singleplayer()


func _on_disconnected_from_server() -> void:
	_is_network_mode = false
	_fallback_to_singleplayer()


func _on_lobby_state_received(payload: Dictionary) -> void:
	_sync_network_players(payload.get("players", {}))


func _on_snapshot_received(payload: Dictionary) -> void:
	_sync_network_players(payload.get("players", {}))


func _sync_network_players(server_players: Dictionary) -> void:
	if not _is_network_mode:
		return
	var active_peer_ids: Dictionary = {}
	for key: Variant in server_players.keys():
		var peer_id: int = int(key)
		active_peer_ids[peer_id] = true
		var state: Dictionary = server_players[key]
		if not _network_players.has(peer_id):
			_network_players[peer_id] = _spawn_network_player(peer_id)
		var player_node: Node3D = _network_players[peer_id]
		_apply_server_player_state(player_node, state)
	for key: Variant in _network_players.keys():
		var peer_id: int = int(key)
		if active_peer_ids.has(peer_id):
			continue
		var stale_player: Node3D = _network_players[peer_id]
		if stale_player and is_instance_valid(stale_player):
			stale_player.queue_free()
		_network_players.erase(peer_id)
	if _local_peer_id < 0 and NetworkClient.is_server_connected():
		_local_peer_id = multiplayer.get_unique_id()
	if _local_peer_id > 0 and _network_players.has(_local_peer_id):
		var local_player = _network_players[_local_peer_id]
		local_player.emits_global_events = true
		if camera:
			camera.set_target(local_player as Node3D)
		_player = local_player as Node3D


func _spawn_network_player(peer_id: int) -> Node3D:
	var player_node = player_scene.instantiate()
	player_node.accepts_local_input = false
	player_node.emits_global_events = peer_id == _local_peer_id
	player_node.add_to_group("players")
	entity_manager.get_node("Players").add_child(player_node)
	return player_node as Node3D


func _apply_server_player_state(player_node: Node3D, state: Dictionary) -> void:
	var target_position: Vector3 = _to_vector3(state.get("position", player_node.global_position), player_node.global_position)
	player_node.global_position = player_node.global_position.lerp(target_position, snapshot_smoothing)


func _on_player_died() -> void:
	current_state = State.GAME_OVER
	GameData.last_score = score_manager.score
	GameData.last_wave = wave_manager._current_wave
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/ui/game_over.tscn")
	)


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


func _to_vector3(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Array and raw.size() >= 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return fallback


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
