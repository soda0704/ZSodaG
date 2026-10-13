extends SceneTree

var failures := 0
var checks := 0
var paths: Array[String] = []
var capture := false
var test_root: String

func _initialize() -> void:
	test_root = "user://feedback_test_%d" % OS.get_process_id()
	ProjectSettings.set_setting(TesterFeedbackStore.ROOT_SETTING, test_root)
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://feedback_test_settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://feedback_test_controls.cfg")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://feedback_test_save_%d.cfg" % OS.get_process_id())
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle() -> void:
	await create_timer(0.45).timeout

func screenshot(name: String) -> void:
	if capture and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/feedback-" + name + ".png")

func inspect_report(result: Dictionary) -> Dictionary:
	if not result.get("ok", false): return {}
	paths.append(str(result.path))
	var reader := ZIPReader.new()
	check(reader.open(result.path) == OK, "archive is readable")
	var data: Dictionary = JSON.parse_string(reader.read_file("report.json").get_string_from_utf8())
	check(reader.file_exists("report.txt"), "archive includes human-readable report")
	reader.close()
	return data

func run() -> void:
	await process_frame
	var fields := {"title": "Дверь не открывается", "category": "Ошибка", "severity": "Мешает играть", "description": "После включения питания дверь осталась закрытой.\nКириллица, ё, Unicode ✓", "steps": "1. Включить щит\n2. Нажать E"}
	var ctx := {"base": {"day": 2, "main_power": true}, "player": {"position": [1.0, 2.0, 3.0]}}
	check(not TesterFeedbackStore.save_report({}, ctx).ok, "empty reports rejected")
	var invalid := fields.duplicate()
	invalid.description = " \n\t"
	check(not TesterFeedbackStore.save_report(invalid, ctx).ok, "whitespace description rejected")
	invalid = fields.duplicate()
	invalid.title = "a".repeat(121)
	check(not TesterFeedbackStore.save_report(invalid, ctx).ok, "overlong title rejected")
	invalid = fields.duplicate()
	invalid.steps = "a".repeat(8001)
	check(not TesterFeedbackStore.save_report(invalid, ctx).ok, "overlong steps rejected")
	invalid = fields.duplicate()
	invalid.category = "Unknown"
	check(not TesterFeedbackStore.save_report(invalid, ctx).ok, "unknown category rejected")
	var result := TesterFeedbackStore.save_report(fields, ctx)
	var report := inspect_report(result)
	check(report.get("description", "") == fields.description and report.get("steps", "") == fields.steps, "JSON preserves Unicode and newlines")
	check(report.get("attachment", "missing") == "" and int(report.get("context", {}).get("base", {}).get("day", -1)) == 2 and bool(report.context.base.main_power) and report.context.player.position.size() == 3, "report without screenshot retains captured diagnostics")
	check(not fields.has("report_id"), "saving does not mutate the draft")
	var image := Image.create(3840, 2160, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.7, 0.3))
	var resized := TesterFeedbackStore.prepare_image(image)
	check(resized.get_size() == Vector2i(1920, 1080) and image.get_size() == Vector2i(3840, 2160), "large screenshot is bounded without modifying original")
	var with_image := TesterFeedbackStore.save_report(fields, ctx, image)
	report = inspect_report(with_image)
	check(TesterFeedbackStore.archive_error(with_image.path).is_empty(), "saved ZIP passes size and entry validation")
	check(str(with_image.get("path", "")) != str(result.get("path", "")), "successive reports never overwrite one another")
	var reader := ZIPReader.new()
	reader.open(with_image.path)
	var restored := Image.new()
	check(restored.load_png_from_buffer(reader.read_file("screenshot.png")) == OK and restored.get_size() == Vector2i(1920, 1080), "ZIP contains valid resized PNG")
	check(report.attachment == "screenshot.png", "JSON names the bundled screenshot")
	reader.close()
	var blocked := test_root.path_join("not_a_directory")
	var file := FileAccess.open(blocked, FileAccess.WRITE)
	file.store_string("keep")
	file.close()
	ProjectSettings.set_setting(TesterFeedbackStore.ROOT_SETTING, blocked.path_join("child"))
	check(not TesterFeedbackStore.save_report(fields, ctx).ok and FileAccess.get_file_as_string(blocked) == "keep", "write failure is reported and does not replace existing files")
	ProjectSettings.set_setting(TesterFeedbackStore.ROOT_SETTING, test_root)
	paths.append(ProjectSettings.globalize_path(blocked))
	var large_path := test_root.path_join("overlarge.zip")
	var zip := ZIPPacker.new()
	zip.open(large_path)
	zip.start_file("report.json")
	zip.write_file("a".repeat(129 * 1024).to_utf8_buffer())
	zip.close_file()
	zip.start_file("report.txt")
	zip.write_file("text".to_utf8_buffer())
	zip.close_file()
	zip.close()
	check(not TesterFeedbackStore.archive_error(large_path).is_empty(), "overlarge compressed JSON is rejected before decompression")
	paths.append(ProjectSettings.globalize_path(large_path))
	var menu = root.get_node("GameMenu")
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await settle()
	check(main.shell.content.get_child(0).has_node("Navigation/Feedback"), "main menu has native feedback entry")
	check(menu.main_panel.has_node("Feedback"), "Escape menu has native feedback entry")
	check(InputMap.action_get_events("tester_feedback")[0].physical_keycode == KEY_F8, "F8 action uses correct physical key")
	var keyboard_f8 := InputEventKey.new()
	keyboard_f8.physical_keycode = KEY_F8
	keyboard_f8.pressed = true
	check(InputMap.event_is_action(keyboard_f8, "tester_feedback"), "ordinary keyboard F8 matches feedback action")
	await menu.open_feedback()
	await settle()
	var form: NorthernTesterFeedback = menu.tester_feedback
	# UI/storage regression must never submit fixtures to the deployed receiver.
	form.delivery_config = form.delivery_config.duplicate() as TesterFeedbackConfig
	form.delivery_config.endpoint = ""
	check(menu.is_menu_open() and form.visible and menu._current_view == menu.MenuView.FEEDBACK, "feedback owns input through existing GameMenu")
	check(form.save_button.disabled, "empty form cannot save")
	form.title_input.text = fields.title
	form.description.text = fields.description
	form.steps.text = fields.steps
	form._edited()
	check(not form.save_button.disabled, "filled form enables report saving")
	var console = root.get_node("DeveloperConsole")
	form.description.grab_focus()
	var letter := InputEventKey.new()
	letter.pressed = true
	letter.unicode = 1105
	console._input(letter)
	check(not console.opened, "typing Russian yo does not open developer console")
	form.set_screenshot(resized, true)
	check(form.preview.texture != null and not form.empty_preview.visible, "attached image has preview")
	var image_file := test_root.path_join("selected.png")
	resized.save_png(image_file)
	paths.append(ProjectSettings.globalize_path(image_file))
	form.attach_file(image_file)
	check(form.screenshot.get_size() == Vector2i(1920, 1080), "image selected from disk is attached")
	var invalid_file := test_root.path_join("broken.png")
	file = FileAccess.open(invalid_file, FileAccess.WRITE)
	file.store_string("not a PNG")
	file.close()
	paths.append(ProjectSettings.globalize_path(invalid_file))
	form.attach_file(invalid_file)
	check(form.status.text.contains("Не удалось") and form.screenshot != null, "broken image keeps previous attachment and reports failure")
	form.set_screenshot(null, true)
	check(form.screenshot == null and form.empty_preview.visible and form.get_node("%RemoveImage").disabled, "attachment can be removed")
	var preserved := form.context.duplicate(true)
	menu.close_feedback()
	check(not menu.is_menu_open(), "feedback opened from main menu returns to main menu")
	await menu.open_feedback()
	check(menu.tester_feedback == form and form.description.text == fields.description and form.context == preserved, "Escape/reopen preserves unsaved draft and original context")
	form.set_screenshot(resized, true)
	await screenshot("form-main")
	await form.save()
	check(not form.saved_path.is_empty() and form.save_button.disabled and not form.get_node("%CopyPath").disabled, "save succeeds and disables accidental duplicate submissions")
	paths.append(form.saved_path)
	menu.close_feedback()
	await menu.open_feedback()
	form = menu.tester_feedback
	check(form.title_input.text.is_empty() and form.description.text.is_empty(), "opening after a saved report starts a fresh report")
	menu.close_feedback()
	main.queue_free()
	current_scene = null
	await process_frame
	var world = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	world.get_node("BaseGameplayController").progress_persistence_enabled = false
	root.add_child(world)
	current_scene = world
	await settle()
	var base := world.get_node("BaseGameplayController") as BaseGameplayController
	var player := get_first_node_in_group("local_player") as GamePlayer
	player.survival.debug_invincible = true
	menu.force_close_menu()
	var f8 := InputEventAction.new()
	f8.action = "tester_feedback"
	f8.pressed = true
	menu._unhandled_input(f8)
	await settle()
	form = menu.tester_feedback
	check(form.visible and menu.is_menu_open() and not paused, "F8 opens feedback during gameplay without pausing world")
	check(form.context.get("base", {}).get("day", -1) == base.day_index and form.context.get("player", {}).has("position"), "real player and base diagnostics captured")
	check(not JSON.stringify(form.context).contains("steam_id") and not form.context.has("save_path"), "diagnostics omit account IDs and local save paths")
	if DisplayServer.get_name() != "headless":
		check(form.screenshot != null and form.screenshot.get_width() <= 1920, "F8 captures a real rendered game screenshot")
		form.title_input.text = "Лифт: проверка восстановления питания"
		form.description.text = "Включил питание и подошёл к лифту. Хочу проверить, одинаково ли он работает у хоста и у гостя."
		form.steps.text = "1. Войти в базу\n2. Включить рубильник\n3. Вызвать лифт"
		form._edited()
		await screenshot("form-game")
		await menu.capture_feedback_screenshot()
		check(form.screenshot != null and form.visible and menu.is_menu_open() and not form._busy, "recapture restores form and input ownership")
		await RenderingServer.frame_post_draw
		var visible_form := TesterFeedbackStore.prepare_image(root.get_texture().get_image())
		var different := 0
		for index in 20:
			var point := Vector2i(visible_form.get_width() * (index + 1) / 21, visible_form.get_height() / 2)
			var first := visible_form.get_pixelv(point)
			var second := form.screenshot.get_pixelv(point)
			if absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b) > 0.05: different += 1
		check(different > 5, "screenshot excludes feedback overlay")
		root.content_scale_size = Vector2i(1920, 1080)
		root.size = Vector2i(1280, 720)
		await settle()
		await screenshot("form-720")
		check(form.get_node("%Save").get_global_rect().end.y <= root.get_visible_rect().end.y, "save action remains on screen at 720p")
	menu.close_feedback()
	check(not menu.is_menu_open() and not paused, "F8 feedback returns directly to gameplay")
	menu._unhandled_input(f8)
	await settle()
	check(menu.is_menu_open() and menu.tester_feedback.visible, "F8 works again after closing feedback")
	menu.close_feedback()
	menu.open_menu(menu.MenuView.MAIN)
	await settle()
	await menu.open_feedback()
	menu.close_feedback()
	check(menu.is_menu_open() and menu._current_view == menu.MenuView.MAIN, "feedback opened from Escape returns to Escape")
	menu.force_close_menu()
	world.queue_free()
	current_scene = null
	await process_frame
	for owned_path in paths: DirAccess.remove_absolute(owned_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root))
	print("TESTER FEEDBACK RESULT: ", checks, " checks, ", failures, " failures")
	quit(0 if failures == 0 else 1)
