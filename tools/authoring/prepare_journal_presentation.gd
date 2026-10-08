extends SceneTree
## Offline authoring only: preserves original UVs and saves an articulated model.
const OUTPUT := "res://scenes/ui/journal/book/"
const HINGE := Vector3(-0.105, 0.0, 0.008)
const PAPER_INNER_EDGE := -0.096
const PAPER_OUTER_EDGE := 0.090
const PAPER_HALF_HEIGHT := 0.139
# The two leather tongues occupy the left branches of the supplied UV atlas.
const LEATHER_PANEL_U := 0.20
# Basis arguments are columns, not rows. This maps the imported closed book to
# X = width, Y = spine, Z = front cover, without reflecting its geometry.
const SOURCE_ALIGNMENT := Transform3D(Basis(Vector3(0.05423818, 0.009044067, -0.001193456), Vector3(-0.006645707, 0.04410205, 0.032184526), Vector3(0.006249325, -0.031594526, 0.044583984)), Vector3(0.054554764, -0.10381226, -0.0953027))
var book: Node3D

func _initialize() -> void:
	run.call_deferred()

func own(node: Node, parent: Node, label: String) -> void:
	parent.add_child(node)
	node.name = label
	node.owner = book

func clip(polygon: Array, keep_front: bool) -> Array:
	var result: Array = []
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i + 1) % polygon.size()]
		var da: float = a.p.z - HINGE.z
		var db: float = b.p.z - HINGE.z
		var inside_a := da >= 0.0 if keep_front else da <= 0.0
		var inside_b := db >= 0.0 if keep_front else db <= 0.0
		if inside_a:
			result.append(a)
		if inside_a != inside_b:
			var amount := da / (da - db)
			result.append({"p": a.p.lerp(b.p, amount), "n": a.n.lerp(b.n, amount).normalized(), "uv": a.uv.lerp(b.uv, amount)})
	return result

func emit(surface: SurfaceTool, polygon: Array, offset: Vector3) -> void:
	for i in range(1, polygon.size() - 1):
		for vertex in [polygon[0], polygon[i], polygon[i + 1]]:
			surface.set_normal(vertex.n)
			surface.set_uv(vertex.uv)
			surface.add_vertex(vertex.p - offset)

func without_tongue(polygon: Array) -> Array:
	var result: Array = []
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i + 1) % polygon.size()]
		var da: float = a.uv.x - LEATHER_PANEL_U
		var db: float = b.uv.x - LEATHER_PANEL_U
		if da >= 0.0: result.append(a)
		if (da >= 0.0) != (db >= 0.0):
			var amount := da / (da - db)
			result.append({"p":a.p.lerp(b.p,amount),"n":a.n.lerp(b.n,amount).normalized(),"uv":a.uv.lerp(b.uv,amount)})
	return result

func save_mesh(mesh: ArrayMesh, path: String) -> ArrayMesh:
	assert(ResourceSaver.save(mesh, OUTPUT + path) == OK)
	return load(OUTPUT + path)

func paper(label: String, parent: Node3D, z: float, left_page: bool, shade: float = 1.0) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Positions are in the normalized source book's frame; UVs select paper only.
	var uv: Array
	if left_page:
		uv = [Vector2(0.487,0.917),Vector2(0.065,0.917),Vector2(0.065,0.06),Vector2(0.487,0.06)]
	else:
		uv = [Vector2(0.515,0.917),Vector2(0.937,0.917),Vector2(0.937,0.06),Vector2(0.515,0.06)]
	var sections := 16 if label.begins_with("Leaf") else 1
	var curl := 0.002 + (1.0-shade)*0.02 if sections > 1 else 0.0
	for row in sections:
		for column in sections:
			var corners := [Vector2(column,row),Vector2(column+1,row),Vector2(column+1,row+1),Vector2(column,row+1)]
			var indices := [0,1,2,0,2,3] if left_page else [0,2,1,0,3,2]
			for index in indices:
				var u: float = corners[index].x / sections
				var v: float = corners[index].y / sections
				var bend := sin(u*PI)*curl*(0.65+0.35*cos(v*TAU))
				var point := Vector3(lerpf(PAPER_INNER_EDGE,PAPER_OUTER_EDGE,u),lerpf(-PAPER_HALF_HEIGHT,PAPER_HALF_HEIGHT,v),z + (-bend if left_page else bend))
				surface.set_uv(uv[0].lerp(uv[1],u).lerp(uv[3].lerp(uv[2],u),v))
				surface.add_vertex(point - (HINGE if parent != book else Vector3.ZERO))
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/ui/journal/journal.png")
	material.albedo_color = Color(shade,shade,shade)
	material.roughness = 0.95
	# The paper image already contains its shading; retain the same color as the UI.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mesh := surface.commit()
	mesh.surface_set_material(0,material)
	var node := MeshInstance3D.new()
	node.mesh = save_mesh(mesh,label.to_snake_case()+".res")
	own(node,parent,label)

func binding() -> void:
	# Both ends are bound to the existing opening: the crease folds inside the
	# closed book instead of leaving a fixed cylinder outside its leather spine.
	var rig := Skeleton3D.new()
	own(rig, book, "PaperBindingRig")
	rig.add_bone("CoverFold")
	rig.add_bone("FixedFold")
	var hinge_rest := Transform3D(Basis.IDENTITY, HINGE)
	rig.set_bone_rest(0, hinge_rest)
	rig.set_bone_rest(1, Transform3D.IDENTITY)
	rig.reset_bone_poses()
	var skin := Skin.new()
	skin.add_bind(0, hinge_rest.affine_inverse())
	skin.add_bind(1, Transform3D.IDENTITY)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for column in 8:
		var corners := [Vector2(column,0),Vector2(column+1,0),Vector2(column+1,1),Vector2(column,1)]
		for i in [0,2,1,0,3,2]:
			var u: float = corners[i].x / 8.0
			var v: float = corners[i].y
			var point := Vector3(PAPER_INNER_EDGE-sin(u*PI)*0.0015,lerpf(-PAPER_HALF_HEIGHT,PAPER_HALF_HEIGHT,v),lerpf(0.0046,0.0117,u))
			surface.set_uv(Vector2(lerpf(0.487,0.515,u),lerpf(0.917,0.06,v)))
			surface.set_bones(PackedInt32Array([0,1,0,0]))
			surface.set_weights(PackedFloat32Array([1.0-u,u,0.0,0.0]))
			surface.add_vertex(point)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/ui/journal/journal.png")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.95
	var mesh := surface.commit()
	mesh.surface_set_material(0,material)
	var node := MeshInstance3D.new()
	node.mesh = save_mesh(mesh,"paper_binding.res")
	node.skin = skin
	node.skeleton = NodePath("../PaperBindingRig")
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	own(node, book, "PaperBinding")
	var animation: Animation = load("res://scenes/ui/journal/journal_presentation_open.tres")
	var cover_path := NodePath("JournalRoot/ModelViewport/SubViewport/World/JournalPose/ModelAlignment/Model/FrontCoverPivot:rotation:y")
	var cover_track := animation.find_track(cover_path,Animation.TYPE_BEZIER)
	assert(cover_track >= 0)
	var binding_path := NodePath("JournalRoot/ModelViewport/SubViewport/World/JournalPose/ModelAlignment/Model/PaperBindingRig:CoverFold")
	for i in range(animation.get_track_count()-1,-1,-1):
		if animation.track_get_path(i) == binding_path: animation.remove_track(i)
	cover_track = animation.find_track(cover_path,Animation.TYPE_BEZIER)
	var track := animation.add_track(Animation.TYPE_ROTATION_3D)
	animation.track_set_path(track,binding_path)
	animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
	animation.track_set_interpolation_loop_wrap(track,false)
	for step in 125:
		var time := step * 0.01
		var angle := animation.bezier_track_interpolate(cover_track,time)
		animation.track_insert_key(track,time,Quaternion(Vector3.UP,angle))
	animation.track_insert_key(track,animation.length,Quaternion(Vector3.UP,-PI))
	assert(ResourceSaver.save(animation,"res://scenes/ui/journal/journal_presentation_open.tres") == OK)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var source: Node3D = load("res://assets/models/leather_journal/scene.gltf").instantiate()
	var alignment := Node3D.new()
	alignment.transform = SOURCE_ALIGNMENT
	root.add_child(alignment)
	alignment.add_child(source)
	await process_frame
	# Fail before saving if a changed import/alignment would leave the cover unsplit.
	var leather: MeshInstance3D = source.find_child("Object_2", true, false)
	var positions: PackedVector3Array = leather.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var bounds := AABB(leather.to_global(positions[0]), Vector3.ZERO)
	for vertex in positions:
		bounds = bounds.expand(leather.to_global(vertex))
	assert(bounds.position.z < -0.018 and bounds.end.z > 0.018, "Source front/back alignment is invalid")
	assert(bounds.size.x > 0.21 and bounds.size.x < 0.23 and bounds.size.y > 0.30 and bounds.size.y < 0.32, "Source book dimensions are invalid")
	book = Node3D.new()
	book.name = "ArticulatedJournal"
	var cover := Node3D.new()
	own(cover,book,"FrontCoverPivot")
	cover.position = HINGE
	for source_mesh: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		# The metal rivet is omitted from the game variant; the supplied source stays intact.
		if source_mesh.name == "Object_4":
			continue
		var xf := source_mesh.global_transform
		var normal_basis := xf.basis.inverse().transposed()
		for sid in source_mesh.mesh.get_surface_count():
			var data := source_mesh.mesh.surface_get_arrays(sid)
			var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			var paper_bounds := AABB(xf * vertices[0],Vector3.ZERO)
			if source_mesh.name == "Object_3":
				for vertex in vertices: paper_bounds = paper_bounds.expand(xf * vertex)
			var indices: PackedInt32Array = data[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for i in vertices.size(): indices.append(i)
			for moving in [false,true]:
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				var triangle_count := 0
				for i in range(0,indices.size(),3):
					var polygon: Array = []
					for index in [indices[i],indices[i+1],indices[i+2]]:
						var point: Vector3 = xf * vertices[index]
						if source_mesh.name == "Object_3":
							# Keep the original page texture/topology, fitted beneath the new reading sheets.
							point.x = remap(point.x,paper_bounds.position.x,paper_bounds.end.x,PAPER_INNER_EDGE+0.002,PAPER_OUTER_EDGE-0.002)
							point.y = remap(point.y,paper_bounds.position.y,paper_bounds.end.y,-PAPER_HALF_HEIGHT+0.002,PAPER_HALF_HEIGHT-0.002)
						elif source_mesh.name == "Object_2" and absf(point.y) < 0.027:
							# Remove the remaining attachment neck from the fore-edge silhouette.
							point.x = minf(point.x,0.105)
						polygon.append({"p": point, "n": (normal_basis * data[Mesh.ARRAY_NORMAL][index]).normalized(),"uv":data[Mesh.ARRAY_TEX_UV][index]})
					if source_mesh.name == "Object_2": polygon = without_tongue(polygon)
					polygon = clip(polygon,moving)
					if polygon.size() >= 3:
						triangle_count += polygon.size()-2
						emit(surface,polygon,HINGE if moving else Vector3.ZERO)
				if triangle_count == 0: continue
				var material = source_mesh.get_active_material(sid).duplicate()
				if material is StandardMaterial3D:
					material.roughness = maxf(material.roughness,0.78)
					material.metallic = 0.0
					if source_mesh.name == "Object_2": material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				var mesh := surface.commit()
				mesh.surface_set_material(0,material)
				var label := str(source_mesh.name)+("Cover" if moving else "Body")
				var node := MeshInstance3D.new()
				node.mesh = save_mesh(mesh,label.to_snake_case()+".res")
				own(node,cover if moving else book,label)
	paper("ReadingPage",book,0.0117,false)
	paper("InnerCover",cover,0.0065,true)
	for i in 3:
		var leaf := Node3D.new()
		own(leaf,cover,"Leaf%dPivot" % i)
		leaf.position = Vector3.ZERO
		# Left leaves travel with the cover; their inner sides face the reader when open.
		paper("Leaf%d" % i,leaf,0.006-i*0.0007,true)
	binding()
	assert(cover.has_node("Object_2Cover"), "Front leather must belong to the moving cover")
	var packed := PackedScene.new()
	assert(packed.pack(book) == OK)
	assert(ResourceSaver.save(packed,OUTPUT+"articulated_journal.tscn") == OK)
	print("SAVED articulated journal with original leather surfaces, hinged cover and three leaves")
	book.free()
	alignment.queue_free()
	quit()
