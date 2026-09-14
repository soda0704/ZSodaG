extends SceneTree

var failed := false

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://maintenance_tools_test.cfg")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print("MAINTENANCE_TEST: ", "PASS " if condition else "FAIL ", message)
	if not condition:
		failed = true

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player = world.get_node("Players/1")
	player.set_physics_process(false)
	var state: BaseGameplayController = world.get_node("V3Level/BaseGameplayController")
	var items := world.get_node("Gameplay/WorldItems")
	check(world.has_node("V3Level") and not world.has_node("Gameplay/GeneratorPanel") and not world.has_node("Gameplay/V3ExitTerminal"), "Normal launch skips and removes legacy generator room")
	var developer_room := world.get_node("V3Level/DeveloperTestRoom") as DeveloperTestRoom
	check(developer_room != null and developer_room.get_child_count() >= 13, "Large lit developer room exists only off-map")
	var original_pose: Transform3D = player.global_transform
	check("Телепорт" in root.get_node("DeveloperConsole").execute("/testroom") and developer_room.contains(player.global_position), "Console enters developer room")
	if OS.get_cmdline_user_args().has("visual"):
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-DeveloperRoom.png"))
	root.get_node("DeveloperConsole").execute("/testroom")
	check(player.global_position.distance_to(original_pose.origin) < 0.05, "Second command returns to exact previous position")
	var tools_count := 0
	var placed := {&"kitchen_knife": false, &"pistol": false, &"pistol_ammo": false, &"crowbar": false}
	for item in items.get_children():
		if item.item_type in [&"tape", &"crowbar"]:
			tools_count += 1
		if placed.has(item.item_type):
			var expected := Vector3.ZERO
			for loot: Dictionary in BaseBlockoutRuntime.DISCOVERABLE_LOOT:
				if loot.type == item.item_type:
					expected = loot.position
			placed[item.item_type] = bool(placed[item.item_type]) or item.global_position.distance_to(expected) < 1.0
	check(tools_count == 3, "Two tape rolls and one crowbar spawn")
	check(
		placed.values().all(func(value): return value),
		"Knife, pistol, ammo and crowbar use discoverable authored placements: %s" % placed
	)
	player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.8})
	player.pickup_world_item_authoritative(&"pistol", {"rounds": 12})
	check(not player.perform_inventory_action_authoritative(&"mount_light"), "Mount requires tape")
	player.pickup_world_item_authoritative(&"tape", {})
	check(player.perform_inventory_action_authoritative(&"mount_light"), "Tape mounts flashlight")
	check(player.tape_count == 0 and player.weapon_light_mounted and player._flashlight_enabled, "One roll consumed, mounted lamp on")
	if OS.get_cmdline_user_args().has("visual"):
		var journal := root.get_node("QuestJournal")
		journal.open_journal()
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-MountJournal.png"))
		journal.force_close()
	check(not player.perform_inventory_action_authoritative(&"mount_light"), "Repeated mount cannot consume or duplicate")
	player.toggle_flashlight_authoritative()
	check(not player._flashlight_enabled and player.has_held_item(&"pistol"), "F switches lamp without stowing gun")
	player.toggle_flashlight_authoritative()
	player.update_authoritative_flashlight_battery(5.0)
	check(player._battery_charge < 0.8, "Mounted light consumes battery")
	var gun_state: Dictionary = player.get_held_item_state()
	player.drop_current_item_authoritative()
	check(not player._has_flashlight and not player.weapon_light_mounted, "Dropped gun carries the lamp, no duplicate in pocket")
	player.pickup_world_item_authoritative(&"pistol", gun_state)
	check(player.weapon_light_mounted and is_equal_approx(player._battery_charge, gun_state.mounted_charge), "Pickup preserves attachment and charge")
	check(player.perform_inventory_action_authoritative(&"detach_light"), "Lamp can be detached without losing it")
	check(player._has_flashlight and player.tape_count == 0, "Detaching retains lamp but does not refund used tape")
	player.pickup_world_item_authoritative(&"crowbar", {"uses": 3})
	var doors = world.get_node("V3Level/Floor_0_Base_Blockout/AutomaticDoors")
	await create_timer(0.9).timeout
	var opened := 0
	for door: Dictionary in doors._doors:
		if door.open or door.locked:
			continue
		player.teleport_authoritative(door.marker.global_position + Vector3(0, 0.1, 1), 0)
		door.blocker.get_parent().network_interact(1, player)
		await create_timer(2.1).timeout
		check(door.open and door.blocker.disabled, "Pry opens and clears closed doorway")
		opened += 1
		if opened == 3:
			break
	check(opened == 3 and player.crowbar_uses == 0, "Crowbar breaks after three doors")
	for door: Dictionary in doors._doors:
		if door.open or door.locked:
			continue
		player.teleport_authoritative(door.marker.global_position + Vector3(0, 0.1, 1), 0)
		door.blocker.get_parent().network_interact(1, player)
		await create_timer(1.3).timeout
		check(not door.open and player.crowbar_uses == 0, "Broken crowbar cannot open a fourth door")
		break
	check(state.maintenance.get("pried_doors", []).size() == 3, "Pried doors stored in shared state")
	state.save_progress_authoritative()
	check(state.load_saved_snapshot().maintenance.pried_doors.size() == 3, "Pried doors survive save")
	state.deliver_fuel_authoritative(1)
	state.activate_main_breaker_authoritative(1)
	state.set_end_day_ready_authoritative(1, true)
	state.set_peer_sleeping_authoritative(1, true)
	await create_timer(1.4).timeout
	check(state.day_index == 2 and state.maintenance.get("wires_required", false) and not state.main_breaker_on, "First night trips wiring and power")
	check(state._siren.playing, "Outage sounds siren")
	check(not state.activate_main_breaker_authoritative(1), "Cannot bypass broken wiring")
	var breaker = get_first_node_in_group("main_breaker")
	player.teleport_authoritative(breaker.global_position + Vector3(0, 0, 1), 0)
	state.open_wiring_ui()
	await process_frame
	var panel = get_first_node_in_group("wiring_ui")
	check(panel != null and panel.left_buttons.size() == 4, "Wire panel opens with four circuits")
	if OS.get_cmdline_user_args().has("visual"):
		root.size = Vector2i(1280, 800)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Wiring.png"))
	var order: Array = state.maintenance.wire_order
	check(not state.connect_wire_authoritative(1, 0, (int(order[0]) + 1) % 4), "Wrong wire rejected")
	check(not state.connect_wire_authoritative(99, 0, int(order[0])), "Unknown peer rejected")
	for i in 4:
		panel._select(i)
		panel._connect(order[i])
	if OS.get_cmdline_user_args().has("visual"):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-WiringComplete.png"))
	check(not state.maintenance.wires_required and not state.main_breaker_on and state._siren.playing, "Repair still requires manual restart")
	panel._close()
	check(state.activate_main_breaker_authoritative(1), "Breaker starts repaired circuits")
	check(not state._siren.playing, "Restored power silences alarm")
	state._process(3000.0)
	check(not state.main_breaker_on and state._siren.playing, "Fuel exhaustion trips alarm again")
	state.refill_authoritative(1, 10.0)
	check(not state.main_breaker_on, "Refueling does not automatically restart power")
	check(state.activate_main_breaker_authoritative(1), "Manual restart after refueling")
	BaseGameplayController.delete_progress_save()
	print("MAINTENANCE_TEST_RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
