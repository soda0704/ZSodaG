extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var scene=load("res://scenes/levels/snow_exterior.tscn").instantiate();scene.set_script(null);root.add_child(scene)
	await process_frame
	var data=scene.get_node("Terrain3D").data
	print("HAS SET HEIGHT ",data.has_method("set_height"))
	for x in range(-13,14):
		for z in range(-193,-166):
			var at:=Vector3(x,0,z);var h:float=data.get_height(at)
			var distance:=maxf(absf(x),absf(z+180))
			if is_finite(h): data.set_height(at,lerpf(10.12,h,smoothstep(6.5,13.,distance)))
	data.update_maps();data.save_directory("res://assets/environments/snow/expanded_terrain")
	print("TOWER FOUNDATION FIT")
	scene.queue_free();await process_frame;quit()
