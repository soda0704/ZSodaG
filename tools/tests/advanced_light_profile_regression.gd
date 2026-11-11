extends SceneTree
## Fixed real-room views: red alarm, its dark pause, power restoration and faults.
var base: Node3D
var camera: Camera3D
var lighting: WorldLighting
var state: BaseGameplayController
var quality: Node
var checks := 0
var failures := 0
var output := "res://tools/.local/advanced-light-review-2026-11-11/"
func _initialize():
	var prefix := "user://advanced_profile_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	create_timer(160).timeout.connect(func():quit(2));run.call_deferred()
func check(ok: bool, label: String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func power(enabled: bool, fault := false):
	var snap:=state.get_snapshot();snap.main_breaker_on=enabled;snap.containment["fault"]=fault;snap.fuel_delivered=true;snap.fuel_liters=30.0;state._broadcast_snapshot(snap)
func mean(image: Image, rect: Rect2i) -> Color:
	var result:=Color(0,0,0,0);var count:=0
	for x in range(rect.position.x,rect.end.x,4):
		for y in range(rect.position.y,rect.end.y,4):result+=image.get_pixel(x,y);count+=1
	return result/maxi(count,1)
func capture(label: String, pulse: float) -> Image:
	var alarm:=lighting.get_node("EmergencyAlarm")
	alarm.stream_paused=true
	for frame in 90:
		lighting._process(1.0/60.0)
		lighting.emergency_intensity=pulse;lighting.emergency_intensity_changed.emit(pulse);lighting._update_lamps(camera.global_position,1.0/60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();picture.save_png(output+label+".png");return picture
func run():
	DirAccess.make_dir_recursive_absolute(output);Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
	base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
	for frame in 30:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.body_animator.hide();actor.get_node("PlayerUI").hide();actor.teleport_authoritative(Vector3(-90,0,45),0)
	state=base.get_node("BaseGameplayController");state.set_process(false)
	base.get_node("SnowExterior/Blizzard").enabled=false
	lighting=base.get_node("WorldLighting");lighting.set_process(false)
	quality=root.get_node("GameMenu/GraphicsQuality");quality.set_process(false)
	var gi:=base.get_node("WorldIndirectLighting")
	var isolation:=base.get_node("InteriorAmbientOcclusion")
	var freecam=actor.debug_free_camera;freecam.set_enabled(true);freecam.set_process(false)
	camera=freecam;camera.fov=80;camera.global_position=Vector3(-6,1.75,6);camera.look_at(Vector3(4,1.7,5.8));camera.reset_physics_interpolation()
	var lamp_count:=lighting._lamps.size()
	var floor_rect:=Rect2i(500,460,180,170)
	for gi_enabled in [true,false]:
		var mode:="gi-on" if gi_enabled else "gi-off"
		quality.set_gi_quality(2 if gi_enabled else 0);power(false)
		var flash:=await capture("alarm-after-"+mode,1.0)
		var rgb:=mean(flash,floor_rect);print("ALARM FLOOR ",mode," ",rgb)
		check(gi.get_active_probe_count()==0,"backup circuit never displays GI in "+mode)
		check(isolation.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_COLOR),"backup room rejects sky ambient in "+mode)
		check(rgb.r>rgb.g*3.0 and rgb.g<.006 and rgb.b<.006,"alarm floor receives red light without neutral white wash in "+mode)
		check(lighting._resident_lamps.any(func(lamp):return lamp.light_energy>.01),"real backup lights remain active in "+mode)
		var dark:=await capture("alarm-pause-after-"+mode,0.0)
		check(mean(dark,floor_rect).get_luminance()<.003,"alarm pause does not retain white GI in "+mode)
		check(lighting._lamps.all(func(lamp):return is_zero_approx(lamp.light_energy)),"alarm pause zeros every pooled source in "+mode)
	quality.set_gi_quality(2);power(true)
	camera.global_position=Vector3(-6,1.7,15.5);camera.look_at(Vector3(1,2,10.1));camera.reset_physics_interpolation()
	await capture("powered-doorway-after",1.0)
	check(gi.get_active_probe_count()>0,"real power restoration restores advanced GI")
	check(isolation.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_DISABLED),"powered room keeps diffuse bounce")
	check(isolation.get_node("Connectors").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_DISABLED),"doorways no longer impose black diffuse rectangles")
	power(true,true);await process_frame
	check(not base.get_node("BasePowerLightingController").is_standard_powered and gi.get_active_probe_count()==0,"containment fault selects backup profile even with the main breaker on")
	power(true);await process_frame
	check(gi.get_active_probe_count()>0 and (int(quality.values.GIQuality) > 0),"fault recovery restores GI without overriding graphics choice")
	check(lighting._lamps.size()==lamp_count,"circuit transitions do not duplicate lamps")
	freecam.set_enabled(false);current_scene=null;base.queue_free();for frame in 15:await process_frame
	# The staged loader can attach rendering blocks after the controller.
	var late:=Node3D.new();root.add_child(late)
	var circuits:=Node3D.new();circuits.name="WorldLighting";late.add_child(circuits)
	for label in ["Standard","Emergency"]:
		var group:=Node3D.new();group.name=label;circuits.add_child(group)
	var controller:=BasePowerLightingController.new();controller.name="BasePowerLightingController";late.add_child(controller)
	var late_gi=load("res://scenes/levels/world_indirect_lighting.tscn").instantiate();late.add_child(late_gi);late_gi.set_process(false);late_gi.update_floor(3.0)
	var late_isolation=load("res://scenes/levels/interior_ambient_occlusion.tscn").instantiate();late.add_child(late_isolation)
	for frame in 3:await process_frame
	check(late_gi.get_active_probe_count()==0 and not late_gi._power_enabled,"late-loaded GI inherits the existing outage")
	check(late_isolation.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_COLOR),"late-loaded ambient isolation inherits the existing outage")
	controller.apply_power_state(true);late_gi.update_floor(3.0)
	check(late_gi.get_active_probe_count()>0,"late-loaded GI responds to subsequent power restoration")
	check(late_isolation.get_node("Fallback").get_children().all(func(probe):return probe.ambient_mode==ReflectionProbe.AMBIENT_DISABLED),"late-loaded room releases the black diffuse override with power")
	late.queue_free();for frame in 5:await process_frame
	print("ADVANCED LIGHT PROFILE CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
