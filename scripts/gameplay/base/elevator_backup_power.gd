class_name ElevatorBackupPower
extends StaticBody3D
## Presentation and interaction only; the base owns the saved power state.

@export_range(0.1, 10.0) var interaction_distance := 3.0
@onready var inserted_fuse: Node3D = %InsertedFuse
@onready var connected_indicator: Node3D = %ConnectedIndicator
@onready var disconnected_indicator: Node3D = %DisconnectedIndicator
@onready var status_label: Label3D = %StatusLabel
var _controller: BaseGameplayController


func _ready() -> void:
	add_to_group("elevator_backup_socket")
	_bind_controller.call_deferred()


func _bind_controller() -> void:
	_controller = get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if _controller == null:
		push_warning("Elevator backup socket could not find base gameplay state")
		return
	_controller.snapshot_changed.connect(_on_snapshot_changed)
	_on_snapshot_changed(_controller.get_snapshot())


func get_interaction_prompt() -> String:
	if not is_instance_valid(_controller):
		return "Резервное питание недоступно"
	if _controller.elevator_backup_installed:
		return "Резервное питание лифта подключено"
	return "Вставить предохранитель · найти в медпункте"


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server() or not is_instance_valid(_controller)
		or interactor == null or interactor != _controller.get_player_node(peer_id)
	):
		return
	_controller.install_elevator_backup_authoritative(peer_id)


func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	var connected := _controller.elevator_backup_installed
	inserted_fuse.visible = connected
	connected_indicator.visible = connected
	disconnected_indicator.visible = not connected
	status_label.text = "РЕЗЕРВ ЛИФТА ПОДКЛЮЧЁН" if connected else "НУЖЕН ПРЕДОХРАНИТЕЛЬ"
