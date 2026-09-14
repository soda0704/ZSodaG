extends RefCounted

static func build(kind: StringName) -> Node3D:
	var root := Node3D.new()
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("566068")
	metal.metallic = 0.75
	metal.roughness = 0.45
	if kind == &"tape":
		metal.albedo_color = Color("858b88")
		metal.metallic = 0.15
		metal.roughness = 0.85
		var cardboard := StandardMaterial3D.new()
		cardboard.albedo_color = Color("b7a07a")
		cardboard.roughness = 1.0
		_add_roll(root, 0.078, 0.037, 0.05, metal)
		_add_roll(root, 0.038, 0.030, 0.052, cardboard)
		var tab := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(0.035, 0.003, 0.05)
		strip.material = metal
		tab.mesh = strip
		tab.position = Vector3(0.085, -0.023, 0)
		tab.rotation.z = -0.12
		root.add_child(tab)
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

static func _add_roll(root: Node3D, outer: float, inner: float, height: float, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	surface.set_material(material)
	for index in 16:
		var a := TAU * index / 16.0
		var b := TAU * (index + 1) / 16.0
		var oa := Vector3(cos(a) * outer, 0, sin(a) * outer)
		var ob := Vector3(cos(b) * outer, 0, sin(b) * outer)
		var ia := Vector3(cos(a) * inner, 0, sin(a) * inner)
		var ib := Vector3(cos(b) * inner, 0, sin(b) * inner)
		var up := Vector3.UP * height * 0.5
		for quad in [[oa-up, ob-up, ob+up, oa+up], [ib-up, ia-up, ia+up, ib+up], [oa+up, ob+up, ib+up, ia+up], [ia-up, ib-up, ob-up, oa-up]]:
			for vertex in [0, 1, 2, 0, 2, 3]:
				surface.add_vertex(quad[vertex])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	root.add_child(mesh)

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
