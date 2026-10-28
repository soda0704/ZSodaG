extends RefCounted


# AI stimulus only; sound playback stays in the weapon/footstep components.
static func emit(source: Node3D, radius: float) -> void:
	if not is_instance_valid(source):
		return
	emit_at(source, source.global_position, radius)


## Scenario noise at the actual impact/landing point; never moves or exposes its source.
static func emit_at(source: Node3D, point: Vector3, radius: float) -> void:
	if (
		not is_instance_valid(source)
		or not source.is_inside_tree()
		or not point.is_finite()
		or not is_finite(radius)
		or radius <= 0.0
		or not source.multiplayer.is_server()
	):
		return
	for monster in source.get_tree().get_nodes_in_group("hostile_monsters"):
		monster.hear_noise(source, point, radius)
