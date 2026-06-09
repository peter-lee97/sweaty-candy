extends Node

signal enemy_killed(position: Vector2)
signal player_health_changed(current_health: int, max_health: int)
signal player_died
signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal all_waves_cleared
signal game_won
