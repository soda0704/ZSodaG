extends SceneTree
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,message:String):
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func run():
	Engine.time_scale=12;Engine.max_physics_steps_per_frame=32;Engine.max_fps=120
	var base:BaseBlockoutRuntime=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base)
	root.get_node("GameMenu").force_close_menu()
	for frame in 12:await physics_frame
	var state:BaseGameplayController=base.get_node("BaseGameplayController");state.set_process(false)
	state.progress_persistence_enabled = false
	state.debug_set_day_authoritative(7)
	var player:GamePlayer=get_first_node_in_group("network_players")
	player.set_physics_process(false);player.survival.set_physics_process(false)
	var cave:Node3D=base.get_node("Cave_Day7")
	var curve:Curve3D=cave.get_node("AuthoredRoute").curve
	var total:=curve.get_baked_length();var distance:=8.0
	player.global_position=curve.sample_baked(distance,true)+Vector3.UP*0.08;player.velocity=Vector3.ZERO;player.survival.reset_fall()
	player.survival._physics_process(0.01)
	check(not player.survival.dead and player.survival.health==100,"Cave depth does not trigger out-of-world death")
	var started:=Time.get_ticks_msec();var last_progress:=started;var low_sections:=0
	var discovery_offset := -1.0
	while distance<total-0.7 and Time.get_ticks_msec()-started<60000:
		await physics_frame
		var next_distance:=curve.get_closest_offset(player.global_position)
		if next_distance>distance+0.025:last_progress=Time.get_ticks_msec()
		distance=next_distance
		if discovery_offset < 0.0 and state.containment.get("cave_hives_found",false): discovery_offset = distance
		var target:=curve.sample_baked(minf(total,distance+0.7),true)
		var offset:=target-player.global_position;offset.y=0
		if Time.get_ticks_msec()-last_progress>1800:
			print("STUCK_AT ",distance," ",player.global_position," expected ",target);break
		var crouch:bool=absf(distance-total*0.24)<9 or absf(distance-total*0.58)<9
		var step:=player.get_physics_process_delta_time()
		player.update_crouch_state(step,crouch)
		if crouch:low_sections+=1
		var speed:=2.2 if crouch else 6.0
		player.velocity=offset.normalized()*minf(speed,offset.length()/step)
		player.velocity.y=-1.2;player.move_and_slide()
		if absf(player.global_position.y-target.y)>0.65:
			print("LOST_FLOOR ",distance," ",player.global_position," expected ",target);break
	check(distance>=total-0.7,"Actual GamePlayer walks from shaft to mouth without jumps/teleports (%.1f / %.1fm)"%[distance,total])
	check(low_sections>10,"Both low passages traversed with production crouch component")
	check(discovery_offset > total * 0.84 and discovery_offset < total * 0.91,"Hive task reveals in the final chamber, not at the shaft (%.1fm)" % discovery_offset)
	check(player.collision_shape.shape.height>1.7,"Player can stand again after low passage")
	var console=root.get_node("DeveloperConsole")
	check(cave.get_node("ExitThreshold").global_position.distance_to(Vector3(342,-155.9,2))<0.02,"Console exit marker follows saved scene")
	var day_before:int=state.get_snapshot().day_index
	for destination in ["entry","lair","exit"]:
		console._execute_authoritative(PackedStringArray(["/cave",destination]),state,1)
		var name:String={"entry":"CaveArrival","lair":"Lair","exit":"ExitThreshold"}[destination]
		check(player.global_position.distance_to(cave.get_node(name).global_position)<0.02,"Authoritative console teleport: "+destination)
	check(state.get_snapshot().day_index==day_before,"Review commands preserve story day")
	print("CAVE_WALKTHROUGH_FAILURES ",failures.size()," elapsed_ms ",Time.get_ticks_msec()-started)
	Engine.time_scale=1
	quit(0 if failures.is_empty() else 1)
