extends Control

@onready var _room_name_label: Label = %RoomNameLabel
@onready var _room_id_label: Label = %RoomIdLabel
@onready var _players_label: Label = %PlayersLabel
@onready var _state_label: Label = %StateLabel
@onready var _status_label: Label = %StatusLabel
@onready var _start_button: Button = %StartButton

var _is_entering: bool = false
var _ping_timeout: float = 0.0
var _ping_done: bool = false


func _ready() -> void:
	BackendApi.lobby_events_updated.connect(_on_lobby_events)
	_refresh()


func _process(delta: float) -> void:
	if _ping_timeout > 0.0:
		_ping_timeout -= delta
		if _ping_timeout <= 0.0:
			_ping_timeout = 0.0
			_finish_ping_measurement(-1)


func _refresh() -> void:
	var res: Dictionary = await BackendApi.list_lobbies()
	if not res.ok:
		return
	var lobbies: Array = res.body.get("lobbies", [])
	var lobby_id: String = GameData.multiplayer_lobby_id
	for l in lobbies:
		var lobby: Dictionary = l
		if str(lobby.get("id", "")) == lobby_id:
			_update_display(lobby)
			return
	_on_room_gone()


func _update_display(lobby: Dictionary) -> void:
	_room_name_label.text = str(lobby.get("name", ""))
	_room_id_label.text = "ID: " + str(lobby.get("id", ""))
	_players_label.text = "Players: " + str(lobby.get("currentPlayers", 0)) + " / " + str(lobby.get("maxPlayers", 0))
	_state_label.text = "State: " + str(lobby.get("state", ""))
	GameData.multiplayer_owner_user_id = str(lobby.get("ownerUserId", ""))
	var is_owner: bool = GameData.multiplayer_owner_user_id == GameData.user_id
	_start_button.visible = is_owner
	if lobby.get("state", "") == "Started":
		_enter_game(lobby)


func _enter_game(lobby: Dictionary) -> void:
	if _is_entering:
		return
	var host: String = str(lobby.get("serverHost", ""))
	var port: int = int(lobby.get("serverPort", 0))
	if host == "" or port == 0:
		_status_label.text = "No game server available"
		return
	_is_entering = true
	var protocol: String = "ws://"
	if port == 443:
		protocol = "wss://"
	GameData.multiplayer_server_url = protocol + host + ":" + str(port)
	BackendApi.disconnect_lobby_events()
	_measure_game_server_ping()


func _measure_game_server_ping() -> void:
	_status_label.text = "Connecting to game server..."
	_ping_done = false
	NetworkClient.rtt_updated.connect(_on_first_rtt)
	NetworkClient.connection_failed.connect(_on_ping_connect_failed)
	NetworkClient.connect_to_server(GameData.multiplayer_server_url)
	_ping_timeout = 3.0


func _on_ping_connect_failed(_reason: String) -> void:
	_finish_ping_measurement(-1)


func _on_first_rtt(rtt_ms: int) -> void:
	_finish_ping_measurement(rtt_ms)


func _finish_ping_measurement(rtt_ms: int) -> void:
	if _ping_done:
		return
	_ping_done = true
	_ping_timeout = 0.0
	if NetworkClient.rtt_updated.is_connected(_on_first_rtt):
		NetworkClient.rtt_updated.disconnect(_on_first_rtt)
	if NetworkClient.connection_failed.is_connected(_on_ping_connect_failed):
		NetworkClient.connection_failed.disconnect(_on_ping_connect_failed)
	if rtt_ms >= 0:
		var label: String = "Server ping: %dms" % rtt_ms
		if rtt_ms > 300:
			label += " (poor)"
		elif rtt_ms > 150:
			label += " (fair)"
		else:
			label += " (good)"
		_status_label.text = label
		NetworkClient.disconnect_from_server()
		await get_tree().create_timer(1.0).timeout
	else:
		_status_label.text = "Game server unreachable, starting anyway..."
		NetworkClient.disconnect_from_server()
	_proceed_to_game()


func _proceed_to_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game/game.tscn")


func _on_lobby_events(lobbies: Array) -> void:
	var lobby_id: String = GameData.multiplayer_lobby_id
	for l in lobbies:
		var lobby: Dictionary = l
		if str(lobby.get("id", "")) == lobby_id:
			_update_display(lobby)
			return


func _on_start_pressed() -> void:
	_status_label.text = "Starting game..."
	var res: Dictionary = await BackendApi.start_lobby(GameData.multiplayer_lobby_id)
	if not res.ok:
		_status_label.text = str(res.get("body", {}).get("error", "Start failed"))
		return
	_enter_game(res.body.get("lobby", {}))


func _on_leave_pressed() -> void:
	await BackendApi.leave_lobby(GameData.multiplayer_lobby_id)
	BackendApi.disconnect_lobby_events()
	GameData.clear_multiplayer_session()
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")


func _on_room_gone() -> void:
	_status_label.text = "Room no longer exists"
	BackendApi.disconnect_lobby_events()
	GameData.clear_multiplayer_session()
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")
