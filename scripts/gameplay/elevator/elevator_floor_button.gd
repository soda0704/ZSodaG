class_name ElevatorFloorButton
extends StaticBody3D

@export_range(0, 5, 1) var floor_index: int = 0
@export var is_call_button: bool = false
@export var controller_path: NodePath

@onready var controller: FunctionalElevatorController = get_node_or_null(
	controller_path
) as FunctionalElevatorController


func get_interaction_prompt() -> String:
	if not is_instance_valid(controller):
		return "Панель лифта не подключена"
	return controller.get_button_prompt(floor_index, is_call_button)


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or not is_instance_valid(controller)
		or int(interactor.get("owner_peer_id")) != peer_id
	):
		return

	if is_call_button:
		controller.request_call(floor_index)
	else:
		controller.request_floor(floor_index)
