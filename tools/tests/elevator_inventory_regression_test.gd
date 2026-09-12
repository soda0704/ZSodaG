extends SceneTree

var failed := false

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://elevator_inventory_regression.cfg")
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	print("ELEVATOR_INVENTORY: ", "PASS " if condition else "FAIL ", message)
	failed = failed or not condition

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player = world.get_node("Players/1")
	player.set_physics_process(false)
	var state: BaseGameplayController = world.get_node("V3Level/BaseGameplayController")
	var elevator = world.get_node("V3Level/Elevator_Functional_Blockout")
	var items = world.get_node("Gameplay/WorldItems")
	player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.65})
	for i in 6:
		player.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 20.0})
		check(player._has_flashlight and not player._flashlight_enabled, "Can pockets but never removes hand flashlight")
		player.drop_current_item_authoritative()
		check(player.toggle_flashlight_authoritative(), "F draws lamp after freeing hands")
		await create_timer(0.04 if i % 2 == 0 else 0.35).timeout
	await create_timer(0.4).timeout
	check(player.flashlight.visible and player.flashlight.is_available and player.flashlight.is_enabled, "Quick stow/draw leaves the flashlight visible and working")
	player.pickup_world_item_authoritative(&"m4a1", {"rounds": 5})
	player.pickup_world_item_authoritative(&"tape", {})
	player.perform_inventory_action_authoritative(&"mount_light")
	player._battery_charge = 0.0
	player._flashlight_enabled = false
	player.pickup_world_item_authoritative(&"battery", {"charge_amount": 1.0})
	player.pickup_world_item_authoritative(&"rifle_magazine", {"rounds": 30})
	player.request_reload_or_battery()
	player.request_reload_or_battery()
	await create_timer(1.2).timeout
	check(player._battery_charge > 0.99 and player.weapon.rounds == 5 and player.weapon.rifle_magazines.size() == 1, "R prioritizes one battery without using ammunition")
	player.request_reload_or_battery()
	await create_timer(2.3).timeout
	check(player.weapon.rounds == 30, "Next R reloads magazine")
	var console := root.get_node("DeveloperConsole")
	check("20" in console.execute("/fuel full") and player.fuel_liters == 20.0, "Console gives full can")
	check("0 / 20" in console.execute("/fuel empty") and player.fuel_liters == 0.0, "Console gives empty can")
	console.execute("/flashlight")
	check(player._has_flashlight, "Console gives flashlight")
	state.deliver_fuel_authoritative(1)
	var saved: Dictionary = world.capture_inventory_checkpoint()
	var cans := 0
	for item: Dictionary in saved.pickups:
		if item.item_type == &"fuel_can":
			cans += 1
	check(cans >= 6, "Refueling no longer removes world cans from checkpoint")
	var cargo: Array[Node3D] = []
	for id in [&"flashlight", &"fuel_can", &"rifle_magazine"]:
		var pose := Transform3D(Basis.IDENTITY, elevator.cabin.to_global(Vector3(cargo.size() - 1.0, 0.8, 0)))
		world.spawn_world_item(id, items.global_transform.affine_inverse() * pose, {})
		cargo.append(items.get_child(-1))
	await create_timer(1.2).timeout
	for item in cargo:
		check(item._cargo_cabin == elevator.cabin, "Cargo settles in cabin reference frame")
	var positions: Array[Vector3] = []
	for item in cargo:
		positions.append(elevator.cabin.to_local(item.global_position))
	for destination in [-18.0, 0.0, -36.0, 0.0]:
		elevator._begin_cabin_motion(destination, 1.0, 100)
		await create_timer(1.15).timeout
		for i in cargo.size():
			check(elevator.cabin.to_local(cargo[i].global_position).distance_to(positions[i]) < 0.015, "Cargo stays above floor on ascent/descent and stops")
	var surface := elevator.cabin as Node3D
	var local_hit := Vector3(2.7, 1.5, 0)
	player.weapon._impact(surface.to_global(local_hit), Vector3.LEFT, surface.get_path(), local_hit)
	var mark = get_nodes_in_group("weapon_impacts").back()
	surface.position.y -= 1.0
	check(mark.get_parent() == surface and mark.position.is_equal_approx(local_hit), "Bullet impact follows hit cabin surface")
	var wall := StaticBody3D.new()
	world.add_child(wall)
	player.weapon._impact(wall.global_position, Vector3.UP, wall.get_path(), Vector3.ZERO)
	var wall_mark = get_nodes_in_group("weapon_impacts").back()
	var before: Vector3 = wall_mark.global_position
	surface.position.y += 1.0
	check(wall_mark.global_position.is_equal_approx(before), "Stationary wall impact does not follow elevator")
	var recovered = cargo[0]
	recovered.release_elevator_cargo()
	recovered._cargo_cooldown = 0.0
	recovered.global_position = surface.to_global(Vector3(0, -0.3, 0))
	await create_timer(0.15).timeout
	check(surface.to_local(recovered.global_position).y > 0.05, "Slightly sunken cabin item is recovered above floor")
	player.perform_inventory_action_authoritative(&"drop_flashlight")
	player.teleport_authoritative(recovered.global_position + Vector3.UP, 0)
	recovered.network_interact(1, player)
	check(player._has_flashlight, "Recovered cargo remains collectible")
	BaseGameplayController.delete_progress_save()
	print("ELEVATOR_INVENTORY_RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
