extends "res://scripts/network/steam/steam_network_service.gd"
## Tests the production creation route without contacting Steam or inviting anyone.
var created_lobbies := 0
func _process(_delta: float) -> void: pass
func create_friends_lobby() -> bool:
	created_lobbies += 1
	steam_available = true
	is_host = true
	lobby_id = 1
	local_steam_id = 1
	_peer = OfflineMultiplayerPeer.new()
	state = SessionState.HOSTING
	session_ready.emit(true)
	return true
func get_lobby_members() -> Array[Dictionary]:
	return [{"steam_id":1,"name":"Test host","is_owner":true,"is_local":true}]
func get_peer_persona_name(_peer_id: int) -> String: return "Test host"
func _exit_tree() -> void: pass
