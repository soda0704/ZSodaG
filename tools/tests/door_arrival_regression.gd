extends SceneTree

var failures: Array[String] = []
func _initialize():
	run.call_deferred()
func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func run():
	var save_path := "user://door_arrival_test_%d.json" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	await root.get_node("GameMenu").start_standalone_flow()
	var world = current_scene
	await create_timer(2).timeout
	check(world.is_solo_arrival(), "new solo stays in helicopter")
	var menu = root.get_node("GameMenu")
	check(not menu.is_menu_open(), "cabin initially playable")
	var escape := InputEventAction.new()
	escape.action = "pause"
	escape.pressed = true
	menu._unhandled_input(escape)
	check(menu.session_panel.visible and not menu.ready_button.disabled, "ESC exposes solo readiness")
	menu.close_menu()
	check(world.is_solo_arrival() and not menu.is_menu_open(), "closing ESC does not land")
	menu.open_menu(menu.MenuView.SESSION)
	menu._on_ready_pressed()
	await create_timer(3).timeout
	check(world.has_node("V3Level") and not world.is_solo_arrival(), "explicit readiness lands at base")
	var controller = get_first_node_in_group("base_gameplay_controller")
	var player = get_first_node_in_group("network_players")
	player.set_physics_process(false)
	var manager: BaseAutoDoorManager
	var door: Dictionary
	for candidate in get_nodes_in_group("base_auto_door_managers"):
		for entry in candidate._doors:
			if not entry.locked and not entry.startup_route and not entry.emergency_egress:
				manager = candidate
				door = entry
				break
		if manager != null: break
	assert(manager != null)
	var id := str(manager.get_parent().get_path_to(door.anchor))
	player.global_position = door.anchor.global_position + Vector3(10,0,0)
	var state: Dictionary = controller.get_snapshot()
	state.main_breaker_on = false
	state.fuel_delivered = true
	state.fuel_liters = 20.0
	state.maintenance["pried_doors"] = []
	state.maintenance["debug_doors"] = {id: true}
	controller._broadcast_snapshot(state)
	await create_timer(0.3).timeout
	check(not door.open, "legacy permanent console override removed")
	manager.debug_set_door_open(door.anchor,true)
	await create_timer(0.2).timeout
	check(door.open,"console open applied")
	state=controller.get_snapshot()
	state.main_breaker_on=true
	controller._broadcast_snapshot(state)
	await create_timer(0.2).timeout
	check(not door.open,"power change restores automatic closing")
	player.global_position=door.anchor.global_position+Vector3(0,0,2)
	await create_timer(0.2).timeout
	check(door.open,"powered door opens on approach")
	state=controller.get_snapshot()
	state.main_breaker_on=false
	controller._broadcast_snapshot(state)
	await create_timer(0.2).timeout
	check(not door.open,"power loss closes intact door")
	player.crowbar_uses=2
	var interaction = door.blocker.get_parent().get_node("ManualInteraction")
	player.crowbar_uses = 0
	check(interaction.get_interaction_prompt().is_empty(), "closed door without crowbar has no prompt")
	player.crowbar_uses = 2
	check(interaction.get_interaction_prompt() == "Вскрыть монтировкой", "pry prompt does not disclose usage count")
	interaction.network_interact(player.owner_peer_id,player)
	await create_timer(1.5).timeout
	check(manager.is_door_pried(door) and door.open and player.crowbar_uses==1,"pry consumes one use and opens")
	player.crowbar_uses=0
	interaction.network_interact(player.owner_peer_id,player)
	await create_timer(0.2).timeout
	check(not door.open,"pried door closes by hand without tool")
	interaction.network_interact(player.owner_peer_id,player)
	await create_timer(0.2).timeout
	check(door.open and player.crowbar_uses==0,"pried door reopens by hand without tool")
	check(interaction.get_interaction_prompt() == "Закрыть вручную", "pried open door offers a useful manual action")
	check(not interaction.get_child(0).disabled,"open door remains interactable")
	state=controller.get_snapshot()
	state.main_breaker_on=true
	controller._broadcast_snapshot(state)
	interaction.network_interact(player.owner_peer_id,player)
	await create_timer(0.2).timeout
	check(not door.open,"broken door remains manual with restored power")
	world.queue_free()
	await process_frame
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
