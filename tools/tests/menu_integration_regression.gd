extends SceneTree
## Real native UI, input transactions and gameplay-facing contracts.
var failures: Array[String] = []
var capture := false

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://menu_integration_settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://menu_integration_controls.cfg")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://menu_integration_save.cfg")
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func wait_ui() -> void:
	await create_timer(0.65).timeout

func screenshot(name: String) -> void:
	if capture and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/menu-" + name + ".png")

func mouse_motion(at: Vector2, pressed: bool = false) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)

func mouse_button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)

func run() -> void:
	await process_frame
	var menu = root.get_node("GameMenu")
	var controls = menu.get_node("ControlSettings")
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await wait_ui()
	check(main.name == "Menu" and main.is_in_group("main_menu"), "approved Menu is the application entry point")
	check(main.selector == null, "home does not select a character before new game")
	check(main.background_video.stream != null and main.background_video.is_playing(), "main background is a playing video")
	check(main.background_video.get_video_texture().get_size() == Vector2(1920, 1080), "background uses the lighter 1080p playback asset")
	check(main.background_video.bus == &"Music", "background audio retains Music routing")
	check(main.shell.shade.get_index() < main.shell.content.get_index(), "backdrop shading draws behind text and controls")
	await screenshot("native-home")
	main._on_single_player_pressed()
	await wait_ui()
	check(main.current_view == "checkpoint", "new game selects an expedition slot first")
	check(main.shell.content.get_child(0).get_node("Slots").item_count == 3, "three authored expedition slots are available")
	main._new_expedition()
	if menu.dialog != null:
		menu.dialog.dismiss(main.show_character.bind("solo"))
		await wait_ui()
	check(main.current_view == "character", "new game opens character selection")
	check(main.selector.option.item_count == 2, "both production characters are selectable")
	main.selector.option.select(1)
	main.selector.option.item_selected.emit(1)
	check(menu.get_character_variant_id() == 1 and main.selector.model.scene_file_path.contains("tactical_b"), "character selection persists and displays the production model")
	check(main.selector.preview.world_3d != root.world_3d and main.selector.preview.transparent_bg, "character render is isolated and transparent")
	check(main.selector.get_parent() == main.shell and main.selector.get_index() < main.shell.top_rail.get_index() and main.selector.get_index() < main.shell.bottom_rail.get_index(), "full-height character is rendered below the black menu rails")
	await screenshot("native-character")
	main._show_home()
	menu.open_settings()
	await wait_ui()
	var settings = menu.settings_panel
	check(settings != null and not settings.has_changes(), "settings open without a spurious pending change")
	var original: Dictionary = menu._settings_data.duplicate(true)
	settings.select_category(2)
	await process_frame
	for spec in NorthernSettingsMenu.AUDIO:
		check(settings.rows.find_child(spec[0], true, false) is NorthernMenuValue, spec[0] + " is connected to a numeric control")
	var volume = settings.rows.find_child("MasterVolume", true, false)
	var before: float = volume.value
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	volume._number_input(click)
	click.pressed = false
	volume._number_input(click)
	check(is_equal_approx(volume.value, before), "clicking a numeric value alone does not increment it")
	if DisplayServer.get_name() != "headless":
		await process_frame
		var point: Vector2 = volume.number.get_global_rect().get_center()
		mouse_motion(point)
		mouse_button(point, true)
		mouse_button(point, false)
		check(is_equal_approx(volume.value, before), "real GUI click leaves the numeric value unchanged")
		mouse_button(point, true)
		check(volume._dragging, "real GUI press starts numeric dragging")
		var delta_x := 65 if before < 50 else -65
		mouse_motion(point + Vector2(delta_x, 0), true)
		mouse_button(point + Vector2(delta_x, 0), false)
		check(not is_equal_approx(volume.value, before), "real LMB drag changes the numeric value")
		check(menu._settings_data == original, "real LMB drag preserves applied settings until Apply")
	var target_volume := 31.0 if not is_equal_approx(before, 31.0) else 49.0
	volume.set_value(target_volume)
	check(is_equal_approx(settings.draft.MasterVolume, target_volume) and menu._settings_data == original, "editing remains staged until Apply")
	check(not settings.apply_button.disabled, "Apply becomes available for pending changes")
	settings.select_category(1)
	await wait_ui()
	if DisplayServer.get_name() != "headless":
		check(settings.scroll.get_v_scroll_bar().max_value > settings.scroll.size.y, "quality settings scroll inside a stable screen")
	else:
		check(settings.scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "quality uses an internal scroll container; geometry is checked graphically")
	await screenshot("native-quality")
	settings.select_category(3)
	var old_bindings: Dictionary = controls.current_bindings()
	settings._wait_for_key("journal")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	key.pressed = true
	settings._input(key)
	check(controls.current_bindings() == old_bindings, "binding changes also wait for Apply")
	settings.apply(false)
	check(is_equal_approx(menu._settings_data.MasterVolume, target_volume) and int(menu.load_settings_data().MasterVolume) == int(target_volume), "Apply persists native settings")
	check(controls.current_bindings().journal == {"key": KEY_K}, "Apply commits keyboard bindings")
	check(not settings.has_changes() and settings.apply_button.disabled, "Apply clears pending changes")
	settings._set_value("MasterVolume", 17, false)
	settings.request_back()
	await wait_ui()
	check(menu.dialog != null and menu.dialog.actions.get_child(menu.dialog.actions.get_child_count() - 1).text == "НАЗАД", "pending-change dialog keeps Back rightmost")
	menu.dialog.dismiss(func(): settings.back_requested.emit())
	await wait_ui()
	check(not menu.is_menu_open() and int(menu._settings_data.MasterVolume) == int(target_volume), "discard returns to Menu without applying drafts")
	menu.confirm("Проверка", "Проверка окна подтверждения", [])
	await wait_ui()
	await screenshot("native-dialog")
	menu.dialog.dismiss()
	await wait_ui()
	check(not menu.is_menu_open(), "dismissing a main-menu dialog restores input ownership")
	main.queue_free()
	current_scene = null
	await process_frame
	var world := Node3D.new()
	world.name = "TestWorld"
	root.add_child(world)
	current_scene = world
	var player := Node3D.new()
	player.add_to_group("local_player")
	world.add_child(player)
	menu.open_menu(menu.MenuView.MAIN)
	await wait_ui()
	check(menu.main_panel.name == "ESC_MENU" and not menu.shell.top_rail.visible and not menu.shell.bottom_rail.visible, "ESC_MENU has no edge rails")
	check(menu.main_panel.continue_button.get_parent().get_child_count() == 3, "ESC contains exactly Continue, Settings and Main menu")
	check(not paused and menu.shell.video == null, "ESC keeps the actual world running and has no replacement backdrop")
	check(is_equal_approx(menu.shell.shade.color.a, menu.escape_background_opacity) and menu.escape_background_opacity >= 0.4, "ESC darkens the live game for legible text")
	await screenshot("native-esc")
	menu.open_settings()
	await wait_ui()
	check(is_equal_approx(menu.shell.shade.color.a, menu.escape_background_opacity), "settings opened from ESC retain its dark backdrop")
	menu.settings_panel.request_back()
	await wait_ui()
	menu.open_menu(menu.MenuView.SESSION)
	await wait_ui()
	check(menu.session_panel.name == "LOBBY_MENU", "native LOBBY_MENU is wired to the session view")
	check(menu.ready_button.disabled, "readiness cannot be set before a session exists")
	var steam = root.get_node("SteamNetwork")
	var lobby = root.get_node("CoopLobby")
	steam.is_host = true
	lobby.session_active = true
	lobby.ready_states = {1: false, 2: false}
	menu.refresh_ready_ui()
	check(menu.start_game_button.visible and menu.start_game_button.disabled, "host launch is gated by authoritative readiness")
	lobby.ready_states = {1: true, 2: true}
	menu.refresh_ready_ui()
	check(not menu.start_game_button.disabled, "host launch becomes available when everyone is ready")
	await screenshot("native-lobby")
	steam.is_host = false
	menu.refresh_ready_ui()
	check(not menu.start_game_button.visible, "guest cannot launch the expedition")
	lobby.session_active = false
	lobby.ready_states.clear()
	menu.open_settings()
	await wait_ui()
	menu.settings_panel.request_back()
	await wait_ui()
	check(menu._current_view == menu.MenuView.SESSION, "settings opened from lobby return to lobby")
	menu.close_menu()
	await wait_ui()
	check(not menu.is_menu_open() and not paused, "closing ESC/lobby returns control without pausing the world")
	print("MENU INTEGRATION RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
