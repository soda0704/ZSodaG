extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var level:Node3D=load("res://scenes/levels/floor_minus1_control_security_blockout.tscn").instantiate()
	root.add_child(level)
	for frame in 90:await physics_frame
	# Isolate beam clearance from the now-correct initially closed level doors.
	var manager = level.get_node("Doors/AutomaticDoors")
	manager.set_process(false)
	for door in manager._doors: manager._apply_door_state(door, true, true)
	for frame in 2: await physics_frame
	var prop:HeavyCarryProp=level.get_node("FallenCheckpointJoist")
	check(prop.global_position.x < -15 and prop.global_position.x > -16,"beam is immediately before first spine door")
	var capsule:=CapsuleShape3D.new()
	capsule.radius=.32
	capsule.height=1.0
	for z in [-1.8,-.9,0,.9,1.8]:
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=capsule
		query.collision_mask=1
		query.transform=Transform3D(Basis.IDENTITY,Vector3(-14.3,.53,z))
		query.motion=Vector3(-2.0,0,0)
		var fractions:=level.get_world_3d().direct_space_state.cast_motion(query)
		check(fractions[0] < .95,"crouched capsule cannot pass under beam at z="+str(z))
	var session=load("res://scenes/levels/base_session.tscn").instantiate()
	session.set_script(load("res://tools/tests/fixtures/heavy_prop_checkpoint_session.gd"))
	root.add_child(session)
	var saved:Dictionary=session.capture_heavy_prop_checkpoint()
	var original:=prop.global_transform
	prop.global_position.z=7
	session.restore_heavy_prop_checkpoint(saved)
	check(prop.global_transform.is_equal_approx(original),"placed obstacle position restores through native checkpoint methods")
	check(prop.grips.is_empty(),"checkpoint restores furniture without transient carriers")
	prop.freeze=true
	prop.position.z=7
	for frame in 5:await physics_frame
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=1
	query.transform=Transform3D(Basis.IDENTITY,Vector3(-14.3,.53,0))
	query.motion=Vector3(-2,0,0)
	var fractions:=level.get_world_3d().direct_space_state.cast_motion(query)
	check(fractions[0]>.99,"moving beam clears its collision and opens the passage")
	var living:Node3D=load("res://scenes/art/base/living/common_room_art.tscn").instantiate()
	check(living.get_node("Visual/MovableSofa") is HeavyCarryProp,"living sofa uses shared carry mechanism")
	check(living.get_node("Visual/NorthMovableBench") is HeavyCarryProp and living.get_node("Visual/SouthMovableBench") is HeavyCarryProp,"both existing dining benches use shared carry mechanism")
	check(not living.has_node("Blockout/Common_Room/Lounge/Living_Lounge_Sofa_Blockout"),"old static sofa collision is removed")
	living.free()
	session.queue_free()
	level.queue_free()
	await process_frame
	await process_frame
	print("HEAVY LEVEL CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
