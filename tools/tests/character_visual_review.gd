extends SceneTree

const OUTPUT := "res://tools/.local/scenery-review/character-visual/"
var arena: Node3D
var actors: Array[GamePlayer] = []

func _initialize() -> void: run.call_deferred()

func capture(label: String) -> void:
	for i in 5: await process_frame
	# Neutral review lighting does not alter the user's saved graphics settings.
	arena.get_node("Environment").environment.adjustment_enabled = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+label+".png")
	print("CAPTURE ",label)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280,900)
	root.get_node("GameMenu").force_close_menu()
	arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for id in [0,1]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.name = str(id+2)
		actor.setup(id+2,"",Vector3(-0.65 if id==0 else 0.65,0.02,0),Color.WHITE,0,id)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.weapon.set_physics_process(false)
		actor.get_node("PlayerRagdoll").set_physics_process(false)
		actor.name_label.hide()
		actor.body_animator.model.get_node("AnimationTree").active = false
		actors.append(actor)
	arena.get_node("ReviewCamera").current = true
	for name in ["Idle","WalkForward","RunForward","CrouchIdle","InAir","RifleAim0","PistolAim0","FlashlightAim0","KnifeAim0","FuseAim0","FuelAim0","Vehicle","Sleep","JournalReading"]:
		var review_camera: Camera3D = arena.get_node("ReviewCamera")
		review_camera.position = Vector3(0,2.5,-3.4) if name=="Sleep" else Vector3(0,1,-3.4)
		review_camera.look_at(Vector3(0,0.35,0) if name=="Sleep" else Vector3(0,1,0))
		var vehicles: Array[Node3D] = []
		if name=="Vehicle":
			for actor in actors:
				var vehicle: Node3D = load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
				vehicle.position = Vector3(-1.1 if actor.character_variant_id==0 else 1.1,0,0)
				arena.add_child(vehicle)
				vehicle.set_physics_process(false)
				vehicle.get_node("Status").hide()
				vehicles.append(vehicle)
				actor.global_position = vehicle.get_node("Seat").global_position
			review_camera.position = Vector3(3.8,2.3,-4.5)
			review_camera.look_at(Vector3(0,0.7,0))
		for actor in actors:
			var presentation := actor.body_animator
			for modifier in presentation.skeleton.get_children():
				if modifier is SkeletonModifier3D: modifier.active = false
			var player: AnimationPlayer = presentation.model.get_node("AnimationPlayer")
			player.play(name)
			player.seek(1.0 if name=="Idle" else player.get_animation(name).length*0.35,true)
			player.advance(0)
			player.pause()
			var equipment := presentation.equipment_root()
			for kind in WeaponController.TYPES: equipment.get_node(String(kind)).visible = (kind==&"m4a1" and name=="RifleAim0") or (kind==&"pistol" and name=="PistolAim0") or (kind==&"kitchen_knife" and name=="KnifeAim0")
			actor.flashlight.visible = name=="FlashlightAim0"
			actor.held_fuse.visible = name=="FuseAim0"
			actor.held_fuel_can.visible = name=="FuelAim0"
			equipment.get_node("Journal").visible = name=="JournalReading"
		await capture("tp-"+name)
		for vehicle in vehicles: vehicle.queue_free()
		for actor in actors: actor.position = Vector3(-0.65 if actor.character_variant_id==0 else 0.65,0.02,0)
	var review_camera: Camera3D = arena.get_node("ReviewCamera")
	review_camera.position = Vector3(0,3.4,-5.5)
	review_camera.look_at(Vector3(0,0.3,-0.5))
	for actor in actors:
		actor.flashlight.hide()
		actor.held_fuse.hide()
		actor.held_fuel_can.hide()
		actor.body_animator.model.get_node("AnimationPlayer").stop()
		actor.survival.death_velocity = Vector3(0,0,-2.5)
		actor.body_animator.begin_death()
		actor.body_animator.advance_death(0.14)
		actor.get_node("PlayerRagdoll").start()
	for i in 24: await physics_frame
	await capture("ragdoll-fall")
	for i in 96: await physics_frame
	await capture("ragdoll-floor")
	for actor in actors:
		actor.get_node("PlayerRagdoll").stop()
		actor.hide()
	for id in [0,1]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.name = "1"
		actor.setup(1,"",Vector3(0,0.02,0),Color.WHITE,0,id)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.get_node("PlayerRagdoll").set_physics_process(false)
		actor.camera.current = true
		for kind in [&"pistol",&"m4a1",&"flashlight",&"kitchen_knife",&"fuse",&"fuel_can"]:
			actor._held_item_type = kind
			actor.weapon.apply_state(kind,12,0)
			actor._has_flashlight = true
			actor._battery_charge = 1.0
			actor._flashlight_enabled = kind==&"flashlight"
			actor._refresh_equipment_visuals()
			for i in 40:
				actor.body_animator.update_context(1.0/60,{"velocity":Vector3.ZERO,"grounded":true,"held_item":kind,"yaw":0.0,"pitch":0.0})
				await process_frame
			await capture("fp-%d-%s"%[id,kind])
			if kind==&"m4a1":
				actor.weapon_light_mounted = true
				actor._flashlight_enabled = true
				actor.weapon._physics_process(0)
				await capture("fp-%d-mounted-flashlight"%id)
				actor.weapon_light_mounted = false
				actor._flashlight_enabled = false
			var sk: Skeleton3D = actor.body_animator.first_person_model.get_node("Skeleton3D")
			var equipment = actor.body_animator.equipment_root()
			print("GRIP ",id," ",kind," R=",sk.get_bone_global_pose(sk.find_bone("RightHand")).origin," L=",sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin)
			if kind==&"m4a1": print("SUPPORT WORLD ",equipment.get_node("m4a1/SupportHand").global_position," LEFT WORLD ",sk.global_transform*sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin)
		var journal: QuestJournalUI = root.get_node("QuestJournal")
		journal.open_journal()
		for time in [0.28,0.65,1.0,1.42,1.80]:
			journal._animation.pause()
			journal._animation.seek(time,true)
			journal._character_arms.get_node("AnimationPlayer").seek(time,true)
			await capture("journal-%d-%0.2f"%[id,time])
			var sk: Skeleton3D = journal._character_arms.get_node("Skeleton3D")
			print("JOURNAL HANDS ",id," ",time," ",sk.global_transform*sk.get_bone_global_pose(sk.find_bone("RightHand")).origin," ",sk.global_transform*sk.get_bone_global_pose(sk.find_bone("LeftHand")).origin)
		journal.force_close()
		actor.queue_free()
		await process_frame
	print("VISUAL REVIEW COMPLETE")
	quit()
