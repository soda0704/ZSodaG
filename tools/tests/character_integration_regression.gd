extends SceneTree

const PLAYER := preload("res://scenes/characters/player.tscn")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func ticks(count: int) -> void:
	for i in count: await physics_frame

func pose(player: GamePlayer, values: Dictionary, frames: int = 30) -> void:
	var context := {"velocity":Vector3.ZERO,"grounded":true,"crouching":false,"yaw":0.0,"pitch":0.0,"held_item":&"","journal_phase":0}
	context.merge(values,true)
	for i in frames:
		player.body_animator.update_context(1.0/60,context)
		await physics_frame

func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var arena: Node3D = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for id in [0,1]:
		var player: GamePlayer = PLAYER.instantiate()
		player.name = "1"
		player.setup(1,"Character regression",Vector3(0,0.1,0),Color.WHITE,0,id)
		arena.get_node("Players").add_child(player)
		await ticks(12)
		player.set_physics_process(false)
		player.survival.set_physics_process(false)
		player.get_node("PlayerRagdoll").set_physics_process(false)
		var presentation := player.body_animator
		var rig := presentation.skeleton
		check(player.character_variant_id==id and presentation.variant.variant_id==id,"variant %d uses matching body and first-person assets"%id)
		check(rig.find_bone("LeftHandIndex3")>=0 and rig.find_bone("RightHandThumb3")>=0,"variant %d retains real articulated fingers"%id)
		check(rig.get_bone_count()==(79 if id==0 else 88) and rig.get_node("Body").mesh.resource_path.contains("tactical_"+("a" if id==0 else "b")),"variant %d loads its own complete mesh and rig"%id)
		var library: AnimationLibrary = presentation.model.get_node("AnimationPlayer").get_animation_library(&"")
		for clip in ["Idle","WalkForward","RunForward","CrouchEnter","CrouchExit","InAir","JumpStart","Landing","JournalOpen","JournalReading","JournalClose","RifleReload","PistolReload","Death","CarryPickup","CarryPlace"]:
			check(library.has_animation(clip),"variant %d has native %s clip"%[id,clip])
		for name in ["WalkForward","RunForward","CrouchForward","JournalOpen","TurnLeft","CarryPickup","CarryPlace"]:
			var clip := library.get_animation(name)
			var motion := false
			for track in clip.get_track_count():
				if clip.track_get_type(track)==Animation.TYPE_ROTATION_3D and clip.track_get_key_count(track)>1:
					var first: Quaternion = clip.track_get_key_value(track,0)
					for key in clip.track_get_key_count(track):
						var value: Quaternion = clip.track_get_key_value(track,key)
						motion = motion or absf(first.dot(value))<0.999
			check(motion,"variant %d %s retains moving native keys"%[id,name])
		await pose(player,{})
		var standing := rig.get_bone_global_pose(rig.find_bone("Hips")).origin.y
		await pose(player,{"crouching":true},80)
		var crouching := rig.get_bone_global_pose(rig.find_bone("Hips")).origin.y
		check(standing-crouching>0.4,"variant %d crouch changes skeletal pose"%id)
		await pose(player,{"crouching":false},80)
		check(absf(rig.get_bone_global_pose(rig.find_bone("Hips")).origin.y-standing)<0.08,"variant %d stands through native transition"%id)
		await pose(player,{"velocity":Vector3(0,4,0),"grounded":false},20)
		var air_foot := rig.get_bone_global_pose(rig.find_bone("LeftFoot")).origin.y
		check(air_foot>0.20,"variant %d airborne pose bends legs"%id)
		await pose(player,{"grounded":true},70)
		presentation.set_corpse_action("pickup")
		await pose(player,{"carrying":true},29)
		check(standing-rig.get_bone_global_pose(rig.find_bone("Hips")).origin.y>0.25,"variant %d bends to lift the corpse through AnimationTree"%id)
		presentation.set_corpse_action("place",0.5)
		await pose(player,{"carrying":true},12)
		check(rig.get_bone_global_pose(rig.find_bone("RightHand")).origin.z<-0.25,"variant %d restores an in-progress native placement"%id)
		presentation.set_corpse_action("")
		await pose(player,{},40)
		for kind in [&"pistol",&"m4a1",&"kitchen_knife",&"flashlight",&"fuse",&"fuel_can"]:
			player._held_item_type = kind
			if kind in WeaponController.TYPES: player.weapon.apply_state(kind,12,0)
			await pose(player,{"held_item":kind})
			var right := rig.get_bone_global_pose(rig.find_bone("RightHand")).origin
			check(right.is_finite() and right.y>0.70 and right.y<1.70,"variant %d holds %s with a valid wrist pose"%[id,kind])
		check(player.flashlight.get_parent()==presentation.equipment_socket("FlashlightGrip"),"variant %d flashlight is attached to a real hand socket"%id)
		check(player.weapon._pose==presentation.equipment_root(),"variant %d weapon gameplay uses authored equipment scene"%id)
		var journal: QuestJournalUI = root.get_node("QuestJournal")
		journal.open_journal()
		await ticks(6)
		check(journal._arms_variant==id and journal._character_arms!=null,"variant %d journal loads matching complete arms"%id)
		var arms_rig: Skeleton3D = journal._character_arms.get_node("Skeleton3D")
		var initial := arms_rig.get_bone_global_pose(arms_rig.find_bone("LeftHand")).origin
		await pose(player,{"journal_phase":1},50)
		var raised := arms_rig.get_bone_global_pose(arms_rig.find_bone("LeftHand")).origin
		check(initial.distance_to(raised)>0.20,"variant %d independent FP journal raises its hands through AnimationTree"%id)
		journal.force_close()
		player.global_position = Vector3(8,0.1,-1.8)
		player.survival.death_velocity = Vector3(0,0,-5)
		player.survival.dead = true
		var rag = player.get_node("PlayerRagdoll")
		presentation.begin_death()
		presentation.advance_death(0.14)
		rag.start()
		check(rag.ragdoll.bodies.size()==17,"variant %d creates 17 physical ragdoll bodies"%id)
		check(rag.ragdoll.root_body.linear_velocity.z<-4.8,"variant %d preserves death momentum"%id)
		await ticks(120)
		var finite := true
		var contained := true
		for body in rag.ragdoll.bodies: finite = finite and body.global_position.is_finite() and body.linear_velocity.length()<35
		for body in rag.ragdoll.bodies: contained = contained and body.global_position.z>-3.20
		check(finite,"variant %d ragdoll remains finite and bounded"%id)
		check(contained,"variant %d physical fall collides with the wall instead of passing through"%id)
		rag.stop()
		player.survival.dead = false
		check(player.character_variant_id==id and presentation.get_parent()==player,"variant %d survives ragdoll reset without replacement"%id)
		player.queue_free()
		await ticks(3)
	print("CHARACTER CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
