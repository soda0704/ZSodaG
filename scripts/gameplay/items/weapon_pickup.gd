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
		if item_state.has("mounted_charge") and item_type == &"m4a1":
			var mount := preload("res://scenes/objects/equipment/mounted_flashlight.tscn").instantiate()
			mount.transform = model.get_node("FlashlightMount").transform
			mount.visible = true
			add_child(mount)
		if use_authored_collision: return
		var bounds := fitted_collision_bounds(model)
		var shape := BoxShape3D.new();shape.size=bounds.size
		$CollisionShape3D.shape=shape;$CollisionShape3D.position=bounds.get_center()
		if item_type == &"pistol_ammo":
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
		return "%s · фонарик%s · %d%%" % [WeaponController.TITLES[item_type], " на скотче" if item_type == &"m4a1" else "", roundi(float(item_state.mounted_charge) * 100.0)]
	if item_type == &"pistol_ammo":
		return "Патроны для пистолета · %d шт." % int(item_state.get("amount", 12))
	if item_type == &"rifle_magazine":
		return "Магазин M4A1 · %d/30" % int(item_state.get("rounds", 30))
	return super.get_interaction_prompt()

func fitted_collision_bounds(model: Node3D = null) -> AABB:
	if item_type==&"pistol_ammo": return AABB(Vector3(-.025,-.018,-.0325),Vector3(.05,.036,.065))
	if item_type==&"rifle_magazine": return AABB(Vector3(-.045,-.08,-.05),Vector3(.09,.16,.1))
	if item_type==&"kitchen_knife":
		var temporary := model==null
		if temporary: model=WeaponController.MODEL_SCENES[item_type].instantiate()
		var bounds := AABB();var first := true
		for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var pose := mesh.transform;var parent := mesh.get_parent()
			while parent!=model:
				pose=parent.transform*pose;parent=parent.get_parent()
			var part: AABB=pose*mesh.get_aabb()
			bounds=part if first else bounds.merge(part);first=false
		if temporary: model.free()
		return bounds.grow(.003)
	var size := Vector3(.08,.32,.85) if item_type==&"m4a1" else Vector3(.07,.18,.38)
	return AABB(Vector3(0,0,-.13)-size*.5,size)
