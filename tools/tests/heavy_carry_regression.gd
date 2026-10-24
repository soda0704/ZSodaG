extends SceneTree
var checks:=0
var failures:=0
var actors:Array[GamePlayer]=[]
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle(frames:=5) -> void:
	for frame in frames: await physics_frame
func aim(actor:GamePlayer,point:Vector3) -> void:
	var offset:=point-actor.head.global_position
	actor.rotation.y=atan2(-offset.x,-offset.z)
	actor.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for peer in [1,2]:
		var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(peer,"Carrier",Vector3(-2.15 if peer==1 else 2.15,.02,.25),Color.WHITE,-PI/2 if peer==1 else PI/2)
		actor.name=str(peer)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.get_node("ItemDrag").set_physics_process(false)
		actors.append(actor)
	var prop:HeavyCarryProp=load("res://scenes/objects/props/bench.tscn").instantiate()
	arena.add_child(prop)
	await settle(20)
	for index in 2:
		var point:=prop.grip_point(index)
		point.x*=.85
		point.y-=.12
		aim(actors[index],point)
		await settle()
		check(actors[index].get_interaction_target()==prop,"native E sees authored bench edge")
		check(prop.acquire_grip(actors[index]),"player claims separate grip")
	check(prop.grips.size()==2,"two players have exactly two grip slots")
	check(prop.acquire_grip(actors[0]) and prop.grips.size()==2,"repeated hold renews lease without duplicate grips")
	check(actors[0].get_node("ItemDrag").is_heavy_carrying() and actors[1].get_node("ItemDrag").is_heavy_carrying(),"both busy-hand states replicate")
	check(not actors[0].weapon.perform_action(&"fire"),"carrying blocks attacks")
	check(not actors[0].handoff.start_authoritative(&"tape",true),"carrying cannot also offer inventory")
	var start:=prop.global_position
	for frame in 90:
		for actor in actors:
			actor.position.z-=.008
			prop.acquire_grip(actor)
		await physics_frame
	print("HEAVY MOTION ",start," -> ",prop.global_position)
	check(prop.global_position.z < start.z-.25,"paired forces actually transport the rigid body")
	check(prop.global_position.y > .05 and prop.global_position.y < .6,"paired carry lifts only to a bounded hand height")
	prop.release_grip(1)
	check(prop.grips.size()==1 and not actors[0].get_node("ItemDrag").is_heavy_carrying(),"one release preserves the partner grip")
	for frame in 50:
		prop.acquire_grip(actors[1])
		await physics_frame
	check(prop.global_position.y<.08,"single carrier lowers the object to the floor")
	check(prop.linear_velocity.length()<2,"single-carrier speed stays bounded")
	await settle(30)
	check(prop.grips.is_empty() and not actors[1].get_node("ItemDrag").is_heavy_carrying(),"missing heartbeat releases both occupancy and animation")
	var before:=actors[0].get_inventory_snapshot()
	prop.network_interact(1,actors[0])
	check(actors[0].get_inventory_snapshot()==before and not prop._collected,"heavy furniture cannot enter inventory")
	for kind in ["sofa","concrete_joist_1","concrete_joist_2"]:
		var item:HeavyCarryProp=load("res://scenes/objects/props/"+kind+".tscn").instantiate()
		check(item.get_node("Grips").get_child_count()==2,"authored grips exist: "+kind)
		check(not item.pickup_enabled and not item.draggable,"furniture cannot use ordinary single-owner drag: "+kind)
		item.free()
	var beam:HeavyCarryProp=load("res://scenes/objects/props/concrete_joist_1.tscn").instantiate()
	arena.add_child(beam)
	beam.position=Vector3(0,.015,5)
	actors[0].position=Vector3(-3.3,.02,5)
	aim(actors[0],Vector3(-2.3,.55,5))
	await settle(10)
	var drag=actors[0].get_node("ItemDrag")
	drag._hold(beam.get_path())
	check(beam.grips.size()==1,"ordinary owner-checked drag path claims the concrete beam")
	var beam_start:=beam.global_transform
	for frame in 150:
		actors[0].position.z+=.012
		drag._hold(beam.get_path())
		await physics_frame
	check(beam.global_position.distance_to(beam_start.origin)>.4 or absf(beam.rotation.y)>.25,"solo player can physically move or turn the heavy concrete beam")
	drag._release()
	check(beam.grips.is_empty(),"solo concrete grip releases cleanly")
	actors.clear()
	prop = null
	arena.queue_free()
	await settle()
	print("HEAVY CARRY CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
