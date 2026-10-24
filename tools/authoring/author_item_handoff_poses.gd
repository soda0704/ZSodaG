extends SceneTree
## Offline prototype poses, saved as native animations and filtered Blend2 nodes.
const KINDS := ["Pocket", "Rifle", "Pistol", "Knife", "Flashlight", "Fuse", "Fuel", "Flamethrower"]
func _initialize() -> void: run.call_deferred()
func arm_bone(label: String) -> bool:
	return label.begins_with("LeftHand") or label.begins_with("RightHand") or label in ["LeftArm", "LeftForeArm", "RightArm", "RightForeArm"] or "Elbow_Pads" in label
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/animations/handoff")
	for variant in ["a", "b"]:
		for fp in [false, true]:
			var path := "res://scenes/characters/visuals/tactical_%s/%s.tscn" % [variant, "first_person" if fp else "body"]
			var model: Node3D = load(path).instantiate()
			root.add_child(model)
			var tree: AnimationTree = model.get_node("AnimationTree")
			tree.active = false
			var sk: Skeleton3D = model.get_node("Skeleton3D")
			var modifier_states := {}
			for node in sk.get_children():
				if node is SkeletonModifier3D:
					modifier_states[node] = node.active
					node.active = false
			var ap: AnimationPlayer = model.get_node("AnimationPlayer")
			var helper = load("res://tools/authoring/rifle_grip_study_author.gd").new()
			helper.initialize(sk, {"meshes": []}, {})
			var library := AnimationLibrary.new()
			for kind in KINDS:
				var source: String = kind + ("Idle" if fp else "Aim0")
				if kind == "Pocket": source = "RelaxedIdle" if fp else "Idle"
				if kind == "Flashlight": source = "offhand/" + ("SoloIdle" if fp else "SoloAim0")
				if kind == "Flamethrower": source = "flamethrower/" + ("HipIdle" if fp else "HipAim0")
				assert(ap.has_animation(source), source)
				ap.play(source)
				ap.advance(0)
				ap.pause()
				sk.force_update_all_bone_transforms()
				var side: String = "Left" if kind == "Flashlight" else "Right"
				var hand := sk.find_bone(side + "Hand")
				var original := sk.get_bone_global_pose(hand)
				var left := sk.get_bone_global_pose(sk.find_bone("LeftHand"))
				var target := Vector3(-0.19 if side == "Left" else 0.19, 1.30, -0.58)
				var desired := original.basis
				if kind == "Pocket": desired = helper.palm_basis("Right", Vector3(0, 0, -1), Vector3.UP)
				helper.fit_rifle_arm(side, target, desired)
				# Preserve both original grip contacts for weapons supported by two hands.
				if kind in ["Rifle", "Pistol", "Flamethrower"]:
					var moved := sk.get_bone_global_pose(hand) * original.affine_inverse() * left
					helper.fit_rifle_arm("Left", moved.origin, moved.basis)
				if kind == "Pocket":
					for finger in ["Index", "Middle", "Ring", "Pinky"]: helper.fit_finger("Right", finger, [8.0, 12.0, 6.0])
					helper.fit_finger("Right", "Thumb", [10.0, 12.0, 5.0])
				if not fp and variant == "b": helper.seat_elbow_shells()
				var clip := Animation.new()
				clip.length = 1
				clip.loop_mode = Animation.LOOP_LINEAR
				for bone in sk.get_bone_count():
					if not arm_bone(sk.get_bone_name(bone)): continue
					var track := clip.add_track(Animation.TYPE_ROTATION_3D)
					clip.track_set_path(track, NodePath("Skeleton3D:" + sk.get_bone_name(bone)))
					clip.track_insert_key(track, 0, sk.get_bone_pose_rotation(bone))
				library.add_animation(kind, clip)
			var file := "res://assets/animations/handoff/%s_%s.res" % [variant, "fp" if fp else "body"]
			assert(ResourceSaver.save(library, file, ResourceSaver.FLAG_COMPRESS) == OK)
			library.take_over_path(file)
			if ap.has_animation_library(&"handoff"): ap.remove_animation_library(&"handoff")
			ap.add_animation_library(&"handoff", library)
			if not tree.tree_root.has_node("OfferBlend"):
				var graph: AnimationNodeBlendTree = tree.tree_root.duplicate(true)
				tree.tree_root = graph
				var transition := AnimationNodeTransition.new()
				transition.input_count = KINDS.size()
				transition.xfade_time = 0.12
				graph.add_node("OfferPose", transition, Vector2(800, 400))
				for i in KINDS.size():
					transition.set("input_%d/name" % i, KINDS[i])
					var node := AnimationNodeAnimation.new()
					node.animation = "handoff/" + KINDS[i]
					graph.add_node("Offer" + KINDS[i], node, Vector2(600, 400 + i * 100))
					graph.connect_node("OfferPose", i, "Offer" + KINDS[i])
				var blend := AnimationNodeBlend2.new()
				blend.filter_enabled = true
				for bone in sk.get_bone_count():
					if arm_bone(sk.get_bone_name(bone)): blend.set_filter_path(NodePath("Skeleton3D:" + sk.get_bone_name(bone)), true)
				graph.add_node("OfferBlend", blend, Vector2(1000, 400))
				graph.connect_node("OfferBlend", 1, "OfferPose")
			var graph: AnimationNodeBlendTree = tree.tree_root
			graph.disconnect_node("BookBlend" if fp else "output", 0)
			graph.disconnect_node("OfferBlend", 0)
			graph.connect_node("OfferBlend", 0, "OffhandTorch")
			graph.connect_node("BookBlend" if fp else "output", 0, "OfferBlend")
			ap.stop()
			sk.reset_bone_poses()
			for node in modifier_states: node.active = modifier_states[node]
			tree.active = true
			var packed := PackedScene.new()
			assert(packed.pack(model) == OK)
			var result := ResourceSaver.save(packed, path)
			for attempt in 3:
				if result == OK: break
				await create_timer(0.25).timeout
				result = ResourceSaver.save(packed, path)
			if result != OK:
				push_error("Could not save handoff scene: " + path)
				quit(1)
				return
			model.queue_free()
			await process_frame
	print("HANDOFF NATIVE POSES READY")
	quit()
