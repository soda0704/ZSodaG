extends SceneTree

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://monster_spawn_stress_test.cfg")
	_run.call_deferred()

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	await current_scene._enter_v3_level()
	var console = root.get_node("DeveloperConsole")
	var started := Time.get_ticks_msec()
	print("MONSTER_STRESS: ", console.execute("/spawn smily 1000"))
	while get_nodes_in_group("debug_spawned_monsters").size() < 1000 and Time.get_ticks_msec() - started < 60000:
		await process_frame
	var count := get_nodes_in_group("debug_spawned_monsters").size()
	print("MONSTER_STRESS: spawned=", count, " ms=", Time.get_ticks_msec() - started)
	var result: String = console.execute("/despawn")
	await process_frame
	var remaining := get_nodes_in_group("debug_spawned_monsters").size()
	print("MONSTER_STRESS: ", result, " remaining=", remaining)
	BaseGameplayController.delete_progress_save()
	quit(0 if count == 1000 and remaining == 0 else 1)
