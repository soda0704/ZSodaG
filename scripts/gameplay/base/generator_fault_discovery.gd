extends Area3D
## A real room visit reveals the shared maintenance objective, including after loading.
var _elapsed := 0.0

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	_elapsed += delta
	if _elapsed < 0.3: return
	_elapsed = 0.0
	var state := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if state == null or not state.maintenance.get("wires_required", false) or state.maintenance.get("generator_fault_discovered", false): return
	for body in get_overlapping_bodies():
		if not body is GamePlayer or body.survival.dead or body.is_sleeping_in_bunk(): continue
		if state.get_player_node(body.owner_peer_id) != body: continue
		var snapshot := state.get_snapshot()
		snapshot.maintenance["generator_fault_discovered"] = true
		state._broadcast_snapshot(snapshot)
		return
