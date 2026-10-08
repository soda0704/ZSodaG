extends RefCounted

static func build(kind: StringName) -> Node3D:
	if kind==&"tape": return preload("res://scenes/objects/items/tape_model.tscn").instantiate()
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("566068")
	metal.metallic = 0.75
	metal.roughness = 0.45
	for spec in [[Vector3(0, 0, 0), Vector3(0.024, 0.024, 0.58), 0.0], [Vector3(0, 0.035, -0.31), Vector3(0.025, 0.10, 0.025), -0.5], [Vector3(0, 0.075, -0.28), Vector3(0.04, 0.012, 0.09), 0.0], [Vector3(0, 0, 0.32), Vector3(0.04, 0.008, 0.08), 0.0]]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[1]
		box.material = metal
		mesh.mesh = box
		mesh.position = spec[0]
		mesh.rotation.x = spec[2]
		root.add_child(mesh)
	return root
