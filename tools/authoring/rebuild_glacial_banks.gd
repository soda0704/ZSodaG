extends SceneTree
func _initialize():run.call_deferred()
func triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3):
	if (b-a).cross(c-a).length_squared()<.000001:return
	# Godot front faces use clockwise winding.
	for v in [a,c,b]:st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	var backup:="res://tools/.local/polar-coast-2026-11-11/before-glacial-banks.tscn"
	if not FileAccess.file_exists(backup):DirAccess.copy_absolute(path,backup)
	# Regenerate from the untouched reference instead of accumulating deformation.
	var detail=load(backup).instantiate()
	for child in detail.get_children():
		if child.name!=&"ExposedWater":detail.remove_child(child);child.free()
	var noise:=FastNoiseLite.new();noise.seed=110112;noise.frequency=.45
	var forms:=[Vector4(-139.5,-110.5,4.8,1.8),Vector4(-137,-88,3.5,1.4),Vector4(-116,-82,5.3,2.3),Vector4(-88,-89,3.8,1.5),Vector4(-80,-112,5.8,2.6),Vector4(-108,-127,3.8,1.3),Vector4(-126,-116,2.8,.9)]
	for i in forms.size():
		var f:Vector4=forms[i];var rings:Array=[]
		for band in 9:
			var t:=band/8.0;var profile:float=[0.0,.92,1.0,1.0,.98,.95,.90,.65,0.0][band];var ring:Array[Vector3]=[]
			for k in 49:
				var angle:=k*TAU/12;var radius:=profile*(1.0+.10*sin(angle*3+i)+.06*sin(angle*5-.4))
				var v:=Vector3(cos(angle)*f.z*radius,t*f.w,sin(angle)*f.z*.65*radius)
				v.y+=(noise.get_noise_3d(v.x,v.y,v.z)*.3+v.x*.10-v.z*.06)*profile
				ring.append(v)
			rings.append(ring)
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_smooth_group(-1)
		for band in 8:
			for k in 12:
				st.set_smooth_group(0 if band>=6 else k+1)
				triangle(st,rings[band][k],rings[band+1][k],rings[band][k+1]);triangle(st,rings[band][k+1],rings[band+1][k],rings[band+1][k+1])
		st.generate_normals();var mesh:=MeshInstance3D.new();mesh.name="GlacialBank%02d"%i;mesh.mesh=st.commit();mesh.position=Vector3(f.x,-6.28,f.y);mesh.layers=65536
		var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/snow/glacial_bank_ice.gdshader");material.set_shader_parameter("formation_height",f.w);material.set_shader_parameter("snow_color",load("res://assets/environments/snow/snow006/runtime_albedo_ao.res"));material.set_shader_parameter("ice_detail",load("res://assets/environments/snow/ice004/ice004_color.jpg"));mesh.material_override=material
		detail.add_child(mesh);mesh.owner=detail;mesh.create_trimesh_collision()
		for body in mesh.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
	var water:MeshInstance3D=detail.get_node("ExposedWater");var material:=ShaderMaterial.new();material.shader=load("res://assets/environments/snow/shallow_polar_water.gdshader");water.material_override=material
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,path);detail.free();print("REBUILT seven glacial banks; water no longer uses ice normal map");quit()
