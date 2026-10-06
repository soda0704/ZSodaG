class_name ContactSurface
extends RefCounted

static func classify(node: Node, impact: bool = false) -> StringName:
	while node != null:
		if impact and node.has_meta("impact_surface"):
			return StringName(node.get_meta("impact_surface"))
		if node.is_class("Terrain3D"):
			return &"snow"
		if node.has_meta("footstep_surface"):
			return StringName(node.get_meta("footstep_surface"))
		node = node.get_parent()
	return &"floor"

