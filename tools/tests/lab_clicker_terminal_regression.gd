extends SceneTree
var failures := 0
var checks := 0
var base: Node3D
var state: BaseGameplayController
var terminal: DayTwoTerminal
var player: GamePlayer
var save_path: String
func _initialize() -> void:
	save_path = "user://clicker_test_%d.cfg" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
func settle() -> void:
	for i in 8: await physics_frame
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	root.push_input(event, true)
func canvas_point(ui_point: Vector2) -> Vector2:
	var bounds: Vector4 = terminal._screen_material.get_shader_parameter("screen_atlas_rect")
	var normalized := ui_point / Vector2(terminal.screen_viewport.size)
	var uv := Vector2(bounds.x + normalized.y * (bounds.z - bounds.x), bounds.y + normalized.x * (bounds.w - bounds.y))
	for triangle in terminal._screen_triangles:
		var a: Vector2 = triangle[1]
		var b: Vector2 = triangle[3]
		var c: Vector2 = triangle[5]
		var denominator := (b - a).cross(c - a)
		if absf(denominator) < 0.000001: continue
		var wb := (uv - a).cross(c - a) / denominator
		var wc := (b - a).cross(uv - a) / denominator
		if wb < 0 or wc < 0 or wb + wc > 1: continue
		var local: Vector3 = triangle[0] * (1 - wb - wc) + triangle[2] * wb + triangle[4] * wc
		var world := terminal._display_mesh.global_transform * local
		return terminal.app_camera.unproject_position(world) * root.get_visible_rect().size / terminal.app_camera.get_viewport().get_visible_rect().size
	return Vector2(-100, -100)
func click_ui(point: Vector2) -> void:
	var canvas := canvas_point(point)
	print("MOUSE MAP ", point, " -> ", canvas, " -> ", terminal.screen_point(canvas))
	mouse(canvas, true)
	mouse(canvas, false)
func run() -> void:
	Engine.max_fps = 60
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1440, 900))
	base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await settle()
	state = base.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false
	terminal = base.get_node("Floor_0_Base_Blockout/DayTwoTaskTerminal")
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	state._broadcast_snapshot({"day_index": 2, "main_breaker_on": true, "fuel_delivered": true, "fuel_liters": 60.0, "quest_stage": 3}, false)
	var facing := terminal.screen.global_basis.z
	facing.y = 0.0
	player.teleport_authoritative(terminal.global_position + facing.normalized() * 2.0, terminal.global_rotation.y)
	player.camera.look_at(terminal.screen.global_position)
	await settle()
	terminal.begin_terminal_interaction()
	await settle()
	check(terminal.active and get_first_node_in_group("terminal_ui") == terminal and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "opens existing physical screen and captures input")
	check(terminal._screen_triangles.size() > 0, "imported display UV geometry cached")
	print("SCREEN TRIANGLES ", terminal._screen_triangles.size())
	click_ui(Vector2(330, 26))
	await settle()
	check(terminal.ui.app_open, "mouse selects app through original imported mesh UVs")
	var before_click := state.clicker.samples
	click_ui(Vector2(255, 300))
	await settle()
	check(state.clicker.samples == before_click + 1, "real 3D tube click reaches UI without firing weapon")
	state.clicker.restore({})
	check(not terminal._screen_material.get_shader_parameter("key_missing"), "quest error overlay excluded from application")
	for i in 20: terminal.request_clicker_action(&"click")
	check(state.clicker.samples == 26.5, "rapid physical terminal actions reach host")
	terminal.request_clicker_action(&"pipette")
	check(state.clicker.count(&"pipette") == 1 and state.clicker.samples == 11.5, "purchase acknowledged and balance exact")
	terminal._command(1, terminal._sequence, &"click")
	check(state.clicker.samples == 11.5, "replayed command ignored")
	check(state.clicker.click_multiplier() == 1.5, "physical clicks fill shared activity")
	state.clicker.bacteria_id = 7
	state.clicker.bacteria_slot = 1
	state.clicker.bacteria_remaining = 9.0
	state.clicker_changed.emit()
	await settle()
	var rare_before := state.clicker.samples
	var rare_reward := state.clicker.bacteria_reward()
	var app := terminal.ui.get_node("Overlay/LabClicker")
	var rare_point: Vector2 = app.position + app.get_node("Bacteria").position + Vector2(30, 30)
	click_ui(rare_point)
	check(state.clicker.samples == rare_before + rare_reward and state.clicker.bacteria_remaining == 0, "physical bacterium click collects one scaled bonus")
	terminal.request_clicker_action(&"bacteria", 7)
	check(state.clicker.samples == rare_before + rare_reward, "second valid command with same ticket cannot double reward")
	state.clicker.samples = 1337
	state.clicker.owned = {"pipette": 3, "assistant": 5, "centrifuge": 1}
	state.clicker.activity = 1.0
	state.clicker.bacteria_id = 8
	state.clicker.bacteria_remaining = 8.5
	state.clicker_changed.emit()
	await create_timer(0.8).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		terminal.screen_viewport.get_texture().get_image().save_png("res://tools/.local/lab-clicker-screen.png")
		root.get_texture().get_image().save_png("res://tools/.local/lab-clicker-terminal.png")
	if DisplayServer.get_name() != "headless":
		var list: ScrollContainer = app.get_node("Scroll")
		list.scroll_vertical = 920
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/lab-clicker-upgrades-mid.png")
		list.scroll_vertical = 100000
		await create_timer(0.2).timeout
		check(terminal.app_scroll > 1800 and list.scroll_vertical > 1800, "long list scrolls to final upgrade and preserves physical display position")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/lab-clicker-upgrades-final.png")
		list.scroll_vertical = 0
		await create_timer(0.2).timeout
	var previous := state.clicker.samples
	if DisplayServer.get_name() != "headless":
		var opened := TesterFeedbackStore.prepare_image(root.get_texture().get_image())
		var menu := root.get_node("GameMenu")
		await menu.open_feedback()
		await create_timer(0.5).timeout
		var image: Image = menu.tester_feedback.screenshot
		var distance := 0.0
		for y in range(200, mini(image.get_height(), 700), 20):
			for x in range(200, mini(image.get_width(), 1200), 20):
				var a := image.get_pixel(x,y)
				var b := opened.get_pixel(x,y)
				distance += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
		check(distance < 2.0, "feedback screenshot retains terminal camera and app")
		check(not terminal.active, "feedback takes ownership only after capturing app")
		menu.tester_feedback._attachment_dirty = false
		menu.force_close_menu()
	terminal.close_terminal()
	await settle()
	check(not terminal.active and get_first_node_in_group("terminal_ui") == null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "close restores camera and mouse")
	state._process_clicker(1.0)
	check(state.clicker.samples >= previous + 10, "passive production continues while app closed")
	terminal.begin_terminal_interaction()
	terminal.request_app(true)
	check(terminal.ui.get_node("Overlay/LabClicker/Scroll/Cards").get_child_count() == state.clicker.config.upgrades.size(), "reopen has all configured cards, no duplicate subscriptions")
	terminal.request_clicker_action(&"quest")
	check(state.quest_stage == BaseGameplayController.QuestStage.DELIVERED, "existing pass-key action still works")
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot, false)
	await settle()
	check(not terminal.active and terminal.screen_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "power loss closes and switches off terminal")
	previous = state.clicker.samples
	state._process_clicker(100)
	check(state.clicker.samples == previous, "no income during outage")
	# General save roundtrip, no clicker-owned file or offline timestamp.
	state.progress_persistence_enabled = true
	check(state.save_progress_authoritative(), "general world save accepts clicker state")
	var data := state.load_saved_snapshot()
	print("SAVE DATA ", data.get("lab_clicker", {}), " LIVE ", state.clicker.capture())
	check(data.get("lab_clicker", {}).get("owned", {}) == state.clicker.owned and absf(float(data.get("lab_clicker", {}).get("samples", -1)) - state.clicker.samples) < 0.001, "general save restores source economy data")
	var restored := LabClicker.new()
	restored.restore(data.get("lab_clicker", {}))
	check(restored.cost(&"assistant") == state.clicker.cost(&"assistant"), "restored price derived from counts")
	state.progress_persistence_enabled = false
	base.queue_free()
	await process_frame
	if FileAccess.file_exists(save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("CLICKER TERMINAL: %d checks, %d failures" % [checks, failures])
	quit(failures)
