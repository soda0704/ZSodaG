extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	var backup:="res://tools/.local/polar-polish-2026-11-11/before-blender.tscn"
	if FileAccess.file_exists(backup):
		push_error("Already installed; refusing repeated replacement");quit(1);return
	DirAccess.copy_absolute(path,backup)
	var variants=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/environment/polar_fractured_ice/fracture_geometry.json"))
	var detail=load(path).instantiate();var count:=0;var triangles:=0
	for node in detail.get_children():
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:continue
		if node.material_override.shader.resource_path!="res://assets/environments/snow/glacial_bank_ice.gdshader":continue
		var bounds:Vector3=node.mesh.get_aabb().size
		var height:float=node.material_override.get_shader_parameter("formation_height")
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for point in variants[count%variants.size()]:
			var v:=Vector3(point[0]*bounds.x,point[1]*height,point[2]*bounds.z)
			st.set_smooth_group(-1);st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
		st.generate_normals();node.mesh=st.commit()
		triangles+=node.mesh.get_faces().size()/3
		for body in node.get_children():node.remove_child(body);body.free()
		node.create_trimesh_collision()
		for body in node.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
		count+=1
	var packed:=PackedScene.new();packed.pack(detail);var result:=ResourceSaver.save(packed,path)
	assert(count==19 and result==OK)
	print("PASS Blender meshes: ",count,"; triangles: ",triangles,"; collisions regenerated")
	detail.free();quit()
