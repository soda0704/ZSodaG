extends SceneTree
## MultiMesh transforms need a graphical rendering server for this test.
func _initialize(): run.call_deferred()
func run():
	if DisplayServer.get_name() == "headless":
		push_error("Run with a graphical renderer to inspect MultiMesh transforms")
		quit(1)
		return
	var world = load("res://scenes/levels/snow_exterior.tscn").instantiate()
	root.add_child(world)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	await process_frame
	await RenderingServer.frame_post_draw
	var terrain = world.get_node("Terrain3D")
	var colliders = world.get_node("Landscape/RockAndTreeCollision").get_children()
	var failures := 0
	var count := 0
	for node in world.get_node("Landscape").get_children():
		if not node is MultiMeshInstance3D or not str(node.name).begins_with("RockVariant"): continue
		var vertices: PackedVector3Array = node.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var low := INF
		for v in vertices: low = minf(low,v.y)
		for i in node.multimesh.instance_count:
			var t: Transform3D = node.multimesh.get_instance_transform(i)
			for v in vertices:
				if v.y > low+0.35: continue
				var point := t*v
				var ground: float = terrain.data.get_height(point)
				if not is_finite(ground) or point.y > ground+0.02:
					failures+=1
					break
			var matched := false
			for collider in colliders:
				if str(collider.name).begins_with("Rock") and collider.transform.is_equal_approx(t):
					matched=true
					break
			if not matched: failures+=1
			count+=1
	print("ROCKS ",count," GROUND/COLLISION FAILURES ",failures)
	quit(0 if failures==0 else 1)
