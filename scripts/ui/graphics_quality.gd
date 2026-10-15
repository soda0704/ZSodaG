extends Node
## Render budgets change detail, never the authored energy, colour or fog distances.
var values: Dictionary = {}
var _render_update_pending := false
var _applied_budgets: Array[int] = []
const DEFAULTS := {"Brightness": 100, "Gamma": 100, "HDR": false, "HDRWhite": 200, "Scale": 100, "MSAA": 0, "FXAA": true, "FPS": 0, "ShadowQuality": 2, "ShadowDistance": 96, "AOQuality": 2, "FogQuality": 2, "GIQuality": 2, "Bloom": true, "LOD": 2, "DecalDistance": 40, "TrackCount": 128, "VegetationDistance": 500}
const PRESETS := {
	1: {"Scale": 75, "MSAA": 0, "FXAA": true, "ShadowQuality": 1, "ShadowDistance": 48, "AOQuality": 1, "FogQuality": 1, "GIQuality": 1, "Bloom": true, "LOD": 6, "DecalDistance": 20, "TrackCount": 64, "VegetationDistance": 250},
	2: {"Scale": 100, "MSAA": 0, "FXAA": true, "ShadowQuality": 2, "ShadowDistance": 96, "AOQuality": 2, "FogQuality": 2, "GIQuality": 2, "Bloom": true, "LOD": 2, "DecalDistance": 40, "TrackCount": 128, "VegetationDistance": 500},
	3: {"Scale": 100, "MSAA": 1, "FXAA": false, "ShadowQuality": 3, "ShadowDistance": 96, "AOQuality": 2, "FogQuality": 3, "GIQuality": 2, "Bloom": true, "LOD": 1, "DecalDistance": 60, "TrackCount": 256, "VegetationDistance": 650},
}

# Revision 1 accidentally combined full-resolution GI and SSAO in the High preset.
const PRESET_REVISION := 2
const LEGACY_HIGH := {"Scale": 100, "MSAA": 1, "FXAA": false, "ShadowQuality": 3, "ShadowDistance": 96, "AOQuality": 3, "FogQuality": 3, "GIQuality": 3, "Bloom": true, "LOD": 1, "DecalDistance": 60, "TrackCount": 256, "VegetationDistance": 650}

static func migrate_saved(data: Dictionary, revision: int) -> Dictionary:
	var result := data.duplicate(true)
	if revision >= PRESET_REVISION: return result
	for key in LEGACY_HIGH:
		if not data.has(key) or data[key] != LEGACY_HIGH[key]: return result
	# Only the exact previous preset is replaced; custom and display values survive.
	result.merge(PRESETS[3], true)
	return result

static func normalized(data: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key in DEFAULTS:
		if data.has(key): result[key] = data[key]
	result.ShadowDistance = clampf(float(result.ShadowDistance), 24.0, 96.0)
	return result

static func preset_index(data: Dictionary) -> int:
	for index in PRESETS:
		var matches := true
		for key in PRESETS[index]:
			if data.get(key, DEFAULTS[key]) != PRESETS[index][key]: matches = false; break
		if matches: return index
	return 0

func _ready() -> void:
	get_tree().node_added.connect(_schedule_node)

func _schedule_node(node: Node) -> void:
	if node is WorldEnvironment or node is Camera3D or node is GeometryInstance3D or node is Decal or node is WorldLighting or node is SubViewport or node.name == &"SnowTracks" or node.has_meta("boundary_detail"):
		_apply_node_id.call_deferred(node.get_instance_id())

func _apply_node_id(id: int) -> void:
	var node := instance_from_id(id)
	if is_instance_valid(node): apply_node(node)

func apply(data: Dictionary) -> void:
	var next := normalized(data)
	if next == values: return
	var update_nodes := values.is_empty()
	for key in ["Brightness", "Gamma", "MSAA", "FXAA", "ShadowDistance", "AOQuality", "FogQuality", "Bloom", "DecalDistance", "TrackCount", "VegetationDistance"]:
		if values.get(key) != next[key]: update_nodes = true; break
	values = next
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_request_hdr_output(bool(values.HDR) and DisplayServer.window_is_hdr_output_supported())
		DisplayServer.window_set_hdr_output_reference_luminance(clampf(float(values.HDRWhite), 100.0, 400.0))
	var viewport := get_viewport()
	viewport.scaling_3d_scale = clampf(float(values.Scale) / 100.0, 0.5, 1.0)
	viewport.msaa_3d = clampi(int(values.MSAA), 0, 3) as Viewport.MSAA
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if values.FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.mesh_lod_threshold = float(values.LOD)
	viewport.positional_shadow_atlas_size = 2048 if int(values.ShadowQuality) == 1 else 4096
	_update_render_budgets()
	Engine.max_fps = maxi(0, int(values.FPS))
	if update_nodes: _visit(get_tree().root)

func _update_render_budgets() -> void:
	if _render_update_pending or DisplayServer.get_name() == "headless": return
	if _budget_signature() == _applied_budgets: return
	_render_update_pending = true
	# The first window buffers must exist before screen-space effects resize them.
	await RenderingServer.frame_post_draw
	if not is_inside_tree(): return
	_render_update_pending = false
	var signature := _budget_signature()
	if signature == _applied_budgets: return
	var shadows := clampi(int(values.ShadowQuality), 1, 3)
	RenderingServer.directional_shadow_atlas_set_size([2048, 4096, 4096][shadows - 1], false)
	RenderingServer.directional_soft_shadow_filter_set_quality((shadows - 1) as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality((shadows - 1) as RenderingServer.ShadowQuality)
	var ao := clampi(int(values.AOQuality), 0, 3)
	RenderingServer.environment_set_ssao_quality(([0, 0, 2, 3][ao]) as RenderingServer.EnvironmentSSAOQuality, ao < 3, 0.5, 2, 30.0, 150.0)
	var fog := clampi(int(values.FogQuality), 0, 3)
	RenderingServer.environment_set_volumetric_fog_volume_size([64, 64, 96, 128][fog], [48, 48, 64, 64][fog])
	var gi := clampi(int(values.GIQuality), 1, 3)
	RenderingServer.gi_set_use_half_resolution(gi < 3)
	RenderingServer.voxel_gi_set_quality((0 if gi == 1 else 1) as RenderingServer.VoxelGIQuality)
	_applied_budgets = signature

func _budget_signature() -> Array[int]:
	return [clampi(int(values.ShadowQuality), 1, 3), clampi(int(values.AOQuality), 0, 3), clampi(int(values.FogQuality), 0, 3), clampi(int(values.GIQuality), 1, 3)]

func _visit(node: Node) -> void:
	apply_node(node)
	for child in node.get_children():
		_visit(child)

func apply_node(node: Node) -> void:
	if not is_instance_valid(node) or values.is_empty():
		return
	if node.get_viewport() != null and node.get_viewport().has_meta("ui_presentation"):
		return
	if node is SubViewport and node.name == &"ViewmodelViewport":
		node.msaa_3d = clampi(int(values.MSAA), 0, 3) as Viewport.MSAA
		node.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if values.FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	# Terrain3D's 2x2 mouse-picking camera and other utility viewports must retain
	# their own unshaded environment; screen-space effects break their data pass.
	if node.get_viewport() != get_viewport(): return
	if node is WorldLighting:
		node.quality_shadow_distance = float(values.ShadowDistance)
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
	if not env.has_meta("quality_authored_effects"):
		env.set_meta("quality_authored_effects", {"ao": env.ssao_enabled, "fog": env.volumetric_fog_enabled, "bloom": env.glow_enabled})
	var authored: Dictionary = env.get_meta("quality_authored_effects")
	if not env.adjustment_enabled: env.adjustment_enabled = true
	var brightness := clampf(float(values.Brightness)/100.0, 0.7, 1.4)
	if not is_equal_approx(env.adjustment_brightness, brightness): env.adjustment_brightness = brightness
	var gamma := clampi(roundi(float(values.Gamma)/10.0)*10, 70, 150)
	var correction: Texture = load("res://assets/environments/calibration/gamma_%d.tres" % gamma) if gamma != 100 else null
	if env.adjustment_color_correction != correction: env.adjustment_color_correction = correction
	var ao_enabled: bool = authored.ao and int(values.AOQuality) > 0
	var fog_enabled: bool = authored.fog and int(values.FogQuality) > 0
	var bloom_enabled: bool = authored.bloom and bool(values.Bloom)
	if env.ssao_enabled != ao_enabled: env.ssao_enabled = ao_enabled
	if env.volumetric_fog_enabled != fog_enabled: env.volumetric_fog_enabled = fog_enabled
	if env.glow_enabled != bloom_enabled: env.glow_enabled = bloom_enabled
	# Distance haze and VoxelGI stay present even on Low; no extra light sources.
	for effect in ["ssil_enabled", "ssr_enabled", "sdfgi_enabled"]:
		if env.get(effect): env.set(effect, false)
	# Environment setters update the renderer but do not consistently emit changed.
	# The isolated hands keep a copy and must receive calibration/effect updates.
	env.emit_changed()
