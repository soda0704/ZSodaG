extends SceneTree
## Real settings state, interrupted transitions and input ownership.
var failures: Array[String] = []
func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://motion_settings_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://motion_controls_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func run() -> void:
	var menu := root.get_node("GameMenu")
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(.5).timeout
	menu.open_settings()
	await create_timer(.6).timeout
	var settings: NorthernSettingsMenu = menu.settings_panel
	check(menu.shell.header.get_child_count() == 0 and settings.navigation.get_child_count() == 4, "settings use four compact sidebar sections, not header buttons")
	settings._request_category(1)
	var first_tab: Control = settings.navigation.get_child(1)
	var immediate_target: float = settings.navigation.position.y + first_tab.position.y + (first_tab.size.y - settings._category_marker.size.y) * .5
	check(absf(settings._marker_target - immediate_target) < .1, "category marker retargets in the click frame without a deferred-frame delay")
	await create_timer(.02).timeout
	settings._request_category(2)
	await create_timer(.02).timeout
	settings._request_category(3)
	await create_timer(.5).timeout
	check(settings.category == 3 and settings.detail.modulate.a > .99, "rapid section changes finish on the last requested section")
	check(settings.navigation.get_child(3).button_pressed and not settings.navigation.get_child(0).button_pressed, "selected section stays distinct from the others")
	var selected: Control = settings.navigation.get_child(3)
	var marker_target: float = settings.navigation.position.y + selected.position.y + (selected.size.y - settings._category_marker.size.y) * .5
	check(absf(settings._category_marker.position.y - marker_target) < .1, "rapid category switches leave the shared marker centered on the last category")
	settings.navigation.get_child(3).set_pressed_no_signal(false)
	settings._request_category(3)
	check(settings.navigation.get_child(3).button_pressed, "clicking the current section cannot turn off its selected state")
	NorthernMenuStyle.keyboard_navigation = true
	settings._request_category(2)
	check(settings.category == 2 and is_equal_approx(settings.detail.modulate.a, 1.0), "keyboard section selection is immediate")
	NorthernMenuStyle.keyboard_navigation = false
	settings._request_category(0)
	await create_timer(.4).timeout
	settings._set_value("ReduceMenuMotion", true, false)
	check(settings.apply(false) and NorthernMenuStyle.reduced_motion, "reduced menu motion is applied and persisted through normal settings")
	menu.confirm("Проверка", "Сниженное движение", [])
	await create_timer(.05).timeout
	check(menu.dialog.get_node("Center").scale.is_equal_approx(Vector2.ONE) and is_zero_approx(menu.dialog.get_node("Center").position.y), "reduced motion keeps modal geometry still while fading")
	NorthernMenuStyle.keyboard_navigation = true
	menu.dialog.dismiss()
	await process_frame
	check(menu.dialog == null, "keyboard dismissal releases the modal without an animation delay")
	menu.force_close_menu()
	current_scene = null
	main.queue_free()
	await process_frame
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var player := Node3D.new()
	world.add_child(player)
	player.add_to_group("local_player")
	NorthernMenuStyle.reduced_motion = false
	NorthernMenuStyle.keyboard_navigation = false
	menu.open_menu()
	await create_timer(.04).timeout
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	await process_frame
	check(not menu.is_menu_open(), "Escape interrupts the entrance and returns to gameplay immediately")
	NorthernMenuStyle.keyboard_navigation = false
	print("MENU MOTION RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
