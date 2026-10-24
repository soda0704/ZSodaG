extends CharacterBody3D

@export_group("Creature")
@export_range(0, 2) var monster_id: int = 0
@export_storage var model_id: String = "the_monster"
@export var ai_profile: MonsterAIProfile
@export_range(0.1, 3.0) var eye_height := 1.45
var encounter: Node
var health: float = 100.0
var visual: MonsterVisual
var agent: NavigationAgent3D
var _attack_left: float = 0.0
var _windup: float = 0.0
var _victim: Node3D
var _path_time: float = 0.0
var _network_time: float = 0.0
var _target_position := Vector3.ZERO
var _target_yaw: float = 0.0
var _moving: bool = false
var _home := Vector3.ZERO
var corpse: RigidBody3D
var ragdoll: SkeletalRagdoll
var death_elapsed := 0.0
var _death_started := false
var _restored := false
var _corpse_saved := false
var debug_spawned := false
var debug_health := 100.0
var _awareness := 0.0
var _alert_target: Node3D
var _last_seen := Vector3.ZERO
var _patrol_left := 0.0
var _patrol_goal := Vector3.ZERO
var _sight_left := 0.0
var _retreat_left := 0.0
var _visual_rest_transform := Transform3D.IDENTITY
enum AwarenessState { PATROL, INVESTIGATE, CHASE, SEARCH, RETURN_HOME }
var awareness_state: AwarenessState = AwarenessState.PATROL
var _has_interest := false
var _sees_target := false
var _search_left := 0.0
var _search_center := Vector3.ZERO
var _search_goal := Vector3.ZERO
var _returning_home := false
var _blocked_time := 0.0
var _travel_goal := Vector3.ZERO
var _travel_stop := 0.7
var _navigation_goal := Vector3.INF

func _ready() -> void:
	add_to_group("hostile_monsters")
	if ai_profile == null:
		push_error("Monster: assign an AI profile in Inspector")
		set_physics_process(false)
		return
	if debug_spawned:
		add_to_group("debug_spawned_monsters")
		debug_health = ai_profile.max_health
	health = ai_profile.max_health
	visual = $Visual
	visual.setup(model_id)
	_visual_rest_transform = visual.transform
	agent = $NavigationAgent3D
	_home = global_position
	_patrol_goal = _home
	_target_position = position

func _physics_process(delta: float) -> void:
	if not _restored and not debug_spawned:
		_restored = true
		var saved: Dictionary = encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
		if saved.has("transform"):
			global_transform = saved.transform
			_target_position = position
	health = debug_health if debug_spawned else encounter.get_monster_health(monster_id)
	if health <= 0.0:
		collision_layer = 0
		if not _death_started:
			_death_started = true
			var saved: Dictionary = encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
			if saved.get("settled", false):
				_corpse_saved = true
				death_elapsed = 8.0
				_create_corpse(true)
		death_elapsed += delta
		if corpse == null:
			_create_corpse(false)
		if corpse != null and multiplayer.is_server():
			global_transform = corpse.global_transform
			var corpse_settled := ragdoll.settled() if ragdoll != null else (corpse.linear_velocity.length() < 0.15 and corpse.angular_velocity.length() < 0.25)
			if death_elapsed >= 6.0 and corpse_settled and not _corpse_saved:
				_corpse_saved = true
				if ragdoll != null:
					ragdoll.freeze_all()
				if not debug_spawned:
					encounter.save_body(monster_id, global_transform, true, ragdoll.capture())
			_network_time += delta
			if _network_time >= 0.1:
				_network_time = 0.0
				for peer_id in encounter.get_ready_peers():
					_sync_corpse.rpc_id(peer_id, global_transform, ragdoll.capture())
		return
	if multiplayer.is_server():
		var nearby_weight := 0.0
		for item in get_tree().get_nodes_in_group("world_items"):
			if item is HeavyCarryProp: continue
			if item is WorldItemPickup and not item._collected and item.global_position.distance_to(global_position) < 0.8:
				item.linear_velocity += (item.global_position - global_position).normalized() * 1.2
				nearby_weight = maxf(nearby_weight, item.get_push_resistance())
		velocity.x *= 1.0 / (1.0 + nearby_weight * 0.05)
		velocity.z *= 1.0 / (1.0 + nearby_weight * 0.05)
		_update_behavior(delta)
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = 0
		var movement_start := global_position
		move_and_slide()
		_update_blocked(delta, movement_start)
		_moving = Vector2(velocity.x, velocity.z).length() > 0.2
		_network_time += delta
		if _network_time > 0.1:
			_network_time = 0.0
			for peer_id in encounter.get_ready_peers():
				_sync.rpc_id(peer_id, position, rotation.y, _moving, _windup)
	else:
		position = position.lerp(_target_position, minf(delta * 12.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(delta * 12.0, 1.0))
	visual.animate(delta, _moving, _windup > 0.0, false)

func _valid_actor(target: Node3D) -> bool:
	return is_instance_valid(target) and target is GamePlayer and not target.survival.dead and not target.is_sleeping_in_bunk() and absf(target.global_position.y - global_position.y) <= ai_profile.vertical_awareness

func _clear_segment(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, point + Vector3.UP, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _can_reach(target: Node3D, reach: float) -> bool:
	return _valid_actor(target) and global_position.distance_to(target.global_position) <= reach and _clear_segment(target.global_position)

func _project_navigation(point: Vector3) -> Vector3:
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var projected := NavigationServer3D.map_get_closest_point(map, point)
	return projected if projected.distance_to(point) <= ai_profile.navigation_projection_distance else Vector3.INF

func _move_towards(point: Vector3, speed: float, stop: float, delta: float) -> void:
	_travel_goal = point
	_travel_stop = stop
	agent.target_desired_distance = stop
	var direction := Vector3.ZERO
	if global_position.distance_to(point) > stop:
		var from := _project_navigation(global_position)
		var goal := _project_navigation(point)
		if from.is_finite() and goal.is_finite():
			_path_time -= delta
			if _path_time <= 0.0 or not _navigation_goal.is_finite() or _navigation_goal.distance_to(goal) > 1.0:
				_path_time = ai_profile.path_update_interval
				_navigation_goal = goal
				agent.target_position = goal
			# Always advance the agent on physics frames, even at the end of a path.
			var next := agent.get_next_path_position()
			if not agent.is_navigation_finished(): direction = next - global_position
		elif _clear_segment(point):
			# Debug actors without a navigation region may walk only visible routes.
			direction = point - global_position
		direction.y = 0.0
		direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not direction.is_zero_approx():
		rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * ai_profile.turn_speed, 1.0))

func _wander_point(center: Vector3, radius: float) -> Vector3:
	var from := _project_navigation(global_position)
	for attempt in 8:
		var angle := randf() * TAU
		var candidate := center + Vector3(cos(angle), 0, sin(angle)) * randf_range(radius * 0.4, radius)
		var goal := _project_navigation(candidate)
		if from.is_finite() and goal.is_finite():
			if absf(goal.y - global_position.y) > ai_profile.vertical_awareness: continue
			var path := NavigationServer3D.map_get_path(agent.get_navigation_map(), from, goal, true)
			if not path.is_empty() and path[-1].distance_to(goal) < 0.5 and global_position.distance_to(goal) > ai_profile.patrol_stop_distance:
				return goal
		elif _clear_segment(candidate):
			return candidate
	return global_position

func _forget_interest() -> void:
	_alert_target = null
	_has_interest = false
	_sees_target = false
	_awareness = 0.0
	_search_left = 0.0
	_returning_home = true
	_patrol_goal = _home
	_patrol_left = 0.0
	_path_time = 0.0

func _remember(point: Vector3, target: Node3D, duration: float, seen: bool) -> void:
	_alert_target = target
	_last_seen = point
	_awareness = duration
	_has_interest = true
	_sees_target = seen
	_search_left = 0.0
	_returning_home = false
	_path_time = 0.0 if not _navigation_goal.is_finite() or _navigation_goal.distance_to(point) > 1.0 else _path_time

func _update_behavior(delta: float) -> void:
	_attack_left = maxf(0.0, _attack_left - delta)
	var target := _find_target(delta)
	_travel_goal = global_position
	if _windup > 0.0:
		_windup = maxf(0.0, _windup - delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if _windup == 0.0 and _can_reach(_victim, ai_profile.attack_reach):
			_victim.survival.damage(ai_profile.attack_damage, "Атака существа")
			if ai_profile.behavior == MonsterAIProfile.Behavior.SKIRMISHER: _retreat_left = ai_profile.retreat_duration
		return
	if _has_interest:
		if _sees_target and target != null:
			awareness_state = AwarenessState.CHASE
			if _retreat_left > 0.0:
				_retreat_left = maxf(0.0, _retreat_left - delta)
				var away := (global_position - target.global_position).normalized()
				var retreat := global_position + away * ai_profile.retreat_distance
				_move_towards(retreat, ai_profile.chase_speed, 0.2, delta)
				return
			if global_position.distance_to(_last_seen) < ai_profile.attack_distance and _attack_left <= 0.0 and _can_reach(target, ai_profile.attack_reach):
				_victim = target
				_windup = ai_profile.attack_windup
				_attack_left = maxf(ai_profile.attack_cooldown, ai_profile.attack_windup)
			_move_towards(_last_seen, ai_profile.chase_speed, ai_profile.stop_distance, delta)
		elif _search_left > 0.0:
			awareness_state = AwarenessState.SEARCH
			_search_left = maxf(0.0, _search_left - delta)
			if _search_left <= 0.0:
				_forget_interest()
			elif global_position.distance_to(_search_goal) <= ai_profile.patrol_stop_distance:
				_search_goal = _wander_point(_search_center, ai_profile.search_radius)
			_move_towards(_search_goal, ai_profile.patrol_speed, ai_profile.patrol_stop_distance, delta)
			if Vector2(velocity.x, velocity.z).length() < 0.05: rotation.y += delta * ai_profile.turn_speed * 0.25
		else:
			awareness_state = AwarenessState.INVESTIGATE
			if global_position.distance_to(_last_seen) < 0.85:
				_start_search(_last_seen)
			_move_towards(_last_seen, ai_profile.chase_speed, 0.6, delta)
	elif _returning_home:
		awareness_state = AwarenessState.RETURN_HOME
		_move_towards(_home, ai_profile.patrol_speed, ai_profile.patrol_stop_distance, delta)
		if global_position.distance_to(_home) <= ai_profile.patrol_stop_distance:
			_returning_home = false
			_patrol_goal = _home
			_patrol_left = randf_range(ai_profile.patrol_interval_min, ai_profile.patrol_interval_max)
	else:
		awareness_state = AwarenessState.PATROL
		if global_position.distance_to(_patrol_goal) <= ai_profile.patrol_stop_distance:
			_patrol_left -= delta
			if _patrol_left <= 0.0:
				_patrol_goal = _wander_point(_home, ai_profile.patrol_radius)
				_patrol_left = randf_range(ai_profile.patrol_interval_min, ai_profile.patrol_interval_max)
		_move_towards(_patrol_goal, ai_profile.patrol_speed, ai_profile.patrol_stop_distance, delta)

func _start_search(center: Vector3) -> void:
	_search_center = center
	_search_goal = _wander_point(center, ai_profile.search_radius)
	_search_left = ai_profile.search_duration
	_awareness = maxf(_awareness, _search_left + 0.1)
	_path_time = 0.0

func _update_blocked(delta: float, previous: Vector3) -> void:
	var traveled := global_position - previous
	traveled.y = 0.0
	var wants_travel := global_position.distance_to(_travel_goal) > _travel_stop + 0.2
	_blocked_time = _blocked_time + delta if wants_travel and traveled.length() < 0.02 * delta else 0.0
	if _blocked_time < ai_profile.stuck_timeout: return
	_blocked_time = 0.0
	_path_time = 0.0
	if _has_interest and not _sees_target:
		_start_search(global_position)
	elif not _has_interest:
		_returning_home = false
		_patrol_goal = _wander_point(_home, ai_profile.patrol_radius)

func hear_noise(source: Node3D, point: Vector3, radius: float) -> void:
	if not ai_profile.hearing_enabled or not multiplayer.is_server() or health <= 0.0 or not is_visible_in_tree() or not is_instance_valid(source): return
	if source is GamePlayer and not _valid_actor(source): return
	radius *= ai_profile.hearing_multiplier
	if radius <= 0.0 or absf(point.y - global_position.y) > ai_profile.vertical_awareness or global_position.distance_to(point) > radius: return
	if not _clear_segment(point) and global_position.distance_to(point) > radius * ai_profile.occluded_hearing_multiplier: return
	# A sound gives an event position, never a live tracking feed through walls.
	if _valid_actor(_alert_target) and _can_see(_alert_target): return
	_remember(point, source if source is GamePlayer else null, ai_profile.hearing_memory, false)

func _find_target(delta: float) -> Node3D:
	_awareness = maxf(0.0, _awareness - delta)
	if not _valid_actor(_alert_target):
		_alert_target = null
		_sees_target = false
		_victim = null
		_windup = 0.0
	_sight_left -= delta
	if _sight_left <= 0.0:
		_sight_left = ai_profile.sight_interval
		var candidate: Node3D = _alert_target if _valid_actor(_alert_target) and _can_see(_alert_target) else encounter.closest_player(global_position, _can_see, ai_profile.sight_distance, ai_profile.vertical_awareness)
		_sees_target = candidate != null
		if candidate != null: _remember(candidate.global_position, candidate, ai_profile.sight_memory, true)
	if _awareness <= 0.0:
		if _has_interest: _forget_interest()
		_alert_target = null
	if _has_interest and ai_profile.behavior == MonsterAIProfile.Behavior.TERRITORIAL:
		if _last_seen.distance_to(_home) > ai_profile.territory_radius or global_position.distance_to(_home) > ai_profile.territory_radius: _forget_interest()
	return _alert_target

func _can_see(target: Node3D) -> bool:
	if not ai_profile.sight_enabled or not _valid_actor(target): return false
	var eye := global_position + Vector3.UP * eye_height
	var target_point: Vector3 = target.head.global_position if target is GamePlayer else target.global_position + Vector3.UP
	var offset := target_point - eye
	var distance := offset.length()
	if distance > ai_profile.sight_distance: return false
	var close_distance := ai_profile.crouched_awareness_distance if target is GamePlayer and target._is_crouching else ai_profile.close_awareness_distance
	if distance > close_distance and (-global_basis.z).dot(offset.normalized()) < cos(deg_to_rad(ai_profile.field_of_view * 0.5)): return false
	var query := PhysicsRayQueryParameters3D.create(eye, target_point, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func apply_weapon_damage(amount: float) -> void:
	if multiplayer.is_server() and health > 0.0:
		# Damage alone does not reveal an unseen shooter's position on another floor.
		var visible_attacker: Node3D = encounter.closest_player(global_position, _can_see, ai_profile.sight_distance, ai_profile.vertical_awareness)
		if visible_attacker != null: _remember(visible_attacker.global_position, visible_attacker, ai_profile.sight_memory, true)
		if amount > 0.0: _blood.rpc()
		if debug_spawned: _set_debug_health.rpc(maxf(0.0, debug_health - amount))
		else: encounter.damage_monster(monster_id, amount)

@rpc("authority", "call_local", "reliable")
func _blood() -> void:
	preload("res://scripts/gameplay/blood_effect.gd").spawn(self, global_position + Vector3.UP)

@rpc("authority", "call_local", "reliable")
func _set_debug_health(value: float) -> void:
	debug_health = value
	health = value

func _create_corpse(restored: bool) -> void:
	ragdoll = load("res://scenes/characters/ragdolls/%s.tscn" % model_id).instantiate()
	ragdoll.name = str(name) + "Ragdoll"
	encounter.add_child(ragdoll)
	ragdoll.global_transform = global_transform
	visual.reparent(ragdoll, false)
	if visual.animator != null:
		visual.animator.pause()
	var rig: Skeleton3D = visual.find_children("*", "Skeleton3D", true, false)[0]
	ragdoll.initialize(rig, multiplayer.is_server() and not restored, velocity)
	if debug_spawned and multiplayer.is_server():
		for body in ragdoll.bodies:
			body.freeze = false
			body.sleeping = false
		ragdoll.root_body.apply_central_impulse(Vector3(0, 1.5, 0))
	corpse = ragdoll.root_body
	if restored and not debug_spawned:
		var saved: Dictionary = encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
		ragdoll.apply_poses(saved.get("ragdoll", []))

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync_corpse(pose: Transform3D, bones: Array = []) -> void:
	global_transform = pose
	if corpse == null and health <= 0:
		_create_corpse(false)
	if ragdoll != null:
		ragdoll.apply_poses(bones)

func reset_enemy() -> void:
	if corpse != null:
		if ragdoll != null:
			ragdoll.clear_pose()
		visual.reparent(self, false)
		if ragdoll != null:
			ragdoll.queue_free()
			ragdoll = null
		else:
			corpse.queue_free()
		corpse = null
	visual.transform = _visual_rest_transform
	visual.death_time = 0
	death_elapsed = 0
	_death_started = false
	_corpse_saved = false
	collision_layer = 2
	global_transform = Transform3D(Basis.IDENTITY, _home)
	velocity = Vector3.ZERO
	_awareness = 0.0
	_has_interest = false
	_sees_target = false
	_search_left = 0.0
	_returning_home = false
	_patrol_goal = _home
	_patrol_left = 0.0
	_navigation_goal = Vector3.INF
	_blocked_time = 0.0
	_alert_target = null
	_victim = null
	_windup = 0.0
	_retreat_left = 0.0
	_attack_left = 0.0

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync(next_position: Vector3, yaw: float, moving: bool, windup: float) -> void:
	_target_position = next_position
	_target_yaw = yaw
	_moving = moving
	_windup = windup

func _exit_tree() -> void:
	if is_instance_valid(ragdoll):
		ragdoll.queue_free()
