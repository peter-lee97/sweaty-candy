extends Node

signal lobby_events_updated(payload: Dictionary)
signal lobby_events_connection_changed(connected: bool)

var base_url: String = "http://127.0.0.1:8787"
var auth_token: String = ""
var current_user: Dictionary = {}
var _lobby_events_peer: WebSocketPeer = null
var _lobby_events_connected: bool = false


func set_base_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	disconnect_lobby_events()


func is_authenticated() -> bool:
	return not auth_token.is_empty()


func register_user(username: String, password: String) -> Dictionary:
	return await _request("POST", "/v1/auth/register", {"username": username, "password": password}, false)


func login_user(username: String, password: String) -> Dictionary:
	var result: Dictionary = await _request("POST", "/v1/auth/login", {"username": username, "password": password}, false)
	if result.get("ok", false):
		auth_token = result.get("body", {}).get("token", "")
		current_user = result.get("body", {}).get("user", {})
		connect_lobby_events()
	return result


func fetch_me() -> Dictionary:
	var result: Dictionary = await _request("GET", "/v1/auth/me", null, true)
	if result.get("ok", false):
		current_user = result.get("body", {})
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


func _ready() -> void:
	set_process(false)


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
	while state == WebSocketPeer.STATE_OPEN and _lobby_events_peer.get_available_packet_count() > 0:
		var packet_text: String = _lobby_events_peer.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(packet_text)
		if parsed is Dictionary:
			lobby_events_updated.emit(parsed)


func _build_lobby_events_url() -> String:
	var ws_base: String = base_url
	if ws_base.begins_with("https://"):
		ws_base = "wss://%s" % ws_base.substr(8)
	elif ws_base.begins_with("http://"):
		ws_base = "ws://%s" % ws_base.substr(7)
	return "%s/v1/lobbies/events?token=%s" % [ws_base, auth_token.uri_encode()]


func _request(method: String, endpoint: String, payload: Variant, requires_auth: bool) -> Dictionary:
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
