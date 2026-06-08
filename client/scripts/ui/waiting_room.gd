extends Control

@onready var room_name_label: Label = %RoomNameLabel
@onready var room_id_label: Label = %RoomIdLabel
@onready var players_label: Label = %PlayersLabel
@onready var state_label: Label = %StateLabel
@onready var start_game_button: Button = %StartGameButton
@onready var refresh_button: Button = %RefreshButton
@onready var leave_button: Button = %LeaveButton
@onready var status_label: Label = %StatusLabel

var _current_room: Dictionary = {}


func _ready() -> void:
	if not BackendApi.is_authenticated():
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	if GameData.multiplayer_lobby_id.is_empty():
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	refresh_button.pressed.connect(_on_refresh_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	if not BackendApi.lobby_events_updated.is_connected(_on_lobby_events_updated):
		BackendApi.lobby_events_updated.connect(_on_lobby_events_updated)
	BackendApi.connect_lobby_events()
	await _refresh_room()


func _on_refresh_pressed() -> void:
	await _refresh_room()


func _on_leave_pressed() -> void:
	if not GameData.multiplayer_lobby_id.is_empty():
		await BackendApi.leave_lobby(GameData.multiplayer_lobby_id)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	GameData.clear_multiplayer_session()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _on_start_game_pressed() -> void:
	if not _is_owner():
		status_label.text = "Only owner can start."
		return
	var result: Dictionary = await BackendApi.start_lobby(GameData.multiplayer_lobby_id)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not result.get("ok", false):
		status_label.text = "Start failed: %s" % result.get("error", "Unknown error")
		return
	var body: Dictionary = result.get("body", {})
	var server_info: Dictionary = body.get("assignedServer", {})
	if server_info.has("host") and server_info.has("port"):
		GameData.multiplayer_server_url = "ws://%s:%s" % [server_info.get("host", "127.0.0.1"), str(server_info.get("port", 7777))]
	status_label.text = "Starting room..."


func _refresh_room() -> void:
	var result: Dictionary = await BackendApi.list_lobbies()
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not result.get("ok", false):
		status_label.text = "Refresh failed: %s" % result.get("error", "Unknown error")
		return
	var found: Dictionary = {}
	for room: Dictionary in result.get("body", {}).get("lobbies", []):
		if room.get("id", "") == GameData.multiplayer_lobby_id:
			found = room
			break
	if found.is_empty():
		status_label.text = "Room no longer exists."
		GameData.clear_multiplayer_session()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	_current_room = found
	_apply_room_to_ui(found)
	_maybe_enter_started_game(found)


func _on_lobby_events_updated(payload: Dictionary) -> void:
	if payload.get("type", "") != "lobbies_updated":
		return
	_apply_snapshot(payload.get("lobbies", []))


func _apply_snapshot(lobbies: Array) -> void:
	var found: Dictionary = {}
	for room: Dictionary in lobbies:
		if room.get("id", "") == GameData.multiplayer_lobby_id:
			found = room
			break
	if found.is_empty():
		status_label.text = "Room no longer exists."
		GameData.clear_multiplayer_session()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
		return
	_current_room = found
	_apply_room_to_ui(found)
	_maybe_enter_started_game(found)


func _maybe_enter_started_game(room: Dictionary) -> void:
	if room.get("state", "Waiting") == "Started":
		var host: String = room.get("serverHost", "")
		var port: int = int(room.get("serverPort", 0))
		if not host.is_empty() and port > 0:
			GameData.multiplayer_server_url = "ws://%s:%d" % [host, port]
		if GameData.multiplayer_server_url.is_empty():
			status_label.text = "Room started, waiting for server details..."
			return
		GameData.multiplayer_session_active = true
		get_tree().change_scene_to_file("res://scenes/ui/loading_screen.tscn")


func _apply_room_to_ui(room: Dictionary) -> void:
	GameData.multiplayer_owner_user_id = room.get("ownerUserId", GameData.multiplayer_owner_user_id)
	var current_players: int = int(room.get("currentPlayers", 0))
	var max_players: int = int(room.get("maxPlayers", 0))
	room_name_label.text = "Room: %s" % room.get("name", "")
	room_id_label.text = "ID: %s" % room.get("id", "")
	players_label.text = "Players: %d/%d" % [current_players, max_players]
	state_label.text = "State: %s" % room.get("state", "Waiting")
	start_game_button.visible = _is_owner()
	start_game_button.disabled = room.get("state", "Waiting") != "Waiting"
	var user_type := BackendApi.get_user_type()
	if _is_owner():
		status_label.text = "You are owner (%s). Start when ready." % user_type.capitalize()
	else:
		status_label.text = "Waiting for owner to start... (Current user: %s)" % user_type.capitalize()


func _is_owner() -> bool:
	return GameData.multiplayer_owner_user_id == BackendApi.current_user.get("id", "")


func _exit_tree() -> void:
	if BackendApi.lobby_events_updated.is_connected(_on_lobby_events_updated):
		BackendApi.lobby_events_updated.disconnect(_on_lobby_events_updated)
	BackendApi.disconnect_lobby_events()
