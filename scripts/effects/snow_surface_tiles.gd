extends RefCounted
## Reuses one fine grid for nearby deformed tiles. Terrain3D supplies the material and height maps.

const SnowDeformation := preload("res://scripts/effects/snow_deformation.gd")
const SnowDriftProfile := preload("res://scripts/effects/snow_drift_profile.gd")
const TILE_SIZE := SnowDeformation.TILE_METRES
const MAX_VISIBLE_TILES := 4
const VISIBLE_RADIUS := 22.0

var _grid := PlaneMesh.new()
var _instances: Array[MeshInstance3D] = []
var _patches: Dictionary[Vector2, MeshInstance3D] = {}
var _update_at := 0.0
var _visible_count := 0

func _init() -> void:
	_grid.size = Vector2.ONE * TILE_SIZE
	_grid.subdivide_width = 95
	_grid.subdivide_depth = 95

func update(host: Node3D, terrain: Terrain3D, origins: PackedVector2Array, clock: float) -> void:
	if clock < _update_at:
		return
	_update_at = clock + 0.10
	var camera := host.get_viewport().get_camera_3d()
	if camera == null:
		return
	var camera_xz := Vector2(camera.global_position.x, camera.global_position.z)
	var candidates: Array[Vector2] = []
	for slot in origins.size():
		var distance := camera_xz.distance_squared_to(origins[slot] + Vector2.ONE * TILE_SIZE * 0.5)
		if distance <= VISIBLE_RADIUS * VISIBLE_RADIUS:
			candidates.append(Vector2(distance, slot))
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var count := mini(MAX_VISIBLE_TILES, candidates.size())
	var visible_origins := PackedVector2Array()
	visible_origins.resize(MAX_VISIBLE_TILES)
	for index in count:
		visible_origins[index] = origins[int(candidates[index].y)]
	var unchanged := count == _visible_count
	for index in count:
		unchanged = unchanged and _patches.has(visible_origins[index])
	if unchanged:
		return
	var selected := visible_origins.slice(0, count)
	for origin in _patches.keys():
		if selected.has(origin):
			continue
		_patches[origin].hide()
		_patches.erase(origin)
	for index in count:
		var origin := visible_origins[index]
		if not _patches.has(origin):
			var patch := _acquire_patch(host, terrain)
			var center := origin + Vector2.ONE * TILE_SIZE * 0.5
			patch.position = Vector3(center.x, 0.0, center.y)
			_patches[origin] = patch
		var patch := _patches[origin]
		# Only outside edges transition to Terrain3D. Adjacent fine grids already meet.
		var coarse_edges := Vector4.ONE
		for neighbor in count:
			var delta := (visible_origins[neighbor] - origin) / TILE_SIZE
			match delta:
				Vector2.LEFT: coarse_edges.x = 0.0
				Vector2.RIGHT: coarse_edges.y = 0.0
				Vector2.UP: coarse_edges.z = 0.0
				Vector2.DOWN: coarse_edges.w = 0.0
		RenderingServer.instance_geometry_set_shader_parameter(patch.get_instance(), &"snow_coarse_edges", coarse_edges)
		patch.show()
	terrain.material.set_shader_param("fine_snow_origins", visible_origins)
	if count != _visible_count:
		terrain.material.set_shader_param("fine_snow_tile_count", count)
		_visible_count = count

func _acquire_patch(host: Node3D, terrain: Terrain3D) -> MeshInstance3D:
	for patch in _instances:
		if not patch.visible:
			return patch
	var patch := MeshInstance3D.new()
	patch.hide()
	patch.mesh = _grid
	patch.layers = terrain.render_layers
	patch.top_level = true
	# An atlas tile is a fixed world cell. Rendering must never interpolate between cells.
	patch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var height_range: Vector2 = terrain.data.get_height_range()
	var bottom := minf(height_range.x, height_range.y) - 1.0
	var top := maxf(height_range.x, height_range.y) + SnowDriftProfile.DEPTH_RANGE + 0.25
	var half_tile := TILE_SIZE * 0.5
	patch.custom_aabb = AABB(Vector3(-half_tile, bottom, -half_tile), Vector3(TILE_SIZE, top - bottom, TILE_SIZE))
	host.add_child(patch)
	RenderingServer.instance_geometry_set_material_override(patch.get_instance(), terrain.material.get_material_rid())
	RenderingServer.instance_geometry_set_shader_parameter(patch.get_instance(), &"fine_snow_mesh", true)
	_instances.append(patch)
	return patch
