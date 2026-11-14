extends SceneTree
const GRAPHICS = preload("res://scripts/ui/graphics_quality.gd")
var failures := 0
var checks := 0
var settings_path := ""
var output := "res://tools/.local/display-calibration-review"

func _initialize() -> void:
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty(): output = OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
	var prefix := "user://display_calibration_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefix))
	settings_path = prefix + "/settings.json"
	ProjectSettings.set_setting("northern_lab/testing/settings_path", settings_path)
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(count := 3) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func settle(view: Control) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while is_instance_valid(view) and view.busy and Time.get_ticks_msec() < deadline:
		await process_frame
	await frames()

func capture(label: String) -> void:
	await frames()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func wait_for_menu() -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.is_in_group("main_menu"): return
		await process_frame

func run() -> void:
	await frames()
	root.size = Vector2i(1280, 720)
	var menu := root.get_node("GameMenu")
	menu._settings_data = menu.default_settings_data()
	menu._settings_data.Graphics = GRAPHICS.DEFAULTS.duplicate()
	menu._settings_data.GraphicsPresetRevision = GRAPHICS.PRESET_REVISION
	menu.get_node("GraphicsQuality").apply(menu._settings_data.Graphics)
	check(menu.needs_display_calibration(), "fresh profile requires calibration")
	change_scene_to_file("res://scenes/ui/startup.tscn")
	await frames(30)
	var view = menu._display_calibration
	await settle(view)
	check(is_instance_valid(view) and view.startup and view.step == 0, "startup opens the first full calibration screen")
	check(get_nodes_in_group("main_menu").is_empty(), "main menu is not instantiated behind calibration")
	check(not FileAccess.file_exists(settings_path), "entering calibration does not mark it complete")
	view.go_back()
	check(menu.is_display_calibration_open() and menu.needs_display_calibration(), "first-run calibration cannot be skipped by Back")
	check(menu.is_menu_open(), "calibration blocks gameplay and other menu shortcuts")
	var clean_text := true
	for label: Label in view.find_children("*", "Label", true, false):
		clean_text = clean_text and not label.text.contains("/ 03") and not label.text.is_valid_int()
	check(clean_text, "calibration has no stage counter or technical numbers")
	check(view._patterns[0].get_width() == 1536 and view._patterns[1].get_width() == 1536, "both reference screens contain three aligned emblems")
	check(view._hint.text == "Левый символ не виден, средний едва заметен, правый хорошо виден.", "one short hint explains the three emblems")
	check(view._slider.has_focus() and menu.menu_root.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED, "wizard owns focus while the underlying menu is disabled")
	check(view._next.find_next_valid_focus() == view._slider, "keyboard navigation wraps within calibration")
	await capture("01-white")
	view._slider.value = 95
	await frames()
	check(view._environment.adjustment_enabled and view._environment.adjustment_color_correction != null, "white calibration drives the real Environment correction")
	view.advance()
	view.advance()
	view.go_back()
	view.reset_current()
	check(view.busy and view._next.disabled and not view._slider.editable, "step motion blocks repeated navigation and editing")
	await settle(view)
	check(view._content.modulate.a == 1.0 and view._footer.modulate.a == 1.0 and not view._next.disabled, "step entrance settles fully and restores controls")
	check(view.step == 1 and view._heading.text == "ТЁМНЫЕ УЧАСТКИ", "Next replaces the white screen with the black screen")
	view._slider.value = -4
	view._slider.value = -10
	await frames()
	var reference: Image = view._patterns[1].get_image()
	var sample := Vector2i.ZERO
	var peak := 0.0
	for y in 512:
		for x in 512:
			var value := reference.get_pixel(x, y).r
			if value > peak:
				peak = value
				sample = Vector2i(x, y)
	var rendered: Image = view._viewport.get_texture().get_image()
	var left := rendered.get_pixelv(sample).r
	var middle := rendered.get_pixelv(sample + Vector2i(512, 0)).r
	var right := rendered.get_pixelv(sample + Vector2i(1024, 0)).r
	check(left < .005 and middle > left and right > middle * 2.0, "rendered black calibration can hide the left emblem while retaining the middle and right")
	view._slider.value = -4
	await capture("02-black")
	view.go_back()
	await settle(view)
	check(view.step == 0 and view._slider.value == 95, "Back preserves the earlier white point")
	view.advance()
	await settle(view)
	view.advance()
	await settle(view)
	check(view.step == 2 and view._surface.albedo_texture == view._patterns[2], "overall brightness uses a neutral tonal ramp instead of photos")
	view._slider.value = 110
	await capture("03-brightness")
	for dimensions in [Vector2i(1280, 720), Vector2i(2560, 1080)]:
		root.size = dimensions
		await frames(5)
		var screen: Rect2 = view.get_global_rect()
		check(screen.encloses(view._slider.get_global_rect()) and screen.encloses(view._next.get_global_rect()) and screen.encloses(view._preview.get_global_rect()), "calibration remains contained at %s" % dimensions)
		await capture("layout-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1280, 720)
	check(view.draft.Gamma == 110 and is_equal_approx(view._environment.adjustment_brightness, 1.0), "midtone calibration preserves exposure and adjusts the real tone curve")
	view.advance()
	await settle(view)
	check(view.step == 3 and view._hud_preview.visible and not view._preview.visible, "HUD calibration is a separate screen")
	view._slider.value = 5
	await capture("04-hud")
	check(view.draft.HUDMargin == 5 and view._hud_preview.margin_percent == 5, "HUD slider updates safe-area preview")
	var safe: Rect2 = preload("res://scripts/ui/hud_layout.gd").safe_rect(Vector2(1920, 1080), 5)
	check(safe.position == Vector2(96, 54) and safe.get_center() == Vector2(960, 540), "HUD safe area insets edges and preserves the aiming center")
	check(not FileAccess.file_exists(settings_path), "unfinished steps have not persisted the completion marker")
	view.advance()
	await wait_for_menu()
	await frames()
	check(not menu.needs_display_calibration() and not menu.is_display_calibration_open(), "Save completes calibration and closes its screen")
	check(current_scene.is_in_group("main_menu"), "main menu appears only after calibration completes")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	check(saved.DisplayCalibrationVersion == 1 and saved.Graphics.DisplayWhitePoint == 95 and saved.Graphics.DisplayBlackPoint == -4 and saved.Graphics.Gamma == 110 and saved.Graphics.HUDMargin == 5, "display values, HUD margin and completion version are saved")
	check(menu.get_node("GraphicsQuality").values.DisplayBlackPoint == -4, "gameplay quality service receives the saved calibration")
	menu._settings_data = menu.load_settings_data()
	change_scene_to_file("res://scenes/ui/startup.tscn")
	await wait_for_menu()
	await frames()
	check(not menu.is_display_calibration_open() and current_scene.is_in_group("main_menu"), "next launch skips completed calibration")
	menu.open_settings()
	await frames(30)
	var settings = menu.settings_panel
	settings.select_category(0)
	var button := settings.find_child("DisplayCalibrationButton", true, false) as Button
	check(button != null, "Screen settings expose the calibration entry")
	check(settings.rows.find_child("Brightness", true, false) == null and settings.rows.find_child("Gamma", true, false) == null, "Screen settings do not duplicate calibration sliders")
	button.pressed.emit()
	await frames(25)
	view = menu._display_calibration
	await settle(view)
	check(is_instance_valid(view) and not view.startup and view.draft.Gamma == 110 and view.draft.HUDMargin == 5, "settings reopen the complete wizard with saved values")
	view._slider.value = 105
	view.go_back()
	await settle(view)
	check(not menu.is_display_calibration_open() and menu._settings_data.Graphics.DisplayWhitePoint == 95, "cancelling recalibration leaves saved values intact")
	check(not settings.has_changes(), "cancelled calibration does not dirty settings")
	check(menu.menu_root.focus_behavior_recursive != Control.FOCUS_BEHAVIOR_DISABLED, "closing calibration restores the settings focus tree")
	settings.select_category(1)
	settings.rows.get_child(0).get_child(1).pressed.emit()
	check(settings.draft.Graphics.DisplayBlackPoint == -4 and settings.draft.Graphics.DisplayWhitePoint == 95 and settings.draft.Graphics.Gamma == 110 and settings.draft.Graphics.HUDMargin == 5, "hardware recommendations preserve the display calibration")
	settings.select_category(0)
	settings.reset_category()
	check(settings.draft.Graphics.Gamma == 110 and settings.draft.Graphics.HUDMargin == 5 and settings.draft.Graphics.DisplayBlackPoint == -4, "resetting Screen settings preserves separate calibration")
	var before: Dictionary = menu._settings_data.duplicate(true)
	menu.open_display_calibration(false)
	await frames()
	view = menu._display_calibration
	await settle(view)
	var old_motion: bool = NorthernMenuStyle.reduced_motion
	NorthernMenuStyle.reduced_motion = true
	for index in 3:
		view.advance()
		await settle(view)
	check(view.step == 3 and view._hud_preview.modulate.a == 1.0 and not view.busy, "reduced-motion transitions include the full HUD preview")
	view._slider.value = 8
	view.reset_current()
	check(view._slider.value == 0 and view.draft.Gamma == 110, "Reset changes only the current calibration step")
	view._slider.value = 8
	ProjectSettings.set_setting("northern_lab/testing/settings_path", settings_path + "/blocked.json")
	view.advance()
	await frames()
	check(menu.is_display_calibration_open() and not view.busy and menu._settings_data == before, "failed save keeps calibration open and rolls back applied settings")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	check(on_disk.Graphics.HUDMargin == 5, "failed save preserves the previous settings file")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", settings_path)
	for index in 3:
		view.go_back()
		await settle(view)
	view.go_back()
	await settle(view)
	NorthernMenuStyle.reduced_motion = old_motion
	check(not menu.is_display_calibration_open() and menu._settings_data == before, "cancelling after a save failure restores the normal settings flow")
	var defaults := GRAPHICS.DEFAULTS
	check(is_equal_approx(GRAPHICS.display_curve_value(.5, defaults), .5), "neutral calibration preserves the existing tone curve")
	var brighter: Dictionary = defaults.duplicate()
	brighter.DisplayBlackPoint = 10
	check(GRAPHICS.display_curve_value(.05, brighter) > GRAPHICS.display_curve_value(.05, defaults), "black point changes real shadow values")
	brighter.DisplayWhitePoint = 90
	check(GRAPHICS.display_curve_value(.95, brighter) == 1.0, "white point changes highlight clipping")
	menu.force_close_menu()
	if current_scene != null: current_scene.queue_free()
	current_scene = null
	await frames(5)
	print("DISPLAY CALIBRATION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
