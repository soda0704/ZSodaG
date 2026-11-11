extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/polar-expansion-2026-11-11/regions/"
const STREAM:=[Vector2(-215,-170),Vector2(-205,-145),Vector2(-214,-120),Vector2(-195,-90),Vector2(-204,-65),Vector2(-188,-40)]
func _initialize():run.call_deferred()
func closest(p:Vector2,levels:Array)->Vector3:
	var best:=Vector3(INF,0,0)
	for k in STREAM.size()-1:
		var q:Vector2=Geometry2D.get_closest_point_to_segment(p,STREAM[k],STREAM[k+1]);var t:float=q.distance_to(STREAM[k])/STREAM[k].distance_to(STREAM[k+1]);var d:=p.distance_to(q)
		if d<best.x:best=Vector3(d,lerpf(levels[k],levels[k+1],t),k+t)
	return best
func own(node:Node,root_node:Node):
	for child in node.get_children():child.owner=root_node;own(child,root_node)
func bank_side(index:int)->Vector2:
	return (STREAM[mini(index+1,STREAM.size()-1)]-STREAM[maxi(0,index-1)]).normalized().orthogonal()*12
func tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3):
	for v in [a,c,b]:st.add_vertex(v)
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Expansion backup exists; refusing cumulative height changes");quit(1);return
	var existing=load("res://scenes/levels/polar_ice_lowland.tscn").instantiate()
	var expanded:bool=existing.has_node("WaterBasin0");existing.free()
	if expanded:push_error("Waterways already exist; restore an intentional baseline before regenerating");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".res"):DirAccess.copy_absolute(DIR+file,BACKUP+file)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();var weather=snow.get_node("Blizzard");snow.remove_child(weather);weather.free();root.add_child(snow)
	var data=snow.get_node("Terrain3D").data
	var ponds:=[Vector4(105,95,32,12),Vector4(-215,90,17,31)]
	var levels:Array=[];var stream_levels:Array=[]
	for p in ponds:levels.append(data.get_height(Vector3(p.x,0,p.y))-.65)
	for p in STREAM:stream_levels.append(data.get_height(Vector3(p.x,0,p.y))-.45)
	# A gently descending watercourse, without uphill water segments.
	for k in range(1,stream_levels.size()):stream_levels[k]=minf(stream_levels[k],stream_levels[k-1]-.12)
	var changed:=0
	for x in range(-260,160):
		for z in range(-225,185):
			var p:=Vector2(x,z);var at:=Vector3(x,0,z);var old:float=data.get_height(at)
			if not is_finite(old) or data.get_control_hole(at):continue
			var apron:=Vector2(maxf(absf(x+2.0)-45.0,0),maxf(absf(float(z))-34.0,0)).length()
			var keep:=smoothstep(6,18,apron)*smoothstep(42,60,p.distance_to(Vector2(-125,95)))*smoothstep(18,35,p.distance_to(Vector2(0,-180)))
			var route:=Geometry2D.get_closest_point_to_segment(p,Vector2(-92,95),Vector2(-41,3));keep*=smoothstep(7,16,p.distance_to(route))
			# Existing pond remains at its established water level.
			keep*=smoothstep(48,65,p.distance_to(Vector2(-110,-105)))
			var envelope:=smoothstep(-260,-245,float(x))*(1-smoothstep(145,160,float(x)))*smoothstep(-225,-205,float(z))*(1-smoothstep(165,185,float(z)))
			var drift:=pow(.5+.5*sin(x*.065+z*.12+sin(z*.028)*1.6),5.0)*(.35+.5*(.5+.5*sin(x*.021-z*.013)))
			var target:=old+drift*keep*envelope
			for i in ponds.size():
				var pond:Vector4=ponds[i];var q:=(p-Vector2(pond.x,pond.y))/Vector2(pond.z,pond.w);var a:=atan2(q.y,q.x);var r:=q.length()*(1+.12*sin(a*3+i)+.07*sin(a*5))
				var depth:=.85 if i==0 else 2.2
				target=lerpf(target,float(levels[i])-depth,(1-smoothstep(.55,1.25,r))*keep)
				target=lerpf(target,maxf(target,float(levels[i])+.35),exp(-pow((r-1.05)/.22,2.0))*keep)
			var near:=closest(p,stream_levels);var width:=3.2+1.2*sin(near.z*1.3)
			target=lerpf(target,near.y-.8,(1-smoothstep(width*.7,width+5,near.x))*keep)
			target=lerpf(target,maxf(target,near.y+.3),exp(-pow((near.x-width-3.0)/2.5,2.0))*keep)
			if absf(target-old)>.001:data.set_height(at,target);changed+=1
	data.update_maps();data.save_directory(DIR)
	var detail=load("res://scenes/levels/polar_ice_lowland.tscn").instantiate()
	var water_material:Material=detail.get_node("ExposedWater").material_override
	for i in ponds.size():
		var p:Vector4=ponds[i];var mesh:=MeshInstance3D.new();mesh.name="WaterBasin%d"%i;var plane:=PlaneMesh.new();plane.size=Vector2(p.z*3,p.w*3);mesh.mesh=plane;mesh.position=Vector3(p.x,levels[i],p.y);mesh.layers=65536;var material:=water_material.duplicate() as ShaderMaterial;material.set_shader_parameter("mask_type",1);material.set_shader_parameter("basin_bounds",p);material.set_shader_parameter("basin_phase",float(i));mesh.material_override=material;detail.add_child(mesh);mesh.owner=detail
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in STREAM.size()-1:
		var a:Vector2=STREAM[k];var b:Vector2=STREAM[k+1];var sa:=bank_side(k);var sb:=bank_side(k+1)
		var a0:=Vector3(a.x-sa.x,stream_levels[k],a.y-sa.y);var a1:=Vector3(a.x+sa.x,stream_levels[k],a.y+sa.y)
		var b0:=Vector3(b.x-sb.x,stream_levels[k+1],b.y-sb.y);var b1:=Vector3(b.x+sb.x,stream_levels[k+1],b.y+sb.y)
		# Up-facing ribbon; terrain hides its excess width at the banks.
		tri(st,a0,b0,a1);tri(st,a1,b0,b1)
	st.generate_normals();var stream:=MeshInstance3D.new();stream.name="MeltwaterStream";stream.mesh=st.commit();stream.layers=65536;var stream_material:=water_material.duplicate() as ShaderMaterial;stream_material.set_shader_parameter("mask_type",2);stream.material_override=stream_material;detail.add_child(stream);stream.owner=detail
	var rng:=RandomNumberGenerator.new();rng.seed=11112027
	for zone in 3:
		for i in 4:
			var source:MeshInstance3D=detail.get_node("GlacialBank%02d"%((i+zone*2)%7));var ice:=source.duplicate() as MeshInstance3D;ice.name="FracturedIce_%d_%d"%[zone,i]
			var p:Vector2
			var level:float
			if zone<2:
				var pond:Vector4=ponds[zone];var angle:=float(i)*.62+.3+zone*1.7;p=Vector2(pond.x+cos(angle)*pond.z*.83,pond.y+sin(angle)*pond.w*.83);level=levels[zone]
			else:p=STREAM[i+1]+Vector2(5 if i%2==0 else -5,0);level=stream_levels[i+1]
			ice.position=Vector3(p.x,maxf(data.get_height(Vector3(p.x,0,p.y)),level)-.3,p.y);ice.rotation.y=rng.randf_range(-PI,PI);ice.scale=Vector3(rng.randf_range(.35,.7),rng.randf_range(.5,1.2),rng.randf_range(.4,.9));detail.add_child(ice);ice.owner=detail;own(ice,detail)
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,"res://scenes/levels/polar_ice_lowland.tscn")
	FileAccess.open("res://tools/.local/polar-expansion-2026-11-11/layout.json",FileAccess.WRITE).store_string(JSON.stringify({"pond_levels":levels,"stream_levels":stream_levels,"samples":changed}))
	FileAccess.open("res://tools/authoring/polar_waterways_layout.json",FileAccess.WRITE).store_string(JSON.stringify({"pond_levels":levels,"stream_levels":stream_levels,"samples":changed}))
	print("EXPANDED heights=",changed," pond levels=",levels," stream=",stream_levels)
	snow.queue_free();detail.free();await process_frame;quit()

