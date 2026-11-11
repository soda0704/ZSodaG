extends SceneTree
const OLD:=[Vector2(-215,-170),Vector2(-205,-145),Vector2(-214,-120),Vector2(-195,-90),Vector2(-204,-65),Vector2(-188,-40)]
const BACKUP:="res://tools/.local/stream-smooth-2026-11-11/"
func _initialize():run.call_deferred()
func sample_curve(rows:Array,z:float)->Vector3:
	for k in rows.size()-1:
		if z<=float(rows[k+1][1]):
			var t:=clampf((z-float(rows[k][1]))/(float(rows[k+1][1])-float(rows[k][1])),0,1)
			return Vector3(lerpf(rows[k][0],rows[k+1][0],t),lerpf(rows[k][2],rows[k+1][2],t),lerpf(rows[k][3],rows[k+1][3],t))
	var last:Array=rows.back();return Vector3(last[0],last[2],last[3])
func old_curve(z:float)->Vector2:
	for k in OLD.size()-1:
		if z<=OLD[k+1].y:
			var t:=clampf((z-OLD[k].y)/(OLD[k+1].y-OLD[k].y),0,1)
			return Vector2(lerpf(OLD[k].x,OLD[k+1].x,t),3.2+1.2*sin((k+t)*1.3))
	return Vector2(-188,3.2+1.2*sin(6.5))
func run():
	if DirAccess.dir_exists_absolute(BACKUP):push_error("Stream reshape already applied");quit(1);return
	DirAccess.make_dir_recursive_absolute(BACKUP)
	var dir:="res://assets/environments/snow/expanded_terrain/"
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".res"):DirAccess.copy_absolute(dir+f,BACKUP+f)
	DirAccess.copy_absolute("res://scenes/levels/polar_ice_lowland.tscn",BACKUP+"before.tscn")
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/snow/smooth_stream_layout.json"))
	var snow=load("res://scenes/levels/snow_exterior.tscn").instantiate();snow.set_script(null)
	for child in snow.find_children("*","",true,false):
		if child.get_script()!=null:child.set_script(null)
	root.add_child(snow);var data=snow.get_node("Terrain3D").data
	# Read every target before writing any height: a local coordinate warp, not a region rollback.
	var updates:Array=[]
	for z in range(-170,-39):
		var old:=old_curve(z);var next:=sample_curve(rows,z)
		for x in range(-249,-155):
			var distance:=absf(x-next.x);var blend:=1.0-smoothstep(14,27,distance)
			var ratio:=lerpf(1.0,old.y/next.z,1.0-smoothstep(8,18,distance))
			var source_x:=lerpf(float(x),old.x+(x-next.x)*ratio,blend)
			var h:float=data.get_height(Vector3(source_x,0,z));var current:float=data.get_height(Vector3(x,0,z))
			if is_finite(h) and absf(h-current)>.001:updates.append(Vector3(x,h,z))
	for p in updates:data.set_height(p,p.y)
	data.update_maps();data.save_directory(dir)
	var detail=load("res://scenes/levels/polar_ice_lowland.tscn").instantiate();snow.add_child(detail)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in rows.size()-1:
		var a:Array=rows[k];var b:Array=rows[k+1]
		var aa:=Vector2(a[0],a[1]);var bb:=Vector2(b[0],b[1]);var sa:Vector2
		if k==0:sa=(bb-aa).normalized().orthogonal()*12
		else:sa=(bb-Vector2(rows[k-1][0],rows[k-1][1])).normalized().orthogonal()*12
		var sb:Vector2
		if k+2>=rows.size():sb=(bb-aa).normalized().orthogonal()*12
		else:sb=(Vector2(rows[k+2][0],rows[k+2][1])-aa).normalized().orthogonal()*12
		var a0:=Vector3(aa.x-sa.x,a[2],aa.y-sa.y);var a1:=Vector3(aa.x+sa.x,a[2],aa.y+sa.y)
		var b0:=Vector3(bb.x-sb.x,b[2],bb.y-sb.y);var b1:=Vector3(bb.x+sb.x,b[2],bb.y+sb.y)
		for v in [a0,a1,b0,a1,b1,b0]:st.add_vertex(v)
	st.generate_normals();detail.get_node("MeltwaterStream").mesh=st.commit()
	for i in 4:
		var ice:MeshInstance3D=detail.get_node("FracturedIce_2_%d"%i)
		var old:=old_curve(ice.position.z);var next:=sample_curve(rows,ice.position.z)
		ice.position.x=next.x+(ice.position.x-old.x)*next.z/old.y
		var surfaces:=ArrayMesh.new()
		for s in ice.mesh.get_surface_count():
			var arrays=ice.mesh.surface_get_arrays(s);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			for j in vertices.size():
				if vertices[j].y<.25:
					var world:=ice.to_global(vertices[j]);var ground:float=data.get_height(world)
					vertices[j].y=ice.to_local(Vector3(world.x,ground-.3,world.z)).y
			arrays[Mesh.ARRAY_VERTEX]=vertices;surfaces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		ice.mesh=surfaces
		for body in ice.get_children():ice.remove_child(body);body.free()
		ice.create_trimesh_collision()
		for body in ice.get_children():
			body.owner=detail
			for shape in body.get_children():shape.owner=detail
	var packed:=PackedScene.new();packed.pack(detail);assert(ResourceSaver.save(packed,"res://scenes/levels/polar_ice_lowland.tscn")==OK)
	print("PASS local stream reshape samples=",updates.size()," cross sections=",rows.size())
	snow.free();quit()
