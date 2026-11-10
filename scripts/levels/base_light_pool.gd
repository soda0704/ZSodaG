@tool
extends RefCounted
## Slow spatial selection; pulse/fault energy is applied separately every frame.
## Selection is independent of camera rotation and the alarm's silent interval.
const REFRESH_SECONDS := 0.12
const SEARCH_DISTANCE := 32.0
const FADE_START := 24.0
var host: Node3D
var targets: Dictionary = {}
var _elapsed := REFRESH_SECONDS
var _at := Vector3.INF
var _dirty := true

func _init(controller: Node3D) -> void:
	host = controller

func invalidate() -> void:
	_dirty = true

func remove(lamp: Light3D) -> void:
	targets.erase(lamp)
	invalidate()

func update(at: Vector3, delta: float) -> Dictionary:
	_elapsed += delta
	if not _dirty and _elapsed < REFRESH_SECONDS and at.distance_squared_to(_at) < 0.25:
		return targets
	_elapsed = 0.0
	_at = at
	_dirty = false
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
		candidates.append({"lamp": lamp, "score": score, "reachable": shared_room})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	# Geometry-aware priority prevents lamps across a wall from evicting this
	# room's lamps. Nearby open doorways are sampled without using view direction.
	var space := host.get_world_3d().direct_space_state
	var excludes: Array[RID] = []
	var camera := host.get_viewport().get_camera_3d()
	if camera != null: excludes = host._exclude_body(camera)
	var anchors: Array[Vector3] = [at]
	if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at - Vector3.UP * 0.8, 1, excludes)).is_empty(): anchors.append(at - Vector3.UP * 0.8)
	for offset in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + offset, 1, excludes)).is_empty(): anchors.append(at + offset)
	for index in mini(candidates.size(), 24):
		var lamp: Light3D = candidates[index].lamp
		var reachable: bool = candidates[index].reachable
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
		targets[lamp] = 1.0 - smoothstep(FADE_START, SEARCH_DISTANCE, lamp.global_position.distance_to(at))
		slots += cost
	return targets
