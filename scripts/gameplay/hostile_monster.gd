extends CharacterBody3D

var monster_id: int = 0
var model_id: String = "the_monster"
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

func _ready() -> void:
	add_to_group("hostile_monsters")
	if debug_spawned:
		add_to_group("debug_spawned_monsters")
	collision_layer = 2
	collision_mask = 3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.1 if monster_id == 2 else 1.9
	shape.shape = capsule
	shape.position.y = capsule.height * 0.5
	add_child(shape)
	visual = preload("res://scripts/gameplay/monster_visual.gd").new()
	add_child(visual)
	visual.setup(model_id, 2.25 if monster_id == 0 else 1.15 if monster_id == 2 else 1.95)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.35
	agent.target_desired_distance = 1.3
	add_child(agent)
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
			if item is WorldItemPickup and not item._collected and item.global_position.distance_to(global_position) < 0.8:
				item.linear_velocity += (item.global_position - global_position).normalized() * 1.2
				nearby_weight = maxf(nearby_weight, item.get_push_resistance())
		velocity.x *= 1.0 / (1.0 + nearby_weight * 0.05)
		velocity.z *= 1.0 / (1.0 + nearby_weight * 0.05)
		_attack_left = maxf(0.0, _attack_left - delta)
		var target: Node3D = _find_target(delta)
		if _windup > 0.0:
			_windup = maxf(0.0, _windup - delta)
			velocity.x = 0
			velocity.z = 0
			if _windup == 0.0 and is_instance_valid(_victim) and not _victim.survival.dead and _can_reach(_victim, 2.0):
				_victim.survival.damage(24.0 if monster_id == 0 else 18.0, "Атака существа")
		elif target != null:
			var offset := _last_seen - global_position
			if offset.length() < 1.65 and _attack_left <= 0.0 and _can_reach(target, 1.8):
				_victim = target
				_windup = 0.5
				_attack_left = 1.6
			_path_time -= delta
			if _path_time <= 0.0:
				_path_time = 0.3
				agent.target_position = _last_seen
			var direction := Vector3.ZERO
			if offset.length() > 1.4:
				direction = offset
				var level_three_y: float = encounter.get_parent().to_global(Vector3(0, -54, 0)).y
				if encounter.navigation_ready and absf(global_position.y - level_three_y) < 4.0 and not agent.is_navigation_finished():
					var nav_direction := agent.get_next_path_position() - global_position
					if nav_direction.length_squared() > 0.04:
						direction = nav_direction
				direction.y = 0
				direction = direction.normalized()
			velocity.x = direction.x * (2.2 if monster_id == 0 else 2.7)
			velocity.z = direction.z * (2.2 if monster_id == 0 else 2.7)
			if offset.length() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(delta * 6, 1.0))
		else:
			_patrol_left -= delta
			if _patrol_left <= 0.0:
				_patrol_left = randf_range(5.0, 10.0)
				var candidate := _home + Vector3(randf_range(-8.0, 8.0), 0, randf_range(-8.0, 8.0))
				if encounter.navigation_ready:
					_patrol_goal = NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), candidate)
					if absf(_patrol_goal.y - _home.y) > 3.0:
						_patrol_goal = _home
				else:
					_patrol_goal = candidate
				agent.target_position = _patrol_goal
			var direction := _patrol_goal - global_position
			if encounter.navigation_ready and not agent.is_navigation_finished():
				direction = agent.get_next_path_position() - global_position
			direction.y = 0.0
			if direction.length() < 0.7:
				direction = Vector3.ZERO
			else:
				direction = direction.normalized()
			velocity.x = direction.x * 0.8
			velocity.z = direction.z * 0.8
			if not direction.is_zero_approx():
				rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), minf(delta * 3.0, 1.0))
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = 0
		move_and_slide()
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

func _can_reach(target: Node3D, reach: float) -> bool:
	if global_position.distance_to(target.global_position) > reach:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func hear_noise(source: Node3D, point: Vector3, radius: float) -> void:
	if not multiplayer.is_server() or health <= 0.0 or not is_instance_valid(source):
		return
	# Do not lure actors between vertically stacked levels through the ceiling.
	if absf(point.y - global_position.y) > 4.0 or global_position.distance_to(point) > radius:
		return
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, point + Vector3.UP, 1, [get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty() and global_position.distance_to(point) > radius * 0.55:
		return
	# Hearing must not overwrite a target currently in clear view.
	if is_instance_valid(_alert_target) and _can_see(_alert_target):
		return
	_alert_target = source
	_last_seen = point
	_awareness = 8.0
	_path_time = 0.0

func _find_target(delta: float) -> Node3D:
	_awareness = maxf(0.0, _awareness - delta)
	_sight_left -= delta
	if _sight_left <= 0.0:
		_sight_left = 0.15
		var candidate: Node3D = encounter.closest_player(global_position, _can_see)
		if candidate != null:
			_alert_target = candidate
			_last_seen = candidate.global_position
			_awareness = 12.0
	if _awareness <= 0.0 or not is_instance_valid(_alert_target) or _alert_target.survival.dead:
		_alert_target = null
	return _alert_target

func _can_see(target: Node3D) -> bool:
	var eye := global_position + Vector3.UP * (1.45 if monster_id != 2 else 0.75)
	var target_point := target.global_position + Vector3.UP
	var offset := target_point - eye
	var distance := offset.length()
	if distance > 28.0:
		return false
	var forward := -global_basis.z
	if distance > 3.0 and forward.dot(offset.normalized()) < cos(deg_to_rad(58.0)):
		return false
	var query := PhysicsRayQueryParameters3D.create(eye, target_point, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func apply_weapon_damage(amount: float) -> void:
	if multiplayer.is_server() and health > 0.0:
		_alert_target = encounter.closest_player(global_position)
		if is_instance_valid(_alert_target):
			_last_seen = _alert_target.global_position
			_awareness = 12.0
		if amount > 0.0:
			_blood.rpc()
		if debug_spawned:
			_set_debug_health.rpc(maxf(0.0, debug_health - amount))
		else:
			encounter.damage_monster(monster_id, amount)

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
	visual.rotation = Vector3(0, PI, 0)
	visual.position = Vector3.ZERO
	visual.death_time = 0
	death_elapsed = 0
	_death_started = false
	_corpse_saved = false
	collision_layer = 2
	global_transform = Transform3D(Basis.IDENTITY, _home)
	velocity = Vector3.ZERO

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync(next_position: Vector3, yaw: float, moving: bool, windup: float) -> void:
	_target_position = next_position
	_target_yaw = yaw
	_moving = moving
	_windup = windup

func _exit_tree() -> void:
	if is_instance_valid(ragdoll):
		ragdoll.queue_free()
