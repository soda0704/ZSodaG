extends AnimatableBody3D

@export var gate_path: NodePath
@onready var gate: Node3D = get_node(gate_path)

func get_interaction_prompt() -> String:
	return "Удерживайте E вдвоём: разблокировать ворота" if gate.progress < 1 else "Ворота разблокированы"

func network_interact(_peer: int, _player: Node) -> void:
	pass # Continuous hold is sampled by the gate controller.
