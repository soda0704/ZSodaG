extends SceneTree
## Stationary support across complete idle loops and the live production tree.

const BONES := ["Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
const OUT := "res://tools/.local/idle-stability/"
var poses: Array[Transform3D] = []
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func record(rig: Skeleton3D) -> void:
	poses.clear()
	for bone in rig.get_bone_count(): poses.append(rig.get_bone_global_pose(bone))

func sample(rig: Skeleton3D, ranges: Dictionary) -> void:
	for name in BONES:
		var point: Vector3 = poses[rig.find_bone(name)].origin
		if not ranges.has(name): ranges[name] = AABB(point, Vector3.ZERO)
		else: ranges[name] = ranges[name].expand(point)

func verify(ranges: Dictionary, label: String) -> void:
	for name in BONES:
		var extent: Vector3 = ranges[name].size
		print("IDLE RANGE ", label, " ", name, " ", extent)
		check(extent.length() < 0.001, "%s %s stays within 1 mm through two complete idle cycles" % [label, name])

func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	root.set_meta("ui_presentation", true)
	Engine.max_fps = 60
	var graphical := DisplayServer.get_name() != "headless"
	if graphical:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1000, 900)); root.size = Vector2i(1000, 900)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(world)
	var camera: Camera3D = world.get_node("ReviewCamera")
	camera.fov = 35
	camera.position = Vector3(0.55, 0.95, -3.2); camera.look_at(Vector3(0, 0.85, 0))
	for variant in [0, 1]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(1, "Idle stability", Vector3(0, 0.1, 0), Color.WHITE, 0, variant)
		world.get_node("Players").add_child(actor)
		for frame in 25: await physics_frame
		actor.set_physics_process(false); actor.survival.set_physics_process(false); actor.weapon.set_physics_process(false)
		actor.get_node("PlayerRagdoll").set_physics_process(false)
		actor.body_animator.set_external_view(true); camera.make_current()
		var rig := actor.body_animator.skeleton
		rig.skeleton_updated.connect(record.bind(rig))
		var context := {"velocity": Vector3.ZERO, "grounded": true, "crouching": false, "yaw": 0.0, "pitch": 0.0, "held_item": &""}
		for kind in [&"", &"pistol", &"m4a1"]:
			context.held_item = kind
			for frame in 80:
				actor.body_animator.update_context(1.0/60, context); await process_frame
			var ranges := {}
			var chest_range := AABB(poses[rig.find_bone("Spine2")].origin, Vector3.ZERO)
			for frame in 360:
				actor.body_animator.update_context(1.0/60, context); await process_frame
				sample(rig, ranges)
				chest_range = chest_range.expand(poses[rig.find_bone("Spine2")].origin)
				if graphical and kind == &"" and frame % 2 == 0:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUT + "%d-%03d.png" % [variant, frame/2])
			verify(ranges, "variant %d %s" % [variant, "empty" if kind == &"" else String(kind)])
			if kind == &"": check(chest_range.size.length() > 0.0001 and chest_range.size.length() < 0.01, "variant %d retains subtle upper-body breathing" % variant)
		context.held_item = &""; context.velocity = Vector3(0, 0, -4)
		for frame in 80: actor.body_animator.update_context(1.0/60, context); await process_frame
		context.velocity = Vector3.ZERO
		for frame in 80: actor.body_animator.update_context(1.0/60, context); await process_frame
		var stopped_ranges := {}
		for frame in 360:
			actor.body_animator.update_context(1.0/60, context); await process_frame
			sample(rig, stopped_ranges)
		verify(stopped_ranges, "variant %d stopped after walking" % variant)
		# The selector uses the same saved clip directly, without the gameplay tree.
		var model = actor.body_animator.variant.body_scene.instantiate(); world.add_child(model)
		var preview_rig: Skeleton3D = model.get_node("Skeleton3D")
		for modifier in preview_rig.get_children():
			if modifier is SkeletonModifier3D: modifier.active = false
		var animation: AnimationPlayer = model.get_node("AnimationPlayer")
		animation.play("Idle"); animation.pause()
		var ranges := {}
		for frame in 181:
			animation.seek(fposmod(float(frame)/30.0, 3.0), true); animation.advance(0)
			preview_rig.force_update_all_bone_transforms(); record(preview_rig); sample(preview_rig, ranges)
		verify(ranges, "variant %d selector preview" % variant)
		model.queue_free(); actor.queue_free(); await process_frame
	print("IDLE STABILITY CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
