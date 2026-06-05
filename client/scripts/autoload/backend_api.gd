extends Node

var base_url: String = "http://127.0.0.1:8787"
var auth_token: String = ""
var current_user: Dictionary = {}


func set_base_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")


func is_authenticated() -> bool:
	return not auth_token.is_empty()


func register_user(username: String, password: String) -> Dictionary:
	return await _request("POST", "/v1/auth/register", {"username": username, "password": password}, false)


func login_user(username: String, password: String) -> Dictionary:
	var result: Dictionary = await _request("POST", "/v1/auth/login", {"username": username, "password": password}, false)
	if result.get("ok", false):
		auth_token = result.get("body", {}).get("token", "")
		current_user = result.get("body", {}).get("user", {})
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
