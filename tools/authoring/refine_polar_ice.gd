extends SceneTree
func _initialize():run.call_deferred()
func add_tri(st:SurfaceTool, a:Vector3,b:Vector3,c:Vector3):
	for v in [a,b,c]:st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	if FileAccess.file_exists("res://tools/.local/polar-coast-2026-11-11/before-water-refine.tscn"):
		push_error("Original ice backup exists; refusing cumulative regeneration");quit(1);return
	DirAccess.copy_absolute(path,"res://tools/.local/polar-coast-2026-11-11/before-water-refine.tscn")
	var detail=load(path).instantiate()
	var rng:=RandomNumberGenerator.new();rng.seed=20261112
	for i in 24:
		var mesh:MeshInstance3D=detail.get_node("PressureIce%02d"%i)
		var cap:MeshInstance3D=detail.get_child(mesh.get_index()+1)
		var bounds:=mesh.mesh.get_aabb();var w:=bounds.size.x*.5;var d:=bounds.size.z*.5
		var h:=rng.randf_range(.35,1.1)
		var bottom:Array[Vector3]=[];var top:Array[Vector3]=[]
		for k in 8:
			var angle:=k*TAU/8;var radius:=rng.randf_range(.85,1.0)
			var p:=Vector3(cos(angle)*w*radius,0,sin(angle)*d*radius)
			bottom.append(p-Vector3.UP*.3)
			top.append(Vector3(p.x*.9,h+p.x*.06+p.z*.04,p.z*.9))
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var crust:=SurfaceTool.new();crust.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 8:
			var next:=(k+1)%8
			add_tri(st,top[k],Vector3(0,h,0),top[next])
			add_tri(st,bottom[k],top[k],bottom[next]);add_tri(st,bottom[next],top[k],top[next])
			add_tri(st,bottom[next],Vector3(0,-.3,0),bottom[k])
			add_tri(crust,top[k]+Vector3.UP*.035,Vector3(0,h+.035,0),top[next]+Vector3.UP*.035)
		st.generate_normals();crust.generate_normals();mesh.mesh=st.commit();cap.mesh=crust.commit()
		for child in mesh.get_children():mesh.remove_child(child);child.free()
		mesh.create_trimesh_collision()
		for body in mesh.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
	var water:MeshInstance3D=detail.get_node("ExposedWater")
	var plane:=PlaneMesh.new();plane.size=Vector2(2,2);water.mesh=plane
	var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/snow/shallow_polar_water.gdshader")
	material.set_shader_parameter("ripple_normal",load("res://assets/environments/snow/ice004/ice004_normalgl.jpg"));water.material_override=material
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,path);detail.free()
	print("REFINED 24 closed planar ice slabs and depth-transparent water");quit()
