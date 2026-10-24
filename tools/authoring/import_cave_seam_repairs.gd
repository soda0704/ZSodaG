extends SceneTree
## Offline mesh editing only. The game loads saved native resources.
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/authoring/cave_shell_repairs.json"))
	var cave: Node3D = load("res://scenes/levels/Cave_Day7.tscn").instantiate()
	if cave.has_node("GeologySeamRepairs"):
		push_error("Repairs already exist; edit the saved mesh rather than duplicating it")
		quit(1)
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	for hole in data.holes:
		var offset := vertices.size()
		for point in hole.vertices:
			vertices.append(Vector3(point[0], point[1], point[2]))
			normals.append(Vector3.ZERO)
			colors.append(Color(0, 0, 0, 1))
		for face in hole.faces:
			var a: int = offset + int(face[0])
			var b: int = offset + int(face[1])
			var c: int = offset + int(face[2])
			indices.append_array(PackedInt32Array([a, b, c]))
			var normal := -(vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			for id in [a, b, c]: normals[id] += normal
	for i in normals.size(): normals[i] = normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, load("res://assets/environments/cave/sculpted/limestone.tres"))
	assert(ResourceSaver.save(mesh, "res://assets/environments/cave/sculpted/seam_repairs.res", ResourceSaver.FLAG_COMPRESS) == OK)
	mesh.take_over_path("res://assets/environments/cave/sculpted/seam_repairs.res")
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	assert(ResourceSaver.save(shape, "res://assets/environments/cave/sculpted/seam_repairs_collision.res", ResourceSaver.FLAG_COMPRESS) == OK)
	shape.take_over_path("res://assets/environments/cave/sculpted/seam_repairs_collision.res")
	var body := StaticBody3D.new()
	body.name = "GeologySeamRepairs"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("footstep_surface", "concrete")
	cave.add_child(body)
	body.owner = cave
	var view := MeshInstance3D.new()
	view.name = "Bedrock"
	view.mesh = mesh
	body.add_child(view)
	view.owner = cave
	var collision := CollisionShape3D.new()
	collision.name = "SolidRock"
	collision.shape = shape
	body.add_child(collision)
	collision.owner = cave
	cave.set_meta("triangle_count", int(cave.get_meta("triangle_count", 0)) + int(data.triangles))
	var packed := PackedScene.new()
	assert(packed.pack(cave) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/levels/Cave_Day7.tscn") == OK)
	cave.free()
	print("SAVED CAVE SEAM REPAIRS ", data.holes.size(), " holes; ", data.triangles, " triangles")
	quit()
