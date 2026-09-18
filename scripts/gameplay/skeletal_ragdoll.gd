class_name SkeletalRagdoll
extends Node3D

var skeleton: Skeleton3D
var bodies: Array[RigidBody3D] = []
var bone_indices: Array[int] = []
var offsets: Array[Transform3D] = []
var root_body: RigidBody3D
var root_bone_index := -1
var root_offset := Transform3D.IDENTITY
var initialized := false

func initialize(rig: Skeleton3D, simulate: bool, initial_velocity := Vector3.ZERO) -> void:
	skeleton = rig
	for child in get_children():
		if not child is RigidBody3D:
			continue
		var bone := rig.find_bone(str(child.get_meta("bone")))
		var end := rig.find_bone(str(child.get_meta("end_bone", "")))
		if bone < 0:
			continue
		var pose := rig.global_transform * rig.get_bone_global_pose(bone)
		var endpoint := rig.to_global(rig.get_bone_global_pose(end).origin) if end >= 0 else pose.origin + pose.basis.orthonormalized().y * 0.12
		var direction := endpoint - pose.origin
		if direction.length() < 0.01:
			direction = Vector3.UP * 0.12
		child.global_transform = Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())), pose.origin + direction * 0.5)
		bodies.append(child)
		bone_indices.append(bone)
		offsets.append(child.global_transform.affine_inverse() * pose)
		child.freeze = not simulate
		child.linear_velocity = initial_velocity.limit_length(8.0)
	if bodies.is_empty():
		return
	root_body = bodies[0]
	# Imported rigs keep a non-deforming root above the first physical bone.
	# When the corpse falls, leaving that root at its old world position makes
	# vertices weighted to it stretch between the root and the ragdoll. Follow
	# the physical root with a fixed offset so the complete skinned mesh falls
	# as one connected body while every selected limb remains simulated.
	root_bone_index = rig.get_bone_parent(bone_indices[0])
	if root_bone_index >= 0:
		var root_pose := rig.global_transform * rig.get_bone_global_pose(root_bone_index)
		root_offset = root_body.global_transform.affine_inverse() * root_pose
	for joint in get_children():
		if joint is ConeTwistJoint3D:
			var child_body := get_node(joint.get_meta("child_body")) as RigidBody3D
			var index := bodies.find(child_body)
			var anchor := skeleton.to_global(skeleton.get_bone_global_pose(bone_indices[index]).origin)
			# Rebuild the constraint after matching the actual animation pose.
			joint.node_a = NodePath()
			joint.node_b = NodePath()
			joint.global_transform = Transform3D(child_body.global_basis, anchor)
			joint.node_a = joint.get_path_to(get_node(joint.get_meta("parent_body")))
			joint.node_b = joint.get_path_to(child_body)
	initialized = true
	if simulate:
		root_body.apply_central_impulse(Vector3(0.5, 0, -1.5))

func _process(_delta: float) -> void:
	if not initialized or not is_instance_valid(skeleton):
		return
	var inverse := skeleton.global_transform.affine_inverse()
	if root_body != null and root_bone_index >= 0:
		var root_pose := inverse * root_body.global_transform * root_offset
		skeleton.set_bone_global_pose_override(root_bone_index, root_pose, 1.0, true)
	for index in bodies.size():
		skeleton.set_bone_global_pose_override(bone_indices[index], inverse * bodies[index].global_transform * offsets[index], 1.0, true)

func capture() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	for body in bodies:
		poses.append(body.global_transform)
	return poses

func apply_poses(poses: Array) -> void:
	if poses.size() != bodies.size():
		return
	for index in bodies.size():
		bodies[index].global_transform = poses[index]
	_process(0)

func settled() -> bool:
	for body in bodies:
		if body.linear_velocity.length() > 0.15 or body.angular_velocity.length() > 0.25:
			return false
	return true

func freeze_all() -> void:
	for body in bodies:
		body.freeze = true

func clear_pose() -> void:
	if is_instance_valid(skeleton):
		skeleton.clear_bones_global_pose_override()
