extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:
	var prefix:="user://audio_arrival_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root",prefix+"/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	create_timer(120).timeout.connect(func():quit(2))
	run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	Engine.max_fps=60
	var menu:=root.get_node("GameMenu")
	var interface_audio:=menu.get_node("InterfaceAudio")
	for attempt in 2:
		await menu.start_standalone_flow()
		var session:=current_scene
		var level:Node3D=session.get_node("V3Level")
		var lighting:WorldLighting=level.get_node("WorldLighting")
		var alarm:AudioStreamPlayer=lighting.get_node("EmergencyAlarm")
		check(not session._v3_transition_in_progress and not session.lobby_hud.flight_transition.visible and not session.is_solo_arrival() and not session.has_node("ArrivalCabin"),"solo %d loads directly into the world without a cabin readiness step"%attempt)
		check(alarm.power==level.get_node("BasePowerLightingController") and alarm.presence==level.get_node("BaseInteriorAmbience"),"arrival %d binds alarm to this level's power and occupancy"%attempt)
		var remnants:=0
		for box:CSGBox3D in level.find_children("*","CSGBox3D",true,false):
			if "Light" in box.name or "Lamp" in box.name or "Fixture" in box.name:remnants+=1
		check(remnants==0,"arrival %d loading plan does not resurrect CSG lamp boxes"%attempt)
		var actor:GamePlayer=get_first_node_in_group("local_player")
		actor.set_physics_process(false);actor.survival.set_physics_process(false)
		actor.teleport_authoritative(Vector3(-5,.1,0),0)
		level.get_node("BaseAmbience").update_listener(actor.camera.global_position,.1,true)
		var state:BaseGameplayController=level.get_node("BaseGameplayController");state.set_process(false)
		var snapshot:=state.get_snapshot();snapshot.main_breaker_on=false;state._broadcast_snapshot(snapshot)
		for frame in 30:await process_frame
		check(alarm.playing and alarm.volume_db> -30,"arrival %d emergency alarm is audible inside the actual base"%attempt)
		check(actor.player_audio.radiation_audio.stream is AudioStreamWAV,"arrival %d player retains the radiation recording"%attempt)
		menu.return_to_main_menu("",false)
		await scene_changed
		for frame in 4:await process_frame
		check(not is_instance_valid(alarm) and is_instance_valid(interface_audio) and menu.get_node("InterfaceAudio")==interface_audio,"exit %d releases the world alarm and keeps one persistent UI audio service"%attempt)
	await create_timer(1.0).timeout
	interface_audio.hover.stop();interface_audio.click.stop()
	for frame in 4:await process_frame
	print("AUDIO ARRIVAL CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
