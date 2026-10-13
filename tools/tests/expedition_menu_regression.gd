extends SceneTree
var failures := 0
var checks := 0
var capture := false
func _initialize() -> void:
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, "user://expedition_menu_regression")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://expedition_menu_settings.json")
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func settle() -> void:
	await create_timer(0.6).timeout
func screenshot(label: String) -> void:
	if capture and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/expedition-menu-" + label + ".png")
func write(day: int, kind: String) -> void:
	var config := ConfigFile.new()
	config.set_value("save", "version", 1)
	config.set_value("base", "day_index", day)
	config.set_value("base", "main_breaker_on", true)
	config.set_value("inventory", "checkpoint", {"players": {}})
	ExpeditionSaveStore.write(config, "coop", kind)
func run() -> void:
	var menu := root.get_node("GameMenu")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_position(Vector2i(-1600, 40))
	Engine.max_fps = 60
	for scope in ["solo", "coop"]:
		for number in range(1, 4):
			ExpeditionSaveStore.select(scope, number)
			ExpeditionSaveStore.clear(scope)
	ExpeditionSaveStore.select("coop", 1)
	ExpeditionSaveStore.rename_slot("coop", "С Димой")
	write(1, "start")
	write(2, "sleep")
	write(3, "sleep")
	write(3, "manual")
	ExpeditionSaveStore.select("coop", 2)
	ExpeditionSaveStore.rename_slot("coop", "С Никитой")
	write(1, "start")
	ExpeditionSaveStore.select("coop", 1)
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await settle()
	check(main.continue_game_button.disabled, "Continue disabled when all solo slots empty")
	main.show_expeditions("coop")
	await settle()
	var page: Control = main.shell.content.get_child(0)
	var body := page.get_node("Scroll/Body")
	check(page.get_node("Slots").item_count == 3, "three selectable companies")
	check(page.get_node("Slots").get_item_text(0).contains("С Димой") and page.get_node("Slots").get_item_text(1).contains("С Никитой"), "named company labels")
	check(body.get_node("Day").text == "ДЕНЬ 3", "current expedition summary")
	check(body.get_node("History").item_count == 2, "bounded history offered")
	check(not body.get_node("Rollback").disabled, "rollback enabled for available checkpoints")
	check(body.get_node("Continue").disabled == not root.get_node("SteamNetwork").steam_available, "host flow follows actual Steam availability")
	await screenshot("coop")
	page.get_node("Slots").item_selected.emit(1)
	await settle()
	page = main.shell.content.get_child(0)
	body = page.get_node("Scroll/Body")
	check(ExpeditionSaveStore.slot("coop") == 2 and body.get_node("Day").text == "ДЕНЬ 1", "selection changes only active company")
	body.get_node("Naming/Name").text = "С третьим другом"
	body.get_node("Naming/Rename").pressed.emit()
	await settle()
	check(ExpeditionSaveStore.slot_name("coop") == "С третьим другом", "authored name field persists label")
	main.show_expeditions("coop")
	page = main.shell.content.get_child(0)
	page.get_node("Slots").item_selected.emit(0)
	await settle()
	page = main.shell.content.get_child(0)
	body = page.get_node("Scroll/Body")
	body.get_node("History").select(1)
	body.get_node("Rollback").pressed.emit()
	await settle()
	check(menu.dialog != null and menu.dialog.get_node("Center/Panel/Content/Message").text.contains("Более поздние"), "rollback warns about discarding future")
	await screenshot("rollback")
	menu.dialog.dismiss(main._rollback.bind(str(main._history_points[1].name)))
	await settle()
	page = main.shell.content.get_child(0)
	body = page.get_node("Scroll/Body")
	check(body.get_node("Day").text == "ДЕНЬ 2", "confirmed rollback changes current expedition")
	check(body.get_node("Rollback").disabled, "discarded future no longer offered")
	page.get_node("Slots").item_selected.emit(1)
	await settle()
	check(ExpeditionSaveStore.summary("coop").day_index == 1, "other company survives rollback")
	page = main.shell.content.get_child(0)
	page.get_node("Slots").item_selected.emit(2)
	await settle()
	page = main.shell.content.get_child(0)
	body = page.get_node("Scroll/Body")
	check(body.get_node("Continue").disabled and body.get_node("Rollback").disabled, "empty slot has no continue or rollback")
	await screenshot("empty")
	main.show_expeditions("solo")
	await settle()
	check(BaseGameplayController.save_scope == "solo", "solo scope selected separately")
	await screenshot("solo")
	# An ESC save control is part of the authored scene and cannot save an absent base.
	check(menu.main_panel.get_node("Save") is Button, "manual save authored in ESC scene")
	menu.main_panel.refresh()
	check(menu.main_panel.get_node("Save").disabled, "manual save unavailable outside expedition")
	print("EXPEDITION MENU CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
