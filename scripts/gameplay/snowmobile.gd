extends CharacterBody3D

@export var max_step_height := 0.45
@export var tank_capacity := 20.0
@export var fuel_per_second := 0.025
@export var max_speed := 12.0
@export var reverse_speed := 3.0
@export var acceleration := 5.0
@export var steering_speed := 1.2
var fuel_liters := 0.0
var driver_peer := 0
var _input := Vector2.ZERO
var _input_age := 0.0
var _speed := 0.0
var _sync_time := 0.0
var _state: BaseGameplayController
var _spawn: Transform3D
var _target := Transform3D.IDENTITY

func _ready() -> void:
	add_to_group("snowmobiles")
	_spawn = global_transform
	_target = global_transform
	_bind.call_deferred()

func _bind() -> void:
	_state = get_tree().get_first_node_in_group("base_gameplay_controller")
	if multiplayer.is_server() and _state != null:
		var saved: Dictionary = _state.maintenance.get("snowmobile", {})
		global_transform = saved.get("transform", _spawn)
		fuel_liters = clampf(float(saved.get("fuel_liters", 0.0)), 0, tank_capacity)

func capture_checkpoint() -> Dictionary:
	return {"transform": global_transform, "fuel_liters": fuel_liters}

func get_interaction_prompt() -> String:
	return "Снегоход · %.1f / %.0f л" % [fuel_liters, tank_capacity] if driver_peer == 0 else "Снегоход занят"

func network_interact(peer: int, player: Node) -> void:
	if not multiplayer.is_server() or player == null or player.owner_peer_id != peer or player.survival.dead or player.is_sleeping_in_bunk() or player.global_position.distance_to(global_position) > 4.0:
		return
	if player.has_held_item(&"fuel_can"):
		if driver_peer != 0:
			return
		var added := minf(tank_capacity - fuel_liters, player.fuel_liters)
		if added <= 0:
			return
		fuel_liters += added
		player.fuel_liters -= added
		player._publish_inventory()
		_save()
	elif driver_peer == 0 and not player.is_driving():
		driver_peer = peer
		_input = Vector2.ZERO
		_sync_time = 1.0
		player.begin_vehicle_view(self)
		player.collision_shape.set_deferred("disabled", true)

func set_driver_input(peer: int, value: Vector2) -> void:
	if multiplayer.is_server() and peer == driver_peer:
		_input = value.limit_length()
		_input_age = 0.0

func exit_driver() -> bool:
	if not multiplayer.is_server() or driver_peer == 0:
		return false
	var player := _player(driver_peer)
	if player != null:
		var exit_point := Vector3.ZERO
		var found := false
		for marker in [$ExitLeft, $ExitRight]:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = player.collision_shape.shape
			query.transform = Transform3D(Basis.IDENTITY, marker.global_position + Vector3.UP * 0.9)
			query.collision_mask = 3
			query.exclude = [get_rid(), player.get_rid()]
			if get_world_3d().direct_space_state.intersect_shape(query).is_empty():
				exit_point = marker.global_position
				found = true
				break
		if not found:
			return false
		player.vehicle = null
		player.head.rotation.y = 0
		player.collision_shape.set_deferred("disabled", false)
		player.teleport_authoritative(exit_point, rotation.y)
		var world := get_tree().get_first_node_in_group("network_gameplay_controller")
		if world != null and world.has_method("get_ready_v3_peers"):
			for peer in world.get_ready_v3_peers():
				_release.rpc_id(peer, driver_peer, exit_point, rotation.y)
	driver_peer = 0
	_input = Vector2.ZERO
	_sync_time = 1.0
	_save()
	return true

@rpc("authority", "call_remote", "reliable")
func _release(peer: int, point: Vector3, yaw: float) -> void:
	var player := _player(peer)
	if player != null:
		player.vehicle = null
		player.head.rotation.y = 0
		player.collision_shape.set_deferred("disabled", not player.is_local_player())
		player._receive_authoritative_teleport(point, yaw)
	driver_peer = 0

func _player(peer: int) -> Node:
	for player in get_tree().get_nodes_in_group("network_players"):
		if player.owner_peer_id == peer:
			return player
	return null

func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		var player := _player(driver_peer) if driver_peer != 0 else null
		if driver_peer != 0 and (player == null or player.survival.dead):
			if player != null:
				player.vehicle = null
				player.head.rotation.y = 0
				player.collision_shape.set_deferred("disabled", false)
			driver_peer = 0
		_input_age += delta
		var command := _input if driver_peer != 0 and _input_age < 0.5 and fuel_liters > 0 else Vector2.ZERO
		var target_speed := -command.y * (max_speed if command.y < 0 else reverse_speed)
		_speed = move_toward(_speed, target_speed, acceleration * delta)
		if is_on_floor():
			rotation.y -= command.x * steering_speed * clampf(_speed / 3.0, -1, 1) * delta
		var forward := -global_basis.z
		velocity.x = move_toward(velocity.x, forward.x * _speed, 14.0 * delta)
		velocity.z = move_toward(velocity.z, forward.z * _speed, 14.0 * delta)
		velocity.y = -0.5 if is_on_floor() else velocity.y - 9.8 * delta
		if not preload("res://scripts/characters/components/step_motion.gd").try_step(self, delta, max_step_height):
			move_and_slide()
		if not command.is_zero_approx():
			fuel_liters = maxf(0, fuel_liters - fuel_per_second * delta)
		if global_position.y < -10:
			global_transform = _spawn
			velocity = Vector3.ZERO
			_speed = 0
		_sync_time += delta
		if _sync_time >= 0.1:
			_sync_time = 0
			var world := get_tree().get_first_node_in_group("network_gameplay_controller")
			if world != null and world.has_method("get_ready_v3_peers"):
				for peer in world.get_ready_v3_peers():
					_receive_state.rpc_id(peer, global_transform, fuel_liters, driver_peer)
	else:
		global_transform = global_transform.interpolate_with(_target, minf(delta * 15, 1))
	var driver := _player(driver_peer) if driver_peer != 0 else null
	if driver != null:
		if driver.vehicle != self:
			driver.begin_vehicle_view(self)
		driver.collision_shape.set_deferred("disabled", true)
		driver.global_position = $Seat.global_position
		driver.rotation.y = global_rotation.y
		driver.velocity = Vector3.ZERO
		driver.survival.reset_fall()
	# The world label is directly above the seat, too close to the driver's camera.
	$Status.visible = driver == null or not driver.is_local_player()
	$Status.text = "СНЕГОХОД · %.1f / %.0f л" % [fuel_liters, tank_capacity]

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_state(pose: Transform3D, fuel: float, peer: int) -> void:
	_target = pose
	fuel_liters = fuel
	if driver_peer != 0 and driver_peer != peer:
		var previous := _player(driver_peer)
		if previous != null:
			previous.vehicle = null
			previous.collision_shape.set_deferred("disabled", not previous.is_local_player())
	driver_peer = peer

func _save() -> void:
	if _state != null:
		_state.save_progress_authoritative()
