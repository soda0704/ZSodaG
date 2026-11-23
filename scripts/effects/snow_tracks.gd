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

@export var deformable_snow := false

var _powder_grain: SphereMesh
var _powder_scale: Curve
var _powder_mist: QuadMesh
var _mist_scale: Curve
var _mist_color: Gradient
const SnowDeformation := preload("res://scripts/effects/snow_deformation.gd")
const SnowDriftProfile := preload("res://scripts/effects/snow_drift_profile.gd")
const SnowSurfaceTiles := preload("res://scripts/effects/snow_surface_tiles.gd")
var _snow_profile := SnowDriftProfile.new()
var _snow_deformation: SnowDeformation
var _snow_material: Terrain3DMaterial
var _snow_tiles: SnowSurfaceTiles
var _terrain: Node3D
var _actors: Dictionary = {}
var _marks: Array[Dictionary] = []
var _clock := 0.0

func _ready() -> void:
	_terrain = get_node_or_null(terrain_path)

func _physics_process(delta: float) -> void:
	# Incremental world loading temporarily detaches Terrain3D. Resolve it again
	# once loading finishes instead of permanently disabling the track sampler.
	if not is_instance_valid(_terrain):
		_terrain = get_node_or_null(terrain_path)
		if _terrain == null:
			return
	_clock += delta
	if deformable_snow and _snow_deformation == null and _terrain is Terrain3D:
		_snow_deformation = SnowDeformation.new()
		_snow_tiles = SnowSurfaceTiles.new()
		_snow_material = (_terrain as Terrain3D).material
		_snow_material.set_shader_param("snow_deformation", _snow_deformation.texture)
		_snow_material.set_shader_param("snow_tile_count", 0)
		_snow_material.set_shader_param("fine_snow_tile_count", 0)
	while _marks.size() > max_marks:
		_remove_oldest()
	var present: Dictionary = {}
	for group in [&"network_players", &"snowmobiles"]:
		for actor in get_tree().get_nodes_in_group(group):
			if actor is CharacterBody3D:
				present[actor.get_instance_id()] = true
				_sample(actor, group == &"snowmobiles")
	if _snow_deformation != null:
		_snow_deformation.flush(_snow_material, _clock)
		_snow_tiles.update(self, _terrain as Terrain3D, _snow_deformation._origins, _clock)
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
		(mark.node as Decal).modulate.a = float(mark.opacity) * clampf(remaining / maxf(fade_seconds, 0.01), 0.0, 1.0)

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
		state.erase("snow_position")
		state.erase("snow_pose")
		return
	movement.y = 0.0
	if vehicle and not actor.is_on_floor():
		state.erase("snow_pose")
	var distance := movement.length()
	if distance < 0.001:
		return
	if not vehicle and _contact(point, actor).is_empty():
		state.distance = 0.0
		state.erase("snow_position")
		return
	if not vehicle and _snow_deformation != null:
		var last_snow_point: Vector3 = state.get("snow_position", previous_point)
		state.snow_position = last_snow_point
		if Vector2(point.x - last_snow_point.x, point.z - last_snow_point.z).length() >= 0.12:
			_snow_deformation.push_snow(last_snow_point, point, _clock)
			state.snow_position = point
	if vehicle and _snow_deformation != null:
		_sample_vehicle_snow(actor, state, previous_pose)
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

func _sample_vehicle_snow(actor: CharacterBody3D, state: Dictionary, previous_pose: Transform3D) -> void:
	if not actor.is_on_floor() or not actor.has_method("get_snow_contact_markers"):
		state.erase("snow_pose")
		return
	var pose := actor.global_transform
	var start: Transform3D = state.get("snow_pose", previous_pose)
	state.snow_pose = start
	if Vector2(pose.origin.x - start.origin.x, pose.origin.z - start.origin.z).length_squared() < 0.22 * 0.22:
		return
	state.snow_pose = pose
	var markers: Array = actor.call("get_snow_contact_markers")
	for index in markers.size():
		var marker := markers[index] as Marker3D
		var contact := marker.global_position
		if not _contact(contact, actor, 0.5).is_empty():
			_snow_deformation.push_snow(start * actor.to_local(contact), contact, _clock, 0.74 if index == 0 else 0.34)

func _contact(point: Vector3, actor: CharacterBody3D, tolerance: float = 0.0) -> Dictionary:
	var allowed_height := maxf(contact_tolerance, tolerance)
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.4, point - Vector3.UP * 0.55, 1, [actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.collider != _terrain or absf(point.y - Vector3(hit.position).y) > allowed_height:
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
	if scene == footprint_scene:
		var p: Vector3 = hit.position
		var packed := SnowDeformation.packed_at(Vector2(p.x, p.z))
		var powder := 1.0 - packed
		var depth := _snow_profile.depth_for_walking(Vector2(p.x, p.z)) if deformable_snow else 0.0
		mark.modulate.a = lerpf(0.50, 1.0, powder)
		mark.albedo_mix = lerpf(0.52, 0.87, powder)
		mark.size *= Vector3(1.0 + 0.17 * powder, 1.0, 1.0 + 0.12 * powder)
		mark.size.y += depth
		mark.global_position += normal * depth * 0.5
		if packed < 0.6 and normal.y > 0.8:
			var camera := get_viewport().get_camera_3d()
			if camera != null and camera.global_position.distance_squared_to(p) < 18.0 * 18.0:
				var travel := actor.velocity.slide(normal)
				var impulse := clampf(travel.length() / 6.0, 0.0, 1.0)
				var direction := normal - travel.normalized() * lerpf(0.25, 0.72, impulse)
				_emit_powder(p + normal * (0.045 + depth * 0.29), direction, powder, impulse, depth)
	elif scene == tread_scene and deformable_snow and actor.is_on_floor():
		var p: Vector3 = hit.position
		var camera := get_viewport().get_camera_3d()
		var depth := _snow_profile.depth_for_walking(Vector2(p.x, p.z))
		if depth > 0.08 and camera != null and camera.global_position.distance_squared_to(p) < 18.0 * 18.0:
			var travel := actor.velocity.slide(normal)
			var speed := travel.length()
			if speed > 2.0:
				var displaced := smoothstep(2.0, 12.0, speed) * smoothstep(0.08, 0.65, depth)
				_emit_snow_mist(p + normal * (0.10 + depth * 0.25), normal - travel.normalized(), displaced)
	_marks.append({"node": mark, "born": _clock, "opacity": mark.modulate.a})

func _emit_powder(point: Vector3, direction: Vector3, powder: float, impulse: float, depth: float) -> void:
	if _powder_grain == null:
		_powder_grain = SphereMesh.new()
		_powder_grain.radius = 0.014
		_powder_grain.height = 0.022
		_powder_grain.radial_segments = 5
		_powder_grain.rings = 3
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.86, 0.91, 0.96)
		material.roughness = 0.95
		_powder_grain.material = material
		_powder_scale = Curve.new()
		_powder_scale.add_point(Vector2(0.0, 0.85))
		_powder_scale.add_point(Vector2(0.2, 1.0))
		_powder_scale.add_point(Vector2(0.65, 0.65))
		_powder_scale.add_point(Vector2(1.0, 0.0))

	var puff := CPUParticles3D.new()
	puff.emitting = false
	puff.one_shot = true
	var loose_depth := smoothstep(0.04, SnowDriftProfile.DEPTH_RANGE, depth)
	var displaced := powder * lerpf(0.30, 1.0, loose_depth) * lerpf(0.5, 1.0, impulse)
	puff.amount = roundi(lerpf(4.0, 21.0, displaced))
	puff.lifetime = 0.42
	puff.explosiveness = 1.0
	puff.direction = direction.normalized()
	puff.spread = 58.0
	puff.initial_velocity_min = 0.25
	puff.initial_velocity_max = lerpf(0.52, 1.75, displaced)
	puff.gravity = Vector3.DOWN * 5.0
	puff.scale_amount_curve = _powder_scale
	puff.scale_amount_min = 0.36
	puff.scale_amount_max = 1.0
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	puff.mesh = _powder_grain
	add_child(puff)
	puff.global_position = point
	puff.finished.connect(puff.queue_free)
	puff.emitting = true
	_emit_snow_mist(point, direction, displaced)

func _emit_snow_mist(point: Vector3, direction: Vector3, displaced: float) -> void:
	if _powder_mist == null:
		var mask := GradientTexture2D.new()
		mask.fill = GradientTexture2D.FILL_RADIAL
		mask.fill_from = Vector2(0.5, 0.5)
		mask.fill_to = Vector2(1.0, 0.5)
		mask.gradient = Gradient.new()
		mask.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
		mask.gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.vertex_color_use_as_albedo = true
		material.albedo_texture = mask
		_powder_mist = QuadMesh.new()
		_powder_mist.size = Vector2(0.86, 0.54)
		_powder_mist.material = material
		_mist_scale = Curve.new()
		_mist_scale.add_point(Vector2(0.0, 0.42))
		_mist_scale.add_point(Vector2(1.0, 1.0))
		_mist_color = Gradient.new()
		_mist_color.offsets = PackedFloat32Array([0.0, 0.16, 0.56, 1.0])
		_mist_color.colors = PackedColorArray([
			Color(0.83, 0.90, 0.96, 0.0), Color(0.83, 0.90, 0.96, 0.21),
			Color(0.83, 0.90, 0.96, 0.12), Color(0.83, 0.90, 0.96, 0.0)
		])
	var mist := CPUParticles3D.new()
	mist.emitting = false
	mist.one_shot = true
	mist.amount = roundi(lerpf(4.0, 8.0, displaced))
	mist.explosiveness = 0.88
	mist.lifetime = lerpf(0.65, 1.10, displaced)
	mist.mesh = _powder_mist
	mist.color_ramp = _mist_color
	mist.scale_amount_curve = _mist_scale
	mist.scale_amount_min = 0.48
	mist.scale_amount_max = lerpf(0.75, 1.25, displaced)
	mist.direction = direction.normalized()
	mist.spread = 62.0
	mist.initial_velocity_min = 0.24
	mist.initial_velocity_max = lerpf(0.45, 0.93, displaced)
	mist.gravity = Vector3(0.33, -0.32, 0.13)
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)
	mist.global_position = point
	mist.finished.connect(mist.queue_free)
	mist.emitting = true

func _remove_oldest() -> void:
	var mark: Dictionary = _marks.pop_front()
	(mark.node as Decal).queue_free()
