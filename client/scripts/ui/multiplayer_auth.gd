extends Control

@onready var backend_url_input: LineEdit = %BackendUrlInput
@onready var username_input: LineEdit = %UsernameInput
@onready var password_input: LineEdit = %PasswordInput
@onready var register_button: Button = %RegisterButton
@onready var login_button: Button = %LoginButton
@onready var continue_button: Button = %ContinueButton
@onready var back_button: Button = %BackButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	backend_url_input.text = BackendApi.base_url
	backend_url_input.placeholder_text = "Backend URL"
	username_input.placeholder_text = "Username"
	password_input.placeholder_text = "Password"
	register_button.pressed.connect(_on_register_pressed)
	login_button.pressed.connect(_on_login_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_update_continue_state()


func _on_register_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = password_input.text
	if username.is_empty() or password.is_empty():
		status_label.text = "Enter username and password."
		return
	BackendApi.set_base_url(backend_url_input.text)
	var result: Dictionary = await BackendApi.register_user_custom(username, password)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not result.get("ok", false):
		status_label.text = "Register failed: %s" % result.get("error", "Unknown error")
		return
	status_label.text = "Registered %s." % username
	_update_continue_state()


func _on_login_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = password_input.text
	if username.is_empty() or password.is_empty():
		status_label.text = "Enter username and password."
		return
	BackendApi.set_base_url(backend_url_input.text)
	var result: Dictionary = await BackendApi.login_user(username, password)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not result.get("ok", false):
		status_label.text = "Login failed: %s" % result.get("error", "Unknown error")
		_update_continue_state()
		return
	status_label.text = "Logged in as %s." % result.get("body", {}).get("user", {}).get("username", username)
	_update_continue_state()


func _on_continue_pressed() -> void:
	if not BackendApi.is_authenticated():
		status_label.text = "Login first."
		return
	GameData.user_type = BackendApi.get_user_type()
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _update_continue_state() -> void:
	continue_button.disabled = not BackendApi.is_authenticated()