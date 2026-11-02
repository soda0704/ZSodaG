extends SceneTree
var actor: GamePlayer
var checks := 0
var failures := 0
var output := "res://tools/.local/blizzard-review/"

func _initialize() -> void:
	var prefix := "user://blizzard_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty(): output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	create_timer(90).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func settle(seconds: float = 0.7) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	picture.save_png(output+label+".png")
	return picture

func red_at(picture: Image, point: Vector2) -> float:
	var sum := 0.0
	for y in range(-3,4):
		for x in range(-3,4):
			var color := picture.get_pixel(clampi(int(point.x)+x,0,picture.get_width()-1),clampi(int(point.y)+y,0,picture.get_height()-1))
			sum += color.r-color.b
	return sum/49.0

func mean_luminance(picture: Image, area: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(area.position.y,area.end.y,4):
		for x in range(area.position.x,area.end.x,4):
			total += picture.get_pixel(x,y).get_luminance()
			count += 1
	return total/count

func marker(parent: Node3D, at: Vector3, size: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new(); box.size=Vector3.ONE*size
	var material := StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=Color(1,0,0)
	box.material=material;mesh.mesh=box
	parent.add_child(mesh);mesh.global_position=at
	return mesh

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene=base
	for frame in 25: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	actor=get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false)
	base.get_node("BaseGameplayController").set_process(false)
	var lighting: WorldLighting=base.get_node("WorldLighting")
	var weather=base.get_node("SnowExterior/Blizzard")
	var quality=root.get_node("GameMenu/GraphicsQuality")
	check(get_nodes_in_group("local_blizzard").size()==1,"loaded world owns exactly one local snow field")
	check(not weather.flakes.local_coords and weather.flakes.amount==1800,"bounded GPU snow remains in world space after emission")
	actor.teleport_authoritative(Vector3(-60,3,50),0)
	actor.camera.rotation=Vector3.ZERO
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
	weather.gust_period=1000000.0;weather._elapsed=0.0
	weather.enabled=false
	await settle(1.0)
	var near=marker(base,actor.camera.global_position+Vector3(1.2,0,-4),0.8)
	var far=marker(base,actor.camera.global_position+Vector3(-4,0,-25),3.0)
	await settle()
	var near_pixel:=actor.camera.unproject_position(near.global_position)
	var far_pixel:=actor.camera.unproject_position(far.global_position)
	var clear:=await capture("visibility-clear")
	check(red_at(clear,near_pixel)>.3 and red_at(clear,far_pixel)>.3,"both distance markers are genuinely visible before the storm")
	weather.enabled=true
	await settle(1.2)
	check(lighting._indoor_mix<.001 and weather.outside_weight>.99 and weather.flakes.visible,"outdoors activates snow and the storm profile")
	var ends: Array[float]=[]
	for advanced in [false,true]:
		quality.set_advanced_lighting_enabled(advanced)
		await settle()
		var image:=await capture("visibility-storm-"+str(advanced))
		var close_red:=red_at(image,near_pixel);var distant_red:=red_at(image,far_pixel)
		print("STORM PIXELS advanced=",advanced," near=",close_red," far=",distant_red)
		check(close_red>.18 and distant_red<.04,"storm preserves a 4 m object but hides a 25 m object, advanced="+str(advanced))
		check(actor.camera.environment.fog_enabled and actor.camera.environment.fog_density>.97,"visibility fog survives the lighting quality switch")
		ends.append(actor.camera.environment.fog_depth_end)
	check(absf(ends[0]-ends[1])<.01,"both light modes keep the same authored visibility distance")
	lighting.set_process(false)
	weather.gust_period=18;weather._elapsed=0;lighting._process(.01)
	var calm:float=actor.camera.environment.fog_depth_end
	weather._elapsed=6.8;lighting._process(.01)
	check(calm>19.5 and actor.camera.environment.fog_depth_end<11.5,"gusts reduce visibility from about 20 m to 11 m")
	lighting.set_process(true)
	near.queue_free();far.queue_free()
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=true
	actor.teleport_authoritative(Vector3(-53.7224,2.02075,37.8333),0)
	actor.camera.look_at(Vector3(-17,2.5,1))
	await settle(1.0)
	print("APPROACH FOG mode=",actor.camera.environment.fog_mode," density=",actor.camera.environment.fog_density," end=",actor.camera.environment.fog_depth_end," sky=",actor.camera.environment.fog_sky_affect," indoor=",lighting._indoor_mix)
	var advanced_image:=await capture("base-approach-storm")
	quality.set_advanced_lighting_enabled(false);await settle()
	var basic_image:=await capture("base-approach-basic")
	var far_terrain:=Rect2i(180,200,90,70)
	var landscape_delta:=absf(mean_luminance(advanced_image,far_terrain)-mean_luminance(basic_image,far_terrain))
	print("STORM LANDSCAPE QUALITY DELTA ",landscape_delta)
	check(landscape_delta<.02,"volumetric shadows do not reveal distant cliff silhouettes in advanced mode")
	quality.set_advanced_lighting_enabled(true)
	actor.teleport_authoritative(Vector3(-45,.1,3),-PI/2)
	actor.camera.rotation=Vector3.ZERO
	await settle(1.0);await capture("entrance-near-storm")
	actor.teleport_authoritative(Vector3(-36.5,.1,3),-PI/2)
	actor.camera.rotation=Vector3.ZERO
	await settle(1.0)
	check(lighting._indoor_mix>.999 and not weather.flakes.visible and not weather.flakes.emitting,"entering the vestibule removes the local snow field")
	check(actor.camera.environment.fog_density<.0001 and weather.local_storm_intensity()==0,"indoor air stays clear and local storm audio target fades to zero")
	await capture("vestibule-clear")
	check(base.get_node("BaseAmbience")._blizzard==weather,"existing storm audio follows this weather instance without a second player")
	actor.teleport_authoritative(Vector3(-60,3,50),0)
	await settle()
	check(weather.flakes.visible and weather.outside_weight>.99,"returning outdoors restores weather after teleport without another field")
	weather.enabled=false;await settle()
	check(not weather.flakes.visible and is_equal_approx(actor.camera.environment.fog_depth_end,450.0),"disabling the prototype restores the original outdoor haze")
	actor=null;current_scene=null;base.queue_free()
	for frame in 5:await process_frame
	check(get_nodes_in_group("local_blizzard").is_empty(),"unloading the world removes the local weather instance")
	print("BLIZZARD CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
