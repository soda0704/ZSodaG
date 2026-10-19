extends AnimatableBody3D

@export var gate_path: NodePath
@onready var gate: Node3D = get_node(gate_path)

func get_interaction_prompt() -> String:
	return ""

func get_interaction_hint_for(_player: Node) -> String:
	if gate.animation.is_playing(): return ""
	var action := "закрыть ворота" if gate.progress >= 1.0 else "открыть ворота"
	var key: String = get_node("/root/SteamInput").get_action_hint(&"interact")
	return "Удерживайте %s одновременно с напарником: %s" % [key, action] if gate.required_operators() == 2 else "Удерживайте %s: %s" % [key, action]

func network_interact(_peer: int, _player: Node) -> void:
	pass # Continuous hold is sampled by the gate controller.
