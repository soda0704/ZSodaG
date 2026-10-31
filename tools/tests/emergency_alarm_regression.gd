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
	var synced:=true
	for position in [.2,1.2,2.4,4.8,6.1]:
		alarm.seek(position)
		await process_frame
		lighting._advance_emergency(.016)
		var clock:float=alarm.get_playback_position()+AudioServer.get_time_since_last_mix()-AudioServer.get_output_latency()
		var pulse:Animation=alarm.animation.get_animation("alarm")
		var expected:float=pulse.value_track_interpolate(0,fposmod(maxf(0,clock),alarm.stream.get_length()))
		synced=synced and absf(lighting.emergency_intensity-expected)<.04
	check(synced,"red light intensity follows the authored envelope at actual audible playback time")
	alarm.seek(1.0);await process_frame;lighting._advance_emergency(.016)
	var before:float=alarm.get_playback_position()
	set_power(state,false);await create_timer(.12).timeout;lighting._advance_emergency(.016)
	check(alarm.get_playback_position()>=before-.02,"repeated power snapshots do not restart the sound or pulse")
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
		alarm.stream_paused=true
		for sample in [{"name":"bright","time":peak_time},{"name":"dim","time":dim_time}]:
			alarm.animation.seek(sample.time,true)
			lighting.emergency_intensity=alarm.intensity
			lighting.emergency_intensity_changed.emit(alarm.intensity)
			for frame in 8:
				lighting._update_lamps(actor.camera.global_position,1.0/60.0)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/feedback-fixes-2026-10-30/emergency-alarm-"+sample.name+".png")
			print("EMERGENCY FRAME ",sample.name," time ",sample.time," intensity ",alarm.intensity)
		alarm.stop()
	current_scene=null;base.queue_free()
	for frame in 6:await process_frame
	print("EMERGENCY ALARM CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
