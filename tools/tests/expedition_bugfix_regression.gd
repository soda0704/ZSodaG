extends SceneTree
## Regression coverage for staged objectives, console, day jumps and shaft occlusion.
var checks := 0
var failures := 0
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://expedition_bugfix_%d.cfg" % OS.get_process_id())
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://expedition_bugfix_settings_%d.json" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle() -> void:
	for frame in 6: await physics_frame
func rock_view_blocked(space: PhysicsDirectSpaceState3D, ray: PhysicsRayQueryParameters3D) -> bool:
	if not space.intersect_ray(ray).is_empty(): return true
	# Exact rays through shared triangle edges can miss in the physics backend.
	# A 2 mm beam checks the same sightline without treating that precision limit as a hole.
	var beam := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new(); sphere.radius = 0.002
	beam.shape = sphere; beam.transform.origin = ray.from; beam.motion = ray.to - ray.from
	beam.collision_mask = ray.collision_mask; beam.exclude = ray.exclude
	return space.cast_motion(beam)[0] < 1.0
func run() -> void:
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await settle()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	root.get_node("GameMenu").force_close_menu()
	var lift: FunctionalElevatorController = base.get_node("Elevator_Functional_Blockout")
	var journal = root.get_node("QuestJournal")
	journal._bind_controller()
	state.debug_set_day_authoritative(5)
	check(not journal.tasks_label.text.contains("Зачистить") and not journal.tasks_label.text.contains("Восстановить питание"), "day five initially reveals only exploration")
	lift.restore_checkpoint_floor(4)
	player.teleport_authoritative(lift.cabin.global_position + Vector3(0, 0.1, 0), 0)
	await settle()
	check(not state.containment.get("level3", false), "arriving inside cabin does not reveal combat goal")
	player.teleport_authoritative(Vector3(-4.0, -71.9, 0), 0)
	await settle()
	check(state.containment.get("level3", false) and journal.tasks_label.text.contains("Зачистить уровень"), "stepping across landing reveals shared combat goal")
	check(not journal.tasks_label.text.contains("Восстановить питание"), "combat goal does not spoil future outage")
	var encounter = base.get_node("ContainmentEncounter")
	for index in 2: encounter.damage_monster(index, 10000)
	check(not journal.tasks_label.text.contains("Восстановить питание"), "two deaths cannot reveal outage objective")
	encounter.damage_monster(2, 10000)
	check(journal.tasks_label.text.contains("Восстановить питание"), "last death reveals restoration objective")
	state.debug_set_day_authoritative(6)
	check(journal.get_hud_summary().tasks.any(func(task): return "уровень 5" in task), "day six HUD directs player to floor five")
	state.debug_set_day_authoritative(7)
	check(journal.get_hud_summary().tasks.any(func(task): return "продолжение шахты" in task), "day seven HUD directs exploration beneath the complex")
	player.teleport_authoritative(base.get_node("Cave_Day7/CaveArrival").global_position, 0)
	await settle()
	check(state.containment.get("cave_visited", false) and not state.can_end_current_day(), "actual shaft visit starts exploration without completing day seven")
	var snapshot := state.get_snapshot()
	snapshot.day_index = 1; snapshot.plant_seed_planted = true; snapshot.plant_withered = false
	snapshot.plant_growth_stage = 0; snapshot.plant_last_watered_day = 1
	state._broadcast_snapshot(snapshot)
	var console = root.get_node("DeveloperConsole")
	console.execute("/day 2")
	check(state.plant_growth_stage == 1 and not state.plant_withered, "day command ages watered plant just like sleep")
	console.execute("/day 4")
	check(state.plant_growth_stage == 1 and state.plant_withered, "skipped unwatered days wither plant")
	check(state.load_saved_snapshot().plant_withered, "day command persists plant outcome")
	console.execute("/day 1")
	check(state.plant_last_watered_day == 0 and state.plant_withered, "rewind removes future watering and cannot revive dead plant")
	console.set_open(true)
	console.entry.text = "/plant"; console.entry.caret_column = 6
	console._refresh_suggestions()
	var suggestions: RichTextLabel = console.get_node("Panel/Box/Commands")
	check(suggestions.is_visible_in_tree() and suggestions.bbcode_enabled and "/plant water" in suggestions.text and "/weapon" not in suggestions.text, "visible clickable suggestions filter input")
	console.complete_command()
	check(console.entry.text.begins_with("/plant "), "Tab completes inspection command")
	suggestions.meta_clicked.emit("/status")
	check(console.entry.text == "/status", "clicking suggestion inserts its command")
	console._submit("/help"); console._submit("clear")
	check(console.output.text.is_empty() and console.history.is_empty() and not suggestions.text.is_empty(), "clear without slash clears output and history but preserves suggestions")
	console._submit("/where; /clear")
	check(console.output.text.is_empty(), "clear at end of batch also discards earlier batch output")
	console.set_open(false)
	lift.set_physics_process(false)
	lift.restore_checkpoint_floor(0)
	await settle()
	lift._begin_cabin_motion(-72.0, 4.0, 100)
	var passed: Array[String] = []
	for step in 81:
		lift._physics_process(0.05)
		if passed.is_empty() or passed[-1] != lift.cabin_floor_display.text: passed.append(lift.cabin_floor_display.text)
		await physics_frame
	check(passed == ["0", "1", "2", "3", "4"], "lift display follows actual travel through all intermediate floors: " + str(passed))
	lift._cabin_motion_active = false
	lift.set_day(7)
	lift.restore_checkpoint_floor(4)
	for index in range(1, 6):
		check(lift.get_node("Landings/Floor_%d/FloorLabel" % index).text == "УРОВЕНЬ %d" % index, "floor label has valid Cyrillic %d" % index)
	await settle()
	var guard = lift.get_node("Landings/Floor_0/SurfaceShaftGuard")
	var rock: StaticBody3D = lift.get_node("SurfaceRockLining")
	# Isolate the authored rock from CSG colliders, which are not CollisionObject3D nodes.
	const ROCK_MASK := 1 << 30
	rock.collision_layer = ROCK_MASK
	var space := lift.get_world_3d().direct_space_state
	var excluded: Array[RID] = []
	for body in base.find_children("*", "CollisionObject3D", true, false):
		if body != rock: excluded.append(body.get_rid())
	check(not guard.has_node("OpaqueSleeve"), "original surface grate has no opaque enclosure")
	check(lift.get_node("Landings/Floor_0/CallButton").position.is_equal_approx(Vector3(-3.46,1.35,-2.75)), "surface button restored to original position")
	var bounds: AABB = rock.get_node("Bedrock").mesh.get_aabb()
	check(bounds.end.y < 0 and bounds.size.y <= 10.01, "rock lining stays below ground and ends before floor one")
	var edge_counts := {}
	var faces: PackedVector3Array = rock.get_node("Bedrock").mesh.get_faces()
	for triangle_index in range(0, faces.size(), 3):
		for edge in 3:
			var a := faces[triangle_index + edge]
			var b := faces[triangle_index + (edge + 1) % 3]
			var key := str(a) + ":" + str(b) if str(a) < str(b) else str(b) + ":" + str(a)
			edge_counts[key] = int(edge_counts.get(key, 0)) + 1
	check(edge_counts.values().all(func(count): return count == 2), "rock mesh is closed and has no open corner or rim edges")
	# Only the actual rock shell counts as opaque, never the cage's mesh collider.
	for height in [0.2, 1.65, 2.5, 4.4, 6.0]:
		for angle_index in 24:
			var angle := angle_index * TAU / 24.0
			var radial := Vector3(cos(angle), 0, sin(angle))
			var query := PhysicsRayQueryParameters3D.create(radial * 7.0 + Vector3.UP * height, radial * -12.0 + Vector3.DOWN * 7.0, ROCK_MASK, excluded)
			check(rock_view_blocked(space, query), "rock blocks oblique lower-map view height %.2f angle %d" % [height, angle_index])
	for depth in [-0.2, -4.0, -9.9]:
		for angle_index in 32:
			var angle := angle_index * TAU / 32.0
			var query := PhysicsRayQueryParameters3D.create(Vector3(0,depth,0), Vector3(cos(angle)*12,depth,sin(angle)*12),ROCK_MASK,excluded)
			check(rock_view_blocked(space, query), "continuous rock wall depth %.2f angle %d" % [depth,angle_index])
	var axial := PhysicsRayQueryParameters3D.create(Vector3(0,7,0), Vector3(0,-12,0),ROCK_MASK,excluded)
	check(space.intersect_ray(axial).is_empty(), "shaft has an open top and no bottom cap")
	lift.restore_checkpoint_floor(0)
	await settle()
	for collider in lift.cabin.find_children("*", "CollisionShape3D", true, false):
		if collider.get_parent() is Area3D: continue
		var travel := PhysicsShapeQueryParameters3D.new()
		travel.shape = collider.shape; travel.transform = collider.global_transform
		travel.motion = Vector3(0,-18,0); travel.collision_mask = ROCK_MASK; travel.exclude = excluded

		check(space.intersect_shape(travel).is_empty() and space.cast_motion(travel)[0] == 1.0, "native cabin collider clears rock through full stroke: " + str(collider.name))
	rock.collision_layer = 1
	var landing_door = lift.get_node("Landings/Floor_0/LandingDoor")
	excluded.clear()
	for body in base.find_children("*", "CollisionObject3D", true, false):
		if body != rock and not guard.is_ancestor_of(body) and not landing_door.is_ancestor_of(body): excluded.append(body.get_rid())
	var opening := PhysicsRayQueryParameters3D.create(Vector3(-5,1.2,0), Vector3(-1,1.2,0),1,excluded)
	check(space.intersect_ray(opening).is_empty(), "restored grate leaves original entrance clear")
	var sweep := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new(); capsule.radius = 0.35; capsule.height = 1.8
	sweep.shape = capsule; sweep.transform.origin = Vector3(-5, 0.95, 0)
	sweep.motion = Vector3(4, 0, 0); sweep.collision_mask = 1; sweep.exclude = excluded
	check(space.cast_motion(sweep)[0] == 1.0, "player capsule can walk through original entrance")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		lift.restore_checkpoint_floor(4)
		await settle()
		# A top-level inspection camera avoids interpolating a teleported player rig.
		var review_camera := Camera3D.new()
		review_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(review_camera)
		review_camera.current = true
		player.body_animator.set_external_view(true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280,720))
		root.size = Vector2i(1280,720)
		for spec in [[Vector3(-6,2.4,6),Vector3(0,1,0),"entry-side"],[Vector3(3.95,2.8,0),Vector3(0,-8,0),"jump"],[Vector3(5,4.4,0),Vector3(0,-3,0),"snowmobile-jump"],[Vector3(3.45,1.65,0),Vector3(-1,-5,0),"standing"],[Vector3(0,1.65,-3.46),Vector3(0,-6,1),"standing-north"],[Vector3(3.95,6,0),Vector3(0,-8,0),"object-jump"],[Vector3(0,7,0),Vector3(0,-20,0.01),"overhead"],[Vector3(0,-3,0),Vector3(3.85,-4,-2),"interior"]]:
			review_camera.global_position = spec[0]
			review_camera.look_at(spec[1])
			for debug_view in [false, true]:
				base.get_node("WorldLighting").set_debug_darkness(0.0 if debug_view else 1.0)
				for frame in 4: await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("northernlab-shaft-fixed-"+spec[2]+("-inspection" if debug_view else "")+".png"))
		# Material review with the game's native flashlight settings, only in this test.
		base.get_node("WorldLighting").set_debug_darkness(1.0)
		var review_beam: SpotLight3D = player.flashlight.get_node("Beam").duplicate()
		review_camera.add_child(review_beam)
		review_beam.position = Vector3(0.3, -0.15, -0.1)
		review_beam.visible = true
		for spec in [[Vector3(0,-2,0),Vector3(3.9,-3,-1.8),"interior"],[Vector3(3.45,1.65,0),Vector3(-1,-5,0),"standing"]]:
			review_camera.global_position = spec[0]
			review_camera.look_at(spec[1])
			for frame in 6: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("northernlab-shaft-natural-lit-"+spec[2]+".png"))
		review_camera.queue_free()
	base.queue_free(); await process_frame
	print("EXPEDITION BUGFIX CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
