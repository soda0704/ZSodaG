extends SceneTree
## Production shaft, native gates, real player/platform physics and checkpoint poses.
var checks := 0
var failures := 0
var base: Node3D
var state: BaseGameplayController
var winch: FunctionalElevatorController
var player: GamePlayer

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://winch_%d.cfg" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle(frames := 8) -> void:
	for frame in frames: await physics_frame

func until(predicate: Callable, seconds := 12.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await physics_frame
	return predicate.call()

func walk_to(point: Vector3, seconds := 4.0) -> bool:
	player.set_physics_process(false)
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		var offset := point - player.global_position
		offset.y = 0.0
		if offset.length() < 0.25:
			player.set_physics_process(true)
			return true
		var direction := offset.normalized()
		player.simulate_movement(1.0 / 60.0, Vector2(direction.x, direction.z), false, false, false, 0.0, 0.0)
		await physics_frame
	player.set_physics_process(true)
	print("WALK BLOCKED at ", player.global_position, " towards ", point)
	return false

func run() -> void:
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await settle()
	state = base.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false; state.set_process(false)
	winch = get_first_node_in_group("expedition_winches")
	player = get_first_node_in_group("local_player")
	player.survival.debug_invincible = true
	player.survival.set_physics_process(false)
	root.get_node("GameMenu").force_close_menu()
	for monster in get_nodes_in_group("hostile_monsters"): monster.set_physics_process(false)
	var travel_audio: AudioStreamPlayer3D = winch.get_node("CabinMoving/TravelAudio")
	check(travel_audio.stream.resource_path.ends_with("winch_gears_loop.ogg") and travel_audio.stream.loop and travel_audio.bus == &"Machinery", "user gear recording uses native looping and machinery mixer on winch only")
	travel_audio.play(travel_audio.stream.get_length() - 0.05)
	await create_timer(0.2).timeout
	check(travel_audio.playing and travel_audio.get_playback_position() < 1.0, "gear audio wraps across encoded loop boundary without stopping")
	travel_audio.stop()
	state.debug_set_day_authoritative(6)
	check(winch.stop_count == 2 and winch.cabin is AnimatableBody3D, "winch reuses the main elevator with two authored stops")
	check(not winch.is_powered and not winch.request_floor(1), "day six cannot depart into the cave")
	check("7-й день" in winch.get_button_prompt(1, false), "locked winch explains day-seven access")
	var prepared_snapshot := state.get_snapshot()
	prepared_snapshot.maintenance["winch_preparation"] = {"inspected":true, "pin_removed":true, "brake_armed":true, "tested":true}
	state._broadcast_snapshot(prepared_snapshot)
	state.debug_set_day_authoritative(7)
	check(winch.is_powered and winch.unlocked_floor_index == 1, "day seven enables winch from main power")
	check(is_equal_approx(winch.cabin.global_position.y, -90.0) and is_equal_approx(winch._get_floor_y(1), -72.0), "stops follow the existing 72-meter shaft contract")
	check(winch._get_landing_door(0).is_open and not winch._get_landing_door(1).is_open, "only occupied landing is initially open")
	var lower: ElevatorFloorButton = winch.get_node("Landings/Floor_1/CallButton")
	var upper: ElevatorFloorButton = winch.get_node("Landings/Floor_0/CallButton")
	check(lower.controller == winch and upper.controller == winch and lower.floor_index == 1 and upper.floor_index == 0, "both landing call buttons are connected")
	check(winch.get_node("CabinMoving/UpButton").controller == winch and winch.get_node("CabinMoving/DownButton").controller == winch, "both in-cage travel buttons are connected")
	# Increase travel speed for regression execution; retain production geometry/physics.
	winch.travel_speed = 24.0; winch.travel_start_stop_time = 0.3
	winch.door_animation_duration = 0.15
	winch.cabin_door.animation_duration = 0.15
	for index in 2: winch._get_landing_door(index).animation_duration = 0.15
	player.teleport_authoritative(winch.cabin.global_position + Vector3(0,0.12,0), 0)
	await settle(20)
	check(player.is_on_floor(), "player stands on authored moving deck")
	player.teleport_authoritative(winch.cabin.global_position + Vector3(0,0.12,2.25), 0)
	await settle()
	check(not winch.request_floor(1) and winch.state == winch.ElevatorState.WAITING_FOR_PLAYERS, "occupied gate prevents departure")
	player.teleport_authoritative(winch.cabin.global_position + Vector3(0,0.12,0), 0)
	await settle()
	check(await until(func(): return winch.state == winch.ElevatorState.MOVING), "clearing gate starts one pending descent")
	check(not winch.request_call(0) and not winch.request_floor(1), "conflicting requests cannot restart moving cage")
	check(not winch.cabin_door_travel_barrier.disabled and not winch._get_landing_door(0).is_open, "departure closes travel barrier and upper landing")
	var ray := PhysicsRayQueryParameters3D.create(winch.global_position + Vector3(0,1.4,4), winch.global_position + Vector3(0,1.4,0), 1)
	var gate_hit := winch.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not gate_hit.is_empty() and winch._get_landing_door(0).is_ancestor_of(gate_hit.collider), "empty upper landing has a physical safety barrier")
	var driver: Node3D = load("res://tools/tests/fixtures/elevator_network_session.tscn").instantiate()
	driver.get_node("Elevator").free()
	root.add_child(driver)
	var saved_pose: Dictionary = driver._capture_cabin_pose(player.global_transform)
	check(saved_pose.in_cabin and saved_pose.cabin_id == "winch_floor", "mid-trip player checkpoint identifies the winch cabin")
	check(await until(func(): return winch.current_floor_index == 1 and winch.state == winch.ElevatorState.IDLE_OPEN), "descent arrives and opens lower gate")
	check(absf(player.global_position.y - winch.cabin.global_position.y) < 0.3 and player.is_on_floor(), "real player rides the full shaft without falling")
	check(winch._get_landing_door(1).is_open and not winch._get_landing_door(0).is_open, "arrival opens only lower landing")
	check(state.containment.get("cave_visited", false), "real descent reaches day-seven visit zone")
	check(await walk_to(winch.cabin.global_position + Vector3(0,0,3.4)), "passenger walks through both lower gates")
	check(await walk_to(winch.cabin.global_position + Vector3(4.0,0,3.4)), "passenger can turn around cage toward cave")
	check(await walk_to(winch.cabin.global_position + Vector3(6.0,0,0)), "lower platform connects to the existing cave route")
	# A saved local pose follows the parked source stop on resume.
	winch.restore_checkpoint_floor(0)
	await settle()
	var restored: Transform3D = driver._restore_cabin_pose(saved_pose, saved_pose.transform)
	check(absf(restored.origin.y + 90.0) < 0.4, "mid-trip checkpoint restores passenger into parked source stop")
	var main: FunctionalElevatorController = base.get_node("Elevator_Functional_Blockout")
	var legacy := {"in_cabin": true}
	check(driver._restore_cabin_pose(legacy, Transform3D.IDENTITY).origin == main.cabin.global_position, "legacy main-elevator saves remain compatible")
	player.teleport_authoritative(winch.global_position + Vector3(0,-71.9,3.6), 0)
	await settle(20)
	check(player.is_on_floor(), "lower call platform supports waiting passenger")
	check(await walk_to(winch.global_position + Vector3(2.7,-72,3.8)), "lower call button is reachable from cave side")
	player.set_physics_process(false)
	var direction := lower.global_position - player.camera.global_position
	player.rotation.y = atan2(-direction.x, -direction.z)
	player.head.rotation.x = atan2(direction.y, Vector2(direction.x,direction.z).length())
	check(player.get_interaction_target() == lower, "real interaction ray reaches lower return control")
	player.try_authoritative_interaction()
	player.set_physics_process(true)
	check(await until(func(): return winch.current_floor_index == 1 and winch.state == winch.ElevatorState.IDLE_OPEN), "lower button calls empty cage back down")
	player.teleport_authoritative(winch.cabin.global_position + Vector3(0,0.12,0), 0)
	await settle()
	winch.get_node("CabinMoving/UpButton").network_interact(player.owner_peer_id, player)
	check(await until(func(): return winch.current_floor_index == 0 and winch.state == winch.ElevatorState.IDLE_OPEN), "in-cage upper button returns player to level five")
	check(absf(player.global_position.y + 90.0) < 0.4, "return trip carries player back to level-five deck")
	var snapshot := state.get_snapshot()
	snapshot.elevator_backup_installed = true
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot)
	check(winch.is_powered,"installed solar reserve powers the winch with the main breaker off")
	check(winch.request_floor(1),"solar reserve accepts an actual departure")
	check(await until(func(): return winch.current_floor_index==1 and winch.state==winch.ElevatorState.IDLE_OPEN),"solar reserve completes descent with main power off")
	check(winch.request_floor(0),"solar reserve accepts return from the lower landing")
	check(await until(func(): return winch.current_floor_index==0 and winch.state==winch.ElevatorState.IDLE_OPEN),"solar reserve returns player to level five")
	snapshot.elevator_backup_installed = false
	state._broadcast_snapshot(snapshot)
	check(not winch.is_powered and not winch.request_floor(1),"without mains or installed solar reserve, winch is unpowered")
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	check(winch.request_floor(1), "main power also restores winch operation")
	check(await until(func(): return winch.state == winch.ElevatorState.MOVING), "power-cut regression begins actual movement")
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot)
	check(await until(func(): return winch.current_floor_index == 1 and winch.state == winch.ElevatorState.UNPOWERED), "power loss finishes active trip at a safe landing")
	check(winch.cabin_door.is_open and winch._get_landing_door(1).is_open, "power loss does not trap passengers behind closed arrival gates")
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	if "--capture" in OS.get_cmdline_user_args(): await capture()
	driver.queue_free(); base.queue_free(); await process_frame
	print("WINCH CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)

func capture() -> void:
	var camera := Camera3D.new()
	base.add_child(camera); camera.current = true
	root.get_node("DeveloperConsole").set_open(false)
	for shot in [{"name":"upper", "at":Vector3(0,1.65,6.0), "to":Vector3(0,1.4,0)}, {"name":"inside", "at":Vector3(0,1.65,0), "to":Vector3(0,1.4,-1.8)}, {"name":"lower", "at":Vector3(0,-70.35,3.8), "to":Vector3(0,-70.5,0)}]:
		winch.restore_checkpoint_floor(1 if shot.name == "lower" else 0)
		await settle()
		camera.global_position = winch.global_position + shot.at
		camera.look_at(winch.global_position + shot.to)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-winch-"+shot.name+".png"))
