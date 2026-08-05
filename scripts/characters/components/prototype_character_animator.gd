class_name PrototypeCharacterAnimator
extends Node3D

const BONE_UPPER_ARM_LEFT := "upper_arm.L_09"
const BONE_UPPER_ARM_RIGHT := "upper_arm.R_013"
const BONE_THIGH_LEFT := "thigh.L_022"
const BONE_THIGH_RIGHT := "thigh.R_027"
const BONE_SHIN_LEFT := "shin.L_023"
const BONE_SHIN_RIGHT := "shin.R_028"
const BONE_SPINE := "spine.003_04"

@export var walk_cycle_speed: float = 8.0
@export var sprint_cycle_speed: float = 11.0
@export var walk_leg_angle_degrees: float = 24.0
@export var sprint_leg_angle_degrees: float = 34.0

var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _bone_indices: Dictionary = {}
var _base_rotations: Dictionary = {}
var _base_position: Vector3
var _cycle: float = 0.0
var _crouch_blend: float = 0.0


func _ready() -> void:
	_base_position = position
	_skeleton = find_descendant_by_type(self, "Skeleton3D") as Skeleton3D
	_mesh = find_descendant_by_type(self, "MeshInstance3D") as MeshInstance3D
	if _skeleton == null:
		push_warning("Prototype character has no Skeleton3D")
		return

	for bone_name in [
		BONE_UPPER_ARM_LEFT,
		BONE_UPPER_ARM_RIGHT,
		BONE_THIGH_LEFT,
		BONE_THIGH_RIGHT,
		BONE_SHIN_LEFT,
		BONE_SHIN_RIGHT,
		BONE_SPINE,
	]:
		var bone_index := _skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		_bone_indices[bone_name] = bone_index
		_base_rotations[bone_name] = _skeleton.get_bone_pose_rotation(bone_index)


func find_descendant_by_type(node: Node, class_type: StringName) -> Node:
	if node.is_class(class_type):
		return node
	for child in node.get_children():
		var found := find_descendant_by_type(child, class_type)
		if found != null:
			return found
	return null


func set_avatar_color(color: Color) -> void:
	if _mesh == null:
		return
	var source_material := _mesh.get_active_material(0)
	if source_material == null:
		return
	var material := source_material.duplicate()
	if material is StandardMaterial3D:
		var standard_material := material as StandardMaterial3D
		standard_material.albedo_color = color
		standard_material.roughness = 0.72
	_mesh.material_override = material


func update_pose(
	delta: float,
	horizontal_speed: float,
	grounded: bool,
	sprinting: bool,
	crouching: bool,
	vertical_velocity: float
) -> void:
	if _skeleton == null or not visible:
		return

	var moving := horizontal_speed > 0.12
	var cycle_speed := sprint_cycle_speed if sprinting else walk_cycle_speed
	if moving and grounded:
		_cycle = fmod(_cycle + delta * cycle_speed, TAU)
	else:
		_cycle = lerpf(_cycle, 0.0, 1.0 - exp(-6.0 * delta))

	_crouch_blend = move_toward(
		_crouch_blend,
		1.0 if crouching else 0.0,
		delta * 7.5
	)
	var pose_weight := 1.0 - exp(-13.0 * delta)
	var leg_angle := deg_to_rad(
		sprint_leg_angle_degrees if sprinting else walk_leg_angle_degrees
	)
	var stride := sin(_cycle) * leg_angle if moving and grounded else 0.0
	var airborne_blend := 0.0 if grounded else 1.0
	var jump_tuck := clampf(absf(vertical_velocity) / 5.0, 0.25, 1.0)

	set_bone_angle(
		BONE_THIGH_LEFT,
		stride + _crouch_blend * 0.52 + airborne_blend * 0.18 * jump_tuck,
		pose_weight
	)
	set_bone_angle(
		BONE_THIGH_RIGHT,
		-stride + _crouch_blend * 0.52 - airborne_blend * 0.12 * jump_tuck,
		pose_weight
	)
	set_bone_angle(
		BONE_SHIN_LEFT,
		maxf(-stride, 0.0) * 0.7 - _crouch_blend * 0.82,
		pose_weight
	)
	set_bone_angle(
		BONE_SHIN_RIGHT,
		maxf(stride, 0.0) * 0.7 - _crouch_blend * 0.82,
		pose_weight
	)
	set_bone_angle(
		BONE_UPPER_ARM_LEFT,
		-stride * 0.72 + airborne_blend * 0.18,
		pose_weight
	)
	set_bone_angle(
		BONE_UPPER_ARM_RIGHT,
		stride * 0.72 + airborne_blend * 0.18,
		pose_weight
	)
	set_bone_angle(
		BONE_SPINE,
		(-0.08 if sprinting and moving else 0.0) + _crouch_blend * 0.16,
		pose_weight
	)

	var step_bob := (
		absf(sin(_cycle * 2.0)) * 0.025
		if moving and grounded
		else 0.0
	)
	position.y = lerpf(
		position.y,
		_base_position.y - _crouch_blend * 0.34 + step_bob,
		1.0 - exp(-12.0 * delta)
	)


func set_bone_angle(bone_name: StringName, angle: float, weight: float) -> void:
	if not _bone_indices.has(bone_name):
		return
	var bone_index := int(_bone_indices[bone_name])
	var base_rotation := _base_rotations[bone_name] as Quaternion
	var target := base_rotation * Quaternion(Vector3.RIGHT, angle)
	var current := _skeleton.get_bone_pose_rotation(bone_index)
	_skeleton.set_bone_pose_rotation(
		bone_index,
		current.slerp(target, weight).normalized()
	)
