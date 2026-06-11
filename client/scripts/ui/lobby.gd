extends Control

@onready var _room_table: Tree = %RoomTable
@onready var _status_label: Label = %StatusLabel
@onready var _create_popup: PopupPanel = %CreatePopup
@onready var _room_name_input: LineEdit = %RoomNameInput
@onready var _room_password_input: LineEdit = %RoomPasswordInput
@onready var _max_players_spin: SpinBox = %MaxPlayersSpin
@onready var _join_password_input: LineEdit = %JoinPasswordInput

const BIRDS: PackedStringArray = ["Eagle", "Falcon", "Sparrow", "Raven", "Owl", "Pigeon", "Hawk", "Swan", "Dove", "Crow"]
const DESSERTS: PackedStringArray = ["Brownie", "Muffin", "Pudding", "Cookie", "Waffle", "Custard", "Sorbet", "Gelato", "Tiramisu", "Mochi"]


func _ready() -> void:
	BackendApi.lobby_events_updated.connect(_on_lobby_events)
	_room_table.set_column_title(0, "Room")
	_room_table.set_column_title(1, "Players")
	_room_table.set_column_title(2, "Status")
	_room_table.set_column_title(3, "Lock")
	_room_table.set_column_expand(0, true)
	_room_table.set_column_expand(1, false)
	_room_table.set_column_expand(2, false)
	_room_table.set_column_expand(3, false)
	_room_table.set_column_custom_minimum_width(1, 70)
	_room_table.set_column_custom_minimum_width(2, 70)
	_room_table.set_column_custom_minimum_width(3, 50)
	BackendApi.connect_lobby_events()
	_refresh_rooms()
	_generate_default_name()


func _generate_default_name() -> void:
	var bird: String = BIRDS[randi() % BIRDS.size()]
	var dessert: String = DESSERTS[randi() % DESSERTS.size()]
	_room_name_input.text = bird + " " + dessert


func _refresh_rooms() -> void:
	_status_label.text = "Loading rooms..."
	var res: Dictionary = await BackendApi.list_lobbies()
	if not res.ok:
		_status_label.text = "Failed to load rooms"
		return
	_update_table(res.body.get("lobbies", []))


func _update_table(lobbies: Array) -> void:
	_room_table.clear()
	var root: TreeItem = _room_table.create_item()
	for lobby in lobbies:
		var l: Dictionary = lobby
		if l.get("state", "") != "Waiting":
			continue
		var item: TreeItem = _room_table.create_item(root)
		item.set_text(0, str(l.get("name", "")))
		item.set_text(1, str(l.get("currentPlayers", 0)) + "/" + str(l.get("maxPlayers", 0)))
		item.set_text(2, str(l.get("state", "")))
		item.set_text(3, "P" if l.get("isPrivate", false) else "")
		item.set_metadata(0, str(l.get("id", "")))
	_status_label.text = str(_room_table.get_root().get_child_count()) + " rooms found"


func _on_lobby_events(lobbies: Array) -> void:
	_update_table(lobbies)


func _on_join_pressed() -> void:
	var selected: TreeItem = _room_table.get_next_selected(null)
	if not selected:
		_status_label.text = "Select a room first"
		return
	var lobby_id: String = selected.get_metadata(0)
	if lobby_id == "":
		return
	var password: String = _join_password_input.text
	var res: Dictionary = await BackendApi.join_lobby(lobby_id, password)
	if not res.ok:
		_status_label.text = str(res.get("body", {}).get("error", "Join failed"))
		return
	_enter_waiting_room(lobby_id)


func _on_create_pressed() -> void:
	_create_popup.popup_centered()


func _on_create_confirm_pressed() -> void:
	var name: String = _room_name_input.text.strip_edges()
	if name == "":
		_generate_default_name()
		name = _room_name_input.text
	var password: String = _room_password_input.text.strip_edges()
	var max_players: int = int(_max_players_spin.value)
	var res: Dictionary = await BackendApi.create_lobby(name, password, max_players)
	if not res.ok:
		_status_label.text = str(res.get("body", {}).get("error", "Create failed"))
		return
	_create_popup.hide()
	var lobby: Dictionary = res.body
	_enter_waiting_room(str(lobby.id))


func _on_create_cancel_pressed() -> void:
	_create_popup.hide()


func _on_back_pressed() -> void:
	BackendApi.disconnect_lobby_events()
	GameData.clear_multiplayer_session()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _enter_waiting_room(lobby_id: String) -> void:
	GameData.multiplayer_lobby_id = lobby_id
	GameData.multiplayer_session_active = true
	get_tree().change_scene_to_file("res://scenes/ui/waiting_room.tscn")
