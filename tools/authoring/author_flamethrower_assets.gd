extends SceneTree
## Offline asset extraction and simplification. Never attached to a game node.
const OUT := "res://assets/models/crafting/prepared/"
const ART := "res://scenes/art/crafting/"
var source: Node3D
var meshes := {}
var materials := {}
var report := {}

func _initialize() -> void: run.call_deferred()

func attach(child: Node, parent: Node, owner_node: Node) -> void:
	parent.add_child(child); child.owner = owner_node

func persist_scene(node: Node, path: String) -> void:
	var packed := PackedScene.new()
	assert(packed.pack(node) == OK)
	assert(ResourceSaver.save(packed,path) == OK)

func material_for(original: Material) -> Material:
	if materials.has(original): return materials[original]
	var mat: Material = original.duplicate()
	var path := OUT + "source_material_%d.tres" % materials.size()
	ResourceSaver.save(mat,path); mat.take_over_path(path)
	materials[original] = mat
	return mat

func reduced(mesh: ArrayMesh, label: String) -> ArrayMesh:
	var importer := ImporterMesh.new()
	var original_count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		original_count += arrays[Mesh.ARRAY_INDEX].size()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},mesh.surface_get_material(surface))
	importer.generate_lods(60.0,25.0,[])
	var result := ArrayMesh.new()
	var reduced_count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var best: PackedInt32Array = indices
		var target_ratio := 1500.0 / (original_count/3.0) if label == "hardware_box" else .70
		var minimum_ratio := .01 if label == "hardware_box" else .48
		var score := 1.0 if label == "hardware_box" else .30
		for lod in importer.get_surface_lod_count(surface):
			var candidate := importer.get_surface_lod_indices(surface,lod)
			var ratio := float(candidate.size()) / indices.size()
			if ratio >= minimum_ratio and absf(ratio-target_ratio) < score:
				score = absf(ratio-target_ratio); best = candidate
		# Compact all vertex streams; the base mesh itself has fewer triangles.
		var remap := {}; var used: Array[int] = []; var compact_indices := PackedInt32Array()
		for index in best:
			if not remap.has(index): remap[index] = used.size(); used.append(index)
			compact_indices.append(remap[index])
		for channel in Mesh.ARRAY_INDEX:
			if arrays[channel] == null or arrays[channel].is_empty(): continue
			var old = arrays[channel]; var compact = old.duplicate(); compact.resize(0)
			var stride := 4 if channel == Mesh.ARRAY_TANGENT else 1
			for vertex in used:
				for component in stride: compact.append(old[vertex*stride+component])
			arrays[channel] = compact
		arrays[Mesh.ARRAY_INDEX] = compact_indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		result.surface_set_material(surface,mesh.surface_get_material(surface))
		reduced_count += compact_indices.size()
	report[label] = {"original_triangles":original_count/3,"triangles":reduced_count/3}
	print("SIMPLIFIED ",label," ",report[label])
	return result

func combine(names: Array, transform: Transform3D) -> ArrayMesh:
	var tools_by_material := {}
	for name in names:
		var node: MeshInstance3D = meshes[name]
		for surface in node.mesh.get_surface_count():
			var mat := material_for(node.mesh.surface_get_material(surface))
			if not tools_by_material.has(mat):
				var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
				tools_by_material[mat] = st
			tools_by_material[mat].append_from(node.mesh,surface,transform*node.global_transform)
	var result := ArrayMesh.new()
	for mat in tools_by_material:
		tools_by_material[mat].set_material(mat)
		tools_by_material[mat].commit(result)
	return result

func save_mesh(mesh: ArrayMesh, label: String) -> ArrayMesh:
	var value := reduced(mesh,label)
	var path := OUT+label+".res"
	assert(ResourceSaver.save(value,path,ResourceSaver.FLAG_COMPRESS) == OK)
	value.take_over_path(path)
	return value

func loose_part(label: String, names: Array, height: float, rotation: Basis = Basis.IDENTITY) -> Node3D:
	var raw := combine(names,Transform3D(rotation,Vector3.ZERO))
	var bounds := raw.get_aabb()
	var scale_factor := height/bounds.size.y
	var center := bounds.get_center(); center.y = bounds.position.y
	var placement := Transform3D(rotation.scaled(Vector3.ONE*scale_factor),-center*scale_factor)
	var mesh := save_mesh(combine(names,placement),label)
	var art := Node3D.new(); art.name = label.to_pascal_case()
	var visual := MeshInstance3D.new(); visual.name="Body"; visual.mesh=mesh; attach(visual,art,art)
	if label in ["large_cylinder","small_cylinder"]: visual.material_override=load(OUT+"loose_cylinder_paint.tres")
	persist_scene(art,ART+label+".tscn")
	return art

func block(parent: Node3D, owner_node: Node, name: String, at: Vector3, size: Vector3, mat: Material) -> void:
	var visual := MeshInstance3D.new(); visual.name=name; visual.position=at
	var mesh := BoxMesh.new(); mesh.size=size; mesh.material=mat; visual.mesh=mesh
	attach(visual,parent,owner_node)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT); DirAccess.make_dir_recursive_absolute(ART)
	source=load("res://assets/models/crafting/flamethrower_source/scene.gltf").instantiate();root.add_child(source)
	for node in source.find_children("*","MeshInstance3D",true,false):
		meshes[String(node.name).split("_standardSurface")[0]]=node
	loose_part("large_cylinder",["polySurface163"],0.43,Basis(Vector3.RIGHT,-PI/2)).free()
	loose_part("small_cylinder",["pCylinder44"],0.26).free()
	loose_part("pressure_gauge",["polySurface185","polySurface186","polySurface153"],0.14).free()
	loose_part("valve",["polySurface102","polySurface132","polySurface122","pCylinder45","pCylinder70"],0.21).free()
	var cola=load("res://assets/models/crafting/cola_source/scene.gltf").instantiate();root.add_child(cola)
	var cola_mesh: MeshInstance3D=cola.find_children("*","MeshInstance3D",true,false)[0]
	# Keep cola extraction on the same prepared-material path.
	var cola_material:=material_for(cola_mesh.mesh.surface_get_material(0))
	var cola_st:=SurfaceTool.new();cola_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	cola_st.append_from(cola_mesh.mesh,0,cola_mesh.global_transform)
	var cola_raw:=cola_st.commit(); var cb:=cola_raw.get_aabb()
	var cola_scale:=0.12/cb.size.y;var cola_center:=cb.get_center();cola_center.y=cb.position.y
	cola_st=SurfaceTool.new();cola_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	cola_st.append_from(cola_raw,0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*cola_scale),-cola_center*cola_scale))
	cola_st.set_material(cola_material)
	var cola_ready:=save_mesh(cola_st.commit(),"cola_can")
	var cola_art:=Node3D.new();cola_art.name="ColaCan"
	var can:=MeshInstance3D.new();can.name="Body";can.mesh=cola_ready;attach(can,cola_art,cola_art)
	persist_scene(cola_art,ART+"cola_can.tscn")
	# Finished gun retains its original muzzle/nozzle; no extra can is attached.
	var frame:=Basis(Vector3.UP,PI);var grip:=Vector3(0,-0.080,-0.375)
	var gun_raw:=combine(meshes.keys(),Transform3D(frame,-(frame*grip)))
	# Fit the fixed stock to the existing rifle pose, keeping the trigger in the palm.
	# This is saved mesh authoring, never a runtime deformation or animation.
	var fitted:=ArrayMesh.new()
	for surface in gun_raw.get_surface_count():
		var arrays:=gun_raw.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			if vertices[i].z > .05: vertices[i].z=.05+(vertices[i].z-.05)*.76
		arrays[Mesh.ARRAY_VERTEX]=vertices
		fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		fitted.surface_set_material(surface,gun_raw.surface_get_material(surface))
	var gun_mesh:=save_mesh(fitted,"flamethrower")
	# Preserve editor-authored contacts when geometry is re-extracted.
	var previous_gun: Node3D=load("res://scenes/objects/items/flamethrower_model.tscn").instantiate()
	var support_transform: Transform3D=previous_gun.get_node("LeftHandGrip").transform
	previous_gun.free()
	var gun:=Node3D.new();gun.name="FlamethrowerModel"
	var body:=MeshInstance3D.new();body.name="Body";body.mesh=gun_mesh;attach(body,gun,gun)
	var grip_marker:=Marker3D.new();grip_marker.name="LeftHandGrip";grip_marker.transform=support_transform;attach(grip_marker,gun,gun)
	var right_grip:=Marker3D.new();right_grip.name="RightHandGrip";right_grip.position=Vector3(.04,-.035,.015);attach(right_grip,gun,gun)
	var muzzle:=Marker3D.new();muzzle.name="Muzzle";muzzle.position=Vector3(0,.109,-.63);attach(muzzle,gun,gun)
	persist_scene(gun,"res://scenes/objects/items/flamethrower_model.tscn")
	# Open-ended pipe bundle: five loose tubes tied as one readable loot pickup.
	var steel:=StandardMaterial3D.new();steel.albedo_color=Color(.24,.28,.29);steel.metallic=.78;steel.roughness=.64
	var strap:=StandardMaterial3D.new();strap.albedo_color=Color(.16,.17,.17);strap.roughness=.95
	var pipes:=Node3D.new();pipes.name="PipeBundle"
	for i in 5:
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var length:=.34+float((i*7)%5)*.045
		for segment in 12:
			var a:=TAU*segment/12.0;var b:=TAU*(segment+1)/12.0
			var outer_a:=Vector2(cos(a),sin(a))*.022;var outer_b:=Vector2(cos(b),sin(b))*.022
			var inner_a:=outer_a*.74;var inner_b:=outer_b*.74
			for quad_points in [[Vector3(outer_a.x,outer_a.y,0),Vector3(outer_b.x,outer_b.y,0),Vector3(outer_b.x,outer_b.y,length),Vector3(outer_a.x,outer_a.y,length)], [Vector3(inner_b.x,inner_b.y,0),Vector3(inner_a.x,inner_a.y,0),Vector3(inner_a.x,inner_a.y,length),Vector3(inner_b.x,inner_b.y,length)], [Vector3(outer_b.x,outer_b.y,0),Vector3(outer_a.x,outer_a.y,0),Vector3(inner_a.x,inner_a.y,0),Vector3(inner_b.x,inner_b.y,0)], [Vector3(outer_a.x,outer_a.y,length),Vector3(outer_b.x,outer_b.y,length),Vector3(inner_b.x,inner_b.y,length),Vector3(inner_a.x,inner_a.y,length)]]:
				for index in [0,2,1,0,3,2]:st.add_vertex(quad_points[index])
		st.generate_normals();st.set_material(steel)
		var pipe:=MeshInstance3D.new();pipe.name="Pipe%d"%i;pipe.mesh=st.commit()
		pipe.position=Vector3((i%3-1)*.046,.025+(i/3)*.045,-length/2+float(i%2)*.035)
		pipe.rotation.y=(i-2)*.022;attach(pipe,pipes,pipes)
	for i in 2:
		block(pipes,pipes,"TieTop%d"%i,Vector3(0,.096,-.10+i*.20),Vector3(.17,.009,.026),strap)
		block(pipes,pipes,"TieBottom%d"%i,Vector3(0,.003,-.10+i*.20),Vector3(.17,.009,.026),strap)
		for side in [-1,1]:block(pipes,pipes,"TieSide%d_%d"%[i,side],Vector3(side*.08,.05,-.10+i*.20),Vector3(.009,.10,.026),strap)
	persist_scene(pipes,ART+"pipe_bundle.tscn")
	# The supplied fastener case replaces the temporary hand-built tray.
	var hardware: Node3D=load("res://assets/models/crafting/hardware_source/scene.gltf").instantiate(); root.add_child(hardware)
	var hardware_source: MeshInstance3D=hardware.find_children("*","MeshInstance3D",true,false)[0]
	var hardware_builder:=SurfaceTool.new();hardware_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	hardware_builder.append_from(hardware_source.mesh,0,hardware_source.global_transform)
	var hardware_raw:=hardware_builder.commit();var hb:=hardware_raw.get_aabb()
	var hardware_scale:=.30/maxf(hb.size.x,hb.size.z);var hardware_center:=hb.get_center();hardware_center.y=hb.position.y
	hardware_builder=SurfaceTool.new();hardware_builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	hardware_builder.append_from(hardware_raw,0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*hardware_scale),-hardware_center*hardware_scale))
	hardware_builder.set_material(material_for(hardware_source.mesh.surface_get_material(0)))
	var case_mesh:=save_mesh(hardware_builder.commit(),"hardware_box")
	var box:=Node3D.new();box.name="HardwareBox"
	var case_visual:=MeshInstance3D.new();case_visual.name="Body";case_visual.mesh=case_mesh;attach(case_visual,box,box)
	persist_scene(box,ART+"hardware_box.tscn")
	hardware.queue_free()
	var file:=FileAccess.open(OUT+"mesh_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CRAFT_ASSETS_READY")
	gun.free(); cola_art.free(); pipes.free(); box.free()
	meshes.clear(); materials.clear()
	source.queue_free(); cola.queue_free()
	await process_frame
	quit()
