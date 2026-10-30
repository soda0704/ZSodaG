extends CharacterBody3D

@export_group("Creature")
@export_range(0, 4) var monster_id: int = 0
@export_storage var model_id: String = "the_monster"
@export var ai_profile: MonsterAIProfile
@export_range(0.1, 3.0) var eye_height := 1.45
@export var ragdoll_scene: PackedScene
@export_group("Scenario control")
@export var ai_enabled := true
## Markers are relative to this actor; empty uses the existing local random patrol.
@export var patrol_point_paths: Array[NodePath] = []
@export var patrol_ping_pong := false
signal awareness_changed(previous: int, current: int)
signal target_spotted(target: Node3D)
signal target_lost(last_position: Vector3)
signal attack_started(target: Node3D, duration: float)
signal attack_finished(target: Node3D, landed: bool)
signal navigation_blocked(destination: Vector3, attempts: int)
signal health_changed(current: float, maximum: float)
signal encounter_resolved(reason: String)
signal scripted_move_finished(destination: Vector3)

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
var _replicated_speed := 0.0
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
enum AwarenessState {
	PATROL,
	INVESTIGATE,
	CHASE,
	SEARCH,
	RETURN_HOME,
	ATTACK,
	RECOVER,
	STUNNED,
	SCRIPTED_MOVE,
	DORMANT,
	RESOLVED,
	DEAD
}
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
var _candidate_target: Node3D
var _confirmed_target: Node3D
var _candidate_exposure := 0.0
var _recovery_left := 0.0
var _stun_left := 0.0
var _search_pause_left := 0.0
var _progress_origin := Vector3.ZERO
var _path_retries := 0
var _ignored_target: Node3D
var _ignore_left := 0.0
var _wants_move := false
var _safe_velocity := Vector3.ZERO
var _scripted_goal := Vector3.INF
var _scripted_speed := 0.0
var _resolve_on_arrival := false
var _scripted_reason := "withdrawn"
var _resolution_reason := ""
var _resolution_hidden := true
var _patrol_markers: Array[Node3D] = []
var _patrol_index := -1
var _patrol_direction := 1
var _patrol_pause_override := Vector2(-1.0, -1.0)
var _home_transform := Transform3D.IDENTITY
var _living_collision_layer := 2
var _corpse_attempted := false


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
	_living_collision_layer = collision_layer
	visual = get_node_or_null("Visual") as MonsterVisual
	if visual != null:
		visual.setup(model_id)
	_visual_rest_transform = visual.transform if visual != null else Transform3D.IDENTITY
	agent = $NavigationAgent3D
	configure_navigation()
	for path in patrol_point_paths:
		var marker := get_node_or_null(path) as Node3D
		if marker != null:
			_patrol_markers.append(marker)
		else:
			push_warning("Monster: missing patrol marker " + str(path))
	_home_transform = global_transform
	_home = global_position
	_progress_origin = global_position
	_patrol_goal = _home
	_target_position = position


func _physics_process(delta: float) -> void:
	if not _restored and _has_story_state():
		_restored = true
		var saved: Dictionary = (
			encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
			if _has_story_state()
			else {}
		)
		if saved.has("transform"):
			global_transform = saved.transform
			_target_position = position
	var previous_health := health
	health = (
		debug_health
		if debug_spawned
		else encounter.get_monster_health(monster_id) if _has_story_state() else health
	)
	if previous_health != health:
		health_changed.emit(health, ai_profile.max_health)
	if not _resolution_reason.is_empty():
		velocity = Vector3.ZERO
		_set_awareness(AwarenessState.RESOLVED)
		return
	if health <= 0.0:
		_set_awareness(AwarenessState.DEAD)
		agent.avoidance_enabled = false
		_moving = false
		collision_layer = 0
		if not _death_started:
			_cancel_attack()
			_death_started = true
			var saved: Dictionary = (
				encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
				if _has_story_state()
				else {}
			)
			if (
				saved.get("settled", false)
				and saved.get("rig_id", get_ragdoll_signature()) == get_ragdoll_signature()
			):
				_corpse_saved = true
				death_elapsed = 8.0
				_create_corpse(true)
		death_elapsed += delta
		if not _corpse_attempted and corpse == null:
			_create_corpse(false)
		if corpse != null and multiplayer.is_server():
			global_transform = corpse.global_transform
			var corpse_settled := (
				ragdoll.settled()
				if ragdoll != null
				else (
					corpse.linear_velocity.length() < 0.15
					and corpse.angular_velocity.length() < 0.25
				)
			)
			if death_elapsed >= 6.0 and corpse_settled and not _corpse_saved:
				_corpse_saved = true
				if ragdoll != null:
					ragdoll.freeze_all()
				if _has_story_state():
					encounter.save_body(monster_id, global_transform, true, ragdoll.capture())
			_network_time += delta
			if _network_time >= 0.1:
				_network_time = 0.0
				for peer_id in _ready_peers():
					_sync_corpse.rpc_id(
						peer_id, global_transform, ragdoll.capture() if ragdoll != null else []
					)
		if corpse == null and not _corpse_saved and multiplayer.is_server():
			_corpse_saved = true
			if _has_story_state():
				encounter.save_body(monster_id, global_transform, true)
		return
	if multiplayer.is_server():
		var nearby_weight := 0.0
		for item in get_tree().get_nodes_in_group("world_items"):
			if item is HeavyCarryProp:
				continue
			if (
				item is WorldItemPickup
				and not item._collected
				and item.global_position.distance_to(global_position) < 0.8
			):
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
		if agent.avoidance_enabled and _wants_move:
			agent.velocity = Vector3(velocity.x, 0.0, velocity.z)
			velocity.x = _safe_velocity.x
			velocity.z = _safe_velocity.z
		elif agent.avoidance_enabled:
			agent.velocity = Vector3.ZERO
			_safe_velocity = Vector3.ZERO
		move_and_slide()
		_update_blocked(delta, movement_start)
		_moving = Vector2(velocity.x, velocity.z).length() > 0.2
		_network_time += delta
		if _network_time > 0.1:
			_network_time = 0.0
			for peer_id in _ready_peers():
				_sync.rpc_id(
					peer_id,
					position,
					rotation.y,
					_moving,
					_windup,
					awareness_state,
					Vector2(velocity.x, velocity.z).length()
				)
	else:
		position = position.lerp(_target_position, minf(delta * 12.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(delta * 12.0, 1.0))
	if visual != null:
		visual.animate(
			delta,
			_moving,
			_windup > 0.0,
			false,
			ai_profile.attack_windup,
			(
				Vector2(velocity.x, velocity.z).length()
				if multiplayer.is_server()
				else _replicated_speed
			)
		)


func _valid_actor(target: Node3D) -> bool:
	return (
		is_instance_valid(target)
		and target is GamePlayer
		and not target.survival.dead
		and not target.is_sleeping_in_bunk()
		and absf(target.global_position.y - global_position.y) <= ai_profile.vertical_awareness
	)


func _clear_segment(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP,
		point + Vector3.UP,
		ai_profile.perception_collision_mask,
		[get_rid()]
	)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _can_reach(target: Node3D, reach: float) -> bool:
	if (
		not _valid_actor(target)
		or global_position.distance_to(target.global_position) > reach
		or not _clear_segment(target.global_position)
	):
		return false
	var offset := target.global_position - global_position
	offset.y = 0.0
	return (
		offset.is_zero_approx()
		or (
			(-global_basis.z).dot(offset.normalized())
			>= cos(deg_to_rad(ai_profile.attack_arc * 0.5))
		)
	)


func _project_navigation(point: Vector3) -> Vector3:
	var map := agent.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var projected := NavigationServer3D.map_get_closest_point(map, point)
	return (
		projected
		if projected.distance_to(point) <= ai_profile.navigation_projection_distance
		else Vector3.INF
	)


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
			if (
				not _navigation_goal.is_finite()
				or (_path_time <= 0.0 and _navigation_goal.distance_to(goal) > 0.25)
			):
				# Reassigning an unchanged target resets native path/link progress.
				# Moving targets are refreshed at the configured interval instead.
				_path_time = ai_profile.path_update_interval
				_navigation_goal = goal
				agent.target_position = goal
			# Always advance the agent on physics frames, even at the end of a path.
			var next := agent.get_next_path_position()
			if not agent.is_navigation_finished():
				direction = next - global_position
		elif _clear_segment(point):
			# Debug actors without a navigation region may walk only visible routes.
			direction = point - global_position
			# Native avoidance accepts submitted velocity only while a target is
			# assigned. Keep a direct-route target without requesting a baked path.
			if agent.avoidance_enabled:
				agent.target_position = point
		direction.y = 0.0
		direction = direction.normalized()
	_wants_move = not direction.is_zero_approx() and speed > 0.0
	var desired := direction * speed
	var blend := ai_profile.acceleration * delta
	velocity.x = move_toward(velocity.x, desired.x, blend) if blend > 0.0 else desired.x
	velocity.z = move_toward(velocity.z, desired.z, blend) if blend > 0.0 else desired.z
	if not direction.is_zero_approx():
		rotation.y = lerp_angle(
			rotation.y, atan2(-direction.x, -direction.z), minf(delta * ai_profile.turn_speed, 1.0)
		)


func _wander_point(center: Vector3, radius: float) -> Vector3:
	var from := _project_navigation(global_position)
	for attempt in 8:
		var angle := randf() * TAU
		var candidate := (
			center + Vector3(cos(angle), 0, sin(angle)) * randf_range(radius * 0.4, radius)
		)
		var goal := _project_navigation(candidate)
		if from.is_finite() and goal.is_finite():
			if absf(goal.y - global_position.y) > ai_profile.vertical_awareness:
				continue
			var path := NavigationServer3D.map_get_path(
				agent.get_navigation_map(), from, goal, true, ai_profile.navigation_layers
			)
			if (
				not path.is_empty()
				and path[-1].distance_to(goal) < 0.5
				and global_position.distance_to(goal) > ai_profile.patrol_stop_distance
			):
				return goal
		elif _clear_segment(candidate):
			return candidate
	return global_position


func _forget_interest() -> void:
	_alert_target = null
	_has_interest = false
	_sees_target = false
	_confirmed_target = null
	_awareness = 0.0
	_search_left = 0.0
	_returning_home = ai_profile.return_home_after_search
	_patrol_goal = _home
	_patrol_left = 0.0
	_path_time = 0.0


func _remember(point: Vector3, target: Node3D, duration: float, seen: bool) -> void:
	_alert_target = target
	_last_seen = point
	_awareness = duration
	_has_interest = true
	_sees_target = seen
	if seen:
		_confirmed_target = target
	_search_left = 0.0
	_returning_home = false
	_path_time = (
		0.0
		if not _navigation_goal.is_finite() or _navigation_goal.distance_to(point) > 1.0
		else _path_time
	)


func _update_behavior(delta: float) -> void:
	_wants_move = false
	_attack_left = maxf(0.0, _attack_left - delta)
	if not ai_enabled or not _resolution_reason.is_empty():
		_stop_motion()
		_set_awareness(
			AwarenessState.RESOLVED if not _resolution_reason.is_empty() else AwarenessState.DORMANT
		)
		return
	if _stun_left > 0.0:
		_stun_left = maxf(0.0, _stun_left - delta)
		_stop_motion()
		_set_awareness(AwarenessState.STUNNED)
		return
	if _scripted_goal.is_finite():
		_set_awareness(AwarenessState.SCRIPTED_MOVE)
		_move_towards(_scripted_goal, _scripted_speed, ai_profile.patrol_stop_distance, delta)
		if global_position.distance_to(_scripted_goal) <= ai_profile.patrol_stop_distance:
			var arrived := _scripted_goal
			_scripted_goal = Vector3.INF
			_stop_motion()
			scripted_move_finished.emit(arrived)
			if _resolve_on_arrival:
				resolve_without_kill(_scripted_reason)
		return
	var target := _find_target(delta)
	_travel_goal = global_position
	if _windup > 0.0:
		_set_awareness(AwarenessState.ATTACK)
		_windup = maxf(0.0, _windup - delta)
		velocity.x = 0.0
		velocity.z = 0.0
		if _windup == 0.0:
			var landed := (
				ai_profile.attacks_enabled and _can_reach(_victim, ai_profile.attack_reach)
			)
			if landed:
				_victim.survival.damage(ai_profile.attack_damage, "Атака существа")
				if ai_profile.behavior == MonsterAIProfile.Behavior.SKIRMISHER:
					_retreat_left = ai_profile.retreat_duration
			_recovery_left = ai_profile.attack_recovery
			attack_finished.emit(_victim if is_instance_valid(_victim) else null, landed)
			_victim = null
		return
	if _recovery_left > 0.0 and _retreat_left <= 0.0:
		_recovery_left = maxf(0.0, _recovery_left - delta)
		_stop_motion()
		_set_awareness(AwarenessState.RECOVER)
		return
	if _has_interest:
		if _sees_target and target != null:
			_set_awareness(AwarenessState.CHASE)
			if _retreat_left > 0.0:
				_retreat_left = maxf(0.0, _retreat_left - delta)
				var away := (global_position - target.global_position).normalized()
				var retreat := global_position + away * ai_profile.retreat_distance
				_move_towards(retreat, ai_profile.chase_speed, 0.2, delta)
				return
			if (
				ai_profile.attacks_enabled
				and global_position.distance_to(_last_seen) < ai_profile.attack_distance
				and _attack_left <= 0.0
				and _can_reach(target, ai_profile.attack_reach)
			):
				_victim = target
				_windup = ai_profile.attack_windup
				_attack_left = maxf(ai_profile.attack_cooldown, ai_profile.attack_windup)
				_stop_motion()
				_set_awareness(AwarenessState.ATTACK)
				attack_started.emit(target, _windup)
				return
			_move_towards(_last_seen, ai_profile.chase_speed, ai_profile.stop_distance, delta)
		elif _search_left > 0.0:
			_set_awareness(AwarenessState.SEARCH)
			_search_left = maxf(0.0, _search_left - delta)
			if _search_left <= 0.0:
				_forget_interest()
			elif _search_pause_left > 0.0:
				_search_pause_left = maxf(0.0, _search_pause_left - delta)
				_stop_motion()
				rotation.y += delta * ai_profile.turn_speed * 0.15
				return
			elif global_position.distance_to(_search_goal) <= ai_profile.patrol_stop_distance:
				_search_goal = _wander_point(_search_center, ai_profile.search_radius)
				_search_pause_left = ai_profile.search_pause
			_move_towards(
				_search_goal, ai_profile.patrol_speed, ai_profile.patrol_stop_distance, delta
			)
			if Vector2(velocity.x, velocity.z).length() < 0.05:
				rotation.y += delta * ai_profile.turn_speed * 0.25
		else:
			_set_awareness(AwarenessState.INVESTIGATE)
			if global_position.distance_to(_last_seen) < 0.85:
				_start_search(_last_seen)
			_move_towards(_last_seen, ai_profile.chase_speed, 0.6, delta)
	elif _returning_home:
		_set_awareness(AwarenessState.RETURN_HOME)
		_move_towards(_home, ai_profile.patrol_speed, ai_profile.patrol_stop_distance, delta)
		if global_position.distance_to(_home) <= ai_profile.patrol_stop_distance:
			_returning_home = false
			_patrol_goal = _home
			_patrol_left = _patrol_delay()
	else:
		_set_awareness(AwarenessState.PATROL)
		if global_position.distance_to(_patrol_goal) <= ai_profile.patrol_stop_distance:
			_patrol_left -= delta
			if _patrol_left <= 0.0:
				_patrol_goal = _next_patrol_goal()
				_patrol_left = _patrol_delay()
		_move_towards(_patrol_goal, ai_profile.patrol_speed, ai_profile.patrol_stop_distance, delta)


func _start_search(center: Vector3) -> void:
	_search_pause_left = ai_profile.search_pause
	_search_center = center
	_search_goal = _wander_point(center, ai_profile.search_radius)
	_search_left = ai_profile.search_duration
	_awareness = maxf(_awareness, _search_left + 0.1)
	_path_time = 0.0


func _update_blocked(delta: float, _previous: Vector3) -> void:
	var wants_travel := (
		_wants_move and global_position.distance_to(_travel_goal) > _travel_stop + 0.2
	)
	# A finished partial path may request zero velocity while its target is still unreachable.
	wants_travel = (
		wants_travel
		or (
			_travel_goal.distance_to(global_position) > _travel_stop + 0.2
			and ai_profile.patrol_speed > 0.0
			and (
				awareness_state
				in [
					AwarenessState.INVESTIGATE,
					AwarenessState.SEARCH,
					AwarenessState.RETURN_HOME,
					AwarenessState.SCRIPTED_MOVE,
					AwarenessState.CHASE
				]
			)
		)
	)
	if not wants_travel:
		_blocked_time = 0.0
		_progress_origin = global_position
		return
	_blocked_time += delta
	if _blocked_time < ai_profile.stuck_timeout:
		return
	_blocked_time = 0.0
	var displacement := (
		Vector2(global_position.x - _progress_origin.x, global_position.z - _progress_origin.z)
		. length()
	)
	_progress_origin = global_position
	if displacement >= ai_profile.minimum_progress_distance:
		_path_retries = 0
		return
	_path_retries += 1
	_path_time = 0.0
	_navigation_goal = Vector3.INF
	navigation_blocked.emit(_travel_goal, _path_retries)
	if _path_retries < ai_profile.maximum_path_retries:
		return
	_path_retries = 0
	if _scripted_goal.is_finite():
		cancel_scripted_movement()
	elif _has_interest and not _sees_target:
		# Do not restart an existing search timer forever against the same wall.
		if _search_left <= 0.0:
			_start_search(global_position)
		else:
			_search_goal = _wander_point(global_position, ai_profile.search_radius)
	elif _sees_target:
		_ignored_target = _alert_target
		_ignore_left = ai_profile.unreachable_target_cooldown
		_forget_interest()
	else:
		_returning_home = false
		_patrol_goal = _next_patrol_goal()


func hear_noise(source: Node3D, point: Vector3, radius: float) -> void:
	if _scripted_goal.is_finite() or not point.is_finite() or not is_finite(radius):
		return
	if (
		not ai_enabled
		or not _resolution_reason.is_empty()
		or not ai_profile.hearing_enabled
		or not multiplayer.is_server()
		or health <= 0.0
		or not is_visible_in_tree()
		or not is_instance_valid(source)
	):
		return
	if source is GamePlayer and not _valid_actor(source):
		return
	radius *= ai_profile.hearing_multiplier
	if (
		radius <= 0.0
		or absf(point.y - global_position.y) > ai_profile.vertical_awareness
		or global_position.distance_to(point) > radius
	):
		return
	if (
		not _clear_segment(point)
		and global_position.distance_to(point) > radius * ai_profile.occluded_hearing_multiplier
	):
		return
	# A sound gives an event position, never a live tracking feed through walls.
	if _valid_actor(_alert_target) and _can_see(_alert_target):
		return
	_remember(point, source if source is GamePlayer else null, ai_profile.hearing_memory, false)


func _find_target(delta: float) -> Node3D:
	var was_seeing := _sees_target
	_ignore_left = maxf(0.0, _ignore_left - delta)
	_awareness = maxf(0.0, _awareness - delta)
	if not _valid_actor(_alert_target):
		_alert_target = null
		_sees_target = false
		_victim = null
		_windup = 0.0
	_sight_left -= delta
	if _sight_left <= 0.0:
		_sight_left = ai_profile.sight_interval
		var candidate := _closest_visible_player()
		if (
			_valid_actor(_alert_target)
			and _can_see(_alert_target)
			and _accept_target(_alert_target)
		):
			if (
				candidate == null
				or candidate == _alert_target
				or (
					candidate.global_position.distance_to(global_position)
					>= (
						_alert_target.global_position.distance_to(global_position)
						* ai_profile.target_switch_ratio
					)
				)
			):
				candidate = _alert_target
		if candidate != _candidate_target:
			_candidate_target = candidate
			_candidate_exposure = 0.0
		elif candidate != null:
			_candidate_exposure = minf(
				_candidate_exposure + maxf(delta, ai_profile.sight_interval),
				maxf(ai_profile.sight_confirmation_time, ai_profile.sight_interval)
			)
		_sees_target = (
			candidate != null
			and (
				candidate == _confirmed_target
				or _candidate_exposure >= ai_profile.sight_confirmation_time
			)
		)
		if _sees_target:
			var newly_spotted := not was_seeing or _confirmed_target != candidate
			_remember(candidate.global_position, candidate, ai_profile.sight_memory, true)
			if newly_spotted:
				target_spotted.emit(candidate)
	if _awareness <= 0.0:
		if _has_interest:
			_forget_interest()
		_alert_target = null
	if _has_interest and ai_profile.behavior == MonsterAIProfile.Behavior.TERRITORIAL:
		if (
			_last_seen.distance_to(_home) > ai_profile.territory_radius
			or global_position.distance_to(_home) > ai_profile.territory_radius
		):
			_forget_interest()
	if was_seeing and not _sees_target:
		target_lost.emit(_last_seen)
	return _alert_target


func _can_see(target: Node3D) -> bool:
	if not ai_profile.sight_enabled or not _valid_actor(target):
		return false
	var eye := global_position + Vector3.UP * eye_height
	var target_point: Vector3 = (
		target.head.global_position if target is GamePlayer else target.global_position + Vector3.UP
	)
	var offset := target_point - eye
	var distance := offset.length()
	if (
		distance
		> (
			ai_profile.sight_distance
			* (ai_profile.crouched_sight_multiplier if target._is_crouching else 1.0)
		)
	):
		return false
	var close_distance := (
		ai_profile.crouched_awareness_distance
		if target is GamePlayer and target._is_crouching
		else ai_profile.close_awareness_distance
	)
	if (
		distance > close_distance
		and (
			(-global_basis.z).dot(offset.normalized())
			< cos(deg_to_rad(ai_profile.field_of_view * 0.5))
		)
	):
		return false
	var query := PhysicsRayQueryParameters3D.create(
		eye, target_point, ai_profile.perception_collision_mask, [get_rid()]
	)
	if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return true
	if ai_profile.sight_body_sample:
		query.to = target.global_position.lerp(target_point, 0.6)
		return get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	return false


func apply_weapon_damage(amount: float) -> void:
	if ai_profile != null and ai_profile.weapon_damage_enabled:
		_receive_damage(amount, true)


func apply_environment_damage(amount: float) -> void:
	if ai_profile != null and ai_profile.environment_damage_enabled:
		_receive_damage(amount, false)


func _receive_damage(amount: float, show_blood: bool) -> void:
	if (
		not multiplayer.is_server()
		or not is_finite(amount)
		or amount <= 0.0
		or health <= 0.0
		or not _resolution_reason.is_empty()
	):
		return
	var visible_attacker := _closest_visible_player()
	if visible_attacker != null:
		_remember(visible_attacker.global_position, visible_attacker, ai_profile.sight_memory, true)
	if show_blood:
		_blood.rpc()
	if _has_story_state():
		encounter.damage_monster(monster_id, amount)
		health = encounter.get_monster_health(monster_id)
		health_changed.emit(health, ai_profile.max_health)
	else:
		_set_debug_health.rpc(maxf(0.0, health - amount))


@rpc("authority", "call_local", "reliable")
func _blood() -> void:
	preload("res://scripts/gameplay/blood_effect.gd").spawn(self, global_position + Vector3.UP)


@rpc("authority", "call_local", "reliable")
func _set_debug_health(value: float) -> void:
	var changed := health != value
	debug_health = value
	health = value
	if changed:
		health_changed.emit(health, ai_profile.max_health)


func _create_corpse(restored: bool) -> void:
	_corpse_attempted = true
	var rigs := visual.find_children("*", "Skeleton3D", true, false) if visual != null else []
	if ragdoll_scene == null or rigs.is_empty():
		if visual != null and visual.animator != null:
			visual.animator.pause()
		return
	ragdoll = ragdoll_scene.instantiate()
	var candidate_rig: Skeleton3D = rigs[0]
	for body in ragdoll.get_children():
		if body is RigidBody3D and candidate_rig.find_bone(str(body.get_meta("bone", ""))) < 0:
			push_warning(
				"Monster: ragdoll does not match the assigned model; using static death pose"
			)
			ragdoll.free()
			ragdoll = null
			if visual.animator != null:
				visual.animator.pause()
			return
	ragdoll.name = str(name) + "Ragdoll"
	(get_parent() if not is_instance_valid(encounter) else encounter).add_child(ragdoll)
	ragdoll.global_transform = global_transform
	visual.reparent(ragdoll, false)
	if visual.animator != null:
		visual.animator.pause()
	var rig: Skeleton3D = rigs[0]
	ragdoll.initialize(rig, multiplayer.is_server() and not restored, velocity)
	if debug_spawned and multiplayer.is_server():
		for body in ragdoll.bodies:
			body.freeze = false
			body.sleeping = false
		ragdoll.root_body.apply_central_impulse(Vector3(0, 1.5, 0))
	corpse = ragdoll.root_body
	if restored and _has_story_state():
		var saved: Dictionary = (
			encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
			if _has_story_state()
			else {}
		)
		var poses: Array = saved.get("ragdoll", [])
		if poses.size() == ragdoll.bodies.size():
			ragdoll.apply_poses(poses)
		else:
			# Legacy saves or a replaced model must never stretch a new rig using
			# unrelated body indices. Re-settle it under the existing authority.
			_corpse_saved = false
			death_elapsed = 0.0
			for body in ragdoll.bodies:
				body.freeze = not multiplayer.is_server()


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync_corpse(pose: Transform3D, bones: Array = []) -> void:
	if is_encounter_resolved():
		return
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
	if visual != null:
		visual.transform = _visual_rest_transform
	if visual != null:
		visual.death_time = 0
	death_elapsed = 0
	_death_started = false
	_corpse_saved = false
	_corpse_attempted = false
	_restored = false
	_resolution_reason = ""
	_stun_left = 0.0
	_recovery_left = 0.0
	_scripted_goal = Vector3.INF
	_candidate_target = null
	_confirmed_target = null
	_candidate_exposure = 0.0
	_ignore_left = 0.0
	_path_retries = 0
	visible = true
	add_to_group("hostile_monsters")
	collision_layer = _living_collision_layer
	global_transform = Transform3D(_home_transform.basis, _home)
	velocity = Vector3.ZERO
	_safe_velocity = Vector3.ZERO
	configure_navigation()
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
	if not _has_story_state():
		health = ai_profile.max_health
		debug_health = health


@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync(
	next_position: Vector3,
	yaw: float,
	moving: bool,
	windup: float,
	state: int = 0,
	movement_speed: float = 0.0
) -> void:
	if is_encounter_resolved() or health <= 0.0:
		return
	_target_position = next_position
	_replicated_speed = movement_speed
	_target_yaw = yaw
	_set_awareness(state)
	_moving = moving
	_windup = windup


func _exit_tree() -> void:
	if is_instance_valid(ragdoll):
		ragdoll.queue_free()


func _has_story_state() -> bool:
	return (
		not debug_spawned
		and is_instance_valid(encounter)
		and encounter.has_method("get_monster_health")
	)


func _ready_peers() -> Array[int]:
	var peers: Array[int] = []
	if is_instance_valid(encounter) and encounter.has_method("get_ready_peers"):
		peers.assign(encounter.get_ready_peers())
	return peers


func _accept_target(player: Node3D) -> bool:
	return _valid_actor(player) and not (player == _ignored_target and _ignore_left > 0.0)


func _closest_visible_player() -> Node3D:
	if is_instance_valid(encounter):
		return encounter.closest_player(
			global_position,
			func(player): return _accept_target(player) and _can_see(player),
			ai_profile.sight_distance,
			ai_profile.vertical_awareness
		)
	var closest: Node3D
	var distance := ai_profile.sight_distance
	for player: Node3D in get_tree().get_nodes_in_group("network_players"):
		if not _accept_target(player) or not _can_see(player):
			continue
		var next := player.global_position.distance_to(global_position)
		if next < distance:
			distance = next
			closest = player
	return closest


func _set_awareness(next: int) -> void:
	if awareness_state == next:
		return
	var previous := awareness_state
	awareness_state = next as AwarenessState
	awareness_changed.emit(previous, next)


func _stop_motion() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_wants_move = false
	_safe_velocity = Vector3.ZERO
	_travel_goal = global_position


func _cancel_attack() -> void:
	if _windup > 0.0:
		attack_finished.emit(_victim if is_instance_valid(_victim) else null, false)
	_windup = 0.0
	_victim = null
	_recovery_left = 0.0
	_retreat_left = 0.0


func configure_navigation() -> void:
	if agent == null or ai_profile == null:
		return
	agent.navigation_layers = ai_profile.navigation_layers
	agent.path_desired_distance = ai_profile.path_desired_distance
	agent.path_height_offset = ai_profile.path_height_offset
	agent.radius = ai_profile.avoidance_radius
	agent.neighbor_distance = ai_profile.neighbor_distance
	agent.max_neighbors = ai_profile.max_neighbors
	agent.max_speed = maxf(ai_profile.chase_speed, ai_profile.patrol_speed)
	agent.avoidance_enabled = ai_profile.avoidance_enabled and multiplayer.is_server()
	if not agent.velocity_computed.is_connected(_on_safe_velocity):
		agent.velocity_computed.connect(_on_safe_velocity)


func _on_safe_velocity(safe: Vector3) -> void:
	_safe_velocity = (
		safe
		if ai_enabled and _windup <= 0.0 and _stun_left <= 0.0 and _resolution_reason.is_empty()
		else Vector3.ZERO
	)


func set_home_transform(pose: Transform3D) -> void:
	_home_transform = pose
	_home = pose.origin
	_patrol_goal = _home
	_progress_origin = global_position


func _next_patrol_goal() -> Vector3:
	if _patrol_markers.is_empty():
		return _wander_point(_home, ai_profile.patrol_radius)
	for attempt in _patrol_markers.size():
		_patrol_index += _patrol_direction
		if patrol_ping_pong and _patrol_markers.size() > 1:
			if _patrol_index >= _patrol_markers.size() or _patrol_index < 0:
				_patrol_direction *= -1
				_patrol_index = clampi(
					_patrol_index + 2 * _patrol_direction, 0, _patrol_markers.size() - 1
				)
		else:
			_patrol_index = posmod(_patrol_index, _patrol_markers.size())
		var marker := _patrol_markers[_patrol_index]
		if is_instance_valid(marker):
			return marker.global_position
	return global_position


func _patrol_delay() -> float:
	return randf_range(_patrol_pause_override.x, _patrol_pause_override.y) if _patrol_pause_override.x >= 0.0 else randf_range(ai_profile.patrol_interval_min, ai_profile.patrol_interval_max)


## Route changes do not cancel an ongoing chase; only the idle patrol is replaced.
func set_patrol_route(points: Array[Node3D], pauses := Vector2(-1.0, -1.0)) -> bool:
	if not multiplayer.is_server():
		return false
	_patrol_markers = points.duplicate()
	_patrol_index = -1
	_patrol_direction = 1
	_patrol_pause_override = pauses
	_patrol_goal = global_position
	_patrol_left = 0.0
	_path_time = 0.0
	_navigation_goal = Vector3.INF
	return true


## Host-only scenario hooks. No player RPC can invoke these methods.
func set_ai_enabled(enabled: bool) -> bool:
	if not multiplayer.is_server():
		return false
	_set_ai_enabled.rpc(enabled)
	return true


@rpc("authority", "call_local", "reliable")
func _set_ai_enabled(enabled: bool) -> void:
	ai_enabled = enabled
	_cancel_attack()
	_stop_motion()
	if not enabled:
		_set_awareness(AwarenessState.DORMANT)


func stun(duration: float) -> bool:
	if (
		not multiplayer.is_server()
		or not is_finite(duration)
		or duration <= 0.0
		or health <= 0.0
		or is_encounter_resolved()
	):
		return false
	_stun_left = maxf(_stun_left, duration)
	_cancel_attack()
	_stop_motion()
	_set_awareness(AwarenessState.STUNNED)
	return true


func investigate_position(point: Vector3, duration: float = -1.0) -> bool:
	if (
		not multiplayer.is_server()
		or not point.is_finite()
		or health <= 0.0
		or is_encounter_resolved()
	):
		return false
	cancel_scripted_movement()
	_remember(
		point, null, ai_profile.hearing_memory if duration < 0.0 else maxf(duration, 0.1), false
	)
	return true


func move_to_position(
	point: Vector3,
	speed: float = -1.0,
	leave_on_arrival: bool = false,
	reason: String = "withdrawn"
) -> bool:
	if (
		not multiplayer.is_server()
		or not point.is_finite()
		or not is_finite(speed)
		or health <= 0.0
		or is_encounter_resolved()
	):
		return false
	_cancel_attack()
	_forget_interest()
	_scripted_goal = point
	_scripted_speed = ai_profile.chase_speed if speed < 0.0 else maxf(speed, 0.1)
	_resolve_on_arrival = leave_on_arrival
	_scripted_reason = reason
	_path_time = 0.0
	_blocked_time = 0.0
	_path_retries = 0
	_progress_origin = global_position
	return true


func cancel_scripted_movement() -> bool:
	if not multiplayer.is_server():
		return false
	_scripted_goal = Vector3.INF
	_resolve_on_arrival = false
	_stop_motion()
	return true


func resolve_without_kill(reason: String = "withdrawn", hide_actor: bool = true) -> bool:
	if (
		not multiplayer.is_server()
		or health <= 0.0
		or is_encounter_resolved()
		or reason.strip_edges().is_empty()
	):
		return false
	if _has_story_state():
		encounter.resolve_monster(monster_id, reason, hide_actor)
	else:
		_apply_resolution.rpc(reason.substr(0, 128), hide_actor)
	return true


func is_encounter_resolved() -> bool:
	return not _resolution_reason.is_empty()


@rpc("authority", "call_local", "reliable")
func _apply_resolution(reason: String, hide_actor: bool = true) -> void:
	var changed := _resolution_reason != reason
	_resolution_reason = reason
	_resolution_hidden = hide_actor
	if agent != null:
		agent.avoidance_enabled = false
	_cancel_attack()
	_stop_motion()
	_moving = false
	remove_from_group("hostile_monsters")
	if visual != null:
		visual.animate(0.0, false, false, false)
	visible = not hide_actor
	collision_layer = 0
	_set_awareness(AwarenessState.RESOLVED)
	if changed:
		encounter_resolved.emit(reason)


func get_ai_debug_state() -> Dictionary:
	return {
		"state": AwarenessState.keys()[awareness_state],
		"health": health,
		"enabled": ai_enabled,
		"target": str(_alert_target.name) if is_instance_valid(_alert_target) else "",
		"sees_target": _sees_target,
		"last_known": _last_seen,
		"memory_left": _awareness,
		"exposure": _candidate_exposure,
		"search_left": _search_left,
		"path_retries": _path_retries,
		"stun_left": _stun_left,
		"resolution": _resolution_reason,
		"scripted_destination": _scripted_goal
	}


func get_ragdoll_signature() -> String:
	if ragdoll_scene == null:
		return "static"
	var data := ragdoll_scene.get_state()
	var bones: PackedStringArray = []
	for i in data.get_node_count():
		for property in data.get_node_property_count(i):
			if data.get_node_property_name(i, property) in [&"metadata/bone", &"metadata/end_bone"]:
				bones.append(str(data.get_node_property_value(i, property)))
	return ragdoll_scene.resource_path + ":" + var_to_str(bones).sha256_text()
