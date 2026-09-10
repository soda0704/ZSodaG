extends WorldItemPickup

func _ready() -> void:
	super._ready()
	display_name = WeaponController.TITLES.get(item_type, "оружие")
	if item_type in [&"pistol_ammo", &"rifle_magazine"]:
		display_name = "патроны для пистолета" if item_type == &"pistol_ammo" else "магазин M4A1"
	if WeaponController.TYPES.has(item_type) or item_type in [&"pistol_ammo", &"rifle_magazine"]:
		var model := (load("res://assets/models/weapons/%s.glb" % item_type) as PackedScene).instantiate()
		add_child(model)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.08, 0.32, 0.85) if item_type == &"m4a1" else Vector3(0.07, 0.18, 0.38)
		$CollisionShape3D.shape = shape
		$CollisionShape3D.position.z = -0.13
		if item_type == &"kitchen_knife":
			shape.size = Vector3(0.05, 0.028, 0.35)
			$CollisionShape3D.position.z = -0.07
		if item_type in [&"pistol_ammo", &"rifle_magazine"]:
			shape.size = Vector3(0.09, 0.16, 0.1)
			$CollisionShape3D.position.z = 0.0
			if item_type == &"pistol_ammo":
				shape.size = Vector3(0.05, 0.036, 0.065)

func get_interaction_prompt() -> String:
	if item_type == &"pistol_ammo":
		return "Патроны для пистолета · %d шт." % int(item_state.get("amount", 12))
	if item_type == &"rifle_magazine":
		return "Магазин M4A1 · %d/30" % int(item_state.get("rounds", 30))
	return super.get_interaction_prompt()
