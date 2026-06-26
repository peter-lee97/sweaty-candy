extends Node

var multiplayer_lobby_id: String = ""
var multiplayer_lobby_name: String = ""
var multiplayer_owner_user_id: String = ""
var multiplayer_server_url: String = ""
var multiplayer_session_active: bool = false
var user_id: String = ""
var username: String = ""
var token: String = ""
var backend_ping_ms: int = 0
var game_server_ping_ms: int = 0


func clear_multiplayer_session() -> void:
	multiplayer_lobby_id = ""
	multiplayer_lobby_name = ""
	multiplayer_owner_user_id = ""
	multiplayer_server_url = ""
	multiplayer_session_active = false
	GameEvents.ui_blocking_input = false

