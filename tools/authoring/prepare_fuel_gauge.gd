extends SceneTree
## Offline authoring: a native scene with the fuel dial on the original surface.
## Run with Godot --headless --path . --script res://tools/authoring/prepare_fuel_gauge.gd
func _initialize() -> void:
	var model: Node3D = load("res://assets/models/electrical/pressure_gauge/scene.gltf").instantiate()
	model.name = "FuelGauge"
	model.scene_file_path = ""
	var dial: MeshInstance3D = model.get_node("Sketchfab_model/root/GLTF_SceneRootNode/Back_0/Object_5")
	var material := StandardMaterial3D.new()
	material.resource_name = "Fuel dial 0–60 L"
	material.albedo_texture = load("res://assets/models/electrical/pressure_gauge/fuel_dial.svg")
	material.roughness = 0.65
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Replace the mesh surface too: there is no pressure dial fallback in this prefab.
	dial.mesh = dial.mesh.duplicate()
	dial.mesh.surface_set_material(0, material)
	dial.material_override = material
	for child in model.find_children("*", "Node", true, false):
		child.scene_file_path = ""
		child.owner = model
	var scene := PackedScene.new()
	assert(scene.pack(model) == OK)
	assert(ResourceSaver.save(scene, "res://assets/models/electrical/pressure_gauge/fuel_gauge.tscn") == OK)
	model.free()
	print("Authored native fuel gauge; pressure scale replaced on its original mesh surface.")
	print("PIPE ROTATION FOLLOW = ", CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW)
	quit()
