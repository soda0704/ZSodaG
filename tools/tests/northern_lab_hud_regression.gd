extends SceneTree
## Real production player, inventory/RPC actions, journal rules and input firing gate.
var failures := 0
var checks := 0
var actor: GamePlayer
var hud: Control
var state: BaseGameplayController
var capture := false
var capture_dir := "res://tools/.local"
const PARALLAX := preload("res://scripts/ui/hud_parallax.gd")
const RESOLUTIONS := [Vector2i(800,600), Vector2i(1024,768), Vector2i(1280,720), Vector2i(1280,1024), Vector2i(1366,768), Vector2i(1440,900), Vector2i(1920,1080), Vector2i(1920,1200), Vector2i(2560,1440), Vector2i(3440,1440), Vector2i(3840,2160), Vector2i(5120,1440), Vector2i(1080,1920)]

func _initialize() -> void:
	create_timer(180.0).timeout.connect(func():
		push_error("HUD regression exceeded its watchdog")
		quit(2))
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://hud_test_%d.cfg" % OS.get_process_id())
	BaseGameplayController.save_scope = "solo"
	capture = DisplayServer.get_name() != "headless"
	root.mode = Window.MODE_WINDOWED
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(capture_dir)
	if OS.get_cmdline_user_args().has("--base-review"):
		review_base.call_deferred()
	elif OS.get_cmdline_user_args().has("--helicopter-review"):
		review_helicopter.call_deferred()
	else:
		run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func ticks(count: int = 3) -> void:
	for index in count: await physics_frame
	await process_frame

func save_capture(name: String) -> void:
	var error := root.get_texture().get_image().save_png(capture_dir.path_join(name))
	if error != OK:
		check(false, "capture could not be saved: %s (%s)" % [name, error_string(error)])

func review_helicopter() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1920, 1080)
	var session: Node3D = load("res://scenes/levels/base_session.tscn").instantiate()
	root.add_child(session)
	current_scene = session
	session.start_standalone_game()
	await ticks(30)
	actor = get_first_node_in_group("local_player") as GamePlayer
	check(actor != null, "helicopter has its production local player")
	# Load lobby scripts after autoloads exist (SceneTree --script compiles before them).
	var lobby = session.get_node("LobbyHud")
	check(lobby.lobby_panel.visible and lobby.lobby_panel.anchor_left == 1.0, "helicopter lobby card is visible on the right")
	check(lobby.lobby_panel.get_global_rect().position.x > root.get_visible_rect().size.x * 0.5, "helicopter card occupies the right half")
	check(lobby.lobby_id_label.get_theme_font("font").resource_path == "res://assets/fonts/hud/heading.tres", "helicopter uses embedded HUD typography")
	check(lobby._panel_reveal >= 0.99, "helicopter reveal animation completes")
	hud = actor.get_node("PlayerUI/NorthernLabHUD")
	hud.set_process(false)
	hud._parallax.offset = Vector2(12, 0)
	lobby._process(0.0)
	check((lobby.lobby_panel.position - lobby._panel_base_position).is_equal_approx(hud.get_parallax_offset_pixels()), "helicopter card shares the gameplay HUD motion")
	for resolution in [Vector2i(800,600), Vector2i(1280,720), Vector2i(1920,1080), Vector2i(3440,1440), Vector2i(5120,1440), Vector2i(1080,1920)]:
		root.size = resolution
		await ticks()
		var rect: Rect2 = lobby.lobby_panel.get_global_rect()
		var viewport_size := root.get_visible_rect().size
		check(rect.position.x > viewport_size.x * 0.5 and rect.end.x <= viewport_size.x - 12, "helicopter card stays anchored and inside %s" % resolution)
	hud._parallax.reset()
	hud.set_process(true)
	root.size = Vector2i(1920, 1080)
	await ticks()
	if capture:
		await RenderingServer.frame_post_draw
		save_capture("northern-hud-helicopter.png")
	var menu = root.get_node("GameMenu")
	menu.open_menu(menu.MenuView.SESSION)
	menu._on_ready_pressed()
	# Wait for actual threaded loading, rather than assuming the base loads in 3 s.
	var deadline := Time.get_ticks_msec() + 30000
	while (not session.has_node("V3Level") or session._v3_transition_in_progress) and Time.get_ticks_msec() < deadline:
		await create_timer(0.1).timeout
	var arrived: bool = session.has_node("V3Level") and not session._v3_transition_in_progress
	check(arrived, "real ready action completes helicopter-to-base transition")
	if arrived:
		await create_timer(1.0).timeout
		hud = actor.get_node("PlayerUI/NorthernLabHUD")
		hud.refresh_state()
		check(hud.visible and not hud.view_state.arrival and hud.view_state.quest.day >= 1, "base restores live day and objective HUD after arrival")
		check(not lobby.lobby_panel.visible, "helicopter card disappears after arrival")
	session.queue_free()
	await process_frame
	print("NORTHERNLAB HUD HELICOPTER CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)

func review_base() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1920, 1080)
	var base: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	state = base.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false
	root.add_child(base)
	current_scene = base
	root.get_node("GameMenu").force_close_menu()
	await ticks(30)
	actor = get_first_node_in_group("local_player") as GamePlayer
	hud = actor.get_node("PlayerUI/NorthernLabHUD")
	actor.survival.set_physics_process(false)
	actor.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.67})
	actor.pickup_world_item_authoritative(&"pistol", {"rounds": 8})
	actor.weapon.pistol_ammo = 24
	actor.survival.health = 92
	await ticks(10)
	check(hud.visible and hud.view_state.quest.day == state.day_index, "production base exposes live HUD and story")
	var breaker: Node3D = get_first_node_in_group("main_breaker")
	check(breaker != null, "production breaker available")
	if breaker != null:
		var target := breaker.global_position + Vector3(0, 0.5, 0)
		actor.teleport_authoritative(target + Vector3(0, -0.8, 1.8), 0)
		var direction := (target - actor.camera.global_position).normalized()
		actor._input_pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		actor._server_pitch = actor._input_pitch
		await ticks(10)
		actor.refresh_interaction_prompt()
		print("PRODUCTION PROMPT ", actor.interaction_prompt_label.text, " visible ", actor.interaction_prompt_label.visible)
	check(hud.view_state.has_flashlight and hud.view_state.weapon_rounds == 8, "production inventory reaches HUD")
	review_production_prompts(base)
	if capture:
		await RenderingServer.frame_post_draw
		save_capture("northern-hud-production-base.png")
	base.queue_free()
	await process_frame
	print("NORTHERNLAB HUD BASE CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)

func review_production_prompts(base: Node) -> void:
	var catalog: Array[Dictionary] = []
	var families := {}
	for node in base.find_children("*", "", true, false):
		if not node.has_method("network_interact"):
			continue
		var text := ""
		if node.has_method("get_interaction_hint_for"):
			text = str(node.call("get_interaction_hint_for", actor))
		elif node.has_method("get_interaction_prompt"):
			var prompt := str(node.call("get_interaction_prompt"))
			if not prompt.strip_edges().is_empty():
				text = "[E] " + prompt
		else:
			continue
		var script_path: String = node.get_script().resource_path
		families[script_path] = true
		catalog.append({"node": str(base.get_path_to(node)), "script": script_path, "prompt": text})
		if text.is_empty():
			continue
		var valid := true
		for resolution in [Vector2i(800,600), Vector2i(1920,1080), Vector2i(5120,1440), Vector2i(1080,1920)]:
			var previous_size: Vector2 = hud._canvas_size
			# Test the same prompt against both compact and full reference compositions.
			hud._canvas_size = Vector2(resolution) / maxf(minf(resolution.x / 2560.0, resolution.y / 1440.0), minf(0.6, minf(resolution.x / 1600.0, resolution.y / 1000.0)))
			var layout: Dictionary = hud.interaction_layout(text)
			var rect: Rect2 = layout.rect
			valid = valid and rect.position.x >= 24 and rect.end.x <= hud._canvas_size.x - 24 and rect.end.y < hud._canvas_size.y - 220
			valid = valid and is_equal_approx(rect.get_center().x, hud._canvas_size.x * 0.5)
			valid = valid and (not text.begins_with("[E]") or layout.key == "E")
			hud._canvas_size = previous_size
		check(valid, "production prompt stays centered and bounded: %s" % base.get_path_to(node))
	check(families.size() >= 12, "production prompt catalog covers at least twelve interaction families")
	var file := FileAccess.open(capture_dir.path_join("production-interaction-catalog.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(catalog, "\t"))
	else:
		check(false, "production prompt catalog could not be saved")

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	root.get_node("GameMenu").force_close_menu()
	var service := root.get_node("SteamInput")
	service.set_process(false)
	service.set_process_input(false)
	service.native_input_available = false
	# The synthetic arena belongs to the external test, never to the shipped game.
	var arena_path: String = get_script().resource_path.get_base_dir().path_join("fixtures/character_test_arena.tscn")
	var arena := load(arena_path) as PackedScene
	if arena == null:
		check(false, "test arena is readable")
		quit(1)
		return
	var world: Node3D = arena.instantiate()
	root.add_child(world)
	current_scene = world
	state = BaseGameplayController.new()
	state.progress_persistence_enabled = false
	world.add_child(state)
	state.set_process(false)
	state.maintenance["base_entered"] = true
	actor = load("res://scenes/characters/player.tscn").instantiate()
	actor.has_journal = true
	actor.name = "1"
	actor.setup(1, "HUD test", Vector3(0, 0.1, 0), Color.WHITE)
	world.get_node("Players").add_child(actor)
	actor.survival.set_physics_process(false)
	actor.debug_fly = true
	hud = actor.get_node("PlayerUI/NorthernLabHUD")
	await ticks(10)
	check(hud.visible, "local player's HUD appears")
	check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "HUD does not consume mouse input")
	check(hud.view_state.quest.day == 1 and hud.view_state.quest.objective == "Вернуть базу к жизни", "HUD reads the journal's real day and objective")
	check(hud.teammate == null, "solo has no fictional teammate")
	check(hud._font.has_char("Ж".unicode_at(0)) and hud._font.has_char("Я".unicode_at(0)), "live font supports Cyrillic")
	check(hud._font.resource_path == "res://assets/fonts/hud/body.tres" and not hud._font.base_font.multichannel_signed_distance_field and hud._font.base_font.oversampling >= 2.0, "embedded font uses high resolution rasterization without MSDF contour artifacts")
	check(hud.view_state.attack_hint == "ЛКМ", "mouse action has a readable binding")
	service.using_controller = true
	service.controller_family = "playstation"
	hud.refresh_state()
	check(hud.view_state.attack_hint == "R2" and hud.view_state.light_hint == "△", "controller hints use actual controller buttons")
	service.using_controller = false
	var old_events := InputMap.action_get_events("flashlight")
	InputMap.action_erase_events("flashlight")
	var rebound := InputEventKey.new()
	rebound.physical_keycode = KEY_H
	InputMap.action_add_event("flashlight", rebound)
	hud.refresh_state()
	check(hud.view_state.light_hint == "H", "HUD reflects rebinding without a restart")
	InputMap.action_erase_events("flashlight")
	for event in old_events: InputMap.action_add_event("flashlight", event)
	check(not hud.view_state.has_flashlight and hud.view_state.held_item == &"", "empty equipment is represented honestly")
	actor.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.67})
	actor.pickup_world_item_authoritative(&"pistol", {"rounds": 8})
	actor.weapon.pistol_ammo = 24
	if capture:
		await RenderingServer.frame_post_draw
		save_capture("northern-hud-in-world.png")
	actor.survival.health = 92.0
	actor.survival.radiation = 12.0
	actor.update_battery_ui()
	hud.refresh_state()
	check(hud.view_state.weapon_rounds == 8 and hud.view_state.pistol_ammo == 24, "live magazine and reserve reach HUD")
	check(is_equal_approx(hud.view_state.battery_charge, 0.67) and hud.view_state.health == 92.0 and hud.view_state.radiation == 12.0, "health, exposure and battery use live values")
	await ticks()
	check(actor.weapon._hud.visible and actor.weapon._hud.self_modulate.a == 0, "legacy text is replaced while its firing gate stays enabled")
	var before := actor.weapon.rounds
	if capture:
		var attack := InputEventAction.new()
		attack.action = &"weapon_attack"
		attack.pressed = true
		Input.parse_input_event(attack)
		await ticks(1)
		attack = InputEventAction.new()
		attack.action = &"weapon_attack"
		Input.parse_input_event(attack)
	else:
		# Headless has no captured mouse; use the production authoritative action.
		actor.weapon.request_action(&"fire")
	await ticks()
	check(actor.weapon.rounds == before - 1, "real weapon input still fires with the new HUD")
	actor.request_reload_or_battery()
	hud.refresh_state()
	check(hud.view_state.weapon_reload > 0, "reload action reaches HUD")
	await create_timer(1.6).timeout
	hud.refresh_state()
	check(hud.view_state.weapon_rounds == 12 and hud.view_state.pistol_ammo == 19, "completed reload updates magazine and reserve")
	actor.weapon.reload_left = 0
	actor._battery_charge = 0.0
	actor._spare_batteries.assign([0.9])
	actor.request_inventory_action(&"replace_battery")
	await create_timer(1.2).timeout
	hud.refresh_state()
	check(absf(hud.view_state.battery_charge - 0.9) < 0.01, "battery replacement remains functional")
	actor._battery_charge = 0.4
	actor._spare_batteries.assign([1.0])
	actor._handheld_flashlight_drawn = true
	hud.refresh_state()
	check(hud.view_state.reload_action == &"replace_battery", "R hint follows handheld flashlight battery priority")
	var rounds_before_battery := actor.weapon.rounds
	actor.request_reload_or_battery()
	hud.refresh_state()
	check(hud.view_state.battery_action_busy and hud.view_state.weapon_reload <= 0, "actual R starts the battery action shown by HUD")
	await create_timer(1.2).timeout
	hud.refresh_state()
	check(absf(hud.view_state.battery_charge - 1.0) < 0.01 and actor.weapon.rounds == rounds_before_battery and not hud.view_state.battery_action_busy, "R completes battery insertion without changing ammunition")
	actor._handheld_flashlight_drawn = false
	hud.refresh_state()
	check(hud.view_state.reload_action == &"reload", "R hint returns to weapon reload when flashlight is stowed")
	state.day_index = 2
	state.maintenance = {"wires_required": true}
	state.snapshot_changed.emit(state.get_snapshot())
	hud.refresh_state()
	check(hud.view_state.quest.day == 2 and hud.view_state.quest.objective == "Авария электроснабжения", "story and maintenance changes update the objective")
	var remote: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
	remote.name = "2"
	remote.setup(2, "Напарник", Vector3(-3, 0.1, -18), Color.WHITE)
	world.get_node("Players").add_child(remote)
	remote.set_physics_process(false)
	remote.survival.set_physics_process(false)
	remote.survival.health = 67
	await ticks()
	hud.refresh_state()
	check(hud.teammate == remote and not remote.get_node("PlayerUI/NorthernLabHUD").visible, "remote teammate tracked without a duplicate remote HUD")
	var journal: QuestJournalUI = root.get_node("QuestJournal")
	journal.open_journal()
	await ticks()
	check(journal.is_journal_open() and not hud.visible, "J journal presentation hides HUD")
	journal.force_close()
	await ticks()
	check(hud.visible, "HUD returns after journal closes")
	root.get_node("GameMenu").open_menu()
	await ticks()
	check(not hud.visible, "pause hides HUD")
	check(hud._parallax.offset == Vector2.ZERO, "menu clears camera inertia before returning to gameplay")
	root.get_node("GameMenu").force_close_menu()
	actor.survival.dead = true
	await ticks()
	check(not hud.visible, "death hides HUD without replacing death/respawn UI")
	actor.survival.dead = false
	actor.debug_free_camera.enabled = true
	await ticks()
	check(not hud.visible, "free camera hides HUD")
	actor.debug_free_camera.enabled = false
	actor._input_yaw = PI * 0.5
	actor.rotation.y = PI * 0.5
	actor.camera.current = true
	await ticks()
	check(absf(hud.compass_heading - 270) < 1, "compass follows the camera's actual heading")
	actor._input_yaw = 0
	actor.rotation.y = 0
	actor.survival.radiation = 0
	actor.survival.health = 92
	actor._battery_charge = 0.67
	actor.weapon.rounds = 8
	actor.weapon.pistol_ammo = 24
	actor.set_physics_process(false)
	review_parallax()
	actor.interaction_prompt_label.text = "[E] Осмотреть щит"
	actor.interaction_prompt_label.show()
	hud._prompt_alpha = 0.0
	hud._prompt_text = ""
	hud._update_animations(0.035)
	check(hud._prompt_alpha > 0.0 and hud._prompt_alpha < 1.0, "interaction animates in")
	await create_timer(0.25).timeout
	check(hud._prompt_alpha >= 0.99, "interaction animation reaches full clarity")
	actor.interaction_prompt_label.text = "[E] Топливо: 99%"
	hud._update_animations(0.01)
	check(hud._prompt_alpha >= 0.99 and hud._prompt_text.ends_with("99%"), "live text updates stay legible without restarting the fade")
	actor.interaction_prompt_label.hide()
	hud._update_animations(0.035)
	check(hud._prompt_alpha >= 0.99, "one-frame target loss does not flicker the prompt")
	hud._update_animations(0.035)
	check(hud._prompt_alpha > 0.0 and hud._prompt_alpha < 1.0, "interaction animates out")
	await create_timer(0.25).timeout
	check(hud._prompt_text.is_empty(), "lost target clears after its short fade")
	var previous_fill: float = hud._health_ratio
	actor.survival.health = 50
	hud.refresh_state()
	hud._update_animations(0.02)
	check(hud._health_ratio < previous_fill and hud._health_ratio > 0.5, "health bar interpolates without changing actual health")
	actor.survival.health = 92
	actor.interaction_prompt_label.text = "[E] Осмотреть щит"
	actor.interaction_prompt_label.show()
	await create_timer(0.25).timeout
	for resolution in RESOLUTIONS:
		root.size = resolution
		await ticks(5)
		hud.refresh_state()
		check(hud._canvas_size.x >= 1599 and hud._canvas_size.y >= 999, "HUD retains room for all groups at %s" % resolution)
		var pixel_scale: float = hud._layout_scale * root.get_stretch_transform().get_scale().x
		check(pixel_scale * 24 >= 11.99, "body text stays readable in screen pixels at %s" % resolution)
		var compass: Rect2 = hud.compass_layout()
		check(compass.position.x > 500 and compass.end.x < hud._canvas_size.x - 300, "compass clears both upper corner groups at %s" % resolution)
		var prompt_rect: Rect2 = hud.interaction_layout("[E] Осмотреть щит").rect
		check(absf(prompt_rect.get_center().x - hud._canvas_size.x * 0.5) < 1 and prompt_rect.position.y > hud._canvas_size.y * 0.5 and prompt_rect.position.y < hud._canvas_size.y * 0.5 + 60, "interaction stays just below crosshair at %s" % resolution)
		var contained := true
		for drift in [Vector2(-12, 0), Vector2(12, 0)]:
			hud._parallax.offset = drift
			var objective: Rect2 = hud.objective_layout(hud.view_state.quest).rect
			objective.position += hud.panel_offset(Vector2(1, 1))
			var prompt: Rect2 = hud.interaction_layout("[E] Осмотреть щит").rect
			prompt.position += hud.panel_offset()
			var viewport := Rect2(Vector2.ZERO, hud._canvas_size)
			contained = contained and viewport.encloses(objective) and viewport.encloses(prompt)
			for card in hud.equipment_layout(hud.view_state):
				var rect: Rect2 = card.frame
				rect.position += hud.panel_offset(Vector2(0, -1))
				contained = contained and viewport.encloses(rect)
		check(contained, "panels stay inside the screen at both parallax limits in %s" % resolution)
		var cards: Array = hud.equipment_layout(hud.view_state)
		var equipment: Rect2 = cards[0].frame.merge(cards[1].frame)
		equipment.position += hud.panel_offset(Vector2(0, -1))
		var health := Rect2(46, hud._canvas_size.y - 200, 355, 186)
		health.position += hud.panel_offset(Vector2(1, -1))
		var status: Dictionary = hud.status_layout(hud.view_state)
		var ammo := Rect2(status.ammo_x, hud._canvas_size.y - 145, hud._canvas_size.x - 48 - status.ammo_x, 110)
		ammo.position += hud.panel_offset(Vector2(-1, -1))
		check(not equipment.intersects(health) and not equipment.intersects(ammo), "bottom groups do not overlap at %s" % resolution)
		hud._parallax.reset()
		if capture:
			# Isolate HUD over the supplied dark preview color for visual layout review.
			var background := ColorRect.new()
			background.color = Color("141e24")
			background.mouse_filter = Control.MOUSE_FILTER_IGNORE
			actor.get_node("PlayerUI").add_child(background)
			actor.get_node("PlayerUI").move_child(background, 0)
			background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			actor.interaction_prompt_label.text = "[E] Осмотреть щит"
			actor.interaction_prompt_label.show()
			actor.set_physics_process(false)
			await process_frame
			actor.interaction_prompt_label.show()
			await RenderingServer.frame_post_draw
			save_capture("northern-hud-%dx%d.png" % [resolution.x,resolution.y])
			background.queue_free()
	actor.set_physics_process(true)
	remote.queue_free()
	await ticks()
	hud.refresh_state()
	check(hud.teammate == null, "disconnected teammate disappears safely")
	await review_layout_states()
	world.queue_free()
	await process_frame
	print("NORTHERNLAB HUD CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)

func review_parallax() -> void:
	var motion := PARALLAX.new()
	motion.sample(Vector3.FORWARD, 1.0 / 60)
	for index in 24:
		motion.sample(Basis(Vector3.UP, (index + 1) * 0.02) * Vector3.FORWARD, 1.0 / 60)
	check(motion.offset.x > 1 and absf(motion.offset.y) < 0.01, "left camera turn moves panels right")
	for index in 24:
		motion.sample(Basis(Vector3.UP, 0.48 - (index + 1) * 0.02) * Vector3.FORWARD, 1.0 / 60)
	check(motion.offset.x < -1, "reversing camera turn moves panels left without a queued animation")
	motion.reset()
	motion.sample(Vector3.FORWARD, 1.0 / 60)
	var vertical_still := true
	for index in 48:
		motion.sample(Basis(Vector3.RIGHT, sin(float(index) / 48 * TAU) * 0.7) * Vector3.FORWARD, 1.0 / 60)
		vertical_still = vertical_still and motion.offset == Vector2.ZERO
	check(vertical_still, "looking up and down leaves every panel stationary")
	var settled := []
	for rate in [30, 60, 144]:
		motion.reset()
		motion.sample(Vector3.FORWARD, 1.0 / rate)
		var bounded := true
		for index in rate:
			motion.sample(Basis.from_euler(Vector3(0.5, 2.0, 0) * float(index + 1) / rate) * Vector3.FORWARD, 1.0 / rate)
			bounded = bounded and absf(motion.offset.x) <= 12 and motion.offset.y == 0
		settled.append(motion.offset)
		var forward := Basis.from_euler(Vector3(0.5, 2.0, 0)) * Vector3.FORWARD
		for index in rate: motion.sample(forward, 1.0 / rate)
		check(bounded and motion.offset.length() < 0.01, "parallax stays bounded and returns smoothly to neutral at %d FPS" % rate)
	check(settled[0].distance_to(settled[2]) < 0.1, "camera inertia has consistent strength at 30 and 144 FPS")
	motion.reset()
	motion.sample(Basis(Vector3.UP, 3.13) * Vector3.FORWARD, 1.0 / 60)
	motion.sample(Basis(Vector3.UP, -3.13) * Vector3.FORWARD, 1.0 / 60)
	check(motion.offset.x > 0 and motion.offset.x < 3, "crossing north's angle seam produces a small continuous drift")
	motion.sample(Vector3.FORWARD, 1.0 / 60)
	check(motion.offset == Vector2.ZERO, "camera cut resets inertia instead of kicking panels")
	hud._update_parallax(Vector3.FORWARD, 1.0 / 60)
	hud._parallax.offset = Vector2(8, 0)
	hud._parallax_position = actor.global_position + Vector3(10, 0, 0)
	hud._update_parallax(Vector3.FORWARD, 1.0 / 60)
	check(hud._parallax.offset == Vector2.ZERO, "player teleport establishes a neutral HUD position")

func review_layout_states() -> void:
	hud.set_process(false)
	root.size = Vector2i(1920, 1080)
	await ticks()
	var empty: Dictionary = hud.objective_layout({"tasks": []})
	var single: Dictionary = hud.objective_layout({"objective": "Восстановить питание", "tasks": ["Включить щит"]})
	var multiple: Dictionary = hud.objective_layout({"objective": "Восстановить питание", "tasks": ["Найти предохранитель", "Включить щит", "Вернуться на базу"]})
	check(empty.rect.size.y <= 60 and empty.empty, "no tasks produces one compact status row")
	check(single.rect.size.y < multiple.rect.size.y and single.rect.size.y < 186, "one task uses only its actual content height")
	var long_text := "Найти предохранитель и проверить резервное питание в подземном комплексе. ".repeat(8)
	var long_layout: Dictionary = hud.objective_layout({"objective": long_text, "tasks": [long_text, long_text]})
	check(long_layout.rect.size.y < 440 and str(long_layout.rows[0].text).ends_with("…") and not str(long_layout.footer).is_empty(), "long objectives stay bounded with a journal continuation")
	check(hud.equipment_layout({}).is_empty(), "no equipment reserves no empty cards")
	var one: Array = hud.equipment_layout({"has_flashlight": true})
	check(one.size() == 1 and absf(one[0].rect.get_center().x - hud._canvas_size.x * 0.5) < 1, "single item is centered")
	var two: Array = hud.equipment_layout({"has_flashlight": true, "held_item": &"pistol"})
	check(two.size() == 2 and two[0].rect.end.x < two[1].rect.position.x, "two real items have a consistent gap")
	var contextual_only := true
	for item in [&"fuse", &"fuel_can", &"seed_packet"]:
		var cards: Array = hud.equipment_layout({"held_item": item, "journal_hint": "K"})
		contextual_only = contextual_only and cards.size() == 1 and cards[0].hint.is_empty()
	check(contextual_only, "interaction-only items never receive a journal or fictitious use key")
	var usable: Array = hud.equipment_layout({"has_flashlight": true, "held_item": &"kitchen_knife", "light_hint": "H", "attack_hint": "R2"})
	check(usable[0].hint == "H" and usable[1].hint == "R2", "usable equipment retains its actual rebound or controller action")
	var compact: Dictionary = hud.interaction_layout("[E] Осмотреть щит")
	check(compact.rect.size.y <= 48 and compact.rect.size.y >= compact.key_size.y + 12, "single-line interaction is compact with enough keycap padding")
	var centered := true
	for source in ["[E] Осмотреть щит", "[ E ] Осмотреть щит", "[PageDown] Включить", "[R2] Взаимодействовать", "Нет питания"]:
		var layout: Dictionary = hud.interaction_layout(source)
		var text_center: float = layout.rect.position.x + layout.indent + layout.text_width * 0.5
		centered = centered and absf(text_center - layout.rect.get_center().x) < 0.01
	check(centered, "interaction text stays centered on its whole frame for keyboard, controller and informational prompts")
	var multiline: Dictionary = hud.interaction_layout("[E] " + long_text)
	var text_height: float = hud._font.get_multiline_string_size(multiline.text, HORIZONTAL_ALIGNMENT_LEFT, multiline.text_width, 24).y
	check(multiline.rect.size.y >= text_height + 14 and multiline.rect.size.x <= 660, "long interaction grows with its text without clipping or losing side padding")
	var gun: Dictionary = hud.status_layout({"held_item": &"pistol", "weapon_rounds": 12, "pistol_ammo": 120})
	var kit: Dictionary = hud.status_layout({"held_item": &"pistol", "weapon_rounds": 12, "pistol_ammo": 120, "has_flashlight": true})
	check(is_equal_approx(gun.ammo_x + gun.ammo_width, hud._canvas_size.x - 48), "ammo aligns to the right when there is no battery")
	check(kit.ammo_x + kit.ammo_width < kit.battery_x - 13, "ammo and battery do not overlap with a large reserve")
	check(not hud.status_layout({"held_item": &"pistol"}, true).has_ammo, "vehicle state removes unavailable gun status")
	# Day seven now has an assigned descent objective; it is no longer an empty day.
	state.day_index = state.EXPEDITION_DAY_INDEX
	state.maintenance = {}
	state.main_breaker_on = true
	state.snapshot_changed.emit(state.get_snapshot())
	hud.refresh_state()
	check(not hud.view_state.quest.tasks.is_empty(), "day seven exposes its assigned descent objective")
	state.day_index = 2
	state.quest_stage = 4
	state.snapshot_changed.emit(state.get_snapshot())
	hud.refresh_state()
	check(hud.view_state.quest.tasks.is_empty() and hud.view_state.quest.empty_label == "ЗАДАЧИ ВЫПОЛНЕНЫ", "completed real story produces the compact completed state")
	for rate in [30, 60, 144]:
		state.day_index = 2
		state.maintenance = {"wires_required": true}
		state.snapshot_changed.emit(state.get_snapshot())
		hud.refresh_state()
		hud._update_animations(0.04)
		state.day_index = 2
		state.quest_stage = 4
		state.maintenance = {}
		state.snapshot_changed.emit(state.get_snapshot())
		hud.refresh_state()
		var contained := true
		for frame in rate:
			hud._update_animations(1.0 / rate)
			contained = contained and (hud._objective_alpha <= 0.001 or hud._objective_height >= hud._objective_view.rect.size.y - 0.1)
		check(hud._objective_phase == 0 and hud._objective_height <= 60 and contained, "interrupted panel motion settles cleanly at %d FPS" % rate)
	if capture:
		await capture_layout_states()
	hud.set_process(true)

func capture_layout_states() -> void:
	var background := ColorRect.new()
	background.color = Color("141e24")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actor.get_node("PlayerUI").add_child(background)
	actor.get_node("PlayerUI").move_child(background, 0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var original: Dictionary = hud.view_state.duplicate(true)
	var cases := {
		"empty": {"quest": {"day": 6, "objective": "", "tasks": [], "empty_label": "НЕТ АКТИВНЫХ ЗАДАЧ"}, "held_item": &"", "has_flashlight": false},
		"single": {"quest": {"day": 2, "objective": "Восстановить питание", "tasks": ["Включить главный щит"]}, "held_item": &"flashlight", "has_flashlight": true},
		"completed": {"quest": {"day": 2, "objective": "Ключ шифрования", "tasks": [], "empty_label": "ЗАДАЧИ ВЫПОЛНЕНЫ"}, "held_item": &"pistol", "has_flashlight": false},
		"item-name": {"quest": {"day": 2, "objective": "Восстановить питание", "tasks": ["Установить предохранитель"]}, "held_item": &"fuse", "has_flashlight": false},
		"long": {"quest": {"day": 2, "objective": "Восстановить аварийное электроснабжение подземного исследовательского комплекса", "tasks": ["Найти предохранитель в медпункте и установить его в резервный блок у входа в подземный комплекс", "Проверить соединение проводов главного распределительного щита в генераторной", "Вернуться на базу"]}, "held_item": &"pistol", "has_flashlight": true}}
	actor.interaction_prompt_label.hide()
	hud._prompt_text = ""
	hud._prompt_progress = 0.0
	hud._prompt_alpha = 0.0
	for id in cases:
		hud.view_state = original.duplicate(true)
		hud.view_state.merge(cases[id], true)
		hud._animated_state_initialized = false
		hud._update_animations(0.2)
		hud.queue_redraw()
		await RenderingServer.frame_post_draw
		save_capture("northern-hud-state-%s.png" % id)
	var fixed_regions: Array[PackedByteArray] = []
	for drift in [Vector2(-12, 0), Vector2(12, 0)]:
		hud._parallax.offset = drift
		hud.queue_redraw()
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		fixed_regions.append(frame.get_region(Rect2i(620, 20, 680, 65)).get_data())
		save_capture("northern-hud-parallax-%s.png" % ("left" if drift.x < 0 else "right"))
	check(fixed_regions[0] == fixed_regions[1], "rendered compass stays fixed while all panels move")
	hud._parallax.reset()
	hud.view_state = original
	hud._animated_state_initialized = false
	if OS.get_cmdline_user_args().has("--motion-capture"):
		await capture_objective_motion()
	background.queue_free()

func capture_objective_motion() -> void:
	DirAccess.make_dir_recursive_absolute("res://tools/.local/hud-motion")
	state.day_index = state.EXPEDITION_DAY_INDEX
	state.maintenance = {}
	state.snapshot_changed.emit(state.get_snapshot())
	hud.refresh_state()
	hud._animated_state_initialized = false
	hud._update_animations(0.2)
	var index := 0
	for active in [true, false]:
		state.day_index = 2 if active else state.EXPEDITION_DAY_INDEX
		state.maintenance = {"wires_required": true} if active else {}
		state.snapshot_changed.emit(state.get_snapshot())
		hud.refresh_state()
		for frame in 45:
			hud._update_animations(1.0 / 30.0)
			hud.queue_redraw()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().get_region(Rect2i(0, 0, 450, 390)).save_png("res://tools/.local/hud-motion/%03d.png" % index)
			index += 1
