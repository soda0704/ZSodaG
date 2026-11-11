@tool
extends RefCounted
## Slow spatial selection; pulse/fault energy is applied separately every frame.
## Visible illuminated surfaces take priority, even beyond the player's room.
const REFRESH_SECONDS := 0.12
const SEARCH_DISTANCE := 128.0
const NEAR_DISTANCE := 14.0
var host: Node3D
var targets: Dictionary = {}
var _elapsed := REFRESH_SECONDS
var _at := Vector3.INF
var _dirty := true
var _direction := Vector3.ZERO

func _init(controller: Node3D) -> void:
	host = controller

func invalidate() -> void:
	_dirty = true

func remove(lamp: Light3D) -> void:
	targets.erase(lamp)
	invalidate()

func update(at: Vector3, delta: float) -> Dictionary:
	_elapsed += delta
	var camera := host.get_viewport().get_camera_3d()
	var direction := -camera.global_basis.z if camera != null else Vector3.ZERO
	if not _dirty and _elapsed < REFRESH_SECONDS and at.distance_squared_to(_at) < 0.25 and direction.dot(_direction) > 0.96:
		return targets
	_elapsed = 0.0
	_at = at
	_dirty = false
	_direction = direction
	targets.clear()
	var candidates: Array[Dictionary] = []
	var rooms := host.get_parent().get_node_or_null("WorldIndirectLighting") if host.get_parent() != null else null
	for lamp: Light3D in host._lamps:
		var parent := lamp.get_parent_node_3d()
		if not bool(host._lamp_enabled[lamp]) or (parent != null and not parent.is_visible_in_tree()): continue
		var distance_sq := lamp.global_position.distance_squared_to(at)
		var radius: float = host.lamp_range(lamp)
		if distance_sq >= SEARCH_DISTANCE * SEARCH_DISTANCE or absf(lamp.global_position.y - at.y) > radius: continue
		# No pulse or current light_energy here: a zero alarm envelope must not
		# evict the lamp and make its next flash rebuild the shadow atlas.
		var score := 1.0 / (0.5 + distance_sq / maxf(radius * radius, 0.01))
		if host._resident_lamps.has(lamp): score *= 1.12
		# An open hall may have a central shaft hiding the opposite fixtures,
		# although their illuminated surfaces remain visible around that shaft.
		var shared_room := false
		var room_id := str(lamp.get_meta("lighting_room", ""))
		if rooms != null and not room_id.is_empty():
			var room := rooms.get_node_or_null(NodePath(room_id)) as VoxelGI
			if room != null: shared_room = AABB(-room.size * 0.5, room.size).has_point(room.to_local(at))
		if shared_room: score *= 3.0
		candidates.append({"lamp": lamp, "score": score, "reachable": shared_room, "visible_surface": false})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	# Geometry-aware priority prevents lamps across a wall from evicting this
	# room's lamps. Nearby open doorways are sampled without using view direction.
	var space := host.get_world_3d().direct_space_state
	var excludes: Array[RID] = []
	if camera != null: excludes = host._exclude_body(camera)
	var visible_points: Array[Vector3] = []
	if camera != null:
		var size := camera.get_viewport().get_visible_rect().size
		# Real visible walls/floors also count when furniture hides all five
		# points below a fixture. Offset hits toward their receiving surface.
		for x in 9:
			for y in 5:
				var pixel := size * Vector2((x + 0.5) / 9.0, (y + 0.5) / 5.0)
				var ray := PhysicsRayQueryParameters3D.create(at, at + camera.project_ray_normal(pixel) * SEARCH_DISTANCE, 1, excludes)
				var hit := space.intersect_ray(ray)
				if not hit.is_empty(): visible_points.append(hit.position + hit.normal * 0.04)
	var anchors: Array[Vector3] = [at]
	if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at - Vector3.UP * 0.8, 1, excludes)).is_empty(): anchors.append(at - Vector3.UP * 0.8)
	for offset in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + offset, 1, excludes)).is_empty(): anchors.append(at + offset)
	for index in candidates.size():
		var lamp: Light3D = candidates[index].lamp
		var reachable: bool = candidates[index].reachable
		var visible_surface := false
		# Test the illuminated space, rather than the ceiling fixture alone.
		# Door headers can hide a lamp whose far floor is clearly visible.
		if camera != null:
			var radius: float = host.lamp_range(lamp)
			var floor_y := floorf((lamp.global_position.y + 8.0) / 18.0) * 18.0
			var center := Vector3(lamp.global_position.x, maxf(floor_y + 0.35, at.y - 0.8), lamp.global_position.z)
			for offset in [Vector3.ZERO, Vector3(radius * 0.45, 0, 0), Vector3(-radius * 0.45, 0, 0), Vector3(0, 0, radius * 0.45), Vector3(0, 0, -radius * 0.45)]:
				var point: Vector3 = center + offset
				var beam := point - lamp.global_position
				if beam.length_squared() > radius * radius: continue
				if lamp is SpotLight3D and beam.length_squared() > 0.001 and (-lamp.global_basis.z).dot(beam.normalized()) < cos(deg_to_rad(lamp.spot_angle)): continue
				if not camera.is_position_in_frustum(point): continue
				var ray := PhysicsRayQueryParameters3D.create(at, point, 1, excludes)
				if not space.intersect_ray(ray).is_empty(): continue
				ray.from = lamp.global_position
				if not space.intersect_ray(ray).is_empty(): continue
				visible_surface = true
				break
			if not visible_surface:
				for point in visible_points:
					var beam := point - lamp.global_position
					if beam.length_squared() > radius * radius: continue
					if lamp is SpotLight3D and beam.length_squared() > 0.001 and (-lamp.global_basis.z).dot(beam.normalized()) < cos(deg_to_rad(lamp.spot_angle)): continue
					if space.intersect_ray(PhysicsRayQueryParameters3D.create(lamp.global_position, point, 1, excludes)).is_empty():
						visible_surface = true
						break
			candidates[index].visible_surface = visible_surface
			if visible_surface: reachable = true
		# Retain local/offscreen illumination for GI and turns. Distant hidden
		# rooms need neither a light nor a shadow-map allocation.
		if lamp.global_position.distance_squared_to(at) > NEAR_DISTANCE * NEAR_DISTANCE and camera != null and not visible_surface and not reachable: continue
		for point in anchors:
			var offset: Vector3 = point - lamp.global_position
			var distance := offset.length()
			var inside_beam: bool = distance <= host.lamp_range(lamp)
			if lamp is SpotLight3D and distance > 0.05:
				inside_beam = inside_beam and (-lamp.global_basis.z).dot(offset / distance) >= cos(deg_to_rad(lamp.spot_angle))
			# Trace in the light's direction: one-sided imported collision faces
			# must agree with the propagation test used for room coverage.
			var direct := inside_beam and space.intersect_ray(PhysicsRayQueryParameters3D.create(lamp.global_position, point, 1, excludes)).is_empty()
			# A ceiling lamp can be hidden by a beam/pillar while its illuminated
			# floor remains visible. This also applies beyond the beam's reach to
			# the viewer: the far end of an open corridor still needs its lamps.
			var floor_point := Vector3(lamp.global_position.x, point.y, lamp.global_position.z)
			var same_room := absf(lamp.global_position.y - point.y) < 8.0 and space.intersect_ray(PhysicsRayQueryParameters3D.create(point, floor_point, 1, excludes)).is_empty()
			if direct or same_room:
				reachable = true
				break
		# Still retain indirect sources at door edges, but behind reachable ones.
		if reachable:
			candidates[index].score *= 8.0
			candidates[index].reachable = true
		if visible_surface: candidates[index].score += 100.0
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var slots := 0
	var has_reachable := candidates.any(func(entry: Dictionary) -> bool: return entry.reachable)
	for entry in candidates:
		# Opaque adjacent rooms need no shadow maps in this view. If the player
		# stands in a fully occluded recess, keep two nearby sources for bounce.
		if has_reachable and not entry.reachable: continue
		if not has_reachable and targets.size() >= 2: break
		var lamp: Light3D = entry.lamp
		var cost: int = host.shadow_slot_cost(lamp)
		if targets.size() >= host.MAX_ACTIVE_LAMPS: break
		if slots + cost > host.MAX_ACTIVE_SHADOW_SLOTS: continue
		# Visible lights keep their authored energy. Distance dimming made the
		# alarm at the end of a corridor visibly switch on as the player approached.
		targets[lamp] = 1.0
		slots += cost
	return targets
