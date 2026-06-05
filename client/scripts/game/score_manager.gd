extends Node

var score: int = 0
var combo: int = 1
var _combo_timer: float = 0.0
var _combo_timeout: float = 2.0
var _max_combo: int = 4


func _ready() -> void:
	GameEvents.enemy_killed.connect(_on_enemy_killed)


func reset() -> void:
	score = 0
	combo = 1
	_combo_timer = 0.0
	GameEvents.score_updated.emit(score, combo)


func _physics_process(delta: float) -> void:
	if combo > 1:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo = 1
			GameEvents.score_updated.emit(score, combo)


func _on_enemy_killed(score_value: int, _position: Vector3) -> void:
	score += score_value * combo
	combo = mini(combo + 1, _max_combo)
	_combo_timer = _combo_timeout
	GameEvents.score_updated.emit(score, combo)
