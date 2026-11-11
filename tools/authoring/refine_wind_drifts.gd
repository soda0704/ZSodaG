extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/wind-drifts-2026-11-11/"
# x,z,half length,half width,height,yaw. Sparse wind-carved crests, not a repeating wave field.
const DRIFTS:=[
	[-168,-47,35,6,.85,.3],[-145,7,27,5,1.1,.18],[-181,38,31,6,.75,.36],
	[-69,78,25,5,.7,.3],[-49,125,42,9,1.6,.42],[5,109,40,7,1.25,.34],
	[63,72,26,5,.8,.24],[131,29,43,8,1.8,.4],[94,-38,36,6,1.3,.29],
	[58,-104,44,8,1.7,.38],[-20,-117,27,5,.9,.22],[-83,-166,35,7,1.5,.31],
	[-275,-83,53,11,2.1,.35],[-280,4,41,9,1.5,.26],[-178,164,57,12,2.3,.33],
	[71,190,67,15,2.7,.32],[199,-82,74,17,3.2,.37],[-74,-243,72,15,2.8,.3]]
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
