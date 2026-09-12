extends WorldItemPickup

func _ready() -> void:
	super._ready()
	add_child(preload("res://scripts/gameplay/tool_models.gd").build(item_type))
	var box := BoxShape3D.new()
	box.size = Vector3(0.16, 0.06, 0.16) if item_type == &"tape" else Vector3(0.06, 0.12, 0.72)
	$CollisionShape3D.shape = box

func get_interaction_prompt() -> String:
	return "Скотч · крепление фонарика" if item_type == &"tape" else "Монтировка · вскрытий: %d/3" % int(item_state.get("uses", 3))
