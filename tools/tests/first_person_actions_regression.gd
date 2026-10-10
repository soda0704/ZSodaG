extends SceneTree
## Owner input, gameplay shot rays and native presentation on both actual rigs.
class Target extends StaticBody3D:
	var damage:=0.0
	func apply_weapon_damage(amount: float): damage+=amount
var failures:=0
var checks:=0
var actor: GamePlayer
var target: Target
var final_poses: Array[Transform3D]=[]
const OUT:="res://tools/.local/scenery-review/first-person-actions/"
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func ticks(count: int):
	for i in count: await physics_frame
func record_pose(rig: Skeleton3D):
	final_poses.clear()
	for bone in rig.get_bone_count(): final_poses.append(rig.get_bone_global_pose(bone))
func capture(label: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+label+".png")
func input_action(action: StringName):
	var event:=InputEventAction.new(); event.action=action; event.pressed=true; Input.parse_input_event(event)
	await physics_frame
	event=InputEventAction.new(); event.action=action; event.pressed=false; Input.parse_input_event(event)
func run():
	if DisplayServer.get_name()=="headless": push_error("Run actions with a graphical renderer."); quit(1); return
	Engine.max_fps=60; root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_node("GameMenu").force_close_menu()
	var service:=root.get_node("SteamInput"); service.set_process(false); service.set_process_input(false); service.native_input_available=false
	var world=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate(); root.add_child(world)
	# Hit layer is queried by weapons, but is outside the movement capsule mask.
	target=Target.new(); target.collision_layer=16; target.collision_mask=0
	var collider:=CollisionShape3D.new(); collider.name="CollisionShape3D"; var shape:=BoxShape3D.new(); shape.size=Vector3(1.5,1.5,1.5); collider.shape=shape; target.add_child(collider); world.add_child(target)
	for id in [0,1]:
		actor=load("res://scenes/characters/player.tscn").instantiate(); actor.name="1"; actor.setup(1,"",Vector3(0,.1,0),Color.WHITE,0,id); world.get_node("Players").add_child(actor)
		actor.survival.set_physics_process(false)
		for action in InputMap.get_actions(): InputMap.action_erase_events(action)
		actor.camera.current=true; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var sk: Skeleton3D=actor.body_animator.first_person_model.get_node("Skeleton3D")
		sk.skeleton_updated.connect(record_pose.bind(sk))
		await ticks(30)
		var peak_lag:=0.0; var bounded:=true; var yaw_before:=actor._input_yaw
		for turn in [Vector2(1200,-800),Vector2(-1600,1600),Vector2(2000,-1700),Vector2(-1800,1000)]:
			var mouse:=InputEventMouseMotion.new(); mouse.position=Vector2(640,360); mouse.relative=turn; Input.parse_input_event(mouse)
			await ticks(3)
			var fp:=actor.body_animator.first_person
			peak_lag=maxf(peak_lag,fp.rotation.length()); bounded=bounded and fp.rotation.is_finite() and fp.rotation.length()<=deg_to_rad(2.01) and fp.position.length()<=.0251
		check(absf(angle_difference(yaw_before,actor._input_yaw))>.1 and peak_lag>.0005,"variant %d real fast mouse input produces independent viewmodel lag"%id)
		check(bounded,"variant %d fast mouse inertia stays finite and bounded"%id)
		await ticks(60)
		check(actor.body_animator.first_person.rotation.length()<.003,"variant %d fast-turn viewmodel settles"%id)
		actor._input_yaw=0; actor._input_pitch=0; await ticks(20)
		for kind in [&"pistol",&"m4a1"]:
			actor.apply_held_item_inventory(kind,{},false); actor.weapon.apply_state(kind,12 if kind==&"pistol" else 30,0)
			actor.weapon.pistol_ammo=24; actor.weapon.rifle_magazines.assign([30,30]); await ticks(30)
			for pitch in [0.0,1.48,-1.48]:
				actor._input_pitch=pitch; await ticks(15)
				Input.action_press("weapon_aim"); await ticks(18)
				check(actor._aiming and actor.body_animator.first_person._ads>.95,"variant %d %s ADS at pitch %.2f"%[id,kind,pitch])
				# Downward rays meet the floor before a distant target. Keep this
				# small target above the floor and outside the excluded player capsule.
				target.get_node("CollisionShape3D").shape.size=Vector3.ONE*.35
				target.global_position=actor.head.global_position-actor.head.global_basis.z*(.8 if pitch< -1.0 else 4.0); target.damage=0; await ticks(2)
				var before:=actor.weapon.rounds
				Input.action_press("weapon_attack"); await ticks(2); Input.action_release("weapon_attack"); await ticks(2)
				check(actor.weapon.rounds<before and target.damage>0,"variant %d %s actual input fires along head ray at pitch %.2f"%[id,kind,pitch])
				check(actor.body_animator.first_person.tree.get("parameters/Kick/active"),"variant %d %s shot triggers native recoil"%[id,kind])
				await capture("%d-%s-aim-%.2f"%[id,kind,pitch])
				Input.action_release("weapon_aim"); await ticks(18)
			actor._input_pitch=0; actor.weapon.rounds=1; await ticks(10)
			await input_action(&"replace_battery"); await ticks(6)
			check(actor.weapon.reload_left>0 and actor.body_animator.first_person.tree.get("parameters/Handling/active"),"variant %d %s reload input starts gameplay and native handling"%[id,kind])
			await ticks(32)
			var marker: Node3D=actor.body_animator.equipment_root().get_node(String(kind)+"/LeftHandGrip")
			var left:=sk.global_transform*final_poses[sk.find_bone("LeftHand")].origin
			check(left.distance_to(marker.global_position)>.06,"variant %d %s support hand releases grip to reload"%[id,kind])
			await capture("%d-%s-reload"%[id,kind]); await ticks(140)
			check(actor.weapon.rounds==int(WeaponController.CAPACITY[kind]) and actor.weapon.reload_left==0,"variant %d %s reload completes with ammo"%[id,kind])
			left=sk.global_transform*final_poses[sk.find_bone("LeftHand")].origin
			print("RETURN GRIP ",id," ",kind," error=",left.distance_to(marker.global_position)," target=",sk.to_local(marker.global_position)," shoulder=",final_poses[sk.find_bone("LeftArm")].origin)
			check(left.distance_to(marker.global_position)<.015,"variant %d %s native IK restores support contact"%[id,kind])
		actor.apply_held_item_inventory(&"flashlight",{"battery_charge":1.0},true); await ticks(30)
		var lamp: Node3D=actor.flashlight.get_node("Model")
		check(lamp.has_node("Grip") and lamp.to_global(lamp.get_node("Grip").position).distance_to(sk.to_global(final_poses[sk.find_bone("RightHand")].origin))<.001,"variant %d flashlight aligns physical model grip to wrist"%id)
		check((-actor.flashlight.beam.global_basis.z).dot(-lamp.global_basis.z)>.999,"variant %d flashlight beam follows actual lamp axis"%id)
		await capture("%d-flashlight"%id)
		var journal: QuestJournalUI=root.get_node("QuestJournal"); journal.open_journal(); await ticks(75)
		for side in ["Left","Right"]:
			var hand:=sk.to_global(final_poses[sk.find_bone(side+"Hand")].origin)
			var grip: Node3D=actor.body_animator.first_person_model.get_node("Journal/"+side+"Grip")
			check(hand.distance_to(grip.global_position)<.015,"variant %d journal %s wrist contacts book grip"%[id,side])
		await capture("%d-journal"%id); journal.close_journal(); await ticks(60)
		check(not journal.is_journal_open(),"variant %d journal stows through native transition"%id)
		actor.queue_free(); await process_frame
	print("FIRST PERSON ACTION CHECKS ",checks," FAILURES ",failures); quit(1 if failures else 0)
