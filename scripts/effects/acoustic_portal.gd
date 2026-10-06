class_name AcousticPortal
extends Node3D
## Local -Z is outdoors, +Z is indoors. The doorway volume is authored in scene.
@export var door_path: NodePath
@export var door_manager_path: NodePath
@export var wind_volume_db := -20.0
@export var fade_seconds := 0.45
@export var roof_probe_guard_distance := 3.0
@export var occlusion_interval := 0.25
@onready var volume: CollisionShape3D = $Passage/CollisionShape3D
@onready var wind: AudioStreamPlayer3D = $Wind
var _door: Node3D
var _manager: Node
var _occlusion_time := 0.0
var _path_clear := true

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
