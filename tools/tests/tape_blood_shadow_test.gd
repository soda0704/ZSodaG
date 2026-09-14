extends SceneTree

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://tape_blood_shadow_test.cfg")
	run.call_deferred()

func shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join(file))

func run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var player = current_scene.get_node("Players/1")
	player.set_physics_process(false)
	player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 1.0})
	player.pickup_world_item_authoritative(&"m4a1", {})
	player.pickup_world_item_authoritative(&"tape", {})
	player.perform_inventory_action_authoritative(&"mount_light")
	var room = current_scene.get_node("V3Level/DeveloperTestRoom")
	player.teleport_authoritative(room.to_global(Vector3(0, 0.1, -9)), 0)
	for light in room.find_children("*", "Light3D", true, false):
		light.visible = false
	await create_timer(0.8).timeout
	var failed: bool = (player.weapon._mounted_beam.shadow_caster_mask & (1 << 19)) != 0
	if DisplayServer.get_name() != "headless":
		await shot("NorthernLab-FixedMountShadow.png")
		player.weapon._pose.hide()
		var preview := Camera3D.new()
		current_scene.add_child(preview)
		var tape := preload("res://scripts/gameplay/tool_models.gd").build(&"tape")
		current_scene.add_child(tape)
		tape.global_position = room.to_global(Vector3(0, 1, 0))
		preview.global_position = tape.global_position + Vector3(0.25, 0.28, 0.32)
		preview.look_at(tape.global_position)
		preview.current = true
		var light := OmniLight3D.new()
		current_scene.add_child(light)
		light.global_position = tape.global_position + Vector3(0.2, 0.5, 0.2)
		light.light_energy = 2
		await create_timer(0.2).timeout
		await shot("NorthernLab-TapeRoll.png")
		tape.hide()
		preview.global_position = room.to_global(Vector3(0, 2.3, 3))
		preview.look_at(room.to_global(Vector3(0, 0.6, 0)))
		preload("res://scripts/gameplay/blood_effect.gd").spawn(player, room.to_global(Vector3(0, 1, 0)))
		await create_timer(0.18).timeout
		await shot("NorthernLab-BloodBurst.png")
	print("TAPE_BLOOD_SHADOW_TEST: ", "FAIL" if failed else "PASS")
	BaseGameplayController.delete_progress_save()
	quit(1 if failed else 0)
