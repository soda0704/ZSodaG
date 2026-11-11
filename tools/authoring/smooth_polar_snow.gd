extends SceneTree
## Offline cross-region Gaussian fairing. Does not touch control/color maps.
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/soft-snow-2026-11-11/terrain-before/"
const X0:=-512
const Z0:=-768
const W:=2048
const H:=1536
const R:=5
var regions:Dictionary={}
func _initialize():run.call_deferred()
func route_distance(p:Vector2,routes:Array)->float:
	var d:=INF
	for route in routes:
		for k in route.size()-1:d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(route[k][0],route[k][1]),Vector2(route[k+1][0],route[k+1][1]))))
	return d
func run():
	if FileAccess.file_exists("res://tools/.local/soft-snow-2026-11-11/result.json"):push_error("Snow smoothing already applied; restore backup before authoring another pass");quit(1);return
	var existing_backup:=DirAccess.dir_exists_absolute(BACKUP)
	DirAccess.make_dir_recursive_absolute(BACKUP)
	var old:=PackedFloat32Array();old.resize(W*H)
	for f in DirAccess.get_files_at(DIR):
		if not f.ends_with(".res"):continue
		if existing_backup:assert(FileAccess.get_sha256(DIR+f)==FileAccess.get_sha256(BACKUP+f),"Partial run: explicitly restore backup before retrying")
		else:assert(DirAccess.copy_absolute(DIR+f,BACKUP+f)==OK)
		var region=load(DIR+f);var loc:Vector2i=Terrain3DUtil.filename_to_location(f);regions[f]=region
		var im:Image=region.get_height_map();var ox:=loc.x*256-X0;var oz:=loc.y*256-Z0
		for z in 256:
			for x in 256:old[(oz+z)*W+ox+x]=im.get_pixel(x,z).r
	assert(regions.size()==48)
	var weights:=PackedFloat32Array();var sum:=0.0
	for k in range(-R,R+1):var v:=exp(-float(k*k)/(2*2.3*2.3));weights.append(v);sum+=v
	for k in weights.size():weights[k]/=sum
	var horizontal:=PackedFloat32Array();horizontal.resize(W*H)
	for z in H:
		var row:=z*W
		for x in W:
			var v:=0.0
			for k in range(-R,R+1):v+=old[row+clampi(x+k,0,W-1)]*weights[k+R]
			horizontal[row+x]=v
		if z%256==0:print("SMOOTH horizontal ",z);await process_frame
	var filtered:=PackedFloat32Array();filtered.resize(W*H)
	for z in H:
		for x in W:
			var v:=0.0
			for k in range(-R,R+1):v+=horizontal[clampi(z+k,0,H-1)*W+x]*weights[k+R]
			filtered[z*W+x]=v
		if z%256==0:print("SMOOTH vertical ",z);await process_frame
	var routes:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/environment/polar_location/composition.json")).routes
	var curve:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/snow/smooth_stream_layout.json"))
	var details=load("res://scenes/art/environment/polar_location_details.tscn").instantiate();var foundations:Array[Rect2]=[]
	for node in details.find_children("*","MeshInstance3D",true,false):
		if node.name.begins_with("RouteStake") or node.name.begins_with("Reflector"):continue
		var aabb:AABB=node.transform*node.mesh.get_aabb()
		foundations.append(Rect2(Vector2(aabb.position.x,aabb.position.z),Vector2(aabb.size.x,aabb.size.z)).grow(1.5))
	details.free()
	var count:=0;var maximum:=0.0;var old_curvature:=0.0;var new_curvature:=0.0
	for f in regions:
		var region=regions[f];var loc:Vector2i=Terrain3DUtil.filename_to_location(f);region.location=loc;var im:Image=region.get_height_map().duplicate();var changes:=0
		for z in 256:
			for x in 256:
				var p:=Vector2(loc.x*256+x,loc.y*256+z);var ix:=int(p.x)-X0;var iz:=int(p.y)-Z0;var index:=iz*W+ix
				var edge:=minf(minf(ix,W-1-ix),minf(iz,H-1-iz));var keep:=smoothstep(24,44,edge)
				var apron:=Vector2(maxf(absf(p.x+2)-52,0),maxf(absf(p.y)-40,0)).length()
				keep*=smoothstep(5,20,apron)*smoothstep(45,62,p.distance_to(Vector2(-125,95)))*smoothstep(32,48,p.distance_to(Vector2(0,-180)))
				keep*=smoothstep(1,1.4,Vector2((p.x-335)/90,p.y/150).length())
				if p.x<220 and p.x> -310 and p.y> -300 and p.y<190:
					keep*=smoothstep(4,10,route_distance(p,routes))
					for basin in [Vector4(-110,-105,55,42),Vector4(105,95,45,27),Vector4(-215,90,32,46)]:
						var q:=(p-Vector2(basin.x,basin.y))/Vector2(basin.z,basin.w);keep*=smoothstep(0,12,(q.length()-1)*minf(basin.z,basin.w))
					var d:=INF
					for k in curve.size()-1:d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,Vector2(curve[k][0],curve[k][1]),Vector2(curve[k+1][0],curve[k+1][1])))-maxf(curve[k][3],curve[k+1][3]))
					keep*=smoothstep(13,24,d)
					for rect in foundations:keep*=smoothstep(0,5,p.distance_to(p.clamp(rect.position,rect.end)))
				var value:=lerpf(old[index],filtered[index],keep*.9)
				if absf(value-old[index])<.0001:continue
				im.set_pixel(x,z,Color(value,0,0,1));changes+=1;maximum=maxf(maximum,absf(value-old[index]))
				if edge>24 and keep>.99:
					old_curvature+=absf(old[index-W]+old[index+W]+old[index-1]+old[index+1]-4*old[index])
					new_curvature+=absf(filtered[index-W]+filtered[index+W]+filtered[index-1]+filtered[index+1]-4*filtered[index])
		region.set_height_map(im);region.set_modified(true);assert(region.save(DIR+f,false)==OK)
		count+=changes;print("SMOOTH saved ",f," samples=",changes);await process_frame
	var result:={"changed_samples":count,"max_delta":maximum,"filtered_curvature_ratio":new_curvature/maxf(old_curvature,.0001),"sigma_m":2.3,"radius_m":R,"blend":.9}
	FileAccess.open("res://tools/.local/soft-snow-2026-11-11/result.json",FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("PASS snow fairing ",JSON.stringify(result));quit()

