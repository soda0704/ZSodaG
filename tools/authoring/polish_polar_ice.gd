extends SceneTree
func _initialize():run.call_deferred()
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	var backup:="res://tools/.local/polar-polish-2026-11-11/before-ice.tscn"
	if FileAccess.file_exists(backup):push_error("Polish reference already exists; refusing cumulative deformation");quit(1);return
	DirAccess.make_dir_recursive_absolute(backup.get_base_dir());DirAccess.copy_absolute(path,backup)
	var detail=load(path).instantiate();var meshes:Dictionary={};var count:=0
	for node in detail.get_children():
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:continue
		if node.material_override.shader.resource_path!="res://assets/environments/snow/glacial_bank_ice.gdshader":continue
		var old:Mesh=node.mesh;var material:ShaderMaterial=node.material_override
		var height:float=material.get_shader_parameter("formation_height")
		if not meshes.has(old):
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var faces:=old.get_faces();var radius:=old.get_aabb().size.x*.5
			for start in range(0,faces.size(),3):
				var triangle:Array[Vector3]=[]
				for k in 3:
					var v:Vector3=faces[start+k]
					v.x=minf(v.x,radius*.76+v.z*.12)
					v.y=minf(v.y,height*.84+v.x*.075-v.z*.045)
					triangle.append(v)
				if (triangle[1]-triangle[0]).cross(triangle[2]-triangle[0]).length_squared()<.000001:continue
				for v in triangle:
					st.set_smooth_group(0 if v.y>height*.68 else 1+posmod(int(round(atan2(v.z/.65,v.x)*12/TAU)),12));st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
			st.generate_normals();meshes[old]=st.commit()
		node.mesh=meshes[old]
		material.set_shader_parameter("snow_normal",load("res://assets/environments/snow/snow006/runtime_normal_rough.res"))
		material.set_shader_parameter("ice_normal",load("res://assets/environments/snow/ice004/ice004_normalgl.jpg"))
		for body in node.get_children():node.remove_child(body);body.free()
		node.create_trimesh_collision()
		for body in node.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
		count+=1
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,path);detail.free();print("POLISHED ",count," ice formations with cut faces, micro normals and updated collisions");quit()
