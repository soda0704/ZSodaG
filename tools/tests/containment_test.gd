extends SceneTree

var failed := false
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://containment_test.cfg")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	print("CONTAINMENT_TEST: ", "PASS " if value else "FAIL ", message)
	failed = failed or not value

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player = world.get_node("Players/1")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	var encounter = world.get_node("V3Level/ContainmentEncounter")
	var state = encounter.state
	var snapshot: Dictionary = state.get_snapshot()
	snapshot.day_index = 3
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	state._broadcast_snapshot(snapshot)
	for step in 100:
		if encounter.navigation_ready:
			break
		await create_timer(0.1).timeout
	check(encounter.navigation_ready, "Navigation mesh baked")
	for index in 3:
		var enemy = encounter.get_node("Monster%d" % index)
		var nearest: Vector3 = NavigationServer3D.map_get_closest_point(enemy.get_world_3d().navigation_map, enemy.global_position)
		check(nearest.distance_to(enemy.global_position) < 1.0, "Monster %d on walkable floor" % index)
	player.teleport_authoritative(Vector3(-15, -35.9, -5), 0)
	await create_timer(0.4).timeout
	check(state.containment.get("level2", false), "Level 2 survey")
	check(world.get_node("V3Level/Elevator_Functional_Blockout").unlocked_floor_index == 3, "Survey unlocks level 3")
	player.teleport_authoritative(Vector3(-18, -53.9, -7.5), 0)
	await create_timer(0.4).timeout
	check(state.containment.get("level3", false), "Level 3 survey")
	var monster = encounter.get_node("Monster0")
	player.teleport_authoritative(monster.global_position + Vector3(0, 0, 4), 0)
	player.head.look_at(monster.global_position + Vector3.UP)
	if OS.get_cmdline_user_args().has("visual"):
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Containment.png"))
	player.pickup_world_item_authoritative(&"m4a1", {})
	await physics_frame
	check(player.weapon.perform_action(&"fire"), "Weapon fires")
	check(encounter.get_monster_health(0) < 120, "Weapon ray damages monster")
	var before: Vector3 = monster.global_position
	await create_timer(1.0).timeout
	check(monster.global_position.distance_to(before) > 0.3, "Monster pursues player")
	player.teleport_authoritative(monster.global_position + Vector3(0, 0, 1.3), 0)
	var old_health: float = player.survival.health
	await create_timer(2.0).timeout
	check(player.survival.health < old_health, "Monster attacks player")
	for index in 3:
		encounter.damage_monster(index, 1000)
	check(state.containment.get("fault", false), "Last kill starts lighting fault")
	var lighting = world.get_node("V3Level/BasePowerLightingController")
	check(lighting._containment_lights.size() >= 14, "Level 3 lights bound")
	check(not lighting._lamp_materials.is_empty(), "Emissive lamp surfaces bound")
	lighting._fault_time = 0
	lighting._process(0)
	var lamp: Light3D = lighting._containment_lights.keys()[0]
	var dim := lamp.light_energy
	lighting._fault_time = 1
	lighting._process(0)
	check(lamp.light_energy > dim * 5, "Level 3 visibly flickers")
	await create_timer(7.0).timeout
	var poses := {}
	for index in 3:
		var enemy = encounter.get_node("Monster%d" % index)
		check(enemy.corpse != null and enemy.corpse.freeze, "Corpse %d settles physically" % index)
		poses[str(index)] = enemy.global_transform
		if OS.get_cmdline_user_args().has("visual"):
			player.teleport_authoritative(enemy.global_position + Vector3(0, 1.2, 3), 0)
			player.head.look_at(enemy.global_position + Vector3.UP * 0.3)
			await create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("Corpse-%d.png" % index))
	state.save_progress_authoritative()
	var saved: Dictionary = state.load_saved_snapshot()
	for index in 3:
		check(saved.containment.bodies[str(index)].transform.is_equal_approx(poses[str(index)]), "Corpse %d exact pose saved" % index)
	var parent = encounter.get_parent()
	encounter.free()
	state._apply_snapshot(saved)
	encounter = load("res://scripts/gameplay/containment_encounter.gd").new()
	encounter.name = "ContainmentEncounter"
	parent.add_child(encounter)
	await create_timer(0.3).timeout
	for index in 3:
		check(encounter.get_node("Monster%d" % index).global_transform.is_equal_approx(poses[str(index)]), "Corpse %d exact pose restored" % index)
	check(encounter.cycle_breaker(1), "Breaker switches off")
	check(not state.main_breaker_on and state.containment.get("fault", false), "Fault remains while off")
	check(encounter.cycle_breaker(1), "Breaker switches on")
	check(state.main_breaker_on and state.containment.get("resolved", false) and not state.containment.get("fault", false), "Power restored")
	check(state.load_saved_snapshot().get("containment", {}).get("resolved", false), "Encounter saved")
	var console = root.get_node("DeveloperConsole")
	check("/across" in console.execute("/help"), "Console help")
	console.execute("/fly")
	check(player.debug_fly and not player.debug_across, "Fly command")
	player.teleport_authoritative(Vector3(0, 10, 0), 0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Input.action_press("move_forward")
	player._input_pitch = 0.0
	var flight_start: Vector3 = player.global_position
	player.set_physics_process(true)
	await create_timer(0.4).timeout
	player.set_physics_process(false)
	Input.action_release("move_forward")
	if DisplayServer.get_name() != "headless":
		check(player.global_position.distance_to(flight_start) > 1.0 and is_equal_approx(player.global_position.y, flight_start.y), "Flight movement without gravity")
	else:
		print("CONTAINMENT_TEST: SKIP captured mouse flight input on headless display (covered by graphical test)")
	console.execute("/across")
	check(player.debug_fly and player.debug_across, "Across command")
	console.execute("/across")
	check(not player.debug_fly and not player.debug_across, "Across toggle off")
	var toggle := InputEventKey.new()
	toggle.pressed = true
	toggle.physical_keycode = KEY_QUOTELEFT
	console._input(toggle)
	check(console.opened and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Tilde opens console")
	if OS.get_cmdline_user_args().has("visual"):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Console.png"))
	toggle.physical_keycode = 0
	toggle.unicode = 1105
	console._input(toggle)
	check(not console.opened and Input.mouse_mode == console.previous_mouse, "Russian yo closes console and restores mouse")
	console.execute("/god")
	var hp: float = player.survival.health
	player.survival.damage(10, "test")
	check(player.survival.health == hp, "God command")
	console.execute("/god")
	console.execute("/monsters reset")
	await physics_frame
	check(encounter.get_monster_health(0) == 120 and encounter.get_node("Monster0").corpse == null, "Console resets encounter")
	var fault_data: Dictionary = state.containment.duplicate(true)
	fault_data.fault = true
	fault_data.resolved = false
	encounter._commit(fault_data)
	console.execute("/monsters reset")
	check(state.containment.get("fault", false), "Monster reset preserves lighting fault")
	var sight_monster = encounter.get_node("Monster0")
	var sight_player = player
	var day_two: Dictionary = state.get_snapshot()
	day_two.day_index = 2
	state._broadcast_snapshot(day_two)
	sight_monster.global_position = Vector3(0, 10, -5)
	sight_monster.rotation.y = 0
	sight_monster._alert_target = null
	sight_monster._awareness = 0
	sight_player.teleport_authoritative(Vector3(0, 10, 0), 0)
	check(sight_monster._find_target(0.1) == null, "Monster does not see behind itself")
	sight_monster.rotation.y = PI
	check(sight_monster._find_target(0.1) == sight_player, "Monster sees player in view cone on day 2")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(3, 3, 0.4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.global_position = Vector3(0, 11, -2.5)
	await physics_frame
	sight_monster._alert_target = null
	sight_monster._awareness = 0
	check(sight_monster._find_target(0.1) == null, "Wall blocks monster line of sight")
	wall.queue_free()
	await physics_frame
	var spawn_result: String = console.execute("/spawn smily 30")
	for frame in 4:
		await process_frame
	check("30" in spawn_result and get_nodes_in_group("debug_spawned_monsters").size() == 30, "Console spawns requested count on any day")
	var spawned = get_nodes_in_group("debug_spawned_monsters")[0]
	spawned.apply_weapon_damage(200)
	await physics_frame
	check(spawned.health <= 0, "Spawned monster can be killed")
	check("30" in console.execute("/despawn"), "Console clears spawned monsters")
	await process_frame
	check(get_nodes_in_group("debug_spawned_monsters").is_empty(), "Spawned monsters removed")
	var spawn_bar = console.panel.find_child("SpawnBar", true, false)
	for button_test in [["SpawnTail", "the_monster"], ["SpawnSlasher", "slasher"], ["SpawnSmily", "smily"]]:
		spawn_bar.get_node(button_test[0]).pressed.emit()
		await process_frame
		var button_spawned = get_nodes_in_group("debug_spawned_monsters")
		check(button_spawned.size() == 1 and button_spawned[0].model_id == button_test[1], "Individual spawn button: " + button_test[0])
		console.execute("/despawn")
		await process_frame
	BaseGameplayController.delete_progress_save()
	print("CONTAINMENT_TEST_RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
