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
	var limit:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<limit:
		var menu=root.get_node("GameMenu")
		var scene=current_scene
		var ready:bool=not menu.shell.busy
		if scene!=null and scene.is_in_group("main_menu"):
			ready=ready and not scene.shell.busy
			if is_instance_valid(scene.selector):ready=ready and scene.selector._picking_ready
		if ready:break
		await process_frame

func backdrop_alpha(menu: Node, control: Control) -> float:
	var shade: ColorRect = menu.shell.shade
	var gradient: Gradient = shade.get_node("Atmosphere").texture.gradient
	var center := control.get_global_rect().get_center()
	var sample := clampf((center.x - shade.global_position.x) / maxf(shade.size.x, 1.0), 0.0, 1.0)
	return 1.0 - (1.0 - shade.color.a) * (1.0 - gradient.sample(sample).a)

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
	check(brand.get_theme_font("font").get_font_name() == "Arial Black", "exported brand preserves the original Arial Black face")
	check(main.single_player_button.get_theme_font("font").get_font_name() == "Oswald" and main.theme.default_font.get_font_name() == "Golos Text", "exported navigation and body use embedded Cyrillic fonts")
	check(brand.get_line_count() == 2 and brand.size.y <= 125, "brand keeps its two-line hierarchy")
	check(main.single_player_button.get_theme_font_size("font_size") == 21 and main.single_player_button.scale == Vector2.ONE, "compact navigation retains native font sizing without scaling text")
	await screenshot("export-menu-home")
	click(main.single_player_button)
	await wait_ui()
	check(main.current_view == "character" and is_instance_valid(main.selector), "real click in exported menu opens character selection")
	if main.current_view != "character" or not is_instance_valid(main.selector):
		quit(1)
		return
	check(main.selector.choices.size()==2 and main.shell.top_rail.visible and main.shell.bottom_rail.visible and not main.shell.header.visible and main.shell.footer.get_node("CharacterBack").is_visible_in_tree(), "character screen keeps header/footer layout and Back without captions or a separate start button")
	main.selector.choices[1].grab_focus()
	await wait_ui()
	if main.selector._highlighted != 1 or not main.selector._picking_ready:
		print("CHARACTER FOCUS DIAGNOSTIC ready=", main.selector._picking_ready, " highlighted=", main.selector._highlighted, " models=", main.selector.models.size(), " focused=", main.selector.choices[1].has_focus(), " pointer_mode=", main.selector._pointer_mode)
	check(main.selector._highlighted==1 and main.selector._picking_ready, "native focus highlights a character and body picking is ready")
	await screenshot("export-menu-character")
	main.back()
	await wait_ui()
	click(main.settings_button)
	await wait_ui()
	check(menu.is_menu_open() and menu.settings_panel.is_visible_in_tree(), "real click in exported menu opens settings")
	check(menu.settings_panel.size.x <= 1380 and menu.settings_panel.navigation.get_child_count() == 4 and menu.shell.header.get_child_count() == 0, "settings use a compact sidebar instead of header buttons")
	menu.settings_panel.select_category(1)
	await wait_ui()
	var first_row = menu.settings_panel.rows.get_child(0)
	var motion := InputEventMouseMotion.new()
	motion.position = first_row.get_global_transform_with_canvas() * (first_row.size * 0.5)
	root.push_input(motion, true)
	# Keyboard selection must not resize text or push controls outside the scroll area.
	first_row.get_child(1).grab_focus()
	await wait_ui()
	var row_rect: Rect2 = first_row.get_global_rect()
	var scroll_rect: Rect2 = menu.settings_panel.scroll.get_global_rect()
	check(first_row.scale.is_equal_approx(Vector2.ONE) and row_rect.position.x >= scroll_rect.position.x and row_rect.end.x <= scroll_rect.end.x, "focused settings stay sharp and inside both scroll edges")
	await screenshot("export-menu-settings")
	var settings = menu.settings_panel
	var column_x := -1.0
	var aligned := true
	for row in settings.rows.get_children():
		if not row is NorthernMenuSettingRow: continue
		var editor: Control = row.get_child(1)
		if column_x < 0.0: column_x = editor.position.x
		aligned = aligned and is_equal_approx(editor.position.x, column_x) and is_equal_approx(editor.size.x, settings.VALUE_COLUMN_WIDTH)
	check(aligned, "exported choices, toggles and numbers share the same value column")
	first_row.get_child(1).pressed.emit()
	check(settings.apply(false) and not settings.has_changes() and settings.apply_button.disabled, "exported recommended settings apply without a stale pending change")
	settings.request_back()
	await wait_ui()
	check(menu.dialog == null and not menu.is_menu_open(), "exported settings exit after Apply without another confirmation")
	check(main.single_player_button.is_visible_in_tree(), "closing exported settings restores the home interface")
	menu.confirm("Оформление окна", "Шрифт, подложка и действия используют тему меню.", [])
	await wait_ui()
	check(menu.dialog.actions.get_child(0).get_theme_font("font") == menu.shell.theme.default_font, "dialog actions retain the menu font outside Shell")
	check(menu.dialog.panel.size.x <= 930 and menu.dialog.panel.get_theme_stylebox("panel").bg_color.a >= .99, "notification stays compact with an isolating dark backdrop")
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
	check(backdrop_alpha(menu, menu.session_panel) >= 0.4, "lobby gradient separates text from the game")
	var member = menu.session_panel.crew.get_child(0)
	check(member is PanelContainer and member.get_theme_stylebox("panel").bg_color.a > 0.0 and member.get_theme_stylebox("panel").bg_color.a <= 0.5, "lobby roster retains its native panel background")
	await screenshot("export-menu-lobby")
	menu.force_close_menu()
	await menu.start_standalone_flow()
	await wait_ui()
	var player = get_first_node_in_group("local_player")
	check(player != null and player.crosshair.visible, "gameplay starts with its reticle visible")
	menu.open_menu(0)
	check(not player.crosshair.visible, "opening ESC immediately hides the gameplay reticle")
	await wait_ui()
	check(is_equal_approx(menu.shell.shade.color.a, menu.escape_background_opacity) and backdrop_alpha(menu, menu.main_panel) >= 0.4, "exported ESC darkens the actual game without rails")
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
	check(backdrop_alpha(menu, menu.settings_panel) >= 0.4, "settings opened from lobby retain the gradient backdrop")
	await screenshot("export-menu-cabin-settings")
	menu.force_close_menu()
	await wait_ui()
	check(not current_scene.lobby_hud.lobby_panel.visible, "solo world keeps the aircraft lobby hint hidden after closing the menu")
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
	# Release gameplay viewports and drain deferred GPU frees before renderer shutdown.
	current_scene.queue_free()
	current_scene = null
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	quit(0 if failures.is_empty() else 1)
