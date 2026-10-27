extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, "user://simplified_menu_%d" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://simplified_settings.json")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)
func settle() -> void:
	await create_timer(0.7).timeout
func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var output := "res://tools/.local/daily-save-ui"
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
func click(button: Control) -> void:
	var at := button.get_global_transform_with_canvas() * (button.size * .5)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.pressed = pressed
		root.push_input(event, true)
func write(day: int, scope: String = "solo", kind: String = "start") -> void:
	var config := ConfigFile.new()
	config.set_value("save", "version", 1)
	config.set_value("base", "day_index", day)
	config.set_value("base", "main_breaker_on", true)
	config.set_value("inventory", "checkpoint", {"players": {}})
	ExpeditionSaveStore.write(config, scope, kind)
func run() -> void:
	var menu := root.get_node("GameMenu")
	ExpeditionSaveStore.select("solo", 2)
	write(3)
	ExpeditionSaveStore.select("solo", 1)
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await settle()
	check(not main.continue_game_button.disabled and ExpeditionSaveStore.slot("solo") == 2, "existing save from removed slot UI stays accessible")
	main._show_checkpoint()
	await settle()
	var page = main.shell.content.get_child(0)
	check(page.get_node("%Morning").get_node("%Day").text == "ДЕНЬ 3" and not page.get_node("%Continue").disabled, "Continue presents the existing expedition")
	check(page.get_node("%Manual").disabled and not page.get_node("%Morning").disabled and page.get_node("%PreviousMorning").disabled, "screen exposes three fixed save entries with empty states")
	await capture("empty-entries")
	write(4, "solo", "sleep")
	write(4, "solo", "manual")
	main._show_checkpoint()
	page = main.shell.content.get_child(0)
	page.get_node("%Morning").pressed.emit()
	page.get_node("%PreviousMorning").pressed.emit()
	await settle()
	check(page.get_node("%Actions").modulate.a > .99 and page.get_node("%Manual").modulate.a > .99 and page.get_node("%Morning").modulate.a > .99, "rapid selection during entrance leaves all entries and actions fully visible")
	check(page.get_node("%PreviousMorning").get_node("%Tint").color.a > .11, "selected entry finishes its native highlight animation")
	page.get_node("%Manual").pressed.emit()
	page = main.shell.content.get_child(0)
	check(not page.get_node("%Manual").disabled and not page.get_node("%Morning").disabled and not page.get_node("%PreviousMorning").disabled, "all three fixed entries become available")
	var path_before: String = ExpeditionSaveStore.read("solo").path
	if DisplayServer.get_name() == "headless": page.get_node("%PreviousMorning").pressed.emit()
	else: click(page.get_node("%PreviousMorning"))
	check(menu.dialog == null and ExpeditionSaveStore.read("solo").path == path_before, "selecting a record only previews it without loading or writing")
	check(page.get_node("%PreviousMorning").get_node("%Marker").visible and page.get_node("%Continue").text.contains("ДНЯ 3"), "selected morning updates highlight and explicit load action")
	await capture("previous-morning")
	page.get_node("%Continue").pressed.emit()
	check(menu.dialog != null and ExpeditionSaveStore.read("solo").path == path_before, "loading older morning asks before discarding progress")
	menu.dialog.dismiss()
	await settle()
	page.get_node("%Morning").pressed.emit()
	await capture("used-manual-morning")
	page.get_node("%Manual").pressed.emit()
	page.get_node("%Continue").grab_focus()
	if DisplayServer.get_name() != "headless":
		var off_row := InputEventMouseMotion.new()
		off_row.position = Vector2(10, 10)
		root.push_input(off_row, true)
		var output := "res://tools/.local/daily-save-ui"
		DirAccess.make_dir_recursive_absolute(output)
		for resolution in [Vector2i(1920,1080), Vector2i(1280,720)]:
			root.size = resolution
			await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("checkpoints-%d.png" % resolution.x))
	main._show_home()
	main._on_single_player_pressed()
	await settle()
	check(menu.dialog == null and main.current_view == "character" and main.selector != null, "new game opens character selection immediately even with an existing save")
	check(ExpeditionSaveStore.read("solo").path == path_before, "opening character selection does not replace the existing save")
	main.back()
	await settle()
	check(main.current_view == "home" and ExpeditionSaveStore.read("solo").path == path_before, "back from character selection preserves existing progress")
	main._show_home()
	check(main.get_node("FeedbackCorner") is Button, "feedback retained in main menu")
	check(menu.main_panel.get_node("Save") is Button and menu.main_panel.get_node("Feedback") is Button, "manual save and feedback retained in ESC")
	menu.main_panel.refresh()
	check(menu.main_panel.get_node("Save").disabled, "manual save cannot run outside an expedition")
	ExpeditionSaveStore.select("solo", 3)
	write(1)
	ExpeditionSaveStore.select("solo", 2)
	main._delete_save()
	await settle()
	check(main.current_view == "home" and main.continue_game_button.disabled, "delete returns home without silently switching to another expedition")
	ExpeditionSaveStore.select("solo", 3)
	check(ExpeditionSaveStore.summary("solo").day_index == 1, "other existing save files survive UI simplification")
	ExpeditionSaveStore.select("coop", 1)
	write(6, "coop")
	var available: bool = root.get_node("SteamNetwork").steam_available
	root.get_node("SteamNetwork").steam_available = true
	menu.start_host_flow()
	check(main.current_view == "checkpoint" and main.shell.content.get_child(0).get_node("%Mode").text.contains("КООПЕРАТИВНАЯ"), "coop uses the same three checkpoint entries on the host")
	await capture("coop-checkpoints")
	root.get_node("SteamNetwork").steam_available = available
	await settle()
	menu.force_close_menu()
	current_scene = null
	main.queue_free()
	for frame in 4: await process_frame
	print("EXPEDITION MENU RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
