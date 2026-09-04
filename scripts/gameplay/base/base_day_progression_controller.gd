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


func _on_end_day_consensus_reached(_completed_day_index: int) -> void:
	if multiplayer.is_server() and _gameplay_controller != null:
		_gameplay_controller.advance_day_authoritative()


func _on_day_changed(next_day_index: int) -> void:
	_apply_day(next_day_index)


func _apply_day(next_day_index: int) -> void:
	var day_two_unlocked := next_day_index >= 2
	if _day_one_collision_root != null:
		for child in _day_one_collision_root.find_children(
			"*",
			"CollisionShape3D",
			true,
			false
		):
			(child as CollisionShape3D).set_deferred(
				"disabled",
				day_two_unlocked
			)
	if multiplayer.is_server() and _elevator_controller != null:
		_elevator_controller.set_day(next_day_index)
