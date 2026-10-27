@tool
extends Node3D

const EXTERIOR_LAYER := 1 << 18
const EXTERIOR_ROOF_GROUP := &"exterior_snow_roof"
@export var minimum_view_distance := 2600.0
var _loading_terrain := false
var _terrain_source_directory := ""
var _pending_terrain: Terrain3D
var _terrain_index := 0

func prepare_loading() -> void:
	if Engine.is_editor_hint() or _loading_terrain: return
	_loading_terrain = true
	_terrain_source_directory = $Terrain3D.data_directory
	# Terrain3D normally reads its whole directory synchronously on entering the
	# tree. Supply those same regions explicitly while the loading cover is up.
	$Terrain3D.data_directory = ""
	$Terrain3D.collision_mode = Terrain3DCollision.DISABLED
	_pending_terrain = $Terrain3D
	_terrain_index = _pending_terrain.get_index()
	_pending_terrain.owner = null
	remove_child(_pending_terrain)

func finish_loading() -> bool:
	if not _loading_terrain: return true
	# The native terrain initializes sizeable rendering resources on entering
	# the tree. Give that its own frame instead of combining it with the base.
	await get_tree().process_frame
	add_child(_pending_terrain)
	move_child(_pending_terrain, _terrain_index)
	_pending_terrain.owner = self
	_pending_terrain = null
	await get_tree().process_frame
	var paths: Array[String] = []
	for file in ResourceLoader.list_directory(_terrain_source_directory):
		if not file.begins_with("terrain3d") or not file.ends_with(".res"): continue
		paths.append(_terrain_source_directory.path_join(file))
	paths.sort()
	if paths.is_empty():
		push_error("No terrain regions in " + _terrain_source_directory)
		return false
	var threaded := DisplayServer.get_name() != "headless"
	if threaded:
		for path in paths:
			if ResourceLoader.load_threaded_request(path, "Terrain3DRegion") != OK:
				push_error("Could not request terrain region: " + path)
				return false
	for path in paths:
		var region: Terrain3DRegion
		if threaded:
			while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await get_tree().process_frame
			if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:
				push_error("Could not load terrain region: " + path)
				return false
			region = ResourceLoader.load_threaded_get(path) as Terrain3DRegion
		else:
			region = load(path) as Terrain3DRegion
		if region == null: return false
		# Locations are encoded in filenames, not serialized in these resources.
		region.set_location(Terrain3DUtil.filename_to_location(path.get_file()))
		$Terrain3D.region_size = region.get_region_size()
		if $Terrain3D.data.add_region(region, false) != OK: return false
		await get_tree().process_frame
	preload("res://scripts/network/level_load_job.gd").trace("maps_begin")
	$Terrain3D.data.update_maps()
	preload("res://scripts/network/level_load_job.gd").trace("maps_end")
	await get_tree().process_frame
	preload("res://scripts/network/level_load_job.gd").trace("instances_begin")
	$Terrain3D.get_instancer().update_mmis(true)
	preload("res://scripts/network/level_load_job.gd").trace("instances_end")
	await get_tree().process_frame
	# Retain full-world collision for distant objects and the other player.
	preload("res://scripts/network/level_load_job.gd").trace("terrain_collision_begin")
	$Terrain3D.collision_mode = Terrain3DCollision.FULL_GAME
	preload("res://scripts/network/level_load_job.gd").trace("terrain_collision_end")
	await get_tree().process_frame
	_loading_terrain = false
	return true

# The native directory setter clears/reloads all regions. Keep the original path
# separately after incremental loading; the authored scene remains unchanged.
func get_terrain_source_directory() -> String:
	return _terrain_source_directory if not _terrain_source_directory.is_empty() else $Terrain3D.data_directory

func _exit_tree() -> void:
	if is_instance_valid(_pending_terrain):
		_pending_terrain.free()
		_pending_terrain = null

func _ready() -> void:
	_finish_setup.call_deferred()

func _finish_setup() -> void:
	# Native collision aliases are not serialized by Terrain3D 1.0.2.
	# Full terrain collision also supports remote players away from the host camera.
	if not Engine.is_editor_hint() and not _loading_terrain:
		$Terrain3D.collision_mode = Terrain3DCollision.FULL_GAME
	var level_root := get_parent()
	if level_root == null:
		return
	var floor_level := level_root.get_node_or_null("Floor_0_Base_Blockout")
	if floor_level == null:
		return
	for geometry in floor_level.find_children("*", "GeometryInstance3D", true, false):
		geometry.layers |= EXTERIOR_LAYER
	if not has_node("RoofSnow"):
		var caps := Node3D.new()
		caps.name = "RoofSnow"
		add_child(caps)
		var snow := StandardMaterial3D.new()
		snow.albedo_color = Color("dce6ed")
		snow.roughness = 1.0
		for roof_node in get_tree().get_nodes_in_group(EXTERIOR_ROOF_GROUP):
			var roof := roof_node as CSGBox3D
			if roof == null or not floor_level.is_ancestor_of(roof) or not roof.is_visible_in_tree():
				continue
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(roof.size.x + 0.12, 0.16, roof.size.z + 0.12)
			box.material = snow
			mesh.mesh = box
			mesh.layers = 1 | EXTERIOR_LAYER
			caps.add_child(mesh)
			mesh.global_transform = roof.global_transform
			mesh.global_position.y += roof.size.y * 0.5 + 0.06

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.far < minimum_view_distance:
		camera.far = minimum_view_distance
