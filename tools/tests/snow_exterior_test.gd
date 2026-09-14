extends SceneTree

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://snow_exterior_test.cfg")
	run.call_deferred()

func run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var exterior := current_scene.get_node("V3Level/SnowExterior")
	var terrain := exterior.get_node("Terrain3D") as Terrain3D
	var player = current_scene.get_node("Players/1")
	player.set_physics_process(false)
	var camera := Camera3D.new()
	current_scene.add_child(camera)
	camera.global_position = Vector3(-110, 95, 145)
	camera.look_at(Vector3(0, 0, 0))
	camera.far = 850
	camera.current = true
	terrain.set_camera(camera)
	await create_timer(3).timeout
	var failed := terrain.data.get_region_count() != 4 or not terrain.data.get_control_hole(Vector3.ZERO)
	var query := PhysicsRayQueryParameters3D.create(Vector3(-65, 35, 20), Vector3(-65, -5, 20), 1)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	failed = failed or hit.is_empty()
	print("SNOW_SURFACE_COLLISION: ", hit.get("position", "MISSING"))
	print("SNOW_TEST: ", "FAIL" if failed else "PASS")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-SnowOverview.png"))
		camera.global_position = Vector3(-65, 2.0, 16)
		camera.look_at(Vector3(-30, 4, 4))
		await create_timer(1).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-SnowArrival.png"))
	BaseGameplayController.delete_progress_save()
	quit(1 if failed else 0)
