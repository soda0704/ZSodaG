extends RefCounted

# AI stimulus only; sound playback stays in the weapon/footstep components.
static func emit(source: Node3D, radius: float) -> void:
	if not source.multiplayer.is_server():
		return
	for monster in source.get_tree().get_nodes_in_group("hostile_monsters"):
		monster.hear_noise(source, source.global_position, radius)
