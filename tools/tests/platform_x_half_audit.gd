extends SceneTree
## Check that cutting the tile preserves its pattern and removes the other half's collision.
const ASSETS := "res://assets/models/modular_scifi_megakit/"
const LIBRARY := "res://scenes/objects/base/modular_scifi/"
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func require(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func area(mesh: Mesh) -> float:
	var faces := mesh.get_faces()
	var total := 0.0
	for index in range(0, faces.size(), 3):
		total += (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length() * 0.5
	return total

func run() -> void:
	var original := load(ASSETS + "meshes/platform_x.res") as ArrayMesh
	var tile := load(LIBRARY + "floors/platform_x_half.tscn").instantiate() as Node3D
	root.add_child(tile)
	var mesh := (tile.get_node("Visual/Mesh0") as MeshInstance3D).mesh
	var shape := (tile.get_node("StaticCollision/Shape0") as CollisionShape3D).shape as ConcavePolygonShape3D
	var bounds := mesh.get_aabb()
	require(bounds.position.is_equal_approx(original.get_aabb().position), "Changed original pivot or floor height")
	require(is_equal_approx(bounds.size.x, 2.0) and is_equal_approx(bounds.size.z, 4.0), "Half tile must be 2x4")
	require(is_equal_approx(area(mesh) * 2.0, area(original)), "Mesh is not exactly half the original area")
	require(mesh.surface_get_material(0) == original.surface_get_material(0), "Half tile lost its shared floor material")
	require(shape.get_faces() == mesh.get_faces(), "Collision does not match cut geometry")
	var before := original.surface_get_arrays(0)
	var after := mesh.surface_get_arrays(0)
	for index in after[Mesh.ARRAY_VERTEX].size():
		var found := false
		for old in before[Mesh.ARRAY_VERTEX].size():
			if after[Mesh.ARRAY_VERTEX][index].distance_to(before[Mesh.ARRAY_VERTEX][old]) < 0.0001 and after[Mesh.ARRAY_TEX_UV][index].distance_to(before[Mesh.ARRAY_TEX_UV][old]) < 0.0001:
				found = true
				break
		require(found, "A vertex or atlas UV was stretched")
	await physics_frame
	await physics_frame
	for x in [-1.75, -1.0, -0.25, -0.001, 0.001, 0.25, 1.0, 1.75]:
		for z in [-1.75, -0.25, 0.25, 1.75]:
			var query := PhysicsRayQueryParameters3D.create(Vector3(x, 1, z), Vector3(x, -1, z), 1)
			var hit := root.world_3d.direct_space_state.intersect_ray(query)
			require(hit.is_empty() == (x > 0.0), "Wrong floor collision at (%s, %s)" % [x, z])
	var catalog := load(LIBRARY + "catalogs/floors.tscn").instantiate() as Node3D
	require(catalog.get_node_or_null("PlatformXHalf") != null, "Half tile missing from floor catalog")
	catalog.free()
	tile.free()
	print("HALF TILE AUDIT: size, area, UVs, material, collision, 32 physics rays, catalog; failures=", failures)
	quit(0 if failures == 0 else 1)
