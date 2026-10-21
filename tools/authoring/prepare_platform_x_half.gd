extends "res://tools/authoring/prepare_modular_scifi_library.gd"
## Prepare only the new half tile; never regenerate existing objects or game levels.

func run() -> void:
	var derived: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS + "derived_models.json"))
	var record: Dictionary = derived.models[0]
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file("res://" + str(record.path), state)
	if result != OK:
		push_error("Cannot read half tile: " + error_string(result))
		quit(1)
		return
	var source := document.generate_scene(state)
	var part := source.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var mesh := part.mesh.duplicate() as ArrayMesh
	var original := load(ASSETS + "meshes/platform_x.res") as ArrayMesh
	# Share the same curated material as the existing floor tile.
	mesh.surface_set_material(0, original.surface_get_material(0))
	save_resource(mesh, ASSETS + "meshes/platform_x_half.res")
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	save_resource(shape, ASSETS + "collisions/platform_x_half.res")
	save_object({"record": record, "parts": [{"mesh": mesh, "shape": shape,
		"transform": Transform3D.IDENTITY}], "bounds": mesh.get_aabb(),
		"collidable": true, "animations": []}, "floors", "platform_x_half")
	source.free()
	if not failed:
		var path := OBJECTS + "library_index.json"
		var text := FileAccess.get_file_as_string(path)
		if not text.contains('"name": "platform_x_half"'):
			# Preserve the original numeric precision and formatting of every other entry.
			var entry := "\t\t" + JSON.stringify(entries[0], "\t").replace("\n", "\n\t\t")
			text = text.replace("\n\t],", ",\n" + entry + "\n\t],")
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(text)
			file.close()
	print("PREPARED HALF TILE: ", mesh.get_aabb())
	entries.clear()
	for frame in 8:
		await process_frame
	quit(1 if failed else 0)
