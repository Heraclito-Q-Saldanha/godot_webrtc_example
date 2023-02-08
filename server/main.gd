extends Node

const SERVER_PORT:= 6464
const MATCH_SIZE:= 2
var _websocket:= WebSocketServer.new()
var _connected_players: Dictionary
var _match_queue: Array

func _ready() -> void:
	print("server staring...")
	_websocket.connect("client_connected", self, "_client_connected")
	_websocket.connect("client_disconnected", self, "_client_disconnected")
	_websocket.connect("data_received", self, "_data_received")
	var err:= _websocket.listen(SERVER_PORT)
	if err != OK:
		printerr("error start server, code: %d" %err)
		get_tree().quit(err)
		return
	print("server started sucessful")

func _process(_delta: float) -> void:
	if _websocket.get_connection_status() != WebSocketServer.CONNECTION_DISCONNECTED:
		_websocket.poll()

func _client_connected(id: int, _protocol: String) -> void:
	print("peer %d connected" %id)
	_connected_players[id] = null
	_match_queue.append(id)
	if _match_queue.size() >= MATCH_SIZE:
		create_new_match()

func _client_disconnected(id: int, clear: bool) -> void:
	print("peer %d disconnected" %id)
	_connected_players.erase(id)
	_match_queue.erase(id)

func _data_received(id: int) -> void:
	var buffer_data:= _websocket.get_peer(id).get_packet()
	var json:= JSON.parse(buffer_data.get_string_from_utf8())
	if json.error != OK: return
	var data:Dictionary = json.result
	for key in data.keys():
		match key:
			"offer":
				if _connected_players[id] == null: return
				var peer_id:= int(data[key]["id"])
				data[key]["id"] = id
				_websocket.get_peer(peer_id).put_packet(JSON.print(data).to_utf8())
			"ice":
				if _connected_players[id] == null: return
				var peer_id:= int(data[key]["id"])
				data[key]["id"] = id
				_websocket.get_peer(peer_id).put_packet(JSON.print(data).to_utf8())

func create_new_match() -> void:
	var new_match:= []
	for i in range(MATCH_SIZE):
		new_match.append(_match_queue[i])
	
	for _i in range(MATCH_SIZE):
		_websocket.get_peer(_match_queue[0]).put_packet(JSON.print({
			"matched": {
				"id": _match_queue[0],
				"peer_list": new_match
			}
		}).to_utf8())
		_match_queue.remove(0)
	
	for i in range(new_match.size()):
		_connected_players[new_match[i]] = new_match
