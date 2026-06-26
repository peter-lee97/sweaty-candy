extends Node

signal lobby_events_updated(lobbies: Array)

const PING_SAMPLE_COUNT: int = 3
const PING_TIMEOUT_SEC: float = 3.0

var _base_url: String = "http://127.0.0.1:8787"
var _websocket: WebSocketPeer = WebSocketPeer.new()
var _ws_connected: bool = false
var _ws_url: String = ""


func _init() -> void:
	if OS.has_feature("web"):
		var origin: String = JavaScriptBridge.eval("window.location.origin")
		if origin:
			_base_url = origin


func is_authenticated() -> bool:
	return GameData.token != ""


func ping_backend() -> int:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	http.timeout = PING_TIMEOUT_SEC
	var url: String = _base_url + "/health"
	var t0: int = Time.get_ticks_msec()
	var err: int = http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if err != OK:
		http.queue_free()
		return -1
	var result: Array = await http.request_completed
	http.queue_free()
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return -1
	var code: int = result[1]
	if code < 200 or code >= 300:
		return -1
	return Time.get_ticks_msec() - t0


func ping_backend_avg(samples: int = PING_SAMPLE_COUNT) -> int:
	var total: int = 0
	var count: int = 0
	for i in samples:
		var ms: int = await ping_backend()
		if ms >= 0:
			total += ms
			count += 1
	if count == 0:
		return -1
	var avg: int = int(total / float(count))
	GameData.backend_ping_ms = avg
	return avg


func authenticate_guest() -> Dictionary:
	if GameData.token != "":
		return {"ok": true, "id": GameData.user_id, "username": GameData.username, "token": GameData.token}
	var res: Dictionary = await _request("POST", "/v1/auth/guest")
	if res.ok:
		GameData.user_id = str(res.body.id)
		GameData.username = str(res.body.username)
		GameData.token = str(res.body.token)
	return res


func list_lobbies() -> Dictionary:
	return await _request("GET", "/v1/lobbies")


func create_lobby(room_name: String, password: String, max_players: int) -> Dictionary:
	var body: Dictionary = {"maxPlayers": max_players}
	if room_name != "":
		body["roomName"] = room_name
	if password != "":
		body["password"] = password
	return await _request("POST", "/v1/lobbies", body)


func join_lobby(lobby_id: String, password: String) -> Dictionary:
	var body: Dictionary = {}
	if password != "":
		body["password"] = password
	return await _request("POST", "/v1/lobbies/" + lobby_id + "/join", body)


func leave_lobby(lobby_id: String) -> Dictionary:
	return await _request("POST", "/v1/lobbies/" + lobby_id + "/leave")


func start_lobby(lobby_id: String) -> Dictionary:
	return await _request("POST", "/v1/lobbies/" + lobby_id + "/start")


func connect_lobby_events() -> void:
	if not is_authenticated():
		return
	var ws_base: String = _base_url
	if ws_base.begins_with("http://"):
		ws_base = "ws://" + ws_base.substr(7)
	elif ws_base.begins_with("https://"):
		ws_base = "wss://" + ws_base.substr(8)
	_ws_url = ws_base + "/v1/lobbies/events?token=" + GameData.token
	if _ws_connected and _websocket != null:
		if _websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_websocket.close()
		_ws_connected = false
		_websocket = null
	_websocket = WebSocketPeer.new()
	var err: int = _websocket.connect_to_url(_ws_url)
	if err != OK:
		push_error("WebSocket connect failed: %d" % err)
		_websocket = null
		return
	_ws_connected = true


func disconnect_lobby_events() -> void:
	if _ws_connected and _websocket != null:
		if _websocket.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_websocket.close()
	_ws_connected = false
	_websocket = null


func _process(_delta: float) -> void:
	if not _ws_connected or _websocket == null:
		return
	var state: int = _websocket.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_ws_connected = false
		_websocket = null
		return
	if state != WebSocketPeer.STATE_CONNECTING and state != WebSocketPeer.STATE_OPEN:
		return
	_websocket.poll()
	state = _websocket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		var pending_lobbies: Array = []
		while _websocket.get_available_packet_count() > 0:
			var packet: PackedByteArray = _websocket.get_packet()
			var json: Variant = JSON.parse_string(packet.get_string_from_utf8())
			if json != null and json.has("lobbies"):
				pending_lobbies.append(json.lobbies)
		for lobbies in pending_lobbies:
			lobby_events_updated.emit(lobbies)
	elif state == WebSocketPeer.STATE_CLOSED:
		_ws_connected = false
		_websocket = null


func _request(method: String, path: String, body: Dictionary = {}) -> Dictionary:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	var url: String = _base_url + path
	var headers: Array[String] = ["Content-Type: application/json"]
	if GameData.token != "":
		headers.append("Authorization: Bearer " + GameData.token)
	var body_str: String = ""
	if not body.is_empty():
		body_str = JSON.stringify(body)
	var http_method: int = HTTPClient.METHOD_POST
	if method == "GET":
		http_method = HTTPClient.METHOD_GET
	http.timeout = 5.0
	var err: int = http.request(url, PackedStringArray(headers), http_method, body_str)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "request failed: %d" % err}
	var result: Array = await http.request_completed
	if result[0] == HTTPRequest.RESULT_TIMEOUT:
		http.queue_free()
		return {"ok": false, "error": "Request timed out"}
	var code: int = result[1]
	var response_body: String = result[3].get_string_from_utf8()
	http.queue_free()
	var parsed: Dictionary = {}
	if response_body.length() > 0:
		var raw: Variant = JSON.parse_string(response_body)
		if raw != null:
			parsed = raw
	return {"ok": code >= 200 and code < 300, "status": code, "body": parsed}
