extends SceneTree

var failed := false

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://door_merge_test.cfg")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	failed = failed or not value
	print("DOOR_MERGE_TEST: ", "PASS " if value else "FAIL ", message)

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	await current_scene._enter_v3_level()
	var level := current_scene.get_node("V3Level")
	var door := level.get_node_or_null("Floor_0_Base_Blockout/Doors/living_hermetic_door")
	check(door != null, "New living door remains in its scene")
	if door != null:
		check(door.position.is_equal_approx(Vector3(10, 0, 0)), "Door placement preserved")
		for part in ["LeftLeaf", "RightLeaf", "Frame", "AccessPanelInteractionSocket", "BackAccessPanelInteractionSocket", "CompactAccessPanel", "BackCompactAccessPanel"]:
			check(door.find_child(part, true, false) != null, "Door part: " + part)
		check(not door.find_children("*", "MeshInstance3D", true, false).is_empty(), "Imported door has visible geometry")
	check(level.has_node("Floor_0_Base_Blockout/Doors/West_Hub_Decon_Door_Visual_Prototype"), "Original western door restored")
	check(level.has_node("ContainmentEncounter") and root.has_node("DeveloperConsole"), "Encounter and console retained")
	if OS.get_cmdline_user_args().has("visual"):
		var player = current_scene.get_node("Players/1")
		player.set_physics_process(false)
		player.survival.set_physics_process(false)
		player.teleport_authoritative(Vector3(6, 0.2, 0), -PI / 2)
		player.head.look_at(Vector3(10, 1.4, 0))
		var light := OmniLight3D.new()
		player.head.add_child(light)
		light.light_energy = 2
		light.omni_range = 8
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Merged-Door.png"))
	BaseGameplayController.delete_progress_save()
	print("DOOR_MERGE_TEST_RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
