extends WorldItemPickup

func _ready() -> void:
	super._ready()
	display_name = WeaponController.TITLES.get(item_type, "оружие")
	if WeaponController.TYPES.has(item_type):
		var model := (load("res://assets/models/weapons/%s.glb" % item_type) as PackedScene).instantiate()
		add_child(model)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.08, 0.24, 0.85) if item_type == &"m4a1" else Vector3(0.07, 0.14, 0.38)
		$CollisionShape3D.shape = shape
		$CollisionShape3D.position.z = -0.13
