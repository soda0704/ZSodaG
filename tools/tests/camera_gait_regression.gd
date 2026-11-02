extends SceneTree
## Drive the production player; measure camera travel relative to its head.
var failures:=0
var checks:=0
var actor:GamePlayer
var mode:=""
func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path","user://camera_gait_%d.json"%OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/controls_path","user://camera_gait_controls_%d.cfg"%OS.get_process_id())
	run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func drive() -> void:
	for action in ["move_forward","sprint","crouch","weapon_aim"]:Input.action_release(action)
	if mode.is_empty():return
	Input.action_press("move_forward")
	if mode=="sprint":Input.action_press("sprint")
	if mode=="crouch":Input.action_press("crouch")
	if mode=="aim":Input.action_press("weapon_aim")
func run() -> void:
	Engine.max_fps=60
	var steam:=root.get_node("SteamInput");steam.set_process(false);steam.using_controller=false;steam.native_input_available=false
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena);current_scene=arena
	physics_frame.connect(drive)
	for variant in [0,1]:
		actor=load("res://scenes/characters/player.tscn").instantiate()
		actor.name="1";actor.setup(1,"",Vector3(0,.1,0),Color.WHITE,0,variant)
		arena.get_node("Players").add_child(actor)
		actor.survival.set_physics_process(false);actor.set_process_unhandled_input(false)
		actor.apply_held_item_inventory(&"m4a1",{});actor.weapon.apply_state(&"m4a1",20,0)
		root.get_node("GameMenu").force_close_menu()
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var ranges:Dictionary={}
		var rolls:Dictionary={}
		for gait in ["walk","sprint","crouch","aim"]:
			mode=""
			actor.teleport_authoritative(Vector3(0,.1,0),0)
			actor.camera.reset_motion();actor.velocity=Vector3.ZERO
			actor._sprint_remaining=actor.sprint_duration;actor._sprint_exhausted=false
			for frame in 20:await physics_frame
			mode=gait
			for frame in 45:await physics_frame
			var low:=Vector3.INF;var high:=-Vector3.INF;var max_roll:=0.0
			var previous:=actor.camera.position;var max_step:=0.0
			var max_aim_deviation:=0.0
			for frame in 90:
				await physics_frame
				var pose:=actor.camera.position-actor.camera._rest_position
				low=low.min(pose);high=high.max(pose)
				max_roll=maxf(max_roll,absf(rad_to_deg(actor.camera.rotation.z-actor.camera._rest_rotation.z)))
				max_step=maxf(max_step,actor.camera.position.distance_to(previous))
				max_aim_deviation=maxf(max_aim_deviation,actor.camera.global_basis.z.distance_to(actor.head.global_basis.z))
				previous=actor.camera.position
			ranges[gait]=high-low
			rolls[gait]=max_roll
			print("GAIT ",variant," ",gait," range=",ranges[gait]," roll_deg=",max_roll," max_step=",max_step)
			check(actor.velocity.length()>1.0 and actor._is_crouching==(gait=="crouch") and actor._aiming==(gait=="aim"),"variant %d actually performs %s"%[variant,gait])
			check(max_step<.02 and max_roll<1.5 and ranges[gait].x<.12,"camera remains continuous and inside the player capsule for "+gait)
			check(max_aim_deviation<.0001,"stride does not tilt the view away from the gameplay shooting direction for "+gait)
		check(ranges.walk.x>.04 and ranges.sprint.x<ranges.walk.x*.85 and rolls.sprint<rolls.walk*.8,"variant %d keeps broad walking but running is steadier with less lateral swing and roll"%variant)
		check(ranges.crouch.x<ranges.walk.x*.8 and ranges.aim.x<ranges.walk.x*.55,"variant %d crouch and ADS reduce camera motion"%variant)
		mode=""
		for frame in 75:await physics_frame
		check(actor.camera.position.distance_to(actor.camera._rest_position)<.001 and actor.camera.rotation.distance_to(actor.camera._rest_rotation)<.001,"stopping settles the camera without idle drift")
		actor.camera.add_look_impulse(Vector2(100,-40))
		actor.camera.reset_motion()
		check(actor.camera.position==actor.camera._rest_position and actor.camera.rotation==actor.camera._rest_rotation,"teleport/respawn reset removes stride and turn inertia")
		actor.queue_free()
		await process_frame
	var spans:Array[float]=[]
	for fps in [30,60,144]:
		var camera:FirstPersonCameraMotion=load("res://scripts/characters/components/first_person_camera_motion.gd").new()
		arena.add_child(camera)
		var low:=100.0;var high:=-100.0
		for frame in fps*3:
			camera.update_motion(1.0/fps,1.0,true,false)
			if frame>fps:low=minf(low,camera.position.x);high=maxf(high,camera.position.x)
		spans.append(high-low)
		for frame in fps:camera.update_motion(1.0/fps,1.0,false,false)
		check(camera.position.length()<.001,"airborne camera does not keep walking at "+str(fps)+" FPS")
		camera.queue_free()
	check(spans.max()-spans.min()<.003,"walking amplitude is consistent at 30, 60 and 144 FPS")
	arena.queue_free();current_scene=null
	for frame in 6:await process_frame
	print("CAMERA GAIT CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
