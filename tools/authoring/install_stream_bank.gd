extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var path:="res://scenes/levels/polar_ice_lowland.tscn"
	var detail=load(path).instantiate()
	if detail.has_node("AuthoredStreamBend"):
		var previous=detail.get_node("AuthoredStreamBend")
		detail.remove_child(previous);previous.free()
	var material:=ShaderMaterial.new()
	material.shader=load("res://assets/environments/snow/stream_bend_ice.gdshader")
	for pair in [["snow_color","snow006/runtime_albedo_ao.res"],["snow_normal","snow006/runtime_normal_rough.res"],["ice_color","ice003/color.res"],["ice_normal","ice003/normalgl.res"],["ice_roughness","ice003/roughness.res"]]:
		material.set_shader_parameter(pair[0],load("res://assets/environments/snow/"+pair[1]))
	var group:=Node3D.new();group.name="AuthoredStreamBend";detail.add_child(group);group.owner=detail
	var rows=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/environment/stream_bend/geometry.json"))
	var triangles:=0
	for row in rows:
		row.name=String(row.name).get_slice(".",0)
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in row.vertices.size():
			var p=row.vertices[i];var n=row.normals[i];var coat:float=row.snow[i]
			st.set_normal(Vector3(n[0],n[1],n[2]));st.set_color(Color(coat,coat,coat,1));st.set_uv(Vector2(p[0],p[2]));st.add_vertex(Vector3(p[0],p[1],p[2]))
		st.index();var mesh:=st.commit()
		assert(ResourceSaver.save(mesh,"res://assets/models/environment/stream_bend/"+row.name.to_snake_case()+".res")==OK)
		var node:=MeshInstance3D.new();node.name=row.name;node.mesh=mesh;node.material_override=material
		group.add_child(node);node.owner=detail;node.create_trimesh_collision()
		for body in node.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
		triangles+=row.vertices.size()/3
	# Replaced only the old formation inside the authored bend, retaining it for review.
	var old:MeshInstance3D=detail.get_node("FracturedIce_2_1");old.visible=false
	for shape in old.find_children("*","CollisionShape3D",true,false):shape.disabled=true
	var packed:=PackedScene.new();assert(packed.pack(detail)==OK);assert(ResourceSaver.save(packed,path)==OK)
	print("PASS installed Blender bend; meshes=",rows.size()," triangles=",triangles)
	detail.free();quit()
