extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void:
	var prefix:="user://emergency_alarm_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	create_timer(80).timeout.connect(func():quit(2))
	run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func set_power(state:BaseGameplayController,on:bool,fault:bool=false) -> void:
	var snapshot:=state.get_snapshot();snapshot.main_breaker_on=on;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.0;snapshot.containment["fault"]=fault
	state._broadcast_snapshot(snapshot)

func capture_phase(lighting:WorldLighting,alarm:AudioStreamPlayer,time:float,label:String) -> Image:
	# Start at the requested position before pausing; seek on a stopped player
	# is discarded when advance_emergency starts it after a power transition.
	alarm.stream_paused=false
	alarm.play(time)
	await process_frame
	alarm.stream_paused=true
	for frame in 54:
		lighting._process(1.0/60.0)
		# Freeze the authored light phase for an apples-to-apples image pair.
		# Audio/renderer warm-up can advance a newly started stream by a frame.
		if not alarm.power.is_standard_powered:
			alarm.animation.seek(time,true)
			lighting.emergency_intensity=alarm.intensity
			lighting.emergency_intensity_changed.emit(alarm.intensity)
			lighting._update_lamps(lighting.get_viewport().get_camera_3d().global_position,1.0/60.0)
		await process_frame
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	var capture_dir := OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
	if capture_dir.is_empty(): capture_dir = "res://tools/.local/feedback-fixes-2026-10-30"
	picture.save_png(capture_dir+"/emergency-darkness-"+label+".png")
	print("DARKNESS CAPTURE ",label," phase=",lighting.emergency_intensity)
	return picture

func world_red_level(picture:Image) -> float:
	# Interior geometry; exclude HUD, compass, status and the lower hand overlay.
	# Measure the alarm's red channel so white indicators do not mask its contrast.
	var total:=0.0;var count:=0
	for y in range(180,550,4):
		for x in range(330,1200,4):
			total+=picture.get_pixel(x,y).r;count+=1
	return total/count
func run() -> void:
	Engine.max_fps=60;root.size=Vector2i(1280,720)
	var base:Node3D=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene=base
	for frame in 20:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false)
	var state:BaseGameplayController=base.get_node("BaseGameplayController");state.set_process(false)
	var lighting:WorldLighting=base.get_node("WorldLighting");lighting.set_process(false)
	var alarm:AudioStreamPlayer=lighting.get_node("EmergencyAlarm")
	var acoustics:ExteriorAcoustics=base.get_node("BaseAmbience")
	var presence:AudioStreamPlayer=base.get_node("BaseInteriorAmbience")
	var boxes:Array[String]=[]
	for box:CSGBox3D in base.find_children("*","CSGBox3D",true,false):
		if "Light" in box.name or "Lamp" in box.name or "Fixture" in box.name:boxes.append(str(box.name))
	check(boxes.is_empty(),"CSG lamp placeholder boxes are absent from the assembled game level")
	check(lighting.get_node("Standard").get_child_count()==89 and lighting.get_node("Emergency").get_child_count()==49,"all 89 standard and 49 emergency light sources remain present")
	actor.teleport_authoritative(Vector3(-5,0.1,0),0)
	acoustics.update_listener(actor.camera.global_position,.1,true)
	check(presence.listener_inside(),"actual listener in the hub is inside the authored base regions")
	check(alarm.stream is AudioStreamWAV and not alarm.stream.stereo and alarm.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"alarm is a mono looping WAV")
	var playback:=alarm.stream.instantiate_playback();playback.start()
	var channels_match:=true
	for sample in playback.mix_audio(1.0,8192):channels_match=channels_match and absf(sample.x-sample.y)<.000001
	playback.stop()
	check(channels_match,"decoded alarm sends identical signal to both ears")
	set_power(state,true);lighting._advance_emergency(.5)
	check(not alarm.playing and alarm.volume_db< -80,"normal power silences the alarm")
	set_power(state,false);lighting._advance_emergency(.05)
	var quiet:=alarm.volume_db
	check(alarm.playing and quiet<alarm.alarm_volume_db,"emergency power starts the alarm with a short fade")
	lighting._advance_emergency(.5)
	check(absf(alarm.volume_db-alarm.alarm_volume_db)<.01,"alarm reaches its configured level inside the base")
	var pulse_resource: Animation = alarm.animation.get_animation("alarm")
	alarm.animation.seek(.431,true)
	check(absf(alarm.intensity-float(pulse_resource.value_track_interpolate(0,.431)))<.001,"alarm envelope preserves fractional brightness on burst transitions")
	var synced:=true
	for position in [.2,.65,1.25,1.95,3.2,4.45,6.1]:
		alarm.seek(position)
		for frame in 3:await process_frame
		var clock_before:float=alarm.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
		lighting._advance_emergency(.016)
		var clock:float=alarm.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
		var pulse:Animation=alarm.animation.get_animation("alarm")
		var expected_before:float=pulse.value_track_interpolate(0,fposmod(maxf(0,clock_before),alarm.stream.get_length()))
		var expected:float=pulse.value_track_interpolate(0,fposmod(maxf(0,clock),alarm.stream.get_length()))
		var matched:bool=lighting.emergency_intensity>=minf(expected_before,expected)-.01 and lighting.emergency_intensity<=maxf(expected_before,expected)+.01
		if not matched:print("SYNC SAMPLE time=",clock_before,"..",clock," range=",expected_before,"..",expected," actual=",lighting.emergency_intensity," alarm=",alarm.intensity," animation_position=",alarm.animation.current_animation_position," standard=",alarm.power.is_standard_powered," emergency=",lighting.get_node("Emergency").visible)
		synced=synced and matched
	check(synced,"red light intensity follows the authored envelope at actual audible playback time")
	var envelope:Animation=alarm.animation.get_animation("alarm")
	var dark_time:float=-1.0;var bright_time:float=-1.0
	var longest_dark:=0.0;var dark_run:=0.0
	for step in ceili(envelope.length*100):
		var value:float=envelope.value_track_interpolate(0,float(step)/100.0)
		if value==0.0:
			dark_time=float(step)/100.0;dark_run+=.01;longest_dark=maxf(longest_dark,dark_run)
		else:dark_run=0.0
		if value==1.0:bright_time=float(step)/100.0
	check(longest_dark>=.2 and bright_time>=0.0,"alarm envelope includes sustained complete blackouts and full-brightness bursts")
	alarm.stream_paused=true
	var fixtures:Node=lighting.get_node("HubFixtures")
	var blackouts:=true;var bursts:=true
	for advanced in [false,true]:
		root.get_node("GameMenu/GraphicsQuality").set_advanced_lighting_enabled(advanced)
		alarm.animation.seek(maxf(0.0,dark_time),true)
		lighting.emergency_intensity=alarm.intensity
		lighting.emergency_intensity_changed.emit(alarm.intensity)
		lighting._update_lamps(actor.camera.global_position,1.0)
		blackouts=blackouts and alarm.intensity==0.0 and lighting.get_node("Emergency").visible and not fixtures._materials.is_empty()
		for lamp:Light3D in lighting.get_node("Emergency").get_children():
			blackouts=blackouts and lamp.light_energy==0.0
		for entry in fixtures._materials:
			blackouts=blackouts and entry.material.emission_energy_multiplier==0.0
		alarm.animation.seek(maxf(0.0,bright_time),true)
		lighting.emergency_intensity=alarm.intensity
		lighting.emergency_intensity_changed.emit(alarm.intensity)
		lighting._update_lamps(actor.camera.global_position,1.0)
		var energy:=0.0
		for lamp:Light3D in lighting.get_node("Emergency").get_children():energy+=lamp.light_energy
		bursts=bursts and alarm.intensity==1.0 and energy>0.0
		for entry in fixtures._materials:bursts=bursts and entry.material.emission_energy_multiplier>0.0
	check(blackouts,"all 49 emergency lights and hub fixture emission reach exact zero in both light quality modes")
	check(bursts,"alarm bursts restore emergency light and fixture emission in both light quality modes")
	alarm.stream_paused=false
	alarm.seek(1.0);await process_frame;lighting._advance_emergency(.016)
	var before:float=alarm.get_playback_position()
	set_power(state,false);await create_timer(.12).timeout;lighting._advance_emergency(.016)
	check(alarm.get_playback_position()>=before-.02,"repeated power snapshots do not restart the sound or pulse")
	actor.teleport_authoritative(Vector3(-39.5,.1,3),0)
	acoustics.update_listener(actor.camera.global_position,.1,true)
	lighting._advance_emergency(1.0)
	presence._process(3.0)
	check(not presence.listener_inside() and presence.listener_gain()>0.1,"open pedestrian doorway carries base sound to the exterior threshold")
	check(alarm.volume_db> -50.0 and alarm.volume_db<alarm.alarm_volume_db and presence._blend>0.0,"alarm and interior ambience are audible but attenuated by the open entrance")
	actor.teleport_authoritative(Vector3(-50,.1,3),0)
	lighting._advance_emergency(1.0)
	check(alarm.listener_gain()>.1 and alarm.volume_db> -50.0,"open entrance alarm reaches twelve metres outdoors")
	actor.teleport_authoritative(Vector3(-39.5,.1,3),0)
	var manager:BaseAutoDoorManager=base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
	var entrance:Node3D=base.get_node("Floor_0_Base_Blockout/Doors/West_Pedestrian_Exterior_Door_Visual_Prototype")
	check(manager.debug_set_door_open(entrance,false),"existing door controller accepts a closed entrance for the acoustic check")
	await create_timer(.85).timeout
	lighting._advance_emergency(1.0);presence._process(3.0)
	check(presence.listener_gain()==0.0 and alarm.volume_db< -80.0 and presence.stream_paused,"closing the actual entrance fades both base sound layers outside")
	manager.debug_set_door_open(entrance,true)
	await create_timer(.85).timeout
	lighting._advance_emergency(1.0)
	check(presence.listener_gain()>0.1 and alarm.playing and alarm.volume_db> -50.0,"reopening the entrance restores the same running alarm clock")
	actor.teleport_authoritative(Vector3(-36.5,.1,3),0)
	acoustics.update_listener(actor.camera.global_position,.1,true)
	lighting._advance_emergency(1.0)
	check(presence.listener_inside() and absf(alarm.volume_db-alarm.alarm_volume_db)<.01,"inside the vestibule the alarm reaches the normal base level")
	actor.teleport_authoritative(Vector3(180,1,180),0)
	lighting._advance_emergency(.5)
	check(not presence.listener_inside() and alarm.volume_db< -80,"alarm is inaudible outside while its clock keeps advancing")
	check(not presence.contains_point(Vector3(-150,-110,100)),"a sheltered cave outside base regions is not treated as part of the base")
	actor.teleport_authoritative(Vector3(-5,0.1,0),0);acoustics.update_listener(actor.camera.global_position,.1,true)
	lighting._advance_emergency(.5)
	check(alarm.playing and absf(alarm.volume_db-alarm.alarm_volume_db)<.01,"returning inside restores sound without a new alarm instance")
	var quality:=root.get_node("GameMenu/GraphicsQuality")
	quality.set_advanced_lighting_enabled(false);lighting._advance_emergency(.1)
	check(alarm.playing and lighting.get_node("Emergency").visible,"normal light quality preserves emergency audio and power logic")
	quality.set_advanced_lighting_enabled(true);lighting._advance_emergency(.1)
	check(alarm.playing,"advanced light quality preserves the same alarm")
	set_power(state,true,true);lighting._advance_emergency(.5)
	check(alarm.playing and not alarm.power.is_standard_powered,"a containment lighting fault triggers the alarm even with breaker on")
	set_power(state,false);lighting.get_node("Emergency").hide();lighting._advance_emergency(.1)
	check(not alarm.playing,"disabled emergency lighting cannot leave the alarm playing")
	set_power(state,true);lighting._advance_emergency(.1)
	check(not alarm.playing and lighting.get_node("Standard").visible,"restored normal light stops the alarm")
	if DisplayServer.get_name()!="headless":
		set_power(state,false);lighting._advance_emergency(.5)
		actor.teleport_authoritative(Vector3(-5,.1,3),0)
		actor.camera.look_at(Vector3(-10,2,0))
		var pulse:Animation=alarm.animation.get_animation("alarm")
		var peak_time:=0.0;var dim_time:=0.0;var peak:=0.0;var dim:=1.0
		for index in pulse.track_get_key_count(0):
			var value:float=pulse.track_get_key_value(0,index)
			if value>peak:peak=value;peak_time=pulse.track_get_key_time(0,index)
			if value<dim:dim=value;dim_time=pulse.track_get_key_time(0,index)
		for advanced in [false,true]:
			var mode:="advanced" if advanced else "basic"
			quality.set_advanced_lighting_enabled(advanced)
			var bright:=world_red_level(await capture_phase(lighting,alarm,peak_time,mode+"-bright"))
			var dark:=world_red_level(await capture_phase(lighting,alarm,dim_time,mode+"-dark"))
			print("DARKNESS ",mode," dark=",dark," bright=",bright," ambient=",actor.camera.environment.ambient_light_energy)
			check(dark<.03 and bright>dark+.01,"unpowered room has no global fill and retains a distinct alarm burst in "+mode+" mode")
			check(is_equal_approx(actor.camera.environment.ambient_light_energy,lighting.source_environment().ambient_light_energy),"power outage preserves the node's authored ambient in "+mode+" mode")
			if advanced:
				actor.flashlight.malfunction_enabled=false
				actor.pickup_world_item_authoritative(&"flashlight",{"battery_charge":1.0})
				actor.update_character_animation(1.0/60.0)
				var torch:=world_red_level(await capture_phase(lighting,alarm,dim_time,mode+"-flashlight"))
				print("DARKNESS FLASHLIGHT luminance=",torch," beam=",actor.flashlight.beam.is_visible_in_tree())
				check(actor.flashlight.beam.is_visible_in_tree() and torch>dark+.01,"player flashlight still illuminates the actual room during an alarm pause")
				actor.toggle_flashlight_authoritative()
			set_power(state,true)
			var normal:=world_red_level(await capture_phase(lighting,alarm,dim_time,mode+"-normal"))
			check(is_equal_approx(actor.camera.environment.ambient_light_energy,lighting.source_environment().ambient_light_energy) and normal>dark+.02,"restoring power illuminates the room through real lamps in "+mode+" mode")
			set_power(state,false)
		actor.teleport_authoritative(Vector3(180,60,180),0)
		await capture_phase(lighting,alarm,dim_time,"exterior")
		check(is_equal_approx(actor.camera.environment.ambient_light_energy,lighting.outdoor_ambient),"base power outage preserves outdoor ambient light")
		alarm.stop()
	current_scene=null;base.queue_free()
	for frame in 6:await process_frame
	print("EMERGENCY ALARM CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
