extends SceneTree
## External script: run with --path <build dir> --main-pack <exported EXE>.
## Exercises production menu actions with isolated saves, never source scenes.
var failures: Array[String] = []

func _initialize() -> void:
	var prefix := "user://export_new_game_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root", prefix + "/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	ProjectSettings.set_setting("northern_lab/testing/base_save_path", "")
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
	return ok

func finish() -> void:
	print("EXPORT NEW GAME RESULT ", failures)
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	for frame in 3:
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	var directory := OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
	if DisplayServer.get_name() == "headless" or directory.is_empty(): return
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "capture packaged " + label)

func run() -> void:
	if not check(FileAccess.file_exists("res://project.binary"), "test uses the exported package"):
		finish()
		return
	var font = load("res://assets/fonts/hud/roboto_condensed.ttf")
	check(font is Font and font.get_string_size("СОСТОЯНИЕ 92").x > 0, "packaged HUD font renders Cyrillic and numbers")
	var theme = load("res://scenes/ui/northern_lab_hud_theme.tres")
	check(theme is Theme and theme.default_font != null, "helicopter HUD theme loads its font")
	var menu = root.get_node("GameMenu")
	await menu.start_standalone_flow()
	await create_timer(0.8).timeout
	var session = current_scene
	if not check(session != null and session.scene_file_path == "res://scenes/levels/base_session.tscn", "New Game opens the real session"):
		finish()
		return
	var player = get_first_node_in_group("local_player")
	if not check(player != null and session.is_solo_arrival(), "New Game spawns a playable player in the helicopter"):
		finish()
		return
	check(player.get_node_or_null("PlayerUI/NorthernLabHUD") != null, "player HUD instantiates in the package")
	check(session.lobby_hud != null and session.lobby_hud.lobby_panel.theme != null, "helicopter interface instantiates with its theme")
	await capture("new-game-helicopter")
	menu.open_menu(1)
	menu._on_ready_pressed()
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline and (not session.has_node("V3Level") or session._v3_transition_in_progress):
		await create_timer(0.1).timeout
	if not check(session.has_node("V3Level") and not session._v3_transition_in_progress, "Ready action completes the transition to the actual base"):
		finish()
		return
	var base = get_first_node_in_group("base_gameplay_controller")
	if not check(base != null and get_first_node_in_group("local_player") != null, "base gameplay and player are active after arrival"):
		finish()
		return
	await capture("new-game-base")
	if not check(base.save_progress_authoritative(), "arrived expedition saves successfully"):
		finish()
		return
	await menu.start_standalone_flow(true)
	await create_timer(0.8).timeout
	session = current_scene
	check(session != null and session.has_node("V3Level") and not session._v3_transition_in_progress, "Continue loads the saved base without another helicopter arrival")
	check(get_first_node_in_group("base_gameplay_controller") != null and get_first_node_in_group("local_player") != null, "continued expedition restores gameplay and player")
	menu.return_to_main_menu()
	deadline = Time.get_ticks_msec() + 15000
	while menu._transition_in_progress and Time.get_ticks_msec() < deadline:
		await process_frame
	if not check(current_scene != null and current_scene.scene_file_path == "res://scenes/ui/main_menu.tscn", "saved expedition returns to the main menu"):
		finish()
		return
	await create_timer(0.8).timeout
	await menu.start_standalone_flow()
	await create_timer(0.8).timeout
	check(current_scene != null and current_scene.has_method("is_solo_arrival") and current_scene.is_solo_arrival(), "a second New Game starts a fresh helicopter session")
	finish()
