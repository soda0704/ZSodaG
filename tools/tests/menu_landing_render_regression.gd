extends SceneTree
## Run with a real rendering driver and isolated APPDATA/LOCALAPPDATA.
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://menu_landing_render_test.cfg")
	run.call_deferred()

func run() -> void:
	var menu = root.get_node("GameMenu")
	print("LANDING RENDER PROFILE ", menu._settings_data.get("Graphics", {}))
	Engine.max_fps = 60
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.show_character()
	for index in 12:
		await process_frame
	print("LANDING RENDER PREVIEW VIDEO MEMORY ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	await menu.start_standalone_flow()
	for index in 12:
		await physics_frame
	var player = get_first_node_in_group("local_player")
	player.survival.debug_invincible = true
	print("LANDING RENDER CABIN VIDEO MEMORY ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	await current_scene._enter_v3_level()
	for index in 60:
		await process_frame
	print("LANDING RENDER BASE VIDEO MEMORY ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	menu.open_menu()
	for index in 12:
		await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/menu-landing-render.png")
	var state = get_first_node_in_group("base_gameplay_controller")
	state.save_progress_authoritative()
	menu.return_to_main_menu()
	await scene_changed
	for index in 12:
		await process_frame
	print("LANDING RENDER RETURN VIDEO MEMORY ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	await menu.start_standalone_flow(true)
	for index in 60:
		await process_frame
	if get_first_node_in_group("base_gameplay_controller") == null:
		push_error("Continue did not restore the base")
		quit(1)
		return
	print("LANDING RENDER CONTINUE VIDEO MEMORY ", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	print("PASS rendered character preview, cabin, base, ESC, return and continue")
	quit()
