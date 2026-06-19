extends Node

signal player_health_changed(current_health: int, max_health: int)
signal player_died
signal projectile_fired
signal projectile_hit
signal enemy_killed(kill_position: Vector2, score_value: int)
signal countdown_tick(seconds_left: int)
signal countdown_finished
signal wave_started(wave: int)
signal wave_completed(wave: int)
signal respawn_tick(time_left: float)
signal respawn_complete
signal game_completed(won: bool, time_sec: float, accuracy: float, shots_fired: int, shots_hit: int)
signal spawn_projectile_requested(position: Vector2, direction: Vector2)
signal projectile_expired(projectile: Node2D)
signal enemy_released(enemy: Node2D)
signal pickup_collected(pickup: Node2D)
signal pickup_expired(pickup: Node2D)

var ui_blocking_input: bool = false
