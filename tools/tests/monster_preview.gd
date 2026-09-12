extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.11, 0.12, 0.14)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.5
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.8
	world.add_child(light)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(3.7, 2.2, 5.5)
	camera.look_at(Vector3(0, 1.0, 0))
	camera.current = true
	if OS.get_cmdline_user_args().has("reel"):
		root.size = Vector2i(512, 384)
		root.content_scale_size = Vector2i(512, 384)
		var visual := preload("res://scripts/gameplay/monster_visual.gd").new()
		world.add_child(visual)
		visual.setup("the_monster")
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 32)
		root.add_child(label)
		var sheet := Image.create(3072, 1536, false, Image.FORMAT_RGBA8)
		var reel_start := float(OS.get_environment("MONSTER_REEL_START"))
		var reel_step := float(OS.get_environment("MONSTER_REEL_STEP"))
		if reel_step <= 0.0:
			reel_step = 0.5
		for index in 24:
			var time := reel_start + index * reel_step
			visual.animator.seek(time, true)
			var skeleton := visual.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
			var hip := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hip_03")).origin)
			camera.position = Vector3(hip.x + 3.0, 2.0, hip.z + 3.0)
			camera.look_at(Vector3(hip.x, 0.9, hip.z))
			label.text = "%.1f s" % time
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			frame.convert(Image.FORMAT_RGBA8)
			frame.resize(512, 384)
			sheet.blit_rect(frame, Rect2i(0, 0, 512, 384), Vector2i(index % 6 * 512, index / 6 * 384))
		sheet.save_png(OS.get_environment("TEMP").path_join("Monster-reel-%d.png" % int(reel_start)))
		quit()
		return
	for id in ["the_monster", "slasher", "smily"]:
		var visual := preload("res://scripts/gameplay/monster_visual.gd").new()
		world.add_child(visual)
		visual.setup(id)
		for skeleton: Skeleton3D in visual.model.find_children("*", "Skeleton3D", true, false):
			for bone in skeleton.get_bone_count():
				if bone < 8 or "pelvis" in skeleton.get_bone_name(bone).to_lower():
					print("BONE ", id, " ", skeleton.get_bone_name(bone), " ", skeleton.to_global(skeleton.get_bone_global_pose(bone).origin))
		for time in ([0.0, 2.0, 10.0, 30.0, 60.0, 120.0, 200.0] if id == "the_monster" else [1.0]):
			visual.animator.seek(time, true)
			await create_timer(0.12).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("Monster-%s-%d.png" % [id, int(time)]))
		print("MONSTER_MODEL: ", id, " scale=", visual.model.scale, " position=", visual.model.position, " animation=", visual.animation_name)
		visual.free()
	quit()
