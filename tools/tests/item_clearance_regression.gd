extends SceneTree
var checks:=0
var failures:=0
var world:Node3D
var actor:GamePlayer
func _initialize():
	ProjectSettings.set_setting("northern_lab/testing/settings_path","user://item_clearance_%d.json"%OS.get_process_id())
	run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle():
	for i in 4:await physics_frame
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();var cube:=BoxShape3D.new();cube.size=size;shape.shape=cube;body.add_child(shape);world.add_child(body);body.position=at;return body
func run():
	world=Node3D.new();root.add_child(world);current_scene=world
	box(Vector3(0,-.15,0),Vector3(20,.3,20))
	var wall:=box(Vector3(0,1,-.7),Vector3(8,3,.15))
	actor=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3(0,.06,0),Color.WHITE,0,0);world.add_child(actor)
	actor.set_physics_process(false);actor.survival.set_physics_process(false)
	await settle()
	for kind in [&"m4a1",&"fuel_can",&"pistol",&"crowbar",&"kitchen_knife",&"fuse",&"flashlight"]:
		for pitch in [0.,1.1]:
			actor.head.rotation.x=pitch
			actor.apply_held_item_inventory(kind,{},false);actor.weapon.apply_state(kind,10,0)
			check(actor.drop_current_item_authoritative(),"drop near wall/floor succeeds: %s pitch %.1f"%[kind,pitch])
			var item:WorldItemPickup=get_first_node_in_group("world_items")
			if item!=null:
				var clear:=true
				for shape:CollisionShape3D in item.find_children("*","CollisionShape3D",true,false):
					if shape.get_parent() is Area3D or shape.disabled:continue
					var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape.shape;query.transform=shape.global_transform;query.collision_mask=1;query.exclude=[actor.get_rid(),item.get_rid()]
					if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():clear=false
				check(clear,"actual collider starts outside wall and floor: "+str(kind))
				item.queue_free()
			await settle()
	actor.head.rotation=Vector3.ZERO
	var hidden:WorldItemPickup=load("res://scenes/objects/items/fuel_can_pickup.tscn").instantiate();world.add_child(hidden);hidden.position=Vector3(0,1,-1.4);hidden.freeze=true
	actor.apply_held_item_inventory(&"",{},false);await settle()
	hidden.network_interact(1,actor)
	check(not hidden._collected and actor._held_item_type==&"","authoritative pickup cannot reach through a wall")
	hidden.position=Vector3(0,1,-.25);await settle();hidden.network_interact(1,actor)
	check(hidden._collected and actor._held_item_type==&"fuel_can","same item can be picked from reachable side")
	await settle()
	wall.queue_free();await settle()
	box(Vector3(2,.8,-.5),Vector3(1.2,.1,1.2))
	var ammo:WorldItemPickup=load("res://scenes/objects/items/weapon_pickup.tscn").instantiate();ammo.item_type=&"pistol_ammo";ammo.item_state={"amount":12};ammo.position=Vector3(2,.88,-.5);world.add_child(ammo);ammo.freeze=true
	actor.teleport_authoritative(Vector3(2,.06,1),0);await settle()
	check(ammo.visible_to(actor),"thin ammunition resting on a real table remains accessible")
	var count:=actor.weapon.pistol_ammo;ammo.network_interact(1,actor)
	check(actor.weapon.pistol_ammo==count+12,"table pickup transfers ammunition once")
	# No free spawn volume: neither G nor a weapon swap may discard ownership.
	var enclosure:=box(actor.global_position+Vector3.UP,Vector3(4,4,4))
	actor.apply_held_item_inventory(&"m4a1",{},false);actor.weapon.apply_state(&"m4a1",17,0)
	await settle()
	check(not actor.drop_current_item_authoritative(),"drop refuses an entirely obstructed spawn volume")
	check(actor._held_item_type==&"m4a1" and int(actor.get_held_item_state().get("rounds",0))==17,"refused drop retains weapon and its ammunition")
	check(not actor.pickup_world_item_authoritative(&"pistol",{"rounds":5}),"swap refuses when the old held weapon cannot be placed")
	check(actor._held_item_type==&"m4a1" and int(actor.get_held_item_state().get("rounds",0))==17,"refused swap retains the original item state")
	enclosure.queue_free()
	world.queue_free();await settle();print("ITEM CLEARANCE CHECKS ",checks," FAILURES ",failures);quit(0 if failures==0 else 1)
