extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-30, -25, 0)
	light.light_energy = 2.0
	var lamp: PlayerFlashlight = load("res://scenes/objects/equipment/flashlight.tscn").instantiate()
	lamp.position = Vector3(0.18, -0.16, -0.02)
	world.add_child(lamp)
	lamp.malfunction_enabled = false
	lamp.set_equipped(true)
	await create_timer(0.4).timeout
	lamp.play_battery_action()
	for index in 22:
		await create_timer(0.02).timeout
		lamp.update_motion(0.02, 0.0, true, false)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Flashlight-Pose.png"))
	quit()
