extends Node
## Display quality; the authored horror lighting profile owns world illumination.
var values: Dictionary = {}
const DEFAULTS := {"Brightness": 100, "Gamma": 100, "HDR": false, "HDRWhite": 200, "Scale": 100, "MSAA": 0, "FXAA": true, "FPS": 0, "SSAO": false, "SSIL": false, "SSR": false, "Glow": false, "Fog": false, "SunShadows": false, "LocalShadows": false, "ShadowDistance": 120, "LOD": 2, "DecalDistance": 40, "TrackCount": 128, "VegetationDistance": 500}

func _ready() -> void:
	get_tree().node_added.connect(_schedule_node)

func _schedule_node(node: Node) -> void:
	if node is WorldEnvironment or node is Camera3D or node is Light3D or node is GeometryInstance3D or node is Decal or node.name == &"SnowTracks" or node.has_meta("boundary_detail"):
		_apply_node_id.call_deferred(node.get_instance_id())

func _apply_node_id(id: int) -> void:
	var node := instance_from_id(id)
	if is_instance_valid(node): apply_node(node)

func apply(data: Dictionary) -> void:
	values = DEFAULTS.duplicate()
	values.merge(data, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_request_hdr_output(bool(values.HDR) and DisplayServer.window_is_hdr_output_supported())
		DisplayServer.window_set_hdr_output_reference_luminance(clampf(float(values.HDRWhite), 100.0, 400.0))
	var viewport := get_viewport()
	viewport.scaling_3d_scale = clampf(float(values.Scale) / 100.0, 0.5, 1.0)
	viewport.msaa_3d = clampi(int(values.MSAA), 0, 3) as Viewport.MSAA
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if values.FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
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
	if node.get_viewport() != null and node.get_viewport().has_meta("ui_presentation"):
		return
	if node is WorldEnvironment and node.environment != null:
		apply_environment(node.environment)
	if node is Camera3D and node.environment != null:
		apply_environment(node.environment)
	if node is Decal:
		node.distance_fade_enabled = true
		node.distance_fade_begin = float(values.DecalDistance) * 0.75
		node.distance_fade_length = float(values.DecalDistance) * 0.25
	if node.name == &"SnowTracks":
		node.set("max_marks", int(values.TrackCount))
	if node is GeometryInstance3D and (node.has_meta("exterior_chunk") or node.has_meta("boundary_detail")):
		node.visibility_range_end = float(values.VegetationDistance)
		node.visibility_range_end_margin = 40.0

func apply_environment(env: Environment) -> void:
	if env == null or values.is_empty(): return
	env.adjustment_enabled = true
	env.adjustment_brightness = clampf(float(values.Brightness)/100.0, 0.7, 1.4)
	var gamma := clampi(roundi(float(values.Gamma)/10.0)*10, 70, 150)
	env.adjustment_color_correction = load("res://assets/environments/calibration/gamma_%d.tres" % gamma) if gamma != 100 else null
	# Keep the authored sky, ambient occlusion, bloom and distance haze.
	# Authored VoxelGI and volumetric scattering own indirect light and atmosphere.
	for effect in ["ssil_enabled", "ssr_enabled", "sdfgi_enabled"]:
		env.set(effect, false)
