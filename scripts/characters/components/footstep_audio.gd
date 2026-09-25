extends AudioStreamPlayer3D
@export var floor_sounds: Array[AudioStream] = []
@export var snow_sounds: Array[AudioStream] = []
@export var metal_sounds: Array[AudioStream] = []
@export var stride := 1.65
var previous := Vector3.ZERO
var distance := 0.0
var initialized := false
func _physics_process(_delta: float) -> void:
	var actor := get_parent() as CharacterBody3D
	if actor == null:
		return
	var point := actor.global_position
	var movement := point - previous
	previous = point
	if not initialized:
		initialized = true
		return
	if movement.length() > 4.0 or (actor is GamePlayer and (actor.debug_fly or actor.debug_across or actor.is_driving() or actor.survival.dead)):
		distance = 0.0
		return
	movement.y = 0.0
	if movement.length() < 0.001:
		return
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.2, point - Vector3.UP * 0.3, 1, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		distance = 0.0
		return
	distance += movement.length()
	if distance < stride:
		return
	distance = fmod(distance, stride)
	var surface := "floor"
	var node := hit.collider as Node
	while node != null:
		if node.is_class("Terrain3D"):
			surface = "snow"
			break
		if node.has_meta("footstep_surface"):
			surface = str(node.get_meta("footstep_surface"))
			break
		node = node.get_parent()
	var clips := snow_sounds if surface == "snow" else metal_sounds if surface == "metal" else floor_sounds
	if clips.is_empty():
		return
	stream = clips.pick_random()
	pitch_scale = randf_range(0.96, 1.04)
	play()
