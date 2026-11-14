class_name PlayerLocomotion
extends RefCounted
## Locomotion, crouch capsule, sprint budget and step noise for one physical body.

var sprint_remaining: float = 10.0
var sprint_exhausted: bool = false
var sprint_active: bool = false
var is_crouching: bool = false
var noise_step_distance: float = 0.0

func _update_sprint(player: GamePlayer, delta: float) -> void:
	var wants_sprint := player._server_sprint if player.multiplayer.is_server() else player._input_sprint
	var movement := player._server_move if player.multiplayer.is_server() else player._input_move
	var crouching := player._server_crouch if player.multiplayer.is_server() else player._input_crouch
	var allowed := not player.is_climbing() and not player.is_carrying_corpse() and wants_sprint and movement.length_squared() > 0.01 and not crouching and not is_crouching and not player.survival.dead and not player.is_driving() and not player.is_bunk_busy() and not player.debug_fly
	sprint_active = allowed and not sprint_exhausted and sprint_remaining > 0.0
	if sprint_active:
		sprint_remaining = maxf(0.0, sprint_remaining - delta)
		if sprint_remaining <= 0.00001:
			sprint_active = false
			sprint_remaining = 0.0
			sprint_exhausted = true
	else:
		sprint_remaining = minf(player.sprint_duration, sprint_remaining + player.sprint_recovery_per_second*delta)
		if sprint_remaining >= minf(player.sprint_restart_reserve,player.sprint_duration):
			sprint_exhausted = false

func simulate_movement(player: GamePlayer,
	delta: float,
	move_input: Vector2,
	sprinting: bool,
	crouching: bool,
	should_jump: bool,
	yaw: float,
	pitch: float
) -> void:
	if player.is_climbing():
		player.get_node("LadderClimb").simulate(delta,move_input,should_jump,yaw,pitch)
		return
	player.rotation.y = yaw
	player.head.rotation.y = 0
	player.head.rotation.x = pitch
	if player.corpse_action_busy:
		move_input = Vector2.ZERO
		should_jump = false
	update_crouch_state(player, delta, crouching)
	if player.debug_fly and not player.survival.dead:
		var flight_direction := player.head.global_basis * Vector3(move_input.x, 0, move_input.y)
		flight_direction.y += player._flight_vertical
		player.velocity = flight_direction.limit_length() * (18.0 if sprinting else 7.0) * player.debug_speed_multiplier
		if player.debug_across:
			player.global_position += player.velocity * delta
		else:
			player.move_and_slide()
		player.survival.reset_fall()
		return

	sprinting = sprint_active

	if not player.is_on_floor():
		var gravity_scale := player.fall_gravity_multiplier if player.velocity.y < 0.0 else 1.0
		player.velocity.y -= player.gravity * gravity_scale * delta
	elif player.velocity.y < 0.0:
		player.velocity.y = 0.0

	if should_jump and player.is_on_floor() and not is_crouching and not player.get_node("ItemDrag").is_heavy_carrying():
		player.velocity.y = player.jump_velocity

	var input_direction := Vector3(move_input.x, 0.0, move_input.y)
	var world_direction := player.transform.basis * input_direction.limit_length(1.0)
	var speed := (
		player.crouch_speed
		if is_crouching
		else player.sprint_speed if sprinting else player.walk_speed
	)
	if player.is_carrying_corpse():
		speed *= player.corpse_carry_speed_multiplier
	if player.get_node("ItemDrag").is_heavy_carrying(): speed = minf(speed, player.walk_speed * 0.5)
	var carried_weight := 0.0
	for item in player.get_tree().get_nodes_in_group("world_items"):
		if item is WorldItemPickup and not item._collected and item.global_position.distance_to(player.global_position) < 0.75:
			carried_weight = maxf(carried_weight, item.get_push_resistance())
			_push_loose_item(player, item, world_direction, delta)
	var target_velocity := world_direction * speed * player.debug_speed_multiplier / (1.0 + carried_weight * 0.06)
	var movement_acceleration := player.acceleration * player.debug_speed_multiplier
	if not player.is_on_floor():
		movement_acceleration *= player.air_control_multiplier

	player.velocity.x = move_toward(
		player.velocity.x,
		target_velocity.x,
		movement_acceleration * delta
	)
	player.velocity.z = move_toward(
		player.velocity.z,
		target_velocity.z,
		movement_acceleration * delta
	)
	var incoming_y := player.velocity.y
	var movement_start := player.global_position
	if not preload("res://scripts/characters/components/step_motion.gd").try_step(player, delta, player.max_step_height):
		player.move_and_slide()
	player.survival.observe_motion(incoming_y, player.is_on_floor(), player.get_platform_velocity().y)
	if player.multiplayer.is_server():
		_emit_movement_noise(player, player.global_position - movement_start - player.get_platform_velocity() * delta, player.is_on_floor())

func update_crouch_state(player: GamePlayer, delta: float, wants_to_crouch: bool) -> void:
	if not wants_to_crouch and is_crouching and not can_stand_up(player):
		wants_to_crouch = true
	is_crouching = wants_to_crouch

	var target_height := player.crouching_height if is_crouching else player.standing_height
	var target_head_height := (
		player.crouching_head_height if is_crouching else player.standing_head_height
	)
	var capsule := player.collision_shape.shape as CapsuleShape3D
	if capsule != null:
		capsule.height = move_toward(
			capsule.height,
			target_height,
			player.crouch_transition_speed * delta
		)
		player.collision_shape.position.y = capsule.height * 0.5
	player.head.position.y = move_toward(
		player.head.position.y,
		target_head_height,
		player.crouch_transition_speed * delta
	)

func can_stand_up(player: GamePlayer) -> bool:
	if player.get_world_3d() == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * (player.crouching_height - 0.08),
		player.global_position + Vector3.UP * (player.standing_height + 0.04),
		player.collision_mask,
		[player.get_rid()]
	)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func get_movement_noise_radius(player: GamePlayer) -> float:
	return player.crouching_noise_radius if is_crouching else player.sprinting_noise_radius if sprint_active else player.walking_noise_radius

func _emit_movement_noise(player: GamePlayer, travel: Vector3, grounded: bool) -> void:
	if not player.multiplayer.is_server(): return
	var distance := Vector2(travel.x, travel.z).length()
	if not grounded or player.survival.dead or player.is_bunk_busy() or player.is_driving() or player.debug_fly or distance > 2.0:
		noise_step_distance = 0.0
		return
	if distance < 0.001: return
	noise_step_distance += distance
	if noise_step_distance >= player.noise_stride:
		noise_step_distance = fmod(noise_step_distance, player.noise_stride)
		preload("res://scripts/gameplay/gameplay_noise.gd").emit(player, get_movement_noise_radius(player))

func _push_loose_item(player: GamePlayer, item: WorldItemPickup, _movement: Vector3, delta: float) -> void:
	if not player.multiplayer.is_server() or item.freeze or item.drag_owner_peer != 0:
		return
	var away := item.global_position - player.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	# Keep the original proximity nudge, at 0.2 instead of 1.5 m/s per
	# 60 Hz tick. No direction/speed gate that makes heavy items immovable.
	item.sleeping = false
	item.linear_velocity += away.normalized() * player.item_push_acceleration * delta
