extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/location-pass-2026-11-11/before/"
# Broad asymmetric crests, separated by quieter wind-scoured corridors.
const RIDGES:=[[-175,35,75,17,1.6,.32],[-70,160,85,20,2.1,.35],[92,160,65,19,2.8,.29],[-145,-225,90,22,2.6,.27],[115,-245,100,24,3.4,.34],[-320,-80,120,23,3.8,.32],[-335,130,95,26,3.1,.36],[-90,305,115,28,3.3,.27],[100,350,130,25,2.7,.31],[-290,-365,130,30,2.8,.34],[660,190,155,31,3.2,.33],[970,-180,190,35,3.8,.28],[1190,320,190,37,3.4,.32],[820,-470,175,34,2.8,.34],[1350,-400,150,26,2.2,.3]]
const ROUTES:=[[[ -92,95],[-41,3]],[[-92,95],[-104,56],[-88,20],[-65,3],[-41,3]],[[-41,3],[-70,-44],[-53,-100],[-12,-158],[0,-180]],[[48,7],[95,24],[145,38],[180,45]]]
func _initialize():run.call_deferred()
func line_distance(p:Vector2,route:Array)->float:
	var d:=INF
	for i in route.size()-1:d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(route[i][0],route[i][1]),Vector2(route[i+1][0],route[i+1][1]))))
	return d
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Composition already applied; refusing additive rerun");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for path in ["scenes/levels/snow_exterior.tscn","scenes/levels/polar_ice_lowland.tscn"]:DirAccess.copy_absolute("res://"+path,BACKUP+path.get_file())
	var curve:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/snow/smooth_stream_layout.json"))
	var noise:=FastNoiseLite.new();noise.seed=402611;noise.frequency=.008
	var changed:=0;var maximum:=0.0
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".res"):continue
		DirAccess.copy_absolute(DIR+file,BACKUP+file)
		var loc:Vector2i=Terrain3DUtil.filename_to_location(file)
		var region=load(DIR+file);var image:Image=region.get_height_map().duplicate();var origin:=Vector2(loc*256);var edits:=0
		for j in image.get_height():
			for i in image.get_width():
				var p:=origin+Vector2(i,j)
				var edge:=minf(minf(p.x+512,1536-p.x),minf(p.y+768,768-p.y))
				var keep:=smoothstep(24,65,edge)
				var apron:=Vector2(maxf(absf(p.x+2)-52,0),maxf(absf(p.y)-40,0)).length()
				keep*=smoothstep(5,24,apron)*smoothstep(45,65,p.distance_to(Vector2(-125,95)))*smoothstep(32,52,p.distance_to(Vector2(0,-180)))
				var cave:=Vector2((p.x-335)/90,p.y/150).length();keep*=smoothstep(1,1.45,cave)
				for r in ROUTES:keep*=smoothstep(7,17,line_distance(p,r))
				if p.x>-290 and p.x<180 and p.y>-215 and p.y<165:
					for basin in [Vector4(-110,-105,55,42),Vector4(105,95,45,27),Vector4(-215,90,32,46)]:
						var q:=(p-Vector2(basin.x,basin.y))/Vector2(basin.z,basin.w);keep*=smoothstep(0,18,(q.length()-1)*minf(basin.z,basin.w))
					var d:=INF
					for k in curve.size()-1:
						var a:=Vector2(curve[k][0],curve[k][1]);var b:=Vector2(curve[k+1][0],curve[k+1][1]);d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))-maxf(curve[k][3],curve[k+1][3]))
					keep*=smoothstep(13,24,d)
				if keep<.001:continue
				var delta:=0.0
				for r in RIDGES:
					var q:=(p-Vector2(r[0],r[1])).rotated(-float(r[5]));var along:=q.x/float(r[2]);var across:=q.y/(float(r[3])*(1.5 if q.y<0 else .8))
					delta+=float(r[4])*exp(-across*across*2)*(1-smoothstep(.55,1,absf(along)))
				# Very broad depressions give the base plateau a legible shoulder.
				var low:=Vector2((p.x-65)/60,(p.y+80)/44).length();delta-=1.15*exp(-low*low*2)
				var near:=1-smoothstep(160,260,p.length());delta+=noise.get_noise_2d(p.x,p.y)*.55*(1-near*.6)
				delta*=keep
				if absf(delta)>.008:
					var old:float=image.get_pixel(i,j).r;image.set_pixel(i,j,Color(old+delta,0,0,1));edits+=1;maximum=maxf(maximum,absf(delta))
		if edits>0:
			region.location=loc;region.set_height_map(image);region.set_modified(true);assert(region.save(DIR+file,false)==OK)
		changed+=edits;print("COMPOSITION ",file," samples=",edits);await process_frame
	var manifest={"ridges":RIDGES,"routes":ROUTES,"samples":changed,"max_delta":maximum}
	FileAccess.open("res://tools/.local/location-pass-2026-11-11/composition.json",FileAccess.WRITE).store_string(JSON.stringify(manifest))
	print("PASS location terrain composition samples=",changed," max delta=",maximum);quit()
