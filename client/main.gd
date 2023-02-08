extends Node

const SERVER_PORT:= 6464
const SERVER_ADDR:= "127.0.0.1"

var _websocket:= WebSocketClient.new()
var _webrtc:= WebRTCMultiplayer.new()
var match_peer_list_state: Dictionary

signal match_ready
signal match_matched

func _ready() -> void:
	_websocket.connect("connection_established", self, "_ws_connection_established")
	_websocket.connect("connection_failed", self, "_ws_connection_failed")
	_websocket.connect("data_received", self, "_data_received")
	_webrtc.connect("peer_connected", self, "_wrtc_peer_connected")
	_webrtc.connect("peer_disconnected", self, "_wrtc_peer_disconnected")
	var err:= _websocket.connect_to_url("%s:%d" %[SERVER_ADDR, SERVER_PORT])
	if err != OK:
		printerr("connection failed, code %d", err)

func _process(_delta: float) -> void:
	_webrtc.poll()
	if _websocket.get_connection_status() != WebSocketClient.CONNECTION_DISCONNECTED:
		_websocket.poll()

func _ws_connection_established(_protocol: String) -> void:
	print("WS connection established")

func _ws_connection_failed() -> void:
	print("WS connection failed")

func _wrtc_peer_connected(id: int) -> void:
	print("WRTC peer %d connect" %id)
	match_peer_list_state[id] = true
	for i in match_peer_list_state.values(): if !i: return
	emit_signal("match_ready")
	print("match_ready")
	get_tree().set_network_peer(_webrtc)
	
func _wrtc_peer_disconnected(id: int) -> void:
	match_peer_list_state.erase(id)
	print("WRTC peer %d disconnect" %id)

func _data_received() -> void:
	var data_buffer:= _websocket.get_peer(1).get_packet()
	var json:= JSON.parse(data_buffer.get_string_from_utf8())
	if json.error != OK: return
	var data:Dictionary = json.result
	for key in data.keys():
		match key:
			"offer":
				var id:= int(data[key]["id"])
				if _webrtc.has_peer(id):
					_webrtc.get_peer(id).connection.set_remote_description(data[key]["type"], data[key]["sdp"])
			"ice":
				var id:= int(data[key]["id"])
				if _webrtc.has_peer(id):
					_webrtc.get_peer(id).connection.add_ice_candidate(data[key]["media"], int(data[key]["index"]), data[key]["name"])
			"matched":
				emit_signal("match_matched")
				var peer_list:Array = data[key]["peer_list"]
				var id:= int(data[key]["id"])
				print("matched, players: ", peer_list)
				_webrtc.initialize(id)
				for peer in peer_list:
					if int(peer) != id: _create_peer(int(peer))
				
func _create_peer(id: int) -> void:
	match_peer_list_state[id] = false
	var peer:= WebRTCPeerConnection.new()
	peer.connect("session_description_created", self, "_offer_created", [id])
	peer.connect("ice_candidate_created", self, "_ice_candidate_created", [id])
	
	peer.initialize({
		"iceServers": [{
			"urls": ["stun:stun.l.google.com:19302"]
		}]
	})
	
	_webrtc.add_peer(peer, id)
	if id > _webrtc.get_unique_id():
		peer.create_offer()
	print("peer %d created" %id)

func _offer_created(type: String, sdp: String, id: int) -> void:
	print("offer created: type:%s, sdp:%s, id:%d" %[type, sdp, id])
	_webrtc.get_peer(id).connection.set_local_description(type, sdp)
	_websocket.get_peer(1).put_packet(JSON.print({
		"offer": {
			"type": type,
			"sdp": sdp,
			"id": id
		}
	}).to_utf8())

func _ice_candidate_created(media: String, index: int, _name: String, id: int) -> void:
	print("offer created: media:%s, index:%d, name:%s, id:%d" %[media, index, _name, id])
	_websocket.get_peer(1).put_packet(JSON.print({
		"ice": {
			"media": media,
			"index": index,
			"name": _name,
			"id": id
		}
	}).to_utf8())
