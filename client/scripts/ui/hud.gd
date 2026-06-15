extends CanvasLayer

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _game_over_label: Label = %GameOverLabel
@onready var _restart_label: Label = %RestartLabel
@onready var _win_label: Label = %WinLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _countdown_label: Label = %CountdownLabel
@onready var _wave_label: Label = %WaveLabel


func _ready() -> void:
	GameEvents.player_health_changed.connect(_on_player_health_changed)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.game_completed.connect(_on_game_completed)
	GameEvents.countdown_tick.connect(_on_countdown_tick)
	GameEvents.countdown_finished.connect(_on_countdown_finished)
	GameEvents.wave_started.connect(_on_wave_started)
	_game_over_label.hide()
	_restart_label.hide()
	_win_label.hide()
	_stats_label.hide()
	_countdown_label.hide()
	_wave_label.hide()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("shoot") and (_game_over_label.visible or _win_label.visible):
		if GameData.multiplayer_session_active:
			GameData.clear_multiplayer_session()
			get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
		else:
			get_tree().reload_current_scene()


func _on_player_health_changed(current: int, max_hp: int) -> void:
	_health_bar.max_value = max_hp
	_health_bar.value = current


func _on_player_died() -> void:
	_game_over_label.show()


func _on_game_completed(won: bool, time_sec: float, _accuracy: float, shots_fired: int, shots_hit: int) -> void:
	var minutes: int = int(max(0.0, time_sec)) / 60
	var seconds: int = int(max(0.0, time_sec)) % 60
	var missed: int = shots_fired - shots_hit
	var accuracy: float = float(shots_hit) / max(1.0, float(shots_fired))
	var stats_str: String = "Time: " + str(minutes) + ":" + ("%02d" % seconds) + "   Shots: " + str(shots_hit) + " hit / " + str(missed) + " missed / " + str(shots_fired) + " total   Accuracy: " + str(int(accuracy * 100.0)) + "%"
	_stats_label.text = stats_str
	_stats_label.show()
	if won:
		_win_label.show()
	_restart_label.show()


func _on_countdown_tick(seconds_left: int) -> void:
	if seconds_left > 0:
		_countdown_label.text = str(seconds_left)
		_countdown_label.show()
	else:
		_countdown_label.text = "GO!"
		_countdown_label.show()


func _on_countdown_finished() -> void:
	await get_tree().create_timer(0.8).timeout
	_countdown_label.hide()


func _on_wave_started(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave
	_wave_label.show()
	await get_tree().create_timer(2.0).timeout
	_wave_label.hide()
