class_name FlashlightPickup
extends RigidBody3D

@export var interaction_prompt: String = "Поднять фонарик"
@export_range(0.0, 1.0, 0.01) var battery_charge: float = 1.0

var _collected: bool = false


func get_interaction_prompt() -> String:
	return "%s — battery %d%%" % [
		interaction_prompt,
		roundi(battery_charge * 100.0),
	]


func interact(interactor: Node) -> void:
	if _collected:
		return

	var collected := false
	if interactor.has_method("swap_flashlight"):
		collected = bool(interactor.call("swap_flashlight", battery_charge))
	elif interactor.has_method("acquire_flashlight"):
		collected = bool(
			interactor.call("acquire_flashlight", battery_charge)
		)

	if collected:
		_collected = true
		freeze = true
		collision_layer = 0
		collision_mask = 0
		queue_free()
