extends Node3D
## Local, temporary contact effects. Terrain owns the snow receiver layer;
## replicated actor positions also produce tracks without extra network traffic.

@export var terrain_path: NodePath
@export var footprint_scene: PackedScene
@export var tread_scene: PackedScene
@export var ski_scene: PackedScene
@export_range(0.2, 2.0) var step_distance := 0.65
@export_range(0.2, 2.0) var track_distance := 0.85
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
		if remaining < fade_seconds:
			(mark.node as Decal).modulate.a = clampf(remaining / maxf(fade_seconds, 0.01), 0.0, 1.0)

func _sample(actor: CharacterBody3D, vehicle: bool) -> void:
	var id := actor.get_instance_id()
	var point := actor.global_position
	if not _actors.has(id):
		_actors[id] = {"position": point, "distance": 0.0, "left": false}
		return
	var state: Dictionary = _actors[id]
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
	if _contact(point, actor).is_empty():
		state.distance = 0.0
		return
	state.distance += distance
	var spacing := track_distance if vehicle else step_distance
	if float(state.distance) < spacing:
		return
	state.distance = fmod(float(state.distance), spacing)
	var forward := movement.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	if vehicle:
		forward = -actor.global_basis.z.normalized()
		right = actor.global_basis.x.normalized()
		_stamp(tread_scene, point - forward * tread_back_offset, forward, actor)
		for side in [-0.5, 0.5]:
			_stamp(ski_scene, point + forward * ski_forward_offset + right * ski_separation * side, forward, actor)
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
