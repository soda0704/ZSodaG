extends Node3D
## Local, temporary contact effects. Terrain owns the snow receiver layer;
## replicated actor positions also produce tracks without extra network traffic.

@export var terrain_path: NodePath
@export var footprint_scene: PackedScene
@export var tread_scene: PackedScene
@export var ski_scene: PackedScene
@export_range(0.2, 2.0) var step_distance := 0.65
@export_range(0.2, 2.0) var track_distance := 0.55
@export_range(16, 1024) var max_marks := 512
@export var lifetime := 75.0
@export var fade_seconds := 10.0
@export var contact_tolerance := 0.25
@export var ski_separation := 1.1
@export var ski_forward_offset := 0.85
@export var tread_back_offset := 0.5

var _terrain: Node3D
var _actors: Dictionary = {}
var _marks: Array[Dictionary] = []
var _clock := 0.0

func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)
	if _terrain == null:
		set_physics_process(false)

func _physics_process(delta: float) -> void:
	_clock += delta
	while _marks.size() > max_marks:
		_remove_oldest()
	var present: Dictionary = {}
	for group in [&"network_players", &"snowmobiles"]:
		for actor in get_tree().get_nodes_in_group(group):
			if actor is CharacterBody3D:
				present[actor.get_instance_id()] = true
				_sample(actor, group == &"snowmobiles")
	for id in _actors.keys():
		if not present.has(id):
			_actors.erase(id)
	while not _marks.is_empty() and _clock - float(_marks[0].born) >= lifetime:
		_remove_oldest()
	for mark in _marks:
		var remaining := lifetime - (_clock - float(mark.born))
		# Marks are ordered by birth: newer marks cannot be fading yet.
		if remaining >= fade_seconds:
			break
		(mark.node as Decal).modulate.a = clampf(remaining / maxf(fade_seconds, 0.01), 0.0, 1.0)

func _sample(actor: CharacterBody3D, vehicle: bool) -> void:
	var id := actor.get_instance_id()
	var point := actor.global_position
	if not _actors.has(id):
		_actors[id] = {"position": point, "pose": actor.global_transform, "distance": 0.0, "left": false}
		return
	var state: Dictionary = _actors[id]
	var previous_pose: Transform3D = state.pose
	state.pose = actor.global_transform
	var previous_point: Vector3 = state.position
	var movement: Vector3 = point - Vector3(state.position)
	state.position = point
	var blocked := false
	if actor is GamePlayer:
		blocked = actor.debug_fly or actor.debug_across or actor.is_driving() or (actor.survival != null and actor.survival.dead)
	# Reset on jumps, teleports and transitions off snow: no connecting streaks.
	if blocked or movement.length() > 4.0:
		state.distance = 0.0
		return
	movement.y = 0.0
	var distance := movement.length()
	if distance < 0.001:
		return
	if not vehicle and _contact(point, actor).is_empty():
		state.distance = 0.0
		return
	var carried: float = state.distance
	state.distance += distance
	var spacing := track_distance if vehicle else step_distance
	if float(state.distance) < spacing:
		return
	var sample_count := mini(int(float(state.distance) / spacing), 8)
	state.distance = fmod(float(state.distance), spacing)
	# Feet keep the body's heading when backpedalling or strafing.
	# Movement determines step spacing, not the direction the toes face.
	var forward := -actor.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if vehicle:
		var contacts: Array = []
		if actor.has_method("get_snow_contact_markers"):
			contacts = actor.call("get_snow_contact_markers")
		# Interpolate the travelled segment so fast movement does not leave dotted trails.
		for sample in sample_count:
			var t := clampf((spacing-carried+sample*spacing)/distance, 0.0, 1.0)
			var pose := previous_pose.interpolate_with(actor.global_transform, t)
			var heading := -pose.basis.z.normalized()
			if not contacts.is_empty():
				for i in contacts.size():
					var local_point := actor.to_local((contacts[i] as Marker3D).global_position)
					var contact_basis: Basis = actor.global_basis.inverse() * contacts[i].global_basis
					var contact_heading := -(pose.basis * contact_basis).z.normalized()
					_stamp(tread_scene if i == 0 else ski_scene, pose*local_point, contact_heading, actor)
			else:
				var center := previous_point.lerp(point, t)
				_stamp(tread_scene, center-heading*tread_back_offset, heading, actor)
				for side in [-0.5, 0.5]:
					_stamp(ski_scene, center+heading*ski_forward_offset+pose.basis.x*ski_separation*side, heading, actor)
	else:
		state.left = not bool(state.left)
		_stamp(footprint_scene, point + right * (-0.13 if state.left else 0.13), forward, actor)

func _contact(point: Vector3, actor: CharacterBody3D) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP * 0.55, 1, [actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != _terrain or absf(point.y - Vector3(hit.position).y) > contact_tolerance:
		return {}
	return hit

func _stamp(scene: PackedScene, point: Vector3, forward: Vector3, actor: CharacterBody3D) -> void:
	if scene == null:
		return
	var hit := _contact(point, actor)
	if hit.is_empty():
		return
	while _marks.size() >= max_marks:
		_remove_oldest()
	var mark := scene.instantiate() as Decal
	add_child(mark)
	var normal: Vector3 = hit.normal
	var z := -forward.slide(normal).normalized()
	var x := normal.cross(z).normalized()
	mark.global_transform = Transform3D(Basis(x, normal, z), Vector3(hit.position) + normal * 0.025)
	_marks.append({"node": mark, "born": _clock})

func _remove_oldest() -> void:
	var mark: Dictionary = _marks.pop_front()
	(mark.node as Decal).queue_free()
