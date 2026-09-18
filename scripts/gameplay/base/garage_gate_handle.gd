extends StaticBody3D

func get_interaction_prompt() -> String:
	return "Рукоять ворот" if get_parent().progress < 1 else "Гараж открыт"

func network_interact(_peer: int, _player: Node) -> void:
	pass # Continuous hold is sampled by the gate controller.
