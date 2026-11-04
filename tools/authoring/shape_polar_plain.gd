extends SceneTree
## One-time, offline reshape. Keep base, arrival, tower and cave interfaces.
const DIRECTORY := "res://assets/environments/snow/expanded_terrain/"
const BACKUP := "res://tools/.local/snow-material-review/before-polar-plain/"
func _initialize():run.call_deferred()
func run():
	if DirAccess.dir_exists_absolute(BACKUP):
		push_error("Polar plain backup already exists; refusing to overwrite the reference terrain")
		quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for file in DirAccess.get_files_at(DIRECTORY):
		if file.ends_with(".res"):DirAccess.copy_absolute(DIRECTORY+file,BACKUP+file)
	var level:=Node3D.new();root.add_child(level)
	var camera:=Camera3D.new();level.add_child(camera);camera.current=true
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();level.add_child(snow)
	var data=snow.get_node("Terrain3D").data
	var count:=0
	for x in range(-512,1536):
		for z in range(-768,768):
			var p:=Vector2(x,z);var at:=Vector3(x,0,z)
			var old:float=data.get_height(at)
			if not is_finite(old) or data.get_control_hole(at):continue
			var radius:=p.length()
			var upper:=8.0*smoothstep(45.0,160.0,radius)
			var phase:=x*0.075+z*0.12+sin(x*0.017-z*0.011)*1.6
			# Long, low sastrugi with an irregular crest, not isolated round hills.
			var wind:=pow(0.5+0.5*sin(phase),3.0)*(0.22+0.10*sin(x*0.009+z*0.005))
			wind+=sin(x*0.006+z*0.004)*0.22
			var target:=lerpf(upper,-160.0,smoothstep(210.0,360.0,float(x)))+wind
			var box_distance:=Vector2(maxf(absf(x+2.0)-42.0,0),maxf(absf(float(z))-31.0,0)).length()
			var keep:=1.0-smoothstep(0.0,14.0,box_distance)
			keep=maxf(keep,1.0-smoothstep(18.0,36.0,p.distance_to(Vector2(-125,95))))
			keep=maxf(keep,1.0-smoothstep(7.0,18.0,p.distance_to(Vector2(0,-180))))
			var cave_distance:=Vector2((x-335.0)/60.0,z/100.0).length()
			keep=maxf(keep,1.0-smoothstep(1.0,1.6,cave_distance))
			data.set_height(at,lerpf(target,old,keep))
			count+=1
		if x%128==0:print("POLAR X ",x);await process_frame
	data.update_maps();data.save_directory(DIRECTORY)
	print("POLAR PLAIN updated samples=",count)
	quit()
