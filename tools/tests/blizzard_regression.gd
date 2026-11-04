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

func marker_red(picture: Image, center: Vector2) -> float:
	var strongest := -1.0
	for y in range(-45,46,5):
		for x in range(-45,46,5):
			strongest = maxf(strongest, red_at(picture, center + Vector2(x,y)))
	return strongest

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
	check(not weather.flakes.local_coords and weather.flakes.amount==2800,"denser small snowflakes remain in world space after emission")
	actor.teleport_authoritative(Vector3(-60,3,50),0)
	actor.camera.rotation=Vector3.ZERO
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
	weather.gust_period=1000000.0;weather._elapsed=0.0
	weather.enabled=false
	await settle(1.0)
	var near=marker(base,actor.camera.global_position+Vector3(1.2,0,-4),0.8)
	var far=marker(base,actor.camera.global_position+Vector3(-4,0,-25),3.0)
	var transparent_far=marker(base,actor.camera.global_position+Vector3(4,0,-25),3.0)
	var transparent_material: StandardMaterial3D = transparent_far.mesh.material
	transparent_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent_material.albedo_color.a = .85
	await settle()
	var near_pixel:=actor.camera.unproject_position(near.global_position)
	var far_pixel:=actor.camera.unproject_position(far.global_position)
	var transparent_pixel:=actor.camera.unproject_position(transparent_far.global_position)
	var clear:=await capture("visibility-clear")
	check(red_at(clear,near_pixel)>.3 and red_at(clear,far_pixel)>.3,"both distance markers are genuinely visible before the storm")
	check(red_at(clear,transparent_pixel)>.3,"transparent distance marker is visible before storm")
	weather.enabled=true
	await settle(1.2)
	weather.fog_material.render_priority = -100
	await settle()
	var old_order:=await capture("transparent-old-order")
	check(red_at(old_order,transparent_pixel)>.3,"old render order reproduces transparent geometry leaking through storm")
	weather.fog_material.render_priority = 126
	await settle()
	check(lighting._indoor_mix<.001 and weather.outside_weight>.99 and weather.flakes.visible,"outdoors activates snow and the storm profile")
	var ends: Array[float]=[]
	for advanced in [false,true]:
		quality.set_advanced_lighting_enabled(advanced)
		await settle()
		var image:=await capture("visibility-storm-"+str(advanced))
		var close_red:=red_at(image,near_pixel);var distant_red:=red_at(image,far_pixel)
		print("STORM PIXELS advanced=",advanced," near=",close_red," far=",distant_red)
		check(close_red>.18 and distant_red<.04,"storm preserves a 4 m object but hides a 25 m object, advanced="+str(advanced))
		check(red_at(image,transparent_pixel)<.04,"transparent geometry cannot draw through distant storm, advanced="+str(advanced))
		check(weather.fog_quad.visible and actor.camera.environment.fog_density<.001,"spatial exterior fog survives the lighting quality switch")
		ends.append(weather.visibility_distance())
	check(absf(ends[0]-ends[1])<.01,"both light modes keep the same authored visibility distance")
	lighting.set_process(false)
	weather.gust_period=18;weather._elapsed=0;lighting._process(.01)
	var calm:float=weather.visibility_distance()
	weather._elapsed=6.8;lighting._process(.01)
	check(calm>22.5 and weather.visibility_distance()<12.8,"visibility distances increased fourteen percent as requested")
	lighting.set_process(true)
	near.queue_free();far.queue_free();transparent_far.queue_free()
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
	check(lighting._indoor_mix>.999 and weather.flakes.visible and weather.fog_quad.visible,"weather remains rendered outside when viewed from the vestibule")
	check(actor.camera.environment.fog_density<.0001 and weather.local_storm_intensity()==0,"indoor air stays clear and local storm audio target fades to zero")
	await capture("vestibule-clear")
	actor.camera.look_at(actor.camera.global_position+Vector3.LEFT*30)
	await settle()
	var marker_outside=marker(base,Vector3(-64,actor.camera.global_position.y,3),4)
	weather.enabled=false;await settle()
	var door_clear:=await capture("doorway-storm-off")
	var marker_pixel:=actor.camera.unproject_position(marker_outside.global_position)
	weather.enabled=true;await settle()
	var door_storm:=await capture("doorway-storm-on")
	print("DOORWAY RED clear=",marker_red(door_clear,marker_pixel)," storm=",marker_red(door_storm,marker_pixel))
	check(marker_red(door_clear,marker_pixel)>.3 and marker_red(door_storm,marker_pixel)<.04,"exterior marker is hidden by storm when looking out from inside")
	marker_outside.queue_free()
	var console=root.get_node("DeveloperConsole")
	check(console._execute_one("/camera_filters off").contains("выключено") and not actor.get_node("PlayerUI/CameraPostProcess").effect_enabled,"console disables local camera filters")
	console._execute_one("/camera_filters on")
	console._execute_one("/blizzard off");await settle()
	check(not weather.enabled and not weather.fog_quad.visible and not weather.flakes.visible,"console disables exterior fog and snow together")
	console._execute_one("/blizzard on");await settle()
	check(weather.enabled and weather.fog_quad.visible,"console restores storm without creating another instance")
	check(base.get_node("BaseAmbience")._blizzard==weather,"existing storm audio follows this weather instance without a second player")
	actor.teleport_authoritative(Vector3(-60,3,50),0)
	await settle(1.0)
	check(weather.flakes.visible and weather.outside_weight>.99,"returning outdoors restores weather after teleport without another field")
	weather.enabled=false;await settle()
	check(not weather.flakes.visible and not actor.camera.environment.fog_enabled and not actor.camera.environment.volumetric_fog_enabled,"disabling weather leaves clear air without a second distant fog layer")
	actor=null;current_scene=null;base.queue_free()
	for frame in 5:await process_frame
	check(get_nodes_in_group("local_blizzard").is_empty(),"unloading the world removes the local weather instance")
	print("BLIZZARD CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
