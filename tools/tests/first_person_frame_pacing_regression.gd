extends SceneTree
## Sample final skin poses and item sockets on actual rendered frames.

var actor: GamePlayer
var elapsed := 0.0
var poses := {}
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func drive() -> void:
	if not is_instance_valid(actor): return
	elapsed += 1.0 / Engine.physics_ticks_per_second
	root.get_node("GameMenu").force_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for action in ["move_forward", "move_backward", "move_left", "move_right", "sprint", "weapon_aim"]: Input.action_release(action)
	if elapsed > 1.0: Input.action_press("move_forward")
	if elapsed > 2.0: Input.action_press("sprint")
	actor._input_yaw = maxf(elapsed - 3.0, 0.0) * 0.4

func capture(rig: Skeleton3D) -> void:
	for name in ["RightHand", "LeftHand", "LeftForeArm", "RightForeArm"]:
		var bone := rig.find_bone(name)
		if bone >= 0: poses[name] = rig.get_bone_global_pose(bone).origin

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This regression requires a graphical renderer."); quit(1); return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	root.position = Vector2i(2200, 1300)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.get_node("SteamInput").set_process(false)
	root.get_node("SteamInput").set_process_input(false)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	physics_frame.connect(drive)
	var arena: Node3D = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	var output := "res://tools/.local/first-person-frame-pacing/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for variant in [0, 1]:
		actor = load("res://scenes/characters/player.tscn").instantiate()
		actor.name = "1"
		actor.setup(1, "", Vector3(0, 0.1, 0), Color.WHITE, 0, variant)
		arena.get_node("Players").add_child(actor)
		actor.set_process_unhandled_input(false)
		actor.survival.set_physics_process(false)
		actor.camera.make_current()
		var fp := actor.body_animator.first_person
		var rig: Skeleton3D = fp.model.get_node("Skeleton3D")
		rig.skeleton_updated.connect(capture.bind(rig))
		for item in [&"pistol", &"fuel_can"]:
			for fps in [20, 30, 60, 144, 0]:
				Engine.max_fps = fps if fps > 0 else 144
				var pace_label := "%d FPS" % fps if fps > 0 else "mixed FPS"
				elapsed = 0.0
				actor.global_position = Vector3(0, 0.1, 0)
				actor.velocity = Vector3.ZERO
				actor._input_yaw = 0.0
				actor._sprint_remaining = actor.sprint_duration
				actor._sprint_exhausted = false
				actor.reset_physics_interpolation()
				actor.apply_held_item_inventory(item, {})
				actor.weapon.apply_state(item, 12, 0)
				var previous := {}
				var largest_step := {}
				var socket_error := 0.0
				var render_gap := 0.0
				var frames := 0
				var moved := false
				var ran := false
				var captured := false
				var file := FileAccess.open(output + "%d-%s-%d.csv" % [variant, item, fps], FileAccess.WRITE)
				file.store_line("time,frame_delta,right_x,right_y,right_z,socket_error")
				while elapsed < 4.2:
					await RenderingServer.frame_post_draw
					if elapsed < 1.1: continue
					if elapsed > 3.6 and not captured:
						root.get_texture().get_image().save_png(output + "%d-%s-%d.png" % [variant, item, fps])
						captured = true
					frames += 1
					if fps == 0:
						Engine.max_fps = [20, 144, 30, 60][frames % 4]
					moved = moved or actor.velocity.length() > 3.5
					ran = ran or actor.velocity.length() > 6.0
					var camera_inverse := fp.view_camera.get_global_transform_interpolated().affine_inverse()
					var skin_transform := rig.get_global_transform_interpolated()
					render_gap = maxf(render_gap, skin_transform.origin.distance_to(rig.global_position))
					for name in poses:
						var point: Vector3 = camera_inverse * skin_transform * poses[name]
						if previous.has(name): largest_step[name] = maxf(float(largest_step.get(name, 0.0)), point.distance_to(previous[name]))
						previous[name] = point
					var hand: Vector3 = poses.get("RightHand", Vector3.ZERO)
					var attachment: Node3D = rig.get_node("RightHand")
					socket_error = maxf(socket_error, (skin_transform * hand).distance_to(attachment.get_global_transform_interpolated().origin))
					var right: Vector3 = previous.get("RightHand", Vector3.ZERO)
					file.store_line("%f,%f,%f,%f,%f,%f" % [elapsed, actor.get_process_delta_time(), right.x, right.y, right.z, socket_error])
				file.close()
				print("FRAME METRICS variant=", variant, " item=", item, " pacing=", pace_label, " frames=", frames, " steps=", largest_step, " socket_error=", socket_error, " render_gap=", render_gap)
				check(moved and ran, "variant %d %s %s actually walks and runs" % [variant, item, pace_label])
				check(float(largest_step.get("RightHand", 999)) < 0.006 and float(largest_step.get("LeftHand", 999)) < 0.006, "variant %d %s %s hands remain continuous in view-camera space" % [variant, item, pace_label])
				check(render_gap < 0.002, "variant %d %s %s rendered rig uses the same frame as view camera" % [variant, item, pace_label])
				check(socket_error < 0.01, "variant %d %s %s item socket follows final hand pose" % [variant, item, pace_label])
		actor.queue_free()
		actor = null
		await process_frame
	print("CHECKS ", checks, " RESULT FAILURES ", failures)
	quit(1 if failures else 0)
