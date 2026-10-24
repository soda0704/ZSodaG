extends SceneTree
## Add native right-finger pose and wrist orientation without rebuilding characters.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for id in ["a","b"]:
		var first = load("res://scenes/characters/visuals/tactical_%s/first_person.tscn" % id).instantiate()
		var skeleton: Skeleton3D = first.get_node("Skeleton3D")
		var wrist := skeleton.get_bone_global_rest(skeleton.find_bone("RightHand"))
		var distal := (skeleton.get_bone_global_rest(skeleton.find_bone("RightHandMiddle1")).origin-wrist.origin).normalized()
		var lateral := skeleton.get_bone_global_rest(skeleton.find_bone("RightHandIndex1")).origin-skeleton.get_bone_global_rest(skeleton.find_bone("RightHandPinky1")).origin
		lateral = (lateral-distal*lateral.dot(distal)).normalized()
		var anatomy := Basis(lateral,distal,lateral.cross(distal)).orthonormalized()
		var y := Vector3(1,1,0).normalized()
		var normal := Vector3(0,0,-1)
		var desired := Basis(y.cross(normal),y,normal)
		var origin := Vector3(-.0457,-.1377,.02394)
		var grip := Transform3D((desired*anatomy.inverse()*wrist.basis).orthonormalized(),origin)
		var variant_path := "res://assets/config/characters/tactical_%s.tres" % id
		var variant = load(variant_path)
		variant.journal_loupe_grip = grip
		var world_grip := grip
		world_grip.origin = origin
		variant.journal_loupe_world_grip = world_grip
		assert(ResourceSaver.save(variant,variant_path)==OK)
		var source: Animation = first.get_node("AnimationPlayer").get_animation("HandPose_Flashlight")
		var thumb_source: Animation = first.get_node("AnimationPlayer").get_animation("HandPose_Rifle_Right")
		var pose := Animation.new()
		pose.length = 1
		pose.loop_mode = Animation.LOOP_LINEAR
		var paths: Array[NodePath] = []
		for i in source.get_track_count():
			var path: NodePath = source.track_get_path(i)
			if source.track_get_type(i)!=Animation.TYPE_ROTATION_3D or not "RightHand" in str(path) or str(path).ends_with(":RightHand"): continue
			var index := pose.add_track(Animation.TYPE_ROTATION_3D)
			pose.track_set_path(index,path)
			var thumb_track := thumb_source.find_track(path,Animation.TYPE_ROTATION_3D) if "Thumb" in str(path) else -1
			pose.rotation_track_insert_key(index,0,thumb_source.rotation_track_interpolate(thumb_track,0) if thumb_track>=0 else source.rotation_track_interpolate(i,0))
			paths.append(path)
		first.free()
		for kind in ["first_person","body"]:
			var scene_path := "res://scenes/characters/visuals/tactical_%s/%s.tscn" % [id,kind]
			var scene = load(scene_path).instantiate()
			var sk: Skeleton3D = scene.get_node("Skeleton3D")
			var player: AnimationPlayer = scene.get_node("AnimationPlayer")
			var equipment: Node3D = scene.get_node("Skeleton3D/RightHand/Equipment")
			var glass: Node3D = equipment.get_node_or_null("JournalMagnifier")
			if glass != null: glass.free()
			glass = load("res://scenes/ui/journal/book/magnifier.tscn").instantiate()
			glass.name = "JournalMagnifier"
			glass.transform = (grip if kind=="first_person" else world_grip).affine_inverse()
			equipment.add_child(glass)
			glass.owner = scene
			for mesh in glass.find_children("*","MeshInstance3D",true,false): mesh.layers = 1<<19 if kind=="first_person" else 1|(1<<18)
			if player.has_animation_library("loupe"): player.remove_animation_library("loupe")
			var library := AnimationLibrary.new()
			library.add_animation("Grip",pose.duplicate(true))
			player.add_animation_library("loupe",library)
			var tree: AnimationTree = scene.get_node("AnimationTree")
			var blend: AnimationNodeBlendTree = tree.tree_root
			if not blend.has_node("LoupeGrip"):
				var links: Array = blend.get("node_connections")
				var previous: StringName
				for i in range(0,links.size(),3):
					if str(links[i])=="output": previous=links[i+2]
				var animation := AnimationNodeAnimation.new()
				animation.animation = "loupe/Grip"
				blend.add_node("LoupePose",animation)
				var overlay := AnimationNodeBlend2.new()
				overlay.filter_enabled = true
				for path in paths: overlay.set_filter_path(path,true)
				blend.add_node("LoupeGrip",overlay)
				blend.disconnect_node("output",0)
				blend.connect_node("LoupeGrip",0,previous)
				blend.connect_node("LoupeGrip",1,"LoupePose")
				blend.connect_node("output",0,"LoupeGrip")
			if not sk.has_node("LoupeWrist"):
				var modifier := CopyTransformModifier3D.new()
				modifier.name = "LoupeWrist"
				modifier.set("setting_count",1)
				modifier.set("settings/0/amount",1.0)
				modifier.set("settings/0/apply_bone_name","RightHand")
				modifier.set("settings/0/reference_type",1)
				modifier.set("settings/0/reference_node",NodePath("../RightWristTarget"))
				modifier.set("settings/0/copy",2)
				modifier.set("settings/0/axes",7)
				modifier.influence = 0
				sk.add_child(modifier)
				modifier.owner = scene
			var packed := PackedScene.new()
			assert(packed.pack(scene)==OK)
			assert(ResourceSaver.save(packed,scene_path)==OK)
			scene.free()
		print("AUTHORED LOUPE GRIP ",id," finger tracks ",pose.get_track_count())
	quit()
