extends WorldItemPickup

## Enable to keep the CollisionShape authored in the scene instead of automatic fitting.
@export var use_authored_collision := false
@export var model_scene: PackedScene

func _ready() -> void:
	super._ready()
	if display_name == "предмет":
		display_name = WeaponController.TITLES.get(item_type, "оружие")
		if item_type in [&"pistol_ammo", &"rifle_magazine"]:
			display_name = "патроны для пистолета" if item_type == &"pistol_ammo" else "магазин M4A1"
	if WeaponController.TYPES.has(item_type) or item_type in [&"pistol_ammo", &"rifle_magazine"]:
		var scene: PackedScene = model_scene if model_scene != null else WeaponController.MODEL_SCENES[item_type]
		var model := scene.instantiate()
		model.name = "Model"
		add_child(model)
		if item_state.has("mounted_charge") and item_type in [&"pistol", &"m4a1"]:
			var mount := preload("res://scenes/objects/equipment/mounted_flashlight.tscn").instantiate()
			mount.position = Vector3(0.053, 0.01, -0.16)
			add_child(mount)
		if use_authored_collision: return
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.08, 0.32, 0.85) if item_type == &"m4a1" else Vector3(0.07, 0.18, 0.38)
		$CollisionShape3D.shape = shape
		$CollisionShape3D.position.z = -0.13
		if item_type == &"kitchen_knife":
			var bounds := AABB()
			var first := true
			for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
				var part: AABB = (model.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
				bounds=part if first else bounds.merge(part)
				first=false
			shape.size=bounds.size+Vector3.ONE*0.006
			$CollisionShape3D.position=bounds.get_center()
		if item_type in [&"pistol_ammo", &"rifle_magazine"]:
			shape.size = Vector3(0.09, 0.16, 0.1)
			$CollisionShape3D.position.z = 0.0
			if item_type == &"pistol_ammo":
				shape.size = Vector3(0.05, 0.036, 0.065)
				var target := Area3D.new()
				target.set_script(preload("res://scripts/gameplay/items/pickup_interaction_area.gd"))
				target.collision_layer = 4
				target.collision_mask = 0
				var target_shape := CollisionShape3D.new()
				var target_box := BoxShape3D.new()
				target_box.size = Vector3(0.18, 0.12, 0.18)
				target_shape.shape = target_box
				target.add_child(target_shape)
				add_child(target)

func get_interaction_prompt() -> String:
	if not pickup_enabled: return ""
	if item_state.has("mounted_charge") and item_type in [&"pistol", &"m4a1"]:
		return "%s · фонарик на скотче · %d%%" % [WeaponController.TITLES[item_type], roundi(float(item_state.mounted_charge) * 100.0)]
	if item_type == &"pistol_ammo":
		return "Патроны для пистолета · %d шт." % int(item_state.get("amount", 12))
	if item_type == &"rifle_magazine":
		return "Магазин M4A1 · %d/30" % int(item_state.get("rounds", 30))
	return super.get_interaction_prompt()
