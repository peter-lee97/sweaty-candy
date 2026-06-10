extends Node

@export var enemy_scene: PackedScene
@export var enemy_fast_scene: PackedScene
@export var enemy_tank_scene: PackedScene
@export var health_pickup_scene: PackedScene
@export var wave_configs: Array[int] = [6, 9, 12, 15, 18, 21, 24, 27, 30, 35]
@export var arena_half_size: float = 700.0
@export var spawn_offset: float = 100.0
@export var wave_cooldown: float = 3.0
@export var health_drop_chance: float = 0.15

var _current_wave: int = 0
var _enemies_alive: int = 0
var _cooldown_timer: float = 0.0
var _spawning: bool = false
var _all_waves_done: bool = false
var _game_start_time: float = 0.0
var _wave_1_started: bool = false


func _ready() -> void:
	GameEvents.enemy_killed.connect(_on_enemy_killed)
	_start_next_wave()


func _process(delta: float) -> void:
	if _all_waves_done:
		return

	if _spawning:
		return

	if _enemies_alive <= 0:
		_cooldown_timer += delta
		if _cooldown_timer >= wave_cooldown:
			if _current_wave >= wave_configs.size():
				_all_waves_done = true
				GameEvents.all_waves_cleared.emit()
				return
			_start_next_wave()


func _start_next_wave() -> void:
	_current_wave += 1
	if not _wave_1_started:
		_wave_1_started = true
		_game_start_time = Time.get_ticks_msec() / 1000.0
	var count: int = wave_configs[_current_wave - 1]
	_cooldown_timer = 0.0
	_spawning = true
	GameEvents.wave_started.emit(_current_wave)

	var spawn_interval: float = max(0.15, 0.5 - _current_wave * 0.03)
	for i: int in range(count):
		_spawn_enemy()
		await get_tree().create_timer(spawn_interval).timeout

	_spawning = false


func _spawn_enemy() -> void:
	var scene: PackedScene
	if _current_wave <= 2:
		scene = enemy_scene
	elif _current_wave <= 4:
		scene = enemy_fast_scene if randf() < 0.3 else enemy_scene
	else:
		var roll: float = randf()
		if roll < 0.25:
			scene = enemy_tank_scene
		elif roll < 0.55:
			scene = enemy_fast_scene
		else:
			scene = enemy_scene

	var enemy: CharacterBody2D = scene.instantiate()
	enemy.global_position = _random_edge_position()
	add_child(enemy)
	_enemies_alive += 1


func _on_enemy_killed(position: Vector2) -> void:
	_enemies_alive = max(0, _enemies_alive - 1)
	if health_pickup_scene and randf() < health_drop_chance:
		_spawn_health_pickup.call_deferred(position)


func _spawn_health_pickup(spawn_pos: Vector2) -> void:
	var pickup: Area2D = health_pickup_scene.instantiate()
	pickup.global_position = spawn_pos
	add_child(pickup)


func _random_edge_position() -> Vector2:
	var side: int = randi() % 4
	var t: float = randf_range(-arena_half_size + spawn_offset, arena_half_size - spawn_offset)
	var offset: float = arena_half_size - spawn_offset
	match side:
		0: return Vector2(-offset, t)
		1: return Vector2(offset, t)
		2: return Vector2(t, -offset)
		_: return Vector2(t, offset)


func get_elapsed_time() -> float:
	return Time.get_ticks_msec() / 1000.0 - _game_start_time
