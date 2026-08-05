class_name LevelTransitionTerminal
extends StaticBody3D

@export var controller_path: NodePath
@export var target_label: String = "V3"

@onready var controller: Node = get_node_or_null(controller_path)


func get_interaction_prompt() -> String:
	if controller == null or not controller.has_method("can_enter_v3_level"):
		return "Переход недоступен"
	if not bool(controller.call("can_enter_v3_level")):
		return "Сначала восстановите питание и откройте дверь"
	return "Перейти на уровень %s" % target_label


func interact(interactor: Node) -> void:
	network_interact(multiplayer.get_unique_id(), interactor)


func network_interact(peer_id: int, interactor: Node) -> void:
	if (
		not multiplayer.is_server()
		or int(interactor.get("owner_peer_id")) != peer_id
		or controller == null
		or not controller.has_method("request_v3_transition")
	):
		return
	controller.call("request_v3_transition", peer_id)
