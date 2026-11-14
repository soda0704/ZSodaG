extends SceneTree
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://scrim_return_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://scrim_controls_%d.cfg" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settled(menu: Node, main: Node) -> void:
	await create_timer(.8).timeout
	while menu.shell.busy or main.shell.busy: await process_frame

func run() -> void:
	await process_frame
	var menu := root.get_node("GameMenu")
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await settled(menu, main)
	for reduced in [false, true]:
		NorthernMenuStyle.reduced_motion = reduced
		for keyboard in [false, true]:
			NorthernMenuStyle.keyboard_navigation = keyboard
			menu.open_settings()
			await settled(menu, main)
			menu.settings_panel.request_back()
			var minimum := 1.0
			var timeout := Time.get_ticks_msec() + 2500
			while Time.get_ticks_msec() < timeout:
				await process_frame
				await RenderingServer.frame_post_draw
				minimum = minf(minimum, main.shell.shade.modulate.a)
				if not menu.menu_root.visible and not main.shell.busy: break
			check(minimum >= .999, "return keeps the main backdrop shaded: reduced=%s keyboard=%s" % [reduced, keyboard])
			check(not menu.menu_root.visible and main.shell.content.visible, "return restores main menu controls")
	NorthernMenuStyle.keyboard_navigation = false
	NorthernMenuStyle.reduced_motion = false
	menu.force_close_menu()
	main.queue_free()
	current_scene = null
	await process_frame
	print("SCRIM RETURN FAILURES ", failures)
	quit(1 if failures else 0)
