extends Control

func _ready() -> void:
	$MarginContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$MarginContainer/VBoxContainer/MultiplayerButton.pressed.connect(_on_multiplayer_pressed)
	$MarginContainer/VBoxContainer/GuestButton.pressed.connect(_on_guest_pressed)
	_check_existing_session()


func _check_existing_session() -> void:
	if BackendApi.is_authenticated() and not BackendApi._check_guest_session_expiry():
		var user_type := BackendApi.get_user_type()
		var username := BackendApi.current_user.get("username", "User")
		$MarginContainer/VBoxContainer/TitleLabel.text = "Welcome back, %s! (%s)" % [username, user_type.capitalize()]


func _on_start_pressed() -> void:
	if BackendApi.get_user_type() == "guest" and BackendApi._check_guest_session_expiry():
		get_tree().change_scene_to_file("res://scenes/ui/multiplayer_auth.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")


func _on_multiplayer_pressed() -> void:
	if BackendApi.get_user_type() == "guest" and BackendApi._check_guest_session_expiry():
		get_tree().change_scene_to_file("res://scenes/ui/multiplayer_auth.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_guest_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_auth.tscn")
