extends SceneTree
## Offline local snow deposits. Run once; do not repeatedly add to the height map.
const BACKUP := "res://tools/.local/snow-material-review/terrain-before-sculpt/"
func _initialize(): run.call_deferred()
func run():
	DirAccess.make_dir_recursive_absolute(BACKUP)
	var directory := "res://assets/environments/snow/expanded_terrain/"
	for file in ["terrain3d-01_00.res", "terrain3d-01-01.res"]:
		if FileAccess.file_exists(BACKUP+file):
			push_error("Snow sculpt backup already exists; refusing to accumulate edits")
			quit(1); return
		DirAccess.copy_absolute(directory+file,BACKUP+file)
	var level := Node3D.new(); root.add_child(level)
	var camera := Camera3D.new(); level.add_child(camera); camera.current=true
	var snow = load("res://scenes/levels/snow_exterior.tscn").instantiate()
	level.add_child(snow)
	var terrain = snow.get_node("Terrain3D")
	for frame in 4: await process_frame
	var data = terrain.data
	var deposits := [Vector4(-51,15,0.7,9),Vector4(-56,-9,0.85,11),Vector4(-72,24,0.95,13),Vector4(-86,46,1.1,12),Vector4(-60,44,0.8,10),Vector4(-46,-15,0.65,8)]
	var changed := 0
	var max_added := 0.0
	for x in range(-108,-37):
		for z in range(-26,67):
			var p := Vector2(x,z)
			var point := Vector3(x,0,z)
			var original: float = data.get_height(point)
			if not is_finite(original) or data.get_control_hole(point): continue
			var added := 0.0
			for deposit in deposits:
				var d := p-Vector2(deposit.x,deposit.y)
				var along := d.dot(Vector2(0.88,0.475))
				var across := d.dot(Vector2(-0.475,0.88))
				added += deposit.z * exp(-pow(along/deposit.w,2)*2.0-pow(across/3.6,2)*1.5)
			# Preserve a broad traversable approach and the door/garage apron.
			var closest := Geometry2D.get_closest_point_to_segment(p,Vector2(-92,95),Vector2(-41,3))
			added *= smoothstep(2.2,5.0,p.distance_to(closest))
			if x > -48: added *= smoothstep(6.0,12.0,absf(z-1.0))
			added *= smoothstep(-108.0,-100.0,float(x))*(1.0-smoothstep(-43.0,-38.0,float(x)))
			added *= smoothstep(-26.0,-19.0,float(z))*(1.0-smoothstep(59.0,67.0,float(z)))
			if added < 0.001: continue
			data.set_height(point,original+added)
			changed += 1; max_added=maxf(max_added,added)
	data.update_maps(); data.save_directory(directory)
	print("SNOW SCULPT samples=",changed," maximum deposit=",max_added)
	quit()
