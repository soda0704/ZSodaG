extends SceneTree


func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://day_two_visual_test.cfg")
	_run.call_deferred()


func _run() -> void:
	BaseGameplayController.delete_progress_save()
	var level: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	level.set("network_runtime_managed", true)
	root.add_child(level)
	var state := level.get_node("BaseGameplayController") as BaseGameplayController
	state._broadcast_snapshot({"day_index": 2, "phase": 2, "fuel_delivered": true, "main_breaker_on": true, "quest_stage": 2})
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	for station_name in ["DayTwoTaskTerminal", "DayTwoKeyTerminal"]:
		var station := level.get_node(station_name) as Node3D
		camera.global_position = station.global_position + station.global_basis.z * 2.2 + Vector3.UP * 0.2
		camera.look_at(station.global_position + Vector3.UP * 0.15)
		await create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		var path := OS.get_environment("TEMP").path_join("NorthernLab-" + station_name + ".png")
		root.get_texture().get_image().save_png(path)
		print("PREVIEW: " + path)
	level.free()
	BaseGameplayController.delete_progress_save()
	quit()
