extends Node

signal lobby_events_updated(payload: Dictionary)
signal lobby_events_connection_changed(connected: bool)
signal guest_session_expired()

const AUTH_CONFIG_PATH: String = "user://config/auth.cfg"

var base_url: String = "http://127.0.0.1:8787"
var auth_token: String = ""
var current_user: Dictionary = {}
var _lobby_events_peer: WebSocketPeer = null
var _lobby_events_connected: bool = false
var _user_type: String = ""
var _guest_session_expires_at: int = 0
var _last_refresh_time: float = 0.0


func set_base_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	disconnect_lobby_events()
	_load_auth_from_config()


func is_authenticated() -> bool:
	if not auth_token.is_empty():
		return true
	return _load_auth_from_config()


func get_user_type() -> String:
	if _user_type.is_empty():
		_load_auth_from_config()
	return _user_type


func register_user_custom(username: String, password: String) -> Dictionary:
	return await _request("POST", "/v1/auth/register", {"username": username, "password": password}, false)


func login_user(username: String, password: String) -> Dictionary:
	var result: Dictionary = await _request("POST", "/v1/auth/login", {"username": username, "password": password}, false)
	if result.get("ok", false):
		auth_token = result.get("body", {}).get("token", "")
		current_user = result.get("body", {}).get("user", {})
		_user_type = "account"
		_save_auth_to_config()
		connect_lobby_events()
	return result


func login_as_guest() -> Dictionary:
	var result: Dictionary = await _request("POST", "/v1/auth/guest", {}, false)
	if result.get("ok", false):
		auth_token = result.get("body", {}).get("token", "")
		current_user = result.get("body", {})
		_user_type = "guest"
		_guest_session_expires_at = Time.get_unix_time_from_system() + 7200
		_save_auth_to_config()
		connect_lobby_events()
	return result


func refresh_token() -> Dictionary:
	if _user_type != "guest":
		return {"ok": false, "error": "only guest sessions can be refreshed"}
	var result: Dictionary = await _request("POST", "/v1/auth/refresh", {}, true)
	if result.get("ok", false):
		_guest_session_expires_at = result.get("body", {}).get("expiresAt", 0) / 1000
		_save_auth_to_config()
		_last_refresh_time = Time.get_ticks_msec() / 1000.0
	return result


func list_lobbies() -> Dictionary:
	return await _request("GET", "/v1/lobbies", null, false)


func create_lobby(room_name: String, password: String, max_players: int) -> Dictionary:
	return await _request(
		"POST",
		"/v1/lobbies",
		{"roomName": room_name, "password": password, "maxPlayers": max_players},
		true
	)


func join_lobby(lobby_id: String, password: String) -> Dictionary:
	return await _request("POST", "/v1/lobbies/%s/join" % lobby_id, {"password": password}, true)


func start_lobby(lobby_id: String) -> Dictionary:
	return await _request("POST", "/v1/lobbies/%s/start" % lobby_id, {}, true)


func leave_lobby(lobby_id: String) -> Dictionary:
	return await _request("POST", "/v1/lobbies/%s/leave" % lobby_id, {}, true)


func connect_lobby_events() -> void:
	if auth_token.is_empty():
		return
	if _lobby_events_peer != null:
		var state: int = _lobby_events_peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN or state == WebSocketPeer.STATE_CONNECTING:
			return
	var ws_url: String = _build_lobby_events_url()
	var peer := WebSocketPeer.new()
	var err: Error = peer.connect_to_url(ws_url)
	if err != OK:
		push_warning("Lobby events websocket connect failed: %d" % err)
		return
	_lobby_events_peer = peer
	set_process(true)


func disconnect_lobby_events() -> void:
	if _lobby_events_peer != null:
		_lobby_events_peer.close()
	_lobby_events_peer = null
	if _lobby_events_connected:
		_lobby_events_connected = false
		lobby_events_connection_changed.emit(false)
	set_process(false)


func clear_auth() -> void:
	auth_token = ""
	current_user = {}
	_user_type = ""
	_guest_session_expires_at = 0
	_save_auth_to_config()
	disconnect_lobby_events()


func _ready() -> void:
	set_process(false)
	_load_auth_from_config()


func _process(_delta: float) -> void:
	if _lobby_events_peer == null:
		set_process(false)
		return
	_lobby_events_peer.poll()
	var state: int = _lobby_events_peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _lobby_events_connected:
		_lobby_events_connected = true
		lobby_events_connection_changed.emit(true)
	elif state == WebSocketPeer.STATE_CLOSING or state == WebSocketPeer.STATE_CLOSED:
		disconnect_lobby_events()
		return
	while _lobby_events_peer != null and state == WebSocketPeer.STATE_OPEN and _lobby_events_peer.get_available_packet_count() > 0:
		var packet_text: String = _lobby_events_peer.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(packet_text)
		if parsed is Dictionary:
			lobby_events_updated.emit(parsed)
	
	if _user_type == "guest" and _guest_session_expires_at > 0:
		var time_until_expiry: int = _guest_session_expires_at - int(Time.get_unix_time_from_system())
		if time_until_expiry <= 300 and time_until_expiry > 0:
			if _lobby_events_connected and (Time.get_ticks_msec() / 1000.0 - _last_refresh_time) >= 60.0:
				refresh_token()
				_last_refresh_time = Time.get_ticks_msec() / 1000.0


func _build_lobby_events_url() -> String:
	var ws_base: String = base_url
	if ws_base.begins_with("https://"):
		ws_base = "wss://%s" % ws_base.substr(8)
	elif ws_base.begins_with("http://"):
		ws_base = "ws://%s" % ws_base.substr(7)
	return "%s/v1/lobbies/events?token=%s" % [ws_base, auth_token.uri_encode()]


func _check_guest_session_expiry() -> bool:
	if _user_type != "guest" or _guest_session_expires_at <= 0:
		return false
	var current_time: int = int(Time.get_unix_time_from_system())
	if current_time >= _guest_session_expires_at:
		guest_session_expired.emit()
		return true
	return false


func _request(method: String, endpoint: String, payload: Variant, requires_auth: bool) -> Dictionary:
	if requires_auth and _check_guest_session_expiry():
		return {"ok": false, "status": 401, "error": "Guest session expired"}
	var http := HTTPRequest.new()
	add_child(http)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if requires_auth:
		if auth_token.is_empty():
			http.queue_free()
			return {"ok": false, "status": 401, "error": "Not authenticated"}
		headers.append("Authorization: Bearer %s" % auth_token)

	var body: String = ""
	if payload != null:
		body = JSON.stringify(payload)

	var err: Error = http.request("%s%s" % [base_url, endpoint], headers, HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "status": 0, "error": "Request error %d" % err}
	
	if requires_auth and _check_guest_session_expiry():
		http.queue_free()
		return {"ok": false, "status": 401, "error": "Guest session expired"}

	var result: Array = await http.request_completed
	http.queue_free()
	var response_code: int = result[1]
	var response_body: String = PackedByteArray(result[3]).get_string_from_utf8()
	var parsed: Variant = {}
	if not response_body.is_empty():
		parsed = JSON.parse_string(response_body)
		if parsed == null:
			parsed = {}
	var ok: bool = response_code >= 200 and response_code < 300
	var error_message: String = ""
	if not ok:
		error_message = parsed.get("error", "Request failed")
	return {
		"ok": ok,
		"status": response_code,
		"body": parsed,
		"error": error_message
	}


func _load_auth_from_config() -> bool:
	var config := ConfigFile.new()
	var err := config.load(AUTH_CONFIG_PATH)
	if err != OK:
		return false
	if not config.has_section("authentication"):
		return false
	auth_token = config.get_value("authentication", "token", "")
	if auth_token.is_empty():
		return false
	current_user = {
		"id": config.get_value("authentication", "user_id", ""),
		"username": config.get_value("authentication", "username", "")
	}
	_user_type = config.get_value("authentication", "user_type", "")
	var created_at: int = int(config.get_value("authentication", "created_at", 0))
	if _user_type == "guest" and created_at > 0:
		_guest_session_expires_at = created_at + 7200
	return true


func _save_auth_to_config() -> void:
	var config := ConfigFile.new()
	config.set_value("authentication", "user_id", current_user.get("id", ""))
	config.set_value("authentication", "username", current_user.get("username", ""))
	config.set_value("authentication", "user_type", _user_type)
	config.set_value("authentication", "token", auth_token)
	if _user_type == "guest" and _guest_session_expires_at > 0:
		config.set_value("authentication", "created_at", _guest_session_expires_at - 7200)
	else:
		config.set_value("authentication", "created_at", int(Time.get_unix_time_from_system()))
	config.set_value("authentication", "backend_url", base_url)
	config.save(AUTH_CONFIG_PATH)


func _exit_tree() -> void:
	_save_auth_to_config()
