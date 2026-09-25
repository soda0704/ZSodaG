extends CollisionObject3D

var manager: Node
var door: Dictionary
var busy := false

func get_interaction_prompt() -> String:
	if busy:
		return "Вскрытие…"
	if manager.is_door_pried(door):
		return "Закрыть вручную" if door.open else "Открыть вручную"
	if manager._controller != null and manager._controller.main_breaker_on and not door.locked:
		return ""
	var local := get_tree().get_first_node_in_group("local_player")
	if not door.open and not door.locked and local != null and local.crowbar_uses <= 0:
		return ""
	return "Вскрыть монтировкой" if not door.open and not door.locked and local != null and local.crowbar_uses > 0 else ""

func network_interact(peer: int, player: Node) -> void:
	if not multiplayer.is_server() or busy or door.locked or player == null or int(player.get("owner_peer_id")) != peer:
		return
	if player.survival.dead or player.global_position.distance_to(door.anchor.global_position + Vector3.UP) > 4.0:
		return
	if manager.is_door_pried(door):
		manager.set_pried_door_open(door, not door.open)
		return
	if player.crowbar_uses <= 0 or door.open or (manager._controller != null and manager._controller.main_breaker_on):
		return
	busy = true
	player.play_crowbar_action.rpc()
	await get_tree().create_timer(1.2, false).timeout
	busy = false
	if not is_instance_valid(player) or player.survival.dead or player.crowbar_uses <= 0 or door.open or manager.is_door_pried(door) or manager._controller.main_breaker_on or player.global_position.distance_to(door.anchor.global_position + Vector3.UP) > 4.0:
		return
	player.crowbar_uses -= 1
	player._publish_inventory()
	var controller: BaseGameplayController = manager.get("_controller")
	var state := controller.get_snapshot()
	var doors: Array = state.maintenance.get("pried_doors", [])
	var id := str(manager.get_parent().get_path_to(door.anchor))
	if not doors.has(id):
		doors.append(id)
	state.maintenance["pried_doors"] = doors
	var manual: Dictionary = state.maintenance.get("manual_doors", {})
	manual[id] = true
	state.maintenance["manual_doors"] = manual
	var overrides: Dictionary = state.maintenance.get("debug_doors", {})
	overrides.erase(id)
	state.maintenance["debug_doors"] = overrides
	controller._broadcast_snapshot(state)
