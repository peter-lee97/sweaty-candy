extends Control

const PASSWORD_MIN_LENGTH: int = 4
const PASSWORD_MAX_LENGTH: int = 11

@onready var create_room_button: Button = %CreateRoomButton
@onready var refresh_button: Button = %RefreshButton
@onready var back_button: Button = %BackButton
@onready var room_table: Tree = %RoomTable
@onready var join_password_input: LineEdit = %JoinPasswordInput
@onready var join_button: Button = %JoinButton
@onready var status_label: Label = %StatusLabel
@onready var create_room_popup: PopupPanel = %CreateRoomPopup
@onready var room_name_input: LineEdit = %RoomNameInput
@onready var room_password_input: LineEdit = %RoomPasswordInput
@onready var max_players_input: SpinBox = %MaxPlayersInput
@onready var popup_cancel_button: Button = %PopupCancelButton
@onready var popup_create_button: Button = %PopupCreateButton

var _rooms: Array[Dictionary] = []
var _sort_column: int = 0
var _sort_ascending: bool = true


func _ready() -> void:
	room_name_input.placeholder_text = "Optional room name"
	room_password_input.placeholder_text = "Optional password (4-11 letters/numbers)"
	join_password_input.placeholder_text = "Password for private room"

	_setup_table()
	create_room_button.pressed.connect(_on_create_room_popup_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	back_button.pressed.connect(_on_back_pressed)
	join_button.pressed.connect(_on_join_pressed)
	popup_cancel_button.pressed.connect(_on_popup_cancel_pressed)
	popup_create_button.pressed.connect(_on_popup_create_pressed)
	room_table.column_title_clicked.connect(_on_column_title_clicked)
	if not BackendApi.lobby_events_updated.is_connected(_on_lobby_events_updated):
		BackendApi.lobby_events_updated.connect(_on_lobby_events_updated)

	if not BackendApi.is_authenticated():
		status_label.text = "Login required."
		get_tree().change_scene_to_file("res://scenes/ui/multiplayer_auth.tscn")
		return

	BackendApi.connect_lobby_events()
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


func _on_create_room_popup_pressed() -> void:
	if not BackendApi.is_authenticated():
		status_label.text = "Login first."
		return
	create_room_popup.popup_centered(create_room_popup.size)
	room_name_input.grab_focus()


func _on_popup_cancel_pressed() -> void:
	create_room_popup.hide()


func _on_popup_create_pressed() -> void:
	var room_name: String = room_name_input.text.strip_edges()
	var room_password: String = room_password_input.text.strip_edges()
	if not room_password.is_empty() and not _is_valid_password(room_password):
		status_label.text = "Password must be 4-11 letters or numbers."
		return
	var result: Dictionary = await BackendApi.create_lobby(room_name, room_password, int(max_players_input.value))
	if not result.get("ok", false):
		status_label.text = "Create failed: %s" % result.get("error", "Unknown error")
		return
	create_room_popup.hide()
	room_name_input.clear()
	room_password_input.clear()
	_enter_waiting_room(result.get("body", {}))


func _on_join_pressed() -> void:
	var lobby_id: String = _get_selected_room_id()
	if lobby_id.is_empty():
		status_label.text = "Select a room first."
		return
	var result: Dictionary = await BackendApi.join_lobby(lobby_id, join_password_input.text)
	if not result.get("ok", false):
		status_label.text = "Join failed: %s" % result.get("error", "Unknown error")
		return
	join_password_input.clear()
	_enter_waiting_room(result.get("body", {}))


func _on_refresh_pressed() -> void:
	await _refresh_rooms()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _refresh_rooms() -> void:
	var result: Dictionary = await BackendApi.list_lobbies()
	if not result.get("ok", false):
		status_label.text = "Lobby refresh failed: %s" % result.get("error", "Unknown error")
		_rooms = []
		_apply_dashboard_view()
		return
	_rooms.clear()
	for lobby: Dictionary in result.get("body", {}).get("lobbies", []):
		_rooms.append(lobby)
	_apply_dashboard_view()


func _on_lobby_events_updated(payload: Dictionary) -> void:
	if payload.get("type", "") != "lobbies_updated":
		return
	_rooms.clear()
	for lobby: Dictionary in payload.get("lobbies", []):
		_rooms.append(lobby)
	_apply_dashboard_view()


func _render_rooms(rooms_to_render: Array[Dictionary]) -> void:
	room_table.clear()
	var root: TreeItem = room_table.create_item()
	for room: Dictionary in rooms_to_render:
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


func _on_column_title_clicked(column: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if _sort_column == column:
		_sort_ascending = not _sort_ascending
	else:
		_sort_column = column
		_sort_ascending = true
	_apply_dashboard_view()


func _apply_dashboard_view() -> void:
	var joinable_rooms: Array[Dictionary] = _filter_joinable_rooms(_rooms)
	if not joinable_rooms.is_empty():
		joinable_rooms.sort_custom(_room_sort_less)
	_render_rooms(joinable_rooms)


func _filter_joinable_rooms(source_rooms: Array[Dictionary]) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for room: Dictionary in source_rooms:
		var state: String = str(room.get("state", "Waiting"))
		var current_players: int = int(room.get("currentPlayers", 0))
		if state != "Waiting":
			continue
		if current_players <= 0:
			continue
		filtered.append(room)
	return filtered


func _room_sort_less(a: Dictionary, b: Dictionary) -> bool:
	var compare_value: int = _compare_rooms(a, b)
	if compare_value == 0:
		return _compare_room_id(a.get("id", ""), b.get("id", "")) < 0
	return compare_value < 0 if _sort_ascending else compare_value > 0


func _compare_rooms(a: Dictionary, b: Dictionary) -> int:
	match _sort_column:
		0:
			return _compare_room_id(a.get("id", ""), b.get("id", ""))
		1:
			return _compare_strings(a.get("name", ""), b.get("name", ""))
		2:
			return _compare_ints(int(a.get("currentPlayers", 0)), int(b.get("currentPlayers", 0)))
		3:
			return _compare_ints(int(a.get("isPrivate", false)), int(b.get("isPrivate", false)))
		4:
			return _compare_strings(a.get("state", ""), b.get("state", ""))
	return _compare_room_id(a.get("id", ""), b.get("id", ""))


func _compare_room_id(left: Variant, right: Variant) -> int:
	var left_text: String = str(left)
	var right_text: String = str(right)
	var left_num: int = _extract_room_numeric_id(left_text)
	var right_num: int = _extract_room_numeric_id(right_text)
	if left_num != right_num:
		return _compare_ints(left_num, right_num)
	return _compare_strings(left_text, right_text)


func _extract_room_numeric_id(room_id: String) -> int:
	if room_id.length() <= 1:
		return 0
	var suffix: String = room_id.substr(1)
	if not suffix.is_valid_int():
		return 0
	return int(suffix)


func _compare_strings(left: Variant, right: Variant) -> int:
	var left_text: String = str(left).to_lower()
	var right_text: String = str(right).to_lower()
	if left_text < right_text:
		return -1
	if left_text > right_text:
		return 1
	return 0


func _compare_ints(left: int, right: int) -> int:
	if left < right:
		return -1
	if left > right:
		return 1
	return 0


func _enter_waiting_room(room: Dictionary) -> void:
	GameData.multiplayer_lobby_id = room.get("id", "")
	GameData.multiplayer_lobby_name = room.get("name", "")
	GameData.multiplayer_owner_user_id = room.get("ownerUserId", "")
	GameData.multiplayer_session_active = false
	GameData.multiplayer_server_url = ""
	get_tree().change_scene_to_file("res://scenes/ui/waiting_room.tscn")


func _exit_tree() -> void:
	if BackendApi.lobby_events_updated.is_connected(_on_lobby_events_updated):
		BackendApi.lobby_events_updated.disconnect(_on_lobby_events_updated)
