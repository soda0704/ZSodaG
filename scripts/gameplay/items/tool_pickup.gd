extends WorldItemPickup

## Enable to keep the CollisionShape authored in the scene instead of automatic fitting.
@export var use_authored_collision := false

func _ready() -> void:
	super._ready()
	add_child(preload("res://scripts/gameplay/tool_models.gd").build(item_type))
	if use_authored_collision: return
	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 0.06, 0.16) if item_type == &"tape" else Vector3(0.06, 0.12, 0.72)
	$CollisionShape3D.shape = box

func get_interaction_prompt() -> String:
	if not pickup_enabled: return ""
	return "Скотч · крепление фонарика" if item_type == &"tape" else "Монтировка"
