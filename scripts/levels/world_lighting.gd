@tool
class_name WorldLighting
extends Node3D
## One world shadow pass and a bounded pool of local lamps.
const EXTERIOR_LAYER := 1 << 16
const MAX_ACTIVE_LAMPS := 8
const MAX_RESIDENT_LAMPS := 10
@export var outdoor_ambient := 0.12
@export var indoor_ambient := 0.025
var _lamps: Array[SpotLight3D] = []
var _energies: Dictionary = {}
var _levels: Dictionary = {}
var _emitters: Dictionary = {}
var _camera: Camera3D
var _camera_environment: Environment
var _indoor_mix := 1.0
var _outdoor_fog_density := 0.0
var _outdoor_fog_sky_affect := 0.0
var _outdoor_volume_density := 0.0
var _outdoor_volume_length := 160.0
var _time := 0.0
var _state: BaseGameplayController
var _sun:DirectionalLight3D
var _sun_shadow_distance:=96.0
var _editor_lights:Array[SpotLight3D]=[]
var _editor_elapsed:=0.0
var _editor_levels:Dictionary={}
var _editor_authored:Dictionary={}

func _ready() -> void:
	if Engine.is_editor_hint():return
	add_to_group("world_lighting")
	_state = get_parent().get_node_or_null("BaseGameplayController") as BaseGameplayController
	_sun=get_node("OvercastSun")
	_sun_shadow_distance=_sun.directional_shadow_max_distance
	_tag_exterior(get_parent().get_node("SnowExterior"))
	for node in find_children("*", "SpotLight3D", true, false):
		var lamp := node as SpotLight3D
		_lamps.append(lamp)
		_energies[lamp] = lamp.light_energy
		_levels[lamp] = 0.0
		lamp.light_energy = 0.0
		var lens := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = Vector3(0.42, 0.025, 0.16)
		lens.mesh = shape
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.set_meta("world_lighting_emission", true)
		material.albedo_color = lamp.light_color.darkened(0.5)
		material.emission_enabled = true
		material.emission = lamp.light_color
		material.emission_energy_multiplier = 0.0
		lens.material_override = material
		lamp.add_child(lens)
		lens.rotation.x = PI / 2
		_emitters[lamp] = material

func _tag_exterior(node: Node) -> void:
	if node is GeometryInstance3D: node.layers |= EXTERIOR_LAYER
	if node.is_class("Terrain3D"): node.set("render_layers", int(node.get("render_layers")) | EXTERIOR_LAYER)
	for child in node.get_children(): _tag_exterior(child)

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
	if to_local(at).y < -8.0: return true
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.15, at + Vector3.UP * 10.0, 1, exclude)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_editor_preview(delta)
		return
	_time += delta
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
	_indoor_mix = move_toward(_indoor_mix, 1.0 if is_covered(at, _exclude_body(camera)) else 0.0, delta * 4.0)
	var ambient := lerpf(outdoor_ambient, indoor_ambient, _indoor_mix)
	# Indoors, only nearby outdoor shadows can be seen through openings.
	var sun_distance:=lerpf(_sun_shadow_distance,minf(_sun_shadow_distance,24.0),_indoor_mix)
	if not is_equal_approx(_sun.directional_shadow_max_distance,sun_distance):_sun.directional_shadow_max_distance=sun_distance
	if not is_equal_approx(_camera_environment.ambient_light_energy, ambient): _camera_environment.ambient_light_energy = ambient
	# Outdoor haze fades away under a roof, including on underground floors.
	var fog_density := _outdoor_fog_density * (1.0 - _indoor_mix)
	if not is_equal_approx(_camera_environment.fog_density, fog_density):
		_camera_environment.fog_density = fog_density
		_camera_environment.fog_sky_affect = _outdoor_fog_sky_affect * (1.0 - _indoor_mix)
	var volume_density := lerpf(_outdoor_volume_density, 0.0006, _indoor_mix)
	if not is_equal_approx(_camera_environment.volumetric_fog_density, volume_density):
		_camera_environment.volumetric_fog_density = volume_density
		_camera_environment.volumetric_fog_length = lerpf(_outdoor_volume_length, 32.0, _indoor_mix)
		get_node("OvercastSun").light_volumetric_fog_energy = 0.7 * (1.0 - _indoor_mix)
	_update_lamps(at, delta)

func _editor_preview(delta:float) -> void:
	_editor_elapsed+=delta
	if _editor_elapsed<0.1:return
	_editor_elapsed=0.0
	if _editor_lights.is_empty():
		for lamp:SpotLight3D in find_children("*","SpotLight3D",true,false):_editor_lights.append(lamp)
	var editor:=Engine.get_singleton("EditorInterface")
	if editor==null:return
	var viewport:SubViewport=editor.get_editor_viewport_3d(0)
	var camera:=viewport.get_camera_3d()
	if camera==null:return
	var nearby:Array[SpotLight3D]=[]
	for lamp in _editor_lights:
		if is_instance_valid(lamp) and lamp.is_visible_in_tree() and absf(lamp.global_position.y-camera.global_position.y)<lamp.spot_range:nearby.append(lamp)
	nearby.sort_custom(func(a:SpotLight3D,b:SpotLight3D)->bool:return a.global_position.distance_squared_to(camera.global_position)<b.global_position.distance_squared_to(camera.global_position))
	if nearby.size()>MAX_ACTIVE_LAMPS:nearby.resize(MAX_ACTIVE_LAMPS)
	for lamp in _editor_lights:
		if not is_instance_valid(lamp):continue
		var energy:=lamp.light_energy if lamp in nearby else 0.0
		if _editor_levels.get(lamp,-1.0)!=energy or _editor_authored.get(lamp,-1.0)!=lamp.light_energy:
			RenderingServer.light_set_param(lamp.get_rid(),RenderingServer.LIGHT_PARAM_ENERGY,energy)
			_editor_levels[lamp]=energy
			_editor_authored[lamp]=lamp.light_energy

func _exit_tree() -> void:
	if not Engine.is_editor_hint():return
	for lamp in _editor_lights:
		if is_instance_valid(lamp):RenderingServer.light_set_param(lamp.get_rid(),RenderingServer.LIGHT_PARAM_ENERGY,lamp.light_energy)

func _update_lamps(at: Vector3, delta: float) -> void:
	var nearby: Array[SpotLight3D] = []
	for lamp in _lamps:
		if lamp.get_parent().visible and lamp.global_position.distance_to(at) < 24.0 and absf(lamp.global_position.y-at.y) < lamp.spot_range: nearby.append(lamp)
	nearby.sort_custom(func(a: SpotLight3D, b: SpotLight3D) -> bool: return a.global_position.distance_squared_to(at) < b.global_position.distance_squared_to(at))
	if nearby.size() > MAX_ACTIVE_LAMPS: nearby.resize(MAX_ACTIVE_LAMPS)
	var faulty := _state != null and bool(_state.containment.get("fault", false))
	var targets: Dictionary = {}
	for lamp in _lamps:
		var wanted := 1.0 if lamp in nearby else 0.0
		if wanted > 0.0:
			wanted *= 1.0 - smoothstep(16.0, 24.0, lamp.global_position.distance_to(at))
			if faulty and lamp.get_parent().name == &"Standard": wanted *= 0.9 + 0.1 * sin(_time * 2.0)
		targets[lamp] = wanted
	# Finish fading existing residents before admitting new lamps to the atlas.
	# Capacity limits must never force a visible source to disappear in one frame.
	var residents := 0
	for lamp in _lamps:
		if float(_levels[lamp]) > 0.0:
			_levels[lamp] = move_toward(float(_levels[lamp]), float(targets[lamp]), delta * 5.0)
			if float(_levels[lamp]) > 0.0: residents += 1
	for lamp in nearby:
		if float(_levels[lamp]) == 0.0 and residents < MAX_RESIDENT_LAMPS and float(targets[lamp]) > 0.0:
			_levels[lamp] = minf(float(targets[lamp]), delta * 5.0)
			residents += 1
	for lamp in _lamps:
		var level := float(_levels[lamp])
		lamp.visible = level > 0.0
		var energy := float(_energies[lamp]) * level
		if not is_equal_approx(lamp.light_energy,energy):lamp.light_energy=energy
		var material:=_emitters[lamp] as StandardMaterial3D
		if not is_equal_approx(material.emission_energy_multiplier,level*0.45):material.emission_energy_multiplier=level*0.45

func sample_view_light(camera: Camera3D) -> Color:
	var at := camera.get_global_transform_interpolated().origin
	var sum := Color(0.018, 0.023, 0.03) * lerpf(1.0, 0.12, _indoor_mix)
	var exclude := _exclude_body(camera)
	for lamp in _lamps:
		if not lamp.is_visible_in_tree() or lamp.light_energy <= 0.0: continue
		var offset := at - lamp.global_position
		var distance := offset.length()
		if distance > lamp.spot_range or distance < 0.1: continue
		if (-lamp.global_basis.z).dot(offset / distance) < cos(deg_to_rad(lamp.spot_angle)): continue
		var query := PhysicsRayQueryParameters3D.create(at, lamp.global_position, 1, exclude)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		sum += lamp.light_color * pow(1.0 - distance / lamp.spot_range, 2.0) * lamp.light_energy * 0.16
	sum += Color(0.08, 0.095, 0.12) * (1.0 - _indoor_mix)
	return Color(minf(sum.r, 0.35), minf(sum.g, 0.35), minf(sum.b, 0.35), 1.0)
