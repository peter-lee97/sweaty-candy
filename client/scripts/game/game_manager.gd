extends Node2D

@onready var _wave_manager: Node = %WaveManager
@onready var _player_spawn: Marker2D = %PlayerSpawn


func _ready() -> void:
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.all_waves_cleared.connect(_on_all_waves_cleared)
	_spawn_player()


func _spawn_player() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody2D = player_scene.instantiate()
	player.global_position = _player_spawn.global_position
	add_child(player)


func _on_player_died() -> void:
	GameEvents.game_won.emit()


func _on_all_waves_cleared() -> void:
	GameEvents.game_won.emit()
