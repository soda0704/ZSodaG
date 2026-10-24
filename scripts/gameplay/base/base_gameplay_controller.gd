class_name BaseGameplayController
extends Node

signal snapshot_changed(snapshot: Dictionary)
signal clicker_changed()
signal phase_changed(phase: int)
signal day_changed(day_index: int)
signal fuel_state_changed(is_fueled: bool)
signal power_state_changed(is_powered: bool)
signal lighting_fault_started()
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
const MAX_DAY_INDEX := ExpeditionSaveStore.MAX_DAY_INDEX
const MAX_PLAYERS := 2
const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://base_gameplay_state.cfg"
const COOP_SAVE_PATH := "user://base_gameplay_state_coop.cfg"
const TEST_SAVE_PATH_SETTING := "northern_lab/testing/base_save_path"
static var save_scope: String = "solo"

enum QuestStage { UNAVAILABLE, OFFERED, ACCEPTED, COLLECTED, DELIVERED }
var quest_stage: QuestStage = QuestStage.UNAVAILABLE

@export_range(1, 7, 1) var starting_day_index: int = FIRST_DAY
const LEVEL_TWO_DAY_INDEX := 3
const TRIALS_DAY_INDEX := 4
const CONTAINMENT_DAY_INDEX := 5
const EXPEDITION_DAY_INDEX := 6
const CAVE_DAY_INDEX := 7
var _last_checkpoint_msec := -5000

var day_index: int = FIRST_DAY
var phase: BasePhase = BasePhase.ARRIVAL
var fuel_delivered: bool = false
const FUEL_CAPACITY := 60.0
const FUEL_PER_SECOND := 0.015
var fuel_liters := 0.0
var _fuel_tick := 0.0


var clicker := LabClicker.new()
var _clicker_sync_elapsed := 0.0
var _last_clicker_sync: Dictionary = {}

func _process(delta: float) -> void:
	_process_clicker(delta)
	if not multiplayer.is_server() or not main_breaker_on:
		return
	fuel_liters = maxf(0.0, fuel_liters - delta * FUEL_PER_SECOND)
	_fuel_tick += delta
	if _fuel_tick >= 5.0 or fuel_liters <= 0.0:
		_fuel_tick = 0.0
		var snapshot := get_snapshot()
		if fuel_liters <= 0.0:
			snapshot.main_breaker_on = false
			snapshot.fuel_delivered = false
		# Fuel replication is not a new checkpoint every tick; depletion is important.
		_broadcast_snapshot(snapshot, fuel_liters <= 0.0)


func refill_authoritative(peer_id: int, amount: float) -> float:
	if not _can_mutate_for_peer(peer_id) or amount <= 0.0:
		return 0.0
	var added := minf(amount, FUEL_CAPACITY - fuel_liters)
	if added <= 0.0:
		return 0.0
	fuel_liters += added
	var snapshot := get_snapshot()
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = fuel_liters
	if phase == BasePhase.ARRIVAL:
		snapshot.phase = BasePhase.RESTORING_POWER
	_broadcast_snapshot(snapshot)
	return added
var main_breaker_on: bool = false
var elevator_backup_installed: bool = false
var end_day_ready_peer_ids: Array[int] = []
var sleeping_peer_ids: Array[int] = []
var _end_day_consensus_announced: bool = false
var inventory_checkpoint: Dictionary = {}
var containment: Dictionary = {}
var maintenance: Dictionary = {}
const PLANT_FINAL_STAGE := 7
var plant_growth_stage := 0
var plant_withered := false
var plant_seed_planted := false
var plant_last_watered_day: int = 0
var has_authoritative_snapshot := false
var applying_initial_snapshot := false
var progress_persistence_enabled := true
var _owns_saved_progress := false


func _ready() -> void:
	_owns_saved_progress = multiplayer.is_server()
	has_authoritative_snapshot = multiplayer.is_server()
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
		clampi(starting_day_index, FIRST_DAY, MAX_DAY_INDEX),
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
	if multiplayer.is_server() and not initial_snapshot.maintenance.has("journal_campaign_id"):
		initial_snapshot.maintenance["journal_campaign_id"] = "%s_%s" % [Time.get_unix_time_from_system(), randi()]
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
	fuel_liters = 20.0
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
		or bool(maintenance.get("wires_required", false))
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


func deactivate_main_breaker_authoritative(peer_id: int) -> bool:
	if not _can_mutate_for_peer(peer_id) or not main_breaker_on:
		return false
	var snapshot := get_snapshot()
	snapshot.main_breaker_on = false
	snapshot.phase = BasePhase.RESTORING_POWER
	# Sleeping/ready votes cannot carry a powered-down base into the next day.
	snapshot.end_day_ready_peer_ids = []
	snapshot.sleeping_peer_ids = []
	_broadcast_snapshot(snapshot)
	return true


func set_end_day_ready_authoritative(peer_id: int, is_ready: bool) -> bool:
	if (
		not _can_mutate_for_peer(peer_id)
		or phase not in [BasePhase.ACTIVE_DAY, BasePhase.ENDING_DAY]
		or (is_ready and not can_end_current_day())
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


func can_end_current_day() -> bool:
	return main_breaker_on and (
		(day_index == 1 and elevator_backup_installed)
		or (day_index == 2 and quest_stage == QuestStage.DELIVERED)
		or (day_index == LEVEL_TWO_DAY_INDEX and bool(containment.get("level2", false)))
		or (day_index == TRIALS_DAY_INDEX and bool(containment.get("trials", false)))
		or (day_index == CONTAINMENT_DAY_INDEX and bool(containment.get("level3", false)) and bool(containment.get("resolved", false)))
		or (day_index == EXPEDITION_DAY_INDEX and is_winch_prepared())
		or (day_index >= CAVE_DAY_INDEX and are_cave_hives_destroyed() and bool(containment.get("cave_exited", false)))
	)


func is_elevator_powered() -> bool:
	return main_breaker_on or elevator_backup_installed

func has_entered_base() -> bool:
	# Existing progressed saves already imply a visit, even before this flag existed.
	return bool(maintenance.get("base_entered", false)) or day_index > FIRST_DAY or phase != BasePhase.ARRIVAL or fuel_delivered or main_breaker_on or elevator_backup_installed


func get_winch_preparation() -> Dictionary:
	return maintenance.get("winch_preparation", {}) as Dictionary


func is_winch_prepared() -> bool:
	return bool(get_winch_preparation().get("tested", false))


func get_destroyed_cave_hive_count() -> int:
	var health: Array = containment.get("cave_hive_health", [])
	var destroyed := 0
	for index in mini(health.size(), 3):
		if is_finite(float(health[index])) and float(health[index]) <= 0.0: destroyed += 1
	return destroyed


func are_cave_hives_destroyed() -> bool:
	return bool(containment.get("cave_hives_found", false)) and get_destroyed_cave_hive_count() == 3


func get_expedition_objective() -> Dictionary:
	var tasks: Array[Dictionary] = []
	var title := ""
	var note := ""
	var description := ""
	if day_index == CONTAINMENT_DAY_INDEX:
		var entered := bool(containment.get("level3", false))
		var cleared := bool(containment.get("fault", false)) or bool(containment.get("resolved", false))
		title = "Зачистить уровень 4" if entered else "Обследовать уровень 4"
		tasks.append({"done": entered, "text": "Спуститься на уровень 4"})
		if entered: tasks.append({"done": cleared, "text": "Зачистить уровень"})
		if cleared:
			tasks.append({"done": bool(containment.get("resolved", false)), "text": "Восстановить питание"})
			if containment.get("fault", false): note = "Сбой питания: выключите и включите главный щит."
	elif day_index == EXPEDITION_DAY_INDEX:
		var preparation := get_winch_preparation()
		title = "Перед следующим спуском"
		tasks.append({"done": bool(preparation.get("inspected", false)), "text": "Спуститься на уровень 5 и осмотреть пульт лебёдки"})
		if preparation.get("inspected", false):
			tasks.append({"done": bool(preparation.get("pin_removed", false)), "text": "Убрать стопорный штифт у барабана"})
			if not preparation.get("brake_armed", false): note = "Транспортный стопор удерживает механизм рядом с барабаном в машинном отделении."
		if preparation.get("pin_removed", false):
			tasks.append({"done": bool(preparation.get("brake_armed", false)), "text": "Перевести рычаг в рабочее положение"})
		if preparation.get("brake_armed", false):
			tasks.append({"done": is_winch_prepared(), "text": "Проверить механизм с пульта"})
			if preparation.get("testing", false): note = "Механизм проходит пробный цикл; проём клети должен оставаться свободным."
	elif day_index >= CAVE_DAY_INDEX:
		title = "За последним уровнем"
		var visited := bool(containment.get("cave_visited", false))
		var found := bool(containment.get("cave_hives_found", false))
		var cleared := are_cave_hives_destroyed()
		var exited := cleared and bool(containment.get("cave_exited", false))
		tasks.append({"done": visited, "text": "Найти продолжение шахты под комплексом"})
		description = "Лебёдка ведёт глубже лаборатории — что осталось внизу, пока неизвестно."
		if visited or found:
			tasks.append({"done": found, "text": "Исследовать пещеру"})
		if found:
			title = "В глубине"
			description = "В конце пещеры обнаружены три улья. Нужно уничтожить их, прежде чем покинуть это место."
			var crafted := int(maintenance.get("flamethrower_crafting",{}).get("crafted",0))
			if not cleared or crafted > 0:
				tasks.append({"done": crafted > 0, "text": "Собрать огнемёт"})
			if not cleared:
				description += " Схему сборки можно рассмотреть на столе в комнате снаряжения уровня 0."
			tasks.append({"done": cleared, "text": "Уничтожить ульи (%d/3)" % get_destroyed_cave_hive_count()})
		if cleared:
			title = "Наружу"
			description = "Ульи уничтожены. Осталось найти выход из пещеры."
			tasks.append({"done": exited, "text": "Выйти наружу"})
		if exited:
			title = "По ту сторону"
			description = "Три улья уничтожены. Вы выбрались наружу."
	if day_index < CAVE_DAY_INDEX and not tasks.is_empty() and tasks.all(func(task): return task.done):
		note = "Вернуться на базу и отдохнуть."
	return {"title": title, "tasks": tasks, "note": note, "description": description}


func install_elevator_backup_authoritative(peer_id: int) -> bool:
	if not _can_mutate_for_peer(peer_id) or elevator_backup_installed:
		return false
	var player := get_player_node(peer_id) as GamePlayer
	var socket := get_tree().get_first_node_in_group("elevator_backup_socket") as Node3D
	if (
		player == null or socket == null
		or player.survival.dead or player.is_sleeping_in_bunk()
		or player.is_carrying_corpse()
		or player.global_position.distance_to(socket.global_position) > float(socket.get("interaction_distance"))
	):
		return false
	if not player.consume_held_item_authoritative(GamePlayer.FUSE_ITEM):
		return false
	# Inventory consumption schedules its checkpoint; this snapshot includes both
	# the installed fuse and the updated inventory before that deferred save runs.
	elevator_backup_installed = true
	_broadcast_snapshot(get_snapshot())
	return true


func advance_quest_authoritative(peer_id: int, expected_stage: QuestStage) -> bool:
	if (
		not _can_mutate_for_peer(peer_id)
		or day_index != 2
		or not main_breaker_on
		or quest_stage != expected_stage
		or expected_stage not in [QuestStage.OFFERED, QuestStage.ACCEPTED, QuestStage.COLLECTED]
	):
		return false
	var snapshot := get_snapshot()
	# OFFERED now means the key is available, without a preliminary hub visit.
	# ACCEPTED remains readable for existing saves.
	snapshot["quest_stage"] = int(QuestStage.COLLECTED) if quest_stage == QuestStage.OFFERED else int(quest_stage) + 1
	_broadcast_snapshot(snapshot)
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
	maintenance = {}
	elevator_backup_installed = false
	plant_growth_stage = 0
	plant_withered = false
	plant_seed_planted = false
	plant_last_watered_day = 0
	clicker.restore({})
	_broadcast_snapshot(
		_make_snapshot(FIRST_DAY, BasePhase.ARRIVAL, false, false, [], [])
	)
	return true


func advance_day_authoritative() -> bool:
	if (
		not multiplayer.is_server()
		or not are_all_connected_players_sleeping()
		or day_index >= MAX_DAY_INDEX
		or not can_end_current_day()
	):
		return false
	var next := _make_snapshot(
			day_index + 1,
			BasePhase.ACTIVE_DAY,
			fuel_delivered,
			main_breaker_on,
			[],
			[]
	)
	_age_plant(next, day_index, day_index + 1)
	if day_index == 1:
		var order := [0, 1, 2, 3]
		order.shuffle()
		# A repair should always require crossing at least two wires.
		if order == [0, 1, 2, 3]:
			order = [2, 0, 3, 1]
		next.maintenance["wires_required"] = true
		next.maintenance["wire_order"] = order
		next.maintenance["wire_links"] = []
		next.maintenance["alarm"] = true
		next.main_breaker_on = false
		next.phase = BasePhase.RESTORING_POWER
	_broadcast_snapshot(next)
	return true


func _age_plant(snapshot: Dictionary, from_day: int, to_day: int) -> void:
	for elapsed_day in range(from_day, to_day):
		if not snapshot.plant_seed_planted or snapshot.plant_withered:
			break
		if int(snapshot.plant_last_watered_day) == elapsed_day:
			snapshot.plant_growth_stage = mini(int(snapshot.plant_growth_stage) + 1, PLANT_FINAL_STAGE)
		else:
			snapshot.plant_withered = true


func debug_set_day_authoritative(next_day: int) -> bool:
	if not multiplayer.is_server() or next_day < FIRST_DAY or next_day > MAX_DAY_INDEX:
		return false
	var snapshot := get_snapshot()
	_age_plant(snapshot, day_index, next_day)
	# Rewinding the calendar cannot leave a watering stamp in the future.
	if next_day < day_index:
		snapshot.plant_last_watered_day = mini(plant_last_watered_day, next_day - 1)
	snapshot.day_index = next_day
	snapshot.phase = BasePhase.ACTIVE_DAY
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = FUEL_CAPACITY
	snapshot.main_breaker_on = true
	snapshot.quest_stage = 4 if next_day >= 3 else 1
	snapshot.sleeping_peer_ids = []
	snapshot.end_day_ready_peer_ids = []
	_broadcast_snapshot(snapshot)
	return true


func save_progress_authoritative(periodic: bool = false, kind: String = "progress", label: String = "") -> bool:
	if not progress_persistence_enabled or not _owns_saved_progress or not multiplayer.is_server():
		return false
	if periodic and Time.get_ticks_msec() - _last_checkpoint_msec < 5000:
		return true
	var config := ConfigFile.new()
	var snapshot := _make_persistent_snapshot()
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	if world != null and world.has_method("capture_inventory_checkpoint"):
		var captured: Dictionary = world.call("capture_inventory_checkpoint")
		if not captured.is_empty():
			inventory_checkpoint = captured
	config.set_value("inventory", "checkpoint", inventory_checkpoint)
	config.set_value("save", "version", SAVE_VERSION)
	config.set_value("save", "label", label)
	for key in snapshot:
		config.set_value("base", str(key), snapshot[key])
	if not ExpeditionSaveStore.write(config, save_scope, kind):
		push_warning("Could not save expedition progress")
		return false
	_last_checkpoint_msec = Time.get_ticks_msec()
	return true


func save_story_checkpoint_authoritative(label: String) -> bool:
	# Future story triggers call this BEFORE applying a consequential event.
	return save_progress_authoritative(false, "event", label)


func load_saved_snapshot() -> Dictionary:
	if not progress_persistence_enabled:
		return {}
	var data := ExpeditionSaveStore.read(save_scope)
	if data.is_empty():
		return {}
	var config: ConfigFile = data.config
	if int(config.get_value("save", "version", 0)) != SAVE_VERSION:
		return {}
	inventory_checkpoint = config.get_value("inventory", "checkpoint", {}) as Dictionary
	var saved_fuel := bool(config.get_value("base", "fuel_delivered", false))
	var saved_power := bool(config.get_value("base", "main_breaker_on", false))
	var saved_phase := clampi(
		int(config.get_value("base", "phase", BasePhase.ARRIVAL)),
		BasePhase.ARRIVAL,
		BasePhase.ACTIVE_DAY
	) as BasePhase
	var snapshot := _make_snapshot(
		int(config.get_value("base", "day_index", FIRST_DAY)),
		saved_phase,
		saved_fuel,
		saved_power,
		[],
		[]
	)
	snapshot["quest_stage"] = int(config.get_value("base", "quest_stage", 0))
	snapshot["fuel_liters"] = float(config.get_value("base", "fuel_liters", 20.0 if saved_fuel else 0.0))
	snapshot["containment"] = config.get_value("base", "containment", {})
	snapshot["maintenance"] = config.get_value("base", "maintenance", {})
	# Earlier day-seven saves predate preparation; preserve access to the cave.
	if int(snapshot.day_index) >= CAVE_DAY_INDEX and not snapshot.maintenance.has("winch_preparation"):
		snapshot.maintenance["winch_preparation"] = {"inspected": true, "pin_removed": true, "brake_armed": true, "tested": true, "testing": false}
	elif snapshot.maintenance.has("winch_preparation"):
		# An interrupted test is retried at the console, never completed by loading.
		snapshot.maintenance["winch_preparation"]["testing"] = false
	snapshot["lab_clicker"] = config.get_value("base", "lab_clicker", {})
	snapshot["plant_growth_stage"] = int(config.get_value("base", "plant_growth_stage", 0))
	snapshot["plant_withered"] = bool(config.get_value("base", "plant_withered", false))
	snapshot["plant_seed_planted"] = bool(config.get_value("base", "plant_seed_planted", false))
	snapshot["plant_last_watered_day"] = int(config.get_value("base", "plant_last_watered_day", 0))
	# Existing campaigns beyond day one already used an always-powered elevator.
	# Keep that access; new campaigns must install the fuse before their first night.
	snapshot["elevator_backup_installed"] = bool(config.get_value(
		"base", "elevator_backup_installed", int(snapshot.day_index) > FIRST_DAY
	))
	# Preserve old combat progress when the former combined day is split in two.
	if int(config.get_value("base", "campaign_layout_version", 1)) < 2:
		var old_day := int(snapshot.day_index)
		var encounter_data: Dictionary = snapshot.containment
		var combat_started: bool = (
			bool(encounter_data.get("level3", false))
			or bool(encounter_data.get("fault", false))
			or bool(encounter_data.get("resolved", false))
			or not (encounter_data.get("bodies", {}) as Dictionary).is_empty()
			or encounter_data.get("health", [120.0, 90.0, 75.0]) != [120.0, 90.0, 75.0]
		)
		if old_day == 3 and combat_started:
			snapshot.day_index = CONTAINMENT_DAY_INDEX
			encounter_data["level2"] = true
			encounter_data["level3"] = true
		elif old_day >= 4:
			snapshot.day_index = mini(old_day + 1, 5)
	return snapshot


func clear_saved_progress_authoritative() -> bool:
	if not progress_persistence_enabled or not multiplayer.is_server():
		return false
	return delete_progress_save()


static func has_progress_save_file() -> bool:
	return not ExpeditionSaveStore.read(save_scope).is_empty() or FileAccess.file_exists(get_progress_save_path())


static func get_saved_progress_summary() -> Dictionary:
	return ExpeditionSaveStore.summary(save_scope)


static func delete_progress_save() -> bool:
	return ExpeditionSaveStore.clear(save_scope)


static func get_progress_save_path() -> String:
	if not ExpeditionSaveStore.test_path().is_empty():
		return ExpeditionSaveStore.test_path()
	var data := ExpeditionSaveStore.read(save_scope)
	return str(data.get("path", ExpeditionSaveStore.directory(save_scope).path_join("no_save.cfg")))


func sync_network_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return
	_receive_snapshot.rpc_id(peer_id, get_snapshot(), false, true)
	for terminal in get_tree().get_nodes_in_group("quest_terminals"):
		terminal.sync_app_to_peer(peer_id)


func _broadcast_snapshot(snapshot: Dictionary, persist: bool = true) -> void:
	if multiplayer.is_server() and not snapshot.maintenance.has("journal_campaign_id"):
		snapshot.maintenance["journal_campaign_id"] = "%s_%s" % [Time.get_unix_time_from_system(), randi()]
	if not multiplayer.is_server():
		return
	# A connecting peer may still be loading the threaded base scene.
	_receive_snapshot(snapshot, persist)
	for peer in clicker_ready_peers():
		_receive_snapshot.rpc_id(peer, snapshot, persist)
	_update_end_day_consensus_signal()


@rpc("authority", "call_local", "reliable")
func _receive_snapshot(snapshot: Dictionary, persist: bool = true, initial_sync: bool = false) -> void:
	applying_initial_snapshot = initial_sync or not has_authoritative_snapshot
	has_authoritative_snapshot = true
	_apply_snapshot(snapshot, false, persist)
	applying_initial_snapshot = false


func _apply_snapshot(snapshot: Dictionary, force_signals: bool = false, persist: bool = true) -> void:
	var previous_day := day_index
	var previous_phase := phase
	var previous_fuel := fuel_delivered
	var previous_power := main_breaker_on
	var previous_lighting_fault := bool(containment.get("fault", false))
	var previous_wiring_fault := bool(maintenance.get("wires_required", false))
	var previous_ready := end_day_ready_peer_ids.duplicate()
	var previous_sleeping := sleeping_peer_ids.duplicate()

	day_index = clampi(int(snapshot.get("day_index", FIRST_DAY)), FIRST_DAY, MAX_DAY_INDEX)
	phase = clampi(
		int(snapshot.get("phase", BasePhase.ARRIVAL)),
		BasePhase.ARRIVAL,
		BasePhase.ENDING_DAY
	) as BasePhase
	fuel_delivered = bool(snapshot.get("fuel_delivered", false))
	fuel_liters = clampf(float(snapshot.get("fuel_liters", 20.0 if fuel_delivered else 0.0)), 0.0, FUEL_CAPACITY)
	main_breaker_on = (
		bool(snapshot.get("main_breaker_on", false)) and fuel_delivered
	)
	elevator_backup_installed = bool(snapshot.get("elevator_backup_installed", false))
	quest_stage = clampi(int(snapshot.get("quest_stage", 0)), 0, 4) as QuestStage
	containment = (snapshot.get("containment", {}) as Dictionary).duplicate(true)
	maintenance = (snapshot.get("maintenance", {}) as Dictionary).duplicate(true)
	var clicker_data: Variant = snapshot.get("lab_clicker", {})
	clicker.restore(clicker_data if clicker_data is Dictionary else {})
	clicker_changed.emit()
	plant_growth_stage = clampi(int(snapshot.get("plant_growth_stage", 0)), 0, PLANT_FINAL_STAGE)
	plant_withered = bool(snapshot.get("plant_withered", false))
	plant_seed_planted = bool(snapshot.get("plant_seed_planted", false))
	plant_last_watered_day = clampi(int(snapshot.get("plant_last_watered_day", 0)), 0, day_index)
	if bool(maintenance.get("wires_required", false)):
		main_breaker_on = false
	if previous_power and not main_breaker_on and phase != BasePhase.ARRIVAL:
		maintenance["alarm"] = true
	if main_breaker_on:
		maintenance["alarm"] = false
	if day_index == 1:
		quest_stage = QuestStage.UNAVAILABLE
	elif quest_stage == QuestStage.UNAVAILABLE:
		quest_stage = QuestStage.OFFERED
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
	# State restoration and late joins must not replay an earlier outage.
	var new_lighting_fault := not previous_lighting_fault and bool(containment.get("fault", false))
	var new_wiring_fault := not previous_wiring_fault and bool(maintenance.get("wires_required", false))
	if not force_signals and not applying_initial_snapshot and (new_lighting_fault or new_wiring_fault):
		lighting_fault_started.emit()
	if multiplayer.is_server() and persist:
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
		"day_index": clampi(next_day_index, FIRST_DAY, MAX_DAY_INDEX),
		"phase": int(next_phase),
		"fuel_delivered": next_fuel_delivered,
		"fuel_liters": fuel_liters if next_fuel_delivered else 0.0,
		"main_breaker_on": next_main_breaker_on and next_fuel_delivered,
		"elevator_backup_installed": elevator_backup_installed,
		"end_day_ready_peer_ids": _normalize_peer_ids(next_ready_peer_ids),
		"sleeping_peer_ids": _normalize_peer_ids(next_sleeping_peer_ids),
		"quest_stage": int(quest_stage) if next_day_index > 1 else 0,
		"containment": containment.duplicate(true),
		"maintenance": maintenance.duplicate(true),
		"lab_clicker": clicker.capture_runtime(),
		"plant_growth_stage": plant_growth_stage,
		"plant_withered": plant_withered,
		"plant_seed_planted": plant_seed_planted,
		"plant_last_watered_day": plant_last_watered_day,
	}


func plant_seed_authoritative(peer_id: int) -> bool:
	if not _can_mutate_for_peer(peer_id) or plant_seed_planted:
		return false
	var socket := get_tree().get_first_node_in_group("plant_seed_socket")
	var player := get_player_node(peer_id) as GamePlayer
	if socket == null or not bool(socket.call("can_use", peer_id, player)):
		return false
	if not player.consume_held_item_authoritative(GamePlayer.SEED_ITEM):
		return false
	var snapshot := get_snapshot()
	snapshot.plant_growth_stage = 0
	snapshot.plant_withered = false
	snapshot.plant_seed_planted = true
	_broadcast_snapshot(snapshot)
	return true


func water_plant_authoritative(peer_id: int) -> bool:
	if not _can_mutate_for_peer(peer_id) or not plant_seed_planted or plant_withered or not main_breaker_on or plant_last_watered_day >= day_index:
		return false
	var button := get_tree().get_first_node_in_group("plant_watering_button")
	if button == null or not bool(button.call("can_use", peer_id, get_player_node(peer_id))):
		return false
	var snapshot := get_snapshot()
	snapshot.plant_last_watered_day = day_index
	# Commit the shared daily use before any presentation starts. Simultaneous
	# input and re-sent interaction packets cannot start another watering cycle.
	_broadcast_snapshot(snapshot)
	return true


func connect_wire_authoritative(peer: int, left: int, right: int) -> bool:
	if not _can_mutate_for_peer(peer) or not maintenance.get("wires_required", false):
		return false
	var player := get_player_node(peer) as Node3D
	var breaker := get_tree().get_first_node_in_group("main_breaker") as Node3D
	if breaker == null or not bool(breaker.call("can_use", peer, player)):
		return false
	var order: Array = maintenance.get("wire_order", [])
	var links: Array = maintenance.get("wire_links", []).duplicate()
	if order.size() != 4 or left < 0 or left >= 4 or right < 0 or right >= 4 or right != int(order[left]) or links.has(left):
		return false
	links.append(left)
	var snapshot := get_snapshot()
	snapshot.maintenance["wire_links"] = links
	if links.size() == 4:
		snapshot.maintenance["wires_required"] = false
	_broadcast_snapshot(snapshot)
	return true


@rpc("any_peer", "call_remote", "reliable")
func request_wire(left: int, right: int) -> void:
	connect_wire_authoritative(multiplayer.get_remote_sender_id(), left, right)


@rpc("authority", "call_local", "reliable")
func open_wiring_ui() -> void:
	if get_tree().get_first_node_in_group("wiring_ui") != null or not maintenance.get("wires_required", false):
		return
	var breaker := get_tree().get_first_node_in_group("main_breaker") as Node3D
	if breaker != null: breaker.get_node("Wiring").call("begin")


func _normalize_peer_ids(peer_ids: Array) -> Array[int]:
	var normalized: Array[int] = []
	for peer_id_variant in peer_ids:
		var peer_id := int(peer_id_variant)
		if peer_id > 0 and not normalized.has(peer_id):
			normalized.append(peer_id)
	normalized.sort()
	return normalized


func _make_persistent_snapshot() -> Dictionary:
	var encounter := get_tree().get_first_node_in_group("containment_encounter") if is_inside_tree() else null
	if encounter != null and encounter.state == self and day_index >= 3:
		containment["bodies"] = encounter.capture_bodies()
	var persistent_phase := phase
	if persistent_phase == BasePhase.ENDING_DAY:
		persistent_phase = (
			BasePhase.ACTIVE_DAY
			if main_breaker_on
			else BasePhase.RESTORING_POWER
			if fuel_delivered
			else BasePhase.ARRIVAL
		)
	var persistent := _make_snapshot(
		day_index,
		persistent_phase,
		fuel_delivered,
		main_breaker_on,
		[],
		[]
	)
	persistent["lab_clicker"] = clicker.capture()
	persistent["campaign_layout_version"] = 2
	if is_inside_tree():
		for transport in get_tree().get_nodes_in_group("elevator_controllers"):
			persistent.maintenance[transport.checkpoint_key] = int(transport.current_floor_index)
		for vehicle_node in get_tree().get_nodes_in_group("snowmobiles"):
			persistent.maintenance["snowmobile"] = vehicle_node.capture_checkpoint()
	if is_inside_tree():
		var recovery: Dictionary = persistent.maintenance.get("corpse_recovery", {}).duplicate(true)
		var bodies: Dictionary = recovery.get("bodies", {}).duplicate(true)
		for corpse in get_tree().get_nodes_in_group("medical_corpses"):
			if corpse.initialized and corpse.state == self:
				bodies[str(corpse.corpse_id)] = corpse.capture_checkpoint()
		recovery["bodies"] = bodies
		persistent.maintenance["corpse_recovery"] = recovery
	return persistent


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
	var next_phase := phase
	if phase == BasePhase.ENDING_DAY:
		next_phase = (
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
		# Roster refresh only needs snapshot_changed (bunks/journal). Re-emitting
		# day_changed sends elevator RPCs before a joining peer has loaded V3.
		_apply_snapshot(get_snapshot())
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


func _process_clicker(delta: float) -> void:
	if not multiplayer.is_server(): return
	var playing := false
	for terminal in get_tree().get_nodes_in_group("quest_terminals"):
		if terminal.operator_peer > 0 and terminal.ui.app_open:
			playing = true
			break
	clicker.advance(delta, playing, main_breaker_on)
	if not main_breaker_on: return
	_clicker_sync_elapsed += delta
	if _clicker_sync_elapsed >= 0.2:
		_clicker_sync_elapsed = 0.0
		var data := clicker.capture_runtime()
		if data == _last_clicker_sync: return
		_last_clicker_sync = data.duplicate(true)
		_receive_clicker_state(data)
		for peer in clicker_ready_peers(): _receive_clicker_state.rpc_id(peer, data)


@rpc("authority", "call_local", "reliable")
func _receive_clicker_state(data: Dictionary) -> void:
	# The host's clock is never rounded back to an older client projection.
	if not multiplayer.is_server(): clicker.restore(data)
	clicker_changed.emit()


func clicker_ready_peers() -> PackedInt32Array:
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	if world != null and world.has_method("get_ready_v3_peers"):
		return PackedInt32Array(world.get_ready_v3_peers())
	return multiplayer.get_peers()
