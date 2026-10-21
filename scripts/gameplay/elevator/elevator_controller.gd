class_name FunctionalElevatorController
extends Node3D

const MAX_FLOOR_INDEX: int = 5

signal state_changed(next_state: int)
signal floor_changed(floor_index: int)
signal interaction_blocked(reason: String)
signal cabin_motion_finished(trip_serial: int)

enum ElevatorState {
	UNPOWERED,
	IDLE_OPEN,
	WAITING_FOR_PLAYERS,
	CLOSING,
	MOVING,
	ARRIVING,
	OPENING,
	FAULT,
}

@export_range(2, 6, 1) var stop_count := 6
@export var checkpoint_key := "elevator_floor"
@export var cabin_checkpoint_half_extents := Vector3(2.7, 4.0, 2.7)
@export var floor_labels := PackedStringArray()
@export var cabin_light_panel_paths: Array[NodePath] = [NodePath("CabinMoving/CabinVisualArt/LightingModules/NorthPanel"), NodePath("CabinMoving/CabinVisualArt/LightingModules/SouthPanel")]
@export_range(0, 5, 1) var unlocked_floor_index: int = 1
## One new floor per day, starting with the surface on day one.
## Day seven uses the separate expedition winch, not another base elevator stop.
@export var floor_unlock_days := PackedInt32Array([1, 2, 3, 4, 5, 6])
@export var floor_spacing: float = 12.0
@export var travel_speed: float = 3.5
@export var travel_start_stop_time: float = 1.5
@export var door_animation_duration: float = 1.5
@export var arrival_alignment_duration: float = 0.3
@export var starts_powered: bool = true
@export var require_all_connected_players: bool = true
@export var use_built_in_surface_platform: bool = true

@onready var cabin: AnimatableBody3D = %CabinMoving
@onready var cabin_light: SpotLight3D = get_node_or_null("CabinMoving/CabinLight")
@onready var cabin_door: ElevatorRollupDoor = %CabinDoor
@onready var cabin_door_travel_barrier: CollisionShape3D = %CabinDoorTravelBarrier
@onready var passenger_area: Area3D = %PassengerArea
@onready var door_safety_area: Area3D = %DoorSafetyArea
@onready var landings: Node3D = %Landings
@onready var cabin_floor_display: Label3D = %CabinFloorDisplay
@onready var cabin_state_display: Label3D = %CabinStateDisplay

var _audio_fade: Tween
var _cabin_light_materials: Array[StandardMaterial3D] = []

var state: ElevatorState = ElevatorState.IDLE_OPEN
var current_floor_index: int = 0
var pending_floor_index: int = -1
var is_powered: bool = true

var _pending_trip_requires_players: bool = true
var _active_destination_floor_index: int = -1
var _power_off_after_trip: bool = false
var _passenger_peer_ids: Dictionary = {}
var _door_obstruction_peer_ids: Dictionary = {}
var _trip_serial: int = 0
var _cabin_motion_active: bool = false
var _cabin_motion_start_y: float = 0.0
var _cabin_motion_target_y: float = 0.0
var _cabin_motion_duration: float = 0.01
var _cabin_motion_elapsed: float = 0.0
var _cabin_motion_trip_serial: int = 0
var _active_travel_duration: float = 0.01
var _state_started_at_msec: int = 0
var _synced_peers: Array[int] = []
var _network_sync_elapsed: float = 0.0
var _snapshot_received: bool = false
var _clock_sample_elapsed: float = 0.0
var _network_half_rtt: float = 0.0
var _has_clock_sample: bool = false
var _network_motion_elapsed_target: float = 0.0
var _pending_network_snapshot: Dictionary = {}


func _ready() -> void:
	add_to_group("elevator_controllers")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	cabin.add_to_group("elevator_cabins")
	is_powered = starts_powered
	for panel_path in cabin_light_panel_paths:
		var panel := get_node_or_null(panel_path) as MeshInstance3D
		if panel == null or not panel.get_active_material(0) is StandardMaterial3D:
			continue
		var material := panel.get_active_material(0).duplicate() as StandardMaterial3D
		panel.material_override = material
		_cabin_light_materials.append(material)
	_refresh_cabin_light()
	unlocked_floor_index = clampi(unlocked_floor_index, 0, stop_count - 1)
	passenger_area.body_entered.connect(_on_passenger_body_entered)
	passenger_area.body_exited.connect(_on_passenger_body_exited)
	door_safety_area.body_entered.connect(_on_door_safety_body_entered)
	door_safety_area.body_exited.connect(_on_door_safety_body_exited)
	_set_surface_landing_platform_enabled(use_built_in_surface_platform)

	cabin.position.y = _get_floor_y(current_floor_index)
	cabin.reset_physics_interpolation()
	cabin_door.animation_duration = door_animation_duration
	for floor_index in stop_count:
		var landing_door := _get_landing_door(floor_index)
		if is_instance_valid(landing_door):
			landing_door.animation_duration = door_animation_duration
			landing_door.set_open(floor_index == current_floor_index, true)
	cabin_door.set_open(true, true)
	_set_cabin_door_travel_barrier_closed(false)
	_set_state(
		ElevatorState.IDLE_OPEN
		if is_powered
		else ElevatorState.UNPOWERED
	)


func _physics_process(delta: float) -> void:
	if not _pending_network_snapshot.is_empty():
		var snapshot := _pending_network_snapshot
		_pending_network_snapshot = {}
		_apply_network_snapshot(snapshot)
	if multiplayer.is_server():
		_network_sync_elapsed += delta
		if _network_sync_elapsed >= 0.5:
			_network_sync_elapsed = 0.0
			_broadcast_network_snapshot()
	elif _snapshot_received:
		_clock_sample_elapsed += delta
		if _clock_sample_elapsed >= 1.0:
			_clock_sample_elapsed = 0.0
			_request_clock_sample.rpc_id(1, Time.get_ticks_msec())
	if not _cabin_motion_active:
		return
	var motion_delta := delta
	if not multiplayer.is_server():
		_network_motion_elapsed_target += delta
		# Correct phase gradually instead of restarting the acceleration curve or
		# teleporting a platform beneath a predicted CharacterBody3D.
		motion_delta += clampf(
			_network_motion_elapsed_target - _cabin_motion_elapsed,
			-delta * 0.25,
			delta * 0.25
		)
	_cabin_motion_elapsed = minf(
		_cabin_motion_elapsed + motion_delta,
		_cabin_motion_duration
	)
	var progress := _cabin_motion_elapsed / _cabin_motion_duration
	var smooth_progress := progress * progress * progress * (
		progress * (progress * 6.0 - 15.0) + 10.0
	)
	cabin.position.y = lerpf(
		_cabin_motion_start_y,
		_cabin_motion_target_y,
		smooth_progress
	)
	_refresh_displays()
	if _cabin_motion_elapsed >= _cabin_motion_duration:
		_cabin_motion_active = false
		cabin_motion_finished.emit(_cabin_motion_trip_serial)


func restore_checkpoint_floor(floor_index: int) -> void:
	if not multiplayer.is_server():
		return
	_trip_serial += 1
	_cabin_motion_active = false
	current_floor_index = clampi(floor_index, 0, unlocked_floor_index)
	pending_floor_index = -1
	_active_destination_floor_index = -1
	_power_off_after_trip = false
	cabin.position.y = _get_floor_y(current_floor_index)
	cabin.reset_physics_interpolation()
	for index in stop_count:
		_get_landing_door(index).set_open(index == current_floor_index, true)
	cabin_door.set_open(true, true)
	_set_cabin_door_travel_barrier_closed(false)
	_set_state(ElevatorState.IDLE_OPEN if is_powered else ElevatorState.UNPOWERED)


func get_button_prompt(floor_index: int, is_call_button: bool) -> String:
	if floor_index < 0 or floor_index > stop_count - 1:
		return ""
	if not is_powered:
		return ""
	if floor_index > unlocked_floor_index:
		return ""
	if state in [
		ElevatorState.CLOSING,
		ElevatorState.MOVING,
		ElevatorState.ARRIVING,
		ElevatorState.OPENING,
	]:
		return ""
	if floor_index == current_floor_index: return ""
	return (
		"Вызвать лифт на уровень %s" % _get_floor_label(floor_index)
		if is_call_button
		else "Ехать на уровень %s" % _get_floor_label(floor_index)
	)


func request_floor(destination_floor_index: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not _can_accept_destination(destination_floor_index):
		return false

	pending_floor_index = destination_floor_index
	_pending_trip_requires_players = require_all_connected_players
	return _try_begin_pending_trip()


func request_call(destination_floor_index: int) -> bool:
	if not multiplayer.is_server():
		return false
	if not _can_accept_destination(destination_floor_index):
		return false

	pending_floor_index = destination_floor_index
	_pending_trip_requires_players = false
	return _try_begin_pending_trip()


func set_day(day_index: int) -> void:
	if not multiplayer.is_server():
		return
	var next_floor := 0
	for index in mini(floor_unlock_days.size(), stop_count):
		if day_index >= floor_unlock_days[index]:
			next_floor = index
	if next_floor != unlocked_floor_index:
		_apply_unlocked_floor(next_floor)
		_broadcast_network_snapshot.call_deferred()


func set_powered(value: bool) -> void:
	if not multiplayer.is_server():
		return
	if is_powered != value:
		_apply_powered(value)
		_broadcast_network_snapshot.call_deferred()


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not multiplayer.get_peers().has(peer_id):
		return
	if not _synced_peers.has(peer_id):
		_synced_peers.append(peer_id)
	_receive_network_snapshot.rpc_id(peer_id, get_network_snapshot())


func get_network_snapshot() -> Dictionary:
	return {
		"current_floor_index": current_floor_index,
		"state": int(state),
		"is_powered": is_powered,
		"unlocked_floor_index": unlocked_floor_index,
		"cabin_y": cabin.position.y,
		"pending_floor_index": pending_floor_index,
		"active_destination_floor_index": _active_destination_floor_index,
		"power_off_after_trip": _power_off_after_trip,
		"active_travel_duration": _active_travel_duration,
		"trip_serial": _trip_serial,
		"motion_start_y": _cabin_motion_start_y,
		"motion_target_y": _cabin_motion_target_y,
		"motion_duration": _cabin_motion_duration,
		"motion_elapsed": _cabin_motion_elapsed,
		"cabin_door": cabin_door.get_network_snapshot(),
		"landing_door": _get_landing_door(current_floor_index).get_network_snapshot(),
		"motion_remaining_seconds": maxf(
			_cabin_motion_duration - _cabin_motion_elapsed,
			0.0
		) if _cabin_motion_active else 0.0,
		"state_remaining_seconds": _get_state_remaining_seconds(),
	}


func _can_accept_destination(destination_floor_index: int) -> bool:
	if not is_powered:
		interaction_blocked.emit("unpowered")
		return false
	if destination_floor_index < 0 or destination_floor_index > stop_count - 1:
		interaction_blocked.emit("invalid_floor")
		return false
	if destination_floor_index > unlocked_floor_index:
		interaction_blocked.emit("locked_floor")
		return false
	if destination_floor_index == current_floor_index:
		interaction_blocked.emit("current_floor")
		return false
	if state not in [
		ElevatorState.IDLE_OPEN,
		ElevatorState.WAITING_FOR_PLAYERS,
	]:
		interaction_blocked.emit("busy")
		return false
	return true


func _try_begin_pending_trip() -> bool:
	if (
		not is_inside_tree() or is_queued_for_deletion()
		or not multiplayer.is_server() or not is_powered
		or state not in [ElevatorState.IDLE_OPEN, ElevatorState.WAITING_FOR_PLAYERS]
		or pending_floor_index < 0
	):
		return false
	_refresh_presence()
	if _pending_trip_requires_players and not _has_all_connected_players():
		_set_state(ElevatorState.WAITING_FOR_PLAYERS)
		interaction_blocked.emit("waiting_for_players")
		return false
	if not _door_obstruction_peer_ids.is_empty():
		_set_state(ElevatorState.WAITING_FOR_PLAYERS)
		interaction_blocked.emit("door_obstructed")
		return false

	var destination_floor_index := pending_floor_index
	var travel_duration := (
		absf(
			_get_floor_y(destination_floor_index)
			- _get_floor_y(current_floor_index)
		)
		/ maxf(travel_speed, 0.1)
		+ maxf(travel_start_stop_time, 0.0)
	)
	pending_floor_index = -1
	_active_destination_floor_index = destination_floor_index
	_active_travel_duration = travel_duration
	_start_trip(destination_floor_index, travel_duration)
	return true


func _start_trip(
	destination_floor_index: int,
	travel_duration: float
) -> void:
	_trip_serial += 1
	_active_travel_duration = maxf(travel_duration, 0.01)
	var active_trip_serial := _trip_serial
	_set_state(ElevatorState.CLOSING)
	_set_current_doors_open(false)
	await cabin_door.motion_finished
	if active_trip_serial != _trip_serial or state != ElevatorState.CLOSING:
		return
	_refresh_presence()
	if (
		not _door_obstruction_peer_ids.is_empty()
		or (_pending_trip_requires_players and not _has_all_connected_players())
	):
		_abort_departure()
		return

	_set_cabin_door_travel_barrier_closed(true)
	_set_state(ElevatorState.MOVING)
	_begin_cabin_motion(
		_get_floor_y(destination_floor_index),
		travel_duration,
		active_trip_serial
	)
	await cabin_motion_finished
	if active_trip_serial != _trip_serial:
		return

	current_floor_index = destination_floor_index
	_active_destination_floor_index = -1
	floor_changed.emit(current_floor_index)
	_set_state(ElevatorState.ARRIVING)
	await get_tree().create_timer(arrival_alignment_duration).timeout
	if active_trip_serial != _trip_serial:
		return

	_set_state(ElevatorState.OPENING)
	_set_current_doors_open(true)
	await cabin_door.motion_finished
	if active_trip_serial != _trip_serial:
		return

	if _power_off_after_trip or not is_powered:
		_power_off_after_trip = false
		_set_state(ElevatorState.UNPOWERED)
	else:
		_set_state(ElevatorState.IDLE_OPEN)


func _abort_departure() -> void:
	if state != ElevatorState.CLOSING:
		return
	_trip_serial += 1
	var aborted_trip_serial := _trip_serial
	pending_floor_index = _active_destination_floor_index
	_active_destination_floor_index = -1
	_set_state(ElevatorState.OPENING)
	_set_current_doors_open(true)
	await cabin_door.motion_finished
	if aborted_trip_serial != _trip_serial:
		return
	if is_powered:
		_set_state(ElevatorState.WAITING_FOR_PLAYERS)
	else:
		_power_off_after_trip = false
		pending_floor_index = -1
		_set_state(ElevatorState.UNPOWERED)
	if multiplayer.is_server():
		call_deferred("_try_begin_pending_trip")


func _apply_unlocked_floor(next_unlocked_floor_index: int) -> void:
	unlocked_floor_index = clampi(
		next_unlocked_floor_index,
		0,
		stop_count - 1
	)
	_refresh_displays()


func _apply_powered(value: bool) -> void:
	is_powered = value
	_refresh_cabin_light()
	if value:
		_power_off_after_trip = false
	if not value and state in [
		ElevatorState.CLOSING,
		ElevatorState.MOVING,
		ElevatorState.ARRIVING,
		ElevatorState.OPENING,
	]:
		_power_off_after_trip = true
		return
	if not value:
		pending_floor_index = -1
		_active_destination_floor_index = -1
		_set_state(ElevatorState.UNPOWERED)
	elif state == ElevatorState.UNPOWERED:
		_set_state(ElevatorState.IDLE_OPEN)


@rpc("authority", "call_remote", "reliable")
func _receive_network_snapshot(snapshot: Dictionary, clock_sample_msec: int = -1) -> void:
	if clock_sample_msec >= 0:
		var half_rtt := maxf(float(Time.get_ticks_msec() - clock_sample_msec) / 2000.0, 0.0)
		half_rtt = minf(half_rtt, 0.5)
		_network_half_rtt = lerpf(_network_half_rtt, half_rtt, 0.5) if _has_clock_sample else half_rtt
		_has_clock_sample = true
	# AnimatableBody transforms and their collisions must update together on a
	# physics tick, including the very first late-join teleport.
	_pending_network_snapshot = snapshot


func _apply_network_snapshot(snapshot: Dictionary) -> void:
	if not _snapshot_received:
		_clock_sample_elapsed = 1.0
	var previous_state := state
	var previous_trip_serial := _trip_serial
	var previous_floor := current_floor_index
	_trip_serial = int(snapshot.get("trip_serial", 0))
	_cabin_motion_trip_serial = _trip_serial
	current_floor_index = clampi(int(snapshot.get("current_floor_index", 0)), 0, stop_count - 1)
	is_powered = bool(snapshot.get("is_powered", true))
	_refresh_cabin_light()
	unlocked_floor_index = clampi(int(snapshot.get("unlocked_floor_index", 0)), 0, stop_count - 1)
	pending_floor_index = clampi(int(snapshot.get("pending_floor_index", -1)), -1, stop_count - 1)
	_active_destination_floor_index = clampi(int(snapshot.get("active_destination_floor_index", -1)), -1, stop_count - 1)
	_power_off_after_trip = bool(snapshot.get("power_off_after_trip", false))
	_active_travel_duration = maxf(float(snapshot.get("active_travel_duration", 0.01)), 0.01)
	var next_state := clampi(int(snapshot.get("state", ElevatorState.IDLE_OPEN)), ElevatorState.UNPOWERED, ElevatorState.FAULT) as ElevatorState
	if not _snapshot_received or state != next_state:
		_set_state(next_state)
	_cabin_motion_start_y = float(snapshot.get("motion_start_y", 0.0))
	_cabin_motion_target_y = float(snapshot.get("motion_target_y", 0.0))
	_cabin_motion_duration = maxf(float(snapshot.get("motion_duration", 0.01)), 0.01)
	_network_motion_elapsed_target = clampf(float(snapshot.get("motion_elapsed", 0.0)) + _network_half_rtt, 0.0, _cabin_motion_duration)
	_cabin_motion_active = state == ElevatorState.MOVING
	if not _snapshot_received or previous_state != state or previous_trip_serial != _trip_serial:
		_cabin_motion_elapsed = _network_motion_elapsed_target
		cabin.position.y = float(snapshot.get("cabin_y", 0.0))
		if not _snapshot_received:
			cabin.reset_physics_interpolation()
	elif state != ElevatorState.MOVING:
		cabin.position.y = float(snapshot.get("cabin_y", 0.0))
	# Only the host advances gameplay phases. Clients continue the same motion
	# curve and native door animation until the next authoritative phase arrives.
	for floor_index in stop_count:
		var landing_door := _get_landing_door(floor_index)
		if is_instance_valid(landing_door):
			if floor_index == current_floor_index:
				landing_door.apply_network_snapshot(snapshot.get("landing_door", {}), _network_half_rtt)
			else:
				landing_door.set_open(false, true)
	cabin_door.apply_network_snapshot(snapshot.get("cabin_door", {}), _network_half_rtt)
	_set_cabin_door_travel_barrier_closed(state in [ElevatorState.MOVING, ElevatorState.ARRIVING])
	_snapshot_received = true
	if previous_floor != current_floor_index:
		floor_changed.emit(current_floor_index)
	_refresh_displays()


@rpc("any_peer", "call_remote", "reliable")
func _request_clock_sample(client_msec: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _synced_peers.has(sender) and multiplayer.get_peers().has(sender):
		_receive_network_snapshot.rpc_id(sender, get_network_snapshot(), client_msec)


func _broadcast_network_snapshot() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not multiplayer.is_server():
		return
	var snapshot := get_network_snapshot()
	for peer_id in _synced_peers:
		if multiplayer.get_peers().has(peer_id):
			_receive_network_snapshot.rpc_id(peer_id, snapshot)


func _on_peer_disconnected(peer_id: int) -> void:
	_synced_peers.erase(peer_id)
	_passenger_peer_ids.erase(peer_id)
	_door_obstruction_peer_ids.erase(peer_id)
	if multiplayer.is_server() and state == ElevatorState.WAITING_FOR_PLAYERS:
		_try_begin_pending_trip.call_deferred()


func _set_current_doors_open(value: bool) -> void:
	cabin_door.set_open(value)
	if value:
		_set_cabin_door_travel_barrier_closed(false)
	var landing_door := _get_landing_door(current_floor_index)
	if is_instance_valid(landing_door):
		landing_door.set_open(value)


func _begin_cabin_motion(
	target_y: float,
	duration: float,
	trip_serial: int
) -> void:
	_cabin_motion_start_y = cabin.position.y
	_cabin_motion_target_y = target_y
	_cabin_motion_duration = maxf(duration, 0.01)
	_cabin_motion_elapsed = 0.0
	_cabin_motion_trip_serial = trip_serial
	_cabin_motion_active = true


func _set_cabin_door_travel_barrier_closed(value: bool) -> void:
	if is_instance_valid(cabin_door_travel_barrier):
		cabin_door_travel_barrier.disabled = not value


func _set_surface_landing_platform_enabled(value: bool) -> void:
	var surface_platform := landings.get_node_or_null(
		"Floor_0/Platform"
	) as StaticBody3D
	if not is_instance_valid(surface_platform):
		return
	surface_platform.visible = value
	var platform_collision := surface_platform.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D
	if is_instance_valid(platform_collision):
		platform_collision.disabled = not value


func _get_landing_door(floor_index: int) -> ElevatorRollupDoor:
	return landings.get_node_or_null(
		"Floor_%d/LandingDoor" % floor_index
	) as ElevatorRollupDoor


func _get_floor_y(floor_index: int) -> float:
	var stop := get_node_or_null("Shaft/FloorStops/Surface" if floor_index == 0 else "Shaft/FloorStops/FloorMinus%d" % floor_index) as Marker3D
	if stop != null:
		return stop.position.y
	return -floor_spacing * float(floor_index)


func _get_floor_label(floor_index: int) -> String:
	return floor_labels[floor_index] if floor_index < floor_labels.size() else str(floor_index)


func contains_cabin_point(point: Vector3, minimum_y := -0.2) -> bool:
	var local := cabin.to_local(point)
	return absf(local.x) < cabin_checkpoint_half_extents.x and absf(local.z) < cabin_checkpoint_half_extents.z and local.y > minimum_y and local.y < cabin_checkpoint_half_extents.y


func _has_all_connected_players() -> bool:
	var expected_peer_ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id in multiplayer.get_peers():
		expected_peer_ids.append(int(peer_id))
	for peer_id in expected_peer_ids:
		if not _passenger_peer_ids.has(peer_id):
			return false
	return not expected_peer_ids.is_empty()


func _refresh_presence() -> void:
	_passenger_peer_ids.clear()
	_door_obstruction_peer_ids.clear()
	for body in passenger_area.get_overlapping_bodies():
		var peer_id := _get_body_peer_id(body)
		if peer_id > 0 and not body.is_queued_for_deletion():
			_passenger_peer_ids[peer_id] = true
	for body in door_safety_area.get_overlapping_bodies():
		var peer_id := _get_body_peer_id(body)
		if peer_id > 0 and not body.is_queued_for_deletion():
			_door_obstruction_peer_ids[peer_id] = true


func _get_body_peer_id(body: Node) -> int:
	if not is_instance_valid(body) or body.is_queued_for_deletion():
		return 0
	var peer_id_variant: Variant = body.get("owner_peer_id")
	if peer_id_variant == null:
		return 0
	return int(peer_id_variant)


func _on_passenger_body_entered(body: Node3D) -> void:
	var peer_id := _get_body_peer_id(body)
	if peer_id <= 0:
		return
	_passenger_peer_ids[peer_id] = true
	if multiplayer.is_server() and state == ElevatorState.WAITING_FOR_PLAYERS:
		call_deferred("_try_begin_pending_trip")


func _on_passenger_body_exited(body: Node3D) -> void:
	var peer_id := _get_body_peer_id(body)
	if peer_id > 0:
		_passenger_peer_ids.erase(peer_id)
		if multiplayer.is_server() and _pending_trip_requires_players and state == ElevatorState.CLOSING:
			_abort_departure.call_deferred()


func _on_door_safety_body_entered(body: Node3D) -> void:
	var peer_id := _get_body_peer_id(body)
	if peer_id <= 0:
		return
	_door_obstruction_peer_ids[peer_id] = true
	if multiplayer.is_server() and state == ElevatorState.CLOSING:
		_abort_departure.call_deferred()


func _on_door_safety_body_exited(body: Node3D) -> void:
	var peer_id := _get_body_peer_id(body)
	if peer_id <= 0:
		return
	_door_obstruction_peer_ids.erase(peer_id)
	if multiplayer.is_server() and state == ElevatorState.WAITING_FOR_PLAYERS:
		call_deferred("_try_begin_pending_trip")


func _set_state(next_state: ElevatorState) -> void:
	state = next_state
	var sound: AudioStreamPlayer3D = $CabinMoving/TravelAudio
	if _audio_fade != null:
		_audio_fade.kill()
	_audio_fade = create_tween()
	if state == ElevatorState.MOVING:
		if not sound.playing:
			sound.volume_db = -60.0
			sound.play()
		_audio_fade.tween_property(sound, "volume_db", -9.0, 0.6)
	else:
		_audio_fade.tween_property(sound, "volume_db", -60.0, 0.45)
		_audio_fade.tween_callback(sound.stop)
	_state_started_at_msec = Time.get_ticks_msec()
	if multiplayer.is_server():
		_broadcast_network_snapshot.call_deferred()
	state_changed.emit(int(state))
	_refresh_displays()


func _refresh_cabin_light() -> void:
	if not is_instance_valid(cabin_light):
		return
	cabin_light.visible = is_powered
	for material in _cabin_light_materials:
		material.emission_enabled = is_powered
		material.emission = cabin_light.light_color
		material.emission_energy_multiplier = 0.65 if is_powered else 0.0


func _get_state_remaining_seconds() -> float:
	var elapsed := maxf(
		float(Time.get_ticks_msec() - _state_started_at_msec) / 1000.0,
		0.0
	)
	match state:
		ElevatorState.CLOSING, ElevatorState.OPENING:
			return maxf(door_animation_duration - elapsed, 0.0)
		ElevatorState.ARRIVING:
			return maxf(arrival_alignment_duration - elapsed, 0.0)
		_:
			return 0.0


func _refresh_displays() -> void:
	if not is_instance_valid(cabin_floor_display):
		return
	var shown_floor_index := current_floor_index
	# Display the floor physically being passed, including non-uniform stop spacing.
	if _cabin_motion_active:
		var closest := INF
		for index in stop_count:
			var distance := absf(cabin.position.y - _get_floor_y(index))
			if distance < closest:
				closest = distance
				shown_floor_index = index
	cabin_floor_display.text = _get_floor_label(shown_floor_index)
	cabin_state_display.text = _get_state_label()


func _get_state_label() -> String:
	match state:
		ElevatorState.UNPOWERED:
			return "NO POWER"
		ElevatorState.IDLE_OPEN:
			return "OPEN"
		ElevatorState.WAITING_FOR_PLAYERS:
			return "WAITING"
		ElevatorState.CLOSING:
			return "CLOSING"
		ElevatorState.MOVING:
			return "MOVING"
		ElevatorState.ARRIVING:
			return "ARRIVING"
		ElevatorState.OPENING:
			return "OPENING"
		_:
			return "FAULT"
