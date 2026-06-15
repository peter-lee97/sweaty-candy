extends Node

signal player_health_changed(current_health: int, max_health: int)
signal player_died
signal projectile_fired
signal enemy_killed(kill_position: Vector2, score_value: int)
signal countdown_tick(seconds_left: int)
signal countdown_finished
signal wave_started(wave: int)
signal wave_completed(wave: int)
signal game_completed(won: bool, time_sec: float, accuracy: float, shots_fired: int, shots_hit: int)

var ui_blocking_input: bool = false
