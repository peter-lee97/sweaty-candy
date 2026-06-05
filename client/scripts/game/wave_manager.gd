extends Node

signal wave_finished

@export var enemy_scene: PackedScene
@export var enemy_fast_scene: PackedScene
@export var enemy_tank_scene: PackedScene
@export var health_pickup_scene: PackedScene
@export var arena_size: float = 14.0
@export var health_drop_chance: float = 0.15

var _current_wave: int = 0
var _active: bool = false
var _enemies_to_spawn: int = 0
var _spawn_timer: float = 0.0
var _spawn_delay: float = 1.0
var _wave_cooldown: float = 3.0
var _cooldown_timer: float = 0.0
var _spawning: bool = false
var _entity_manager: Node = null

var _wave_configs: Array[Dictionary] = [
	{"enemy_count": 5, "spawn_delay": 1.0, "cooldown": 3.0},
	{"enemy_count": 8, "spawn_delay": 0.8, "cooldown": 3.0},
	{"enemy_count": 12, "spawn_delay": 0.7, "cooldown": 3.0},
	{"enemy_count": 16, "spawn_delay": 0.6, "cooldown": 2.5},
	{"enemy_count": 20, "spawn_delay": 0.5, "cooldown": 2.5},
]


func _ready() -> void:
	GameEvents.enemy_killed.connect(_on_enemy_killed)


func start_waves() -> void:
	_active = true
	_current_wave = 0
	_start_next_wave()


func set_entity_manager(manager: Node) -> void:
	_entity_manager = manager


func _physics_process(delta: float) -> void:
	if not _active:
		return

	if _spawning:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0 and _enemies_to_spawn > 0:
			_spawn_enemy()
			_enemies_to_spawn -= 1
			_spawn_timer = _spawn_delay
		if _enemies_to_spawn <= 0:
			_spawning = false
		return

	if _entity_manager and _entity_manager.get_enemy_count() == 0:
		_cooldown_timer += delta
		if _cooldown_timer >= _wave_cooldown:
			_start_next_wave()


func _start_next_wave() -> void:
	_current_wave += 1
	var config_index: int = mini(_current_wave - 1, _wave_configs.size() - 1)
	var config: Dictionary = _wave_configs[config_index]

	_enemies_to_spawn = config.get("enemy_count", 5)
	_spawn_delay = config.get("spawn_delay", 1.0)
	_wave_cooldown = config.get("cooldown", 3.0)

	var scaling: int = maxi(0, _current_wave - _wave_configs.size())
	_enemies_to_spawn += scaling * 3

	_spawning = true
	_spawn_timer = 0.0
	_cooldown_timer = 0.0

	GameEvents.wave_started.emit(_current_wave)


func _spawn_enemy() -> void:
	if enemy_scene == null or _entity_manager == null:
		return
	var scene: PackedScene = _pick_enemy_scene()
	var enemy: Node3D = scene.instantiate()
	var spawn_pos: Vector3 = _get_random_edge_position()
	_entity_manager.spawn_enemy(enemy, spawn_pos)


func _pick_enemy_scene() -> PackedScene:
	if _current_wave >= 5 and enemy_tank_scene and randf() < 0.2:
		return enemy_tank_scene
	if _current_wave >= 3 and enemy_fast_scene and randf() < 0.35:
		return enemy_fast_scene
	return enemy_scene


func _on_enemy_killed(_score_value: int, position: Vector3) -> void:
	if health_pickup_scene and _entity_manager and randf() < health_drop_chance:
		var pickup: Node3D = health_pickup_scene.instantiate()
		_entity_manager.spawn_pickup(pickup, position)


func _get_random_edge_position() -> Vector3:
	var side: int = randi() % 4
	var t: float = randf_range(-arena_size, arena_size)
	var offset: float = arena_size - 1.0
	match side:
		0: return Vector3(-offset, 0.0, t)
		1: return Vector3(offset, 0.0, t)
		2: return Vector3(t, 0.0, -offset)
		_: return Vector3(t, 0.0, offset)
