extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	var backup:="res://tools/.local/polar-polish-2026-11-11/before-seating.tscn"
	if FileAccess.file_exists(backup):push_error("Already seated; refusing cumulative changes");quit(1);return
	DirAccess.copy_absolute(path,backup)
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate()
	snow.set_script(null)
	for child in snow.find_children("*","",true,false):
		if child.get_script()!=null:child.set_script(null)
	root.add_child(snow)
	var data=snow.get_node("Terrain3D").data
	var detail=load(path).instantiate();snow.add_child(detail)
	var count:=0;var changed:=0;var max_extension:=0.0
	for node in detail.get_children():
		if not node is MeshInstance3D or not node.material_override is ShaderMaterial:continue
		if node.material_override.shader.resource_path!="res://assets/environments/snow/glacial_bank_ice.gdshader":continue
		var height:float=node.material_override.get_shader_parameter("formation_height")
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for point in node.mesh.get_faces():
			var v:Vector3=point
			if v.y<height*.32:
				var world:Vector3=node.to_global(v)
				var ground:float=data.get_height(world)
				if is_finite(ground):
					var target:float=node.to_local(Vector3(world.x,ground-.3,world.z)).y
					if target<v.y:max_extension=maxf(max_extension,v.y-target);v.y=target;changed+=1
			st.set_smooth_group(0 if point.y>height*.62 else -1)
			st.set_uv(Vector2(v.x,v.z));st.add_vertex(v)
		st.generate_normals();node.mesh=st.commit()
		for body in node.get_children():node.remove_child(body);body.free()
		node.create_trimesh_collision()
		for body in node.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
		count+=1
	var packed:=PackedScene.new();packed.pack(detail);assert(ResourceSaver.save(packed,path)==OK)
	print("PASS seated formations=",count," extended vertices=",changed," max local extension=",max_extension)
	snow.free();quit()
