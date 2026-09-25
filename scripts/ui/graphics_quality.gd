extends Node
## Applies quality limits without changing authored materials or light placement.
var values: Dictionary = {}
const DEFAULTS := {"Scale": 100, "MSAA": 0, "FXAA": true, "FPS": 0, "SSAO": true, "SSIL": false, "SSR": false, "Glow": true, "Fog": true, "SunShadows": true, "LocalShadows": true, "ShadowDistance": 120, "LOD": 2, "DecalDistance": 40, "TrackCount": 128, "VegetationDistance": 500}

func _ready() -> void:
	get_tree().node_added.connect(_schedule_node)

func _schedule_node(node: Node) -> void:
	if node is WorldEnvironment or node is Light3D or node is Decal or node.name == &"SnowTracks" or node is MultiMeshInstance3D:
		apply_node.call_deferred(node)

func apply(data: Dictionary) -> void:
	values = DEFAULTS.duplicate()
	values.merge(data, true)
	var viewport := get_viewport()
	viewport.scaling_3d_scale = clampf(float(values.Scale) / 100.0, 0.5, 1.0)
	viewport.msaa_3d = clampi(int(values.MSAA), 0, 3)
	viewport.screen_space_aa = 1 if values.FXAA else 0
	viewport.mesh_lod_threshold = float(values.LOD)
	Engine.max_fps = maxi(0, int(values.FPS))
	_visit(get_tree().root)

func _visit(node: Node) -> void:
	apply_node(node)
	for child in node.get_children():
		_visit(child)

func apply_node(node: Node) -> void:
	if not is_instance_valid(node) or values.is_empty():
		return
	if node is WorldEnvironment and node.environment != null:
		apply_environment(node.environment)
	if node is EnvironmentZoneController:
		apply_environment(node.indoor_environment)
		apply_environment(node._transition_environment)
	if node is Light3D:
		if not node.has_meta("quality_shadow_original"):
			node.set_meta("quality_shadow_original", node.shadow_enabled)
		node.shadow_enabled = bool(node.get_meta("quality_shadow_original")) and bool(values.SunShadows if node is DirectionalLight3D else values.LocalShadows)
		if node is DirectionalLight3D:
			node.directional_shadow_max_distance = float(values.ShadowDistance)
	if node is Decal:
		node.distance_fade_enabled = true
		node.distance_fade_begin = float(values.DecalDistance) * 0.75
		node.distance_fade_length = float(values.DecalDistance) * 0.25
	if node.name == &"SnowTracks":
		node.set("max_marks", int(values.TrackCount))
	if node is MultiMeshInstance3D and node.has_meta("exterior_chunk"):
		node.visibility_range_end = float(values.VegetationDistance)
		node.visibility_range_end_margin = 40.0

func apply_environment(env: Environment) -> void:
	if env == null or values.is_empty(): return
	for pair in [["ssao_enabled", "SSAO"], ["ssil_enabled", "SSIL"], ["ssr_enabled", "SSR"], ["glow_enabled", "Glow"], ["fog_enabled", "Fog"]]:
		if not env.has_meta(pair[0]): env.set_meta(pair[0], env.get(pair[0]))
		env.set(pair[0], bool(values[pair[1]]) and (bool(env.get_meta(pair[0])) if pair[1] == "Fog" else true))
