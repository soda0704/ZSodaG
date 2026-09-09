class_name SteamNetworkService
extends Node

signal steam_initialized(user_name: String)
signal steam_initialization_failed(reason: String)
signal state_changed(state: SessionState, message: String)
signal lobby_entered(lobby_id: int, as_host: bool)
signal lobby_members_changed(members: Array[Dictionary])
signal lobby_list_received(lobbies: Array[Dictionary])
signal invite_join_requested(lobby_id: int)
signal session_ready(as_host: bool)
signal session_closed(reason: String)
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

enum SessionState {
	STARTING_STEAM,
	STEAM_UNAVAILABLE,
	READY,
	CREATING_LOBBY,
	JOINING_LOBBY,
	HOSTING,
	CONNECTING,
	CONNECTED,
	LEAVING,
}

const DEFAULT_APP_ID := 480
const DEFAULT_MAX_MEMBERS := 2
const DEFAULT_LOBBY_TAG := "northern_lab_story_coop_v1"
const NETWORK_VERSION := "2"
const BUILD_ID_PATH := "res://network_build.cfg"
var _build_identity: String = ""
const STEAM_API_INIT_RESULT_OK := 0
const STEAM_RESULT_OK := 1
const CHAT_ROOM_ENTER_SUCCESS := 1
const LOBBY_TYPE_FRIENDS_ONLY := 1
const LOBBY_COMPARISON_EQUAL := 0
var state: SessionState = SessionState.STARTING_STEAM
var state_message: String = "Starting Steam..."
var steam_available: bool = false
var lobby_id: int = 0
var is_host: bool = false
var local_steam_id: int = 0
var local_user_name: String = "Player"

var _steam: Object
var _peer: MultiplayerPeer
var _is_leaving: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	connect_multiplayer_callbacks()
	initialize_steam()


func _process(_delta: float) -> void:
	if steam_available and _steam != null:
		_steam.call("run_callbacks")


func connect_steam_callbacks() -> void:
	connect_steam_signal("lobby_created", _on_lobby_created)
	connect_steam_signal("lobby_joined", _on_lobby_joined)
	connect_steam_signal("lobby_match_list", _on_lobby_match_list)
	connect_steam_signal("lobby_chat_update", _on_lobby_chat_update)
	connect_steam_signal("lobby_data_update", _on_lobby_data_update)
	connect_steam_signal("join_requested", _on_lobby_join_requested)


func connect_steam_signal(signal_name: StringName, callback: Callable) -> void:
	if (
		_steam != null
		and _steam.has_signal(signal_name)
		and not _steam.is_connected(signal_name, callback)
	):
		_steam.connect(signal_name, callback)


func connect_multiplayer_callbacks() -> void:
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func initialize_steam() -> void:
	set_state(SessionState.STARTING_STEAM, "Starting Steam...")
	if not Engine.has_singleton("Steam"):
		var missing_reason := (
			"GodotSteam is unavailable. Use a compatible editor and Steam API."
		)
		set_state(SessionState.STEAM_UNAVAILABLE, missing_reason)
		steam_initialization_failed.emit(missing_reason)
		return

	_steam = Engine.get_singleton("Steam")
	connect_steam_callbacks()
	var app_id := int(
		ProjectSettings.get_setting("network/steam/app_id", DEFAULT_APP_ID)
	)
	var response: Dictionary = _steam.call("steamInitEx", app_id, false)
	var status := int(response.get("status", -1))

	if status != STEAM_API_INIT_RESULT_OK:
		steam_available = false
		var reason := str(response.get("verbal", "Unknown Steam error"))
		set_state(SessionState.STEAM_UNAVAILABLE, reason)
		steam_initialization_failed.emit(reason)
		return

	steam_available = true
	local_steam_id = int(_steam.call("getSteamID"))
	local_user_name = str(_steam.call("getPersonaName")).strip_edges()
	if local_user_name.is_empty():
		local_user_name = "Player"

	print(
		"Steam initialized for %s (App ID %s, GodotSteam %s)."
		% [
			local_user_name,
			app_id,
			_steam.call("get_godotsteam_version"),
		]
	)
	set_state(SessionState.READY, "Steam online as %s" % local_user_name)
	steam_initialized.emit(local_user_name)


func create_friends_lobby() -> bool:
	if not can_start_session():
		return false

	reset_current_session(false)
	set_state(SessionState.CREATING_LOBBY, "Creating friends-only lobby...")
	var max_members := int(
		ProjectSettings.get_setting(
			"network/steam/lobby_max_members",
			DEFAULT_MAX_MEMBERS
		)
	)
	_steam.call(
		"createLobby",
		LOBBY_TYPE_FRIENDS_ONLY,
		clampi(max_members, 2, DEFAULT_MAX_MEMBERS)
	)
	return true


func join_lobby(target_lobby_id: int) -> bool:
	if not can_start_session() or target_lobby_id <= 0:
		return false

	reset_current_session(true)
	set_state(
		SessionState.JOINING_LOBBY,
		"Joining Steam lobby %s..." % target_lobby_id
	)
	_steam.call("joinLobby", target_lobby_id)
	return true


func request_lobby_list() -> bool:
	if not steam_available:
		return false

	_steam.call(
		"addRequestLobbyListStringFilter",
		"game_tag",
		get_lobby_tag(),
		LOBBY_COMPARISON_EQUAL
	)
	_steam.call(
		"addRequestLobbyListStringFilter",
		"network_version",
		NETWORK_VERSION,
		LOBBY_COMPARISON_EQUAL
	)
	_steam.call("addRequestLobbyListFilterSlotsAvailable", 1)
	_steam.call("addRequestLobbyListResultCountFilter", 30)
	_steam.call("requestLobbyList")
	set_state(state, "Searching for compatible lobbies...")
	return true


func open_invite_overlay() -> bool:
	if (
		not steam_available
		or lobby_id <= 0
		or not is_host
		or not is_overlay_enabled()
	):
		return false

	_steam.call("activateGameOverlayInviteDialog", lobby_id)
	return true


func is_overlay_enabled() -> bool:
	return (
		steam_available
		and _steam != null
		and _steam.has_method("isOverlayEnabled")
		and bool(_steam.call("isOverlayEnabled"))
	)


func leave_session(reason: String = "Left session") -> void:
	if _is_leaving:
		return

	_is_leaving = true
	set_state(SessionState.LEAVING, reason)
	reset_current_session(true)
	_is_leaving = false
	set_state(SessionState.READY, "Steam online as %s" % local_user_name)
	session_closed.emit(reason)


func can_start_session() -> bool:
	return (
		steam_available
		and state != SessionState.CREATING_LOBBY
		and state != SessionState.JOINING_LOBBY
		and state != SessionState.CONNECTING
		and state != SessionState.LEAVING
	)


func has_active_session() -> bool:
	return _peer != null and lobby_id > 0


func get_lobby_members() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	if not steam_available or lobby_id <= 0:
		return members

	var member_count := int(_steam.call("getNumLobbyMembers", lobby_id))
	var owner_id := int(_steam.call("getLobbyOwner", lobby_id))
	for member_index in member_count:
		var member_steam_id := int(
			_steam.call("getLobbyMemberByIndex", lobby_id, member_index)
		)
		var member_name := get_persona_name(member_steam_id)
		members.append({
			"steam_id": member_steam_id,
			"name": member_name,
			"is_host": member_steam_id == owner_id,
		})
	return members


func get_peer_persona_name(peer_id: int) -> String:
	if _peer == null:
		return "Player %s" % peer_id

	var steam_id := int(_peer.call("get_steam_id_for_peer_id", peer_id))
	if steam_id <= 0:
		return "Player %s" % peer_id
	return get_persona_name(steam_id)


func get_peer_inventory_id(peer_id: int) -> String:
	if _peer != null:
		var steam_id := int(_peer.call("get_steam_id_for_peer_id", peer_id))
		if steam_id > 0:
			return "steam:%d" % steam_id
	return "peer:%d" % peer_id


func get_persona_name(steam_id: int) -> String:
	if steam_id == local_steam_id:
		return local_user_name

	var persona_name := str(
		_steam.call("getFriendPersonaName", steam_id)
	).strip_edges()
	if persona_name.is_empty():
		return "Steam %s" % steam_id
	return persona_name


func get_lobby_tag() -> String:
	return str(
		ProjectSettings.get_setting(
			"network/steam/lobby_tag",
			DEFAULT_LOBBY_TAG
		)
	)


func get_build_identity() -> String:
	if not _build_identity.is_empty():
		return _build_identity
	if OS.has_feature("editor") and FileAccess.file_exists("res://project.godot"):
		_build_identity = compute_source_identity()
	else:
		var config := ConfigFile.new()
		if config.load(BUILD_ID_PATH) == OK:
			_build_identity = str(config.get_value("build", "identity", ""))
	return _build_identity


static func compute_source_identity() -> String:
	var paths: Array[String] = ["res://project.godot", "res://game_actions_480.vdf"]
	_collect_identity_paths("res://scripts", paths)
	_collect_identity_paths("res://scenes", paths)
	paths.sort()
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in paths:
		context.update(path.to_utf8_buffer())
		context.update(FileAccess.get_file_as_string(path).replace("\r\n", "\n").to_utf8_buffer())
	return context.finish().hex_encode()


static func _collect_identity_paths(directory: String, paths: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["gd", "tscn", "tres"]:
			paths.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		_collect_identity_paths(directory.path_join(child), paths)


func is_compatible_lobby(tag: String, protocol: String, identity: String) -> bool:
	return (
		tag == get_lobby_tag() and protocol == NETWORK_VERSION
		and not identity.is_empty() and identity == get_build_identity()
	)


func set_state(next_state: SessionState, message: String) -> void:
	state = next_state
	state_message = message
	state_changed.emit(state, state_message)


func reset_current_session(leave_lobby: bool) -> void:
	if _peer != null:
		_peer.close()
		_peer = null

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	if leave_lobby and steam_available and lobby_id > 0:
		_steam.call("leaveLobby", lobby_id)

	lobby_id = 0
	is_host = false
	var empty_members: Array[Dictionary] = []
	lobby_members_changed.emit(empty_members)


func start_host_peer() -> void:
	var next_peer := create_steam_peer()
	if next_peer == null:
		fail_session("SteamMultiplayerPeer is unavailable.")
		return
	var result := int(next_peer.call("create_host", 0))
	if result != OK:
		fail_session("Could not create Steam host peer: %s" % error_string(result))
		return

	next_peer.server_relay = true
	_peer = next_peer
	multiplayer.multiplayer_peer = _peer
	set_state(SessionState.HOSTING, "Lobby ready. Invite a friend.")
	session_ready.emit(true)


func start_client_peer(host_steam_id: int) -> void:
	var next_peer := create_steam_peer()
	if next_peer == null:
		fail_session("SteamMultiplayerPeer is unavailable.")
		return
	var result := int(next_peer.call("create_client", host_steam_id, 0))
	if result != OK:
		fail_session("Could not connect to Steam host: %s" % error_string(result))
		return

	next_peer.server_relay = true
	_peer = next_peer
	multiplayer.multiplayer_peer = _peer
	set_state(SessionState.CONNECTING, "Connecting to lobby host...")


func create_steam_peer() -> MultiplayerPeer:
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer


func fail_session(reason: String) -> void:
	push_error(reason)
	reset_current_session(true)
	set_state(SessionState.READY, reason)
	session_closed.emit(reason)


func _on_lobby_created(connect_status: int, new_lobby_id: int) -> void:
	if connect_status != STEAM_RESULT_OK:
		fail_session("Steam could not create the lobby (%s)." % connect_status)
		return

	lobby_id = new_lobby_id
	_steam.call("setLobbyData", lobby_id, "game_tag", get_lobby_tag())
	_steam.call("setLobbyData", lobby_id, "network_version", NETWORK_VERSION)
	_steam.call("setLobbyData", lobby_id, "build_identity", get_build_identity())
	_steam.call("setLobbyData", lobby_id, "game_mode", "story_coop")
	_steam.call(
		"setLobbyData",
		lobby_id,
		"lobby_name",
		"%s's Northern Lab" % local_user_name
	)
	_steam.call("setLobbyJoinable", lobby_id, true)


func _on_lobby_joined(
	joined_lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	if response != CHAT_ROOM_ENTER_SUCCESS:
		fail_session(
			"Steam could not enter lobby %s (response %s)."
			% [joined_lobby_id, response]
		)
		return

	lobby_id = joined_lobby_id
	var owner_steam_id := int(_steam.call("getLobbyOwner", lobby_id))
	is_host = owner_steam_id == local_steam_id
	if not is_host and not is_compatible_lobby(
		str(_steam.call("getLobbyData", lobby_id, "game_tag")),
		str(_steam.call("getLobbyData", lobby_id, "network_version")),
		str(_steam.call("getLobbyData", lobby_id, "build_identity"))
	):
		fail_session("Несовместимая сборка. Оба игрока должны обновить проект и пересобрать игру через NorthernLab.cmd.")
		return
	lobby_entered.emit(lobby_id, is_host)
	lobby_members_changed.emit(get_lobby_members())

	if is_host:
		start_host_peer()
	else:
		start_client_peer(owner_steam_id)


func _on_lobby_match_list(lobby_ids: Array) -> void:
	var lobbies: Array[Dictionary] = []
	for found_lobby_id_variant in lobby_ids:
		var found_lobby_id := int(found_lobby_id_variant)
		var owner_id := int(_steam.call("getLobbyOwner", found_lobby_id))
		var lobby_name := str(
			_steam.call("getLobbyData", found_lobby_id, "lobby_name")
		).strip_edges()
		if lobby_name.is_empty():
			lobby_name = "%s's lobby" % get_persona_name(owner_id)

		lobbies.append({
			"lobby_id": found_lobby_id,
			"name": lobby_name,
			"members": _steam.call("getNumLobbyMembers", found_lobby_id),
			"limit": _steam.call("getLobbyMemberLimit", found_lobby_id),
		})

	lobby_list_received.emit(lobbies)
	set_state(state, "Found %s compatible lobby/lobbies." % lobbies.size())


func _on_lobby_chat_update(
	updated_lobby_id: int,
	_changed_id: int,
	_making_change_id: int,
	_chat_state: int
) -> void:
	if updated_lobby_id == lobby_id:
		lobby_members_changed.emit(get_lobby_members())


func _on_lobby_data_update(
	_success: int,
	updated_lobby_id: int,
	_member_id: int
) -> void:
	if updated_lobby_id == lobby_id:
		lobby_members_changed.emit(get_lobby_members())


func _on_lobby_join_requested(requested_lobby_id: int, _friend_id: int) -> void:
	invite_join_requested.emit(requested_lobby_id)


func _on_connected_to_server() -> void:
	set_state(SessionState.CONNECTED, "Connected to host through Steam.")
	session_ready.emit(false)


func _on_connection_failed() -> void:
	fail_session("Connection to the Steam host failed.")


func _on_server_disconnected() -> void:
	if not _is_leaving:
		leave_session("Host disconnected. Returning to lobby menu.")


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)
	if lobby_id > 0:
		lobby_members_changed.emit(get_lobby_members())


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)
	if lobby_id > 0:
		lobby_members_changed.emit(get_lobby_members())
