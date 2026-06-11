extends Control

@onready var _status_label: Label = %StatusLabel


func _on_singleplayer_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_multiplayer_pressed() -> void:
	_status_label.text = "Connecting..."
	_status_label.show()
	var res: Dictionary = await BackendApi.authenticate_guest()
	if res.ok:
		get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
	else:
		_status_label.text = "Failed to connect: " + str(res.get("error", "unknown"))
