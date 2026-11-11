extends SceneTree
var checks:=0
var failures:=0
var base:Node3D
var lighting:WorldLighting
var camera:Camera3D
var alarm:AudioStreamPlayer
var dark_time:=0.0
var output:="res://tools/.local/interior-lighting-2026-11-06/captures/"
func _initialize():
	var prefix:="user://interior_daylight_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	create_timer(160).timeout.connect(func():quit(2));run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func capture(label:String,at:Vector3,target:Vector3,powered:bool=false)->Image:
	camera.position=at;camera.look_at(target);camera.reset_physics_interpolation()
	await physics_frame
	if not powered:
		alarm.play(dark_time);await process_frame;alarm.stream_paused=true
	for i in 70:
		lighting._process(1.0/60.0)
		if not powered:
			alarm.animation.seek(dark_time,true);lighting.emergency_intensity=0.0;lighting.emergency_intensity_changed.emit(0.0)
			lighting._update_lamps(camera.position,1.0/60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();picture.save_png(output+label+".png");return picture
func mean(picture:Image,rect:Rect2i)->float:
	var total:=0.0;var count:=0
	for y in range(rect.position.y,rect.end.y,5):
		for x in range(rect.position.x,rect.end.x,5):total+=picture.get_pixel(x,y).get_luminance();count+=1
	return total/maxi(1,count)
func floor_mean(picture:Image)->float:
	var total:=0.0;var count:=0
	for y in range(240,680,8):
		for x in range(300,1150,8):
			var ray:=camera.project_ray_normal(Vector2(x,y))
			var hit:=base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera.position,camera.position+ray*30.0,0xFFFFFFFF))
			if hit.is_empty() or hit.normal.y<.8 or hit.position.x< -37.7 or hit.position.x> -34.0 or absf(hit.position.z-3)>1.5:continue
			total+=picture.get_pixel(x,y).get_luminance();count+=1
	print("INTERIOR FLOOR samples=",count," mean=",total/maxi(1,count))
	return total/maxi(1,count)
func set_power(powered:bool):
	var state:BaseGameplayController=base.get_node("BaseGameplayController")
	var snapshot:=state.get_snapshot();snapshot.main_breaker_on=powered;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.0;snapshot.containment["fault"]=false
	state._broadcast_snapshot(snapshot)
func run():
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,720);root.content_scale_size=root.size;Engine.max_fps=60
	base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
	for i in 30:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.body_animator.hide();actor.get_node("PlayerUI").hide()
	actor.teleport_authoritative(Vector3(-60,0,16),0)
	base.get_node("BaseGameplayController").set_process(false);base.get_node("SnowExterior/Blizzard").enabled=false
	lighting=base.get_node("WorldLighting");lighting.set_process(false)
	alarm=lighting.get_node("EmergencyAlarm")
	var animation:Animation=alarm.animation.get_animation("alarm")
	for sample in ceili(animation.length*100):
		if is_zero_approx(animation.value_track_interpolate(0,sample*.01)):dark_time=sample*.01+.02;break
	var source:=lighting.source_environment()
	check(source.ambient_light_source==Environment.AMBIENT_SOURCE_SKY and is_equal_approx(source.ambient_light_sky_contribution,1.0),"exterior diffuse ambient comes from the authored sky")
	check(is_equal_approx(source.adjustment_contrast,1.0),"grading does not lift physically black surfaces")
	var valid_gi:=true
	for probe in base.get_node("WorldIndirectLighting").get_children():
		if probe.data!=null:valid_gi=valid_gi and probe.data.interior and not probe.data.get_octree_cells().is_empty() and probe.data.get_bounds().size.is_equal_approx(probe.size)
	check(valid_gi,"resident VoxelGI volumes exclude global sky while retaining baked geometry")
	var sun:DirectionalLight3D=lighting.get_node("OvercastSun")
	check(bool(sun.light_cull_mask&1) and bool(sun.shadow_caster_mask&1),"the single world sun reaches room surfaces and respects real door shadows")
	var fallback=base.get_node("InteriorAmbientOcclusion")
	check(fallback.get_node("Fallback").get_child_count()==8 and fallback.get_node("Connectors").get_child_count()==4 and fallback.find_children("*","ReflectionProbe").all(func(probe):return probe.cull_mask==0 and probe.interior and probe.update_mode==ReflectionProbe.UPDATE_ONCE),"room fallback and connector isolation use static empty captures, not extra lamps")
	camera=Camera3D.new();base.add_child(camera);camera.current=true;camera.fov=75
	var manager=base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
	var entrance=base.get_node("Floor_0_Base_Blockout/Doors/West_Pedestrian_Exterior_Door_Visual_Prototype")
	var quality=root.get_node("GameMenu/GraphicsQuality");quality.set_process(false)
	for gi_enabled in [true,false]:
		var mode:="gi-on" if gi_enabled else "gi-off"
		quality.set_gi_quality(2 if gi_enabled else 0);set_power(false)
		check(fallback.get_node("Fallback").visible,"room sky isolation remains available at GI boundaries in "+mode)
		check(fallback.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_COLOR),"backup circuit excludes neutral ambient in "+mode)
		manager.debug_set_door_open(entrance,false);await create_timer(1.0).timeout
		var hub:=await capture(mode+"-unlit-hub",Vector3(-5,1.75,0),Vector3(0,1.7,-4))
		var closed_room:=mean(hub,Rect2i(750,240,330,210))
		check(closed_room<.003,"closed room surfaces receive no phantom ambient in "+mode+" ("+str(closed_room)+")")
		var closed:=await capture(mode+"-door-closed",Vector3(-35.6,1.7,3),Vector3(-37.5,.8,3))
		var closed_floor:=floor_mean(closed)
		manager.debug_set_door_open(entrance,true);await create_timer(1.0).timeout
		var opened:=await capture(mode+"-door-open",Vector3(-35.6,1.7,3),Vector3(-37.5,.8,3))
		var open_floor:=floor_mean(opened)
		check(closed_floor<.005 and open_floor>closed_floor+.04,"opening the actual door admits daylight onto interior floor in "+mode)
		check(is_equal_approx(camera.environment.ambient_light_energy,source.ambient_light_energy),"door state never changes global exposure/ambient in "+mode)
		var facade:=await capture(mode+"-facade",Vector3(-44,5.7,16),Vector3(-37,6.5,9))
		check(mean(facade,Rect2i(550,340,450,200))>.15,"outside facade remains lit in "+mode)
		if gi_enabled:
			sun.hide()
			var ambient_only:=await capture("exterior-sky-only",Vector3(-44,5.7,16),Vector3(-37,6.5,9))
			var indirect=base.get_node("WorldIndirectLighting");indirect.set_debug_disabled(true)
			var no_room_gi:=await capture("exterior-sky-no-room-gi",Vector3(-44,5.7,16),Vector3(-37,6.5,9))
			var region:=Rect2i(220,355,330,160)
			var delta:=absf(mean(ambient_only,region)-mean(no_room_gi,region))
			print("EXTERIOR SKY GI DIFFERENCE ",delta)
			check(delta<.015,"room GI does not blacken the exterior hood or roof in sky-only light")
			indirect.set_debug_disabled(false);sun.show()
		set_power(true)
		check(fallback.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==(ReflectionProbe.AMBIENT_DISABLED if gi_enabled else ReflectionProbe.AMBIENT_COLOR)),"powered room preserves GI only in advanced mode: "+mode)
		check(fallback.get_node("Connectors").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_DISABLED),"doorway captures never impose a black diffuse rectangle in "+mode)
		var normal:=await capture(mode+"-powered-room",Vector3(-27,1.7,-2),Vector3(-22,2,-6.6),true)
		var lit_room:=mean(normal,Rect2i(340,180,720,380));print("POWERED ROOM ",mode," ",lit_room)
		check(lit_room>.025,"real standard lamps illuminate the powered room in "+mode)
		set_power(false)
	quality.set_gi_quality(2)
	actor.camera.current=true;actor.teleport_authoritative(Vector3(-5,.1,0),0)
	await capture("view-light-unlit",Vector3(-5,1.75,0),Vector3(0,1.7,-4))
	check(lighting.sample_view_light(actor.camera).get_luminance()<.001,"hands have no constant fill when world light sources are absent")
	current_scene=null;base.queue_free();for i in 20:await process_frame
	print("INTERIOR DAYLIGHT CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
