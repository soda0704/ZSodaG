class_name BaseGameplayController
extends Node

signal snapshot_changed(snapshot: Dictionary)
signal phase_changed(phase: int)
signal day_changed(day_index: int)
signal fuel_state_changed(is_fueled: bool)
signal power_state_changed(is_powered: bool)
signal end_day_ready_changed(ready_peer_ids: Array[int])
signal sleeping_state_changed(sleeping_peer_ids: Array[int])
signal end_day_consensus_reached(day_index: int)

enum BasePhase {
	ARRIVAL,
	RESTORING_POWER,
	ACTIVE_DAY,
	ENDING_DAY,
}

const FIRST_DAY := 1
const MAX_PLAYERS := 2
const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://base_gameplay_state.cfg"
const TEST_SAVE_PATH_SETTING := "northern_lab/testing/base_save_path"

@export_range(1, 5, 1) var starting_day_index: int = FIRST_DAY

var day_index: int = FIRST_DAY
var phase: BasePhase = BasePhase.ARRIVAL
var fuel_delivered: bool = false
var main_breaker_on: bool = false
var end_day_ready_peer_ids: Array[int] = []
var sleeping_peer_ids: Array[int] = []
var _end_day_consensus_announced: bool = false


func _ready() -> void:
	add_to_group("base_gameplay_controller")
	var steam_network := get_node_or_null("/root/SteamNetwork")
	if (
		steam_network != null
		and steam_network.has_signal("peer_left")
		and not steam_network.is_connected("peer_left", _on_peer_left)
	):
		steam_network.connect("peer_left", _on_peer_left)
	if (
		steam_network != null
		and steam_network.has_signal("peer_joined")
		and not steam_network.is_connected("peer_joined", _on_peer_joined)
	):
		steam_network.connect("peer_joined", _on_peer_joined)
	var initial_snapshot := _make_snapshot(
		clampi(starting_day_index, 1, 5),
		BasePhase.ARRIVAL,
		false,
		false,
		[],
		[]
	)
	if multiplayer.is_server():
		var saved_snapshot := load_saved_snapshot()
		if not saved_snapshot.is_empty():
			initial_snapshot = saved_snapshot
	_apply_snapshot(initial_snapshot, true)


func get_snapshot() -> Dictionary:
	return _make_snapshot(
		day_index,
		phase,
		fuel_delivered,
		main_breaker_on,
		end_day_ready_peer_ids,
		sleeping_peer_ids
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
			end_day_ready_peer_ids,
			sleeping_peer_ids
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
			end_day_ready_peer_ids,
			sleeping_peer_ids
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
	var next_sleeping_peer_ids := sleeping_peer_ids.duplicate()
	if is_ready and not next_ready_peer_ids.has(peer_id):
		next_ready_peer_ids.append(peer_id)
	elif not is_ready:
		next_ready_peer_ids.erase(peer_id)
		next_sleeping_peer_ids.erase(peer_id)
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
			next_ready_peer_ids,
			next_sleeping_peer_ids
		)
	)
	return true


func set_peer_sleeping_authoritative(peer_id: int, is_sleeping: bool) -> bool:
	if (
		not _can_mutate_for_peer(peer_id)
		or phase != BasePhase.ENDING_DAY
		or not end_day_ready_peer_ids.has(peer_id)
	):
		return false
	var next_sleeping_peer_ids := sleeping_peer_ids.duplicate()
	if is_sleeping and not next_sleeping_peer_ids.has(peer_id):
		next_sleeping_peer_ids.append(peer_id)
	elif not is_sleeping:
		next_sleeping_peer_ids.erase(peer_id)
	next_sleeping_peer_ids.sort()
	_broadcast_snapshot(_make_snapshot(
		day_index,
		phase,
		fuel_delivered,
		main_breaker_on,
		end_day_ready_peer_ids,
		next_sleeping_peer_ids
	))
	return true


func are_all_connected_players_ready() -> bool:
	if end_day_ready_peer_ids.is_empty():
		return false
	var connected_peer_ids := get_connected_player_peer_ids()
	if connected_peer_ids.is_empty():
		return false
	for peer_id in connected_peer_ids:
		if not end_day_ready_peer_ids.has(peer_id):
			return false
	return true


func is_peer_ready_to_end_day(peer_id: int) -> bool:
	return end_day_ready_peer_ids.has(peer_id)


func is_peer_sleeping(peer_id: int) -> bool:
	return sleeping_peer_ids.has(peer_id)


func are_all_connected_players_sleeping() -> bool:
	if sleeping_peer_ids.is_empty():
		return false
	for peer_id in get_connected_player_peer_ids():
		if not sleeping_peer_ids.has(peer_id):
			return false
	return true


func get_connected_player_peer_ids() -> Array[int]:
	return _get_connected_player_peer_ids()


func get_player_slot(peer_id: int) -> int:
	return get_connected_player_peer_ids().find(peer_id)


func get_peer_for_player_slot(player_slot: int) -> int:
	var peer_ids := get_connected_player_peer_ids()
	if player_slot < 0 or player_slot >= peer_ids.size():
		return 0
	return peer_ids[player_slot]


func get_player_display_name(peer_id: int) -> String:
	var player_node := _find_player_node(peer_id)
	if player_node != null:
		var display_name := str(player_node.get("player_display_name")).strip_edges()
		if not display_name.is_empty():
			return display_name
	var steam_network := get_node_or_null("/root/SteamNetwork")
	if steam_network != null and steam_network.has_method("get_peer_persona_name"):
		var steam_name := str(
			steam_network.call("get_peer_persona_name", peer_id)
		).strip_edges()
		if not steam_name.is_empty():
			return steam_name
	return "Игрок %d" % (get_player_slot(peer_id) + 1)


func get_player_node(peer_id: int) -> Node:
	return _find_player_node(peer_id)


func reset_day_one_authoritative() -> bool:
	if not multiplayer.is_server():
		return false
	_broadcast_snapshot(
		_make_snapshot(FIRST_DAY, BasePhase.ARRIVAL, false, false, [], [])
	)
	return true


func advance_day_authoritative() -> bool:
	if (
		not multiplayer.is_server()
		or not are_all_connected_players_sleeping()
		or day_index >= 5
	):
		return false
	_broadcast_snapshot(
		_make_snapshot(
			day_index + 1,
			BasePhase.ACTIVE_DAY,
			fuel_delivered,
			main_breaker_on,
			[],
			[]
		)
	)
	return true


func save_progress_authoritative() -> bool:
	if not multiplayer.is_server():
		return false
	var config := ConfigFile.new()
	var snapshot := _make_persistent_snapshot()
	config.set_value("save", "version", SAVE_VERSION)
	for key in snapshot:
		config.set_value("base", str(key), snapshot[key])
	var error := config.save(_get_save_path())
	if error != OK:
		push_warning("Could not save base progress: %s" % error_string(error))
		return false
	return true


func load_saved_snapshot() -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(_get_save_path())
	if error == ERR_FILE_NOT_FOUND:
		return {}
	if error != OK:
		push_warning("Could not load base progress: %s" % error_string(error))
		return {}
	if int(config.get_value("save", "version", 0)) != SAVE_VERSION:
		return {}
	var saved_fuel := bool(config.get_value("base", "fuel_delivered", false))
	var saved_power := bool(config.get_value("base", "main_breaker_on", false))
	var saved_phase := clampi(
		int(config.get_value("base", "phase", BasePhase.ARRIVAL)),
		BasePhase.ARRIVAL,
		BasePhase.ACTIVE_DAY
	) as BasePhase
	return _make_snapshot(
		int(config.get_value("base", "day_index", FIRST_DAY)),
		saved_phase,
		saved_fuel,
		saved_power,
		[],
		[]
	)


func clear_saved_progress_authoritative() -> bool:
	if not multiplayer.is_server():
		return false
	return delete_progress_save()


static func has_progress_save_file() -> bool:
	return FileAccess.file_exists(get_progress_save_path())


static func get_saved_progress_summary() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(get_progress_save_path()) != OK:
		return {}
	if int(config.get_value("save", "version", 0)) != SAVE_VERSION:
		return {}
	var saved_day := int(config.get_value("base", "day_index", 0))
	if saved_day < FIRST_DAY or saved_day > 5:
		return {}
	return {
		"day_index": saved_day,
		"phase": int(config.get_value("base", "phase", BasePhase.ARRIVAL)),
		"fuel_delivered": bool(config.get_value(
			"base",
			"fuel_delivered",
			false
		)),
		"main_breaker_on": bool(config.get_value(
			"base",
			"main_breaker_on",
			false
		)),
	}


static func delete_progress_save() -> bool:
	var absolute_path := ProjectSettings.globalize_path(
		get_progress_save_path()
	)
	if not FileAccess.file_exists(absolute_path):
		return true
	return DirAccess.remove_absolute(absolute_path) == OK


static func get_progress_save_path() -> String:
	return str(ProjectSettings.get_setting(
		TEST_SAVE_PATH_SETTING,
		DEFAULT_SAVE_PATH
	))


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	_receive_snapshot.rpc_id(peer_id, get_snapshot())


func _broadcast_snapshot(snapshot: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_receive_snapshot.rpc(snapshot)
	_update_end_day_consensus_signal()


@rpc("authority", "call_local", "reliable")
func _receive_snapshot(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)


func _apply_snapshot(snapshot: Dictionary, force_signals: bool = false) -> void:
	var previous_day := day_index
	var previous_phase := phase
	var previous_fuel := fuel_delivered
	var previous_power := main_breaker_on
	var previous_ready := end_day_ready_peer_ids.duplicate()
	var previous_sleeping := sleeping_peer_ids.duplicate()

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
	sleeping_peer_ids = _normalize_peer_ids(
		snapshot.get("sleeping_peer_ids", []) as Array
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
	if force_signals or previous_sleeping != sleeping_peer_ids:
		sleeping_state_changed.emit(sleeping_peer_ids.duplicate())
	snapshot_changed.emit(get_snapshot())
	if multiplayer.is_server():
		save_progress_authoritative()


func _make_snapshot(
	next_day_index: int,
	next_phase: BasePhase,
	next_fuel_delivered: bool,
	next_main_breaker_on: bool,
	next_ready_peer_ids: Array,
	next_sleeping_peer_ids: Array = []
) -> Dictionary:
	return {
		"day_index": clampi(next_day_index, 1, 5),
		"phase": int(next_phase),
		"fuel_delivered": next_fuel_delivered,
		"main_breaker_on": next_main_breaker_on and next_fuel_delivered,
		"end_day_ready_peer_ids": _normalize_peer_ids(next_ready_peer_ids),
		"sleeping_peer_ids": _normalize_peer_ids(next_sleeping_peer_ids),
	}


func _normalize_peer_ids(peer_ids: Array) -> Array[int]:
	var normalized: Array[int] = []
	for peer_id_variant in peer_ids:
		var peer_id := int(peer_id_variant)
		if peer_id > 0 and not normalized.has(peer_id):
			normalized.append(peer_id)
	normalized.sort()
	return normalized


func _make_persistent_snapshot() -> Dictionary:
	var persistent_phase := phase
	if persistent_phase == BasePhase.ENDING_DAY:
		persistent_phase = (
			BasePhase.ACTIVE_DAY
			if main_breaker_on
			else BasePhase.RESTORING_POWER
			if fuel_delivered
			else BasePhase.ARRIVAL
		)
	return _make_snapshot(
		day_index,
		persistent_phase,
		fuel_delivered,
		main_breaker_on,
		[],
		[]
	)


func _get_save_path() -> String:
	return get_progress_save_path()


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


func _find_player_node(peer_id: int) -> Node:
	var gameplay_controller := get_tree().get_first_node_in_group(
		"network_gameplay_controller"
	)
	if gameplay_controller != null:
		var players_node := gameplay_controller.get_node_or_null("Players")
		if players_node != null:
			var network_player := players_node.get_node_or_null(str(peer_id))
			if network_player != null:
				return network_player
			for player_node in players_node.get_children():
				if int(player_node.get("owner_peer_id")) == peer_id:
					return player_node
	var runtime_players := get_parent().get_node_or_null("RuntimePlayers")
	if runtime_players != null:
		return runtime_players.get_node_or_null(str(peer_id))
	return null


func _on_peer_left(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var next_ready_peer_ids := end_day_ready_peer_ids.duplicate()
	var next_sleeping_peer_ids := sleeping_peer_ids.duplicate()
	next_ready_peer_ids.erase(peer_id)
	next_sleeping_peer_ids.erase(peer_id)
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
			next_ready_peer_ids,
			next_sleeping_peer_ids
		)
	)
	call_deferred("_refresh_roster_dependent_state")


func _on_peer_joined(_peer_id: int) -> void:
	if multiplayer.is_server():
		call_deferred("_refresh_roster_dependent_state")


func _refresh_roster_dependent_state() -> void:
	if multiplayer.is_server():
		_apply_snapshot(get_snapshot(), true)
		_update_end_day_consensus_signal()


func _update_end_day_consensus_signal() -> void:
	if not multiplayer.is_server():
		return
	var has_consensus := (
		phase == BasePhase.ENDING_DAY
		and are_all_connected_players_sleeping()
	)
	if has_consensus and not _end_day_consensus_announced:
		_end_day_consensus_announced = true
		end_day_consensus_reached.emit(day_index)
	elif not has_consensus:
		_end_day_consensus_announced = false
