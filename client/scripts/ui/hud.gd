extends CanvasLayer

@onready var health_bar: ProgressBar = %HealthBar
@onready var score_label: Label = %ScoreLabel
@onready var wave_label: Label = %WaveLabel
@onready var combo_label: Label = %ComboLabel
@onready var weapon_label: Label = %WeaponLabel


func _ready() -> void:
	GameEvents.player_health_changed.connect(_on_health_changed)
	GameEvents.score_updated.connect(_on_score_updated)
	GameEvents.wave_started.connect(_on_wave_started)
	GameEvents.weapon_changed.connect(_on_weapon_changed)


func _on_health_changed(current: int, maximum: int) -> void:
	health_bar.max_value = maximum
	health_bar.value = current


func _on_score_updated(new_score: int, new_combo: int) -> void:
	score_label.text = "Score: %d" % new_score
	if new_combo > 1:
		combo_label.text = "x%d COMBO" % new_combo
		combo_label.visible = true
	else:
		combo_label.visible = false


func _on_wave_started(wave_number: int) -> void:
	wave_label.text = "Wave %d" % wave_number


func _on_weapon_changed(weapon_name: String) -> void:
	weapon_label.text = weapon_name
