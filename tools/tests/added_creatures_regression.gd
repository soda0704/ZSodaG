extends SceneTree
## Runtime asset integration, real console aliases, skeletal locomotion and environmental deaths.
var failures := 0
var checks := 0


func _initialize() -> void:
	var isolated := "user://added_creatures_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated))
	ProjectSettings.set_setting(
		BaseGameplayController.TEST_SAVE_PATH_SETTING, isolated + "/campaign.cfg"
	)
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, isolated + "/slots")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", isolated + "/settings.json")
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)


func frames(count := 6) -> void:
	for i in count:
		await process_frame


func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await frames(12)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false
	state.set_process(false)
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 30.0
	state._broadcast_snapshot(snapshot)
	root.get_node("GameMenu").force_close_menu()
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.teleport_authoritative(Vector3(16.5, .1, 5.5), PI)
	var review_camera := Camera3D.new()
	base.add_child(review_camera)
	review_camera.global_position = Vector3(16.5, 1.65, 5.5)
	review_camera.look_at(Vector3(16.5, 1.05, 0))
	review_camera.make_current()
	var console = root.get_node("DeveloperConsole")
	var encounter = base.get_node("ContainmentEncounter")
	for old in get_nodes_in_group("hostile_monsters"):
		old.set_physics_process(false)
	for prop in base.find_children("*", "RigidBody3D", true, false):
		if prop is HeavyCarryProp:
			prop.visible = false
			prop.freeze = true
	var actors: Array = []
	for index in 2:
		var kind := "head" if index == 0 else "involuntary_evolution"
		var command := "head" if index == 0 else "evolution"
		var point := Vector3(15.0 if index == 0 else 18.0, .15, 0)
		var result: String = console._execute_authoritative(
			PackedStringArray(["/spawn", command]), state, player.owner_peer_id, NodePath(), point
		)
		check(result.contains("1"), "console /spawn " + command + " creates one creature")
		var found = null
		for candidate in get_nodes_in_group("debug_spawned_monsters"):
			if candidate.model_id == kind:
				found = candidate
		check(found != null, "supplied model integrated with existing debug spawn: " + kind)
		if found == null:
			continue
		found.set_physics_process(false)
		found.rotation.y = PI
		found.global_position.y = 0.02
		found.set_home_transform(found.global_transform)
		actors.append(found)
		var visual: MonsterVisual = found.visual
		check(
			visual.skeleton != null and visual.skeleton.get_bone_count() >= 10,
			"deforming rig exists: " + kind
		)
		if visual.animator == null:
			continue
		check(
			(
				visual.animator.has_animation(visual.idle_animation)
				and visual.animator.has_animation(visual.walk_animation)
				and visual.animator.has_animation(visual.attack_animation)
			),
			"all Inspector animation references resolve: " + kind
		)
		check(
			visual.animator.get_animation(visual.walk_animation).loop_mode != Animation.LOOP_NONE,
			"locomotion is a native looping clip: " + kind
		)
		check(
			not visual.prototype_motion and not visual.use_animation_reel,
			"locomotion uses authored bones, no whole-object bob or legacy reel: " + kind
		)
		var before := visual.skeleton.get_bone_pose_rotation(visual.skeleton.find_bone("body"))
		visual.animate(
			.016, true, false, false, found.ai_profile.attack_windup, found.ai_profile.chase_speed
		)
		await frames(5)
		var after := visual.skeleton.get_bone_pose_rotation(visual.skeleton.find_bone("body"))
		check(
			not before.is_equal_approx(after),
			"native animation actually advances skeleton: " + kind
		)
		check(
			is_equal_approx(
				visual.animator.speed_scale,
				found.ai_profile.chase_speed / visual.walk_reference_speed
			),
			"gait playback follows physical movement speed: " + kind
		)
	check(
		(
			actors.size() == 2
			and actors[0].ai_profile.chase_speed > 5.0
			and actors[0].ai_profile.chase_speed > actors[1].ai_profile.chase_speed
		),
		"head is distinctly faster than the larger creature"
	)
	if DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args():
		var output := "res://tools/.local/monster_ai/runtime"
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--output="):
				output = argument.trim_prefix("--output=")
		DirAccess.make_dir_recursive_absolute(output)
		for actor in actors:
			actor.visual.animator.speed_scale = 0.0
		for frame in 24:
			for actor in actors:
				var animator: AnimationPlayer = actor.visual.animator
				var length := animator.get_animation(actor.visual.walk_animation).length
				animator.seek(
					fmod(
						(
							float(frame)
							/ 50.0
							* actor.ai_profile.chase_speed
							/ actor.visual.walk_reference_speed
						),
						length
					),
					true
				)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("walk_%02d.png" % frame))
	for actor in actors:
		actor.apply_environment_damage(10000.0)
		actor._physics_process(.01)
		check(
			actor.ragdoll != null and actor.ragdoll.initialized,
			"new model has working skeletal environmental death: " + actor.model_id
		)
		if actor.ragdoll != null:
			actor.ragdoll.freeze_all()
	check(
		(
			(
				console
				. _execute_authoritative(
					PackedStringArray(["/monsters", "status"]), state, player.owner_peer_id
				)
				. length()
			)
			> 0
		),
		"AI state diagnostics available in existing console"
	)
	encounter.debug_clear_spawned()
	base.queue_free()
	actors.clear()
	await frames(6)
	print("ADDED CREATURE CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
