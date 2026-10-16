extends SceneTree
## Offline preparation of the curated Quaternius kit. No level is modified.
const ASSETS := "res://assets/models/modular_scifi_megakit/"
const OBJECTS := "res://scenes/objects/base/modular_scifi/"
var meshes: Dictionary = {}
var shapes: Dictionary = {}
var materials: Dictionary = {}
var entries: Array = []
var failed := false

func _initialize() -> void:
	run.call_deferred()

func save_resource(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var result := ResourceSaver.save(resource, path, ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		push_error("Cannot save %s: %s" % [path, error_string(result)])
		failed = true
	resource.take_over_path(path)

func prepare_material(source: StandardMaterial3D) -> StandardMaterial3D:
	var key := source.resource_name
	if materials.has(key):
		return materials[key]
	var material := source.duplicate() as StandardMaterial3D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# The Standard glTF exports its glass as opaque. Make the observation
	# window usable in Godot while keeping the author's glass colour.
	if key == "M_Glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.18
		material.roughness = 0.16
		material.metallic = 0.0
	save_resource(material, ASSETS + "materials/" + key.to_snake_case() + ".tres")
	materials[key] = material
	return material

func prepare_model(record: Dictionary) -> void:
	# Keep atlas UVs intact: automatic LODs smear the kit's flat panels.
	var import_options := ConfigFile.new()
	if import_options.load("res://" + str(record.path) + ".import") != OK or bool(import_options.get_value("params", "meshes/generate_lods", true)):
		push_error("Disable Generate LODs and reimport: " + str(record.path))
		failed = true
		return
	var source := load("res://" + str(record.path)) as PackedScene
	if source == null:
		push_error("Missing model: " + str(record.path))
		failed = true
		return
	var instance := source.instantiate() as Node3D
	var parts := instance.find_children("*", "MeshInstance3D", true, false)
	if instance is MeshInstance3D:
		parts.push_front(instance)
	if parts.size() != 1:
		push_error("Unexpected mesh hierarchy: " + str(record.name))
		failed = true
		instance.free()
		return
	var part := parts[0] as MeshInstance3D
	var transform := part.transform
	var parent := part.get_parent()
	while parent is Node3D:
		transform = parent.transform * transform
		parent = parent.get_parent()
	if not transform.is_equal_approx(Transform3D.IDENTITY):
		push_error("Unexpected model transform: " + str(record.name))
		failed = true
		instance.free()
		return
	var mesh := part.mesh.duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as StandardMaterial3D
		if material != null:
			mesh.surface_set_material(surface, prepare_material(material))
	var key := str(record.name)
	save_resource(mesh, ASSETS + "meshes/" + key.to_snake_case() + ".res")
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	save_resource(shape, ASSETS + "collisions/" + key.to_snake_case() + ".res")
	meshes[key] = mesh
	shapes[key] = shape
	instance.free()

func make_object(definition: Dictionary) -> Node3D:
	var object := Node3D.new()
	object.name = str(definition.name).to_pascal_case()
	object.editor_description = str(definition.description)
	object.set_meta("quaternius_source_models", definition.sources)
	object.set_meta("recommended_zone", definition.zone)
	var visual := Node3D.new()
	visual.name = "Visual"
	object.add_child(visual)
	visual.owner = object
	var body := StaticBody3D.new()
	body.name = "StaticCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	object.add_child(body)
	body.owner = object
	var basis := Basis.IDENTITY
	var anchor := Vector3.ZERO
	if definition.mount in ["wall", "wall_top", "wall_full"]:
		basis = Basis(Vector3.UP, -PI / 2.0)
		anchor = Vector3(-2, 5 if definition.mount == "wall_top" else 0, 0)
		if definition.mount == "wall_full":
			basis = basis.scaled(Vector3(1, 1.1, 1))
	elif definition.mount == "ceiling":
		basis = Basis(Vector3.RIGHT, PI)
	var transform := Transform3D(basis, -(basis * anchor))
	visual.transform = transform
	for source_name: String in definition.sources:
		var model := MeshInstance3D.new()
		model.name = source_name
		model.mesh = meshes[source_name]
		model.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		visual.add_child(model)
		model.owner = object
		var collision := CollisionShape3D.new()
		collision.name = source_name
		collision.shape = shapes[source_name]
		collision.transform = transform
		body.add_child(collision)
		collision.owner = object
	return object

func save_scene(node: Node3D, path: String) -> void:
	var scene := PackedScene.new()
	if scene.pack(node) != OK:
		failed = true
		push_error("Cannot pack " + path)
		return
	save_resource(scene, path)

func make_catalog(category: String) -> void:
	var catalog := Node3D.new()
	catalog.name = (category + "_catalog").to_pascal_case()
	catalog.editor_description = "Каталог объектов; игровые уровни не заменяет. Выбирайте отдельные сцены из соседних папок."
	var index := 0
	for entry: Dictionary in entries:
		if entry.category != category:
			continue
		var object := load(OBJECTS + category + "/" + str(entry.name) + ".tscn").instantiate() as Node3D
		object.position = Vector3((index % 5) * 8.0, 0, -floori(index / 5.0) * 10.0)
		catalog.add_child(object)
		object.owner = catalog
		var label := Label3D.new()
		label.name = "Label%d" % index
		label.text = str(entry.name).replace("_", " ")
		label.font_size = 56
		label.pixel_size = 0.008
		label.modulate = Color(0.9, 0.96, 1.0)
		label.outline_size = 8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = object.position + Vector3(0, 0.15, 2.7)
		catalog.add_child(label)
		label.owner = catalog
		index += 1
	save_scene(catalog, OBJECTS + "catalogs/" + category + ".tscn")
	catalog.free()

func run() -> void:
	var selection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "selection.json"))
	entries = selection.objects
	for record: Dictionary in selection.models:
		prepare_model(record)
	if failed:
		quit(1)
		return
	if not OS.get_cmdline_user_args().has("--resources-only"):
		for entry: Dictionary in entries:
			var object := make_object(entry)
			save_scene(object, OBJECTS + str(entry.category) + "/" + str(entry.name) + ".tscn")
			object.free()
		for category in ["walls", "floors", "ceilings"]:
			make_catalog(category)
	print("PREPARED SCIFI OBJECTS ", entries.size(), " MODELS ", meshes.size(), " SHARED MATERIALS ", materials.size())
	meshes.clear()
	shapes.clear()
	materials.clear()
	for frame in 8:
		await process_frame
	# Menu music starts deferred, so release it after the startup frames.
	for player: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	quit(1 if failed else 0)
