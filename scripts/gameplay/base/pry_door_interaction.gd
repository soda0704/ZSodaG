extends StaticBody3D

var manager: Node
var door: Dictionary
var busy := false

func get_interaction_prompt() -> String:
	if busy:
		return "Вскрытие…"
	var local := get_tree().get_first_node_in_group("local_player")
	if not door.open and not door.locked and local != null and local.crowbar_uses <= 0:
		return "Закрыто · нужна монтировка"
	return "Вскрыть монтировкой · 1 использование" if not door.open and not door.locked else "Дверь открыта" if door.open else "Ворота слишком тяжёлые"

func network_interact(peer: int, player: Node) -> void:
	if not multiplayer.is_server() or busy or door.open or door.locked or player == null or int(player.get("owner_peer_id")) != peer:
		return
	if player.crowbar_uses <= 0 or player.survival.dead or player.global_position.distance_to(door.anchor.global_position + Vector3.UP) > 4.0:
		return
	busy = true
	player.play_crowbar_action.rpc()
	await get_tree().create_timer(1.2, false).timeout
	busy = false
	if not is_instance_valid(player) or player.survival.dead or player.crowbar_uses <= 0 or door.open or player.global_position.distance_to(door.anchor.global_position + Vector3.UP) > 4.0:
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
	controller._broadcast_snapshot(state)
