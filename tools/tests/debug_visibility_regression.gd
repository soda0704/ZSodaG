extends SceneTree
var checks := 0
var failures := 0
var save_path: String
func _initialize() -> void:
	save_path = "user://debug_visibility_test_%d.cfg" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://debug_visibility_settings.json")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle() -> void:
	for frame in 8: await physics_frame
	await process_frame
	await process_frame
func capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/debug-visibility-%s.png" % label)
func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960,540)
	Engine.max_fps = 60
	var menu = root.get_node("GameMenu")
	menu.force_close_menu()
	var world = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	world.get_node("BaseGameplayController").progress_persistence_enabled = false
	root.add_child(world)
	await settle()
	var state: BaseGameplayController = world.get_node("BaseGameplayController")
	state.set_process(false)
	var player := get_first_node_in_group("local_player") as GamePlayer
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.teleport_authoritative(Vector3(23,0.1,-1),-PI/2)
	var lighting: WorldLighting = world.get_node("WorldLighting")
	var indirect = world.get_node("WorldIndirectLighting")
	var console = root.get_node("DeveloperConsole")
	var original_draw := root.debug_draw
	var snapshot := state.get_snapshot()
	var authored: Environment = world.get_node("SnowExterior/OvercastDayEnvironment").environment
	var authored_ambient := authored.ambient_light_energy
	await create_timer(0.45).timeout
	await capture("authored")
	check(lighting.debug_darkness == 1.0, "default keeps authored darkness")
	console.execute("/fullbright on")
	await settle()
	check(root.debug_draw == Viewport.DEBUG_DRAW_UNSHADED and player.body_animator.first_person.viewport.debug_draw == Viewport.DEBUG_DRAW_UNSHADED, "fullbright covers world and FP viewport")
	check(indirect.get_active_probe_count() == 0 and is_zero_approx(player.camera.environment.volumetric_fog_density), "fullbright disables GI darkness and fog locally")
	await capture("fullbright")
	for removed in ["/darkness 0.5", "/darkness reset", "/fullbright maybe"]:
		console.execute(removed)
		check(lighting.debug_darkness == 0.0, "removed/invalid command leaves light unchanged: %s" % removed)
	check(not console._help_text().contains("/darkness") and not str(console.LIGHTING_COMMANDS).contains("/darkness"), "darkness removed from help and completion")
	console.execute("/fullbright off")
	await settle()
	print("DEBUG RESET probes=",indirect.get_active_probe_count()," mode=",root.debug_draw," darkness=",lighting.debug_darkness)
	check(lighting.debug_darkness == 1.0 and indirect.get_active_probe_count() > 0 and root.debug_draw == original_draw, "reset restores authored light, GI and render mode")
	check(is_equal_approx(authored.ambient_light_energy, authored_ambient) and state.get_snapshot() == snapshot, "debug visibility does not edit resources, power or saved gameplay state")
	console.execute("/fullbright")
	await settle()
	check(lighting.debug_darkness == 0.0, "fullbright toggles on")
	console.execute("/fullbright off")
	check(lighting.debug_darkness == 1.0, "fullbright off restores authored darkness")
	console.execute("/fullbright on")
	world.queue_free()
	await process_frame
	await process_frame
	check(root.debug_draw == original_draw, "leaving level clears fullbright override")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("DEBUG VISIBILITY CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
