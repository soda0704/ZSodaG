extends SceneTree
const DIR := "res://assets/environments/snow/expanded_terrain/"
const BACKUP := "res://tools/.local/polar-coast-2026-11-11/regions-v2/"
func _initialize():run.call_deferred()
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Backup exists; refusing cumulative sculpt");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".res"):DirAccess.copy_absolute(DIR+f,BACKUP+f)
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();var weather=snow.get_node("Blizzard");snow.remove_child(weather);weather.free();root.add_child(snow)
	var data=snow.get_node("Terrain3D").data
	var count:=0
	for x in range(-230,180):
		for z in range(-260,220):
			var p:=Vector2(x,z);var at:=Vector3(x,0,z);var old:float=data.get_height(at)
			if not is_finite(old) or data.get_control_hole(at):continue
			var apron:=Vector2(maxf(absf(x+2.0)-45.0,0),maxf(absf(float(z))-34.0,0)).length()
			var keep:=smoothstep(5,18,apron)*smoothstep(35,58,p.distance_to(Vector2(-125,95)))*smoothstep(16,32,p.distance_to(Vector2(0,-180)))
			var route:=Geometry2D.get_closest_point_to_segment(p,Vector2(-92,95),Vector2(-41,3))
			keep*=smoothstep(5,14,p.distance_to(route))
			var edge:float=smoothstep(-230,-190,float(x))*(1-smoothstep(130,180,float(x)))*smoothstep(-260,-210,float(z))*(1-smoothstep(170,220,float(z)))
			var phase:float=x*.045+z*.083+sin(z*.019)*1.3
			var drift:float=pow(.5+.5*sin(phase),4.0)*(1.0+.7*sin(x*.014-z*.009))+sin(x*.018+z*.011)*.35
			var h:=old+drift*keep*edge
			var r:=Vector2((x+110.0)/40.0,(z+105.0)/29.0).length()
			var angle:=atan2((z+105.0)/29.0,(x+110.0)/40.0)
			r*=1.0+.13*sin(angle*3+.7)+.10*sin(angle*5-1.0)
			h=lerpf(h,-6.4,1-smoothstep(.5,1.2,r))
			if absf(h-old)>.001:data.set_height(at,h);count+=1
	data.update_maps();data.save_directory(DIR)
	print("POLAR LOWLAND samples=",count)
	var detail:=Node3D.new();detail.name="PolarIceLowland"
	var ice:=StandardMaterial3D.new();ice.albedo_texture=load("res://assets/environments/snow/ice004/ice004_color.jpg");ice.normal_enabled=true;ice.normal_texture=load("res://assets/environments/snow/ice004/ice004_normalgl.jpg");ice.roughness_texture=load("res://assets/environments/snow/ice004/ice004_roughness.jpg");ice.albedo_color=Color(.65,.82,.88);ice.uv1_triplanar=true;ice.uv1_world_triplanar=true;ice.uv1_scale=Vector3.ONE*.35
	var frost:=StandardMaterial3D.new();frost.albedo_texture=load("res://assets/environments/snow/snow006/runtime_albedo_ao.res");frost.normal_enabled=true;frost.normal_texture=load("res://assets/environments/snow/snow006/runtime_normal_rough.res");frost.roughness=1.0;frost.uv1_triplanar=true;frost.uv1_world_triplanar=true
	var rng:=RandomNumberGenerator.new();rng.seed=11112026
	for i in 24:
		var a:=rng.randf_range(0,TAU);var pos:=Vector3(-110+cos(a)*rng.randf_range(23,36),0,-105+sin(a)*rng.randf_range(15,25));pos.y=maxf(data.get_height(pos),-6.0)-.15
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var ring:Array[Vector3]=[];var w:=rng.randf_range(1.0,3.2);var height:=rng.randf_range(.7,2.4)
		for k in 7:ring.append(Vector3(cos(k*TAU/7)*w, rng.randf_range(.0,.2),sin(k*TAU/7)*w*.6))
		var top:Array[Vector3]=[]
		for v in ring:top.append(Vector3(v.x*.75,height*rng.randf_range(.65,1.0),v.z*.8))
		var peak:=Vector3(0,height*.85,0)
		for k in 7:
			for v in [top[k],peak,top[(k+1)%7],ring[k],top[k],ring[(k+1)%7],ring[(k+1)%7],top[k],top[(k+1)%7]]:st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
		st.generate_normals();var mesh:=MeshInstance3D.new();mesh.name="PressureIce%02d"%i;mesh.mesh=st.commit();mesh.material_override=ice;mesh.layers=65536;mesh.position=pos;detail.add_child(mesh);mesh.owner=detail;mesh.create_trimesh_collision()
		for child in mesh.get_children():child.owner=detail;for_shape(child,detail)
		var cap:=SurfaceTool.new();cap.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 7:
			for v in [top[k]*Vector3(.92,1,.92)+Vector3.UP*.025,peak+Vector3.UP*.025,top[(k+1)%7]*Vector3(.92,1,.92)+Vector3.UP*.025]:cap.set_uv(Vector2(v.x,v.z));cap.add_vertex(v)
		cap.generate_normals();var crust:=MeshInstance3D.new();crust.mesh=cap.commit();crust.material_override=frost;crust.layers=65536;crust.position=pos;detail.add_child(crust);crust.owner=detail
	var water:=MeshInstance3D.new();water.name="ExposedWater";var plane:=CylinderMesh.new();plane.top_radius=1;plane.bottom_radius=1;plane.height=.03;plane.radial_segments=96;water.mesh=plane;water.position=Vector3(-110,-6.0,-105);water.layers=65536;water.scale=Vector3(52,1,38)
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(.035,.12,.15);mat.roughness=.16;mat.metallic_specular=.8;mat.normal_enabled=true;mat.normal_texture=ice.normal_texture;mat.normal_scale=.12;water.material_override=mat;detail.add_child(water);water.owner=detail
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,"res://scenes/levels/polar_ice_lowland.tscn")
	snow.queue_free();detail.free();await process_frame
	quit()
func for_shape(node:Node,owner_node:Node):
	for child in node.get_children():child.owner=owner_node;for_shape(child,owner_node)
