extends "res://scripts/network/base_session_controller.gd"
## ENet has no Steam identity. Simulate stable account IDs, retaining all other
## production session behavior so reconnects use the same persisted inventory.
func _inventory_id(peer_id: int) -> String:
	return "test:host" if peer_id == 1 else "test:guest"

# Gameplay-focused ENet tests explicitly accept the lobby before exercising
# their mechanic; the production session no longer skips it when resuming.
func start_test_session(as_host: bool) -> void:
	if as_host: CoopLobby._on_session_ready(true)
	_on_session_ready(as_host)
	if as_host: launch_test_expedition()

func launch_test_expedition() -> bool:
	for peer_id in multiplayer.get_peers():
		CoopLobby.set_peer_ready(peer_id, true)
	return CoopLobby.set_local_ready(true) and CoopLobby.start_game()
