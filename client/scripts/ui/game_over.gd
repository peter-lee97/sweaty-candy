extends Control


func _ready() -> void:
	$MarginContainer/VBoxContainer/FinalScoreLabel.text = "Final Score: %d" % GameData.last_score
	$MarginContainer/VBoxContainer/WaveLabel.text = "Reached Wave %d" % GameData.last_wave
	$MarginContainer/VBoxContainer/RestartButton.pressed.connect(_on_restart_pressed)


func _on_restart_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
