class_name FunctionalElevatorController
extends Node3D

const MAX_FLOOR_INDEX: int = 4

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

@export_range(0, 4, 1) var unlocked_floor_index: int = 1
@export var floor_spacing: float = 12.0
@export var travel_speed: float = 3.5
@export var travel_start_stop_time: float = 1.5
@export var door_animation_duration: float = 1.5
@export var arrival_alignment_duration: float = 0.3
@export var starts_powered: bool = true
@export var require_all_connected_players: bool = true
@export var use_built_in_surface_platform: bool = true

@onready var cabin: AnimatableBody3D = %CabinMoving
@onready var cabin_door: ElevatorRollupDoor = %CabinDoor
@onready var cabin_door_travel_barrier: CollisionShape3D = %CabinDoorTravelBarrier
@onready var passenger_area: Area3D = %PassengerArea
@onready var door_safety_area: Area3D = %DoorSafetyArea
@onready var landings: Node3D = %Landings
@onready var cabin_floor_display: Label3D = %CabinFloorDisplay
@onready var cabin_state_display: Label3D = %CabinStateDisplay

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


func _ready() -> void:
	is_powered = starts_powered
	unlocked_floor_index = clampi(unlocked_floor_index, 0, MAX_FLOOR_INDEX)
	passenger_area.body_entered.connect(_on_passenger_body_entered)
	passenger_area.body_exited.connect(_on_passenger_body_exited)
	door_safety_area.body_entered.connect(_on_door_safety_body_entered)
	door_safety_area.body_exited.connect(_on_door_safety_body_exited)
	_set_surface_landing_platform_enabled(use_built_in_surface_platform)

	cabin.position.y = _get_floor_y(current_floor_index)
	cabin.reset_physics_interpolation()
	cabin_door.animation_duration = door_animation_duration
	for floor_index in MAX_FLOOR_INDEX + 1:
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
	if not _cabin_motion_active:
		return
	_cabin_motion_elapsed = minf(
		_cabin_motion_elapsed + delta,
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
	if _cabin_motion_elapsed >= _cabin_motion_duration:
		_cabin_motion_active = false
		cabin_motion_finished.emit(_cabin_motion_trip_serial)


func get_button_prompt(floor_index: int, is_call_button: bool) -> String:
	if floor_index < 0 or floor_index > MAX_FLOOR_INDEX:
		return "Неизвестный этаж"
	if not is_powered:
		return "Лифт обесточен"
	if floor_index > unlocked_floor_index:
		return "Этаж %s закрыт" % _get_floor_label(floor_index)
	if state in [
		ElevatorState.CLOSING,
		ElevatorState.MOVING,
		ElevatorState.ARRIVING,
		ElevatorState.OPENING,
	]:
		return "Лифт движется"
	if floor_index == current_floor_index:
		return (
			"Лифт уже здесь"
			if is_call_button
			else "Текущий этаж %s" % _get_floor_label(floor_index)
		)
	return (
		"Вызвать лифт на этаж %s" % _get_floor_label(floor_index)
		if is_call_button
		else "Ехать на этаж %s" % _get_floor_label(floor_index)
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
	var next_floor := clampi(day_index - 1, 0, MAX_FLOOR_INDEX)
	if next_floor != unlocked_floor_index:
		_apply_unlocked_floor.rpc(next_floor)


func set_powered(value: bool) -> void:
	if not multiplayer.is_server():
		return
	_apply_powered.rpc(value)


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
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
	if destination_floor_index < 0 or destination_floor_index > MAX_FLOOR_INDEX:
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
	if pending_floor_index < 0:
		return false
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
	_start_trip.rpc(destination_floor_index, travel_duration)
	return true


@rpc("authority", "call_local", "reliable")
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


@rpc("authority", "call_local", "reliable")
func _abort_departure() -> void:
	if state != ElevatorState.CLOSING:
		return
	_trip_serial += 1
	pending_floor_index = _active_destination_floor_index
	_active_destination_floor_index = -1
	_set_state(ElevatorState.OPENING)
	_set_current_doors_open(true)
	await cabin_door.motion_finished
	if is_powered:
		_set_state(ElevatorState.WAITING_FOR_PLAYERS)
	else:
		_power_off_after_trip = false
		pending_floor_index = -1
		_set_state(ElevatorState.UNPOWERED)
	if multiplayer.is_server():
		call_deferred("_try_begin_pending_trip")


@rpc("authority", "call_local", "reliable")
func _apply_unlocked_floor(next_unlocked_floor_index: int) -> void:
	unlocked_floor_index = clampi(
		next_unlocked_floor_index,
		0,
		MAX_FLOOR_INDEX
	)
	_refresh_displays()


@rpc("authority", "call_local", "reliable")
func _apply_powered(value: bool) -> void:
	is_powered = value
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
func _receive_network_snapshot(snapshot: Dictionary) -> void:
	_trip_serial += 1
	var resumed_trip_serial := _trip_serial
	_cabin_motion_active = false
	current_floor_index = clampi(
		int(snapshot.get("current_floor_index", 0)),
		0,
		MAX_FLOOR_INDEX
	)
	is_powered = bool(snapshot.get("is_powered", true))
	unlocked_floor_index = clampi(
		int(snapshot.get("unlocked_floor_index", 0)),
		0,
		MAX_FLOOR_INDEX
	)
	pending_floor_index = clampi(
		int(snapshot.get("pending_floor_index", -1)),
		-1,
		MAX_FLOOR_INDEX
	)
	_active_destination_floor_index = clampi(
		int(snapshot.get("active_destination_floor_index", -1)),
		-1,
		MAX_FLOOR_INDEX
	)
	_power_off_after_trip = bool(snapshot.get("power_off_after_trip", false))
	_active_travel_duration = maxf(
		float(snapshot.get("active_travel_duration", 0.01)),
		0.01
	)
	cabin.position.y = float(snapshot.get("cabin_y", 0.0))
	cabin.reset_physics_interpolation()
	var next_state := clampi(
		int(snapshot.get("state", ElevatorState.IDLE_OPEN)),
		ElevatorState.UNPOWERED,
		ElevatorState.FAULT
	) as ElevatorState
	_set_state(next_state)
	for floor_index in MAX_FLOOR_INDEX + 1:
		var landing_door := _get_landing_door(floor_index)
		if is_instance_valid(landing_door):
			landing_door.set_open(
				floor_index == current_floor_index
				and state in [
					ElevatorState.IDLE_OPEN,
					ElevatorState.WAITING_FOR_PLAYERS,
					ElevatorState.UNPOWERED,
				],
				true
			)
	var cabin_doors_open := state in [
		ElevatorState.IDLE_OPEN,
		ElevatorState.WAITING_FOR_PLAYERS,
		ElevatorState.UNPOWERED,
	]
	cabin_door.set_open(cabin_doors_open, true)
	_set_cabin_door_travel_barrier_closed(
		state in [ElevatorState.MOVING, ElevatorState.ARRIVING]
	)
	if state in [
		ElevatorState.CLOSING,
		ElevatorState.MOVING,
		ElevatorState.ARRIVING,
		ElevatorState.OPENING,
	]:
		_resume_network_trip(
			resumed_trip_serial,
			state,
			float(snapshot.get("state_remaining_seconds", 0.0)),
			float(snapshot.get("motion_remaining_seconds", 0.0))
		)


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


func _resume_network_trip(
	resumed_trip_serial: int,
	resumed_state: ElevatorState,
	state_remaining_seconds: float,
	motion_remaining_seconds: float
) -> void:
	var destination_floor_index := (
		_active_destination_floor_index
		if _active_destination_floor_index >= 0
		else current_floor_index
	)
	if resumed_state == ElevatorState.CLOSING:
		await get_tree().create_timer(maxf(state_remaining_seconds, 0.0)).timeout
		if resumed_trip_serial != _trip_serial:
			return
		_set_state(ElevatorState.MOVING)
		_begin_cabin_motion(
			_get_floor_y(destination_floor_index),
			_active_travel_duration,
			resumed_trip_serial
		)
		await cabin_motion_finished
	elif resumed_state == ElevatorState.MOVING:
		_begin_cabin_motion(
			_get_floor_y(destination_floor_index),
			maxf(motion_remaining_seconds, 0.01),
			resumed_trip_serial
		)
		await cabin_motion_finished
	if resumed_trip_serial != _trip_serial:
		return
	if resumed_state in [ElevatorState.CLOSING, ElevatorState.MOVING]:
		current_floor_index = destination_floor_index
		_active_destination_floor_index = -1
		floor_changed.emit(current_floor_index)
		_set_state(ElevatorState.ARRIVING)
		await get_tree().create_timer(arrival_alignment_duration).timeout
	elif resumed_state == ElevatorState.ARRIVING:
		await get_tree().create_timer(maxf(state_remaining_seconds, 0.0)).timeout
	if resumed_trip_serial != _trip_serial:
		return
	if resumed_state != ElevatorState.OPENING:
		_set_state(ElevatorState.OPENING)
		await get_tree().create_timer(door_animation_duration).timeout
	else:
		await get_tree().create_timer(maxf(state_remaining_seconds, 0.0)).timeout
	if resumed_trip_serial != _trip_serial:
		return
	_set_current_doors_open_instant(true)
	if _power_off_after_trip or not is_powered:
		_power_off_after_trip = false
		_set_state(ElevatorState.UNPOWERED)
	else:
		_set_state(ElevatorState.IDLE_OPEN)


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
	return -floor_spacing * float(floor_index)


func _get_floor_label(floor_index: int) -> String:
	return "0" if floor_index == 0 else "-%d" % floor_index


func _has_all_connected_players() -> bool:
	var expected_peer_ids: Array[int] = [multiplayer.get_unique_id()]
	for peer_id in multiplayer.get_peers():
		expected_peer_ids.append(int(peer_id))
	for peer_id in expected_peer_ids:
		if not _passenger_peer_ids.has(peer_id):
			return false
	return not expected_peer_ids.is_empty()


func _get_body_peer_id(body: Node) -> int:
	if body == null:
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


func _on_door_safety_body_entered(body: Node3D) -> void:
	var peer_id := _get_body_peer_id(body)
	if peer_id <= 0:
		return
	_door_obstruction_peer_ids[peer_id] = true
	if multiplayer.is_server() and state == ElevatorState.CLOSING:
		_abort_departure.rpc()


func _on_door_safety_body_exited(body: Node3D) -> void:
	var peer_id := _get_body_peer_id(body)
	if peer_id <= 0:
		return
	_door_obstruction_peer_ids.erase(peer_id)
	if multiplayer.is_server() and state == ElevatorState.WAITING_FOR_PLAYERS:
		call_deferred("_try_begin_pending_trip")


func _set_state(next_state: ElevatorState) -> void:
	state = next_state
	_state_started_at_msec = Time.get_ticks_msec()
	state_changed.emit(int(state))
	_refresh_displays()


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


func _set_current_doors_open_instant(value: bool) -> void:
	cabin_door.set_open(value, true)
	_set_cabin_door_travel_barrier_closed(not value)
	var landing_door := _get_landing_door(current_floor_index)
	if is_instance_valid(landing_door):
		landing_door.set_open(value, true)


func _refresh_displays() -> void:
	if not is_instance_valid(cabin_floor_display):
		return
	var shown_floor_index := (
		pending_floor_index
		if pending_floor_index >= 0
		else current_floor_index
	)
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
