extends SceneTree
## Run with the editor binary, --path <build directory>, --main-pack <exported exe>
## and --script <absolute path>. Extension DLLs must also be next to the editor EXE.
## Uses the actual exported scenes/scripts, not the source project's resources.
var failures: Array[String] = []

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root", "user://export_menu_slots_%d" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://export_menu_settings_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://export_menu_controls_%d.cfg" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/base_save_path", "user://export_menu_test_%d.cfg" % OS.get_process_id())
	run.call_deferred()

func check(value: bool, message: String) -> void:
	print("PASS " if value else "FAIL ", message)
	if not value:
		failures.append(message)

func wait_ui() -> void:
	await create_timer(0.8).timeout

func screenshot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").path_join(label + ".png"))

func click(button: Control) -> void:
	var at := button.get_global_transform_with_canvas() * (button.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.pressed = pressed
		root.push_input(event, true)

func run() -> void:
	check(FileAccess.file_exists("res://project.binary"), "test is using the exported package")
	for template in ["menu_home", "menu_dialog", "esc_menu", "lobby_menu", "character_selection"]:
		var styled = load("res://scenes/ui/%s.tscn" % template).instantiate()
		check(styled.theme != null and styled.theme.default_font != null, "exported %s has its own font/theme in standalone use" % template)
		styled.free()
	var menu = root.get_node("GameMenu")
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait_ui()
	check(main.background_video.get_parent() == main and main.background_video.get_index() < main.shell.get_index(), "exported video draws below the complete interface")
	check(main.shell.shade.get_index() < main.shell.content.get_index(), "exported shade darkens the background without dimming the text")
	check(main.background_video.get_video_texture().get_size() == Vector2(1920, 1080), "exported background uses the optimized 1080p video")
	check(main.single_player_button.is_visible_in_tree() and main.single_player_button.get_global_rect().has_area(), "exported New Game button is visible and laid out")
	var home = main.shell.content.get_child(0)
	var brand = home.get_node("Brand")
	check(brand.get_theme_font("font").get_font_name() == "Arial Black", "exported brand resolves the approved Arial Black face")
	check(main.single_player_button.get_theme_font("font").get_font_name() == "Bahnschrift", "exported menu resolves Bahnschrift instead of the engine fallback")
	check(brand.get_line_count() == 2 and brand.size.y <= 125, "brand keeps the two compact lines from the approved concept")
	check(main.single_player_button.get_theme_font_size("font_size") == 23 and main.single_player_button.scale == Vector2.ONE, "navigation retains the approved size without scaling its text")
	await screenshot("export-menu-home")
	click(main.single_player_button)
	await wait_ui()
	check(main.current_view == "checkpoint", "real click in exported menu opens expedition slots")
	if main.current_view != "checkpoint":
		quit(1)
		return
	var expedition_page = main.shell.content.get_child(0)
	check(expedition_page.get_node("Slots").item_count == 3, "exported menu offers three isolated expedition slots")
	click(expedition_page.get_node("Scroll/Body/New"))
	await wait_ui()
	check(main.current_view == "character" and is_instance_valid(main.selector), "real click in exported menu opens character selection")
	if main.current_view != "character" or not is_instance_valid(main.selector):
		quit(1)
		return
	var start_button = main.shell.footer.get_child(main.shell.footer.get_child_count() - 2)
	start_button.grab_focus()
	await wait_ui()
	check(start_button.selection_line_rect().size.x <= start_button.get_theme_font("font").get_string_size(start_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, start_button.get_theme_font_size("font_size")).x + 1, "character action underline stays within the caption width")
	check(start_button.get_theme_stylebox("focus").get_border_width(SIDE_BOTTOM) == 0, "native focus does not add a second full-width underline")
	main.selector.option.grab_focus()
	await wait_ui()
	check(main.selector.option.selection_line_rect().size.x < main.selector.option.size.x * 0.5 and main.selector.option.get_theme_stylebox("focus") is StyleBoxEmpty, "character selector highlights its caption instead of the full field width")
	await screenshot("export-menu-character")
	main.back()
	await wait_ui()
	click(main.settings_button)
	await wait_ui()
	check(menu.is_menu_open() and menu.settings_panel.is_visible_in_tree(), "real click in exported menu opens settings")
	check(menu.settings_panel.size.x <= 1020 and not menu.settings_panel.title.visible, "settings retain the reference column width and tabs without an extra heading")
	menu.settings_panel.select_category(1)
	await wait_ui()
	var first_row = menu.settings_panel.rows.get_child(0)
	var motion := InputEventMouseMotion.new()
	motion.position = first_row.get_global_transform_with_canvas() * (first_row.size * 0.5)
	root.push_input(motion, true)
	# Keyboard selection runs the same enlargement without depending on the OS cursor.
	first_row.get_child(1).grab_focus()
	await wait_ui()
	var row_rect: Rect2 = first_row.get_global_rect()
	var scroll_rect: Rect2 = menu.settings_panel.scroll.get_global_rect()
	check(first_row.scale.x > 1.005 and row_rect.position.x >= scroll_rect.position.x and row_rect.end.x <= scroll_rect.end.x, "enlarged settings text stays inside the left and right scroll edges")
	await screenshot("export-menu-settings")
	menu.force_close_menu()
	await wait_ui()
	check(main.single_player_button.is_visible_in_tree(), "closing exported settings restores the home interface")
	menu.confirm("Оформление окна", "Шрифт, подложка и действия используют тему меню.", [])
	await wait_ui()
	check(menu.dialog.actions.get_child(0).get_theme_font("font") == menu.shell.theme.default_font, "dialog actions retain the menu font outside Shell")
	check(menu.dialog.panel.size.x == 930 and is_equal_approx(menu.dialog.get_node("Shade").color.a, 0.32), "notification size and backdrop match the approved concept")
	check(menu.dialog.panel.scale.is_equal_approx(Vector2.ONE) and menu.dialog.get_node("Center").scale.is_equal_approx(Vector2.ONE) and menu.dialog._line_progress > 0.99, "notification entrance settles on sharp text and a complete accent line")
	check(menu.dialog.panel.get_global_rect().get_center().distance_to(menu.dialog.get_global_rect().get_center()) < 2.0, "exported notification is centered after its entrance")
	await screenshot("export-menu-dialog")
	menu.dialog.dismiss()
	await wait_ui()
	menu.confirm("Прерывание анимации", "Закрытие во время появления.", [])
	await create_timer(0.06).timeout
	menu.dialog.dismiss()
	await wait_ui()
	check(menu.dialog == null and not menu.is_menu_open(), "closing a notification during its entrance restores input")
	menu.open_menu(0)
	await wait_ui()
	check(menu.main_panel.is_visible_in_tree() and menu.main_panel.continue_button.is_visible_in_tree(), "exported ESC controls survive scene packing")
	await screenshot("export-menu-esc")
	menu.open_menu(1)
	await wait_ui()
	check(menu.session_panel.is_visible_in_tree() and menu.ready_button.is_visible_in_tree(), "exported lobby controls survive scene packing")
	check(menu.shell.shade.color.a >= 0.7, "lobby backdrop is dark enough to separate text from the game")
	var member = menu.session_panel.crew.get_child(0)
	check(member is PanelContainer and member.get_theme_stylebox("panel").bg_color.a >= 0.3, "lobby roster retains its native panel background")
	await screenshot("export-menu-lobby")
	menu.force_close_menu()
	await menu.start_standalone_flow()
	await wait_ui()
	var player = get_first_node_in_group("local_player")
	check(player != null and player.crosshair.visible, "gameplay starts with its reticle visible")
	menu.open_menu(0)
	check(not player.crosshair.visible, "opening ESC immediately hides the gameplay reticle")
	await wait_ui()
	check(is_equal_approx(menu.shell.shade.color.a, menu.escape_background_opacity) and menu.escape_background_opacity >= 0.4, "exported ESC darkens the actual game without rails")
	await screenshot("export-menu-cabin-esc")
	menu.open_settings()
	await wait_ui()
	check(not player.crosshair.visible, "settings keep the gameplay reticle hidden")
	check(is_equal_approx(menu.shell.shade.color.a, menu.escape_background_opacity), "exported settings opened from ESC retain its backdrop")
	menu.force_close_menu()
	check(player.crosshair.visible, "closing ESC restores the gameplay reticle")
	menu.open_menu(1)
	await wait_ui()
	await screenshot("export-menu-cabin")
	menu.open_settings()
	await wait_ui()
	check(not current_scene.lobby_hud.lobby_panel.visible, "cabin hint stays hidden behind menu and settings")
	check(menu.shell.shade.color.a >= 0.7, "settings opened from lobby retain the dark backdrop")
	await screenshot("export-menu-cabin-settings")
	menu.force_close_menu()
	await wait_ui()
	check(current_scene.lobby_hud.lobby_panel.visible, "cabin hint returns after closing the menu")
	menu.confirm("Выход", "Проверка прицела", [])
	check(not player.crosshair.visible, "standalone confirmation hides the gameplay reticle")
	player.survival._sync(player.survival.health, 0, false, "", 0)
	check(not player.crosshair.visible, "a survival update cannot restore the reticle over a dialog")
	player.survival.set_physics_process(false)
	player.survival.dead = true
	menu.dialog.dismiss()
	await wait_ui()
	check(not player.crosshair.visible, "closing a dialog does not restore a dead player's reticle")
	player.survival.dead = false
	player.survival.set_physics_process(true)
	player.refresh_crosshair_visibility()
	print("EXPORTED MENU RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
