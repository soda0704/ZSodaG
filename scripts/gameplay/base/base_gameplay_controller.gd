class_name BaseGameplayController
extends Node

signal snapshot_changed(snapshot: Dictionary)
signal phase_changed(phase: int)
signal day_changed(day_index: int)
signal fuel_state_changed(is_fueled: bool)
signal power_state_changed(is_powered: bool)
signal end_day_ready_changed(ready_peer_ids: Array[int])

enum BasePhase {
	ARRIVAL,
	RESTORING_POWER,
	ACTIVE_DAY,
	ENDING_DAY,
}

const FIRST_DAY := 1
const MAX_PLAYERS := 4

@export_range(1, 5, 1) var starting_day_index: int = FIRST_DAY

var day_index: int = FIRST_DAY
var phase: BasePhase = BasePhase.ARRIVAL
var fuel_delivered: bool = false
var main_breaker_on: bool = false
var end_day_ready_peer_ids: Array[int] = []


func _ready() -> void:
	add_to_group("base_gameplay_controller")
	var steam_network := get_node_or_null("/root/SteamNetwork")
	if (
		steam_network != null
		and steam_network.has_signal("peer_left")
		and not steam_network.is_connected("peer_left", _on_peer_left)
	):
		steam_network.connect("peer_left", _on_peer_left)
	_apply_snapshot(
		_make_snapshot(
			clampi(starting_day_index, 1, 5),
			BasePhase.ARRIVAL,
			false,
			false,
			[]
		),
		true
	)


func get_snapshot() -> Dictionary:
	return _make_snapshot(
		day_index,
		phase,
		fuel_delivered,
		main_breaker_on,
		end_day_ready_peer_ids
	)


func deliver_fuel_authoritative(peer_id: int) -> bool:
	if not _can_mutate_for_peer(peer_id) or fuel_delivered:
		return false
	var next_phase := phase
	if phase == BasePhase.ARRIVAL:
		next_phase = BasePhase.RESTORING_POWER
	_broadcast_snapshot(
		_make_snapshot(
			day_index,
			next_phase,
			true,
			main_breaker_on,
			end_day_ready_peer_ids
		)
	)
	return true


func activate_main_breaker_authoritative(peer_id: int) -> bool:
	if (
		not _can_mutate_for_peer(peer_id)
		or not fuel_delivered
		or main_breaker_on
	):
		return false
	_broadcast_snapshot(
		_make_snapshot(
			day_index,
			BasePhase.ACTIVE_DAY,
			true,
			true,
			end_day_ready_peer_ids
		)
	)
	return true


func set_end_day_ready_authoritative(peer_id: int, is_ready: bool) -> bool:
	if (
		not _can_mutate_for_peer(peer_id)
		or phase not in [BasePhase.ACTIVE_DAY, BasePhase.ENDING_DAY]
	):
		return false

	var next_ready_peer_ids := end_day_ready_peer_ids.duplicate()
	if is_ready and not next_ready_peer_ids.has(peer_id):
		next_ready_peer_ids.append(peer_id)
	elif not is_ready:
		next_ready_peer_ids.erase(peer_id)
	next_ready_peer_ids.sort()

	var next_phase := (
		BasePhase.ENDING_DAY
		if not next_ready_peer_ids.is_empty()
		else BasePhase.ACTIVE_DAY
	)
	_broadcast_snapshot(
		_make_snapshot(
			day_index,
			next_phase,
			fuel_delivered,
			main_breaker_on,
			next_ready_peer_ids
		)
	)
	return true


func are_all_connected_players_ready() -> bool:
	if not multiplayer.is_server() or end_day_ready_peer_ids.is_empty():
		return false
	for peer_id in _get_connected_player_peer_ids():
		if not end_day_ready_peer_ids.has(peer_id):
			return false
	return true


func reset_day_one_authoritative() -> bool:
	if not multiplayer.is_server():
		return false
	_broadcast_snapshot(
		_make_snapshot(FIRST_DAY, BasePhase.ARRIVAL, false, false, [])
	)
	return true


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	_receive_snapshot.rpc_id(peer_id, get_snapshot())


func _broadcast_snapshot(snapshot: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_receive_snapshot.rpc(snapshot)


@rpc("authority", "call_local", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary, force_signals: bool = false) -> void:
	var previous_day := day_index
	var previous_phase := phase
	var previous_fuel := fuel_delivered
	var previous_power := main_breaker_on
	var previous_ready := end_day_ready_peer_ids.duplicate()

	day_index = clampi(int(snapshot.get("day_index", FIRST_DAY)), 1, 5)
	phase = clampi(
		int(snapshot.get("phase", BasePhase.ARRIVAL)),
		BasePhase.ARRIVAL,
		BasePhase.ENDING_DAY
	) as BasePhase
	fuel_delivered = bool(snapshot.get("fuel_delivered", false))
	main_breaker_on = (
		bool(snapshot.get("main_breaker_on", false)) and fuel_delivered
	)
	end_day_ready_peer_ids = _normalize_peer_ids(
		snapshot.get("end_day_ready_peer_ids", []) as Array
	)

	if force_signals or previous_day != day_index:
		day_changed.emit(day_index)
	if force_signals or previous_phase != phase:
		phase_changed.emit(int(phase))
	if force_signals or previous_fuel != fuel_delivered:
		fuel_state_changed.emit(fuel_delivered)
	if force_signals or previous_power != main_breaker_on:
		power_state_changed.emit(main_breaker_on)
	if force_signals or previous_ready != end_day_ready_peer_ids:
		end_day_ready_changed.emit(end_day_ready_peer_ids.duplicate())
	snapshot_changed.emit(get_snapshot())


func _make_snapshot(
	next_day_index: int,
	next_phase: BasePhase,
	next_fuel_delivered: bool,
	next_main_breaker_on: bool,
	next_ready_peer_ids: Array
) -> Dictionary:
	return {
		"day_index": clampi(next_day_index, 1, 5),
		"phase": int(next_phase),
		"fuel_delivered": next_fuel_delivered,
		"main_breaker_on": next_main_breaker_on and next_fuel_delivered,
		"end_day_ready_peer_ids": _normalize_peer_ids(next_ready_peer_ids),
	}


func _normalize_peer_ids(peer_ids: Array) -> Array[int]:
	var normalized: Array[int] = []
	for peer_id_variant in peer_ids:
		var peer_id := int(peer_id_variant)
		if peer_id > 0 and not normalized.has(peer_id):
			normalized.append(peer_id)
	normalized.sort()
	return normalized


func _can_mutate_for_peer(peer_id: int) -> bool:
	return (
		multiplayer.is_server()
		and peer_id > 0
		and _get_connected_player_peer_ids().has(peer_id)
	)


func _get_connected_player_peer_ids() -> Array[int]:
	var peer_ids: Array[int] = []
	var gameplay_controller := get_tree().get_first_node_in_group(
		"network_gameplay_controller"
	)
	if gameplay_controller != null:
		var players_node := gameplay_controller.get_node_or_null("Players")
		if players_node != null:
			for player_node in players_node.get_children():
				var peer_id := int(player_node.get("owner_peer_id"))
				if peer_id > 0 and not peer_ids.has(peer_id):
					peer_ids.append(peer_id)
	if peer_ids.is_empty():
		peer_ids.append(multiplayer.get_unique_id())
	for connected_peer_id in multiplayer.get_peers():
		var peer_id := int(connected_peer_id)
		if peer_id > 0 and not peer_ids.has(peer_id):
			peer_ids.append(peer_id)
	peer_ids.sort()
	return peer_ids.slice(0, MAX_PLAYERS)


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server() or not end_day_ready_peer_ids.has(peer_id):
		return
	var next_ready_peer_ids := end_day_ready_peer_ids.duplicate()
	next_ready_peer_ids.erase(peer_id)
	var next_phase := (
		BasePhase.ENDING_DAY
		if not next_ready_peer_ids.is_empty()
		else BasePhase.ACTIVE_DAY
	)
	_broadcast_snapshot(
		_make_snapshot(
			day_index,
			next_phase,
			fuel_delivered,
			main_breaker_on,
			next_ready_peer_ids
		)
	)
