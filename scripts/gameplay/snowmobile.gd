extends CharacterBody3D

@export_group("Movement")
@export var max_step_height := 0.45
## Height in expedition coordinates, below the playable world; recovery for a physics fall-through.
@export var recovery_min_height := -160.0
@export_group("Fuel")
@export var tank_capacity := 20.0
@export var fuel_per_second := 0.025
@export_group("Speed and steering")
@export var max_speed := 12.0
@export_range(1.0, 2.0) var boost_speed_multiplier := 1.2
@export_range(1.0, 4.0) var boost_fuel_multiplier := 2.0
@export var reverse_speed := 3.0
@export var acceleration := 5.0
@export var steering_speed := 1.2
@export_group("Driving physics")
@export var braking_deceleration := 9.0
@export var coasting_deceleration := 1.6
@export var lateral_grip := 5.5
@export var slope_gravity := 3.5
@export var air_control := 0.12
@export var exit_max_speed := 1.0
@export var terrain_alignment_speed := 8.0
@export_range(0.0, 45.0) var ski_steering_angle := 22.0
@export_group("Engine audio")
@export_range(0.1, 2.0) var engine_idle_pitch := 1.0
@export_range(0.1, 2.0) var engine_driving_pitch := 0.74
@export_range(0.1, 2.0) var engine_low_speed_pitch := 0.66
@export_range(1.0, 1.3) var engine_idle_load_pitch := 1.08
@export_range(-60.0, 0.0) var engine_idle_volume_db := -11.0
@export_range(-60.0, 0.0) var engine_driving_volume_db := -23.0
@export_range(0.05, 2.0) var engine_crossfade_seconds := 0.35
@export_range(0.0, 2.0) var ignition_overlap_seconds := 0.6
@export var snow_contact_volume_db := -25.0
@onready var _start_audio: AudioStreamPlayer3D = $EngineStartAudio
@onready var _loop_audio: AudioStreamPlayer3D = $EngineLoopAudio
@onready var _idle_audio: AudioStreamPlayer3D = $EngineIdleAudio
@onready var _snow_audio: AudioStreamPlayer3D = $SnowContactAudio
@onready var _stop_audio: AudioStreamPlayer3D = $EngineStopAudio
var _audio_engine_on := false
var _audio_speed := 0.0
var _received_speed := 0.0
var _steering_input := 0.0
var _received_audio_state := false
var _skip_engine_start := false
var _engine_powered := false
var _ignition_left := 0.0

func ignition_duration() -> float:
	return _start_audio.stream.get_length() / maxf(_start_audio.pitch_scale, 0.01)

func is_engine_starting() -> bool:
	return _ignition_left > 0.0

func _advance_ignition(delta: float) -> void:
	var powered := driver_peer != 0 and fuel_liters > 0.0
	if powered and not _engine_powered:
		_ignition_left = ignition_duration()
	elif powered:
		_ignition_left = maxf(0.0, _ignition_left - delta)
	else:
		_ignition_left = 0.0
	_engine_powered = powered

var fuel_liters := 0.0
var driver_peer := 0
var _input := Vector2.ZERO
var _input_boost := false
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

func get_driving_speed() -> float:
	return Vector2(velocity.x, velocity.z).length() if multiplayer.is_server() else _received_speed

func get_interaction_prompt() -> String:
	if driver_peer != 0 and get_driving_speed() > exit_max_speed:
		return ""
	return "Снегоход · %.1f / %.0f л" % [fuel_liters, tank_capacity] if driver_peer == 0 else "Снегоход занят"

func network_interact(peer: int, player: Node) -> void:
	if not multiplayer.is_server() or player == null or player.owner_peer_id != peer or player.survival.dead or player.is_sleeping_in_bunk() or player.is_carrying_corpse() or player.global_position.distance_to(global_position) > 4.0:
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
		_engine_powered = false
		_input = Vector2.ZERO
		_input_boost = false
		_sync_time = 1.0
		player.begin_vehicle_view(self)
		player.collision_shape.set_deferred("disabled", true)

func set_driver_input(peer: int, value: Vector2, boosting: bool = false) -> void:
	if multiplayer.is_server() and peer == driver_peer:
		_input = value.limit_length()
		_input_boost = boosting
		_input_age = 0.0

func exit_driver() -> bool:
	if not multiplayer.is_server() or driver_peer == 0 or Vector2(velocity.x, velocity.z).length() > exit_max_speed:
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
	_engine_powered = false
	_ignition_left = 0.0
	_input_boost = false
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
		_advance_ignition(delta)
		if is_engine_starting():
			_speed = 0.0
			velocity.x = 0.0
			velocity.z = 0.0
		var command := _input if driver_peer != 0 and _input_age < 0.5 and fuel_liters > 0 and not is_engine_starting() else Vector2.ZERO
		var boosting := _input_boost and command.y < 0.0
		var forward_speed := max_speed * (boost_speed_multiplier if boosting else 1.0)
		_drive(delta, command, forward_speed, is_on_floor(), get_floor_normal() if is_on_floor() else Vector3.UP)
		velocity.y = -0.5 if is_on_floor() else velocity.y - 9.8 * delta
		if not preload("res://scripts/characters/components/step_motion.gd").try_step(self, delta, max_step_height):
			move_and_slide()
		if get_slide_collision_count() > 0:
			_speed = Vector3(velocity.x, 0, velocity.z).dot(-global_basis.z)
		if command.y < -0.05 or (command.y > 0.05 and _speed <= 0.1):
			fuel_liters = maxf(0, fuel_liters - fuel_per_second * (boost_fuel_multiplier if boosting else 1.0) * delta)
		var level := get_tree().get_first_node_in_group("expedition_level") as Node3D
		var recovery_position := level.to_local(global_position) if level != null else global_position
		if recovery_position.y < recovery_min_height:
			global_transform = _spawn
			velocity = Vector3.ZERO
			_speed = 0
		_sync_time += delta
		if _sync_time >= 0.1:
			_sync_time = 0
			var world := get_tree().get_first_node_in_group("network_gameplay_controller")
			if world != null and world.has_method("get_ready_v3_peers"):
				for peer in world.get_ready_v3_peers():
					_receive_state.rpc_id(peer, global_transform, fuel_liters, driver_peer, get_driving_speed(), _ignition_left, _steering_input)
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
	_align_visual_to_ground(delta)
	_update_engine_audio(delta)
	# The world label is directly above the seat, too close to the driver's camera.
	$Status.visible = driver == null or not driver.is_local_player()
	$Status.text = "СНЕГОХОД · %.1f / %.0f л" % [fuel_liters, tank_capacity]

## S brakes forward motion before engaging reverse. Steering alone does not burn fuel.
func _drive(delta: float, command: Vector2, forward_limit: float, grounded: bool, normal: Vector3) -> void:
	var target_speed := -command.y * (forward_limit if command.y < 0.0 else reverse_speed)
	var reversing := _speed * target_speed < 0.0 and absf(_speed) > 0.15
	var rate := braking_deceleration if reversing else coasting_deceleration if absf(command.y) < 0.05 else acceleration
	if reversing: target_speed = 0.0
	_speed = move_toward(_speed, target_speed, rate * delta * (1.0 if grounded else air_control))
	if grounded and not is_engine_starting():
		var downhill := Vector3.DOWN.slide(normal) * slope_gravity
		_speed += downhill.dot(-global_basis.z) * delta
	_steering_input = move_toward(_steering_input, command.x, delta * 4.0)
	if grounded:
		# Less aggressive steering at speed, reversed steering while backing up.
		var speed_factor := clampf(_speed / 3.0, -1.0, 1.0)
		var high_speed_factor := lerpf(1.0, 0.55, clampf(absf(_speed) / max_speed, 0.0, 1.0))
		rotation.y -= _steering_input * steering_speed * speed_factor * high_speed_factor * delta
	var forward := -global_basis.z
	var right := global_basis.x
	var lateral := Vector3(velocity.x, 0, velocity.z).dot(right)
	lateral *= exp(-lateral_grip * delta * (1.0 if grounded else air_control))
	var motion := forward * _speed + right * lateral
	velocity.x = motion.x
	velocity.z = motion.z

func get_snow_contact_markers() -> Array[Marker3D]:
	return [$Visual/TrackContact, $Visual/SkiPatrol/SkiLeftPivot/SnowContact, $Visual/SkiPatrol/SkiRightPivot/SnowContact]

func _align_visual_to_ground(delta: float) -> void:
	var steering_angle := -_steering_input * deg_to_rad(ski_steering_angle)
	for part in [$Visual/SkiPatrol/SkiLeftPivot, $Visual/SkiPatrol/SkiRightPivot, $Visual/SkiPatrol/HandlebarPivot]:
		part.rotation.y = lerp_angle(part.rotation.y, steering_angle, 1.0-exp(-12.0*delta))
	var up := Vector3.ZERO
	for ray: RayCast3D in [$GroundFrontLeft, $GroundFrontRight, $GroundRear]:
		if ray.is_colliding(): up += ray.get_collision_normal()
	var target := Vector3.ZERO
	if up.length_squared() > 0.01:
		up = global_basis.inverse() * up.normalized()
		target.x = clampf(atan2(up.z, up.y), -0.5, 0.5)
		target.z = clampf(atan2(-up.x, up.y), -0.4, 0.4)
	var vertical_offset := 0.0
	var markers := get_snow_contact_markers()
	var contacts := [markers[1], markers[2], markers[0]]
	var probes := [$GroundFrontLeft, $GroundFrontRight, $GroundRear]
	var contact_count := 0
	for i in probes.size():
		if probes[i].is_colliding():
			var contact_position: Vector3 = Basis.from_euler(target) * $Visual.to_local(contacts[i].global_position)
			vertical_offset += to_local(probes[i].get_collision_point()).y - contact_position.y
			contact_count += 1
	if contact_count > 0:
		vertical_offset = clampf(vertical_offset / contact_count, -1.0, 0.4)
	$Visual.position.y = lerpf($Visual.position.y, vertical_offset, 1.0-exp(-terrain_alignment_speed*delta))
	$Visual.rotation = $Visual.rotation.lerp(target, 1.0-exp(-terrain_alignment_speed*delta))

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_state(pose: Transform3D, fuel: float, peer: int, speed: float = 0.0, ignition_left: float = -1.0, steering: float = 0.0) -> void:
	if ignition_left >= 0.0:
		_ignition_left = clampf(ignition_left, 0.0, ignition_duration())
	if not _received_audio_state:
		_skip_engine_start = peer != 0 and _ignition_left <= 0.0
		_received_audio_state = true
	_received_speed = clampf(speed, 0.0, max_speed * boost_speed_multiplier)
	_steering_input = clampf(steering, -1.0, 1.0)
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

func _update_engine_audio(delta: float) -> void:
	var running := driver_peer != 0 and fuel_liters > 0.0
	if running != _audio_engine_on:
		_audio_engine_on = running
		if running:
			_stop_audio.stop()
			if not _skip_engine_start and (not _received_audio_state or _ignition_left > 0.0):
				var seek := maxf(0.0, ignition_duration() - _ignition_left) if _received_audio_state and _ignition_left > 0.0 else 0.0
				_start_audio.play(seek * _start_audio.pitch_scale)
			_skip_engine_start = false
		else:
			_start_audio.stop()
			_stop_audio.play()
			_audio_speed = 0.0
	if not running:
		AudioFade.apply(_idle_audio, 0.0, delta, engine_crossfade_seconds)
		AudioFade.apply(_loop_audio, 0.0, delta, engine_crossfade_seconds)
		AudioFade.apply(_snow_audio, 0.0, delta, engine_crossfade_seconds)
		return
	var speed := absf(_speed) if multiplayer.is_server() else _received_speed
	_audio_speed = move_toward(_audio_speed, speed, max_speed * 2.0 * delta)
	var throttle := clampf(_audio_speed / maxf(max_speed, 0.01), 0.0, boost_speed_multiplier)
	_idle_audio.pitch_scale = engine_idle_pitch * lerpf(1.0, engine_idle_load_pitch, throttle)
	_loop_audio.pitch_scale = lerpf(engine_low_speed_pitch, engine_driving_pitch, throttle)
	var ignition_gain := 1.0
	if _start_audio.playing:
		var left := _start_audio.stream.get_length() - _start_audio.get_playback_position()
		ignition_gain = 1.0 - smoothstep(0.0, maxf(ignition_overlap_seconds, 0.01), left)
	var driving_mix := smoothstep(0.03, 0.75, throttle)
	AudioFade.apply(_idle_audio, db_to_linear(engine_idle_volume_db) * ignition_gain, delta, engine_crossfade_seconds)
	AudioFade.apply(_loop_audio, db_to_linear(engine_driving_volume_db) * driving_mix * ignition_gain, delta, engine_crossfade_seconds)
	var snow_gain := smoothstep(0.2, 3.0, speed) if _on_snow() else 0.0
	AudioFade.apply(_snow_audio, db_to_linear(snow_contact_volume_db) * snow_gain, delta, engine_crossfade_seconds)

func _on_snow() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.2, global_position - Vector3.UP * 0.8, 1, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and ContactSurface.classify(hit.collider as Node) == &"snow"
