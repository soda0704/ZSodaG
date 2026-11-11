extends SceneTree
const OUTPUT:="res://scenes/art/environment/polar_location_details.tscn"
func _initialize():run.call_deferred()
func save_scene(node:Node,path:String):
	var packed:=PackedScene.new();assert(packed.pack(node)==OK);assert(ResourceSaver.save(packed,path)==OK)
func own_tree(node:Node,owner_node:Node):
	for child in node.get_children():child.owner=owner_node;own_tree(child,owner_node)
func make_material(rock:bool=false)->ShaderMaterial:
	var m:=ShaderMaterial.new();m.shader=load("res://assets/environments/snow/stream_bend_ice.gdshader")
	if rock:
		var shader:=Shader.new();shader.code=m.shader.code.replace("shader_type spatial;","shader_type spatial;\nrender_mode cull_disabled;").replace("vec3 n=normalize(world_normal);","vec3 n=normalize(world_normal);if(!FRONT_FACING){n=-n;}")
		assert(ResourceSaver.save(shader,"res://assets/environments/snow/snow_covered_scans.gdshader")==OK);m.shader=shader
	m.set_shader_parameter("snow_color",load("res://assets/environments/snow/snow006/runtime_albedo_ao.res"));m.set_shader_parameter("snow_normal",load("res://assets/environments/snow/snow006/runtime_normal_rough.res"))
	for pair in [["ice_color","color.res","rock_06_diff_2k.jpg"],["ice_normal","normalgl.res","rock_06_nor_gl_2k.jpg"],["ice_roughness","roughness.res","rock_06_rough_2k.jpg"]]:
		m.set_shader_parameter(pair[0],load("res://assets/environments/"+("cave/pbr/"+pair[2] if rock else "snow/ice003/"+pair[1])))
	m.set_shader_parameter("rock_mode",rock);return m
func run():
	var output:=Node3D.new();output.name="PolarLocationDetails"
	var ice_material:=make_material();var rock_material:=make_material(true)
	var groups:Dictionary={};var triangles:=0
	var rows=JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/environment/polar_location/geometry.json"))
	for row in rows:
		if not groups.has(row.zone):
			var zone:=Node3D.new();zone.name=row.zone;output.add_child(zone);zone.owner=output;groups[row.zone]=zone
		var bounds:=AABB(Vector3(row.vertices[0][0],row.vertices[0][1],row.vertices[0][2]),Vector3.ZERO)
		for v in row.vertices:bounds=bounds.expand(Vector3(v[0],v[1],v[2]))
		var center:=bounds.get_center();var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in row.vertices.size():
			var p=row.vertices[i];var n=row.normals[i];var coat:float=row.snow[i]
			st.set_normal(Vector3(n[0],n[1],n[2]));st.set_color(Color(coat,coat,coat,1));st.set_uv(Vector2(p[0],p[2]));st.add_vertex(Vector3(p[0],p[1],p[2])-center)
		st.index();var mesh:=st.commit();var name:String=row.name.to_snake_case()
		assert(ResourceSaver.save(mesh,"res://assets/models/environment/polar_location/"+name+".res")==OK)
		var node:=MeshInstance3D.new();node.name=row.name;node.mesh=mesh;node.material_override=ice_material;node.position=center
		node.visibility_range_end=700;node.layers=327681;groups[row.zone].add_child(node);node.owner=output
		node.create_trimesh_collision();own_tree(node,output);triangles+=row.vertices.size()/3
	# Existing optimized scan geometry; no imported full-resolution meshes or random scattering.
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null)
	for n in snow.find_children("*","",true,false):n.set_script(null)
	var camera:=Camera3D.new();snow.add_child(camera);camera.current=true;root.add_child(snow)
	var data=snow.get_node("Terrain3D").data
	var rock_group:=Node3D.new();rock_group.name="CaveRimOutcrops";output.add_child(rock_group);rock_group.owner=output
	var rock_rows:=[Vector4(180,-77,8,.4),Vector4(184,-80,5.8,-.4),Vector4(175,-71,3.5,.9),Vector4(189,82,7,-.2),Vector4(185,85,4.8,.7),Vector4(194,79,2.8,-.5),Vector4(146,-272,9,.6),Vector4(151,-270,5.5,-.7),Vector4(140,-269,3.2,.2)]
	var variants:=["rock_face_01","rock_face_02","boulder_01"]
	for i in rock_rows.size():
		var r:Vector4=rock_rows[i];var mesh:Mesh=load("res://assets/environments/cave/rocks/"+variants[i%3]+"/cave_mesh.res")
		var node:=MeshInstance3D.new();node.name="Outcrop_%02d"%i;node.mesh=mesh;node.material_override=rock_material;node.layers=327681
		var size:=mesh.get_aabb().size;var scale_factor:float=r.z/maxf(size.x,maxf(size.y,size.z))
		node.scale=Vector3.ONE*scale_factor;node.rotation.y=r.w
		var bottom:float=mesh.get_aabb().position.y*scale_factor
		var floor_level:float=data.get_height(Vector3(r.x,0,r.y))
		# Bury to the lowest sampled perimeter ground, not just the central point.
		for offset in [Vector2(-.35,-.35),Vector2(.35,-.35),Vector2(-.35,.35),Vector2(.35,.35)]:floor_level=minf(floor_level,data.get_height(Vector3(r.x+offset.x*r.z,0,r.y+offset.y*r.z)))
		node.position=Vector3(r.x,floor_level-bottom-r.z*.10,r.y);node.visibility_range_end=1100
		rock_group.add_child(node);node.owner=output
		var body:=StaticBody3D.new();var collision:=CollisionShape3D.new();collision.shape=mesh.create_convex_shape(true,true);body.add_child(collision);node.add_child(body);own_tree(node,output)
	# Reflective service stakes: one shared small mesh, no real light sources.
	var markers:=Node3D.new();markers.name="ServiceRouteMarkers";output.add_child(markers);markers.owner=output
	var pole:=CylinderMesh.new();pole.top_radius=.033;pole.bottom_radius=.045;pole.height=1.55;pole.radial_segments=8
	var paint:=StandardMaterial3D.new();paint.albedo_color=Color(.45,.32,.10);paint.metallic=.35;paint.roughness=.65
	var band:=CylinderMesh.new();band.top_radius=.046;band.bottom_radius=.046;band.height=.12;band.radial_segments=8
	var reflector:=StandardMaterial3D.new();reflector.albedo_color=Color(.73,.71,.55);reflector.roughness=.55
	var posts:=[Vector2(-96,81),Vector2(-83,57),Vector2(-61,28),Vector2(-53,9),Vector2(-64,-61),Vector2(-38,-126),Vector2(-11,-161)]
	for i in posts.size():
		var p:Vector2=posts[i];var pole_node:=MeshInstance3D.new();pole_node.name="RouteStake_%02d"%i;pole_node.mesh=pole;pole_node.material_override=paint
		pole_node.position=Vector3(p.x,data.get_height(Vector3(p.x,0,p.y))+.55,p.y);pole_node.visibility_range_end=140
		markers.add_child(pole_node);pole_node.owner=output
		for h in [.36,.56]:
			var stripe:=MeshInstance3D.new();stripe.name="Reflector";stripe.mesh=band;stripe.material_override=reflector;stripe.position.y=h;stripe.visibility_range_end=140;pole_node.add_child(stripe);stripe.owner=output
	save_scene(output,OUTPUT)
	# Retain previous prototypes, but exclude their duplicate visuals and collisions.
	var path:="res://scenes/levels/polar_ice_lowland.tscn";var old=load(path).instantiate()
	for node in old.get_children():
		if node is MeshInstance3D and (String(node.name).begins_with("GlacialBank") or String(node.name).begins_with("FracturedIce")):
			node.visible=false
			for shape in node.find_children("*","CollisionShape3D",true,false):shape.disabled=true
	save_scene(old,path);old.free()
	path="res://scenes/levels/snow_exterior.tscn";var text:=FileAccess.get_file_as_string(path)
	if not text.contains("id=\"polar_location_details\""):
		text=text.replace("[gd_scene format=3 uid=\"uid://it38xnxigcbi\"]","[gd_scene format=3 uid=\"uid://it38xnxigcbi\"]\n\n[ext_resource type=\"PackedScene\" path=\""+OUTPUT+"\" id=\"polar_location_details\"]")
		text+="\n[node name=\"PolarLocationDetails\" parent=\".\" instance=ExtResource(\"polar_location_details\")]\n"
		FileAccess.open(path,FileAccess.WRITE).store_string(text)
	print("PASS installed whole-location details ice meshes=",rows.size()," ice triangles=",triangles," rock scans=",rock_rows.size()," service stakes=",posts.size())
	snow.free();output.free();quit()
