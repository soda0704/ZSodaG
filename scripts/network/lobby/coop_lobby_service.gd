class_name CoopLobbyService
extends Node

signal ready_state_changed(ready_states: Dictionary)
signal gameplay_started

const MAX_PLAYERS := 2

var ready_states: Dictionary = {}
var session_active: bool = false
var game_has_started: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	SteamNetwork.peer_joined.connect(_on_peer_joined)
	SteamNetwork.peer_left.connect(_on_peer_left)


func set_local_ready(is_ready: bool) -> bool:
	if not session_active or game_has_started:
		return false

	var local_peer_id := multiplayer.get_unique_id()
	if local_peer_id <= 0:
		return false

	if multiplayer.is_server():
		set_peer_ready(local_peer_id, is_ready)
	else:
		_submit_ready.rpc_id(1, is_ready)
	return true


func is_local_ready() -> bool:
	return bool(ready_states.get(multiplayer.get_unique_id(), false))


func get_ready_count() -> int:
	var count := 0
	for is_ready in ready_states.values():
		if bool(is_ready):
			count += 1
	return count


func get_player_count() -> int:
	return ready_states.size()


func can_host_start() -> bool:
	if (
		not session_active
		or game_has_started
		or not multiplayer.is_server()
	):
		return false

	# Validate the live transport peers, not only the cached dictionary. This
	# closes the short join window where a connected peer has not reached the
	# ready-state callback yet.
	var connected_peer_ids: Array[int] = [multiplayer.get_unique_id()]
	for connected_peer_id in multiplayer.get_peers():
		connected_peer_ids.append(int(connected_peer_id))
	for peer_id in connected_peer_ids:
		if not ready_states.has(peer_id) or not bool(ready_states[peer_id]):
			return false
	for is_ready in ready_states.values():
		if not bool(is_ready):
			return false
	return true


func start_game() -> bool:
	if not can_host_start():
		return false

	_receive_gameplay_started.rpc()
	return true


func is_waiting_for_start() -> bool:
	return session_active and not game_has_started


func set_peer_ready(peer_id: int, is_ready: bool) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return

	ready_states[peer_id] = is_ready
	broadcast_ready_state()


func broadcast_ready_state() -> void:
	if not multiplayer.is_server():
		return
	_receive_ready_state.rpc(ready_states.duplicate(true))


@rpc("any_peer", "call_remote", "reliable")
func _submit_ready(is_ready: bool) -> void:
	if not multiplayer.is_server() or not session_active:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender_id):
		return
	set_peer_ready(sender_id, is_ready)


@rpc("any_peer", "call_remote", "reliable")
func _request_ready_state() -> void:
	if not multiplayer.is_server() or not session_active:
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if not multiplayer.get_peers().has(sender_id):
		return
	_receive_ready_state.rpc_id(sender_id, ready_states.duplicate(true))
	if game_has_started:
		_receive_gameplay_started.rpc_id(sender_id)


@rpc("authority", "call_local", "reliable")
func _receive_ready_state(next_ready_states: Dictionary) -> void:
	ready_states = next_ready_states.duplicate(true)
	ready_state_changed.emit(ready_states.duplicate(true))


@rpc("authority", "call_local", "reliable")
func _receive_gameplay_started() -> void:
	if game_has_started:
		return
	game_has_started = true
	gameplay_started.emit()


func _on_session_ready(as_host: bool) -> void:
	session_active = true
	game_has_started = false
	ready_states.clear()
	ready_state_changed.emit(ready_states.duplicate(true))

	if as_host:
		set_peer_ready(multiplayer.get_unique_id(), false)
	else:
		_request_ready_state.rpc_id(1)


func _on_peer_joined(peer_id: int) -> void:
	if session_active and multiplayer.is_server():
		set_peer_ready(peer_id, false)


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server() or not ready_states.has(peer_id):
		return
	ready_states.erase(peer_id)
	broadcast_ready_state()


func _on_session_closed(_reason: String) -> void:
	session_active = false
	game_has_started = false
	ready_states.clear()
	ready_state_changed.emit(ready_states.duplicate(true))
