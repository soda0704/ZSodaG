extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	for id in ["the_monster", "slasher", "smily", "player"]:
		var path := "res://assets/characters/prototype/scene.gltf" if id == "player" else "res://assets/monsters/%s/scene.gltf" % id
		var model: Node3D = load(path).instantiate()
		root.add_child(model)
		var rig: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		print("RIG ", id)
		for i in rig.get_bone_count():
			print(i, " ", rig.get_bone_name(i), " parent=", rig.get_bone_parent(i), " pose=", rig.get_bone_global_pose(i).origin)
		model.free()
	quit()
