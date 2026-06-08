extends Control

@onready var login_button: Button = %LoginButton
@onready var username_label: Label = %UsernameLabel


func _ready() -> void:
	$MarginContainer/VBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$MarginContainer/VBoxContainer/MultiplayerButton.pressed.connect(_on_multiplayer_pressed)
	login_button.pressed.connect(_on_login_pressed)
	_check_existing_session()


func _check_existing_session() -> void:
	if not BackendApi.is_authenticated():
		await _ensure_guest_session()
		if not is_instance_valid(self) or not is_inside_tree():
			return
	elif BackendApi._check_guest_session_expiry():
		await _refresh_or_recreate_guest_session()
		if not is_instance_valid(self) or not is_inside_tree():
			return
	var username: String = String(BackendApi.current_user.get("username", "Guest"))
	username_label.text = "Playing as: %s" % username


func _on_start_pressed() -> void:
	if BackendApi.get_user_type() == "guest" and BackendApi._check_guest_session_expiry():
		await _refresh_or_recreate_guest_session()
		if not is_instance_valid(self) or not is_inside_tree():
			return
	get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")


func _on_multiplayer_pressed() -> void:
	if BackendApi.get_user_type() == "guest" and BackendApi._check_guest_session_expiry():
		await _refresh_or_recreate_guest_session()
		if not is_instance_valid(self) or not is_inside_tree():
			return
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_login_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/multiplayer_auth.tscn")


func _ensure_guest_session() -> void:
	var result: Dictionary = await BackendApi.login_as_guest()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if result.get("ok", false):
		username_label.text = "Playing as: %s" % result.get("body", {}).get("username", "Guest")


func _refresh_or_recreate_guest_session() -> void:
	var result: Dictionary = await BackendApi.refresh_token()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not result.get("ok", false):
		await _ensure_guest_session()
