extends SceneTree
## Source completeness, original eyes and sole contact under production blending.

const OUT := "res://tools/.local/model-integrity/"
var failures := 0
var checks := 0
var poses: Array[Transform3D] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func capture(rig: Skeleton3D) -> void:
	poses.clear()
	for bone in rig.get_bone_count(): poses.append(rig.get_bone_global_pose(bone))

func skin_point(body: MeshInstance3D, arrays: Array, vertex: int) -> Vector3:
	var point := Vector3.ZERO
	for slot in 4:
		var at := vertex * 4 + slot
		var bone: int = arrays[Mesh.ARRAY_BONES][at]
		point += poses[bone] * body.skin.get_bind_pose(bone) * arrays[Mesh.ARRAY_VERTEX][vertex] * arrays[Mesh.ARRAY_WEIGHTS][at]
	return body.get_parent().to_global(point)

func sole_heights(body: MeshInstance3D, soles: Array) -> Vector2:
	var low := Vector2(INF, INF)
	for sample in soles:
		var point := skin_point(body, sample.arrays, sample.vertex)
		low[sample.side] = minf(low[sample.side], point.y)
	return low

func snapshot(camera: Camera3D, target: Vector3, offset: Vector3, filename: String) -> void:
	if DisplayServer.get_name() == "headless": return
	camera.position = target + offset
	camera.look_at(target)
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + filename + ".png")

func run() -> void:
	Engine.max_fps = 60
	root.get_node("GameMenu").force_close_menu()
	root.set_meta("ui_presentation", true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1200, 1000)); root.size = Vector2i(1200, 1000)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(world)
	var camera: Camera3D = world.get_node("ReviewCamera"); camera.fov = 35
	var sources := {}
	for id in ["a", "b"]:
		var instance = load("res://assets/characters/tactical_%s/scene.gltf" % id).instantiate()
		sources[id] = instance.find_children("*", "MeshInstance3D", true, false)
	for variant in [0, 1]:
		var id := "a" if variant == 0 else "b"
		var player: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		player.setup(1, "Model integrity", Vector3(0, 0.1, 0), Color.WHITE, 0, variant)
		world.get_node("Players").add_child(player)
		for frame in 25: await physics_frame
		player.set_physics_process(false); player.survival.set_physics_process(false); player.weapon.set_physics_process(false)
		player.get_node("PlayerRagdoll").set_physics_process(false)
		player.body_animator.set_external_view(true); camera.make_current()
		var rig := player.body_animator.skeleton
		var body: MeshInstance3D = rig.get_node("Body")
		rig.skeleton_updated.connect(capture.bind(rig))
		var expected_vertices := 0
		var expected_indices := 0
		var source_parts: Array = sources[id].duplicate()
		if variant == 0:
			source_parts = source_parts.filter(func(mesh): return mesh.get_active_material(0).resource_name != "gloves")
			source_parts.append(sources.b.filter(func(mesh): return mesh.name == &"Object_115")[0])
		for mesh: MeshInstance3D in source_parts:
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				expected_vertices += arrays[Mesh.ARRAY_VERTEX].size()
				expected_indices += arrays[Mesh.ARRAY_INDEX].size()
		var actual_vertices := 0
		var actual_indices := 0
		var soles := []
		var eyes: Array = []
		var knee_shells: Array = []
		for surface in body.mesh.get_surface_count():
			var arrays := body.mesh.surface_get_arrays(surface)
			actual_vertices += arrays[Mesh.ARRAY_VERTEX].size(); actual_indices += arrays[Mesh.ARRAY_INDEX].size()
			for vertex in arrays[Mesh.ARRAY_VERTEX].size():
				var point: Vector3 = arrays[Mesh.ARRAY_VERTEX][vertex]
				if point.y < 0.08: soles.append({"arrays": arrays, "vertex": vertex, "side": 0 if point.x < 0 else 1})
			if body.mesh.surface_get_material(surface).resource_name == "Mil_Suit_R5_Eyes": eyes = arrays
			if body.mesh.surface_get_material(surface).resource_path.ends_with("Object_101_0.tres"): knee_shells = arrays
		check(actual_vertices == expected_vertices and actual_indices == expected_indices, "variant %d retains every source mesh including rigid parts (with the documented glove transfer)" % variant)
		if variant == 1:
			var original: MeshInstance3D = sources.b.filter(func(mesh): return mesh.skin == null)[0]
			check(not eyes.is_empty(), "Military retains its original separate eyes")
			if not eyes.is_empty():
				var source_arrays := original.mesh.surface_get_arrays(0)
				check(eyes[Mesh.ARRAY_TEX_UV] == source_arrays[Mesh.ARRAY_TEX_UV] and eyes[Mesh.ARRAY_INDEX] == source_arrays[Mesh.ARRAY_INDEX], "Military eye UVs and triangles are unchanged from the archive model")
				var eye_bounds := AABB(eyes[Mesh.ARRAY_VERTEX][0], Vector3.ZERO)
				for point in eyes[Mesh.ARRAY_VERTEX]: eye_bounds = eye_bounds.expand(point)
				var face: Array = body.mesh.surface_get_arrays(0)
				var face_bounds := AABB(face[Mesh.ARRAY_VERTEX][0], Vector3.ZERO)
				for point in face[Mesh.ARRAY_VERTEX]: face_bounds = face_bounds.expand(point)
				print("EYE REST ", eye_bounds, " FACE REST ", face_bounds)
				check(eye_bounds.get_center().distance_to(face_bounds.get_center()) < 0.025, "Military eyeballs sit inside their original eye sockets")
		for state in ["idle", "crouch", "walk", "run", "backward", "strafe", "crouch_walk", "journal"]:
			var velocity := Vector3.ZERO
			if state in ["walk", "run", "crouch_walk"]: velocity.z = -6.8 if state == "run" else -2.2 if state == "crouch_walk" else -4.0
			if state == "backward": velocity.z = 4.0
			if state == "strafe": velocity.x = 4.0
			var context := {"grounded": true, "crouching": state in ["crouch", "crouch_walk"], "velocity": velocity, "sprinting": state == "run", "pitch": 0.0, "yaw": 0.0, "held_item": &"", "journal_phase": 2 if state == "journal" else 0}
			for frame in 80:
				player.body_animator.update_context(1.0/60, context); await process_frame
			var worst := 0.0
			var penetration := 0.0
			var airborne_samples := 0
			var shell_deformation := 0.0
			for frame in 70:
				player.body_animator.update_context(1.0/60, context); await process_frame
				var low := sole_heights(body, soles)
				var support := low.min_axis_index()
				worst = maxf(worst, low[support]); penetration = minf(penetration, low[support])
				if low.max_axis_index() != support and low[low.max_axis_index()] - low[support] > 0.025: airborne_samples += 1
				if not knee_shells.is_empty():
					var points: PackedVector3Array = knee_shells[Mesh.ARRAY_VERTEX]
					var anchors := [-1, -1]
					for vertex in range(0, points.size(), 53):
						var side := 0 if points[vertex].x < 0 else 1
						if anchors[side] < 0: anchors[side] = vertex
						var anchor: int = anchors[side]
						var distance := skin_point(body, knee_shells, vertex).distance_to(skin_point(body, knee_shells, anchor))
						shell_deformation = maxf(shell_deformation, absf(distance - points[vertex].distance_to(points[anchor])))
			print("SOLE ", variant, " ", state, " support range ", penetration, "..", worst)
			check(worst < 0.015 and penetration > -0.015, "variant %d %s support sole stays on the physical floor across the animation cycle" % [variant, state])
			if variant == 1: check(shell_deformation < 0.001, "Military %s knee shells retain their original rigid shape" % state)
			if state in ["idle", "crouch", "journal"]:
				check(sole_heights(body, soles).abs().x < 0.01 and sole_heights(body, soles).abs().y < 0.01, "variant %d %s plants both feet" % [variant, state])
			if state in ["walk", "run", "crouch_walk"]: check(airborne_samples > 0, "variant %d %s preserves the swing foot" % [variant, state])
			await snapshot(camera, Vector3(0, 0.13, 0), Vector3(0.65, 0.20, -0.85), "%d-%s-feet" % [variant, state])
			if state in ["idle", "crouch"]: await snapshot(camera, Vector3(0, 0.85, 0), Vector3(0.65, 0.10, -3.2), "%d-%s-full" % [variant, state])
			if variant == 1 and state == "idle":
				var head := rig.find_bone("Head")
				await snapshot(camera, rig.to_global(poses[head].origin) + Vector3(0, 0.1, -0.025), Vector3(0, 0, -0.65), "military-eyes")
		var air := {"grounded": false, "velocity": Vector3(0, 4, 0), "crouching": false, "pitch": 0.0, "yaw": 0.0, "held_item": &"", "journal_phase": 0}
		for frame in 40: player.body_animator.update_context(1.0/60, air); await process_frame
		check(player.body_animator.model.position.y == 0.0 and sole_heights(body, soles).x > 0.10 and sole_heights(body, soles).y > 0.10, "variant %d airborne pose is free of floor snapping" % variant)
		world.get_node("Floor").position.y = 0.5
		player.global_position.y = 0.64
		await physics_frame
		var stand := {"grounded": true, "velocity": Vector3.ZERO, "crouching": false, "pitch": 0.0, "yaw": 0.0, "held_item": &"", "journal_phase": 0}
		for frame in 80: player.body_animator.update_context(1.0/60, stand); await process_frame
		var elevated := sole_heights(body, soles) - Vector2.ONE * 0.6
		check(absf(elevated.x) < 0.01 and absf(elevated.y) < 0.01, "variant %d floor compensation follows an elevated physical surface" % variant)
		world.get_node("Floor").position.y = -0.1
		player.queue_free(); await process_frame
	for meshes in sources.values():
		if not meshes.is_empty():
			var instance: Node = meshes[0]
			while instance.get_parent() != null: instance = instance.get_parent()
			instance.free()
	print("MODEL INTEGRITY CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
