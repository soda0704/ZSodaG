extends SceneTree
## Offline conversion only. Runtime uses native meshes and editable scenes.

const BASE := "res://assets/models/"
var saved_materials: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func arrays_in_world(instance: MeshInstance3D, surface: int) -> Array:
	var arrays := instance.mesh.surface_get_arrays(surface).duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var transforms: Array[Transform3D] = []
	if instance.skin != null:
		bones = arrays[Mesh.ARRAY_BONES]
		weights = arrays[Mesh.ARRAY_WEIGHTS]
		var rig: Skeleton3D = instance.get_node(instance.skeleton)
		for i in instance.skin.get_bind_count():
			var bone := rig.find_bone(instance.skin.get_bind_name(i))
			if bone<0: bone = instance.skin.get_bind_bone(i)
			transforms.append(rig.global_transform*rig.get_bone_global_rest(bone)*instance.skin.get_bind_pose(i))
	for i in vertices.size():
		var transform := instance.global_transform
		if not transforms.is_empty():
			transform = Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
			var stride := int(bones.size()/vertices.size())
			for j in stride:
				var weight := weights[i*stride+j]
				if weight<=0: continue
				var bind := transforms[bones[i*stride+j]]
				transform.origin += bind.origin*weight
				transform.basis.x += bind.basis.x*weight
				transform.basis.y += bind.basis.y*weight
				transform.basis.z += bind.basis.z*weight
		vertices[i] = transform*vertices[i]
		var normal_basis := transform.basis.inverse().transposed()
		if i<normals.size(): normals[i] = (normal_basis*normals[i]).normalized()
		if tangents.size()>i*4:
			var tangent := (transform.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
			tangents[i*4] = tangent.x
			tangents[i*4+1] = tangent.y
			tangents[i*4+2] = tangent.z
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_BONES] = null
	arrays[Mesh.ARRAY_WEIGHTS] = null
	for attribute in [Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]: arrays[attribute] = null
	return arrays

func bake_source(source: Node3D, folder: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for part: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		for surface in part.mesh.get_surface_count():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays_in_world(part,surface))
			mesh.surface_set_material(mesh.get_surface_count()-1,part.get_active_material(surface))
	return mesh

func normalize_mesh(mesh: ArrayMesh, transform: Transform3D, folder: String) -> ArrayMesh:
	var result := ArrayMesh.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BASE+folder+"/materials"))
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for i in vertices.size():
			vertices[i] = transform*vertices[i]
			normals[i] = (transform.basis.inverse().transposed()*normals[i]).normalized()
			if tangents.size()>i*4:
				var tangent := (transform.basis*Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])).normalized()
				tangents[i*4] = tangent.x
				tangents[i*4+1] = tangent.y
				tangents[i*4+2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material: StandardMaterial3D = mesh.surface_get_material(surface)
		var key := folder+"/"+material.resource_name.validate_filename()
		if not saved_materials.has(key):
			material = material.duplicate()
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.refraction_enabled = false
			material.refraction_texture = null
			if folder=="items/flashlight": material.emission_enabled = false
			var path := BASE+folder+"/materials/"+material.resource_name.validate_filename()+".tres"
			assert(ResourceSaver.save(material,path)==OK)
			material.take_over_path(path)
			saved_materials[key] = material
		result.surface_set_material(surface,saved_materials[key])
	return result

func own(node: Node, parent: Node, scene: Node, label: String) -> void:
	parent.add_child(node)
	node.name = label
	node.owner = scene

func save_scene(scene: Node3D, path: String) -> void:
	var previous_uid := ""
	if FileAccess.file_exists(path):
		var expression := RegEx.new()
		expression.compile('uid="(uid://[^"]+)"')
		var found := expression.search(FileAccess.get_file_as_string(path).get_slice("\n",0))
		if found != null: previous_uid = found.get_string(1)
	var packed := PackedScene.new()
	assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,path)==OK)
	if not previous_uid.is_empty():
		var text := FileAccess.get_file_as_string(path)
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(text.replace("format=3]",'format=3 uid="'+previous_uid+'"]'))
		file.close()
	scene.free()

func save_model(mesh: ArrayMesh, folder: String, label: String) -> Node3D:
	var path := BASE+folder+"/gameplay.res"
	assert(ResourceSaver.save(mesh,path)==OK)
	mesh.take_over_path(path)
	var scene := Node3D.new()
	scene.name = label
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	own(visual,scene,scene,"Body")
	print("ITEM MODEL ",folder," ",mesh.get_aabb()," surfaces=",mesh.get_surface_count())
	return scene

func batteries() -> void:
	var source: Node3D = load(BASE+"items/battery_set/scene.gltf").instantiate()
	root.add_child(source)
	var groups: Array = source.find_children("*","Node3D",true,false).filter(func(node): return node.get_child_count()==2 and node.get_child(0) is MeshInstance3D)
	assert(groups.size()==9)
	var library := MeshLibrary.new()
	for id in groups.size():
		var mesh := bake_source(groups[id],"items/battery_set")
		var box := mesh.get_aabb()
		var factor: float = (0.057 if String(groups[id].name).begins_with("AAA") else 0.065)/box.size.y
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*factor),-box.get_center()*factor)
		mesh = normalize_mesh(mesh,transform,"items/battery_set")
		var path := BASE+"items/battery_set/variant_%d.res"%id
		assert(ResourceSaver.save(mesh,path)==OK)
		mesh.take_over_path(path)
		library.create_item(id)
		library.set_item_name(id,groups[id].name)
		library.set_item_mesh(id,mesh)
	assert(ResourceSaver.save(library,BASE+"items/battery_set/variants.tres")==OK)
	source.free()

func run() -> void:
	for folder in ["weapons/g17","weapons/m4a1","items/flashlight","items/fuel_can","items/duct_tape","generator"]:
		var source: Node3D = load(BASE+folder+"/scene.gltf").instantiate()
		root.add_child(source)
		var mesh := bake_source(source,folder)
		var box := mesh.get_aabb()
		var turn := Basis(Vector3.UP,PI*0.5)
		var factor := 1.0
		var pivot := Vector3.ZERO
		var path := ""
		if folder.begins_with("weapons"):
			factor = (0.225 if folder=="weapons/g17" else 0.829)/box.size.x
			pivot = Vector3(-2.5,-0.5,box.get_center().z) if folder=="weapons/g17" else Vector3(-26,0,box.get_center().z)
			path = "res://scenes/objects/items/"+("pistol_model.tscn" if folder=="weapons/g17" else "m4a1_model.tscn")
		elif folder in ["items/flashlight","items/duct_tape"]:
			var part: MeshInstance3D = source.find_children("*","MeshInstance3D",true,false)[0]
			var local_box := part.mesh.get_aabb()
			factor = 0.24/local_box.size.z if folder=="items/flashlight" else 1.0
			pivot = Vector3(local_box.get_center().x,local_box.get_center().y,local_box.end.z-0.07/factor) if folder=="items/flashlight" else local_box.get_center()
			var local_transform := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*factor),-pivot*factor)*part.global_transform.affine_inverse()
			mesh = normalize_mesh(mesh,local_transform,folder)
			path = "res://scenes/objects/equipment/flashlight_model.tscn" if folder=="items/flashlight" else "res://scenes/objects/items/tape_model.tscn"
		elif folder=="items/fuel_can":
			factor = 0.60/box.size.y
			pivot = box.get_center()
			path = "res://scenes/objects/items/fuel_can_model.tscn"
		else:
			factor = 3.0/box.size.y
			pivot = Vector3(box.get_center().x,box.position.y,box.get_center().z)
			path = "res://scenes/art/base/technical/generator_model.tscn"
		if folder not in ["items/flashlight","items/duct_tape"]: mesh = normalize_mesh(mesh,Transform3D(turn.scaled(Vector3.ONE*factor),-(turn*pivot)*factor),folder)
		var scene := save_model(mesh,folder,"ItemModel")
		if folder.begins_with("weapons"):
			var muzzle := Marker3D.new()
			muzzle.position = Vector3(0,0.055 if folder=="weapons/g17" else 0.064,mesh.get_aabb().position.z)
			own(muzzle,scene,scene,"Muzzle")
		elif folder=="items/flashlight":
			var lens := MeshInstance3D.new()
			var disk := CylinderMesh.new()
			disk.top_radius = 0.0195
			disk.bottom_radius = 0.0195
			disk.height = 0.001
			disk.radial_segments = 24
			var lens_material := StandardMaterial3D.new()
			lens_material.albedo_color = Color(0.30,0.32,0.33)
			lens_material.roughness = 0.22
			disk.material = lens_material
			lens.mesh = disk
			lens.position.z = -0.166
			lens.rotation.x = PI*0.5
			own(lens,scene,scene,"Lens")
		save_scene(scene,path)
		source.free()
	batteries()
	print("ITEM MODELS AUTHORED")
	quit()
