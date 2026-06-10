extends Node

signal enemy_killed(position: Vector2)
signal player_health_changed(current_health: int, max_health: int)
signal player_died
signal wave_started(wave_number: int)
signal all_waves_cleared
signal game_won
signal projectile_fired
signal projectile_hit
signal game_completed(won: bool, time_sec: float, accuracy: float, shots_fired: int, shots_hit: int)

var ui_blocking_input: bool = false
