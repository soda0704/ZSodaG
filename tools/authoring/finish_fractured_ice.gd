extends SceneTree
## Keep hard ice edges, but avoid low-poly shading triangles across snow caps.
func _initialize():run.call_deferred()
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	var reference:="res://tools/.local/polar-expansion-2026-11-11/before-cap-normals.tscn"
	if not FileAccess.file_exists(reference):DirAccess.copy_absolute(path,reference)
	var detail=load(path).instantiate();var meshes:Dictionary={};var count:=0
	for node in detail.get_children():
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:continue
		if node.material_override.shader.resource_path!="res://assets/environments/snow/glacial_bank_ice.gdshader":continue
		var old:Mesh=node.mesh
		if not meshes.has(old):
			var height:float=node.material_override.get_shader_parameter("formation_height")
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for v in old.get_faces():
				var group:=0 if v.y>=height*.74 else 1+posmod(int(round(atan2(v.z/.65,v.x)*12/TAU)),12)
				st.set_smooth_group(group);st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
			st.generate_normals();meshes[old]=st.commit()
		node.mesh=meshes[old];count+=1
	var packed:=PackedScene.new();packed.pack(detail);ResourceSaver.save(packed,path);detail.free();print("Finished snow-cap normals on ",count," formations; vertex positions and collisions preserved");quit()
