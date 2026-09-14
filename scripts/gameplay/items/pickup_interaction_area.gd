extends Area3D

func get_interaction_prompt() -> String:
	return get_parent().get_interaction_prompt()

func network_interact(peer_id: int, player: Node) -> void:
	get_parent().network_interact(peer_id, player)
