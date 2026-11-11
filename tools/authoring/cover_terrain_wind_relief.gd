extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/full-wind-relief-2026-11-11/"
func _initialize():run.call_deferred()
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Full wind relief already applied");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	var files:Array[String]=[];var coords:Dictionary={}
	var minp:=Vector2(INF,INF);var maxp:=Vector2(-INF,-INF)
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".res"):continue
		files.append(f);DirAccess.copy_absolute(DIR+f,BACKUP+f)
		var suffix:=f.trim_prefix("terrain3d").trim_suffix(".res")
		var loc:=Vector2(int(suffix.substr(0,3).replace("_","")),int(suffix.substr(3,3).replace("_","")))
		coords[f]=loc;minp=minp.min(loc*256);maxp=maxp.max((loc+Vector2.ONE)*256)
	var curve:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/snow/smooth_stream_layout.json"))
	var ice_scene=load("res://scenes/levels/polar_ice_lowland.tscn").instantiate();var ice_positions:Array[Vector2]=[]
	for ice in ice_scene.get_children():
		if ice is MeshInstance3D and ice.material_override is ShaderMaterial and ice.material_override.shader.resource_path.ends_with("glacial_bank_ice.gdshader"):ice_positions.append(Vector2(ice.position.x,ice.position.z))
	ice_scene.free()
	var noise:=FastNoiseLite.new();noise.seed=112611;noise.frequency=.055
	var broad:=FastNoiseLite.new();broad.seed=81277;broad.frequency=.009
	var total:=0;var peak:=0.0
	for f in files:
		var region=load(DIR+f);var image:Image=region.get_height_map().duplicate();var origin:Vector2=coords[f]*256;var changed:=0
		for j in image.get_height():
			for i in image.get_width():
				var p:=origin+Vector2(i,j)
				var edge:=minf(minf(p.x-minp.x,maxp.x-p.x),minf(p.y-minp.y,maxp.y-p.y))
				var keep:=smoothstep(12,55,edge)
				var apron:=Vector2(maxf(absf(p.x+2)-47,0),maxf(absf(p.y)-36,0)).length()
				keep*=smoothstep(8,23,apron)*smoothstep(43,62,p.distance_to(Vector2(-125,95)))*smoothstep(22,40,p.distance_to(Vector2(0,-180)))
				keep*=smoothstep(10,20,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(-92,95),Vector2(-41,3))))
				if p.x>-280 and p.x<170 and p.y>-205 and p.y<155:
					for basin in [Vector4(-110,-105,53,40),Vector4(105,95,44,24),Vector4(-215,90,29,43)]:
						var q:=(p-Vector2(basin.x,basin.y))/Vector2(basin.z,basin.w);keep*=smoothstep(0,18,(q.length()-1)*minf(basin.z,basin.w))
					var d:=INF
					for k in curve.size()-1:
						var a:=Vector2(curve[k][0],curve[k][1]);var b:=Vector2(curve[k+1][0],curve[k+1][1]);d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))-maxf(curve[k][3],curve[k+1][3]))
					keep*=smoothstep(7,18,d)
					for at in ice_positions:keep*=smoothstep(10,18,p.distance_to(at))
				if keep<.001:continue
				var q:=p.rotated(-.32);var warp:=broad.get_noise_2d(p.x,p.y)*16
				var n:=noise.get_noise_2d(q.x*.16,q.y+warp)
				var ridge:=pow(clampf(n*2.2+.15,0,1),2.6)
				var variation:=.65+.55*(broad.get_noise_2d(p.x+271,p.y-133)*.5+.5)
				var height:=ridge*variation*1.5*keep
				if height>.006:
					var old:float=image.get_pixel(i,j).r;image.set_pixel(i,j,Color(old+height,0,0,1));changed+=1;peak=maxf(peak,height)
		region.location=Vector2i(coords[f]);region.set_height_map(image);region.set_modified(true);assert(region.save(DIR+f,false)==OK)
		total+=changed;print("WIND REGION ",f," samples=",changed)
		await process_frame
	print("PASS full terrain wind relief regions=",files.size()," changed=",total," maximum addition=",peak," bounds=",minp,"..",maxp)
	quit()
