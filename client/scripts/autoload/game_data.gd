extends Node

var last_score: int = 0
var last_wave: int = 0
var multiplayer_lobby_id: String = ""
var multiplayer_lobby_name: String = ""
var multiplayer_owner_user_id: String = ""
var multiplayer_server_url: String = ""
var multiplayer_session_active: bool = false
var user_id: String = ""
var username: String = ""
var token: String = ""
var user_type: String = "guest"


func clear_multiplayer_session() -> void:
	multiplayer_lobby_id = ""
	multiplayer_lobby_name = ""
	multiplayer_owner_user_id = ""
	multiplayer_server_url = ""
	multiplayer_session_active = false


func clear_auth() -> void:
	user_id = ""
	username = ""
	token = ""
	user_type = "guest"
