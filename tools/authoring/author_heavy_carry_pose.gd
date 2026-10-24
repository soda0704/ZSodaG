extends SceneTree
# Offline native AnimationLibrary authoring, never runtime bone animation.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/animations/heavy_carry")
	for variant in ["a", "b"]:
		for fp in [false, true]:
			var path := "res://scenes/characters/visuals/tactical_%s/%s.tscn" % [variant, "first_person" if fp else "body"]
			var model: Node3D = load(path).instantiate()
			root.add_child(model)
			var tree: AnimationTree = model.get_node("AnimationTree")
			tree.active = false
			var sk: Skeleton3D = model.get_node("Skeleton3D")
			var states := {}
			for node in sk.get_children():
				if node is SkeletonModifier3D:
					states[node] = node.active
					node.active = false
			var ap: AnimationPlayer = model.get_node("AnimationPlayer")
			ap.play("RelaxedIdle" if fp else "Idle")
			ap.advance(0)
			ap.pause()
			var helper = load("res://tools/authoring/rifle_grip_study_author.gd").new()
			helper.initialize(sk, {"meshes": []}, {})
			for side in ["Left", "Right"]:
				var target := Vector3(-0.27 if side == "Left" else 0.27, 1.05, -0.48)
				helper.fit_rifle_arm(side, target, helper.palm_basis(side, Vector3.FORWARD, Vector3.UP))
				for finger in ["Index", "Middle", "Ring", "Pinky"]: helper.fit_finger(side, finger, [15.0, 30.0, 18.0])
			if not fp and variant == "b": helper.seat_elbow_shells()
			var clip := Animation.new()
			clip.length = 1
			clip.loop_mode = Animation.LOOP_LINEAR
			for bone in sk.get_bone_count():
				if not (sk.get_bone_name(bone).begins_with("LeftHand") or sk.get_bone_name(bone).begins_with("RightHand") or sk.get_bone_name(bone) in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"] or "Elbow_Pads" in sk.get_bone_name(bone)): continue
				var track := clip.add_track(Animation.TYPE_ROTATION_3D)
				clip.track_set_path(track, NodePath("Skeleton3D:" + sk.get_bone_name(bone)))
				clip.track_insert_key(track, 0, sk.get_bone_pose_rotation(bone))
			var lib := AnimationLibrary.new()
			lib.add_animation("Carry", clip)
			var file := "res://assets/animations/heavy_carry/%s_%s.res" % [variant, "fp" if fp else "body"]
			assert(ResourceSaver.save(lib, file, ResourceSaver.FLAG_COMPRESS) == OK)
			if ap.has_animation_library("heavy"): ap.remove_animation_library("heavy")
			ap.add_animation_library("heavy", lib)
			var graph: AnimationNodeBlendTree = tree.tree_root.duplicate(true)
			tree.tree_root = graph
			if not graph.has_node("OfferHeavy"):
				var transition: AnimationNodeTransition = graph.get_node("OfferPose")
				var index := transition.input_count
				transition.input_count += 1
				transition.set("input_%d/name" % index, "Heavy")
				var anim := AnimationNodeAnimation.new()
				anim.animation = "heavy/Carry"
				graph.add_node("OfferHeavy", anim, Vector2(600,1250))
				graph.connect_node("OfferPose", index, "OfferHeavy")
			ap.stop()
			sk.reset_bone_poses()
			for node in states: node.active = states[node]
			tree.active = true
			var packed := PackedScene.new()
			assert(packed.pack(model) == OK)
			var error := ResourceSaver.save(packed, path)
			for attempt in 3:
				if error == OK: break
				await create_timer(.25).timeout
				error = ResourceSaver.save(packed, path)
			if error != OK:
				push_error("Cannot save heavy carry scene: " + path)
				quit(1)
				return
			model.queue_free()
			await process_frame
	print("HEAVY CARRY POSES READY")
	quit()
