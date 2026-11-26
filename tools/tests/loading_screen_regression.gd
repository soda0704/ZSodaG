extends SceneTree
var failures: Array[String] = []
var checks := 0
var captures := "res://tools/.local/loading-review"
func _initialize() -> void:
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty(): captures = OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://loading_settings_%d.json" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures.append(message)
func run() -> void:
	await process_frame
	Engine.max_fps = 60
	root.get_node("GameMenu").force_close_menu()
	var service = root.get_node("SteamInput")
	service.using_controller = false
	for action in [&"interact", &"journal", &"offer_item", &"ui_cancel", &"flashlight"]:
		var hint: String = service.get_action_hint(action)
		check(hint.begins_with("[ ") and hint.ends_with(" ]"), "spaced keyboard hint: " + str(action))
	service.using_controller = true
	check(service.get_action_hint(&"interact").begins_with("[ "), "controller hint uses the same spacing")
	service.using_controller = false
	var hud = load("res://scenes/ui/helicopter_lobby_hud.tscn").instantiate()
	root.add_child(hud)
	var screen = hud.get_node("FlightTransition")
	var generation: int = hud.show_transition_cover("ПОСАДКА У БАЗЫ…")
	check(screen.visible and screen.get_node("SmokeBackground").material is ShaderMaterial and screen.music.playing, "production transition starts shared fog and separate music")
	check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "loading disables the existing polled gameplay input gate")
	check(screen.tips.any(func(tip): return tip.body=="Не забывайте поливать растение") and screen.find_child("Video", true, false)==null, "authored tips remain and VHS video is removed")
	check(screen.music.stream.loop and screen.logo.texture.resource_path.ends_with("northernlab-512.png"), "music loops and loading uses the current brand logo")
	check(screen.music.stream.resource_path == "res://assets/audio/music/main_menu.ogg" and screen.music.stream.get_length() > 0.0,
		"loading plays the current menu track and the resource contains audio")
	check(screen.tip_title.text == "Прислушивайся.", "approved opening copy")
	check(screen.displayed_progress == 0.0, "loading progress starts empty")
	screen.set_progress(0.62)
	screen._process(0.4)
	check(is_equal_approx(screen.displayed_progress, 0.62), "pill follows reported loading work")
	screen.set_progress(0.2)
	screen.set_progress(NAN)
	check(is_equal_approx(screen._progress_target, 0.62), "stale and invalid progress cannot move bar backwards")
	check(is_equal_approx(screen.progress_bar.material.get_shader_parameter("fill_ratio"), 0.62), "reported progress reaches shader fill")

	check(screen.find_child("NextHint", true, false) == null, "no tip counter or Space instruction is displayed")
	check(screen.tip_seconds <= 6.0, "automatic tips change every few seconds")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	await tip_finished(screen)
	check(screen.tip_index == 1 and "находиться" in screen.tip_body.text, "real Space input selects the next approved tip")
	event.echo = true
	Input.parse_input_event(event)
	await process_frame
	check(screen.tip_index == 1, "key repeat does not skip tips")
	event.echo = false
	event.pressed = false
	Input.parse_input_event(event)
	screen.next_tip()
	await tip_finished(screen)
	check(screen.tip_title.text == "Делитесь с напарником." and screen.tip_body.text == "Удерживайте [ СКМ ], чтобы протянуть предмет.", "handoff copy is short and uses current input binding")
	var old_events := InputMap.action_get_events(&"offer_item")
	InputMap.action_erase_events(&"offer_item")
	var changed := InputEventKey.new()
	changed.physical_keycode = KEY_H
	InputMap.action_add_event(&"offer_item", changed)
	screen._refresh_tip()
	check("[ H ]" in screen.tip_body.text, "tip respects remapped actions")
	InputMap.action_erase_events(&"offer_item")
	for previous in old_events: InputMap.action_add_event(&"offer_item", previous)
	screen._refresh_tip()
	screen.next_tip()
	await tip_finished(screen)
	check(screen.tip_title.text == "Вдвоём легче." and "[ E ]" in screen.tip_body.text, "carry tip uses approved copy and spaced action")
	screen.next_tip()
	await tip_finished(screen)
	check("ваши вещи" in screen.tip_body.text and "Просмотреть — [ J ]" in screen.tip_body.text, "journal copy follows approved wording")
	screen.next_tip()
	await tip_finished(screen)
	check(screen.tip_body.text=="Не забывайте поливать растение", "watering reminder is displayed through normal tip cycling")
	screen.next_tip()
	await tip_finished(screen)
	check(screen.tip_index == 0, "tip list wraps")
	screen._process(screen.tip_seconds)
	await tip_finished(screen)
	check(screen.tip_index == 1, "automatic cycling also works")
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		DirAccess.make_dir_recursive_absolute(captures)
		for dimensions in [Vector2i(1920, 1080), Vector2i(1024, 768), Vector2i(3440, 1440), Vector2i(1280, 720)]:
			root.size = dimensions
			for frame in 20: await process_frame
			await RenderingServer.frame_post_draw
			var tip_rect: Rect2 = screen.tip_body.get_global_rect()
			check(root.get_visible_rect().grow(1).encloses(tip_rect), "footer fits " + str(dimensions))
			check(screen.get_node("SmokeBackground").get_global_rect().encloses(root.get_visible_rect()), "fog covers " + str(dimensions))
			root.get_texture().get_image().save_png(captures.path_join("%dx%d.png" % [dimensions.x, dimensions.y]))
	var current: int = hud.show_transition_cover("ПОДЛЁТ К БАЗЕ…")
	hud.reveal_transition_cover(generation)
	check(screen.visible and screen.music.playing, "stale completion cannot dismiss a newer transition")
	await hud.reveal_transition_cover(current)
	check(not screen.visible and not screen.music.playing, "completion hides screen and stops loading music")
	check(not screen.is_processing() and (not is_instance_valid(screen._logo_tween) or not screen._logo_tween.is_valid()), "hidden loading screen stops presentation updates")
	var index: int = screen.tip_index
	event.pressed = true
	screen._input(event)
	check(screen.tip_index == index, "hidden screen ignores input")
	hud.queue_free()
	await process_frame
	print("RESULT ", checks, " CHECKS; FAILURES ", failures.size())
	quit(0 if failures.is_empty() else 1)

func tip_finished(screen: Control) -> void:
	await process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while screen._tip_changing and Time.get_ticks_msec() < deadline:
		await process_frame
