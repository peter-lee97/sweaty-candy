extends Node2D

@onready var _wave_manager: Node = %WaveManager
@onready var _player_spawn: Marker2D = %PlayerSpawn

var _shots_fired: int = 0
var _shots_hit: int = 0


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.all_waves_cleared.connect(_on_all_waves_cleared)
	GameEvents.projectile_fired.connect(_on_projectile_fired)
	GameEvents.projectile_hit.connect(_on_projectile_hit)
	_spawn_player()


func _spawn_player() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()
	player.global_position = _player_spawn.global_position
	add_child(player)


func _on_projectile_fired() -> void:
	_shots_fired += 1


func _on_projectile_hit() -> void:
	_shots_hit += 1


func _compute_stats() -> Dictionary:
	var elapsed: float = _wave_manager.get_elapsed_time()
	var accuracy: float = float(_shots_hit) / max(1.0, float(_shots_fired))
	return {"time": elapsed, "accuracy": accuracy, "fired": _shots_fired, "hit": _shots_hit}


func _on_player_died() -> void:
	var stats := _compute_stats()
	GameEvents.game_completed.emit(false, stats.time, stats.accuracy, stats.fired, stats.hit)


func _on_all_waves_cleared() -> void:
	var stats := _compute_stats()
	GameEvents.game_completed.emit(true, stats.time, stats.accuracy, stats.fired, stats.hit)
	GameEvents.game_won.emit()
