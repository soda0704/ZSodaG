extends SceneTree
## Native 1440p comparison of the previous and revised High budgets.
## Uses isolated preferences; fixed cameras exclude movement/physics and loading.
func _initialize():
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://high_profile_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://high_profile.cfg")
	run.call_deferred()
func frames(count):
	for index in count: await process_frame
func measure(label):
	await frames(60)
	var samples: Array[float] = []
	var previous = Time.get_ticks_usec()
	for index in 120:
		await process_frame
		var now = Time.get_ticks_usec()
		samples.append((now-previous)/1000.0)
		previous = now
	samples.sort()
	print("PROFILE ",label," median_ms=",snappedf(samples[60],0.01)," p95_ms=",snappedf(samples[114],0.01))
func run():
	await process_frame
	var menu = root.get_node("GameMenu")
	menu.force_close_menu()
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(2560,1440)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var level = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	level.network_runtime_managed = true
	root.add_child(level)
	current_scene = level
	var player = load("res://scenes/characters/player.tscn").instantiate()
	player.setup(1,"Profile",Vector3(-25,0.1,0),Color.WHITE,-PI/2)
	level.add_child(player)
	player.survival.debug_invincible = true
	player.set_physics_process(false)
	player.apply_held_item_inventory(&"pistol",{})
	player.update_character_animation(1.0/60)
	var quality = menu.get_node("GraphicsQuality")
	var variants = {"legacy_high":quality.LEGACY_HIGH,"high":quality.PRESETS[3]}
	var routes = {"hub":[Vector3(0,1.75,6),Vector3(0,1.6,-4)],"level-2":[Vector3(-17,-31.75,0),Vector3(-29,-33.5,0)],"exterior-near":[Vector3(-58,8,18),Vector3(-15,3,0)],"exterior-far":[Vector3(-95,22,32),Vector3(-15,3,0)]}
	for route in routes:
		player.camera.global_position = routes[route][0]
		player.camera.look_at(routes[route][1])
		for variant in variants:
			var settings: Dictionary = quality.PRESETS[3].duplicate()
			settings.merge(variants[variant],true)
			quality.apply(settings)
			Engine.max_fps = 0
			await frames(2)
			if variant == "legacy_high": RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)
			await measure(route+"/"+variant)
	print("PROFILE COMPLETE")
	quit()
