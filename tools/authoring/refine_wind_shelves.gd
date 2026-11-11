extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/wind-shelves-2026-11-11/"
# x,z,half length,half width,height,yaw. Sparse wind-carved crests, not a repeating wave field.
const DRIFTS:=[[-171,16,65,11,1.05,.32],[-91,134,62,13,1.3,.28],[70,-68,70,12,1.1,.35],[173,83,61,10,1.2,.3],[-286,128,57,12,1.4,.38]]
func _initialize():run.call_deferred()
func water_distance(p:Vector2,rows:Array)->float:
	var distance:=INF
	for k in rows.size()-1:
		var a:=Vector2(rows[k][0],rows[k][1]);var b:=Vector2(rows[k+1][0],rows[k+1][1])
		distance=minf(distance,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))-maxf(rows[k][3],rows[k+1][3]))
	# Exclude the complete shores as well as water. Current ice foundations stay seated.
	for basin in [Vector4(-110,-105,53,40),Vector4(105,95,44,24),Vector4(-215,90,29,43)]:
		var q:=(p-Vector2(basin.x,basin.y))/Vector2(basin.z,basin.w)
		distance=minf(distance,(q.length()-1)*minf(basin.z,basin.w))
	return distance
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Wind relief already applied");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".res"):DirAccess.copy_absolute(DIR+f,BACKUP+f)
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/snow/smooth_stream_layout.json"))
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null)
	for child in snow.find_children("*","",true,false):
		if child.get_script()!=null:child.set_script(null)
	root.add_child(snow);var data=snow.get_node("Terrain3D").data;var count:=0;var maximum:=0.0
	for x in range(-360,300):
		for z in range(-310,260):
			var p:=Vector2(x,z);var at:=Vector3(x,0,z);var old:float=data.get_height(at)
			if not is_finite(old) or data.get_control_hole(at):continue
			var apron:=Vector2(maxf(absf(x+2.0)-47,0),maxf(absf(float(z))-36,0)).length()
			var keep:=smoothstep(8,22,apron)*smoothstep(43,62,p.distance_to(Vector2(-125,95)))*smoothstep(22,40,p.distance_to(Vector2(0,-180)))
			var route:=Geometry2D.get_closest_point_to_segment(p,Vector2(-92,95),Vector2(-41,3));keep*=smoothstep(10,19,p.distance_to(route))
			keep*=smoothstep(7,18,water_distance(p,rows))
			# Keep every existing ice foundation unchanged, including minor fragments.
			var ice_root=snow.get_node("PolarIceLowland")
			for ice in ice_root.get_children():
				if ice is MeshInstance3D and ice.name!="MeltwaterStream" and not str(ice.name).begins_with("Water") and ice.name!="ExposedWater":
					keep*=smoothstep(10,18,p.distance_to(Vector2(ice.position.x,ice.position.z)))
			if keep<.001:continue
			var height:=0.0
			for row in DRIFTS:
				var q:=(p-Vector2(row[0],row[1])).rotated(-float(row[5]));var along:=q.x/float(row[2]);var across:=q.y/float(row[3])
				# Broad windward slope, shorter leeward face; continuous at crest and ends.
				across/=1.35 if across<0 else .72
				var end:=1.0-smoothstep(.55,1.0,absf(along))
				var profile:=exp(-across*across*2.2)*(1.0-smoothstep(1.5,2.1,absf(across)))
				height+=float(row[4])*profile*end
			height*=keep
			if height>.008:data.set_height(at,old+height);count+=1;maximum=maxf(maximum,height)
	data.update_maps();data.save_directory(DIR)
	print("PASS wind relief samples=",count," maximum addition=",maximum," protected shores, ice, arrival and route")
	snow.free();quit()
