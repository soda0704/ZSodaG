extends SceneTree
var checks := 0
var failures := 0
var actor: GamePlayer
var output := "res://tools/.local/snow-material-review/captures/"
const Plan = preload("res://scripts/network/level_load_plan.gd")
func _initialize() -> void:
	var prefix := "user://snow_session_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root",prefix+"/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	create_timer(110).timeout.connect(func():quit(2))
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func shot(label: String) -> void:
	await create_timer(0.65).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60;root.size=Vector2i(1600,900);root.content_scale_size=root.size
	var menu=root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var session=current_scene
	await session._enter_v3_level()
	var base=session.get_node("V3Level")
	actor=get_first_node_in_group("local_player")
	actor.survival.set_physics_process(false)
	var exterior=base.get_node("SnowExterior")
	var terrain=exterior.get_node("Terrain3D")
	var tracks=exterior.get_node("SnowTracks")
	check(tracks.is_physics_processing() and tracks._terrain==terrain,"track sampler reacquires Terrain3D after staged loading")
	var at=Vector3(-57,0,22);at.y=terrain.data.get_height(at)+0.1
	actor.teleport_authoritative(at,0)
	for frame in 20:await physics_frame
	var before:int=tracks._marks.size()
	Input.action_press("move_forward")
	for frame in 180:await physics_frame
	Input.action_release("move_forward")
	for frame in 10:await physics_frame
	check(actor.global_position.z<at.z-5,"normal forward input actually moves the player on snow")
	check(tracks._marks.size()>=before+8,"normal walking leaves boot prints without calling the sampler directly")
	print("WALK position=",actor.global_position," marks=",tracks._marks.size()-before)
	# Traverse the complete protected arrival-to-entry corridor under normal input.
	var start:=Vector3(-92,0,95);start.y=terrain.data.get_height(start)+0.1
	actor.teleport_authoritative(start,0)
	var reached:=true
	for fraction in [0.33,0.66,1.0]:
		var target:Vector3=Vector3(-92,0,95).lerp(Vector3(-41,0,3),fraction)
		Input.action_press("move_forward")
		for frame in 650:
			var delta:=target-actor.global_position;delta.y=0
			if delta.length()<0.6:break
			actor._input_yaw=atan2(-delta.x,-delta.z)
			await physics_frame
		Input.action_release("move_forward")
		var remaining:Vector3=target-actor.global_position;remaining.y=0
		reached=reached and remaining.length()<0.8
		print("APPROACH waypoint=",target," actual=",actor.global_position)
	check(reached,"normal walking traverses the full arrival-to-base corridor without jumping")
	actor.set_physics_process(false)
	exterior.get_node("Blizzard").enabled=false
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
	actor.head.look_at(Vector3(-57,terrain.data.get_height(Vector3(-57,0,18)),18))
	await shot("normal-walk-bootprints")
	at=Vector3(-62,0,21);at.y=terrain.data.get_height(at)+0.1
	actor.teleport_authoritative(at,0)
	actor.head.look_at(Vector3(-43,1.1,3))
	await shot("sculpted-snow-clear")
	if "--benchmark" in OS.get_cmdline_user_args():
		menu.get_node("GraphicsQuality").set_process(false)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps=0
		var timings:Array=[]
		for repeat in 3:
			for enabled in [false,true]:
				terrain.material.set_shader_param("entry_snow_enabled",enabled)
				for frame in 40:await process_frame
				var started=Time.get_ticks_usec()
				for frame in 120:await process_frame
				var ms=(Time.get_ticks_usec()-started)/120000.0
				timings.append({"sample":repeat,"new_material":enabled,"frame_ms":ms})
				print("SNOW BENCH ",timings[-1])
		FileAccess.open(output+"snow-frame-times.json",FileAccess.WRITE).store_string(JSON.stringify(timings,"  "))
		terrain.material.set_shader_param("entry_snow_enabled",true)
		Engine.max_fps=60
	exterior.get_node("Blizzard").enabled=true
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=true
	await shot("sculpted-snow-storm")
	# Let gameplay nodes and render resources leave the tree before shutting down.
	actor=null;current_scene=null;session.queue_free()
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	print("SNOW SESSION CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
