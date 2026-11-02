class_name AcousticPortal
extends Node3D
## Local -Z is outdoors, +Z is indoors. The doorway volume is authored in scene.
@export var door_path: NodePath
@export var door_manager_path: NodePath
@export var wind_volume_db := -20.0
@export var fade_seconds := 0.45
@export var roof_probe_guard_distance := 3.0
@export var occlusion_interval := 0.25
@export var interior_leak_distance := 6.0
@export_range(0.0, 1.0) var interior_leak_gain := .65
@onready var volume: CollisionShape3D = $Passage/CollisionShape3D
@onready var wind: AudioStreamPlayer3D = $Wind
var _door: Node3D
var _manager: Node
var _occlusion_time := 0.0
var _path_clear := true
var _leak_probe_at := Vector3.INF
var _next_leak_probe := 0
var _leak_path_clear := false

func _ready() -> void:
	add_to_group("acoustic_portals")
	_door = get_node_or_null(door_path)
	_manager = get_node_or_null(door_manager_path)

func openness() -> float:
	if _door == null:
		return 0.0
	if _door.has_method("get_acoustic_openness"):
		return _door.get_acoustic_openness()
	if _manager != null and _manager.has_method("get_acoustic_openness_at"):
		return _manager.get_acoustic_openness_at(_door)
	return 0.0

## Returns -1 if no valid threshold crossing, 0 for outside, 1 for inside.
func crossing(from: Vector3, to: Vector3) -> int:
	var a := volume.to_local(from)
	var b := volume.to_local(to)
	if a.z * b.z > 0.0 or absf(b.z - a.z) < 0.0001:
		return -1
	var at := a.lerp(b, clampf(-a.z / (b.z - a.z), 0.0, 1.0))
	var half_size: Vector3 = (volume.shape as BoxShape3D).size * 0.5
	if absf(at.x) > half_size.x or absf(at.y) > half_size.y:
		return -1
	return 1 if b.z > a.z else 0

func near_threshold(point: Vector3) -> bool:
	var local := volume.to_local(point).abs()
	var half_size: Vector3 = (volume.shape as BoxShape3D).size * 0.5
	return local.x < half_size.x + 1.0 and local.y < half_size.y + 0.5 and local.z < roof_probe_guard_distance

func wind_path_clear(camera: Camera3D) -> bool:
	var excluded: Array[RID] = []
	var ancestor: Node = camera
	while ancestor != null:
		if ancestor is CollisionObject3D:
			excluded.append(ancestor.get_rid())
		ancestor = ancestor.get_parent()
	var target := wind.global_position + global_basis.z.normalized() * 0.35
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, target, 1, excluded)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func interior_gain_at(camera: Camera3D) -> float:
	var opened := openness()
	var distance := camera.global_position.distance_to(wind.global_position)
	if opened <= .001 or distance >= interior_leak_distance: return 0.0
	# Reuse the real doorway and its collision, without a second alarm player/clock.
	var now := Time.get_ticks_msec()
	if now >= _next_leak_probe or camera.global_position.distance_squared_to(_leak_probe_at) > .25:
		_leak_probe_at = camera.global_position
		_next_leak_probe = now + roundi(occlusion_interval * 1000)
		_leak_path_clear = wind_path_clear(camera)
	if not _leak_path_clear: return 0.0
	return opened * interior_leak_gain * (1.0 - smoothstep(0.0, interior_leak_distance, distance))

func update_audio(delta: float) -> void:
	var acoustics := get_tree().get_first_node_in_group("exterior_acoustics")
	var indoors: bool = acoustics != null and acoustics.is_inside
	var camera := get_viewport().get_camera_3d()
	var nearby := camera != null and camera.global_position.distance_to(wind.global_position) < wind.max_distance
	_occlusion_time += delta
	if indoors and nearby and _occlusion_time >= occlusion_interval:
		_occlusion_time = 0.0
		_path_clear = wind_path_clear(camera)
	AudioFade.apply(wind, db_to_linear(wind_volume_db) * openness() if indoors and nearby and _path_clear else 0.0, delta, fade_seconds)

func _physics_process(delta: float) -> void:
	update_audio(delta)
