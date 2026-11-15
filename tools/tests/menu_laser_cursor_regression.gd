extends SceneTree
## Run headless for input/lifecycle, or graphically for shader/render checks.
var failures: Array[String] = []
var clicks := 0
var cursor: CanvasLayer
var button: Button

func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://laser_cursor_settings.json")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures.append(label)

func move_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	root.push_input(event, true)

func mouse_button(pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event, true)

func wait_frames(count: int = 3) -> void:
	for index in count:
		await process_frame

func run() -> void:
	await process_frame
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(960, 540)
	root.disable_3d = true
	var menu := root.get_node("GameMenu")
	cursor = menu.get_node("MenuLaserCursor")
	check(cursor != null, "global menu owns exactly one laser cursor")
	NorthernMenuStyle.install_cursor(menu)
	check(menu.get_node("MenuLaserCursor") == cursor, "repeated installation is idempotent")
	menu.menu_root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Programmatic test windows may be intentionally hidden/unfocused.
	cursor._focused = true
	cursor._mouse_inside = true
	var stage := CanvasLayer.new()
	stage.layer = 110
	root.add_child(stage)
	var background := ColorRect.new()
	background.size = Vector2(960, 540)
	background.color = Color("10171e")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(background)
	button = Button.new()
	button.position = Vector2(160, 180)
	button.size = Vector2(300, 64)
	button.text = "NORTHERNLAB  /  CONTINUE"
	button.pressed.connect(func(): clicks += 1)
	stage.add_child(button)
	move_pointer(Vector2(600, 300))
	await wait_frames()
	check(cursor._animated and cursor._light.visible, "visible menu activates the optical pointer")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "cursor never changes the caller's mouse mode")
	check(cursor._light.mouse_filter == Control.MOUSE_FILTER_IGNORE, "optical overlay cannot intercept GUI input")
	for index in 8:
		move_pointer(Vector2(600 - index * 20, 300 - index * 8))
		await process_frame
	var visible_trail := false
	for ghost in cursor._trail:
		visible_trail = visible_trail or ghost.visible
	check(visible_trail, "movement leaves a short optical afterimage")
	check(cursor._light.size.x >= 128.0 * 1.1, "menu pointer uses the enlarged visual size")
	var continuous := false
	for ghost in cursor._trail:
		if ghost.visible and ghost.material.get_shader_parameter("segment_length") > 0.0:
			continuous = true
	check(continuous, "movement draws connected light segments instead of separated dots")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tools/.local/laser-review")
		root.get_texture().get_image().save_png("res://tools/.local/laser-review/cursor-trail.png")

	var center := Vector2(310, 212)
	move_pointer(center)
	await wait_frames()
	check((cursor._light.position + cursor._light.size * 0.5).distance_to(center) < 0.01, "luminous core exactly matches the GUI click position")
	await create_timer(0.45).timeout
	check(cursor._hover > 0.9, "enabled button smoothly strengthens the laser")
	var trail_settled := true
	for ghost in cursor._trail:
		trail_settled = trail_settled and not ghost.visible
	check(trail_settled, "afterimage disappears when the mouse stops")
	mouse_button(true, center)
	await create_timer(0.08).timeout
	check(cursor._held and cursor._press > 0.5, "held press gently contracts the light")
	mouse_button(false, center)
	await wait_frames(1)
	check(clicks == 1 and cursor._click_age < 0.12, "native button receives one click and laser reacts on release")
	await create_timer(0.7).timeout
	check(cursor._press < 0.01 and cursor._click_age > 0.5, "click response settles without a permanent flash")
	button.disabled = true
	await create_timer(0.45).timeout
	check(cursor._hover < 0.1, "disabled buttons do not acquire an active hover")
	button.disabled = false
	NorthernMenuStyle.reduced_motion = true
	for index in 5:
		move_pointer(Vector2(600 + index * 10, 300))
		await process_frame
	var quiet: bool = cursor._history.is_empty()
	for ghost in cursor._trail:
		quiet = quiet and not ghost.visible
	check(quiet, "reduced-motion preference removes afterimages")
	NorthernMenuStyle.reduced_motion = false
	paused = true
	move_pointer(Vector2(650, 320))
	await wait_frames()
	check(cursor._animated and (cursor._light.position + cursor._light.size * 0.5).distance_to(Vector2(650, 320)) < 0.01, "paused gameplay does not freeze the menu pointer")
	paused = false
	# Dummy DisplayServer cannot change OS mouse mode. Exercise with real driver.
	if DisplayServer.get_name() != "headless":
		for mode in [Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_HIDDEN]:
			Input.mouse_mode = mode
			await wait_frames()
			check(not cursor._animated and not cursor._light.visible, "capture/loading mouse mode %d hides all optical effects" % mode)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await wait_frames()
	cursor._on_mouse_exited()
	check(not cursor._animated, "leaving the window immediately clears the software pointer")
	cursor._on_mouse_entered()
	await wait_frames()
	cursor._on_window_focus_exited()
	await wait_frames()
	check(not cursor._animated, "unfocused windows cannot keep an animated laser")
	cursor._on_window_focus_entered()
	NorthernMenuStyle.touch_navigation = true
	await wait_frames()
	check(not cursor._animated, "touch navigation hides the laser")
	NorthernMenuStyle.touch_navigation = false
	menu.menu_root.hide()
	await wait_frames()
	check(not cursor._animated, "closing menu restores native fallback without an orphan overlay")
	menu.menu_root.show()
	await wait_frames()
	check(cursor._animated and cursor._history.size() <= 1, "reopening begins without stale click or movement effects")
	if DisplayServer.get_name() != "headless":
		move_pointer(Vector2(650, 320))
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		DirAccess.make_dir_recursive_absolute("res://tools/.local/laser-review")
		capture.save_png("res://tools/.local/laser-review/cursor-dark.png")
		var core := capture.get_pixel(650, 320)
		var nearby := capture.get_pixel(654, 320)
		var vertical := capture.get_pixel(650, 324)
		check(core.r > 0.8 and core.g > 0.6 and nearby.r > nearby.g, "real renderer draws a warm white core and red bloom")
		check(absf(nearby.r - vertical.r) < 0.03, "glow is radial without a horizontal flare line")
		check(absf(capture.get_pixel(664, 320).r - capture.get_pixel(680, 320).r) < 0.015, "compact glow leaves no broad tinted disk around pointer")
		background.color = Color("e8e6df")
		await wait_frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/laser-review/cursor-light.png")
		var pale := root.get_texture().get_image()
		check(pale.get_pixel(650, 320).r > 0.9, "outline-free pointer keeps its bright core on pale surfaces")
		root.content_scale_size = Vector2i(1280, 720)
		root.size = Vector2i(1280, 720)
		await wait_frames()
		move_pointer(Vector2(640, 360))
		await wait_frames()
		check((cursor._light.position + cursor._light.size * 0.5).distance_to(Vector2(640, 360)) < 0.01, "viewport resize preserves exact pointer hotspot")

	stage.queue_free()
	menu.force_close_menu()
	NorthernMenuStyle.uninstall_cursor()
	check(not is_instance_valid(cursor), "uninstall frees overlay and native cursor resources")
	NorthernMenuStyle.install_cursor(menu)
	check(menu.get_node_or_null("MenuLaserCursor") != null, "cursor can be reinstalled after a full teardown")
	print("MENU LASER RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
