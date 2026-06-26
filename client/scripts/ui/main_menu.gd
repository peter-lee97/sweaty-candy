extends Control

@onready var _status_label: Label = %StatusLabel


func _on_singleplayer_pressed() -> void:
	GameData.clear_multiplayer_session()
	GameEvents.ui_blocking_input = false
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_multiplayer_pressed() -> void:
	_status_label.text = "Connecting..."
	_status_label.show()
	var res: Dictionary = await BackendApi.authenticate_guest()
	if not res.ok:
		_status_label.text = "Failed to connect: " + str(res.get("error", "unknown"))
		return
	_status_label.text = "Measuring ping..."
	var ping_ms: int = await BackendApi.ping_backend_avg()
	if ping_ms < 0:
		_status_label.text = "Backend unreachable"
		return
	var ping_label: String = "Ping: %dms" % ping_ms
	if ping_ms > 300:
		ping_label += " (poor)"
	elif ping_ms > 150:
		ping_label += " (fair)"
	else:
		ping_label += " (good)"
	_status_label.text = ping_label
	await get_tree().create_timer(0.8).timeout
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
