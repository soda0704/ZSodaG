extends SceneTree

const SAVE := "user://equipment_inventory_test.cfg"
var failed := false

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, SAVE)
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("EQUIPMENT_TEST: " + message)

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player: Node3D = world.get_node("Players/1")
	player.set_physics_process(false)
	var items := world.get_node("Gameplay/WorldItems")
	check(player.pickup_world_item_authoritative(&"battery", {"charge_amount": 1.0}), "Collect battery without a flashlight")
	check(player.pickup_world_item_authoritative(&"battery", {"charge_amount": 0.5}), "Stack another battery")
	check(player.get_inventory_snapshot().spare_batteries.size() == 2, "Two spare cells")
	check(player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.2}), "Acquire flashlight")
	var item_count := items.get_child_count()
	check(player.pickup_world_item_authoritative(&"fuel_can", {}), "Take bulky item")
	check(items.get_child_count() == item_count, "Taking fuel must not drop the flashlight")
	check(player.get_inventory_snapshot().has_flashlight and not player.get_inventory_snapshot().flashlight_enabled, "Pocket flashlight remains owned and off")
	check(not player.toggle_flashlight_authoritative(), "Occupied hands must not eject fuel on F")
	check(player.consume_held_item_authoritative(&"fuel_can"), "Deliver bulky item")
	check(player.toggle_flashlight_authoritative(), "F draws flashlight")
	check(player.get_inventory_snapshot().flashlight_enabled, "Drawn flashlight lights")
	check(player.toggle_flashlight_authoritative(), "F stows flashlight")
	check(player.get_inventory_snapshot().has_flashlight and player.get_inventory_snapshot().held_item == &"", "Stow is not discard")
	var old_charge: float = player.get_inventory_snapshot().battery_charge
	player.update_authoritative_flashlight_battery(10.0)
	check(is_equal_approx(old_charge, player.get_inventory_snapshot().battery_charge), "Pocket light does not drain")
	check(player.perform_inventory_action_authoritative(&"replace_battery"), "Replace from inventory")
	check(player.get_inventory_snapshot().battery_charge == 1.0 and player.get_inventory_snapshot().spare_batteries.size() == 1, "Replacement consumes exactly one cell")
	check(not player.perform_inventory_action_authoritative(&"replace_battery"), "Full light does not waste a cell")
	check(player.perform_inventory_action_authoritative(&"drop_battery"), "Drop one spare cell")
	check(player.get_inventory_snapshot().spare_batteries.is_empty(), "Cell removed from pocket")
	check(items.get_child_count() == item_count + 1, "Dropped cell exists in world")
	check(player.perform_inventory_action_authoritative(&"drop_flashlight"), "Explicit discard works for pocket flashlight")
	check(not player.get_inventory_snapshot().has_flashlight, "Discard clears ownership")
	check(not player.perform_inventory_action_authoritative(&"drop_flashlight"), "No duplicate drop")
	player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.0})
	player.toggle_flashlight_authoritative()
	player.toggle_flashlight_authoritative()
	check(player.get_inventory_snapshot().held_item == &"flashlight", "Empty flashlight can be drawn and stowed")
	player.pickup_world_item_authoritative(&"battery", {"charge_amount": 1.0})
	player.perform_inventory_action_authoritative(&"replace_battery")
	check(player.get_inventory_snapshot().flashlight_enabled, "Replacing empty drawn flashlight restores light")
	var before: Dictionary = player.get_inventory_snapshot()
	player.apply_inventory_snapshot({"revision": int(before.revision) - 1, "has_flashlight": false})
	check(player.get_inventory_snapshot().has_flashlight, "Stale snapshots cannot erase a newer pickup")
	var input := root.get_node("SteamInput")
	var square := InputEventJoypadButton.new()
	square.button_index = JOY_BUTTON_X
	square.pressed = true
	input._input(square)
	check(input.using_controller and input.get_action_hint(&"interact") == "[□]", "DualSense square prompt")
	var keyboard := InputEventKey.new()
	keyboard.physical_keycode = KEY_E
	keyboard.pressed = true
	input._input(keyboard)
	check(not input.using_controller and input.get_action_hint(&"interact") == "[E]", "Keyboard prompt restores")
	input._input(square)
	var l3 := InputEventJoypadButton.new()
	l3.button_index = JOY_BUTTON_LEFT_STICK
	l3.pressed = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	check(l3.is_action_pressed("sprint"), "L3 maps to sprint")
	# Headless DisplayServer cannot capture the mouse. Exercise the actual
	# gameplay input guard in the graphical run, never bypass it in production.
	if DisplayServer.get_name() != "headless":
		player._unhandled_input(l3)
		Input.action_press("move_forward")
		player.collect_local_input()
		check(player.get("_input_sprint"), "L3 toggles sprint without holding stick button")
		Input.action_release("move_forward")
		player.collect_local_input()
		check(not player.get("_input_sprint"), "Stopping resets sprint")
	var state: BaseGameplayController = world.get_node("V3Level/BaseGameplayController")
	state._apply_snapshot({"day_index": 2, "fuel_delivered": true, "main_breaker_on": true, "quest_stage": 3})
	var journal := root.get_node("QuestJournal")
	journal.open_journal()
	check(journal.inventory_label.text.contains("Ключ шифрования ×1"), "Journal displays quest items")
	check(journal.inventory_label.text.contains("Фонарик: 100%"), "Journal displays equipment")
	check(journal.controls_label.text.contains("L3"), "Journal explains sprint")
	if "visual" in OS.get_cmdline_user_args():
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-InventoryJournal.png"))
	journal.force_close()
	await test_elevator(world, player)
	player.pickup_world_item_authoritative(&"battery", {"charge_amount": 0.75})
	world.save_inventory_checkpoint()
	var checkpoint: Dictionary = world.capture_inventory_checkpoint()
	await menu.return_to_main_menu()
	await create_timer(0.3).timeout
	await menu.start_standalone_flow(true)
	world = current_scene
	player = world.get_node("Players/1")
	check(player.get_inventory_snapshot().has_flashlight, "Continue retains personal flashlight")
	check(not player.get_inventory_snapshot().flashlight_enabled, "Continue starts light switched off")
	check(player.get_inventory_snapshot().spare_batteries.size() == 1, "Continue retains exact spare cell count")
	check(world.get_node("Gameplay/WorldItems").get_child_count() == checkpoint.pickups.size(), "Continue restores world equipment without supply duplication")
	world.free()
	BaseGameplayController.delete_progress_save()
	print("EQUIPMENT_INVENTORY_TEST: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func test_elevator(world: Node, player: Node3D) -> void:
	var elevator: Node3D = world.get_node("V3Level/Elevator_Functional_Blockout")
	var cabin: Node3D = elevator.get_node("CabinMoving")
	player.global_position = cabin.global_position + Vector3(0, 0.06, 0)
	player.get_node("Head").rotation.x = deg_to_rad(-85.0)
	var drop: Transform3D = player.get_held_item_drop_transform()
	check(drop.origin.y > cabin.global_position.y + 0.3, "Downward drop is above elevator floor")
	var drops: Array[Node3D] = []
	for kind in [&"flashlight", &"battery", &"fuel_can"]:
		world.spawn_dropped_item(kind, {"item_state": {}, "transform": Transform3D(Basis.IDENTITY, cabin.global_position + Vector3(drops.size() * 0.4, 1.4, 0)), "linear_velocity": Vector3(0, -15, 0)})
		drops.append(world.get_node("Gameplay/WorldItems").get_child(-1))
	await create_timer(1.0).timeout
	for pickup in drops:
		check(pickup.global_position.y > cabin.global_position.y - 0.1, "Dropped %s remains on elevator floor" % pickup.item_type)
	elevator.require_all_connected_players = false
	elevator.door_animation_duration = 0.05
	elevator.cabin_door.animation_duration = 0.05
	elevator.set_powered(true)
	elevator.set_day(2)
	check(elevator.request_call(1), "Elevator starts descent")
	await create_timer(9.0).timeout
	for pickup in drops:
		check(pickup.global_position.y > cabin.global_position.y - 0.12 and pickup.global_position.y < cabin.global_position.y + 0.7, "Cargo %s arrives on floor -1" % pickup.item_type)
	check(elevator.request_call(0), "Elevator starts ascent")
	await create_timer(9.0).timeout
	for pickup in drops:
		check(pickup.global_position.y > cabin.global_position.y - 0.12 and pickup.global_position.y < cabin.global_position.y + 0.7, "Cargo %s returns to surface" % pickup.item_type)
