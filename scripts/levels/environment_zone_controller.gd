class_name EnvironmentZoneController
extends Node

@export var indoor_environment: Environment
@export var outdoor_environment_path: NodePath
@export var indoor_zone_group: StringName = &"indoor_environment_zone"
@export_range(0.1, 5.0, 0.05) var transition_duration: float = 1.25

var _indoor_zones: Array[Area3D] = []
var _outdoor_environment: Environment
var _transition_environment: Environment
var _active_camera: Camera3D
var _target_indoor: bool = false
var _blend: float = 0.0
var _initialized: bool = false


func _ready() -> void:
	set_process(false)
	_connect_indoor_zones.call_deferred()


func _connect_indoor_zones() -> void:
	if not is_inside_tree():
		return
	var outdoor_node := get_node_or_null(outdoor_environment_path) as WorldEnvironment
	if outdoor_node != null:
		_outdoor_environment = outdoor_node.environment
	if _outdoor_environment == null or indoor_environment == null:
		push_warning("Indoor and outdoor environments must both be assigned")
		return
	_transition_environment = _outdoor_environment.duplicate() as Environment
	for node in get_tree().get_nodes_in_group(indoor_zone_group):
		var zone := node as Area3D
		if zone == null:
			continue
		_indoor_zones.append(zone)
		zone.body_entered.connect(_on_zone_body_changed)
		zone.body_exited.connect(_on_zone_body_changed)
	_refresh_camera_environment.call_deferred(true)


func _on_zone_body_changed(_body: Node3D) -> void:
	# Defer until the physics server has updated every overlapping zone. This
	# prevents a one-frame outdoor flash where two interior volumes overlap.
	if not is_inside_tree():
		return
	_refresh_camera_environment.call_deferred(false)


func _refresh_camera_environment(immediate: bool = false) -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	var is_indoor := _is_camera_indoor(camera)
	if not _initialized or camera != _active_camera:
		_active_camera = camera
		_target_indoor = is_indoor
		_blend = 1.0 if is_indoor else 0.0
		_initialized = true
		_apply_final_environment()
		return
	if is_indoor == _target_indoor:
		return
	_target_indoor = is_indoor
	if immediate:
		_blend = 1.0 if is_indoor else 0.0
		_apply_final_environment()
		return
	camera.environment = _transition_environment
	_apply_environment_blend()
	set_process(true)


func _is_camera_indoor(camera: Camera3D) -> bool:
	for zone in _indoor_zones:
		for body in zone.get_overlapping_bodies():
			if body is Node and body.is_ancestor_of(camera):
				return true
	return false


func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	if camera != _active_camera:
		_initialized = false
		_refresh_camera_environment(true)
		return
	var target := 1.0 if _target_indoor else 0.0
	_blend = move_toward(_blend, target, delta / transition_duration)
	_apply_environment_blend()
	if is_equal_approx(_blend, target):
		_apply_final_environment()


func _apply_environment_blend() -> void:
	if _transition_environment == null or _active_camera == null:
		return
	var weight := smoothstep(0.0, 1.0, _blend)
	_transition_environment.background_energy_multiplier = lerpf(
		_outdoor_environment.background_energy_multiplier,
		indoor_environment.background_energy_multiplier,
		weight
	)
	_transition_environment.ambient_light_color = (
		_outdoor_environment.ambient_light_color.lerp(
			indoor_environment.ambient_light_color,
			weight
		)
	)
	_transition_environment.ambient_light_energy = lerpf(
		_outdoor_environment.ambient_light_energy,
		indoor_environment.ambient_light_energy,
		weight
	)
	_transition_environment.fog_enabled = true
	_transition_environment.fog_light_color = (
		_outdoor_environment.fog_light_color.lerp(
			indoor_environment.fog_light_color,
			weight
		)
	)
	_transition_environment.fog_density = lerpf(
		_outdoor_environment.fog_density if _outdoor_environment.fog_enabled else 0.0,
		indoor_environment.fog_density if indoor_environment.fog_enabled else 0.0,
		weight
	)
	_transition_environment.fog_sky_affect = lerpf(
		_outdoor_environment.fog_sky_affect if _outdoor_environment.fog_enabled else 0.0,
		indoor_environment.fog_sky_affect if indoor_environment.fog_enabled else 0.0,
		weight
	)
	_active_camera.environment = _transition_environment


func _apply_final_environment() -> void:
	if _active_camera == null:
		return
	_active_camera.environment = indoor_environment if _target_indoor else null
	set_process(false)
