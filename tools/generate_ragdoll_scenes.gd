extends SceneTree

const BONES := {
	"the_monster": [2, 73, 74, 76, 77, 3, 4, 5, 26, 27, 28, 141, 142, 143, 163, 164, 165, 49, 52, 55, 58, 61, 64, 67],
	"slasher": [1, 3, 4, 5, 6, 9, 10, 11, 17, 18, 19, 24, 25, 26, 29, 30, 31],
	# Keep the torso as the physical root.  The old order started at Hip.L_035,
	# which left the spine and the opposite hind leg without a stable parent;
	# that disconnected chain was the source of the stretched strip on death.
	"smily": [1, 2, 3, 4, 5, 36, 37, 38, 39, 41, 42, 43, 44, 9, 10, 11, 23, 24, 25],
	"player": [1, 3, 4, 5, 7, 9, 10, 11, 13, 14, 15, 22, 23, 24, 27, 28, 29],
}

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://scenes/characters/ragdolls")
	for id in BONES:
		var visual: Node3D
		if id == "player":
			visual = Node3D.new()
			root.add_child(visual)
			var model: Node3D = load("res://assets/characters/prototype/scene.gltf").instantiate()
			visual.add_child(model)
			model.scale = Vector3.ONE * 0.013
		else:
			visual = MonsterVisual.new()
			root.add_child(visual)
			visual.setup(id, 2.25 if id == "the_monster" else 1.15 if id == "smily" else 1.95)
		var rig: Skeleton3D = visual.find_children("*", "Skeleton3D", true, false)[0]
		var ragdoll := Node3D.new()
		ragdoll.name = "Ragdoll"
		ragdoll.set_script(load("res://scripts/gameplay/skeletal_ragdoll.gd"))
		var selected: Array = BONES[id]
		for index in selected.size():
			var bone: int = selected[index]
			var end := -1
			for candidate in selected:
				if rig.get_bone_parent(candidate) == bone:
					end = candidate
					break
			if end < 0 and not rig.get_bone_children(bone).is_empty():
				end = rig.get_bone_children(bone)[0]
			var start := rig.to_global(rig.get_bone_global_pose(bone).origin)
			var endpoint := rig.to_global(rig.get_bone_global_pose(end).origin) if end >= 0 else start + Vector3.UP * 0.12
			var length := maxf(start.distance_to(endpoint), 0.12)
			var name_lower := rig.get_bone_name(bone).to_lower()
			var radius := clampf(length * 0.22, 0.055, 0.13)
			if index < 3:
				radius = 0.16 if id != "the_monster" else 0.22
			if "head" in name_lower or (id == "player" and bone == 7):
				radius = 0.14
			var body := RigidBody3D.new()
			body.name = "Body%d" % index
			body.position = (start + endpoint) * 0.5
			body.freeze = true
			body.mass = 10.0 if index < 3 else 2.5
			body.collision_layer = 8
			body.collision_mask = 1
			body.continuous_cd = true
			body.linear_damp = 0.7
			body.angular_damp = 1.5
			body.set_meta("bone", rig.get_bone_name(bone))
			body.set_meta("end_bone", rig.get_bone_name(end) if end >= 0 else "")
			ragdoll.add_child(body)
			body.owner = ragdoll
			var collision := CollisionShape3D.new()
			var shape := CapsuleShape3D.new()
			shape.radius = radius
			shape.height = maxf(radius * 2.0, length)
			collision.shape = shape
			body.add_child(collision)
			collision.owner = ragdoll
			if index > 0:
				var parent := rig.get_bone_parent(bone)
				while parent >= 0 and not selected.has(parent):
					parent = rig.get_bone_parent(parent)
				var parent_index := selected.find(parent)
				if parent_index < 0:
					# Smily's source rig has a non-deforming root above the torso and
					# hips. Attach those top-level bodies to the torso instead of
					# emitting a free rigid body that can pull the skin away.
					if id == "smily":
						parent_index = 0
					else:
						continue
				var joint := ConeTwistJoint3D.new()
				joint.name = "Joint%d" % index
				joint.position = start
				joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(55))
				joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(25))
				joint.set_meta("parent_body", NodePath("Body%d" % parent_index))
				joint.set_meta("child_body", NodePath("Body%d" % index))
				ragdoll.add_child(joint)
				joint.owner = ragdoll
		var packed := PackedScene.new()
		packed.pack(ragdoll)
		ResourceSaver.save(packed, "res://scenes/characters/ragdolls/%s.tscn" % id)
		print("RAGDOLL_SCENE ", id, " bodies=", selected.size())
		ragdoll.free()
		visual.free()
	quit()
