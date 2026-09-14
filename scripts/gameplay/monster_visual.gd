class_name MonsterVisual
extends Node3D

var model: Node3D
var animator: AnimationPlayer
var animation_name: StringName
var phase: float = 0.0
var base_y: float = 0.0
var model_id := ""
var death_time := 0.0
var skeleton: Skeleton3D
var root_bone := -1
var root_pose := Transform3D.IDENTITY
var motion_state := ""

func setup(id: String, height: float = 2.1) -> void:
	model_id = id
	model = (load("res://assets/monsters/%s/scene.gltf" % id) as PackedScene).instantiate()
	add_child(model)
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		animator = players[0]
		for clip in animator.get_animation_list():
			if clip != &"RESET":
				animation_name = clip
				break
		if not animation_name.is_empty():
			animator.play(animation_name)
			animator.seek(0.0, true)
			animator.pause()
	# Calibrated from skinned pose bounds, not the unskinned mesh AABB.
	# Fixed calibration also works on headless authoritative servers.
	var sizes := {"the_monster": 0.833777, "slasher": 1.17651, "smily": 0.02173}
	var offsets := {"the_monster": Vector3(0.051237, 0.079778, 2.856270), "slasher": Vector3(-0.003169, 0.001185, 0.008035), "smily": Vector3(1.694613, 0.03887, -0.173227)}
	model.scale *= float(sizes[id]) * height / 2.1
	model.position = offsets[id] * height / 2.1
	base_y = model.position.y
	# Imported creatures face +Z; the character controller faces -Z.
	rotation.y = PI
	if id == "the_monster":
		skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
		root_bone = skeleton.find_bone("root_02")
		root_pose = skeleton.get_bone_pose(root_bone)

func animate(delta: float, moving: bool, attacking: bool, dead: bool) -> void:
	var next_state := "death" if dead else "attack" if attacking else "walk" if moving else "idle"
	if next_state != motion_state:
		phase = 0.0
		motion_state = next_state
	phase += delta
	if model_id == "the_monster":
		# Take 001 is a single animation reel. Keep root motion under the AI's control.
		var time := fmod(phase, 2.8)
		if dead:
			death_time = minf(death_time + delta, 1.5)
			time = 239.5 + death_time
		elif attacking:
			# The reel's actual claw-and-tail strike is at 30-32 seconds.
			# Run the full anticipation and contact during the AI's 0.5 s windup.
			time = 30.0 + minf(phase * 4.0, 2.0)
		elif moving:
			time = 65.0 + fmod(phase, 1.0)
		animator.seek(time, true)
		if not dead:
			skeleton.set_bone_pose(root_bone, root_pose)
		return
	if animator != null and not animation_name.is_empty() and not dead:
		var clip := animator.get_animation(animation_name)
		animator.seek(fmod(phase * (1.3 if moving else 0.5), minf(clip.length, 3.0)), true)
	if dead:
		# Body motion is handled by the corpse's RigidBody3D, never by a visual tilt.
		animator.seek(1.0, true)
		model.position.y = base_y
		rotation.x = 0
		rotation.z = 0
		return
	else:
		model.position.y = base_y + absf(sin(phase * 8.0)) * (0.055 if moving else 0.01)
		rotation.x = sin(phase * 18.0) * 0.2 if attacking else 0.0
		rotation.z = sin(phase * 7.0) * 0.04 if moving else 0.0
