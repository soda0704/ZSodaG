extends SceneTree
## Exercise the real solo menu/arrival/save chain with live lighting and FP hands.
var failures: Array[String] = []
func _initialize():
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://menu_light_%d.json" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://menu_light_%d.cfg" % OS.get_process_id())
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://menu_light_save_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool,label:String):
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures.append(label)
func frames(count:int):
	for frame in count: await process_frame
func settle(): await create_timer(0.7).timeout
func wait_for(predicate:Callable,seconds:=15.0):
	var deadline=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()
func run():
	await process_frame
	var menu=root.get_node("GameMenu")
	var quality=menu.get_node("GraphicsQuality")
	quality.set_advanced_lighting_enabled(true)
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1280,720)
	Engine.max_fps=60
	var main=load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene=main
	await settle()
	main.single_player_button.pressed.emit()
	await settle()
	check(main.current_view=="character", "New Game reaches the production character selector")
	main.selector.option.select(1)
	main.selector.option.item_selected.emit(1)
	main._confirm_character()
	if not await wait_for(func(): return current_scene!=null and current_scene.scene_file_path==menu.MECHANICS_TEST_ROOM_SCENE and not menu._transition_in_progress):
		check(false,"character confirmation loads the arrival session"); quit(1); return
	var world=current_scene
	var player=get_first_node_in_group("local_player")
	player.survival.debug_invincible=true
	check(world.is_solo_arrival() and menu.get_character_variant_id()==1, "chosen character enters the cabin and waits for explicit readiness")
	menu.open_menu(menu.MenuView.SESSION)
	await settle()
	check(menu.session_panel.visible and not menu.ready_button.disabled, "solo lobby offers readiness without requiring a network session")
	check(menu.shell.header.get_child(0).text.contains("ОДИНОЧНАЯ") and menu.ready_button.text == "ГОТОВ К ВЫСАДКЕ", "solo arrival is labelled as solo and uses a consistent disembark action")
	menu._on_ready_pressed()
	if not await wait_for(func(): return world.has_node("V3Level") and not world.is_solo_arrival() and not world._v3_transition_in_progress):
		check(false,"readiness loads the real base"); quit(1); return
	await frames(45)
	var level=world.get_node("V3Level")
	var state:BaseGameplayController=level.get_node("BaseGameplayController")
	var lighting:WorldLighting=level.get_node("WorldLighting")
	var power=level.get_node("BasePowerLightingController")
	var fp=player.body_animator.first_person
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.apply_held_item_inventory(&"pistol",{})
	player.update_character_animation(1.0/60)
	var snapshot=state.get_snapshot()
	snapshot.fuel_delivered=true
	snapshot.fuel_liters=30.0
	snapshot.phase=BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on=true
	state._broadcast_snapshot(snapshot)
	await frames(30)
	check(power.is_standard_powered, "authoritative base power reaches the live lighting controller")
	menu.open_menu()
	await settle()
	menu.open_settings()
	await settle()
	var settings=menu.settings_panel
	var env:Environment=player.camera.environment
	settings._set_value("Gamma",120,true)
	settings._set_value("AOQuality",0,true)
	settings._set_value("FogQuality",0,true)
	settings._set_value("Bloom",false,true)
	check(env.ssao_enabled and env.volumetric_fog_enabled and env.glow_enabled, "draft effects do not alter live light before Apply")
	settings.apply(false)
	await frames(10)
	check(not env.ssao_enabled and not env.volumetric_fog_enabled and not env.glow_enabled and power.is_standard_powered, "ESC Apply changes effects without resetting base power")
	check(fp.view_camera.environment.adjustment_color_correction==env.adjustment_color_correction and not fp.view_camera.environment.glow_enabled, "hand presentation receives gamma and bloom changes without copying world fog")
	settings.draft.Graphics=quality.normalized(quality.PRESETS[3])
	settings.apply(false)
	await frames(10)
	check(env.ssao_enabled and env.volumetric_fog_enabled and env.glow_enabled and fp.view_camera.environment.glow_enabled, "restoring High restores authored effects in both world and hands")
	check(not level.get_node("SnowExterior/Terrain3D/MouseViewport/MouseCamera").environment.ssao_enabled, "settings never contaminate the Terrain3D utility camera")
	var notified=[0]
	env.changed.connect(func(): notified[0]+=1)
	var capped:Dictionary=quality.values.duplicate()
	capped.FPS=90
	quality.apply(capped)
	check(notified[0]==0 and not quality._render_update_pending and Engine.max_fps==90, "FPS-only change leaves live environments and effect buffers untouched")
	settings.request_back()
	await settle()
	check(menu._current_view==menu.MenuView.MAIN and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE, "settings return to ESC with menu input ownership")
	menu.close_menu()
	await settle()
	check(not menu.is_menu_open(), "Resume closes the gameplay menu")
	if DisplayServer.get_name() == "headless":
		print("SKIP mouse capture: headless DisplayServer always reports a visible pointer")
	else:
		check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED, "Resume returns mouse ownership to the gameplay camera")
	# Dynamically attached geometry/lights must join and leave the cached FP membership.
	var light=OmniLight3D.new()
	light.light_energy=0
	fp.model.add_child(light)
	var geometry=MeshInstance3D.new()
	geometry.mesh=BoxMesh.new()
	fp.model.add_child(geometry)
	fp.set_external_view(true)
	check(not geometry.visible and light.is_visible_in_tree(), "new view geometry hides externally without hiding gameplay lights")
	fp._sync_world_light_instances()
	check(fp._world_light_instances.has(light.get_instance()), "new equipment light registers with the world rendering scenario")
	geometry.reparent(level)
	check(geometry.visible and not fp._model_geometry.has(geometry), "detached geometry restores visibility and leaves the FP cache")
	geometry.free()
	fp.model.remove_child(light)
	check(not fp._model_lights.has(light), "removed equipment cannot leave stale light references")
	fp.model.add_child(light)
	fp._sync_world_light_instances()
	check(fp._world_light_instances.has(light.get_instance()), "reattached light re-registers its rendering scenario")
	light.free()
	fp.set_external_view(false)
	# A density equal at both ends must not freeze length or sun scattering.
	var original_density:float=lighting._outdoor_volume_density
	lighting._outdoor_volume_density=0.0006
	player.camera.global_position=Vector3(-17,-31.75,0)
	player.camera.reset_physics_interpolation()
	await physics_frame
	await frames(2)
	lighting._indoor_mix=1.0
	env.volumetric_fog_density=0.0006
	env.volumetric_fog_length=160
	lighting.get_node("OvercastSun").light_volumetric_fog_energy=0.7
	lighting._process(1.0/60)
	check(is_equal_approx(env.volumetric_fog_length,32) and is_zero_approx(lighting.get_node("OvercastSun").light_volumetric_fog_energy), "roof transition updates fog length and sun scattering even at unchanged density")
	lighting._outdoor_volume_density=original_density
	menu.open_menu()
	await settle()
	menu.main_panel.get_node("Save").pressed.emit()
	check(menu.feedback_label.text=="Экспедиция сохранена.", "ESC Save publishes the current expedition")
	menu.return_to_main_menu()
	if not await wait_for(func(): return current_scene!=null and current_scene.is_in_group("main_menu") and not menu._transition_in_progress):
		check(false,"return reaches main menu"); quit(1); return
	await settle()
	check(not current_scene.continue_game_button.disabled and root.debug_draw==Viewport.DEBUG_DRAW_DISABLED, "return offers Continue without leaving a world debug override")
	await menu.start_standalone_flow(true)
	await frames(30)
	state=get_first_node_in_group("base_gameplay_controller")
	check(state!=null and state.main_breaker_on and current_scene.get_node("V3Level/BasePowerLightingController").is_standard_powered, "Continue restores saved power and its lighting")
	check(quality.preset_index(quality.values)==3 and not menu.is_menu_open(), "Continue retains selected graphics and closes the previous overlay")
	print("MENU LIGHTING CHAIN RESULT ",failures)
	quit(0 if failures.is_empty() else 1)
