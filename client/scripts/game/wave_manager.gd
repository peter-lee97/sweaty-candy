extends Node

@export var enemy_scene: PackedScene
@export var wave_configs: Array[int] = [6, 9, 12, 15, 18]
@export var arena_half_size: float = 1400.0
@export var spawn_offset: float = 100.0
@export var wave_cooldown: float = 3.0

var _current_wave: int = 0
var _enemies_alive: int = 0
var _cooldown_timer: float = 0.0
var _spawning: bool = false
var _all_waves_done: bool = false


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
			GameEvents.wave_cleared.emit(_current_wave)
			_start_next_wave()


func _start_next_wave() -> void:
	_current_wave += 1
	var count: int = wave_configs[_current_wave - 1]
	_cooldown_timer = 0.0
	_spawning = true
	GameEvents.wave_started.emit(_current_wave)

	for i: int in range(count):
		_spawn_enemy()
		await get_tree().create_timer(0.5).timeout

	_spawning = false


func _spawn_enemy() -> void:
	var enemy: CharacterBody2D = enemy_scene.instantiate()
	enemy.global_position = _random_edge_position()
	add_child(enemy)
	_enemies_alive += 1


func _on_enemy_killed(_position: Vector2) -> void:
	_enemies_alive = max(0, _enemies_alive - 1)


func _random_edge_position() -> Vector2:
	var side: int = randi() % 4
	var t: float = randf_range(-arena_half_size + spawn_offset, arena_half_size - spawn_offset)
	var offset: float = arena_half_size - spawn_offset
	match side:
		0: return Vector2(-offset, t)
		1: return Vector2(offset, t)
		2: return Vector2(t, -offset)
		_: return Vector2(t, offset)
