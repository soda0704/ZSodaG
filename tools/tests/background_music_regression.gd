extends SceneTree

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "res://tools/.local/background_music_test.cfg")
	run.call_deferred()

func run() -> void:
	await process_frame
	var game_menu := root.get_node("GameMenu")
	assert(not game_menu.has_node("BackgroundMusic"))
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	assert(menu.background_video.is_playing() and menu.background_video.bus == &"Music")
	menu.queue_free()
	await process_frame
	assert(not game_menu.has_node("BackgroundMusic"))
	print("PASS no persistent background track before or after the main menu; menu video plays on Music")
	quit()
