extends Node

signal game_started
signal game_over_requested
signal player_died
signal enemy_killed(score_value: int, position: Vector3)
signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal score_updated(score: int, combo: int)
signal player_health_changed(current: int, maximum: int)
signal weapon_changed(weapon_name: String)
signal pause_state_changed(paused: bool)
signal pause_toggle_requested
signal exit_to_menu_requested
signal guest_session_expired
