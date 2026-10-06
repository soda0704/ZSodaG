extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	await process_frame
	var music: AudioStreamPlayer = root.get_node("GameMenu/BackgroundMusic")
	assert(music.playing and music.bus == &"Music" and music.stream.loop)
	var start_volume := music.volume_db
	await create_timer(0.3).timeout
	assert(music.volume_db > start_volume)
	var position := music.get_playback_position()
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	assert(menu.background_video.volume_db <= -80.0)
	menu.queue_free()
	await process_frame
	assert(root.get_node("GameMenu/BackgroundMusic") == music and music.get_playback_position() >= position)
	var bus := AudioServer.get_bus_index("Music")
	var muted := AudioServer.is_bus_mute(bus)
	AudioServer.set_bus_mute(bus, true)
	assert(music.playing and AudioServer.is_bus_mute(bus))
	AudioServer.set_bus_mute(bus, muted)
	print("PASS native music loop, fade-in, Music bus, persistent scene playback and muted video soundtrack")
	quit()
