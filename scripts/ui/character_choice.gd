extends TextureButton
## Hit areas follow the animated head, torso and arms without GPU image readback.
const REGIONS := [
	["Hips", "Spine2", .21], ["Spine2", "Neck", .18],
	["Head", "HeadTop_End", .12],
	["LeftArm", "LeftForeArm", .09], ["LeftForeArm", "LeftHand", .08],
	["RightArm", "RightForeArm", .09], ["RightForeArm", "RightHand", .08],
]
var _skeleton: Skeleton3D
var _camera: Camera3D
var _bones: Array[Vector2i] = []

func setup(skeleton: Skeleton3D, camera: Camera3D) -> void:
	_skeleton = skeleton
	_camera = camera
	for region in REGIONS:
		_bones.append(Vector2i(skeleton.find_bone(region[0]), skeleton.find_bone(region[1])))

func _has_point(point: Vector2) -> bool:
	if not is_instance_valid(_skeleton) or not Rect2(Vector2.ZERO, size).has_point(point): return false
	var pixel := point / size * Vector2(_camera.get_viewport().size)
	for index in _bones.size():
		var bones := _bones[index]
		var start := _skeleton.to_global(_skeleton.get_bone_global_pose(bones.x).origin)
		var end := _skeleton.to_global(_skeleton.get_bone_global_pose(bones.y).origin)
		var projected_start := _camera.unproject_position(start)
		var projected_end := _camera.unproject_position(end)
		var edge := _camera.unproject_position(start + _camera.global_basis.x * float(REGIONS[index][2]))
		var radius := projected_start.distance_to(edge)
		if pixel.distance_to(Geometry2D.get_closest_point_to_segment(pixel, projected_start, projected_end)) <= radius:
			return true
	return false
