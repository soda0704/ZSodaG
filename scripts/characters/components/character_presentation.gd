class_name GameCharacterPresentation
extends Node3D

@export var variants: Array[CharacterVisualVariant] = []
@export var first_person_parent := NodePath("../Head/Camera3D")
@export_range(1.0, 30.0) var parameter_smoothing := 12.0

var variant: CharacterVisualVariant
var model: Node3D
var first_person_model: Node3D
var skeleton: Skeleton3D
var _skeleton: Skeleton3D
var _trees: Array[AnimationTree] = []
var _view_tree: AnimationTree
var _sleeping := false
var _dead := false
var _facing_yaw := 0.0
var _previous_velocity := Vector3.ZERO
var _lean := Vector2.ZERO
var _upper_blend := 0.0
var _previous_grounded := true
var _sampled := false
var _equipment_kind := ""
var _journal_phase := 0
var _local := false
var _corpse_action := ""

func _ready() -> void:
	var player := get_parent()
	_local = player.is_local_player()
	_facing_yaw = player.rotation.y
	var id: int = clampi(player.character_variant_id,0,variants.size()-1)
	variant = variants[id]
	model = variant.body_scene.instantiate()
	add_child(model)
	model.name = "CharacterModel"
	skeleton = model.get_node("Skeleton3D")
	_skeleton = skeleton
	_prepare_tree(model)
	if _local:
		first_person_model = variant.first_person_scene.instantiate()
		get_node(first_person_parent).add_child(first_person_model)
		first_person_model.visible = false
		_prepare_tree(first_person_model)
	set_local_visibility(false)

func _prepare_tree(instance: Node3D) -> void:
	var tree: AnimationTree = instance.get_node("AnimationTree")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	_trees.append(tree)
	if instance==first_person_model: _view_tree = tree
	var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
	playback.start("Stand")

func _process(delta: float) -> void:
	# Skinning is evaluated per rendered frame. Interpolating the animated
	# hand attachment again would make the weapon trail behind its fingers.
	if not _dead and _view_tree != null and _view_tree.active:
		_view_tree.advance(delta)

func set_local_visibility(dead: bool) -> void:
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mesh.layers = 1 | (1<<18)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if _local and not dead else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Third-person attachments are replaced by the view rig for the owner.
	model.get_node("Skeleton3D/RightHand/Equipment").visible = not _local or dead
	if first_person_model != null and dead: first_person_model.hide()

func equipment_root() -> Node3D:
	var instance := first_person_model if _local and first_person_model != null else model
	return instance.get_node("Skeleton3D/RightHand/Equipment")

func equipment_socket(label: String) -> Node3D:
	return equipment_root().get_node(label)

func set_sleeping(value: bool) -> void:
	_sleeping = value

func set_corpse_action(clip: String, elapsed: float = 0.0) -> void:
	_corpse_action = "CarryPickup" if clip=="pickup" else "CarryPlace" if clip=="place" else ""
	if _corpse_action.is_empty(): return
	for tree in _trees:
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
		playback.travel(_corpse_action)
		tree.set("parameters/Movement/%s/ActionTime/seek_request"%_corpse_action,maxf(elapsed,0.0))

func update_context(delta: float, context: Dictionary) -> void:
	if _dead: return
	var weight := 1.0-exp(-parameter_smoothing*delta)
	var world_velocity: Vector3 = context.get("velocity",Vector3.ZERO)
	var view_yaw: float = context.get("yaw",0.0)
	var difference := angle_difference(_facing_yaw,view_yaw)
	var moving := Vector2(world_velocity.x,world_velocity.z).length()>0.18
	if moving or absf(difference)>deg_to_rad(variant.idle_turn_limit_degrees):
		_facing_yaw = lerp_angle(_facing_yaw,view_yaw,1-exp(-variant.body_turn_speed*delta))
	# Facing is a root orientation; all limb motion comes from animation assets.
	rotation.y = angle_difference(get_parent().rotation.y,_facing_yaw)
	model.get_node("LookTarget").global_position = get_parent().head.global_position-get_parent().head.global_basis.z*4.0
	var relative_velocity := global_basis.inverse()*world_velocity
	var planar_velocity := Vector2(relative_velocity.x,relative_velocity.z)
	var acceleration := (world_velocity-_previous_velocity)/maxf(delta,0.001)
	acceleration = global_basis.inverse()*acceleration
	_previous_velocity = world_velocity
	_lean = _lean.lerp(Vector2(acceleration.x,acceleration.z).limit_length(15)/15,weight)
	var grounded: bool = context.get("grounded",true)
	var crouch: bool = context.get("crouching",false)
	var journal: int = context.get("journal_phase",0)
	if journal>0: model.get_node("LookTarget").global_position = model.get_node("JournalLookTarget").global_position
	if journal>0 and _journal_phase==0:
		for tree in _trees: tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	model.get_node("Skeleton3D/RightHand/Equipment/Journal").visible = journal>0
	var kind: StringName = context.get("held_item",&"")
	var state := "Stand"
	if _sleeping: state = "Sleep"
	elif context.get("driving",false): state = "Vehicle"
	elif not _corpse_action.is_empty(): state = _corpse_action
	elif journal > 0:
		state = "JournalOpen" if journal==1 else "JournalReading" if journal==2 else "JournalClose"
	elif not grounded:
		state = "JumpStart" if _previous_grounded and world_velocity.y>0.1 else "InAir"
	elif _sampled and not _previous_grounded: state = "Landing"
	elif crouch: state = "Crouch"
	elif not moving and absf(difference)>deg_to_rad(variant.idle_turn_limit_degrees): state = "TurnLeft" if difference>0 else "TurnRight"
	var equipment := _kind_name(kind)
	if context.get("carrying",false): equipment = "Carry"
	var upper_target := 1.0 if not equipment.is_empty() and journal==0 and not _sleeping and not context.get("driving",false) and _corpse_action.is_empty() else 0.0
	_upper_blend = lerpf(_upper_blend,upper_target,weight)
	for tree in _trees:
		var first := first_person_model != null and tree.get_parent()==first_person_model
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
		var current := String(playback.get_current_node())
		# The view rig inherits camera movement. Full-body gait, turns and landing
		# must not move its pelvis underneath an otherwise steady equipment pose.
		var requested := "Stand" if first and journal==0 and _corpse_action.is_empty() else state
		if requested=="Crouch" and current not in ["Crouch","CrouchEnter"]: requested = "CrouchEnter"
		elif requested=="Stand" and current=="Crouch": requested = "CrouchExit"
		if requested=="Stand" and current in ["Landing","CrouchExit","JournalClose","TurnLeft","TurnRight"]:
			pass
		elif requested=="InAir" and current=="JumpStart":
			pass
		elif requested=="Crouch" and current=="CrouchEnter":
			pass
		elif requested!=current:
			playback.travel(requested)
		tree.set("parameters/Movement/Stand/Locomotion/blend_position",Vector2.ZERO if first else planar_velocity)
		tree.set("parameters/Movement/Crouch/Locomotion/blend_position",Vector2.ZERO if first else planar_velocity)
		var speed := planar_velocity.length()
		var forward_weight := maxf(-planar_velocity.normalized().y,0.0)
		var walk_stride := lerpf(variant.other_walk_stride_speed,variant.forward_walk_stride_speed,forward_weight)
		var nominal := lerpf(walk_stride,variant.run_stride_speed,clampf((speed-4.0)/2.8,0,1))
		tree.set("parameters/Movement/Stand/StrideRate/scale",(clampf(speed/nominal,0.65,2.4) if speed>0.2 else 1.0)*variant.locomotion_rate)
		tree.set("parameters/Movement/Crouch/StrideRate/scale",(clampf(speed/variant.crouch_stride_speed,0.65,2.4) if speed>0.2 else 1.0)*variant.locomotion_rate)
		# The first visible frame must already have the equipped pose, not the
		# world body's arms swinging up through the camera during the blend.
		tree.set("parameters/UpperBody/blend_amount",upper_target if first else _upper_blend)
		tree.set("parameters/Lean/blend_position",_lean)
		tree.set("parameters/Inertia/add_amount",0.0 if first else variant.inertia_strength)
		if not equipment.is_empty():
			if equipment!=_equipment_kind: tree.set("parameters/Equipment/transition_request",equipment)
			for name in ["Rifle","Pistol","Knife","Flashlight","Fuse","Fuel","Carry"]:
				tree.set("parameters/%s/blend_position"%name,0.0 if first else clampf(context.get("pitch",0.0),-1.25,1.25))
		if not first: tree.advance(delta)
		var instance: Node3D = tree.get_parent()
		var ik: TwoBoneIK3D = instance.get_node("Skeleton3D/SupportHandIK")
		var ik_target := 1.0 if equipment in ["Rifle","Pistol"] and journal==0 and upper_target>0.5 and not context.get("reloading",false) else 0.0
		ik.active = true
		ik.influence = lerpf(ik.influence,ik_target,weight)
		if ik_target>0:
			var weapon_name := "m4a1" if equipment=="Rifle" else "pistol"
			ik.set_target_node(0,ik.get_path_to(instance.get_node("Skeleton3D/RightHand/Equipment/%s/SupportHand"%weapon_name)))
	if first_person_model != null:
		first_person_model.visible = (upper_target>0.5 or not _corpse_action.is_empty()) and journal==0 and not context.get("driving",false)
	_previous_grounded = grounded
	_journal_phase = journal
	_sampled = true
	for modifier in skeleton.get_children():
		if modifier is LookAtModifier3D: modifier.active = not _sleeping
	if not equipment.is_empty(): _equipment_kind = equipment

func _kind_name(kind: StringName) -> String:
	return {&"m4a1":"Rifle",&"pistol":"Pistol",&"kitchen_knife":"Knife",&"flashlight":"Flashlight",&"fuse":"Fuse",&"fuel_can":"Fuel"}.get(kind,"")

func weapon_effect(kind: StringName, reload: bool) -> void:
	var name := _kind_name(kind)
	if name.is_empty(): return
	for tree in _trees:
		if name=="Knife":
			tree.set("parameters/Action/transition_request","KnifeAttack")
			tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		elif reload:
			tree.set("parameters/Action/transition_request",name+"Reload")
			tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		else:
			tree.set("parameters/Recoil/transition_request",name)
			tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func weapon_battery_action(kind: StringName) -> void:
	var name := _kind_name(kind)
	if name.is_empty(): return
	for tree in _trees:
		tree.set("parameters/Action/transition_request",name+"Battery")
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func cancel_weapon_action() -> void:
	for tree in _trees:
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

func begin_death() -> void:
	_dead = true
	model.get_node("Skeleton3D/RightHand/Equipment/Journal").hide()
	set_local_visibility(true)
	for tree in _trees:
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/UpperBody/blend_amount",0.0)
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
		playback.travel("Death")

func advance_death(delta: float) -> void:
	for tree in _trees: tree.advance(delta)

func freeze_for_ragdoll() -> void:
	for tree in _trees: tree.active = false
	for instance in [model,first_person_model]:
		if instance != null:
			for modifier in instance.get_node("Skeleton3D").get_children():
				if modifier is SkeletonModifier3D: modifier.active = false
	skeleton.force_update_all_bone_transforms()

func restore_after_respawn() -> void:
	_dead = false
	_corpse_action = ""
	_sleeping = false
	_sampled = false
	_upper_blend = 0
	_equipment_kind = ""
	_lean = Vector2.ZERO
	_previous_velocity = Vector3.ZERO
	_facing_yaw = get_parent().rotation.y
	rotation.y = 0
	skeleton.clear_bones_global_pose_override()
	model.get_node("Skeleton3D/HeadLook").active = true
	model.get_node("Skeleton3D/NeckLook").active = true
	model.get_node("Skeleton3D/Spine2Look").active = true
	set_local_visibility(false)
	for tree in _trees:
		tree.active = true
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
		playback.start("Stand")
