extends SceneTree
## Real player camera, world-space surface samples and identical light budgets.
const OUT := "res://tools/.local/world-lighting-review/"
var failures := 0

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://world_lighting_test.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1

func frames(count: int) -> void:
	for frame in count: await process_frame

func sample(picture: Image, camera: Camera3D, point: Vector3) -> float:
	var pixel := Vector2i(camera.unproject_position(point)*Vector2(picture.get_size())/root.get_visible_rect().size)
	if pixel.x<3 or pixel.y<3 or pixel.x>=picture.get_width()-3 or pixel.y>=picture.get_height()-3: return -1.0
	var total:=0.0
	for x in range(pixel.x-2,pixel.x+3):
		for y in range(pixel.y-2,pixel.y+3):
			var color:=picture.get_pixel(x,y)
			total+=color.r*0.2126+color.g*0.7152+color.b*0.0722
	return total/25.0

func mean(picture: Image) -> float:
	var total:=0.0
	for x in 48:
		for y in 27:
			var c:=picture.get_pixel(x*picture.get_width()/48,y*picture.get_height()/27)
			total+=(c.r+c.g+c.b)/3.0
	return total/(48.0*27.0)

func capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	picture.save_png(OUT+label+".png")
	return picture

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(1); return
	var menu=root.get_node("GameMenu")
	menu.force_close_menu()
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(960,540)
	if "--full-hd" in OS.get_cmdline_user_args():root.size=Vector2i(1920,1080)
	Engine.max_fps=60
	if "--no-vsync" in OS.get_cmdline_user_args():DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var level:BaseBlockoutRuntime=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	level.network_runtime_managed=true
	root.add_child(level)
	var state:BaseGameplayController=level.get_node("BaseGameplayController")
	state.set_process(false)
	state.containment={"fault":false}
	var power:BasePowerLightingController=level.get_node("BasePowerLightingController")
	var lighting=level.get_node("WorldLighting")
	var indirect: Node3D=level.get_node("WorldIndirectLighting")
	var probes:=indirect.find_children("*","VoxelGI",true,false)
	check(probes.size()==8,"all eight lighting zones have baked voxel geometry")
	var interior_probes:=true
	var overlap_safe:=true
	for probe:VoxelGI in probes:
		interior_probes=interior_probes and probe.data!=null and probe.data.interior==(probe.position.y<0.0) and probe.data.use_two_bounces and is_equal_approx(probe.data.energy,0.7)
		var bounds:=AABB(probe.position-probe.size/2,probe.size)
		for other:VoxelGI in probes:
			if probe==other:continue
			var intersection:=bounds.intersection(AABB(other.position-other.size/2,other.size))
			if not intersection.has_volume():continue
			for third:VoxelGI in probes:
				if third!=probe and third!=other and intersection.intersects(AABB(third.position-third.size/2,third.size)):overlap_safe=false
	check(interior_probes and overlap_safe,"underground GI excludes sky while surface GI preserves exterior ambient; no triple overlap")
	var authored: Environment = level.get_node("SnowExterior/OvercastDayEnvironment").environment
	var panorama := authored.sky.sky_material as PanoramaSkyMaterial
	check(panorama != null and panorama.panorama.resource_path.ends_with("overcast_soil_puresky_4k.exr") and panorama.panorama.get_width() == 4096,"sky uses the full-resolution project EXR")
	check(authored.sky.radiance_size == Sky.RADIANCE_SIZE_1024 and authored.sky.process_mode == Sky.PROCESS_MODE_QUALITY,"static HDR sky uses quality radiance processing")
	var player:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
	player.setup(1,"World lighting",Vector3(-25,0.1,0),Color.WHITE,-PI/2)
	level.add_child(player)
	player.set_physics_process(false);player.set_process_unhandled_input(false)
	player.survival.set_physics_process(false);player.weapon.set_physics_process(false)
	player.get_node("PlayerRagdoll").set_physics_process(false)
	player.apply_held_item_inventory(&"pistol",{})
	player.weapon.apply_state(&"pistol",12,0)
	player.update_character_animation(1.0/60)
	var camera:Camera3D=player.camera
	camera.make_current()
	await frames(45)
	if "--approach-check" in OS.get_cmdline_user_args():
		player.debug_free_camera.set_enabled(true)
		camera=player.debug_free_camera
		camera.set_process(false)
		power.apply_power_state(true)
		var points:=[Vector3(-38.16,2.8,-6.7),Vector3(-24,5.95,0),Vector3(0,8.5,0),Vector3(23,5.95,2)]
		var far_values:Array=[]
		for pose in [["far",Vector3(-95,22,32)],["near",Vector3(-58,8,18)],["above",Vector3(-30,14,20)]]:
			camera.global_position=pose[1];camera.look_at(Vector3(-15,3,0))
			await frames(45)
			var picture:=await capture("approach-"+pose[0])
			var values:Array=[]
			for point in points:values.append(sample(picture,camera,point))
			print("APPROACH ",pose[0]," probes=",indirect.get_active_probe_count()," ambient=",camera.environment.ambient_light_energy," samples=",values)
			check(indirect.get_active_probe_count()==3,"exterior "+pose[0]+" keeps surface GI resident")
			check(values[0]>0.06 and values[1]>0.1,"exterior "+pose[0]+" facade and roof retain visible light")
			if pose[0]=="far":far_values=values.duplicate()
			if pose[0]=="near":check(absf(values[0]-far_values[0])<0.035 and absf(values[1]-far_values[1])<0.035,"approaching the base does not abruptly replace its exterior lighting")
			if pose[0]=="near" and "--approach-diagnose" in OS.get_cmdline_user_args():
				indirect.hide();await frames(30)
				picture=await capture("approach-near-no-gi");values=[]
				for point in points:values.append(sample(picture,camera,point))
				print("APPROACH near no GI samples=",values)
				indirect.show()
		print("APPROACH FAILURES ",failures)
		quit(1 if failures else 0);return
	if "--profile-gi" in OS.get_cmdline_user_args():
		power.apply_power_state(true)
		if "--free-inactive-gi" in OS.get_cmdline_user_args():
			for probe:VoxelGI in probes:
				if absf(camera.global_position.y-probe.global_position.y)>probe.size.y*0.5+2.0:probe.data=null
		await frames(60)
		var dynamic_objects:Array[GeometryInstance3D]=[]
		for geometry:GeometryInstance3D in level.find_children("*","GeometryInstance3D",true,false):
			if geometry.gi_mode==GeometryInstance3D.GI_MODE_DYNAMIC:dynamic_objects.append(geometry)
		print("GI PROFILE dynamic_objects=",dynamic_objects.size())
		print("GI PROFILE sizes main=",root.size," texture=",root.get_texture().get_size()," scale=",root.scaling_3d_scale," msaa=",root.msaa_3d," logical=",root.get_visible_rect().size," hands=",player.body_animator.first_person.viewport.size)
		var modes:=["full","hands_no_glow","hands_no_msaa","no_hands","static_geometry","no_volume","direct_only","no_sun","no_shadows","no_ssao","no_glow"]
		if "--profile-short" in OS.get_cmdline_user_args():modes=["full","no_hands"]
		if "--profile-balanced" in OS.get_cmdline_user_args():modes=["full","low_filter","two_cascades","hands_2x","hands_half","no_ssao","scale_75"]
		var route:={
			"hub":[Vector3(0,1.75,6),Vector3(0,1.6,-4)],
			"living":[Vector3(23,1.75,-1),Vector3(28,1.7,2)],
			"level-1":[Vector3(-8,-16.25,3),Vector3(-14,-16.0,0)],
			"level-2":[Vector3(-17,-31.75,0),Vector3(-29,-33.5,0)],
			"level-3":[Vector3(-25,-52.25,1),Vector3(-30,-52,-10)],
			"level-4":[Vector3(-5.5,-70.25,2),Vector3(-11,-70.25,0)],
			"level-5":[Vector3(-6.25,-88.25,2),Vector3(-13,-88.25,0)],
			"exterior":[Vector3(-65,2.5,8),Vector3(-38,2,0)],
			"exterior-near":[Vector3(-58,8,18),Vector3(-15,3,0)],
			"exterior-far":[Vector3(-95,22,32),Vector3(-15,3,0)]}
		if "--profile-route" in OS.get_cmdline_user_args():modes=["full"]+route.keys()
		for mode in modes:
			if route.has(mode):
				camera.global_position=route[mode][0]
				camera.look_at(route[mode][1])
			if mode=="low_filter":
				RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
				RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW)
			if mode=="two_cascades":level.get_node("WorldLighting/OvercastSun").directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			if mode=="hands_2x":player.body_animator.first_person.viewport.msaa_3d=Viewport.MSAA_2X
			if mode=="hands_half":
				player.body_animator.first_person.viewport.scaling_3d_scale=0.5
				player.body_animator.first_person._disabled=true
			if mode=="scale_75":root.scaling_3d_scale=0.75
			if mode=="hands_no_glow":player.body_animator.first_person.view_camera.environment.glow_enabled=false
			if mode=="hands_no_msaa":player.body_animator.first_person.viewport.msaa_3d=Viewport.MSAA_DISABLED
			if mode=="static_geometry":
				for geometry in dynamic_objects:geometry.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
			if mode=="no_volume":camera.environment.volumetric_fog_enabled=false
			if mode=="direct_only":indirect.hide()
			if mode=="no_sun":level.get_node("WorldLighting/OvercastSun").hide()
			if mode=="no_shadows":
				for source:Light3D in level.find_children("*","Light3D",true,false):source.shadow_enabled=false
			if mode=="no_hands":player.body_animator.first_person.set_external_view(true)
			if mode=="no_ssao":camera.environment.ssao_enabled=false
			if mode=="no_glow":camera.environment.glow_enabled=false
			await frames(30)
			var started:=Time.get_ticks_msec()
			await frames(60)
			print("GI PROFILE ",mode," fps=",60000.0/(Time.get_ticks_msec()-started)," cpu_ms=",Performance.get_monitor(Performance.TIME_PROCESS)*1000," physics_ms=",Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," primitives=",Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)," gpu_mem_mb=",Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0)
		quit();return
	check(lighting.is_covered(camera.global_position),"roof detection identifies the interior")
	check(not lighting.is_covered(Vector3(-70,3,0)),"roof detection identifies open exterior")
	check(not player.body_animator.first_person._lighting_fill.shadow_enabled and player.body_animator.first_person.viewport.positional_shadow_atlas_size==0,"hands do not render a second set of world shadows")
	check(player.body_animator.first_person.viewport.world_3d!=camera.get_world_3d(),"hands render in an isolated world without traversing the base")
	check(player.body_animator.first_person.viewport.size==root.size,"hand render target matches physical window pixels")
	check(not root.positional_shadow_atlas_16_bits,"world positional shadows use full depth precision")
	check(indirect.get_active_probe_count()==3,"ground-floor view processes only its three GI zones")
	var hands_environment_id:=player.body_animator.first_person.view_camera.environment.get_instance_id()
	menu.get_node("GraphicsQuality").apply({"SSIL":true,"SSR":true,"Glow":true,"SunShadows":false,"LocalShadows":false,"Brightness":100,"Gamma":100,"FPS":60})
	await frames(20)
	check(not camera.environment.ssil_enabled and not camera.environment.ssr_enabled and not camera.environment.sdfgi_enabled,"legacy graphics settings cannot reintroduce unstable indirect lighting")
	check(camera.environment.ssao_enabled and camera.environment.glow_enabled and camera.environment.fog_enabled,"authored ambient occlusion, bloom and sky haze survive saved quality settings")
	check(is_zero_approx(camera.environment.fog_density),"outdoor haze does not wash out interiors")
	check(camera.environment.volumetric_fog_enabled and not camera.environment.volumetric_fog_temporal_reprojection_enabled,"real volumetric scattering runs without temporal ghost trails")
	check(not player.body_animator.first_person.view_camera.environment.volumetric_fog_enabled,"hands never render the world's volumetric scattering again")
	power.apply_power_state(false)
	await frames(40)
	var emergency:=await capture("garage-emergency")
	power.apply_power_state(true)
	await frames(40)
	var powered:=await capture("garage-powered")
	var saved_breaker: bool = state.main_breaker_on
	state.main_breaker_on = true
	state.containment["fault"] = true
	state.snapshot_changed.emit(state.get_snapshot())
	await frames(40)
	var fault_picture := await capture("garage-fault")
	check(not power.is_standard_powered and not level.get_node("WorldLighting/Standard").visible, "electrical fault extinguishes standard sources without changing the breaker")
	check(mean(fault_picture) < mean(powered) * 0.85, "fault visibly darkens the room to emergency lighting")
	state.containment["fault"] = false
	state.snapshot_changed.emit(state.get_snapshot())
	state.main_breaker_on = saved_breaker
	await frames(40)
	# VoxelGI also occludes the fallback ambient; isolate the actual bounce
	# contribution with ambient zero in both comparison frames.
	var saved_ambient:float=lighting.indoor_ambient
	lighting.indoor_ambient=0.0
	await frames(40)
	var bounced_only:=await capture("garage-bounce-comparison")
	indirect.hide()
	await frames(40)
	var direct_only:=await capture("garage-direct-only")
	indirect.show()
	lighting.indoor_ambient=saved_ambient
	await frames(40)
	await capture("garage-powered")
	print("GI LEVELS direct=",mean(direct_only)," bounced=",mean(bounced_only))
	check(mean(bounced_only)>mean(direct_only)+0.005,"voxel indirect light visibly contributes beyond direct lamps")
	check(mean(powered)<0.22,"indirect light preserves the dark horror interior")
	print("LIGHT LEVELS emergency=",mean(emergency)," powered=",mean(powered))
	check(mean(powered)>mean(emergency)*1.15,"standard room lighting is brighter than the emergency circuit")
	var home:=camera.global_transform
	var targets:Array[Vector3]=[]
	for screen:Vector2 in [Vector2(.23,.82),Vector2(.30,.75),Vector2(.34,.68),Vector2(.18,.28),Vector2(.8,.28)]:
		var ray:=camera.project_ray_normal(screen*root.get_visible_rect().size)
		var hit:=camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position+ray*35,1,[player.get_rid()]))
		if not hit.is_empty():targets.append(hit.position)
	check(targets.size()>=3,"motion test samples real world surfaces outside the hand overlay")
	var largest_jump:=0.0
	var previous:Array[float]=[]
	var maximum_lamps:=0
	var brightest_sample:=0.0
	for index in 31:
		camera.global_transform=home
		camera.global_position+=Vector3(sin(index*.12)*.25,0,0)
		camera.global_rotate(Vector3.UP,lerpf(-.12,.12,index/30.0))
		await frames(3)
		var picture:=await capture("motion-%02d"%index)
		var values:Array[float]=[]
		for point in targets:
			var measured:=sample(picture,camera,point)
			values.append(measured)
			brightest_sample=maxf(brightest_sample,measured)
		for i in values.size():
			if not previous.is_empty() and values[i]>=0 and previous[i]>=0:largest_jump=maxf(largest_jump,absf(values[i]-previous[i]))
		previous=values
		var active:=0
		for lamp in level.find_children("*","SpotLight3D",true,false):
			if lamp.is_visible_in_tree() and lamp.shadow_enabled:active+=1
		maximum_lamps=maxi(maximum_lamps,active)
		check(is_equal_approx(camera.environment.ambient_light_energy,lighting.indoor_ambient),"camera rotation preserves indoor ambient %d"%index)
	print("MOTION largest_luminance_step=",largest_jump," max_shadow_lamps=",maximum_lamps)
	check(largest_jump<0.07,"small camera motion does not abruptly switch surface lighting")
	check(brightest_sample>0.04,"motion stability includes lit surfaces, not only black shadows")
	check(maximum_lamps<=16,"all resident lamp shadows fit equal-sized atlas slots")
	camera.global_transform=home
	await frames(20)
	var with_sun:=await capture("interior-sun-on")
	level.get_node("WorldLighting/OvercastSun").hide()
	await frames(20)
	var without_sun:=await capture("interior-sun-off")
	var sun_leak:=0.0
	for point in targets:sun_leak=maxf(sun_leak,absf(sample(with_sun,camera,point)-sample(without_sun,camera,point)))
	check(sun_leak<0.01,"exterior sunlight does not illuminate interior surfaces")
	level.get_node("WorldLighting/OvercastSun").show()
	var locations := [
		["hub",Vector3(0,1.75,6),Vector3(0,1.6,-4)],
		["technical-storage",Vector3(0,1.75,12),Vector3(-3.5,1.6,18)],
		["generator",Vector3(-3.5,1.75,20),Vector3(1.5,1.6,22)],
		["living",Vector3(23,1.75,-1),Vector3(28,1.7,2)],
		["level-1",Vector3(-8,-16.25,3),Vector3(-14,-16.0,0)],
		["level-2",Vector3(-17,-31.75,0),Vector3(-29,-33.5,0)],
		["level-3",Vector3(-25,-52.25,1),Vector3(-30,-52,-10)],
		["level-4",Vector3(-5.5,-70.25,2),Vector3(-11,-70.25,0)],
		["level-5",Vector3(-6.25,-88.25,2),Vector3(-13,-88.25,0)]
	]
	for location in locations:
		camera.global_position=location[1]
		camera.look_at(location[2])
		await frames(30)
		var room_picture:=await capture(location[0])
		print("ROOM ",location[0]," mean=",mean(room_picture)," fps=",Engine.get_frames_per_second())
		check(is_equal_approx(camera.environment.ambient_light_energy,lighting.indoor_ambient),"room "+location[0]+" uses interior lighting")
		var residents:=0
		for lamp in level.find_children("*","SpotLight3D",true,false):
			if lamp.is_visible_in_tree() and lamp.shadow_enabled:residents+=1
		check(residents<=16,"room "+location[0]+" stays within the shadow budget")
		check(indirect.get_active_probe_count()<=3,"room "+location[0]+" does not render GI on unrelated floors")
		var resident_probes:=0
		for probe:VoxelGI in probes:
			if probe.data!=null:resident_probes+=1
		check(resident_probes<=3,"room "+location[0]+" releases distant GPU volumes")
		check(player.body_animator.first_person.view_camera.environment.get_instance_id()==hands_environment_id,"room "+location[0]+" reuses the hand environment")
	var smooth_handover := true
	var bounded_handover := true
	for step in 120:
		var before: Dictionary = lighting._levels.duplicate()
		var route := Vector3(lerpf(-35.0, 30.0, step / 119.0), 1.75, 0.0)
		lighting._update_lamps(route, 1.0 / 60.0)
		var residents := 0
		for lamp in lighting._lamps:
			var lamp_level: float = lighting._levels[lamp]
			if lamp_level > 0.0: residents += 1
			if absf(lamp_level - float(before[lamp])) > 5.0 / 60.0 + 0.0001: smooth_handover = false
		if residents > lighting.MAX_RESIDENT_LAMPS: bounded_handover = false
	check(smooth_handover,"changing nearest lamps never abruptly removes a resident light")
	check(bounded_handover,"lamp handover reserves flashlight slots even during rapid traversal")
	camera.global_transform=home
	power.apply_power_state(false)
	player.apply_held_item_inventory(&"flashlight",{})
	player.apply_flashlight_inventory(true,1.0,true)
	player.update_character_animation(1.0/60)
	await frames(40)
	var flashlight_picture:=await capture("flashlight")
	check(indirect.get_node("Entrance").data!=null and indirect.get_node("Control").data==null,"return to ground floor restores its GI and releases underground volumes")
	check(player.flashlight.beam.is_visible_in_tree() and player.flashlight.beam.shadow_enabled,"handheld flashlight casts world shadows")
	check(mean(flashlight_picture)>mean(emergency),"flashlight makes the emergency room more readable")
	player.flashlight.set_enabled(false,false)
	camera.global_position=Vector3(-65,2.5,8)
	camera.look_at(Vector3(-38,2,0))
	await frames(45)
	await capture("exterior")
	check(is_equal_approx(camera.environment.ambient_light_energy,lighting.outdoor_ambient),"exterior has its own low ambient level")
	check(is_equal_approx(camera.environment.fog_density,authored.fog_density),"exterior receives the authored distance haze")
	player.apply_held_item_inventory(&"",{})
	player.update_character_animation(1.0/60)
	camera.look_at(camera.global_position+Vector3(-150,160,-150))
	await frames(35)
	var sky_picture:=await capture("sky-clouds")
	var lowest:=1.0
	var highest:=0.0
	var clipped:=0
	var sky_samples:=0
	for x in range(4,44):
		for y in range(3,11):
			var screen:=Vector2(x/48.0,y/27.0)*root.get_visible_rect().size
			var ray:=camera.project_ray_normal(screen)
			var hit:=camera.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position+ray*400,1,[player.get_rid()]))
			if not hit.is_empty():continue
			var color:=sky_picture.get_pixel(x*sky_picture.get_width()/48,y*sky_picture.get_height()/27)
			var luminance:=color.get_luminance()
			lowest=minf(lowest,luminance);highest=maxf(highest,luminance)
			sky_samples+=1
			if minf(color.r,minf(color.g,color.b))>0.98:clipped+=1
	print("SKY cloud_contrast=",highest-lowest," clipped_samples=",clipped," sky_samples=",sky_samples)
	check(sky_samples>100 and highest-lowest>0.05 and clipped<sky_samples/100,"clouds retain visible detail without white clipping")
	for view in [["valley-west",Vector3(-90,3,0),Vector3(-270,45,-40)],["valley-east",Vector3(70,4,40),Vector3(280,65,0)]]:
		camera.global_position=view[1]
		camera.look_at(view[2])
		await frames(20)
		await capture(view[0])
	var quality = menu.get_node("GraphicsQuality")
	quality.apply(quality.PRESETS[1])
	await frames(30)
	check(is_equal_approx(lighting.get_node("OvercastSun").directional_shadow_max_distance,48.0),"Low preset caps exterior shadows at 48 metres")
	quality.apply(quality.PRESETS[3])
	await frames(30)
	check(is_equal_approx(lighting.get_node("OvercastSun").directional_shadow_max_distance,96.0),"High preset restores authored exterior shadow distance")
	check(not level.get_node("SnowExterior/Terrain3D/MouseViewport/MouseCamera").environment.ssao_enabled,"preset switching preserves Terrain3D picking environment")
	print("WORLD LIGHTING FAILURES ",failures)
	quit(1 if failures else 0)
