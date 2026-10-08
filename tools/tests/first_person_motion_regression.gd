extends SceneTree
## First-person motion is checked through real player input and rendered poses.

const OUTPUT := "res://tools/.local/scenery-review/first-person-motion/"
var failures := 0
var checks := 0
var final_poses: Array[Transform3D] = []
var active_actor: GamePlayer
var motion_frame := -1
var jump_sent := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func release_input() -> void:
	for action in ["move_forward","move_backward","move_right","sprint","crouch","weapon_attack","replace_battery"]:
		Input.action_release(action)

func record_final_pose(rig: Skeleton3D) -> void:
	# Modifiers run deferred; the ordinary pose getter later in the frame
	# returns the animation pose, not necessarily the pose sent to the skin.
	final_poses.clear()
	for i in rig.get_bone_count(): final_poses.append(rig.get_bone_global_pose(i))

func drive_input() -> void:
	release_input()
	if not is_instance_valid(active_actor): return
	root.get_node("GameMenu").force_close_menu()
	root.get_node("SteamInput").using_controller = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if motion_frame<0: return
	if motion_frame<110: Input.action_press("move_forward")
	if motion_frame>=50 and motion_frame<110: Input.action_press("sprint")
	if motion_frame>=110 and motion_frame<145: Input.action_press("move_backward")
	if motion_frame>=145 and motion_frame<180: Input.action_press("move_right")
	if motion_frame>=180 and motion_frame<210: Input.action_press("crouch")
	if motion_frame>=220 and not jump_sent:
		active_actor._jump_serial += 1
		jump_sent = true
	active_actor._input_pitch = 0.75 if motion_frame>=145 and motion_frame<180 else -0.75 if motion_frame>=180 and motion_frame<210 else 0.0

func camera_intrusions(actor: GamePlayer) -> int:
	# Evaluate the actually skinned view mesh, not its bind-pose AABB.
	# Sleeves may enter the lower third. Shoulders must not cross the central view.
	var view := actor.body_animator.first_person_model
	var rig: Skeleton3D = view.get_node("Skeleton3D")
	var mesh: MeshInstance3D = rig.get_node("Arms")
	var transforms: Array[Transform3D] = []
	for i in mesh.skin.get_bind_count():
		transforms.append(view.transform*final_poses[mesh.skin.get_bind_bone(i)]*mesh.skin.get_bind_pose(i))
	var offenders := 0
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var visited := {}
		for vertex in arrays[Mesh.ARRAY_INDEX]:
			if visited.has(vertex): continue
			visited[vertex] = true
			var point := Vector3.ZERO
			for slot in 4:
				var at: int = vertex*4+slot
				point += (transforms[arrays[Mesh.ARRAY_BONES][at]]*arrays[Mesh.ARRAY_VERTEX][vertex])*arrays[Mesh.ARRAY_WEIGHTS][at]
			if point.z>=-actor.camera.near: continue
			var pixel := actor.camera.unproject_position(actor.camera.global_transform*point)
			if pixel.x>root.size.x*0.06 and pixel.x<root.size.x*0.94 and pixel.y>=0 and pixel.y<root.size.y*0.65:
				offenders += 1
	return offenders

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Run this visual input regression with a graphical renderer.")
		quit(1)
		return
	Engine.max_fps = 120
	root.size = Vector2i(1280,720)
	root.position = Vector2i(2200,1300)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.get_node("GameMenu").force_close_menu()
	root.get_node("SteamInput").using_controller = false
	root.get_node("SteamInput").set_process(false)
	root.get_node("SteamInput").set_process_input(false)
	root.get_node("SteamInput").native_input_available = false
	# Synthetic actions remain available, but live mouse/joypad events must
	# not inject attacks, turns or sprint interruptions into a recorded run.
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	physics_frame.connect(drive_input)
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	await process_frame
	arena.get_node("Environment").environment.adjustment_enabled = false
	for id in [0,1]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.name = "1"
		actor.setup(1,"",Vector3(0,0.1,0),Color.WHITE,0,id)
		arena.get_node("Players").add_child(actor)
		InputMap.action_erase_events("weapon_attack")
		active_actor = actor
		actor.survival.set_physics_process(false)
		actor.set_process_unhandled_input(false)
		actor.camera.current = true
		var view_rig: Skeleton3D = actor.body_animator.first_person_model.get_node("Skeleton3D")
		view_rig.skeleton_updated.connect(record_final_pose.bind(view_rig))
		for i in 12: await physics_frame
		for kind in [&"m4a1",&"pistol",&"flashlight",&"kitchen_knife",&"fuse",&"fuel_can"]:
			motion_frame = -1
			jump_sent = false
			release_input()
			actor.apply_held_item_inventory(kind,{"battery_charge":1.0},kind==&"flashlight")
			actor.weapon.apply_state(kind,12,0)
			actor.global_position = Vector3(0,0.1,0)
			actor.reset_physics_interpolation()
			actor.velocity = Vector3.ZERO
			actor._sprint_remaining = actor.sprint_duration
			actor._sprint_exhausted = false
			actor._sprint_active = false
			for i in 35: await physics_frame
			var view := actor.body_animator.first_person_model
			var rig: Skeleton3D = view.get_node("Skeleton3D")
			var hand := rig.find_bone("RightHand")
			var initial := rig.get_bone_global_pose(hand).origin
			if kind==&"m4a1": check(initial.distance_to(Vector3(0.14,1.43,-0.27))<0.02,"variant %d rifle works as the first equipped item"%id)
			var peak_step := 0.0
			var max_excursion := 0.0
			var previous := initial
			var intrusion := 0
			var grip_error := 0.0
			var moving := false
			var ran := false
			var crouched := false
			var jumped := false
			for frame in 240:
				motion_frame = frame
				await physics_frame
				await RenderingServer.frame_post_draw
				var current := rig.get_bone_global_pose(hand).origin
				peak_step = maxf(peak_step,current.distance_to(previous))
				max_excursion = maxf(max_excursion,current.distance_to(initial))
				previous = current
				moving = moving or actor.velocity.length()>3.8
				ran = ran or actor.velocity.length()>6.5
				crouched = crouched or actor._is_crouching
				jumped = jumped or actor.velocity.y>2.0
				if frame in [49,85,130,170,199,230]:
					print("INPUT SAMPLE ",id," ",kind," frame=",frame," velocity=",actor.velocity," crouch=",actor._is_crouching," mouse=",Input.mouse_mode," held=",actor._held_item_type," journal=",actor._journal_phase)
					intrusion = maxi(intrusion,camera_intrusions(actor))
					root.get_texture().get_image().save_png(OUTPUT+"%d-%s-%d.png"%[id,kind,frame])
				if kind in [&"m4a1",&"pistol"]:
					var support: Node3D = actor.body_animator.equipment_root().get_node(String(kind)+"/SupportHand")
					var left := rig.global_transform*final_poses[rig.find_bone("LeftHand")].origin
					grip_error = maxf(grip_error,left.distance_to(support.global_position))
			print("VIEW METRICS ",id," ",kind," step=",peak_step," excursion=",max_excursion," intrusions=",intrusion," support_error=",grip_error)
			check(moving and ran and crouched and jumped,"variant %d %s actually walks, runs, crouches and jumps (%s/%s/%s/%s)"%[id,kind,moving,ran,crouched,jumped])
			check(peak_step<0.01 and max_excursion<0.01,"variant %d %s stays steady across movement transitions"%[id,kind])
			check(intrusion==0,"variant %d %s keeps shoulders out of central camera view"%[id,kind])
			if kind in [&"m4a1",&"pistol"]: check(grip_error<0.035,"variant %d %s support hand follows its moving weapon"%[id,kind])
		release_input()
		active_actor = null
		actor.queue_free()
		await process_frame
	print("FIRST PERSON CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
