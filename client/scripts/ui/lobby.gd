extends Control

const PASSWORD_MIN_LENGTH: int = 4
const PASSWORD_MAX_LENGTH: int = 11

@onready var backend_url_input: LineEdit = %BackendUrlInput
@onready var username_input: LineEdit = %UsernameInput
@onready var auth_password_input: LineEdit = %AuthPasswordInput
@onready var login_button: Button = %LoginButton
@onready var register_button: Button = %RegisterButton
@onready var room_name_input: LineEdit = %RoomNameInput
@onready var room_password_input: LineEdit = %RoomPasswordInput
@onready var max_players_input: SpinBox = %MaxPlayersInput
@onready var create_button: Button = %CreateButton
@onready var room_table: Tree = %RoomTable
@onready var join_password_input: LineEdit = %JoinPasswordInput
@onready var join_button: Button = %JoinButton
@onready var start_button: Button = %StartButton
@onready var refresh_button: Button = %RefreshButton
@onready var back_button: Button = %BackButton
@onready var status_label: Label = %StatusLabel

var _rooms: Array[Dictionary] = []


func _ready() -> void:
	backend_url_input.placeholder_text = "Backend URL"
	backend_url_input.text = BackendApi.base_url
	username_input.placeholder_text = "Username"
	auth_password_input.placeholder_text = "Password"
	room_name_input.placeholder_text = "Optional room name"
	room_password_input.placeholder_text = "Optional password (4-11 letters/numbers)"
	join_password_input.placeholder_text = "Password for private room"

	_setup_table()

	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	create_button.pressed.connect(_on_create_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)

	await _refresh_rooms()


func _setup_table() -> void:
	room_table.columns = 5
	room_table.hide_root = true
	room_table.select_mode = Tree.SELECT_ROW
	room_table.set_column_title(0, "Room ID")
	room_table.set_column_title(1, "Room Name")
	room_table.set_column_title(2, "Players")
	room_table.set_column_title(3, "")
	room_table.set_column_title(4, "State")
	for i in range(5):
		room_table.set_column_titles_visible(true)
		room_table.set_column_expand(i, true)
	room_table.set_column_expand(3, false)
	room_table.set_column_custom_minimum_width(3, 48)


func _on_login_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = auth_password_input.text
	if username.is_empty() or password.is_empty():
		status_label.text = "Enter username and password."
		return
	BackendApi.set_base_url(backend_url_input.text)
	var result: Dictionary = await BackendApi.login_user(username, password)
	if not result.get("ok", false):
		status_label.text = "Login failed: %s" % result.get("error", "Unknown error")
		return
	status_label.text = "Logged in as %s." % result.get("body", {}).get("user", {}).get("username", username)
	await _refresh_rooms()


func _on_register_pressed() -> void:
	var username: String = username_input.text.strip_edges()
	var password: String = auth_password_input.text
	if username.is_empty() or password.is_empty():
		status_label.text = "Enter username and password."
		return
	BackendApi.set_base_url(backend_url_input.text)
	var result: Dictionary = await BackendApi.register_user(username, password)
	if not result.get("ok", false):
		status_label.text = "Register failed: %s" % result.get("error", "Unknown error")
		return
	status_label.text = "Registered %s. You can now login." % username


func _on_create_pressed() -> void:
	if not BackendApi.is_authenticated():
		status_label.text = "Login first."
		return
	var room_name: String = room_name_input.text.strip_edges()
	var room_password: String = room_password_input.text.strip_edges()
	if not room_password.is_empty() and not _is_valid_password(room_password):
		status_label.text = "Password must be 4-11 letters or numbers."
		return
	var result: Dictionary = await BackendApi.create_lobby(room_name, room_password, int(max_players_input.value))
	if not result.get("ok", false):
		status_label.text = "Create failed: %s" % result.get("error", "Unknown error")
		return
	room_name_input.clear()
	room_password_input.clear()
	status_label.text = "Created %s." % result.get("body", {}).get("name", "room")
	await _refresh_rooms()


func _on_join_pressed() -> void:
	if not BackendApi.is_authenticated():
		status_label.text = "Login first."
		return
	var lobby_id: String = _get_selected_room_id()
	if lobby_id.is_empty():
		status_label.text = "Select a room first."
		return
	var result: Dictionary = await BackendApi.join_lobby(lobby_id, join_password_input.text)
	if not result.get("ok", false):
		status_label.text = "Join failed: %s" % result.get("error", "Unknown error")
		return
	join_password_input.clear()
	status_label.text = "Joined %s." % result.get("body", {}).get("name", lobby_id)
	await _refresh_rooms()


func _on_start_pressed() -> void:
	if not BackendApi.is_authenticated():
		status_label.text = "Login first."
		return
	var lobby_id: String = _get_selected_room_id()
	if lobby_id.is_empty():
		status_label.text = "Select a room first."
		return
	var result: Dictionary = await BackendApi.start_lobby(lobby_id)
	if not result.get("ok", false):
		status_label.text = "Start failed: %s" % result.get("error", "Unknown error")
		return
	var server_info: Dictionary = result.get("body", {}).get("assignedServer", {})
	status_label.text = "Started on %s:%s." % [server_info.get("host", "?"), str(server_info.get("port", "?"))]
	await _refresh_rooms()


func _on_refresh_pressed() -> void:
	await _refresh_rooms()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _refresh_rooms() -> void:
	BackendApi.set_base_url(backend_url_input.text)
	var result: Dictionary = await BackendApi.list_lobbies()
	if not result.get("ok", false):
		status_label.text = "Lobby refresh failed: %s" % result.get("error", "Unknown error")
		_rooms = []
		_render_rooms()
		return
	_rooms.clear()
	for lobby: Dictionary in result.get("body", {}).get("lobbies", []):
		_rooms.append(lobby)
	_render_rooms()


func _render_rooms() -> void:
	room_table.clear()
	var root: TreeItem = room_table.create_item()
	for room: Dictionary in _rooms:
		var row: TreeItem = room_table.create_item(root)
		row.set_text(0, room.get("id", ""))
		row.set_text(1, room.get("name", ""))
		row.set_text(2, "%d/%d" % [int(room.get("currentPlayers", 0)), int(room.get("maxPlayers", 0))])
		row.set_text(3, "🔒" if room.get("isPrivate", false) else "")
		row.set_text(4, room.get("state", "Waiting"))


func _get_selected_room_id() -> String:
	var selected_item: TreeItem = room_table.get_selected()
	if selected_item == null:
		return ""
	return selected_item.get_text(0)


func _is_valid_password(password: String) -> bool:
	if password.length() < PASSWORD_MIN_LENGTH or password.length() > PASSWORD_MAX_LENGTH:
		return false
	for ch in password:
		var code: int = ch.unicode_at(0)
		var is_digit: bool = code >= 48 and code <= 57
		var is_upper: bool = code >= 65 and code <= 90
		var is_lower: bool = code >= 97 and code <= 122
		if not (is_digit or is_upper or is_lower):
			return false
	return true
