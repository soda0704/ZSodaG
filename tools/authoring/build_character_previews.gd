extends SceneTree
## Rebuild menu-only bodies from production visuals; never modify the source scenes.
func _initialize() -> void:
	for variant in ["tactical_a", "tactical_b"]:
		var source: Node3D = load("res://scenes/characters/visuals/%s/body.tscn" % variant).instantiate()
		var skeleton: Skeleton3D = source.get_node("Skeleton3D")
		var idle: Animation = source.get_node("AnimationPlayer").get_animation("Idle").duplicate()
		for index in range(idle.get_track_count() - 1, -1, -1):
			if not str(idle.track_get_path(index)).begins_with("Skeleton3D:"):
				idle.remove_track(index)
		for child in source.get_children():
			if child != skeleton: child.free()
		for child in skeleton.get_children():
			if child.name != &"Body": child.free()
		source.name = "CharacterPreview"
		source.scene_file_path = ""
		var player := AnimationPlayer.new()
		player.name = "AnimationPlayer"
		source.add_child(player)
		var library := AnimationLibrary.new()
		library.add_animation(&"Idle", idle)
		player.add_animation_library(&"", library)
		for child in source.find_children("*", "", true, false): child.owner = source
		var packed := PackedScene.new()
		assert(packed.pack(source) == OK)
		var path := "res://scenes/ui/characters/%s.scn" % variant
		DirAccess.make_dir_recursive_absolute("res://scenes/ui/characters")
		assert(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK)
		print("PREVIEW ", path, " nodes=", source.find_children("*", "", true, false).size(), " idle tracks=", idle.get_track_count())
		source.free()
	quit()
