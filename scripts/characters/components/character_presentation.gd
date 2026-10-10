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
var _external_view := false
var _corpse_action := ""
var first_person: GameFirstPersonPresentation

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
		first_person = preload("res://scripts/characters/components/first_person_presentation.gd").new()
		first_person.name="FirstPersonPresentation"
		get_node(first_person_parent).add_child(first_person)
		first_person.initialize(variant.first_person_scene,get_node(first_person_parent))
		first_person_model=first_person.model
		_make_shadow_items()
	set_local_visibility(false)

func _prepare_tree(instance: Node3D) -> void:
	var tree: AnimationTree = instance.get_node("AnimationTree")
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	_trees.append(tree)
	var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
	playback.start("Stand")

func _make_shadow_items() -> void:
	var sockets: Node3D=model.get_node("Skeleton3D/RightHand/Equipment")
	for pair in [["FlashlightGrip","res://scenes/objects/equipment/flashlight_model.tscn"],["FuseGrip","res://scenes/objects/items/fuse_model.tscn"],["FuelGrip","res://scenes/objects/items/fuel_can_model.tscn"]]:
		var visual: Node3D=load(pair[1]).instantiate()
		sockets.get_node(pair[0]).add_child(visual); visual.name="ShadowItem"
		if pair[0]=="FlashlightGrip": visual.position.z=-0.22

func set_local_visibility(dead: bool) -> void:
	_update_world_visibility(dead)
	if first_person != null: first_person.set_dead(dead)

func set_external_view(value: bool) -> void:
	_external_view = value
	_update_world_visibility(_dead)
	if first_person != null: first_person.set_external_view(value)

func _update_world_visibility(dead: bool) -> void:
	var hide_body := _local and not dead and not _external_view
	for mesh: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		mesh.layers = (1<<17)|(1<<18) if hide_body else 1|(1<<18)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if hide_body else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Third-person attachments are replaced by the view rig for the owner.
	model.get_node("Skeleton3D/RightHand/Equipment").visible = true

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
	var limited_pitch:=clampf(float(context.get("pitch",0)),-0.62,0.62)
	var limited_yaw:=clampf(angle_difference(_facing_yaw,view_yaw),-0.52,0.52)
	model.get_node("LookTarget").global_position = get_parent().head.global_position+global_basis*Basis.from_euler(Vector3(limited_pitch,limited_yaw,0))*Vector3(0,0,-4)
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
	model.get_node("Journal").visible = journal>0
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
	model.get_node("Skeleton3D/Spine2Look").influence=0.15 if journal>0 else 0.25 if not equipment.is_empty() else 0.70
	if context.get("carrying",false): equipment = "Carry"
	var upper_target := 1.0 if not equipment.is_empty() and journal==0 and not _sleeping and not context.get("driving",false) and _corpse_action.is_empty() else 0.0
	_upper_blend = lerpf(_upper_blend,upper_target,weight)
	for tree in _trees:
		var playback: AnimationNodeStateMachinePlayback = tree.get("parameters/Movement/playback")
		var current := String(playback.get_current_node())
		var requested := state
		if requested=="Crouch" and current not in ["Crouch","CrouchEnter"]: requested = "CrouchEnter"
		elif requested=="Stand" and current=="Crouch": requested = "CrouchExit"
		if requested=="Stand" and current in ["Landing","CrouchExit","JournalClose","TurnLeft","TurnRight"]:
			pass
		elif requested=="InAir" and current=="JumpStart":
			pass
		elif requested=="Crouch" and current=="CrouchEnter":
			pass
		elif requested!=current:
			# Repeating travel() while an AT_END transition is queued restarts its
			# path and can hold JournalOpen indefinitely at an intermediate pose.
			if requested!=String(tree.get_meta("requested_state","")):
				playback.travel(requested)
				tree.set_meta("requested_state",requested)
		else: tree.set_meta("requested_state",requested)
		tree.set("parameters/Movement/Stand/Locomotion/blend_position",planar_velocity)
		tree.set("parameters/Movement/Crouch/Locomotion/blend_position",planar_velocity)
		var speed := planar_velocity.length()
		var forward_weight := maxf(-planar_velocity.normalized().y,0.0)
		var walk_stride := lerpf(variant.other_walk_stride_speed,variant.forward_walk_stride_speed,forward_weight)
		var nominal := lerpf(walk_stride,variant.run_stride_speed,clampf((speed-4.0)/2.8,0,1))
		tree.set("parameters/Movement/Stand/StrideRate/scale",(clampf(speed/nominal,0.65,2.4) if speed>0.2 else 1.0)*variant.locomotion_rate)
		tree.set("parameters/Movement/Crouch/StrideRate/scale",(clampf(speed/variant.crouch_stride_speed,0.65,2.4) if speed>0.2 else 1.0)*variant.locomotion_rate)
		tree.set("parameters/UpperBody/blend_amount",_upper_blend)
		tree.set("parameters/Lean/blend_position",_lean)
		tree.set("parameters/Inertia/add_amount",variant.inertia_strength)
		if not equipment.is_empty():
			if equipment!=_equipment_kind: tree.set("parameters/Equipment/transition_request",equipment)
			for name in ["Rifle","Pistol","Knife","Flashlight","Fuse","Fuel","Carry"]:
				tree.set("parameters/%s/blend_position"%name,clampf(limited_pitch*0.70-(0.10 if name in ["Rifle","Pistol"] and not context.get("aiming",false) else 0.0),-0.48,0.48))
		tree.advance(delta)
		GameFirstPersonPresentation.update_grips(model,equipment,journal,context.get("reloading",false),delta)
	if first_person!=null:
		var fp_context:=context.duplicate(); fp_context["sleeping"]=_sleeping
		first_person.update_context(fp_context)
		_sync_world_items(kind,journal)
	_previous_grounded = grounded
	_update_floor_offset(grounded and not _sleeping and not context.get("driving", false))
	_journal_phase = journal
	_sampled = true
	for modifier in skeleton.get_children():
		if modifier is LookAtModifier3D: modifier.active = not _sleeping
	if not equipment.is_empty(): _equipment_kind = equipment

func _update_floor_offset(grounded: bool) -> void:
	# CharacterBody keeps a collision safety gap above the support surface.
	# The world model's baked sole plane belongs on that surface, also on peers.
	model.position.y = 0.0
	if not grounded: return
	var player := get_parent() as CharacterBody3D
	if player == null: return
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.15, player.global_position + Vector3.DOWN * 0.20, player.collision_mask)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.y >= cos(player.floor_max_angle):
		model.position.y = clampf(hit.position.y - player.global_position.y, -0.15, 0.10)

func _kind_name(kind: StringName) -> String:
	return {&"m4a1":"Rifle",&"pistol":"Pistol",&"kitchen_knife":"Knife",&"flashlight":"Flashlight",&"fuse":"Fuse",&"fuel_can":"Fuel"}.get(kind,"")

func _sync_world_items(kind: StringName, journal: int) -> void:
	var sockets: Node3D=model.get_node("Skeleton3D/RightHand/Equipment")
	for label in ["pistol","m4a1","kitchen_knife"]: sockets.get_node(label).visible=String(kind)==label and journal==0
	for pair in [["FlashlightGrip",&"flashlight"],["FuseGrip",&"fuse"],["FuelGrip",&"fuel_can"]]: sockets.get_node(pair[0]+"/ShadowItem").visible=kind==pair[1] and journal==0
	sockets.get_node("MountedLamp").visible=get_parent().weapon_light_mounted and journal==0
	sockets.get_node("MountedLamp/Beam").visible=false

func weapon_effect(kind: StringName, reload: bool) -> void:
	var name := _kind_name(kind)
	if name.is_empty(): return
	if first_person!=null: first_person.action(name,"Attack" if name=="Knife" else "Reload" if reload else "Recoil")
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
	if first_person!=null: first_person.action(name,"Battery")
	for tree in _trees:
		tree.set("parameters/Action/transition_request",name+"Battery")
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func cancel_weapon_action() -> void:
	if first_person!=null: first_person.cancel_action()
	for tree in _trees:
		tree.set("parameters/Handling/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/Kick/request",AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)

func begin_death() -> void:
	_dead = true
	model.get_node("Journal").hide()
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
