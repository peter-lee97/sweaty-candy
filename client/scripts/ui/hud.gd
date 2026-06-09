extends CanvasLayer

@onready var _health_bar: ProgressBar = %HealthBar
@onready var _wave_label: Label = %WaveLabel
@onready var _game_over_label: Label = %GameOverLabel
@onready var _restart_label: Label = %RestartLabel
@onready var _win_label: Label = %WinLabel


func _ready() -> void:
	GameEvents.player_health_changed.connect(_on_player_health_changed)
	GameEvents.player_died.connect(_on_player_died)
	GameEvents.wave_started.connect(_on_wave_started)
	GameEvents.game_won.connect(_on_game_won)
	_game_over_label.hide()
	_restart_label.hide()
	_win_label.hide()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("shoot") and (_game_over_label.visible or _win_label.visible):
		get_tree().reload_current_scene()


func _on_player_health_changed(current: int, max_hp: int) -> void:
	_health_bar.max_value = max_hp
	_health_bar.value = current


func _on_player_died() -> void:
	_game_over_label.show()
	_restart_label.show()


func _on_wave_started(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave


func _on_game_won() -> void:
	var player: Node2D = _find_player()
	if player:
		_wave_label.text = "Wave %d" % (get_node("/root/Game/WaveManager")._current_wave if has_node("/root/Game/WaveManager") else 0)
		_win_label.show()
		_restart_label.show()
	else:
		_game_over_label.show()
		_restart_label.show()


func _find_player() -> Node2D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	return players[0]
