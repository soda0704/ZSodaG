extends SceneTree
## Production source scenes, isolated saves; no export, quality reduction or driver-cache deletion.
## Frame intervals include stalls. GPU/CPU viewport timers describe the preceding rendered frame.
var actor:GamePlayer
var world:Node
var base:Node3D
var phase:="boot"
var rows:Array=[]
var events:Array=[]
var previous:=0
var started:=0
var recording:=true
var moving:=false
var goal:=Vector3.ZERO
var yaw:=0.0
var pitch:=0.0
var ladder_direction:=0.0
var output:="res://tools/.local/frame-spikes/baseline"
var quick:=false
var power_only:=false
var legacy_bench:=false
const PIPELINES:=[Performance.PIPELINE_COMPILATIONS_CANVAS,Performance.PIPELINE_COMPILATIONS_MESH,Performance.PIPELINE_COMPILATIONS_SURFACE,Performance.PIPELINE_COMPILATIONS_DRAW,Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]

func _initialize():
	var prefix:="user://frame_spike_%d"%OS.get_process_id()
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,prefix)
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+".controls")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix+"/journal")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--quick":quick=true
		if arg=="--power-only":power_only=true
		if arg=="--legacy-bench":legacy_bench=true
	ProjectSettings.set_setting("northern_lab/testing/loading_trace",true)
	started=Time.get_ticks_usec()
	create_timer(210).timeout.connect(func():push_error("Frame profile timed out");save_results();quit(2))
	run.call_deferred()

func _process(_delta:float)->bool:
	var now:=Time.get_ticks_usec()
	if recording and previous>0:
		var pipes:=[]
		for key in PIPELINES:pipes.append(int(Performance.get_monitor(key)))
		rows.append([phase,(now-started)/1000.0,(now-previous)/1000.0,RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),Performance.get_monitor(Performance.TIME_PROCESS)*1000.,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),pipes])
	previous=now
	return false

func _physics_process(delta:float)->bool:
	if not is_instance_valid(actor):return false
	var input:=Vector2.ZERO
	if not is_zero_approx(ladder_direction):input=Vector2(0,ladder_direction)
	elif moving:
		var direction:=goal-actor.global_position;direction.y=0
		if direction.length()>.35:
			yaw=atan2(-direction.x,-direction.z);input=Vector2(0,-1)
	actor.simulate_movement(delta,input,false,false,false,yaw,pitch)
	actor.update_local_view_motion(delta)
	actor.update_character_animation(delta)
	actor.refresh_interaction_prompt()
	return false

func mark(label:String):
	phase=label
	events.append({"phase":label,"at_ms":(Time.get_ticks_usec()-started)/1000.,"position":str(actor.global_position) if is_instance_valid(actor) else ""})
	print("FRAME PHASE ",label)

func hold(label:String,seconds:float):
	mark(label);await create_timer(seconds).timeout

func pan(label:String,seconds:=3.0):
	mark(label)
	var from:=yaw;var begin:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-begin<seconds*1000:
		yaw=from+TAU*float(Time.get_ticks_msec()-begin)/(seconds*1000.)
		await process_frame
	yaw=wrapf(yaw,-PI,PI)

func walk(label:String,points:Array):
	mark(label)
	for point:Vector3 in points:
		goal=point;moving=true
		var deadline:=Time.get_ticks_msec()+5000
		while Vector2(actor.global_position.x-goal.x,actor.global_position.z-goal.z).length()>.45 and Time.get_ticks_msec()<deadline:await physics_frame
		if Vector2(actor.global_position.x-goal.x,actor.global_position.z-goal.z).length()>.5:
			events.append({"blocked_goal":str(goal),"actual":str(actor.global_position),"phase":phase})
			print("FRAME ROUTE BLOCKED ",goal," at ",actor.global_position)
			moving=false;return
	moving=false

func place(at:Vector3,next_yaw:=0.0):
	mark("relocation")
	actor.teleport_authoritative(at,next_yaw);yaw=next_yaw;pitch=0
	await physics_frame

func screenshot(label:String):
	recording=false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	for i in 3:await process_frame
	recording=true;previous=Time.get_ticks_usec()

func run():
	if DisplayServer.get_name()=="headless":push_error("Graphical renderer required");quit(1);return
	DirAccess.make_dir_recursive_absolute(output)
	root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1920,1080)
	Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var menu:=root.get_node("GameMenu")
	menu._settings_data["GraphicsCalibrationPending"]=false
	var quality:=menu.get_node("GraphicsQuality")
	var settings:Dictionary=quality.DEFAULTS.duplicate();settings.merge(quality.PRESETS[3],true);settings.FPS=0
	quality.apply(settings)
	mark("session_load");await menu.start_standalone_flow(false)
	world=current_scene
	mark("arrival_load");await world._enter_v3_level()
	base=world.get_node("V3Level")
	actor=world.players.get_node("1");actor.set_physics_process(false);actor.survival.debug_invincible=true
	var state:BaseGameplayController=world._base_gameplay_controller
	if legacy_bench:
		# Recreate the prior animation only in this unsaved process for an A/B/A control.
		for bench in get_nodes_in_group("flamethrower_workbenches"):
			var animation:AnimationPlayer=bench.get_node("Power")
			for clip_name in ["Off","On"]:
				var clip:=animation.get_animation(clip_name)
				clip.track_set_path(0,NodePath("WorkbenchVisual:material_override:emission_enabled"))
				clip.track_set_key_value(0,0,clip_name=="On")
			bench.get_node("WorkbenchVisual").material_override.emission_energy_multiplier=1.0
			bench._on_power_changed(state.main_breaker_on)
	state.progress_persistence_enabled=false;state.set_process(false)
	var snapshot:=state.get_snapshot();snapshot.day_index=2;snapshot.main_breaker_on=true;snapshot.fuel_delivered=true;snapshot.fuel_liters=40.;snapshot.maintenance.erase("wires_required")
	mark("power_on_first")
	var before:=Time.get_ticks_usec();state._broadcast_snapshot(snapshot)
	events.append({"power_cpu_ms":(Time.get_ticks_usec()-before)/1000.0,"phase":phase})
	await hold("arrival_visible",2)
	if power_only:
		for i in 2:
			snapshot=state.get_snapshot();snapshot.main_breaker_on=false;mark("power_off_%d"%i);before=Time.get_ticks_usec();state._broadcast_snapshot(snapshot);events.append({"power_cpu_ms":(Time.get_ticks_usec()-before)/1000.0,"phase":phase});await create_timer(1).timeout
			snapshot.main_breaker_on=true;mark("power_on_%d"%i);before=Time.get_ticks_usec();state._broadcast_snapshot(snapshot);events.append({"power_cpu_ms":(Time.get_ticks_usec()-before)/1000.0,"phase":phase});await create_timer(1).timeout
		await finish();return
	await place(Vector3(0,.7,0));await pan("hub_first_pan");await pan("hub_repeated_pan")
	await screenshot("hub")
	await walk("hub_exit_route",[Vector3(-14,0,0),Vector3(-14,0,-3.5),Vector3(-22,0,-3.5),Vector3(-22,0,4.5),Vector3(-30,0,4.5),Vector3(-34,0,5),Vector3(-36.5,0,5),Vector3(-36.5,0,3),Vector3(-43,0,3)])
	# A blocked route is recorded, not silently flown through walls.
	await place(Vector3(-43,.7,3),PI/2);await pan("exterior_first_pan");await pan("exterior_repeated_pan")
	await screenshot("exterior")
	var route:LadderRoute=base.get_node("SnowExterior/RadioTower/Ladder")
	await place(route.bottom_exit.global_position)
	await hold("tower_foot_first",2)
	actor.get_node("LadderClimb").enter(route)
	if actor.is_climbing() and not quick:
		mark("tower_ascent");ladder_direction=-1
		while actor.is_climbing():await physics_frame
		ladder_direction=0
	elif actor.is_climbing():actor.get_node("LadderClimb").finish(route.top_exit.global_position)
	await pan("tower_top_first_pan");await pan("tower_top_repeated_pan")
	await screenshot("tower_top")
	if not quick:
		await place(route.top_exit.global_position)
		actor.get_node("LadderClimb").enter(route)
		if actor.is_climbing():
			mark("tower_descent");ladder_direction=1
			while actor.is_climbing():await physics_frame
			ladder_direction=0
	await place(Vector3(0,.7,0));await hold("hub_return",2)
	await finish()

func finish():
	recording=false;save_results()
	actor=null;current_scene=null;world.queue_free();world=null;base=null
	for i in 8:await process_frame
	for audio:AudioStreamPlayer in root.find_children("*","AudioStreamPlayer",true,false):audio.stop();audio.stream=null
	await create_timer(.15).timeout
	print("FRAME SPIKE PROFILE COMPLETE");quit()

func save_results():
	var summary:=[];var phases:Dictionary={}
	for row in rows:
		if not phases.has(row[0]):phases[row[0]]=[]
		phases[row[0]].append(row)
	for label in phases:
		var samples:Array=phases[label].duplicate();samples.sort_custom(func(a,b):return a[2]<b[2])
		var count:int=samples.size();var over33:=0;var over100:=0
		for row in samples:
			if row[2]>33.3:over33+=1
			if row[2]>100:over100+=1
		var record:Dictionary={"phase":label,"frames":count,"p50_ms":samples[count/2][2],"p99_ms":samples[mini(count-1,int(count*.99))][2],"max_ms":samples.back()[2],"over33":over33,"over100":over100,"worst":samples.slice(maxi(0,count-5))}
		summary.append(record);print("FRAME RESULT ",JSON.stringify(record))
	var file:=FileAccess.open(output.path_join("results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"engine":Engine.get_version_info().string,"resolution":str(root.size),"quality":root.get_node("GameMenu/GraphicsQuality").values,"gi_quality":root.get_node("GameMenu/GraphicsQuality").values.GIQuality,"options":{"legacy_bench":legacy_bench,"power_only":power_only,"quick":quick},"columns":["phase","at_ms","dt_ms","render_cpu_ms","render_gpu_ms","process_monitor_ms","physics_monitor_ms","draws","primitives","pipeline_counts"],"pipeline_order":["canvas","mesh","surface","draw","specialization"],"events":events,"summary":summary,"frames":rows},"\t"));file.close()
