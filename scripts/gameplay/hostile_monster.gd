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
var death_elapsed := 0.0
var _death_started := false
var _restored := false
var _corpse_saved := false

func _ready() -> void:
	add_to_group("hostile_monsters")
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
	_target_position = position

func _physics_process(delta: float) -> void:
	if not _restored:
		_restored = true
		var saved: Dictionary = encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
		if saved.has("transform"):
			global_transform = saved.transform
			_target_position = position
	health = encounter.get_monster_health(monster_id)
	if health <= 0.0:
		collision_layer = 0
		if not _death_started:
			_death_started = true
			var saved: Dictionary = encounter.state.containment.get("bodies", {}).get(str(monster_id), {})
			if saved.get("settled", false):
				_corpse_saved = true
				death_elapsed = 8.0
				visual.animate(2.0, false, false, true)
				_create_corpse(true)
		death_elapsed += delta
		visual.animate(delta, false, false, true)
		if corpse == null and (monster_id != 0 or death_elapsed >= 1.5):
			_create_corpse(false)
		if corpse != null and multiplayer.is_server():
			global_transform = corpse.global_transform
			if death_elapsed >= 6.0 and corpse.linear_velocity.length() < 0.2 and corpse.angular_velocity.length() < 0.2 and not _corpse_saved:
				_corpse_saved = true
				corpse.freeze = true
				encounter.save_body(monster_id, global_transform, true)
			_network_time += delta
			if _network_time >= 0.1:
				_network_time = 0.0
				_sync_corpse.rpc(global_transform)
		return
	if multiplayer.is_server():
		_attack_left = maxf(0.0, _attack_left - delta)
		var target: Node3D = encounter.closest_player(global_position)
		if _windup > 0.0:
			_windup = maxf(0.0, _windup - delta)
			velocity.x = 0
			velocity.z = 0
			if _windup == 0.0 and is_instance_valid(_victim) and not _victim.survival.dead and _can_reach(_victim, 2.0):
				_victim.survival.damage(24.0 if monster_id == 0 else 18.0, "Атака существа")
		elif target != null and encounter.navigation_ready:
			var offset := target.global_position - global_position
			if offset.length() < 1.65 and _attack_left <= 0.0 and _can_reach(target, 1.8):
				_victim = target
				_windup = 0.5
				_attack_left = 1.6
			_path_time -= delta
			if _path_time <= 0.0:
				_path_time = 0.3
				agent.target_position = target.global_position
			var direction := Vector3.ZERO
			if offset.length() > 1.4 and not agent.is_navigation_finished():
				direction = agent.get_next_path_position() - global_position
				direction.y = 0
				direction = direction.normalized()
			velocity.x = direction.x * (2.2 if monster_id == 0 else 2.7)
			velocity.z = direction.z * (2.2 if monster_id == 0 else 2.7)
			if offset.length() > 0.01:
				rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(delta * 6, 1.0))
		else:
			velocity.x = 0
			velocity.z = 0
		if not is_on_floor():
			velocity.y -= 9.8 * delta
		else:
			velocity.y = 0
		move_and_slide()
		if global_position.y < _home.y - 5.0:
			global_position = _home
			velocity = Vector3.ZERO
		_moving = Vector2(velocity.x, velocity.z).length() > 0.2
		_network_time += delta
		if _network_time > 0.1:
			_network_time = 0.0
			_sync.rpc(position, rotation.y, _moving, _windup)
	else:
		position = position.lerp(_target_position, minf(delta * 12.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _target_yaw, minf(delta * 12.0, 1.0))
	visual.animate(delta, _moving, _windup > 0.0, false)

func _can_reach(target: Node3D, reach: float) -> bool:
	if global_position.distance_to(target.global_position) > reach:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, target.global_position + Vector3.UP, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func apply_weapon_damage(amount: float) -> void:
	if multiplayer.is_server() and health > 0.0:
		encounter.damage_monster(monster_id, amount)

func _create_corpse(restored: bool) -> void:
	corpse = RigidBody3D.new()
	corpse.name = "Corpse%d" % monster_id
	corpse.mass = 60.0
	corpse.collision_layer = 0
	corpse.collision_mask = 1
	corpse.continuous_cd = true
	corpse.linear_damp = 1.0
	corpse.angular_damp = 2.0
	corpse.freeze = restored or not multiplayer.is_server()
	encounter.add_child(corpse)
	corpse.global_transform = global_transform
	var collider := CollisionShape3D.new()
	if monster_id == 0:
		var box := BoxShape3D.new()
		box.size = Vector3(0.8, 0.45, 1.5)
		collider.shape = box
		collider.position = Vector3(0, 0.26, 0)
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.32 if monster_id == 1 else 0.25
		capsule.height = 1.8 if monster_id == 1 else 1.0
		collider.shape = capsule
		collider.position.y = capsule.height * 0.5
	corpse.add_child(collider)
	visual.reparent(corpse, false)
	# Contact points protect the head and extremities from sinking through the floor.
	for rig: Skeleton3D in visual.model.find_children("*", "Skeleton3D", true, false):
		for bone in rig.get_bone_count():
			var bone_name := rig.get_bone_name(bone).to_lower()
			if "_s0_" in bone_name or "_s1_" in bone_name or "end" in bone_name:
				continue
			if not ("head" in bone_name or "foot" in bone_name or "hand" in bone_name or "forearm" in bone_name or "claw" in bone_name):
				continue
			var contact := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = 0.12 if "head" in bone_name else 0.035 if "claw" in bone_name else 0.07
			contact.shape = sphere
			contact.position = corpse.to_local(rig.to_global(rig.get_bone_global_pose(bone).origin))
			corpse.add_child(contact)
	if not restored and multiplayer.is_server():
		corpse.apply_central_impulse(-global_basis.z * 30.0)
		if monster_id != 0:
			corpse.apply_torque_impulse(global_basis.x * -30.0)

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _sync_corpse(pose: Transform3D) -> void:
	global_transform = pose
	if corpse != null:
		corpse.global_transform = pose

func reset_enemy() -> void:
	if corpse != null:
		visual.reparent(self, false)
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
