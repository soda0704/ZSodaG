extends SceneTree
## Fit metrics in rest space plus rendered production poses from every side.

const OUT := "res://tools/.local/accessory-fit/"
var failures := 0
var checks := 0
var final_poses: Array[Transform3D] = []


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)


func bounds(vertices: PackedVector3Array) -> AABB:
	var result := AABB(vertices[0], Vector3.ZERO)
	for vertex in vertices: result = result.expand(vertex)
	return result


func record_pose(rig: Skeleton3D) -> void:
	final_poses.clear()
	for bone in rig.get_bone_count(): final_poses.append(rig.get_bone_global_pose(bone))


func skin_point(body: MeshInstance3D, arrays: Array, vertex: int) -> Vector3:
	var result := Vector3.ZERO
	for slot in 4:
		var at := vertex * 4 + slot
		var bone: int = arrays[Mesh.ARRAY_BONES][at]
		result += final_poses[bone] * body.skin.get_bind_pose(bone) * arrays[Mesh.ARRAY_VERTEX][vertex] * arrays[Mesh.ARRAY_WEIGHTS][at]
	return result


func run() -> void:
	Engine.max_fps = 60
	root.get_node("GameMenu").force_close_menu()
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1200, 1000))
		root.size = Vector2i(1200, 1000)
	root.set_meta("ui_presentation", true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var world = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(world)
	world.get_node("Environment").environment.ambient_light_energy = 1.1
	var camera: Camera3D = world.get_node("ReviewCamera")
	camera.fov = 40.0
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 1.8, -1)
	fill.light_energy = 1.0
	fill.omni_range = 5.0
	world.add_child(fill)
	for variant in [0, 1]:
		var player: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		player.setup(1, "", Vector3.ZERO, Color.WHITE, 0, variant)
		world.get_node("Players").add_child(player)
		player.set_physics_process(false)
		player.survival.set_physics_process(false)
		player.weapon.set_physics_process(false)
		player.get_node("PlayerRagdoll").set_physics_process(false)
		player.body_animator.set_external_view(true)
		camera.make_current()
		var rig: Skeleton3D = player.body_animator.skeleton
		var body: MeshInstance3D = rig.get_node("Body")
		rig.skeleton_updated.connect(record_pose.bind(rig))
		var surfaces := {}
		var materials := {}
		var head_vertices := PackedVector3Array()
		for surface in body.mesh.get_surface_count():
			var arrays := body.mesh.surface_get_arrays(surface)
			var label := body.mesh.surface_get_material(surface).resource_name
			surfaces[label] = arrays
			materials[label] = body.mesh.surface_get_material(surface)
			if label in ["Head", "Mil_Suit_R5_Head"]:
				for vertex in arrays[Mesh.ARRAY_VERTEX]:
					if vertex.y > 1.60: head_vertices.append(vertex)
		var head_bounds := bounds(head_vertices)
		var cap: Array = surfaces["material" if variant == 0 else "GreenCap"]
		var headphones: Array = surfaces["Headphones" if variant == 0 else "HeadphonesT"]
		var cap_bounds := bounds(cap[Mesh.ARRAY_VERTEX])
		var headphone_bounds := bounds(headphones[Mesh.ARRAY_VERTEX])
		check(cap_bounds.size.y > 0.07 and cap_bounds.size.y < 0.20, "variant %d cap has a full crown rather than flattened brim" % variant)
		check(cap_bounds.end.y - head_bounds.end.y > -0.02 and cap_bounds.end.y - head_bounds.end.y < 0.035, "variant %d crown sits on the scalp without hovering" % variant)
		check(cap_bounds.size.x / head_bounds.size.x > 0.75 and cap_bounds.size.x / head_bounds.size.x < 1.25, "variant %d cap width fits head proportions" % variant)
		check(headphone_bounds.size.x < head_bounds.size.x * 1.4, "variant %d earcups are fitted to head width" % variant)
		for side in [-1, 1]:
			var nearest := INF
			for cup: Vector3 in headphones[Mesh.ARRAY_VERTEX]:
				if cup.x * side < 0.055 or cup.y > 1.72 or cup.z < -0.065: continue
				for vertex in head_vertices: nearest = minf(nearest, cup.distance_to(vertex))
			print("EAR CONTACT ", variant, " side ", side, " distance ", nearest)
			check(nearest < 0.018, "variant %d side %d ear padding touches the covered head" % [variant, side])
		if variant == 0:
			var plate_bounds := bounds(surfaces["plate"][Mesh.ARRAY_VERTEX])
			var shoulder_bounds := bounds(surfaces["ShoulderPads"][Mesh.ARRAY_VERTEX])
			check(plate_bounds.end.y < shoulder_bounds.end.y + 0.025, "Tactical vest straps follow shoulders instead of floating beside the neck")
			var lens: StandardMaterial3D = materials["Material.001"]
			check(lens.albedo_color.r > lens.albedo_color.g * 3.0, "Tactical original red lenses are retained")
		var accessories := [cap, headphones]
		if variant == 0: accessories.append(surfaces["Material.001"])
		if variant == 1: accessories.append(surfaces["Mil_Suit_R5_Eyes"])
		var head := rig.find_bone("Head")
		for state in ["idle", "turn", "up", "down", "walk", "run", "crouch"]:
			var context := {"grounded": true, "velocity": Vector3(0, 0, -4) if state == "walk" else Vector3(0, 0, -6.8) if state == "run" else Vector3.ZERO, "sprinting": state == "run", "crouching": state == "crouch", "pitch": 1.2 if state == "up" else -1.2 if state == "down" else 0.0, "yaw": 0.9 if state == "turn" else 0.0, "held_item": &""}
			for i in 60:
				player.body_animator.update_context(1.0 / 60, context)
				await process_frame
			var max_drift := 0.0
			var reference := final_poses[head].affine_inverse()
			for arrays: Array in accessories:
				for vertex in range(0, arrays[Mesh.ARRAY_VERTEX].size(), 17):
					var expected: Vector3 = body.skin.get_bind_pose(head) * arrays[Mesh.ARRAY_VERTEX][vertex]
					max_drift = maxf(max_drift, (reference * skin_point(body, arrays, vertex)).distance_to(expected))
			check(max_drift < 0.001, "variant %d %s accessories remain attached under final animated head pose" % [variant, state])
			if DisplayServer.get_name() != "headless":
				var target: Vector3 = rig.to_global(final_poses[head] * body.skin.get_bind_pose(head) * head_bounds.get_center())
				for view in ["front", "side", "back"]:
					camera.position = target + (Vector3(0, 0, -0.85) if view == "front" else Vector3(0.85, 0, 0) if view == "side" else Vector3(0, 0, 0.85))
					camera.look_at(target)
					for i in 3: await process_frame
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(OUT + "%d-%s-%s.png" % [variant, state, view])
				if state in ["idle", "crouch", "run"]:
					for view in ["torso-front", "torso-back"]:
						var torso: Vector3 = rig.to_global(final_poses[rig.find_bone("Spine1")].origin)
						camera.position = torso + Vector3(0.6, 0.1, -1.55 if view == "torso-front" else 1.55)
						camera.look_at(torso)
						for i in 3: await process_frame
						await RenderingServer.frame_post_draw
						root.get_texture().get_image().save_png(OUT + "%d-%s-%s.png" % [variant, state, view])
		player.queue_free()
		await process_frame
	print("ACCESSORY FIT CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
