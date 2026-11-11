extends SceneTree
var checks := 0
var failures := 0
var console: CanvasLayer
func _initialize():
	var prefix := "user://console_controls_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	create_timer(110).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func click(control: Control):
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate();event.pressed = false
	Input.parse_input_event(event)
	await process_frame
func run():
	Engine.max_fps = 60;root.size = Vector2i(1280,720);root.content_scale_size = root.size
	var base: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene = base
	for frame in 30: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor: GamePlayer = get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false)
	base.get_node("BaseGameplayController").set_process(false)
	console = root.get_node("DeveloperConsole")
	console.set_open(true)
	# The first open reflows the output, tabs and scroll area over several frames.
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	var dashboard = console.command_controls
	check(dashboard.panel.is_visible_in_tree() and not console.get_node("Panel/Box/Commands").visible, "console opens the button panel by default")
	var covered := true
	for command: String in console._all_commands():
		covered = covered and (dashboard.actions.has(command) or (dashboard.controls.has(command.get_slice(" ",0)) and not " speed " in command))
	check(covered, "every registered command is represented by an action or explicit toggle")
	var weather = base.get_node("SnowExterior/Blizzard")
	var toggle_position: Vector2 = dashboard.controls["/blizzard"].global_position
	await click(dashboard.controls["/blizzard"])
	check(not weather.enabled, "a real mouse click switches off the local blizzard")
	check(dashboard.controls["/blizzard"].global_position.is_equal_approx(toggle_position), "the first command result never moves controls under the pointer")
	await click(dashboard.controls["/blizzard"])
	check(weather.enabled, "a second mouse click restores the local blizzard")
	console.execute("/clear")
	for frame in 3:await process_frame
	check(dashboard.controls["/blizzard"].global_position.is_equal_approx(toggle_position), "clearing the log keeps the controls in place")
	check(not dashboard.controls.has("/light_swap"), "the obsolete combined lighting toggle is absent")
	check(not console._help_text().contains("/light_swap"), "help and completion no longer advertise the removed mode")
	console.execute("/god on; /god on")
	dashboard.sync()
	check(actor.survival.debug_invincible and dashboard.controls["/god"].button_pressed, "explicit god on is idempotent and panel reads actual state")
	console.execute("/god off; /fly on; /fly on")
	dashboard.sync()
	check(actor.debug_fly and not actor.debug_across and not dashboard.controls["/god"].button_pressed, "explicit flight and god commands retain their requested state")
	console.execute("/across on; /across off; /fly off")
	check(not actor.debug_fly and not actor.debug_across, "explicit movement switches can be safely disabled")
	dashboard.panel.current_tab = 1
	await process_frame
	var rows: VBoxContainer = dashboard.pages["Игрок"]
	var row := rows.get_child(rows.get_child_count()-1)
	var spin: SpinBox = row.get_child(1)
	spin.get_line_edit().grab_focus()
	var before: String = console.entry.text
	var key := InputEventKey.new();key.keycode = KEY_2;key.unicode = 50;key.pressed = true
	Input.parse_input_event(key);await process_frame
	check(spin.get_line_edit().has_focus() and console.entry.text == before, "typing a numeric parameter is not stolen by the command line")
	spin.value = 2.5
	row.get_child(2).pressed.emit()
	check(is_equal_approx(actor.debug_speed_multiplier,2.5), "numeric parameter Apply uses the ordinary validated command")
	console.execute("/speed reset")
	dashboard.panel.current_tab = 0
	console.entry.text = "/";console.show_all_commands()
	await process_frame
	check(console.panel.get_global_rect().end.y < root.size.y and console.entry.get_global_rect().end.y < console.panel.get_global_rect().end.y, "controls and input fit the 1280 by 720 window")
	var out := OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
	if out.is_empty(): out = "res://tools/.local/lighting-review-2026-11-11"
	DirAccess.make_dir_recursive_absolute(out)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/console-controls.png")
	console.set_open(false)
	current_scene = null;base.queue_free()
	for frame in 12: await process_frame
	print("CONSOLE CONTROLS CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
