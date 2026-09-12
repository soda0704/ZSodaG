extends RefCounted

static func build(kind: StringName) -> Node3D:
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("566068")
	metal.metallic = 0.75
	metal.roughness = 0.45
	if kind == &"tape":
		var ring := TorusMesh.new()
		ring.inner_radius = 0.038
		ring.outer_radius = 0.075
		ring.material = metal
		var mesh := MeshInstance3D.new()
		mesh.mesh = ring
		root.add_child(mesh)
	else:
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

static func build_mount() -> Node3D:
	var root := Node3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.027
	cylinder.bottom_radius = 0.025
	cylinder.height = 0.17
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("22292c")
	metal.metallic = 0.65
	cylinder.material = metal
	var barrel := MeshInstance3D.new()
	barrel.mesh = cylinder
	barrel.rotation.x = PI / 2.0
	root.add_child(barrel)
	for z in [-0.045, 0.045]:
		var tape := MeshInstance3D.new()
		var band := BoxMesh.new()
		band.size = Vector3(0.115, 0.063, 0.023)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("62666a")
		material.roughness = 0.95
		band.material = material
		tape.mesh = band
		tape.position = Vector3(-0.038, 0, z)
		root.add_child(tape)
	return root
