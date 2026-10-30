extends SceneTree
func _initialize(): run.call_deferred()
func run():
	root.get_node("GameMenu").force_close_menu()
	var cam:=Camera3D.new();root.add_child(cam);cam.current=true;cam.position=Vector3(0,100,-180)
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null);root.add_child(snow)
	await process_frame;await RenderingServer.frame_post_draw
	var data=snow.get_node("Terrain3D").data
	var body:=StaticBody3D.new();body.collision_layer=1<<19
	var shape:=CollisionShape3D.new();shape.shape=snow.get_node("CliffValley/DistantValleyFloor").mesh.create_trimesh_shape();body.add_child(shape);root.add_child(body)
	await physics_frame;await physics_frame
	var space=root.get_world_3d().direct_space_state
	var result=[]
	for node in snow.find_children("*","MultiMeshInstance3D",true,false):
		if not (str(node.name).begins_with("Pine") or str(node.name).begins_with("Forest") or str(node.name).begins_with("RockVariant")):continue
		var mm:MultiMesh=node.multimesh
		var changes=[]
		for i in mm.instance_count:
			var t:=mm.get_instance_transform(i)
			var point:Vector3=node.to_global(t.origin)
			var old_point:=point
			var offset:=Vector3.ZERO
			var close:=Vector2(point.x,point.z+180)
			if close.length()<13 and (str(node.name).begins_with("Rock") or str(node.name).begins_with("Pine")):
				var direction:=close.normalized() if close.length()>.1 else Vector2.RIGHT
				offset=Vector3(direction.x,0,direction.y)*(18-close.length())
				point+=offset
			var h:float=data.get_height(point)
			if str(node.name).begins_with("Forest"):
				var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(point.x,2000,point.z),Vector3(point.x,-1000,point.z),1<<19))
				if not hit.is_empty():h=maxf(h,hit.position.y) if is_finite(h) else hit.position.y
			var base:float=mm.mesh.get_aabb().position.y*t.basis.y.length()
			if is_finite(h) and (absf(point.y+base-h)>.15 or offset.length()>0):
				changes.append({"index":i,"x":old_point.x,"z":old_point.z,"next_x":point.x,"next_z":point.z,"old":t.origin.y,"next":t.origin.y+h-point.y-base,"delta":h-point.y-base})
		if not changes.is_empty():result.append({"path":str(snow.get_path_to(node)),"changes":changes,"count":mm.instance_count,"bounds":str(mm.mesh.get_aabb())})
	var f=FileAccess.open("res://tools/.local/radio_tower/forest_grounding.json",FileAccess.WRITE);f.store_string(JSON.stringify(result))
	print("LANDSCAPE AUDIT groups ",result.size())
	snow.queue_free();body.queue_free();await process_frame;quit()
