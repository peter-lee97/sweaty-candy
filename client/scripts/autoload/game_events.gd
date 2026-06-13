extends Node

signal player_health_changed(current_health: int, max_health: int)
signal player_died
signal projectile_fired
signal projectile_hit
signal game_completed(won: bool, time_sec: float, accuracy: float, shots_fired: int, shots_hit: int)

var ui_blocking_input: bool = false
