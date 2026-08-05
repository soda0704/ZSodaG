extends SceneTree

const SOURCE_SCENE := "res://assets/characters/prototype/scene.gltf"
const OUTPUT_MESH := "res://assets/characters/prototype/character_visual.res"


func _init() -> void:
	call_deferred("build")


func build() -> void:
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		push_error("Could not load prototype character source")
		quit(1)
		return

	var source_root := packed.instantiate()
	var source_mesh := find_mesh(source_root)
	if source_mesh == null or source_mesh.mesh == null:
		push_error("No MeshInstance3D found in prototype character source")
		quit(1)
		return

	var optimized := ArrayMesh.new()
	for surface_index in source_mesh.mesh.get_surface_count():
		var arrays := source_mesh.mesh.surface_get_arrays(surface_index)
		# The supplied export has 320 joints but no animations. Keeping bone and
		# weight streams would cost memory without changing the static prototype.
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		optimized.add_surface_from_arrays(
			source_mesh.mesh.surface_get_primitive_type(surface_index),
			arrays
		)
		optimized.surface_set_material(
			surface_index,
			source_mesh.mesh.surface_get_material(surface_index)
		)

	var save_result := ResourceSaver.save(optimized, OUTPUT_MESH)
	if save_result != OK:
		push_error("Could not save optimized character mesh: %s" % save_result)
		quit(1)
		return

	print(
		"Saved static prototype character: vertices=",
		optimized.surface_get_array_len(0),
		" aabb=",
		optimized.get_aabb()
	)
	print("Runtime mesh dependencies: ", ResourceLoader.get_dependencies(OUTPUT_MESH))
	source_root.free()
	await process_frame
	quit()


func find_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := find_mesh(child)
		if found != null:
			return found
	return null
