extends CharacterBody3D

@export var max_step_height := 0.45
@export var tank_capacity := 20.0
@export var fuel_per_second := 0.025
@export var max_speed := 12.0
@export_range(1.0, 2.0) var boost_speed_multiplier := 1.2
@export_range(1.0, 4.0) var boost_fuel_multiplier := 2.0
@export var reverse_speed := 3.0
@export var acceleration := 5.0
@export var steering_speed := 1.2
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
		var target_speed := -command.y * (forward_speed if command.y < 0 else reverse_speed)
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
			fuel_liters = maxf(0, fuel_liters - fuel_per_second * (boost_fuel_multiplier if boosting else 1.0) * delta)
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
					_receive_state.rpc_id(peer, global_transform, fuel_liters, driver_peer, absf(_speed), _ignition_left)
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
	_update_engine_audio(delta)
	# The world label is directly above the seat, too close to the driver's camera.
	$Status.visible = driver == null or not driver.is_local_player()
	$Status.text = "СНЕГОХОД · %.1f / %.0f л" % [fuel_liters, tank_capacity]

@rpc("authority", "call_remote", "unreliable_ordered", 3)
func _receive_state(pose: Transform3D, fuel: float, peer: int, speed: float = 0.0, ignition_left: float = -1.0) -> void:
	if ignition_left >= 0.0:
		_ignition_left = clampf(ignition_left, 0.0, ignition_duration())
	if not _received_audio_state:
		_skip_engine_start = peer != 0 and _ignition_left <= 0.0
		_received_audio_state = true
	_received_speed = clampf(speed, 0.0, max_speed * boost_speed_multiplier)
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
