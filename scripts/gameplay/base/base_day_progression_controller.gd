class_name BaseDayProgressionController
extends Node

@export var gameplay_controller_path := NodePath("../BaseGameplayController")
@export var day_one_collision_root_path := NodePath(
	"../Floor_0_Base_Blockout/Day1_Door_Collisions"
)
@export var elevator_controller_path := NodePath(
	"../Elevator_Functional_Blockout"
)

var _gameplay_controller: BaseGameplayController
var _day_one_collision_root: Node3D
var _elevator_controller: FunctionalElevatorController


func _ready() -> void:
	call_deferred("_bind_runtime")


func _bind_runtime() -> void:
	_gameplay_controller = get_node_or_null(
		gameplay_controller_path
	) as BaseGameplayController
	_day_one_collision_root = get_node_or_null(
		day_one_collision_root_path
	) as Node3D
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


func _on_end_day_consensus_reached(completed_day_index: int) -> void:
	if not multiplayer.is_server() or _gameplay_controller == null:
		return
	await get_tree().create_timer(1.1).timeout
	if (
		_gameplay_controller.day_index != completed_day_index
		or not _gameplay_controller.are_all_connected_players_sleeping()
		or not _gameplay_controller.advance_day_authoritative()
	):
		return
	_wake_players_for_new_day()


func _on_day_changed(next_day_index: int) -> void:
	_apply_day(next_day_index)


func _apply_day(next_day_index: int) -> void:
	if _day_one_collision_root != null:
		for child in _day_one_collision_root.find_children(
			"*",
			"CollisionShape3D",
			true,
			false
		):
			(child as CollisionShape3D).set_deferred(
				"disabled",
				true
			)
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
		player.call(
			"leave_bunk_sleep_authoritative",
			level_root.call("get_day_start_transform", player_slot)
		)
