extends SceneTree
var checks:=0
var failures:=0
var base:Node3D
var state:BaseGameplayController
var player:GamePlayer
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://radio_tower_%d.cfg"%OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/settings_path","user://radio_settings_%d.json"%OS.get_process_id())
	run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle() -> void:
	for i in 6:await physics_frame
func boot() -> void:
	base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene=base
	await settle()
	state=base.get_node("BaseGameplayController")
	player=get_first_node_in_group("local_player")
	player.set_physics_process(false);player.survival.set_physics_process(false)
	player.survival.debug_invincible=true
func run() -> void:
	for variant in ["a","b"]:
		for kind in ["body","first_person"]:
			var model=load("res://scenes/characters/visuals/tactical_%s/%s.tscn"%[variant,kind]).instantiate()
			root.add_child(model)
			check(model.get_node("AnimationPlayer").has_animation("ladder/Climb"),"native climb clip bound for %s %s"%[variant,kind])
			model.queue_free()
	await boot()
	state.progress_persistence_enabled=false
	state.set_process(false)
	var snapshot=state.get_snapshot(); snapshot.day_index=2; snapshot.fuel_delivered=true; snapshot.fuel_liters=20.; snapshot.main_breaker_on=true; snapshot.maintenance.erase("wires_required")
	state._apply_snapshot(snapshot,true)
	var pin=str(state.maintenance.get("radio_pin",""))
	check(pin.length()==4 and pin.is_valid_int(),"campaign generates a four-digit shared code")
	var tower=base.get_node("SnowExterior/RadioTower")
	var gate=tower.get_node("Keypad")
	var note=base.get_node("Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/RadioAccessNote")
	var module=base.get_node("Floor_Minus3_Trials_Observation_Blockout/Props/ObservationConsole1/RadioModule")
	var socket=tower.get_node("ServiceSocket")
	check(tower.get_node("Ladder/Top").position.y>50,"original mast extends to a usable high service deck")
	player.teleport_authoritative(note.global_position+note.global_basis.z*1.3-Vector3.UP*1.2)
	await settle()
	check(note.can_use(1,player),"actual vault note is reachable and visible")
	check(RadioTowerProgress.act(state,&"note",1,note),"reading note records shared code and module location")
	player.teleport_authoritative(gate.global_position+Vector3(-1.2,-1.3,0))
	await settle()
	check(gate.can_use(1,player),"original keypad is usable from outside the fence")
	check(not RadioTowerProgress.act(state,&"gate",1,gate,"xxxx"),"wrong code does not open fence")
	check(RadioTowerProgress.act(state,&"gate",1,gate,pin),"campaign code opens original gate")
	await settle()
	check(tower.get_node("GateCollision/CollisionShape3D").disabled,"unlocked gate releases its actual collision")
	var route=tower.get_node("Ladder")
	player.teleport_authoritative(route.bottom_exit.global_position)
	await settle()
	player.get_node("LadderClimb").enter(route)
	check(player.is_climbing(),"player attaches to lower ladder")
	var bystander:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
	bystander.name="LadderBystander";bystander.setup(2,"",Vector3.ZERO,Color.WHITE,0,0);base.add_child(bystander)
	bystander.set_physics_process(false);bystander.survival.set_physics_process(false)
	bystander.global_position=route.top_exit.global_position
	check(not route.can_enter(bystander),"second player cannot enter occupied ladder from opposite end")
	check(not player.perform_inventory_action_authoritative(&"toggle_flashlight") and not player.drop_current_item_authoritative(),"inventory actions and throwing are blocked while climbing")
	player.has_journal=true;player.request_journal_phase(1);root.get_node("QuestJournal").open_journal()
	check(player._journal_phase==0 and not root.get_node("QuestJournal").is_journal_open(),"journal and its world animation cannot open on ladder")
	check(not player.handoff.usable(player),"handoff cannot use either player's hands during climb")
	check(not player.pickup_world_item_authoritative(&"battery",{}),"host cannot accept a pickup while climbing")
	var y=player.global_position.y
	for step in 1800:
		if not player.is_climbing(): break
		player.simulate_movement(1./60,Vector2(0,-1),false,false,false,0,0)
		if step%60==0: await physics_frame
	print("CLIMB FROM ",y," TO ",player.global_position," EXPECT ",route.top_exit.global_position)
	print("CLIMB CONTACT ",player.get_node("LadderClimb").last_contact," ",player.get_node("LadderClimb").last_collider)
	check(player.is_climbing() and player.get_node("LadderClimb").exit_blocked,"occupied upper landing keeps climber attached instead of overlapping teammate")
	bystander.global_position=route.top_exit.global_position+Vector3(10,0,0)
	await settle()
	player.simulate_movement(1./60,Vector2.ZERO,false,false,false,0,0)
	check(not player.is_climbing() and player.global_position.distance_to(route.top_exit.global_position)<.2,"cleared upper exit automatically lands without jump input")
	bystander.queue_free();await settle()

	var floor_gaps:=0
	for x in range(-8,9):
		for z in range(-8,9):
			var point:=Vector3(x*.2,route.top_exit.global_position.y,z*.2-180)
			if absf(point.x)<.53 and absf(point.z+180)<.51:continue
			var query:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*.3,point-Vector3.UP*.4,1)
			if base.get_world_3d().direct_space_state.intersect_ray(query).is_empty():floor_gaps+=1
	check(floor_gaps==0,"service deck is solid everywhere except the single central ladder hatch")
	var start_top=player.global_position
	for step in 90:
		player.simulate_movement(1./60,Vector2.ZERO,false,false,false,0,0)
		if step%10==0: await physics_frame
	check(player.global_position.y>start_top.y-.3,"upper landing supports player after releasing ladder")
	player.teleport_authoritative(route.top_exit.global_position)
	player.get_node("LadderClimb").enter(route)
	check(player.is_climbing(),"upper access attaches for descent")
	for step in 1800:
		if not player.is_climbing():break
		player.simulate_movement(1./60,Vector2(0,1),false,false,false,0,0)
		if step%60==0:await physics_frame
	check(not player.is_climbing() and player.global_position.distance_to(route.bottom_exit.global_position)<.2,"full physical descent reaches safe lower landing")
	var blocker:=StaticBody3D.new();var blocking_shape:=CollisionShape3D.new();var blocking_box:=BoxShape3D.new();blocking_box.size=Vector3(.4,1.,.4);blocking_shape.shape=blocking_box;blocker.add_child(blocking_shape);base.add_child(blocker);blocker.global_position=route.bottom_exit.global_position+Vector3.UP*.5
	await settle()
	check(not route.position_clear(player,route.bottom_exit.global_position),"physical object blocks the exit clearance check")
	blocker.queue_free();await settle()
	check(route.position_clear(player,route.bottom_exit.global_position),"removing object restores exit clearance")

	player.teleport_authoritative(socket.global_position+Vector3(-1,-.8,0))
	await settle()
	check(not RadioTowerProgress.act(state,&"socket",1,socket),"replacement requires the spare module")
	player.teleport_authoritative(module.global_position+Vector3(0,-.9,1.2))
	await settle()
	check(module.can_use(1,player),"spare cartridge is reachable beside the actual trial computer")
	check(RadioTowerProgress.act(state,&"module",1,module),"spare joins durable shared story inventory")
	check(not RadioTowerProgress.act(state,&"module",1,module),"module cannot be duplicated")
	player.teleport_authoritative(socket.global_position+Vector3(-1,-.8,0))
	await settle()
	check(RadioTowerProgress.act(state,&"socket",1,socket),"real upper socket accepts the cartridge")
	check(state.maintenance.get("radio_repaired",false) and not state.maintenance.get("radio_module",false),"repair commits completion and consumes spare exactly once")
	var replacement:AnimationPlayer=socket.get_node("Replacement/AnimationPlayer")
	check(replacement.is_playing(),"confirmed repair starts native replacement animation")
	await create_timer(.3).timeout
	check(tower.get_node("Visual/module_mount").position.x<-.05,"old module physically pulls out of cabinet")
	await create_timer(1.3).timeout
	check(tower.get_node("Visual/module_mount").position.is_zero_approx() and socket.get_node("Status").text=="СВЯЗЬ АКТИВНА","new module seats and status confirms completion")
	check(socket.get_node("Replacement/Indicator").material_override.emission.g>.7,"cabinet indicator turns green on completion")

	var saved=state.get_snapshot(); state._apply_snapshot(saved,true)
	check(str(state.maintenance.radio_pin)==pin and state.maintenance.get("radio_repaired",false),"snapshot restoration retains code, gate and repair")
	state.applying_initial_snapshot=true
	socket.refresh(state.get_snapshot())
	state.applying_initial_snapshot=false
	check(not replacement.is_playing() and not socket.get_node("Replacement/Extract").playing and not socket.get_node("Replacement/Insert").playing,"restored completion never replays extraction, insertion or audio")

	state.progress_persistence_enabled=true
	state.manual_save_day=0
	check(state.save_progress_authoritative(false,"manual","Tower regression"),"normal checkpoint writes new story flags")
	var loaded=state.load_saved_snapshot()
	check(str(loaded.get("maintenance",{}).get("radio_pin",""))==pin and loaded.get("maintenance",{}).get("radio_repaired",false),"disk checkpoint retains PIN and completed repair")
	base.queue_free(); await settle()
	print("RADIO TOWER CHECKS ",checks," FAILURES ",failures)
	quit(0 if failures==0 else 1)
