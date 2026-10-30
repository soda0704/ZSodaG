class_name MonsterVisual
extends Node3D
## Presentation adapter; AI never depends on animation names, bones or the model ID.
@export_node_path("Node3D") var model_path := NodePath("Model")
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export var idle_animation: StringName
@export var walk_animation: StringName
@export var attack_animation: StringName
@export_range(0.0, 1.0) var blend_time := 0.12
@export var prototype_motion := true
## Movement speed used when authoring the planted-foot gait.
@export_range(0.1, 12.0) var walk_reference_speed := 1.0
@export_group("Animation reel")
## Enable only for a model whose imported animation contains several actions in one reel.
@export var use_animation_reel := false
@export var idle_reel := Vector2(0.0, 2.8)
@export var walk_reel := Vector2(65.0, 66.0)
@export var attack_reel := Vector2(30.0, 32.0)
@export var death_reel := Vector2(239.5, 241.0)
## Optional bone whose imported translation must not override the CharacterBody movement.
@export var root_motion_bone: StringName
var model: Node3D
var animator: AnimationPlayer
var animation_name: StringName
var phase := 0.0
var base_y := 0.0
var model_id := ""
var death_time := 0.0
var skeleton: Skeleton3D
var root_bone := -1
var root_pose := Transform3D.IDENTITY
var motion_state := ""


func setup(id: String, _height: float = 2.1) -> void:
	model_id = id
	model = get_node_or_null(model_path) as Node3D
	if model == null:
		return
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	animator = (
		get_node_or_null(animation_player_path) as AnimationPlayer
		if not animation_player_path.is_empty()
		else null
	)
	if animator == null:
		var players := model.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			animator = players[0]
	if animator != null:
		# Authored gait and contact audio share the movement clock, including catch-up ticks.
		if not walk_animation.is_empty():
			animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
		for clip in animator.get_animation_list():
			if clip != &"RESET":
				animation_name = clip
				break
		if not animation_name.is_empty():
			animator.play(animation_name)
			animator.seek(0.0, true)
			animator.pause()
	base_y = model.position.y
	var rigs := model.find_children("*", "Skeleton3D", true, false)
	if not rigs.is_empty():
		skeleton = rigs[0]
	if skeleton != null and not root_motion_bone.is_empty():
		root_bone = skeleton.find_bone(root_motion_bone)
		if root_bone >= 0:
			root_pose = skeleton.get_bone_pose(root_bone)


func animate(
	delta: float,
	moving: bool,
	attacking: bool,
	dead: bool,
	attack_duration: float = 0.5,
	movement_speed: float = 1.0
) -> void:
	if model == null:
		return
	var next_state := "death" if dead else "attack" if attacking else "walk" if moving else "idle"
	var changed := next_state != motion_state
	if changed:
		phase = 0.0
		motion_state = next_state
	phase += delta
	if animator != null and not animation_name.is_empty() and use_animation_reel:
		var segment := (
			death_reel if dead else attack_reel if attacking else walk_reel if moving else idle_reel
		)
		var duration := maxf(segment.y - segment.x, 0.001)
		var time := (
			segment.x
			+ (
				minf(phase / maxf(attack_duration, 0.01), 1.0) * duration
				if attacking
				else minf(phase, duration) if dead else fmod(phase, duration)
			)
		)
		animator.seek(clampf(time, 0.0, animator.get_animation(animation_name).length), true)
		if not dead and root_bone >= 0 and skeleton != null:
			skeleton.set_bone_pose(root_bone, root_pose)
		return
	var authored := attack_animation if attacking else walk_animation if moving else idle_animation
	if (
		animator != null
		and not authored.is_empty()
		and animator.has_animation(authored)
		and not dead
	):
		if changed or animator.current_animation != authored:
			animator.play(authored, blend_time)
		animator.speed_scale = (
			animator.get_animation(authored).length / maxf(attack_duration, 0.01)
			if attacking
			else clampf(movement_speed / walk_reference_speed, 0.1, 4.0) if moving else 1.0
		)
		return
	if animator != null and not animation_name.is_empty() and not dead:
		animator.pause()
		var clip := animator.get_animation(animation_name)
		animator.seek(
			fmod(phase * (1.3 if moving else 0.5), maxf(minf(clip.length, 3.0), 0.001)), true
		)
	if dead:
		if animator != null:
			animator.pause()
		model.position.y = base_y
		rotation.x = 0.0
		rotation.z = 0.0
	elif prototype_motion:
		model.position.y = base_y + absf(sin(phase * 8.0)) * (0.055 if moving else 0.01)
		rotation.x = sin(phase * 18.0) * 0.2 if attacking else 0.0
		rotation.z = sin(phase * 7.0) * 0.04 if moving else 0.0
