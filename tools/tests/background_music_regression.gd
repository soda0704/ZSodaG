extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "res://tools/.local/background_music_test.cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "res://tools/.local/menu-music-20261020/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "res://tools/.local/menu-music-20261020/controls.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func run() -> void:
	await process_frame
	var game_menu := root.get_node("GameMenu")
	check(not game_menu.has_node("BackgroundMusic"), "no persistent music outside the main menu")
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	var music: AudioStreamPlayer = menu.get_node("BackgroundMusic")
	check(is_zero_approx(music.volume_linear), "first menu entry starts at silence before deferred playback")
	await create_timer(0.2).timeout
	var initial_gain := music.volume_linear
	check(initial_gain > 0.0 and initial_gain < db_to_linear(music.background_volume_db) * 0.1, "startup music begins quietly")
	await create_timer(1.0).timeout
	check(music.volume_linear > initial_gain and music.volume_db < music.background_volume_db, "startup volume rises gradually rather than jumping to full level")
	await create_timer(music.fade_in_seconds - 1.2 + 0.2).timeout
	check(is_equal_approx(music.volume_db, music.background_volume_db), "startup fade reaches the configured source level")
	check(menu.background_video.is_playing() and menu.background_video.volume_db <= -80.0, "background video plays silently")
	check(music.playing and music.bus == &"Music", "separate menu music plays through the Music settings bus")
	check(music.stream.resource_path == "res://assets/audio/music/main_menu.ogg", "menu uses the replacement track")
	check(music.stream is AudioStreamOggVorbis and music.stream.loop, "native stream looping is enabled")
	check(is_equal_approx(music.stream.get_length(), 30.0), "the full 30-second user recording is retained")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master", "master volume controls menu music too")
	check(not FileAccess.file_exists("res://assets/audio/music/northernlab.ogg"), "previous standalone track is removed")

	game_menu.open_settings()
	await create_timer(0.7).timeout
	var settings = game_menu.settings_panel
	var original: Dictionary = game_menu._settings_data.duplicate(true)
	settings._set_value("MusicVolume", 25.0, false)
	settings._set_value("MasterVolume", 50.0, false)
	check(settings.apply(false), "music and master controls apply successfully")
	var music_bus := AudioServer.get_bus_index("Music")
	var master_bus := AudioServer.get_bus_index("Master")
	check(is_equal_approx(AudioServer.get_bus_volume_db(music_bus), linear_to_db(0.25)), "Music slider changes the track's bus gain")
	check(is_equal_approx(AudioServer.get_bus_volume_db(master_bus), linear_to_db(0.5)), "Master slider changes the parent gain")
	check(music.playing, "opening and applying settings keeps the same track playing")
	check(is_equal_approx(music.volume_db, music.background_volume_db), "opening settings does not restart the fade")
	settings._set_value("MusicVolume", 0.0, false)
	check(settings.apply(false) and AudioServer.is_bus_mute(music_bus), "Music at zero mutes the track")
	settings._set_value("MusicVolume", 70.0, false)
	settings._set_value("MasterVolume", 0.0, false)
	check(settings.apply(false) and not AudioServer.is_bus_mute(music_bus) and AudioServer.is_bus_mute(master_bus), "Master at zero mutes music independently")
	settings.draft = original.duplicate(true)
	check(settings.apply(false), "test restores the original settings")
	game_menu.force_close_menu()

	music.seek(music.stream.get_length() - 0.15)
	await create_timer(0.5).timeout
	check(music.playing and music.get_playback_position() < 2.0, "track wraps from its end back to its beginning")
	check(is_equal_approx(music.volume_db, music.background_volume_db), "looping the track does not restart the fade")
	menu._show_coop()
	check(menu.get_node("BackgroundMusic") == music and music.playing, "changing menu pages retains the same player")
	check(is_equal_approx(music.volume_db, music.background_volume_db), "changing pages does not restart the fade")
	var old_player: WeakRef = weakref(music)
	menu.queue_free()
	current_scene = null
	await process_frame
	check(old_player.get_ref() == null and not game_menu.has_node("BackgroundMusic"), "leaving the main menu frees its music instead of carrying it into gameplay")
	menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	music = menu.get_node("BackgroundMusic")
	check(is_zero_approx(music.volume_linear), "returning to the menu starts at silence too")
	await create_timer(0.2).timeout
	check(music.playing and music.get_playback_position() < 1.0, "returning to the main menu starts a fresh track")
	check(music.volume_linear > 0.0 and music.volume_linear < db_to_linear(music.background_volume_db) * 0.1, "returning from gameplay begins quietly")
	await create_timer(music.fade_in_seconds + 0.1).timeout
	check(is_equal_approx(music.volume_db, music.background_volume_db), "return fade reaches the configured source level")
	menu.queue_free()
	current_scene = null
	await process_frame
	print("BACKGROUND MUSIC RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
