extends SceneTree
## Offline mirroring of the existing right-hand animation assets.
## The game only plays saved Animation resources and authored sockets.
const MIRROR := Transform3D(Basis(Vector3(-1,0,0),Vector3(0,1,0),Vector3(0,0,1)),Vector3.ZERO)
func _initialize() -> void: run.call_deferred()
func arm_bone(label: String) -> bool:
	return label.begins_with("LeftShoulder") or label.begins_with("RightShoulder") or label.begins_with("LeftArm") or label.begins_with("RightArm") or label.begins_with("LeftForeArm") or label.begins_with("RightForeArm") or label.begins_with("LeftHand") or label.begins_with("RightHand")
func counterpart(label: String) -> String:
	return "Right" + label.trim_prefix("Left") if label.begins_with("Left") else "Left" + label.trim_prefix("Right")
func mirrored_clip(scene: Node3D, source_name: String) -> Animation:
	var sk: Skeleton3D = scene.get_node("Skeleton3D")
	var player: AnimationPlayer = scene.get_node("AnimationPlayer")
	var source := player.get_animation(source_name)
	assert(source != null, source_name)
	var clip := source.duplicate(true) as Animation
	for track in range(clip.get_track_count()-1, -1, -1):
		var path := String(clip.track_get_path(track))
		if path.begins_with("Skeleton3D:") and arm_bone(path.get_slice(":",1)): clip.remove_track(track)
	var tracks := {}
	for bone in sk.get_bone_count():
		var label := String(sk.get_bone_name(bone))
		if not arm_bone(label) or sk.find_bone(counterpart(label)) < 0: continue
		var indices: Array[int] = []
		for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			var track := clip.add_track(type)
			clip.track_set_path(track, NodePath("Skeleton3D:" + label))
			indices.append(track)
		tracks[bone] = indices
	var frames := maxi(1, ceili(source.length * 30.0))
	for frame in frames + 1:
		var time := source.length * frame / frames
		sk.reset_bone_poses()
		player.play(source_name); player.seek(time, true); player.pause()
		sk.force_update_all_bone_transforms()
		var sampled: Array[Transform3D] = []
		var desired: Array[Transform3D] = []
		for bone in sk.get_bone_count():
			sampled.append(sk.get_bone_global_pose(bone))
			desired.append(sampled[-1])
		for bone: int in tracks:
			var other := sk.find_bone(counterpart(sk.get_bone_name(bone)))
			# Mirror the complete deformation, accounting for the native L/R
			# bone axes and rest proportions. Finger positions are included.
			desired[bone] = MIRROR * sampled[other] * sk.get_bone_global_rest(other).affine_inverse() * MIRROR * sk.get_bone_global_rest(bone)
		for bone: int in tracks:
			var parent := sk.get_bone_parent(bone)
			var local := desired[parent].affine_inverse() * desired[bone] if parent >= 0 else desired[bone]
			var indices: Array[int] = tracks[bone]
			clip.position_track_insert_key(indices[0], time, local.origin)
			clip.rotation_track_insert_key(indices[1], time, local.basis.orthonormalized().get_rotation_quaternion())
			clip.scale_track_insert_key(indices[2], time, local.basis.get_scale())
	# Constant channels need one key. Keep every varying sample, including
	# breathing and the battery action; this reduces native asset load size.
	for track in clip.get_track_count():
		if clip.track_get_key_count(track) < 2: continue
		var first: Variant = clip.track_get_key_value(track, 0)
		if typeof(first) not in [TYPE_VECTOR3, TYPE_QUATERNION]: continue
		var constant := true
		for key in clip.track_get_key_count(track):
			if not first.is_equal_approx(clip.track_get_key_value(track, key)):
				constant = false
				break
		if constant:
			for key in range(clip.track_get_key_count(track)-1, 0, -1): clip.track_remove_key(track, key)
	return clip
func left_only(source: Animation) -> Animation:
	var clip := source.duplicate(true) as Animation
	for track in range(clip.get_track_count()-1, -1, -1):
		var path := String(clip.track_get_path(track))
		if not path.begins_with("Skeleton3D:Left") or not arm_bone(path.get_slice(":",1)): clip.remove_track(track)
	return clip
func run() -> void:
	for variant in ["tactical_a", "tactical_b"]:
		for view in ["body", "first_person"]:
			var folder: String = "res://scenes/characters/visuals/" + variant + "/"
			var scene: Node3D = load(folder + view + ".tscn").instantiate()
			root.add_child(scene)
			scene.get_node("AnimationTree").active = false
			var sk: Skeleton3D = scene.get_node("Skeleton3D")
			for modifier in sk.get_children():
				if modifier is SkeletonModifier3D: modifier.active = false
			var library := AnimationLibrary.new()
			if view == "first_person":
				var solo := mirrored_clip(scene, "FlashlightIdle")
				library.add_animation("SoloIdle", solo)
				var hold := left_only(solo)
				for point in [-1,0,1]: library.add_animation("Hold" + str(point), hold)
			else:
				for point in [-1,0,1]:
					var solo := mirrored_clip(scene, "FlashlightAim" + str(point))
					library.add_animation("SoloAim" + str(point), solo)
					library.add_animation("Hold" + str(point), left_only(solo))
			library.add_animation("Battery", mirrored_clip(scene, "FlashlightBattery"))
			assert(ResourceSaver.save(library, folder + view + "_offhand.tres") == OK)
			var right: Node3D = sk.get_node("RightHand/Equipment")
			var right_grip: Node3D = right.get_node("FlashlightGrip")
			var right_rest := sk.get_bone_global_rest(sk.find_bone("RightHand"))
			var left_rest := sk.get_bone_global_rest(sk.find_bone("LeftHand"))
			var socket := BoneAttachment3D.new()
			socket.name = "LeftHand"; socket.bone_name = "LeftHand"
			var equipment := Node3D.new()
			equipment.name = "Equipment"
			equipment.transform = left_rest.affine_inverse() * MIRROR * right_rest * right.transform * right_grip.transform * MIRROR
			socket.add_child(equipment); equipment.owner = socket
			var grip := Marker3D.new()
			grip.name = "FlashlightGrip"
			equipment.add_child(grip); grip.owner = socket
			if view == "body":
				var shadow: Node3D = load("res://scenes/objects/equipment/flashlight_model.tscn").instantiate()
				shadow.name = "ShadowItem"; shadow.position.z = -0.22; shadow.visible = false
				grip.add_child(shadow); shadow.owner = socket
			var packed := PackedScene.new()
			assert(packed.pack(socket) == OK)
			assert(ResourceSaver.save(packed, folder + view + "_offhand_socket.tscn") == OK)
			socket.free(); scene.free()
	print("MIRRORED FLASHLIGHT AUTHORING PASS")
	quit()
