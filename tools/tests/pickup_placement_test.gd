extends SceneTree

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://placement_regression.cfg")
	run.call_deferred()

func run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	await create_timer(8).timeout
	var failed := false
	var found := {}
	for item in current_scene.get_node("Gameplay/WorldItems").get_children():
		print("PLACEMENT ", item.item_type, " ", item.global_position)
		for loot: Dictionary in BaseBlockoutRuntime.DISCOVERABLE_LOOT:
			if item.item_type == loot.type and item.global_position.distance_to(loot.position) < 0.5:
				found[item.item_type] = true
	failed = found.size() != 4
	var player = current_scene.get_node("Players/1")
	player.weapon.pistol_ammo = 235
	for item in current_scene.get_node("Gameplay/WorldItems").get_children():
		if item.item_type == &"pistol_ammo":
			player.teleport_authoritative(item.global_position + Vector3(0, 0, 1), 0)
			item.network_interact(1, player)
			failed = failed or player.weapon.pistol_ammo != 240 or int(item.item_state.amount) != 7 or item.is_queued_for_deletion()
			break
	failed = failed or current_scene.has_node("Gameplay/Geometry") or current_scene.has_node("Helicopter")
	if OS.get_cmdline_user_args().has("visual"):
		root.get_node("DeveloperConsole").set_open(true)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Console.png"))
		root.get_node("DeveloperConsole").set_open(false)
		var bunk = get_first_node_in_group("end_day_bunks")
		bunk.bed_pivot.rotation.x = 0.0
		player._receive_bunk_sleep_state(true, bunk.sleep_pose.global_transform)
		for mesh in player.body_animator.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var preview := Camera3D.new()
		current_scene.add_child(preview)
		preview.global_position = bunk.to_global(Vector3(2.5, 2.2, 3.5))
		preview.look_at(bunk.to_global(Vector3(0, 0.2, 1)))
		preview.current = true
		var light := OmniLight3D.new()
		current_scene.add_child(light)
		light.global_position = bunk.to_global(Vector3(0, 2, 2))
		light.light_energy = 3
		light.omni_range = 7
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Bunk.png"))
	print("PLACEMENT_AMMO_RESULT: ", "FAIL" if failed else "PASS")
	BaseGameplayController.delete_progress_save()
	quit(1 if failed else 0)
