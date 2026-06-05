extends Control


func _ready() -> void:
	$MarginContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$MarginContainer/VBoxContainer/MultiplayerButton.pressed.connect(_on_multiplayer_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")


func _on_multiplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
