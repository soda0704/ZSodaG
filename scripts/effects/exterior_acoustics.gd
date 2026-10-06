class_name ExteriorAcoustics
extends Node

@export var storm_sources_path: NodePath
@export var wind_volume_db := -20.0
@export var storm_volume_db := -16.0
@export var sheltered_wind_gain := 0.025
@export var fade_seconds := 1.0
@export var initialization_roof_distance := 12.0
@export var roof_probe_spacing := 3.0
@onready var wind: AudioStreamPlayer = $Wind
@onready var muffled_wind: AudioStreamPlayer = $MuffledWind
@onready var storm: AudioStreamPlayer = $Storm
var is_inside := false
var outside_blend := 1.0
var _camera: Camera3D
var _previous := Vector3.ZERO
var _last_roof_probe := Vector3.ZERO
var _portals: Array[Node] = []
var _storm_volumes: Array[Node] = []

func _ready() -> void:
	add_to_group("exterior_acoustics")
	_bind.call_deferred()

func _bind() -> void:
	_portals = get_tree().get_nodes_in_group("acoustic_portals")
	var sources := get_node_or_null(storm_sources_path)
	if sources != null:
		_storm_volumes = sources.find_children("StormHaze_*", "FogVolume", true, false)

func has_roof(point: Vector3) -> bool:
	# One roof probe on spawn/teleport or after walking several metres, never each frame.
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.1, point + Vector3.UP * initialization_roof_distance, 1)
	var camera := get_viewport().get_camera_3d()
	var excluded: Array[RID] = []
	if camera != null:
		var ancestor: Node = camera
		while ancestor != null:
			if ancestor is CollisionObject3D:
				excluded.append(ancestor.get_rid())
			ancestor = ancestor.get_parent()
	query.exclude = excluded
	return not get_viewport().find_world_3d().direct_space_state.intersect_ray(query).is_empty()

func update_listener(point: Vector3, delta: float, reset: bool = false) -> void:
	if reset or point.distance_to(_previous) > 4.0:
		is_inside = has_roof(point)
		_last_roof_probe = point
	else:
		var near_door := false
		for portal in _portals:
			near_door = near_door or portal.near_threshold(point)
			var side: int = portal.crossing(_previous, point)
			if side >= 0:
				is_inside = side == 1
		if not near_door and point.distance_to(_last_roof_probe) >= roof_probe_spacing:
			is_inside = has_roof(point)
			_last_roof_probe = point
	_previous = point
	outside_blend = move_toward(outside_blend, 0.0 if is_inside else 1.0, delta / maxf(fade_seconds, 0.01))

func storm_intensity(point: Vector3) -> float:
	var intensity := 0.0
	for volume in _storm_volumes:
		var local: Vector3 = volume.to_local(point)
		var size: Vector3 = volume.size * 0.5
		var radius := Vector2(local.x / maxf(size.x, 0.01), local.z / maxf(size.z, 0.01)).length()
		intensity = maxf(intensity, (1.0 - smoothstep(0.25, 1.8, radius)) * (1.0 - smoothstep(1.0, 2.0, absf(local.y) / maxf(size.y, 0.01))))
	return intensity

func mix_audio(delta: float, point: Vector3, active: bool = true) -> void:
	var outside := smoothstep(0.0, 1.0, outside_blend) if active else 0.0
	AudioFade.apply(wind, db_to_linear(wind_volume_db) * outside, delta, fade_seconds)
	AudioFade.apply(muffled_wind, db_to_linear(wind_volume_db) * sheltered_wind_gain * (1.0 - outside) if active else 0.0, delta, fade_seconds)
	AudioFade.apply(storm, db_to_linear(storm_volume_db) * storm_intensity(point) * outside, delta, fade_seconds)

func _physics_process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		update_listener(camera.global_position, delta, camera != _camera)
	_camera = camera
	mix_audio(delta, camera.global_position if camera != null else Vector3.ZERO, camera != null)
