extends SceneTree


## Only authors the two added creatures; existing three ragdolls are left untouched.
func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for id in ["head", "involuntary_evolution"]:
		var actor = load("res://scenes/characters/monsters/%s.tscn" % id).instantiate()
		root.add_child(actor)
		actor.set_physics_process(false)
		var rig: Skeleton3D = actor.visual.skeleton
		if rig == null:
			push_error("Missing rig: " + id)
			quit(1)
			return
		var selected: Array[int] = []
		for i in rig.get_bone_count():
			var label := rig.get_bone_name(i)
			if label == "root" or label.ends_with("_tip") or label == "jaw":
				continue
			selected.append(i)
		var ragdoll := Node3D.new()
		ragdoll.name = "Ragdoll"
		ragdoll.set_script(load("res://scripts/gameplay/skeletal_ragdoll.gd"))
		ragdoll.exclude_self_collision = true
		for index in selected.size():
			var bone := selected[index]
			var end := -1
			for child in rig.get_bone_children(bone):
				if rig.get_bone_name(child) != "jaw":
					end = child
					break
			var start := rig.get_bone_global_rest(bone).origin
			var endpoint := (
				rig.get_bone_global_rest(end).origin if end >= 0 else start + Vector3.UP * 0.12
			)
			var length := maxf(start.distance_to(endpoint), 0.08)
			var body := RigidBody3D.new()
			body.name = "Body%d" % index
			body.freeze = true
			body.mass = (5.0 if id == "head" else 12.0) if index == 0 else 1.5
			body.collision_layer = 8
			body.collision_mask = 1
			body.continuous_cd = true
			body.linear_damp = 0.9
			body.angular_damp = 2.0
			body.set_meta("bone", rig.get_bone_name(bone))
			body.set_meta("end_bone", rig.get_bone_name(end) if end >= 0 else "")
			ragdoll.add_child(body)
			body.owner = ragdoll
			var shape := CapsuleShape3D.new()
			shape.radius = (
				(0.28 if id == "head" else 0.26)
				if index == 0
				else (
					0.14
					if rig.get_bone_name(bone) == "skull"
					else clampf(length * 0.16, 0.025, 0.085)
				)
			)
			shape.height = maxf(shape.radius * 2.0, length)
			var collision := CollisionShape3D.new()
			collision.shape = shape
			body.add_child(collision)
			collision.owner = ragdoll
			if index == 0:
				continue
			var parent := rig.get_bone_parent(bone)
			while parent >= 0 and not selected.has(parent):
				parent = rig.get_bone_parent(parent)
			var joint := ConeTwistJoint3D.new()
			joint.name = "Joint%d" % index
			joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(45.0))
			joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(22.0))
			joint.set_meta("parent_body", NodePath("Body%d" % maxi(0, selected.find(parent))))
			joint.set_meta("child_body", NodePath("Body%d" % index))
			ragdoll.add_child(joint)
			joint.owner = ragdoll
		var packed := PackedScene.new()
		if (
			packed.pack(ragdoll) != OK
			or ResourceSaver.save(packed, "res://scenes/characters/ragdolls/%s.tscn" % id) != OK
		):
			quit(1)
			return
		print(
			"ADDED CREATURE RAGDOLL ",
			id,
			" bodies ",
			selected.size(),
			" animations ",
			actor.visual.animator.get_animation_list()
		)
		ragdoll.free()
		actor.free()
	quit()
