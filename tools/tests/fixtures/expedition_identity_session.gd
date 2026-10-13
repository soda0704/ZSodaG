extends "res://scripts/network/base_session_controller.gd"
## ENet has no Steam identity. Simulate stable account IDs, retaining all other
## production session behavior so reconnects use the same persisted inventory.
func _inventory_id(peer_id: int) -> String:
	return "test:host" if peer_id == 1 else "test:guest"
