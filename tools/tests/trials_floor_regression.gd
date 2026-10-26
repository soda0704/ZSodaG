extends SceneTree
## Walk the authored layout with the actual player capsule; no teleport between rooms.
var checks := 0
var failures := 0
var base: BaseBlockoutRuntime
var floor_root: Node3D
var player: GamePlayer
var state: BaseGameplayController
var elevator: FunctionalElevatorController

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func settle(frames: int = 8) -> void:
	for frame in frames: await physics_frame
	await process_frame

func point(x: float, z: float, y: float = 0.03) -> Vector3:
	return floor_root.to_global(Vector3(x, y, z))

func walk_to(x: float, z: float, label: String) -> void:
	var target := point(x, z)
	var deadline := Time.get_ticks_msec() + 7000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		var offset := target - player.global_position
		offset.y = 0.0
		if offset.length() < 0.12: break
		var speed := minf(6.0, offset.length() * 60.0)
		player.velocity = offset.normalized() * speed
		player.velocity.y = -1.0
		player.move_and_slide()
	player.velocity = Vector3.ZERO
	var arrived := Vector2(player.global_position.x - target.x, player.global_position.z - target.z).length() < 0.18
	check(arrived and absf(player.global_position.y - floor_root.global_position.y) < 0.2, label)
	if not arrived or absf(player.global_position.y - floor_root.global_position.y) >= 0.2:
		print("WALK AT ", floor_root.to_local(player.global_position), " TARGET ", Vector3(x, 0, z))

func capture(label: String, at: Vector3, target: Vector3) -> void:
	if "--capture" not in OS.get_cmdline_user_args(): return
	var camera := Camera3D.new()
	base.add_child(camera)
	camera.global_position = floor_root.to_global(at)
	camera.look_at(floor_root.to_global(target))
	camera.fov = 78
	camera.make_current()
	for frame in 55: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var luminance := 0.0
	var samples := 0
	for y in range(8, image.get_height(), 16):
		for x in range(8, image.get_width(), 16):
			luminance += image.get_pixel(x, y).get_luminance()
			samples += 1
	check(luminance / maxi(samples, 1) > 0.02, "authored powered lighting makes %s visible" % label)
	image.save_png("res://tools/.local/trials-%s.png" % label)
	camera.queue_free()
	await process_frame

func run() -> void:
	Engine.max_fps = 120
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	root.get_node("GameMenu").force_close_menu()
	await settle(12)
	state = base.get_node("BaseGameplayController")
	check(not state.progress_persistence_enabled, "preview leaves expedition saves untouched")
	state.set_process(false)
	player = get_first_node_in_group("network_players")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	floor_root = base.get_node("Floor_Minus3_Trials_Observation_Blockout")
	elevator = base.get_node("Elevator_Functional_Blockout")
	var snapshot := state.get_snapshot()
	snapshot.day_index = 4
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 60.0
	snapshot.main_breaker_on = true
	snapshot.maintenance = {}
	snapshot.containment = {}
	state._broadcast_snapshot(snapshot)
	await settle()
	check(elevator.unlocked_floor_index == 3, "day four opens only trials")
	elevator.set_day(3)
	check(elevator.unlocked_floor_index == 2, "day three still limits lift to life support")
	elevator.set_day(5)
	check(elevator.unlocked_floor_index == 4, "day five opens relocated containment")
	elevator.set_day(6)
	check(elevator.unlocked_floor_index == 5, "day six opens relocated expedition shaft")
	elevator.set_day(7)
	check(elevator.unlocked_floor_index == 5, "day seven reserves the cave for the separate winch")
	check(elevator.landings.get_child_count() == 6, "six authored landings")
	for index in elevator.MAX_FLOOR_INDEX + 1:
		var button := elevator.get_node("CabinMoving/InteriorPanel/FloorButton%d" % index)
		check(button.floor_index == index and button.get_node("Label").text == str(index), "cabin button and label %d agree" % index)
		var landing := elevator.landings.get_node("Floor_%d" % index) as Node3D
		check(is_equal_approx(landing.position.y, -18.0 * index) and landing.get_node("CallButton").floor_index == index, "landing and call %d align" % index)
		if index >= 3:
			var call_button := landing.get_node("CallButton") as StaticBody3D
			var call_visual := landing.get_node("LandingPortalArt/CallPanelVisual/Housing") as MeshInstance3D
			check(call_button.global_position.distance_to(call_visual.global_position) < 0.02, "call collider matches visible station %d" % index)
			var target := call_button.global_position
			var hit := call_button.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(target + Vector3(0, 0.2, 1.5), target, 1))
			check(not hit.is_empty() and hit.get("collider") == call_button, "call station %d reachable from inside arrival" % index)
			player.teleport_authoritative(target + Vector3(0, -1.3, 1.5), 0)
			await settle()
			player.camera.look_at(target)
			check(player.get_interaction_target() == call_button, "actual interaction ray selects call %d" % index)
			player.try_authoritative_interaction()
			check(elevator._active_destination_floor_index == index, "production E starts call to floor %d" % index)
			elevator.restore_checkpoint_floor(0)
			player.camera.rotation = Vector3.ZERO
			await settle()
	check(is_equal_approx(floor_root.global_position.y, -54.0), "trials occupies level three")
	check(is_equal_approx(base.get_node("Floor_Minus4_Biocontainment_Blockout").global_position.y, -72.0), "containment moved down one stop")
	check(is_equal_approx(base.get_node("Floor_Minus5_Expedition_Shaft_Blockout").global_position.y, -90.0), "expedition and its cavern placeholder moved together")
	var manager: BaseAutoDoorManager = floor_root.get_node("Doors/AutomaticDoors")
	check(manager.get_door_count() == 9, "all nine doors use existing base automation")
	var physics := floor_root.get_world_3d().direct_space_state
	for marker: Marker3D in floor_root.get_node("ReviewPoints").get_children():
		var hit := physics.intersect_ray(PhysicsRayQueryParameters3D.create(marker.global_position + Vector3.UP * 1.8, marker.global_position + Vector3.DOWN, 1))
		check(not hit.is_empty() and absf(Vector3(hit.get("position", Vector3.ZERO)).y - floor_root.global_position.y) < 0.1, "walkable floor under " + str(marker.name))
	elevator.restore_checkpoint_floor(3)
	await settle()
	player.teleport_authoritative(elevator.cabin.to_global(Vector3(0, 0.1, 0)), PI / 2)
	await settle()
	check(absf(player.global_position.y - floor_root.global_position.y) < 0.2, "walker starts on the restored physical cabin")
	await walk_to(-6, 0, "cabin threshold leads into trials arrival")
	await walk_to(-16, 0, "arrival access opens and capsule passes")
	await walk_to(-28, 0, "approach connects to control room")
	await capture("control", Vector3(-23.9, 1.75, 2.1), Vector3(-31, 2.2, -10))
	await walk_to(-41, 0, "control opens into western service loop")
	await walk_to(-41, -18, "western service has a continuous floor")
	await walk_to(-30, -18, "north service connects around chamber")
	await walk_to(-30, -13, "rear chamber door allows entry")
	await capture("exposure", Vector3(-35.7, 1.75, -14.4), Vector3(-28, 2.1, -7))
	await walk_to(-25, -13, "capsule can circle exposure apparatus")
	await walk_to(-25, -10, "east side of apparatus is traversable")
	await walk_to(-20, -10, "east chamber door connects to alternative route")
	await walk_to(-20, 0, "east service returns to approach")
	await walk_to(-34, 0, "control reachable again without backtracking through chamber")
	await walk_to(-34, 7, "observation A door is traversable")
	await capture("observation", Vector3(-32, 1.75, 6), Vector3(-35, 1.2, 12.5))
	await walk_to(-36, 7, "observation A provides passage beside its table")
	await walk_to(-36, 9, "observation A has usable interior space")
	await walk_to(-41, 9, "observation A also connects to service route")
	await walk_to(-41, 0, "observation service loop returns north")
	await walk_to(-26, 0, "return to control through service door")
	await walk_to(-26, 7, "observation B door is traversable")
	await walk_to(-26, 0, "observation B exit is unobstructed")
	var ray := physics.intersect_ray(PhysicsRayQueryParameters3D.create(point(-28, -2, 2), point(-28, -6, 2), 1))
	check(not ray.is_empty() and absf(Vector3(ray.get("position", Vector3.ZERO)).z + 3.96) < 0.12, "observation glass blocks interaction and bullet rays")
	await walk_to(-27.5, -2.5, "space between consoles reaches protected window")
	for frame in 70:
		await physics_frame
		player.velocity = Vector3(0, -1, -3)
		player.move_and_slide()
	check(player.global_position.z > -3.7, "player capsule cannot cross protective glass or sill")
	player.velocity = Vector3.ZERO
	snapshot = state.get_snapshot()
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot)
	await settle(50)
	check(not base.get_node("WorldLighting/Standard").visible and base.get_node("WorldLighting/Emergency").visible, "trials lights obey existing main and emergency power")
	var service_open := true
	for door in manager._doors:
		if door.startup_route: service_open = service_open and door.open and door.blocker.disabled
	check(service_open, "service egress stays usable during power loss")
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	await settle(15)
	await capture("arrival", Vector3(-5.5, 1.75, 1.4), Vector3(-14, 1.9, 0))
	base.queue_free()
	await settle()
	print("TRIALS CHECKS ", checks, " RESULT FAILURES ", failures)
	quit(1 if failures else 0)
