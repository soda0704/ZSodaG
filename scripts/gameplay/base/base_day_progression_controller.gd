class_name BaseDayProgressionController
extends Node

@export var gameplay_controller_path := NodePath("../BaseGameplayController")
@export var elevator_controller_path := NodePath(
	"../Elevator_Functional_Blockout"
)
@export_range(1.0, 30.0, 0.1) var sleep_duration := 5.0

var _gameplay_controller: BaseGameplayController
var _elevator_controller: FunctionalElevatorController
var _sleep_transition_serial := 0
var _aborting_sleep := false
var _prepared_wake_poses := {}
var _sleep_check_elapsed := 0.0

func _process(delta: float) -> void:
	_sleep_check_elapsed+=delta
	if _sleep_check_elapsed<.2 or not multiplayer.is_server() or _gameplay_controller==null: return
	_sleep_check_elapsed=0.0
	for peer in _gameplay_controller.sleeping_peer_ids:
		var player := _gameplay_controller.get_player_node(peer) as GamePlayer
		if player!=null and player.survival.dead:
			_abort_night();break

func _abort_night() -> void:
	if _aborting_sleep or not multiplayer.is_server(): return
	_aborting_sleep=true;_sleep_transition_serial+=1
	for bunk in get_tree().get_nodes_in_group("end_day_bunks"):
		if get_parent().is_ancestor_of(bunk):
			var peer := _gameplay_controller.get_peer_for_player_slot(bunk.assigned_player_slot)
			var player := _gameplay_controller.get_player_node(peer)
			if player!=null: bunk.cancel_sleep_authoritative(peer,player)
	_aborting_sleep=false


func _ready() -> void:
	call_deferred("_bind_runtime")


func _bind_runtime() -> void:
	_gameplay_controller = get_node_or_null(
		gameplay_controller_path
	) as BaseGameplayController
	_elevator_controller = get_node_or_null(
		elevator_controller_path
	) as FunctionalElevatorController
	if _gameplay_controller == null:
		push_warning("BaseDayProgressionController could not find gameplay state")
		return
	if not _gameplay_controller.day_changed.is_connected(_on_day_changed):
		_gameplay_controller.day_changed.connect(_on_day_changed)
	if not _gameplay_controller.end_day_consensus_reached.is_connected(
		_on_end_day_consensus_reached
	):
		_gameplay_controller.end_day_consensus_reached.connect(
			_on_end_day_consensus_reached
		)
	_apply_day(_gameplay_controller.day_index)
	_gameplay_controller.snapshot_changed.connect(_on_snapshot_changed)
	_apply_elevator_power()


func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	_apply_elevator_power()
	if not _gameplay_controller.sleeping_peer_ids.is_empty() and not _gameplay_controller.can_end_current_day(): _abort_night()
	if not _gameplay_controller.are_all_connected_players_sleeping():
		# Leaving/re-entering a bunk must start a complete new night.
		_sleep_transition_serial += 1


func _apply_elevator_power() -> void:
	if not multiplayer.is_server() or _elevator_controller == null:
		return
	var powered := _gameplay_controller.is_elevator_powered()
	if _elevator_controller.is_powered != powered:
		_elevator_controller.set_powered(powered)


func _on_end_day_consensus_reached(completed_day_index: int) -> void:
	if not multiplayer.is_server() or _gameplay_controller == null:
		return
	_sleep_transition_serial += 1
	var serial := _sleep_transition_serial
	await get_tree().create_timer(sleep_duration).timeout
	if not is_instance_valid(_gameplay_controller) or not is_inside_tree() or serial != _sleep_transition_serial:
		return
	if (
		_gameplay_controller.day_index != completed_day_index
		or not _gameplay_controller.are_all_connected_players_sleeping()
	):
		return
	_finish_night()


func _finish_night(debug_skip_requirements: bool = false) -> bool:
	_prepared_wake_poses.clear()
	for peer in _gameplay_controller.get_connected_player_peer_ids():
		var player := _gameplay_controller.get_player_node(peer) as GamePlayer
		if player==null or player.survival.dead or not player.is_sleeping_in_bunk():
			_abort_night();return false
		var reserved: Array=[]
		for previous_pose: Transform3D in _prepared_wake_poses.values(): reserved.append(previous_pose.origin)
		var pose: Variant=player.clear_wake_pose(get_parent().get_day_start_transform(_gameplay_controller.get_player_slot(peer)),reserved)
		if pose==null: _abort_night();return false
		_prepared_wake_poses[peer]=pose
	if not _gameplay_controller.advance_day_authoritative(debug_skip_requirements): return false
	_wake_players_for_new_day()
	return _gameplay_controller.save_progress_authoritative(false, "sleep", "Утро дня %d" % _gameplay_controller.day_index, debug_skip_requirements)


func debug_sleep_authoritative() -> String:
	if not multiplayer.is_server() or _gameplay_controller == null:
		return "Сон выполняется хостом после загрузки базы."
	if _gameplay_controller.day_index >= BaseGameplayController.MAX_DAY_INDEX:
		return "Достигнут последний доступный день."
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	if world != null and (not world._v3_items_spawned or world._v3_transition_in_progress):
		return "Дождитесь окончания загрузки базы."
	var level := get_parent()
	if not level.has_method("get_day_start_transform"):
		return "В этой сцене не назначены точки пробуждения."
	var players: Array[GamePlayer] = []
	for peer in _gameplay_controller.get_connected_player_peer_ids():
		var player := _gameplay_controller.get_player_node(peer) as GamePlayer
		if player == null: return "Дождитесь появления всех игроков."
		if player.survival.dead or player.is_driving() or player.is_carrying_corpse() or player.get_node("ItemDrag").is_heavy_carrying():
			return "Все игроки должны быть живы, выйти из транспорта и отпустить переносимые тела и тяжёлые предметы."
		players.append(player)
	if players.is_empty(): return "Нет игроков для перехода к утру."
	# Cancel any pending bunk timer; this command completes exactly one night now.
	_sleep_transition_serial += 1
	for player in players:
		player.enter_bunk_sleep_authoritative(level.get_day_start_transform(_gameplay_controller.get_player_slot(player.owner_peer_id)))
	var saved := _finish_night(true)
	var day := _gameplay_controller.day_index
	if not _gameplay_controller.progress_persistence_enabled:
		return "Наступило утро дня %d. Запись отключена в тестовом режиме (F6)." % day
	return "Наступило утро дня %d. Утренний автосейв записан." % day if saved else "Наступило утро дня %d, но записать автосейв не удалось. Предыдущая запись сохранена." % day


func _on_day_changed(next_day_index: int) -> void:
	_apply_day(next_day_index)


func _apply_day(next_day_index: int) -> void:
	if multiplayer.is_server() and _elevator_controller != null:
		_elevator_controller.set_day(next_day_index)


func _wake_players_for_new_day() -> void:
	var level_root := get_parent()
	if level_root == null or not level_root.has_method("get_day_start_transform"):
		return
	for peer_id in _gameplay_controller.get_connected_player_peer_ids():
		var player := _gameplay_controller.get_player_node(peer_id)
		if player == null or not player.has_method("leave_bunk_sleep_authoritative"):
			player = level_root.get_node_or_null("RuntimePlayers/%d" % peer_id)
		if player == null or not player.has_method("leave_bunk_sleep_authoritative"):
			continue
		var player_slot := _gameplay_controller.get_player_slot(peer_id)
		if player is GamePlayer:
			player.survival.restore_after_sleep_authoritative()
		player.call(
			"leave_bunk_sleep_authoritative",
			_prepared_wake_poses.get(peer_id,level_root.call("get_day_start_transform", player_slot))
		)
