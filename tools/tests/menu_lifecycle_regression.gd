extends SceneTree
var failures: Array[String] = []
func _initialize():
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://menu_lifecycle_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://menu_lifecycle_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool, label: String):
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func settle(seconds := 0.7): await create_timer(seconds).timeout
func run():
	await process_frame
	var menu = root.get_node("GameMenu")
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1280,720)
	var world=Node3D.new()
	root.add_child(world)
	current_scene=world
	var player=Node3D.new()
	world.add_child(player)
	player.add_to_group("local_player")
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	menu.confirm("Проверка", "Отменить выход из игры", [])
	await settle()
	menu.dialog.dismiss()
	await settle()
	check(not menu.is_menu_open() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED, "dismissed gameplay modal returns captured mouse to the player")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	menu.confirm("Проверка", "Модальное окно поверх открытого журнала", [])
	await settle()
	menu.dialog.dismiss()
	await settle()
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE, "modal preserves visible mouse ownership of another gameplay interface")
	menu.open_menu()
	await settle()
	menu.open_settings()
	await settle()
	var settings=menu.settings_panel
	var bindings=settings.draft_bindings.duplicate(true)
	settings.select_category(2)
	var value=settings.rows.find_child("MasterVolume",true,false)
	var original_value:float=value.value
	value._dragging=true
	settings._wait_for_key("journal")
	menu.force_close_menu()
	var key=InputEventKey.new()
	key.physical_keycode=KEY_K
	key.keycode=KEY_K
	key.pressed=true
	root.push_input(key,true)
	await process_frame
	check(settings.draft_bindings==bindings, "hidden settings cannot capture a gameplay key")
	var motion=InputEventMouseMotion.new()
	motion.position=Vector2(10000,0)
	root.push_input(motion,true)
	check(not value._dragging and value.value==original_value, "hidden numeric controls release dragging and cannot steal camera motion")
	menu.open_menu()
	await settle()
	menu.shell.transition(func(): menu.force_close_menu())
	await settle(0.23)
	check(not menu.is_menu_open() and menu.shell.content.modulate.a==1 and not menu.shell.busy, "closing from transition callback cancels the obsolete entrance animation")
	await settle()
	menu.open_menu()
	await settle()
	menu.open_settings()
	await settle()
	# Applying audio must not reset a manually resized window to saved dimensions.
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1230,690)
	var quality=menu.get_node("GraphicsQuality")
	var graphics_before:Dictionary=quality.values.duplicate(true)
	menu.settings_panel._set_value("MasterVolume",37,false)
	menu.settings_panel.apply(false)
	check(not quality._render_update_pending, "audio-only Apply does not rebuild GPU effect budgets")
	await process_frame
	check(root.mode==Window.MODE_WINDOWED and root.size==Vector2i(1230,690), "audio-only Apply leaves the window and display mode intact")
	check(quality.values==graphics_before, "audio-only Apply leaves graphics unchanged")
	menu.settings_panel._set_value("VSync",not bool(menu._settings_data.VSync),false)
	menu.settings_panel.apply(false)
	check(root.mode==Window.MODE_WINDOWED and root.size==Vector2i(1230,690), "VSync-only Apply does not recreate the window")
	menu.settings_panel._set_value("Gamma",120,true)
	menu.settings_panel.apply(false)
	check(not quality._render_update_pending, "gamma calibration does not rebuild unchanged SSAO/fog/GI budgets")
	var good_path:String=menu.get_settings_path()
	var blocked_path="user://settings_block_%d" % OS.get_process_id()
	var blocker=FileAccess.open(blocked_path,FileAccess.WRITE)
	blocker.store_string("keep"); blocker.close()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",blocked_path.path_join("settings.json"))
	var old_applied:Dictionary=menu._settings_data.duplicate(true)
	menu.settings_panel._set_value("MasterVolume",19,false)
	check(not menu.settings_panel.apply(false) and menu.settings_panel.has_changes() and not menu.settings_panel.apply_button.disabled, "failed settings write keeps retry available instead of reporting success")
	check(menu._settings_data==old_applied and FileAccess.get_file_as_string(blocked_path)=="keep", "failed write preserves applied preferences and the blocking file")
	if menu.dialog!=null: menu.dialog.dismiss()
	await settle()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",good_path)
	check(menu.settings_panel.apply(false) and not menu.settings_panel.has_changes(), "retry after a write failure publishes the staged preferences")
	DirAccess.remove_absolute(blocked_path)
	settings = menu.settings_panel
	var good_controls_path: String = settings.controls.path()
	var controls_blocker := "user://controls_block_%d" % OS.get_process_id()
	blocker = FileAccess.open(controls_blocker, FileAccess.WRITE)
	blocker.store_string("keep"); blocker.close()
	ProjectSettings.set_setting("northern_lab/testing/controls_path", controls_blocker.path_join("controls.cfg"))
	var old_bindings: Dictionary = settings.controls.current_bindings()
	settings.draft_bindings.journal = {"key": int(KEY_K)}
	check(not settings.apply(false) and settings.controls.current_bindings() == old_bindings and settings.has_changes(), "failed binding write preserves live input and the staged retry")
	if menu.dialog != null: menu.dialog.dismiss()
	await settle()
	ProjectSettings.set_setting("northern_lab/testing/controls_path", good_controls_path)
	check(settings.apply(false) and settings.controls.current_bindings().journal == {"key": int(KEY_K)} and not settings.has_changes(), "binding retry saves and applies the staged key")
	DirAccess.remove_absolute(controls_blocker)
	menu.force_close_menu()
	world.queue_free()
	current_scene=null
	await process_frame
	var main=load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene=main
	await settle()
	menu.open_settings()
	await settle()
	check(not main.shell.footer.is_visible_in_tree(), "main-menu footer is hidden behind the settings overlay")
	menu.settings_panel.request_back()
	await settle()
	check(not menu.is_menu_open() and main.is_ancestor_of(root.gui_get_focus_owner()), "returning from settings restores focus to the main menu")
	print("MENU LIFECYCLE RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
