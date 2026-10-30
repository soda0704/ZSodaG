@tool
class_name WorldLighting
extends Node3D
## A bounded shadow atlas pool shared by spot and omni lamps.
const EXTERIOR_LAYER := 1 << 16
const ARRIVAL_SHADOW_LAYER := 1 << 15
const MAX_ACTIVE_LAMPS := 8
const MAX_RESIDENT_LAMPS := 10
const MAX_ACTIVE_SHADOW_SLOTS := 8
const MAX_RESIDENT_SHADOW_SLOTS := 10
const EMERGENCY_COLOR := Color(1.0, 0.025, 0.012)
const EMERGENCY_PERIOD := 2.0
const EMERGENCY_MIN_INTENSITY := 0.15
signal emergency_intensity_changed(intensity: float)
@export var outdoor_ambient := 0.12
@export var indoor_ambient := 0.025
@export_group("Exterior below the base")
@export var lower_exterior_bounds: CollisionShape3D
@export_group("Debug visibility")
@export var debug_visibility_profile: Environment
var debug_darkness := 1.0
var _debug_viewports: Dictionary = {}
var _lamps: Array[Light3D] = []
var _resident_lamps: Array[Light3D] = []
var _energies: Dictionary = {}
var _modulations: Dictionary = {}
var _levels: Dictionary = {}
var _lamp_enabled: Dictionary = {}
var _pool_visibility: Dictionary = {}
var _emergency_lamps: Dictionary = {}
var _emergency_phase := 0.0
var emergency_intensity := 1.0
var _setting_lamp_visibility := false
var _camera: Camera3D
var _camera_environment: Environment
var _indoor_mix := 1.0
var _outdoor_fog_density := 0.0
var _outdoor_fog_sky_affect := 0.0
var _outdoor_volume_density := 0.0
var _outdoor_volume_length := 160.0
var _sun:DirectionalLight3D
var _sun_shadow_distance:=96.0
var quality_shadow_distance := 96.0
var _editor_lights:Array[Light3D]=[]
var _editor_elapsed:=0.0
var _editor_visibility:Dictionary={}

func _ready() -> void:
	if Engine.is_editor_hint():return
	add_to_group("world_lighting")
	_sun=get_node("OvercastSun")
	_sun_shadow_distance=_sun.directional_shadow_max_distance
	refresh_exterior_layers()
	var arrival := get_parent().get_node_or_null("ArrivalSite")
	if arrival != null:
		_tag_shadow_casters(arrival)
		_tag_arrival_exterior(arrival)
	for node in find_children("*", "Light3D", true, false):
		if node is SpotLight3D or node is OmniLight3D: _register_lamp(node)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if (node is SpotLight3D or node is OmniLight3D) and is_ancestor_of(node):
		_register_lamp_id.call_deferred(node.get_instance_id())

func _register_lamp_id(id: int) -> void:
	var lamp := instance_from_id(id) as Light3D
	if is_instance_valid(lamp): _register_lamp(lamp)

static func lamp_range(lamp: Light3D) -> float:
	return lamp.spot_range if lamp is SpotLight3D else lamp.omni_range if lamp is OmniLight3D else 0.0

static func shadow_slot_cost(lamp: Light3D) -> int:
	# Omni shadows occupy two neighbouring atlas cells (dual paraboloid).
	return (2 if lamp is OmniLight3D else 1) if lamp.shadow_enabled else 0

func _select_nearest(lamps: Array[Light3D], at: Vector3) -> Array[Light3D]:
	# Compare coverage: a narrow task lamp must not evict a room's broad fill.
	lamps.sort_custom(func(a: Light3D, b: Light3D) -> bool: return a.global_position.distance_squared_to(at) / pow(lamp_range(a), 2.0) < b.global_position.distance_squared_to(at) / pow(lamp_range(b), 2.0))
	var selected: Array[Light3D] = []
	var slots := 0
	for lamp in lamps:
		var cost := shadow_slot_cost(lamp)
		if selected.size() >= MAX_ACTIVE_LAMPS: break
		if slots + cost > MAX_ACTIVE_SHADOW_SLOTS: continue
		selected.append(lamp)
		slots += cost
	return selected

func _register_lamp(lamp: Light3D) -> void:
	if not is_instance_valid(lamp) or not is_ancestor_of(lamp) or _lamps.has(lamp): return
	_lamps.append(lamp)
	_energies[lamp] = lamp.light_energy
	_levels[lamp] = 0.0
	_lamp_enabled[lamp] = lamp.visible
	_pool_visibility[lamp] = lamp.visible
	var emergency := get_node_or_null("Emergency")
	if emergency != null and emergency.is_ancestor_of(lamp):
		_emergency_lamps[lamp] = lamp.light_color
		lamp.light_color = EMERGENCY_COLOR
	lamp.light_energy = 0.0
	lamp.visibility_changed.connect(_on_lamp_visibility_changed.bind(lamp))
	lamp.tree_exiting.connect(_unregister_lamp.bind(lamp), CONNECT_ONE_SHOT)

func _on_lamp_visibility_changed(lamp: Light3D) -> void:
	# Ancestor visibility also emits this signal. Only a local user change is intent.
	if not _setting_lamp_visibility and lamp.visible != bool(_pool_visibility[lamp]):
		_lamp_enabled[lamp] = lamp.visible
		_pool_visibility[lamp] = lamp.visible

func set_lamp_enabled(lamp: Light3D, enabled: bool) -> void:
	# Also works on a distant lamp whose render visibility is already false.
	if not _lamp_enabled.has(lamp): return
	_lamp_enabled[lamp] = enabled
	if not enabled:
		_setting_lamp_visibility = true
		lamp.hide()
		_pool_visibility[lamp] = false
		_setting_lamp_visibility = false

func set_lamp_modulation(lamp: Light3D, intensity: float) -> void:
	# Fault effects multiply the pool's energy; they never fight its visibility/budget.
	if not _energies.has(lamp): return
	_modulations[lamp] = clampf(intensity, 0.0, 1.0)
	lamp.light_energy = float(_energies[lamp]) * float(_levels[lamp]) * float(_modulations[lamp]) * (emergency_intensity if _emergency_lamps.has(lamp) else 1.0)

func _unregister_lamp(lamp: Light3D) -> void:
	if not _energies.has(lamp): return
	lamp.visibility_changed.disconnect(_on_lamp_visibility_changed.bind(lamp))
	lamp.light_energy = float(_energies[lamp])
	if _emergency_lamps.has(lamp): lamp.light_color = _emergency_lamps[lamp]
	lamp.visible = bool(_lamp_enabled[lamp])
	_lamps.erase(lamp)
	_resident_lamps.erase(lamp)
	for cache in [_energies, _modulations, _levels, _lamp_enabled, _pool_visibility, _emergency_lamps]:
		cache.erase(lamp)

func _advance_emergency(delta: float) -> void:
	# One clock for every backup source and the existing fixture materials.
	# Modulate energy, never circuit visibility or the shadow residency budget.
	_emergency_phase = fposmod(_emergency_phase + delta / EMERGENCY_PERIOD, 1.0)
	var wave := 0.5 + 0.5 * cos(_emergency_phase * TAU)
	emergency_intensity = lerpf(EMERGENCY_MIN_INTENSITY, 1.0, wave * wave)
	emergency_intensity_changed.emit(emergency_intensity)

func refresh_exterior_layers() -> void:
	# A staged Terrain3D enters after _ready. Its native rendering instances
	# must receive the same sunlight membership as a directly loaded scene.
	_tag_exterior(get_parent().get_node("SnowExterior"))

func _tag_exterior(node: Node) -> void:
	if node is GeometryInstance3D: node.layers |= EXTERIOR_LAYER
	if node.is_class("Terrain3D"): node.set("render_layers", int(node.get("render_layers")) | EXTERIOR_LAYER)
	for child in node.get_children(): _tag_exterior(child)

func _tag_arrival_exterior(arrival: Node) -> void:
	# The fixed pad, ramp and rails need both receiver and caster membership.
	# Chinook's imported interior is separate from its exterior mesh surfaces;
	# keep the cabin on its own lamps rather than admitting sun through its walls.
	for child in arrival.get_children():
		if child.name == &"Chinook":
			for mesh: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
				if "Chinook_Exterior" in mesh.name: mesh.layers |= EXTERIOR_LAYER
		else:
			_tag_exterior(child)

func _exclude_body(camera: Camera3D) -> Array[RID]:
	var result: Array[RID] = []
	var parent := camera.get_parent()
	while parent != null:
		if parent is CollisionObject3D:
			result.append(parent.get_rid())
			break
		parent = parent.get_parent()
	return result

func is_covered(at: Vector3, exclude: Array[RID] = []) -> bool:
	# Roof detection uses world-up, independently of the camera's viewing angle.
	var lower_exterior := false
	if is_instance_valid(lower_exterior_bounds) and lower_exterior_bounds.shape is BoxShape3D:
		var half_size: Vector3 = lower_exterior_bounds.shape.size * 0.5
		lower_exterior = AABB(-half_size, half_size * 2.0).has_point(lower_exterior_bounds.to_local(at))
	if to_local(at).y < -8.0 and not lower_exterior: return true
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.15, at + Vector3.UP * 10.0, 1, exclude)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_preview(delta)
		return
	_advance_emergency(delta)
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	if camera != _camera:
		_camera = camera
		var source: Environment = get_parent().get_node("SnowExterior/OvercastDayEnvironment").environment
		_camera_environment = source.duplicate() as Environment
		_outdoor_fog_density = source.fog_density if source.fog_enabled else 0.0
		_outdoor_fog_sky_affect = source.fog_sky_affect
		_outdoor_volume_density = source.volumetric_fog_density
		_outdoor_volume_length = source.volumetric_fog_length
		_camera.environment = _camera_environment
		get_node("/root/GameMenu/GraphicsQuality").apply_environment(_camera_environment)
	var at := camera.get_global_transform_interpolated().origin
	var environment_changed := false
	_indoor_mix = move_toward(_indoor_mix, 1.0 if is_covered(at, _exclude_body(camera)) else 0.0, delta * 4.0)
	var ambient := lerpf(outdoor_ambient, indoor_ambient, _indoor_mix)
	if debug_visibility_profile != null:
		ambient = lerpf(debug_visibility_profile.ambient_light_energy, ambient, debug_darkness)
		var color := debug_visibility_profile.ambient_light_color.lerp(source_environment().ambient_light_color, debug_darkness)
		if not _camera_environment.ambient_light_color.is_equal_approx(color):
			_camera_environment.ambient_light_color = color
			environment_changed = true
	_update_debug_viewports()
	# Indoors, only nearby outdoor shadows can be seen through openings.
	var shadow_range := minf(_sun_shadow_distance, clampf(quality_shadow_distance, 24.0, 96.0))
	var sun_distance:=lerpf(shadow_range,minf(shadow_range,24.0),_indoor_mix)
	if not is_equal_approx(_sun.directional_shadow_max_distance,sun_distance):_sun.directional_shadow_max_distance=sun_distance
	if not is_equal_approx(_camera_environment.ambient_light_energy, ambient):
		_camera_environment.ambient_light_energy = ambient
		environment_changed = true
	# Outdoor haze fades away under a roof, including on underground floors.
	var fog_density := _outdoor_fog_density * (1.0 - _indoor_mix) * debug_darkness
	if not is_equal_approx(_camera_environment.fog_density, fog_density):
		_camera_environment.fog_density = fog_density
		environment_changed = true
	var sky_affect := _outdoor_fog_sky_affect * (1.0 - _indoor_mix)
	if not is_equal_approx(_camera_environment.fog_sky_affect, sky_affect):
		_camera_environment.fog_sky_affect = sky_affect
		environment_changed = true
	var volume_density := lerpf(_outdoor_volume_density, 0.0006, _indoor_mix) * debug_darkness
	if not is_equal_approx(_camera_environment.volumetric_fog_density, volume_density):
		_camera_environment.volumetric_fog_density = volume_density
		environment_changed = true
	var volume_length := lerpf(_outdoor_volume_length, 32.0, _indoor_mix)
	if not is_equal_approx(_camera_environment.volumetric_fog_length, volume_length):
		_camera_environment.volumetric_fog_length = volume_length
		environment_changed = true
	var sun_scattering := 0.7 * (1.0 - _indoor_mix)
	if not is_equal_approx(_sun.light_volumetric_fog_energy, sun_scattering): _sun.light_volumetric_fog_energy = sun_scattering
	if environment_changed: _camera_environment.emit_changed()
	_update_lamps(at, delta)

func source_environment() -> Environment:
	return get_parent().get_node("SnowExterior/OvercastDayEnvironment").environment

func set_debug_darkness(value: float) -> void:
	debug_darkness = clampf(value, 0.0, 1.0)
	var indirect := get_parent().get_node_or_null("WorldIndirectLighting")
	if indirect != null:
		indirect.set_debug_disabled(debug_darkness < 1.0)
	_update_debug_viewports()

func _update_debug_viewports() -> void:
	if not is_zero_approx(debug_darkness) and _debug_viewports.is_empty(): return
	var views: Array[Viewport] = [get_viewport()]
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null and player.body_animator.first_person != null:
		views.append(player.body_animator.first_person.viewport)
	for view in views:
		if is_zero_approx(debug_darkness):
			if not _debug_viewports.has(view): _debug_viewports[view] = view.debug_draw
			view.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
		elif _debug_viewports.has(view):
			view.debug_draw = _debug_viewports[view]
			_debug_viewports.erase(view)

func _editor_preview(delta:float) -> void:
	_editor_elapsed+=delta
	if _editor_elapsed<0.1:return
	_editor_elapsed=0.0
	var editor:=Engine.get_singleton("EditorInterface")
	if editor==null:return
	var viewport:SubViewport=editor.get_editor_viewport_3d(0)
	if viewport == null:return
	var camera:=viewport.get_camera_3d()
	if camera==null:return
	_update_editor_lamp_visibility(camera.global_position)

func _update_editor_lamp_visibility(at: Vector3) -> void:
	var current: Array[Light3D] = []
	for lamp: Light3D in find_children("*", "Light3D", true, false):
		if lamp is SpotLight3D or lamp is OmniLight3D: current.append(lamp)
	for lamp in _editor_lights:
		if not is_instance_valid(lamp):
			_editor_visibility.erase(lamp)
			continue
		if lamp not in current:
			RenderingServer.instance_set_visible(lamp.get_instance(), lamp.is_visible_in_tree())
			_editor_visibility.erase(lamp)
	_editor_lights = current
	var nearby:Array[Light3D]=[]
	for lamp in _editor_lights:
		if lamp.is_visible_in_tree() and absf(lamp.global_position.y-at.y)<lamp_range(lamp):nearby.append(lamp)
	nearby = _select_nearest(nearby, at)
	for lamp in _editor_lights:
		if not is_instance_valid(lamp):continue
		var active := lamp in nearby
		if _editor_visibility.get(lamp, null) != active:
			RenderingServer.instance_set_visible(lamp.get_instance(), active)
			_editor_visibility[lamp] = active

func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		for view in _debug_viewports:
			if is_instance_valid(view): view.debug_draw = _debug_viewports[view]
		return
	for lamp in _editor_lights:
		if is_instance_valid(lamp):RenderingServer.instance_set_visible(lamp.get_instance(),lamp.is_visible_in_tree())

func _update_lamps(at: Vector3, delta: float) -> void:
	var nearby: Array[Light3D] = []
	for lamp in _lamps:
		var parent := lamp.get_parent_node_3d()
		if bool(_lamp_enabled[lamp]) and (parent == null or parent.is_visible_in_tree()) and lamp.global_position.distance_to(at) < 24.0 and absf(lamp.global_position.y-at.y) < lamp_range(lamp): nearby.append(lamp)
	nearby = _select_nearest(nearby, at)
	var targets: Dictionary = {}
	for lamp in _lamps:
		var wanted := 1.0 if lamp in nearby else 0.0
		if wanted > 0.0:
			wanted *= 1.0 - smoothstep(16.0, 24.0, lamp.global_position.distance_to(at))
		targets[lamp] = wanted
	# Finish fading existing residents before admitting new lamps to the atlas.
	# Capacity limits must never force a visible source to disappear in one frame.
	var residents := 0
	var resident_slots := 0
	for lamp in _lamps:
		if float(_levels[lamp]) > 0.0:
			_levels[lamp] = move_toward(float(_levels[lamp]), float(targets[lamp]), delta * 5.0)
			if float(_levels[lamp]) > 0.0:
				residents += 1
				resident_slots += shadow_slot_cost(lamp)
	for lamp in nearby:
		var cost := shadow_slot_cost(lamp)
		if float(_levels[lamp]) == 0.0 and residents < MAX_RESIDENT_LAMPS and resident_slots + cost <= MAX_RESIDENT_SHADOW_SLOTS and float(targets[lamp]) > 0.0:
			_levels[lamp] = minf(float(targets[lamp]), delta * 5.0)
			residents += 1
			resident_slots += cost
	_resident_lamps.clear()
	for lamp in _lamps:
		var level := float(_levels[lamp])
		if level > 0.0: _resident_lamps.append(lamp)
		_setting_lamp_visibility = true
		lamp.visible = level > 0.0 and bool(_lamp_enabled[lamp])
		_pool_visibility[lamp] = lamp.visible
		_setting_lamp_visibility = false
		var energy := float(_energies[lamp]) * level
		energy *= float(_modulations.get(lamp, 1.0))
		if _emergency_lamps.has(lamp): energy *= emergency_intensity
		if not is_equal_approx(lamp.light_energy,energy):lamp.light_energy=energy

func sample_view_light(camera: Camera3D) -> Color:
	var at := camera.get_global_transform_interpolated().origin
	var sum := Color(0.018, 0.023, 0.03) * lerpf(1.0, 0.12, _indoor_mix)
	var exclude := _exclude_body(camera)
	var sources: Array[Light3D] = _resident_lamps.duplicate()
	for mobile in get_tree().get_nodes_in_group("mobile_interior_lights"):
		if (mobile is SpotLight3D or mobile is OmniLight3D) and mobile not in sources:
			sources.append(mobile)
	for lamp in sources:
		if not lamp.is_visible_in_tree() or lamp.light_energy <= 0.0: continue
		var offset := at - lamp.global_position
		var distance := offset.length()
		if distance > lamp_range(lamp) or distance < 0.1: continue
		if lamp is SpotLight3D and (-lamp.global_basis.z).dot(offset / distance) < cos(deg_to_rad(lamp.spot_angle)): continue
		var query := PhysicsRayQueryParameters3D.create(at, lamp.global_position, 1, exclude)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		sum += lamp.light_color * pow(1.0 - distance / lamp_range(lamp), 2.0) * lamp.light_energy * 0.16
	sum += Color(0.08, 0.095, 0.12) * (1.0 - _indoor_mix)
	return Color(minf(sum.r, 0.35), minf(sum.g, 0.35), minf(sum.b, 0.35), 1.0)

func _tag_shadow_casters(node: Node) -> void:
	# Separate caster membership must survive the player camera excluding layers 18/19.
	# Receiver membership is assigned separately by _tag_arrival_exterior.
	if node is GeometryInstance3D: node.layers |= ARRIVAL_SHADOW_LAYER
	for child in node.get_children(): _tag_shadow_casters(child)
