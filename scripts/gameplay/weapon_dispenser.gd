extends StaticBody3D

var item_type: StringName = &"pistol"

func _ready() -> void:
	collision_layer = 4
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.65, 0.6, 0.9)
	shape.shape = box
	add_child(shape)
	var model := (load("res://assets/models/weapons/%s.glb" % item_type) as PackedScene).instantiate()
	add_child(model)
	model.rotation_degrees = Vector3(0, 90, -20)
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.65, 0.08, 0.85)
	plate.mesh = mesh
	plate.position.y = -0.22
	add_child(plate)
	var label := Label3D.new()
	add_child(label)
	label.text = WeaponController.TITLES[item_type]
	label.position.y = 0.35
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 36

func get_interaction_prompt() -> String:
	return "%s" % WeaponController.TITLES[item_type]

func network_interact(peer_id: int, player: Node) -> void:
	if not multiplayer.is_server() or player.get("owner_peer_id") != peer_id:
		return
	if global_position.distance_to(player.global_position) > 4.0 or player.survival.dead:
		return
	if player.get_inventory_snapshot().held_item == item_type:
		return
	player.pickup_world_item_authoritative(item_type, {})
