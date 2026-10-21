extends SceneTree
## Prepare the complete kit without changing any game level or source pivot.
const ASSETS := "res://assets/models/modular_scifi_megakit/"
const OBJECTS := "res://scenes/objects/base/modular_scifi/"
const CATEGORIES := ["walls", "floors", "ceilings", "doors", "columns", "props", "decals", "aliens"]
var materials: Dictionary = {}
var entries: Array[Dictionary] = []
var failed := false
var curated_models: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func save_resource(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var result := ResourceSaver.save(resource, path, ResourceSaver.FLAG_COMPRESS)
	if result != OK:
		push_error("Cannot save %s: %s" % [path, error_string(result)])
		failed = true
	else:
		resource.take_over_path(path)

func material_signature(material: StandardMaterial3D) -> String:
	var values: Dictionary = {}
	for property: Dictionary in material.get_property_list():
		var name := str(property.name)
		# AO and filtering were intentionally improved on the curated materials.
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or name.begins_with("resource_") or name.begins_with("metadata/") or name.begins_with("ao_") or name == "texture_filter":
			continue
		var value: Variant = material.get(name)
		values[name] = value.resource_path if value is Resource else var_to_str(value)
	return JSON.stringify(values).md5_text()

func prepare_material(source: StandardMaterial3D) -> StandardMaterial3D:
	var signature := material_signature(source)
	var key := source.resource_name + ":" + signature
	if materials.has(key):
		return materials[key]
	var basename := source.resource_name.to_snake_case()
	var path := ASSETS + "materials/" + basename + ".tres"
	# Existing curated materials contain project-specific atlas and glass settings.
	if ResourceLoader.exists(path):
		var existing := load(path) as StandardMaterial3D
		if source.resource_name == "M_Glass" or material_signature(existing) == signature:
			materials[key] = existing
			return existing
		# The archive reuses material names for different textures and alpha modes.
		path = ASSETS + "materials/" + basename + "_" + signature.left(8) + ".tres"
		if ResourceLoader.exists(path):
			materials[key] = load(path)
			return materials[key]
	var material := source.duplicate() as StandardMaterial3D
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if source.resource_name == "M_Glass":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color.a = 0.18
		material.roughness = 0.16
		material.metallic = 0.0
	save_resource(material, path)
	materials[key] = material
	return material

func mesh_transform(part: Node3D) -> Transform3D:
	var result := part.transform
	var parent := part.get_parent()
	while parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result

func import_model(record: Dictionary) -> Dictionary:
	var path := "res://" + str(record.path)
	if path.ends_with(".gltf"):
		var options := ConfigFile.new()
		if options.load(path + ".import") != OK or bool(options.get_value("params", "meshes/generate_lods", true)):
			push_error("Reimport with Generate LODs disabled: " + path)
			failed = true
			return {}
	var resource := load(path)
	var instance: Node3D
	if resource is PackedScene:
		instance = resource.instantiate() as Node3D
	elif resource is Mesh:
		instance = MeshInstance3D.new()
		(instance as MeshInstance3D).mesh = resource
	else:
		push_error("Cannot load model: " + path)
		failed = true
		return {}
	var parts := instance.find_children("*", "MeshInstance3D", true, false)
	if instance is MeshInstance3D:
		parts.push_front(instance)
	if parts.is_empty():
		push_error("No mesh in " + path)
		failed = true
		instance.free()
		return {}
	var bounds := AABB()
	var prepared: Array[Dictionary] = []
	var collide: bool = not bool(record.animated) and record.category != "decals"
	for index in parts.size():
		var part := parts[index] as MeshInstance3D
		var transform := mesh_transform(part)
		var part_bounds: AABB = transform * part.mesh.get_aabb()
		bounds = part_bounds if index == 0 else bounds.merge(part_bounds)
		if record.animated:
			continue
		var key := str(record.name).to_snake_case()
		if parts.size() > 1:
			key += "_part_%d" % index
		var mesh_path := ASSETS + "meshes/" + key + ".res"
		var mesh: ArrayMesh
		var refresh: bool = OS.get_cmdline_user_args().has("--refresh-library-resources") and not curated_models.has(str(record.name))
		if ResourceLoader.exists(mesh_path) and not refresh:
			mesh = load(mesh_path) as ArrayMesh
		else:
			mesh = part.mesh.duplicate() as ArrayMesh
			for surface in mesh.get_surface_count():
				var material := part.get_active_material(surface) as StandardMaterial3D
				if material != null:
					mesh.surface_set_material(surface, prepare_material(material))
			save_resource(mesh, mesh_path)
		var shape: ConcavePolygonShape3D
		if collide:
			var shape_path := ASSETS + "collisions/" + key + ".res"
			if ResourceLoader.exists(shape_path):
				shape = load(shape_path) as ConcavePolygonShape3D
			else:
				shape = mesh.create_trimesh_shape()
				shape.backface_collision = true
				save_resource(shape, shape_path)
		prepared.append({"mesh": mesh, "shape": shape, "transform": transform})
	var animations: Array[String] = []
	for player: AnimationPlayer in instance.find_children("*", "AnimationPlayer", true, false):
		for animation in player.get_animation_list():
			if animation != "RESET":
				animations.append(str(animation))
	instance.free()
	return {"record": record, "source": resource, "parts": prepared, "bounds": bounds,
		"collidable": collide, "animations": animations}

func save_object(data: Dictionary, category: String, filename: String, ceiling := false) -> void:
	var object := Node3D.new()
	object.name = filename.to_pascal_case()
	object.editor_description = "%s — Quaternius, CC0. Original scale and modular pivot." % data.record.name
	object.set_meta("quaternius_source_model", data.record.name)
	object.set_meta("source_path", "res://" + str(data.record.path))
	object.set_meta("library_category", category)
	var visual := Node3D.new()
	visual.name = "Visual"
	object.add_child(visual)
	visual.owner = object
	var placement := Transform3D.IDENTITY
	if ceiling:
		placement.basis = Basis(Vector3.RIGHT, PI)
		var rotated: AABB = placement * data.bounds
		placement.origin.y = -rotated.position.y
		object.editor_description = "Ceiling variant of %s. Visible underside at Y=0; thickness above it." % data.record.name
	visual.transform = placement
	if data.record.animated:
		# Keep the imported scene boundary: bones and animation paths stay intact.
		var imported := (data.source as PackedScene).instantiate()
		visual.add_child(imported)
		imported.owner = object
		object.set_meta("available_animations", data.animations)
	else:
		var body: StaticBody3D
		if data.collidable:
			body = StaticBody3D.new()
			body.name = "StaticCollision"
			body.collision_layer = 1
			body.collision_mask = 0
			object.add_child(body)
			body.owner = object
		for index in data.parts.size():
			var prepared: Dictionary = data.parts[index]
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh%d" % index
			mesh.mesh = prepared.mesh
			mesh.transform = prepared.transform
			mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			visual.add_child(mesh)
			mesh.owner = object
			if body != null:
				var collision := CollisionShape3D.new()
				collision.name = "Shape%d" % index
				collision.shape = prepared.shape
				collision.transform = placement * prepared.transform
				body.add_child(collision)
				collision.owner = object
	var path := OBJECTS + category + "/" + filename + ".tscn"
	var scene := PackedScene.new()
	if scene.pack(object) != OK:
		failed = true
		push_error("Cannot pack " + path)
	else:
		save_resource(scene, path)
	var bounds: AABB = placement * data.bounds
	entries.append({"name": filename, "model": data.record.name, "category": category,
		"scene": path, "animated": data.record.animated, "animations": data.animations,
		"collidable": data.collidable, "ceiling_variant": ceiling,
		"bounds_position": [bounds.position.x, bounds.position.y, bounds.position.z],
		"bounds_size": [bounds.size.x, bounds.size.y, bounds.size.z]})
	object.free()

func make_catalog(category: String) -> void:
	var catalog := Node3D.new()
	catalog.name = (category + "_catalog").to_pascal_case()
	catalog.editor_description = "Library preview. Drag individual scenes from the category folder into your level."
	var index := 0
	for entry in entries:
		if entry.category != category:
			continue
		var object := load(str(entry.scene)).instantiate() as Node3D
		var source_position: Array = entry.bounds_position
		var size: Array = entry.bounds_size
		object.position = Vector3((index % 5) * 10.0 - float(source_position[0]) - float(size[0]) / 2.0,
			-float(source_position[1]), -floori(index / 5.0) * 12.0 - float(source_position[2]) - float(size[2]) / 2.0)
		catalog.add_child(object)
		object.owner = catalog
		var label := Label3D.new()
		label.name = "Label%d" % index
		label.text = str(entry.model) + (" (ceiling)" if entry.ceiling_variant else "")
		label.font_size = 40
		label.pixel_size = 0.008
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3((index % 5) * 10.0, 0.15, -floori(index / 5.0) * 12.0 + 4.2)
		catalog.add_child(label)
		label.owner = catalog
		index += 1
	var scene := PackedScene.new()
	if scene.pack(catalog) != OK:
		failed = true
	else:
		save_resource(scene, OBJECTS + "catalogs/" + category + ".tscn")
	catalog.free()

func run() -> void:
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "library.json"))
	var selection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "selection.json"))
	for record: Dictionary in selection.models:
		curated_models[str(record.name)] = true
	for record: Dictionary in library.models:
		var data := import_model(record)
		if data.is_empty():
			continue
		save_object(data, str(record.category), str(record.name).to_snake_case())
		# Only thin, flat platform tiles have a usable inverted ceiling surface.
		if record.category == "floors" and str(record.name).begins_with("Platform_") and data.bounds.size.y < 0.3:
			save_object(data, "ceilings", "ceiling_" + str(record.name).trim_prefix("Platform_").to_snake_case(), true)
	# Project derivatives live separately so reimporting the original ZIP preserves them.
	var derived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "derived_models.json"))
	for record: Dictionary in derived.models:
		var data := import_model(record)
		if not data.is_empty():
			save_object(data, str(record.category), str(record.name).to_snake_case())
	if not failed:
		for category: String in CATEGORIES:
			make_catalog(category)
		var manifest := FileAccess.open(OBJECTS + "library_index.json", FileAccess.WRITE)
		manifest.store_string(JSON.stringify({"source_models": library.models.size(), "objects": entries}, "\t") + "\n")
		manifest.close()
	print("PREPARED LIBRARY: %d source models, %d objects" % [library.models.size(), entries.size()])
	entries.clear()
	materials.clear()
	for frame in 8:
		await process_frame
	for player: AudioStreamPlayer in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
		player.stream = null
	await create_timer(0.1).timeout
	quit(1 if failed else 0)
