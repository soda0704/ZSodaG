@tool
extends Node3D
## Interior reflection captures also cover GI boundaries and missing voxels.
## They replace sky only on interior geometry, never on the whole camera.
const RECEIVER_LAYER := 1 << 19
const EXTERIOR_LAYER := 1 << 16
var _receivers: Dictionary = {}
var _gi_enabled := true
var _power_enabled := true

func _ready() -> void:
	add_to_group("interior_ambient_occlusion")
	var circuit := get_parent().get_node_or_null("BasePowerLightingController")
	if circuit != null: _power_enabled = circuit.is_standard_powered
	_tag_tree(get_parent())
	get_tree().node_added.connect(_on_node_added)
	set_gi_enabled(_gi_enabled)

func set_gi_enabled(enabled: bool) -> void:
	_gi_enabled = enabled
	_refresh_mode()

func set_power_enabled(enabled: bool) -> void:
	if _power_enabled == enabled: return
	_power_enabled = enabled
	_refresh_mode()

func _refresh_mode() -> void:
	# VoxelGI does not cover every trim, doorway edge or newly placed panel.
	# With GI enabled replace sky reflections only. AMBIENT_COLOR would also
	# override VoxelGI's diffuse bounce, flattening light from the room lamps.
	$Fallback.visible = true
	for probe: ReflectionProbe in $Fallback.get_children():
		probe.ambient_mode = ReflectionProbe.AMBIENT_DISABLED if _gi_enabled and _power_enabled else ReflectionProbe.AMBIENT_COLOR

func _excluded(node: Node) -> bool:
	return node.name in [&"ArcticBase_ExteriorShell", &"SnowExterior", &"ArrivalSite"] or "SolarPanel" in str(node.name)

func _tag_tree(node: Node) -> void:
	if _excluded(node): return
	if node is Node3D and node.get_world_3d() != get_world_3d(): return
	if node is GeometryInstance3D and not (node.layers & EXTERIOR_LAYER):
		if not _receivers.has(node.get_instance_id()): _receivers[node.get_instance_id()] = node.layers
		# Use the node setter so both render culling and reflection receiver data
		# (including internally generated CSG instances) receive the same mask.
		# Runtime node membership does not modify imported meshes or materials.
		if not Engine.is_editor_hint(): node.layers |= RECEIVER_LAYER
	for child in node.get_children(): _tag_tree(child)

func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D: _tag_added.call_deferred(node.get_instance_id())

func _tag_added(id: int) -> void:
	var node := instance_from_id(id) as Node
	if not is_instance_valid(node) or not get_parent().is_ancestor_of(node): return
	var ancestor := node
	while ancestor != get_parent():
		if _excluded(ancestor): return
		ancestor = ancestor.get_parent()
	_tag_tree(node)

func _exit_tree() -> void:
	for id in _receivers:
		var node := instance_from_id(id) as GeometryInstance3D
		if is_instance_valid(node) and node.is_inside_tree():
			if not Engine.is_editor_hint() and not (int(_receivers[id]) & RECEIVER_LAYER): node.layers &= ~RECEIVER_LAYER
