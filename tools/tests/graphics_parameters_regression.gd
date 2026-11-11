extends SceneTree
## Apply real presets through Settings, then inspect the live world and render.
var checks := 0
var failures := 0
var output := "res://tools/.local/lighting-independent-2026-11-11/"
func _initialize():
	var prefix := "user://graphics_parameters_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+".cfg")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+"_save.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	create_timer(170).timeout.connect(func():quit(2));run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle(count := 20):
	for frame in count:await process_frame
func capture(label: String) -> Image:
	await settle(60);await RenderingServer.frame_post_draw
	var result:=root.get_texture().get_image();result.save_png(output+label+".png");return result
func run():
	DirAccess.make_dir_recursive_absolute(output)
	var menu=root.get_node("GameMenu");var quality=menu.get_node("GraphicsQuality");quality.set_process(false)
	menu._settings_data.WindowMode="windowed";menu._settings_data.Resolution="1280x720";menu._settings_data.VSync=false;menu._settings_data.GraphicsCalibrationPending=false
	menu.apply_settings_data();root.content_scale_size=Vector2i(1280,720)
	check(DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_WINDOWED and DisplayServer.window_get_size()==Vector2i(1280,720),"window mode and resolution reach the actual window")
	check(DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_DISABLED,"VSync Off reaches the actual display backend")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var arena=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(arena);current_scene=arena
	for frame in 30:await physics_frame
	menu.force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.body_animator.hide();actor.get_node("PlayerUI").hide()
	var state=arena.get_node("BaseGameplayController");state.set_process(false)
	var snap=state.get_snapshot();snap.main_breaker_on=true;snap.fuel_delivered=true;snap.fuel_liters=30.0;snap.containment["fault"]=false;state._broadcast_snapshot(snap)
	arena.get_node("SnowExterior/Blizzard").enabled=false
	var camera:=Camera3D.new();arena.add_child(camera);camera.position=Vector3(-27,1.7,-2);camera.look_at(Vector3(-22,2,-6.6));camera.current=true
	var lighting:WorldLighting=arena.get_node("WorldLighting")
	var gi=arena.get_node("WorldIndirectLighting")
	var tracks=arena.find_child("SnowTracks",true,false)
	var decal:=Decal.new();arena.add_child(decal)
	var rows:=[]
	for index in [1,2,3]:
		menu.open_settings();await create_timer(1.0).timeout
		var panel=menu.settings_panel;panel.select_category(1)
		panel._set_value("FPS",144,true);panel._set_value("Gamma",110,true);panel._set_value("MotionBlur",true,true);panel._set_value("MotionBlurStrength",55,true)
		var preset:OptionButton=panel.rows.find_child("Preset",true,false);preset.select(index);preset.item_selected.emit(index)
		check(panel.apply(false),"preset %d applies through the real Settings panel"%index)
		var selected:Dictionary=quality.PRESETS[index]
		check(quality.preset_index(quality.values)==index and quality.values.FPS==144 and quality.values.Gamma==110 and quality.values.MotionBlur and quality.values.MotionBlurStrength==55,"preset %d preserves calibration, frame cap and deliberate blur choices"%index)
		menu.force_close_menu();await settle()
		check(is_equal_approx(root.scaling_3d_scale,float(selected.Scale)/100.0) and root.msaa_3d==int(selected.MSAA) and root.screen_space_aa==(Viewport.SCREEN_SPACE_AA_FXAA if selected.FXAA else Viewport.SCREEN_SPACE_AA_DISABLED),"preset %d changes actual render resolution and anti-aliasing"%index)
		check(root.positional_shadow_atlas_size==(2048 if index==1 else 4096) and is_equal_approx(lighting.quality_shadow_distance,float(selected.ShadowDistance)),"preset %d changes real shadow budgets"%index)
		check(is_equal_approx(root.mesh_lod_threshold,float(selected.LOD)) and tracks!=null and tracks.max_marks==int(selected.TrackCount) and is_equal_approx(decal.distance_fade_begin,float(selected.DecalDistance)*.75),"preset %d updates LOD, snow capacity and existing decals"%index)
		check(gi.get_active_probe_count()>0 and camera.environment.ssao_enabled and camera.environment.glow_enabled,"preset %d retains authored lighting and real effects"%index)
		Engine.max_fps=0
		await capture("preset-%d"%index)
		var samples:Array[float]=[]
		for frame in 60:
			await process_frame;samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		samples.sort();rows.append({"preset":index,"gpu_median_ms":samples[30],"scale":root.scaling_3d_scale,"msaa":root.msaa_3d,"fxaa":root.screen_space_aa,"atlas":root.positional_shadow_atlas_size,"lod":root.mesh_lod_threshold,"tracks":tracks.max_marks,"decal_begin":decal.distance_fade_begin,"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		print("PRESET RENDER ",JSON.stringify(rows[-1]))
	var custom:Dictionary=quality.values.duplicate();custom.Scale=85;custom.FPS=75;custom.Brightness=115;custom.Gamma=130;custom.ShadowDistance=40;custom.DecalDistance=30;custom.TrackCount=96;custom.MotionBlur=true;custom.MotionBlurStrength=55
	quality.apply(custom);await settle()
	check(Engine.max_fps==75 and is_equal_approx(root.scaling_3d_scale,.85),"manual scale and custom frame cap reach the engine")
	check(is_equal_approx(camera.environment.adjustment_brightness,1.15) and camera.environment.adjustment_color_correction==load("res://assets/environments/calibration/gamma_130.tres"),"brightness and gamma reach the real camera")
	check(is_equal_approx(lighting.quality_shadow_distance,40.0) and tracks.max_marks==96 and is_equal_approx(decal.distance_fade_begin,22.5),"manual shadow, track and decal settings reach existing world objects")
	var effect=actor.get_node("PlayerUI/CameraPostProcess")
	check(effect.motion_blur_enabled and is_equal_approx(effect.motion_blur_strength,.55),"manual motion blur and strength reach the existing camera effect")
	var late:=Decal.new();arena.add_child(late);await settle(3)
	check(late.distance_fade_enabled and is_equal_approx(late.distance_fade_begin,22.5),"newly created decals inherit the current distance")
	menu._settings_data.Graphics=quality.values.duplicate();menu._settings_data.ShowFPS=true;menu.apply_settings_data()
	check(menu.get_node("FPSCounter").visible,"the FPS option activates the real counter")
	menu.open_settings();await create_timer(1.0).timeout
	var panel=menu.settings_panel;panel.select_category(1)
	var fps:OptionButton=panel.rows.find_child("FPS",true,false)
	check(fps.get_item_text(fps.selected)=="75","saved custom FPS is displayed accurately instead of Unlimited")
	panel.select_category(0)
	check(panel.rows.find_child("HDR",true,false).disabled == (not DisplayServer.window_is_hdr_output_supported()),"HDR availability reflects the current display capability")
	panel._set_value("WindowMode","maximized",false)
	check(panel.rows.find_child("Resolution",true,false).disabled,"maximized mode does not offer an ineffective resolution choice")
	panel._set_value("WindowMode","windowed",false)
	check(not panel.rows.find_child("Resolution",true,false).disabled,"windowed mode restores the resolution control")
	menu.force_close_menu();Engine.max_fps=60
	check(root.get_camera_3d()==camera,"fixed comparison camera remains the active world camera")
	# Confirm Glow actually changes pixels around a bright emitter, not just a flag.
	quality.apply({"GIQuality":0,"AOQuality":0,"Bloom":false,"Gamma":100,"Brightness":100})
	var emitter:=MeshInstance3D.new();var sphere:=SphereMesh.new();sphere.radius=.016;sphere.height=.032;emitter.mesh=sphere
	var material:=StandardMaterial3D.new();material.albedo_color=Color.BLACK;material.emission_enabled=true;material.emission=Color.WHITE;material.emission_energy_multiplier=8.0;emitter.material_override=material;arena.add_child(emitter);emitter.global_position=camera.global_transform*Vector3(0,0,-.4)
	var no_glow:=await capture("glow-off")
	custom=quality.values.duplicate();custom.Bloom=true;quality.apply(custom)
	var with_glow:=await capture("glow-on")
	var difference:=0.0;var count:=0
	for x in range(590,690,2):
		for y in range(310,410,2):
			if Vector2(x-640,y-360).length()<26:continue
			difference+=absf(with_glow.get_pixel(x,y).get_luminance()-no_glow.get_pixel(x,y).get_luminance());count+=1
	print("GLOW RING DIFFERENCE ",difference/maxi(count,1))
	check(difference/maxi(count,1)>.00001,"Glow creates an actual halo around a bright object")
	var invalid:Dictionary=quality.normalized({"Brightness":999,"Gamma":-1,"Scale":0,"ShadowQuality":9,"GIQuality":-10,"LOD":-2,"TrackCount":9999,"MSAA":99,"HDRWhite":999,"FPS":-30,"MotionBlurStrength":999})
	check(invalid.Brightness==140 and invalid.Gamma==70 and invalid.Scale==50 and invalid.ShadowQuality==3 and invalid.GIQuality==0 and invalid.LOD==1 and invalid.TrackCount==512 and invalid.MSAA==3 and invalid.HDRWhite==400 and invalid.FPS==0 and invalid.MotionBlurStrength==100,"out-of-range preferences normalize to the same legal values the renderer uses")
	var wrong_types:Dictionary=quality.normalized({"Scale":"broken","Bloom":{},"FPS":INF})
	check(wrong_types.Scale==100 and wrong_types.Bloom and wrong_types.FPS==0,"damaged value types recover without invalid render settings")
	var saved_file:=FileAccess.get_file_as_string(menu.get_settings_path())
	FileAccess.open(menu.get_settings_path(),FileAccess.WRITE).store_string(JSON.stringify({"Graphics":"damaged"}))
	var repaired:Dictionary=menu.load_settings_data()
	check(repaired.Graphics is Dictionary and repaired.Graphics.Scale==100 and repaired.Graphics.GIQuality==2,"a damaged Graphics block loads safe defaults through GameMenu")
	FileAccess.open(menu.get_settings_path(),FileAccess.WRITE).store_string(saved_file)
	FileAccess.open(output+"preset-render-results.json",FileAccess.WRITE).store_string(JSON.stringify(rows,"  "))
	current_scene=null;arena.queue_free();await settle(8)
	print("GRAPHICS PARAMETERS CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
