extends Node
## Render budgets change detail, never the authored energy, colour or fog distances.
const INDIRECT_LIGHTING_SCRIPT = preload("res://scripts/levels/world_indirect_lighting.gd")
const INTERIOR_OCCLUSION_SCRIPT = preload("res://scripts/levels/interior_ambient_occlusion.gd")
signal camera_effects_changed(motion_blur: bool, strength: float)
var values: Dictionary = {}
var _render_update_pending := false
var _applied_budgets: Array[int] = []
const DEFAULTS := {"Brightness": 100, "Gamma": 100, "HDR": false, "HDRWhite": 200, "Scale": 100, "MSAA": 0, "FXAA": true, "FPS": 0, "ShadowQuality": 2, "ShadowDistance": 96, "AOQuality": 2, "FogQuality": 2, "GIQuality": 2, "Bloom": true, "MotionBlur": false, "MotionBlurStrength": 35, "LOD": 2, "DecalDistance": 40, "TrackCount": 128, "VegetationDistance": 500}
const PRESETS := {
	1: {"Scale": 75, "MSAA": 0, "FXAA": true, "ShadowQuality": 1, "ShadowDistance": 48, "AOQuality": 1, "GIQuality": 1, "Bloom": true, "LOD": 6, "DecalDistance": 20, "TrackCount": 64},
	2: {"Scale": 100, "MSAA": 0, "FXAA": true, "ShadowQuality": 2, "ShadowDistance": 96, "AOQuality": 2, "GIQuality": 2, "Bloom": true, "LOD": 2, "DecalDistance": 40, "TrackCount": 128},
	3: {"Scale": 100, "MSAA": 1, "FXAA": false, "ShadowQuality": 3, "ShadowDistance": 96, "AOQuality": 2, "GIQuality": 2, "Bloom": true, "LOD": 1, "DecalDistance": 60, "TrackCount": 256},
}

# Revision 1 accidentally combined full-resolution GI and SSAO in the High preset.
const PRESET_REVISION := 3
const LEGACY_HIGH := {"Scale": 100, "MSAA": 1, "FXAA": false, "ShadowQuality": 3, "ShadowDistance": 96, "AOQuality": 3, "FogQuality": 3, "GIQuality": 3, "Bloom": true, "LOD": 1, "DecalDistance": 60, "TrackCount": 256, "VegetationDistance": 650}

static func migrate_saved(data: Dictionary, revision: int) -> Dictionary:
	var result := data.duplicate(true)
	if revision >= PRESET_REVISION: return result
	# Revision 2 enabled camera blur automatically. The revised film profile
	# starts sharp, also for existing installs; later explicit choices survive.
	if result.has("MotionBlur"): result.MotionBlur = false
	if revision >= 2: return result
	for key in LEGACY_HIGH:
		if not data.has(key) or data[key] != LEGACY_HIGH[key]: return result
	# Only the exact previous preset is replaced; custom and display values survive.
	result.merge(PRESETS[3], true)
	return result

static func normalized(data: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key in DEFAULTS:
		if data.has(key): result[key] = data[key]
	# Saved files and the UI must describe the same values the renderer receives.
	var ranges := {"Brightness": [70, 140], "Gamma": [70, 150], "HDRWhite": [100, 400], "Scale": [50, 100], "MSAA": [0, 3], "FPS": [0, 240], "ShadowQuality": [1, 3], "ShadowDistance": [24, 96], "AOQuality": [0, 3], "FogQuality": [0, 3], "GIQuality": [0, 3], "MotionBlurStrength": [0, 100], "LOD": [1, 8], "DecalDistance": [10, 70], "TrackCount": [32, 512], "VegetationDistance": [150, 750]}
	for key in ranges:
		if not (result[key] is int or result[key] is float) or not is_finite(float(result[key])): result[key] = DEFAULTS[key]
		result[key] = clampi(roundi(float(result[key])), ranges[key][0], ranges[key][1])
	result.Gamma = roundi(float(result.Gamma) / 10.0) * 10
	for key in ["HDR", "FXAA", "Bloom", "MotionBlur"]:
		if not (result[key] is bool or result[key] is int or result[key] is float): result[key] = DEFAULTS[key]
		result[key] = bool(result[key])
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
	if node is WorldEnvironment or node is Camera3D or node is GeometryInstance3D or node is Decal or node is WorldLighting or node is SubViewport or (node.get_script() == INDIRECT_LIGHTING_SCRIPT or node.get_script() == INTERIOR_OCCLUSION_SCRIPT) or node.name == &"SnowTracks" or node.has_meta("boundary_detail"):
		_apply_node_id.call_deferred(node.get_instance_id())

func _apply_node_id(id: int) -> void:
	var node := instance_from_id(id)
	if is_instance_valid(node): apply_node(node)

func apply(data: Dictionary) -> void:
	var next := normalized(data)
	if next == values:
		apply_display_output()
		return
	var update_nodes := values.is_empty()
	for key in ["Brightness", "Gamma", "MSAA", "FXAA", "ShadowDistance", "AOQuality", "FogQuality", "GIQuality", "Bloom", "DecalDistance", "TrackCount", "VegetationDistance"]:
		if values.get(key) != next[key]: update_nodes = true; break
	var camera_changed: bool = values.is_empty() or values.get("MotionBlur") != next.MotionBlur or values.get("MotionBlurStrength") != next.MotionBlurStrength
	values = next
	if camera_changed: camera_effects_changed.emit(bool(values.MotionBlur), float(values.MotionBlurStrength) / 100.0)
	apply_display_output()
	var viewport := get_viewport()
	viewport.scaling_3d_scale = clampf(float(values.Scale) / 100.0, 0.5, 1.0)
	viewport.msaa_3d = clampi(int(values.MSAA), 0, 3) as Viewport.MSAA
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if values.FXAA else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.mesh_lod_threshold = float(values.LOD)
	_update_shadow_atlas()
	_update_render_budgets()
	Engine.max_fps = maxi(0, int(values.FPS))
	if update_nodes: _visit(get_tree().root)

func apply_display_output() -> void:
	if values.is_empty() or DisplayServer.get_name() == "headless": return
	# Re-evaluate support after changing monitors even when graphics are identical.
	DisplayServer.window_request_hdr_output(bool(values.HDR) and DisplayServer.window_is_hdr_output_supported())
	DisplayServer.window_set_hdr_output_reference_luminance(float(values.HDRWhite))

func set_gi_quality(level: int) -> void:
	var next := values.duplicate()
	next.GIQuality = clampi(level, 0, 3)
	apply(next)

func _update_shadow_atlas() -> void:
	get_viewport().positional_shadow_atlas_size = 2048 if int(values.ShadowQuality) == 1 else 4096

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
	# Engine enum entries include Very Low and Low before Medium. A numeric
	# offset made the UI's Medium/High settings select Very Low/Low filtering.
	var shadow_filter: RenderingServer.ShadowQuality = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][shadows - 1]
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_filter)
	# Multiple local shadow maps are substantially dearer than the single sun.
	# Keep filtered occlusion at Medium without running the sun's PCF kernel
	# for every room lamp; High retains the previous Medium kernel locally.
	var local_filter: RenderingServer.ShadowQuality = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][shadows - 1]
	RenderingServer.positional_soft_shadow_filter_set_quality(local_filter)
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
	if node.get_script() == INDIRECT_LIGHTING_SCRIPT:
		node.set_quality_enabled(int(values.GIQuality) > 0)
	if node.get_script() == INTERIOR_OCCLUSION_SCRIPT:
		node.set_gi_enabled(int(values.GIQuality) > 0)
	if node is WorldEnvironment:
		# The authored node is the source, never the destination of a preset.
		var active_camera := node.get_viewport().get_camera_3d()
		if active_camera != null: apply_node(active_camera)
	if node is Camera3D:
		var source: Environment = node.environment if node.environment != null else node.get_world_3d().environment
		if source != null:
			if not source.get_meta("quality_runtime_environment", false):
				node.environment = make_environment_copy(source)
			elif node.environment == null: node.environment = source
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

func _remember_environment(env: Environment) -> void:
	env.set_meta("quality_authored_effects", {"ao":env.ssao_enabled,"fog":env.volumetric_fog_enabled,"bloom":env.glow_enabled,"ssil":env.ssil_enabled,"ssr":env.ssr_enabled,"sdfgi":env.sdfgi_enabled})
	env.set_meta("quality_authored_calibration", {"enabled":env.adjustment_enabled,"brightness":env.adjustment_brightness,"correction":env.adjustment_color_correction})

func make_environment_copy(source: Environment) -> Environment:
	var result := source.duplicate() as Environment
	# Discard stale metadata from older scenes; actual Inspector values win.
	_remember_environment(result)
	result.set_meta("quality_runtime_environment", true)
	return result

func apply_environment(env: Environment) -> void:
	if env == null or values.is_empty(): return
	if not env.has_meta("quality_authored_calibration"): _remember_environment(env)
	var authored: Dictionary = env.get_meta("quality_authored_effects")
	var calibration: Dictionary = env.get_meta("quality_authored_calibration")
	var brightness := float(calibration.brightness) * clampf(float(values.Brightness)/100.0, 0.7, 1.4)
	if not is_equal_approx(env.adjustment_brightness, brightness): env.adjustment_brightness = brightness
	var gamma := clampi(roundi(float(values.Gamma)/10.0)*10, 70, 150)
	env.adjustment_enabled = bool(calibration.enabled) or int(values.Brightness) != 100 or gamma != 100
	var correction: Texture = load("res://assets/environments/calibration/gamma_%d.tres" % gamma) if gamma != 100 else calibration.correction
	if env.adjustment_color_correction != correction: env.adjustment_color_correction = correction
	var ao_enabled: bool = authored.ao and int(values.AOQuality) > 0
	var fog_enabled: bool = authored.fog and int(values.FogQuality) > 0
	var bloom_enabled: bool = authored.bloom and bool(values.Bloom)
	if env.ssao_enabled != ao_enabled: env.ssao_enabled = ao_enabled
	if env.volumetric_fog_enabled != fog_enabled: env.volumetric_fog_enabled = fog_enabled
	if env.glow_enabled != bloom_enabled: env.glow_enabled = bloom_enabled
	# Preserve the remaining authored effects; no bundled lighting override.
	# VoxelGI has its own saved setting and a separate circuit constraint.
	for effect in ["ssil_enabled", "ssr_enabled", "sdfgi_enabled"]:
		var enabled: bool = bool(authored.get(effect.trim_suffix("_enabled"), false))
		if env.get(effect) != enabled: env.set(effect, enabled)
	# Environment setters update the renderer but do not consistently emit changed.
	# The isolated hands keep a copy and must receive calibration/effect updates.
	env.emit_changed()

# Conservative hardware baseline, followed by a measured in-session check.
# Frame-time correction changes rendering budgets only, never authored light.
static func recommended(adapter: String = "", pixels: int = 0) -> Dictionary:
	if adapter.is_empty(): adapter = RenderingServer.get_video_adapter_name()
	if pixels <= 0: pixels = DisplayServer.screen_get_size().x * DisplayServer.screen_get_size().y if DisplayServer.get_name() != "headless" else 2073600
	var integrated := adapter.to_lower().contains("intel") or adapter.to_lower().contains("vega") or adapter.to_lower().contains("radeon graphics")
	var data: Dictionary = DEFAULTS.duplicate()
	data.merge(PRESETS[1 if integrated else 2], true)
	if pixels > 2560 * 1440: data.Scale = mini(int(data.Scale), 67)
	elif pixels > 1920 * 1200: data.Scale = mini(int(data.Scale), 85)
	data.FPS = 60
	return data

var _calibration_elapsed := 0.0
var _calibration_frames: Array[float] = []
var _calibration_round := 0
var _previous_frame_usec := 0

func _process(delta: float) -> void:
	var menu := get_node_or_null("/root/GameMenu")
	if menu == null or not menu._settings_data.get("GraphicsCalibrationPending", false) or DisplayServer.get_name() == "headless": return
	var player := get_tree().get_first_node_in_group("local_player")
	if player == null or menu.is_menu_open() or get_tree().get_first_node_in_group("main_menu") != null or get_tree().get_first_node_in_group("base_gameplay_controller") == null:
		_previous_frame_usec = 0
		return
	var now := Time.get_ticks_usec()
	var frame_ms := float(now - _previous_frame_usec) / 1000.0 if _previous_frame_usec > 0 else 0.0
	_previous_frame_usec = now
	_calibration_elapsed += delta
	if _calibration_elapsed < 5.0: return # Asset/shader warm-up is not steady gameplay.
	if frame_ms > 0.0: _calibration_frames.append(frame_ms)
	if _calibration_frames.size() < 240: return
	_calibration_frames.sort()
	var slow_frame := _calibration_frames[int(_calibration_frames.size() * 0.9)]
	if slow_frame > 18.5 and int(values.Scale) > 50 and _calibration_round < 5:
		var reduced := values.duplicate()
		reduced.Scale = maxi(50, int(reduced.Scale) - 10)
		if _calibration_round >= 1:
			for key in ["LOD", "DecalDistance", "TrackCount"]: reduced[key] = PRESETS[1][key]
		apply(reduced)
		menu._settings_data.Graphics = reduced
		_calibration_round += 1
		_calibration_elapsed = 3.0
		_calibration_frames.clear()
	else:
		menu._settings_data.GraphicsCalibrationPending = false
		menu._settings_data.RecommendedGraphics = values.duplicate()
		menu._settings_data.GraphicsMeasuredP90 = slow_frame
		menu.save_settings_data()
		_calibration_frames.clear()

func restart_recommendation() -> void:
	_calibration_elapsed = 0.0
	_calibration_frames.clear()
	_calibration_round = 0
	_previous_frame_usec = 0
