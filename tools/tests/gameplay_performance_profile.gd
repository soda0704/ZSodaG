extends "res://tools/tests/journal_performance_profile.gd"
## Real rendered production scenes; timings are measurements, not pass/fail limits.

func measure(label: String, warmup := 30, action: Callable = Callable()) -> void:
	await frames(warmup)
	samples.clear()
	measuring = true
	previous = Time.get_ticks_usec()
	var deadline := Time.get_ticks_msec() + 3000
	if action.is_valid(): action.call()
	while Time.get_ticks_msec() < deadline: await process_frame
	measuring = false
	samples.sort()
	var record := {"state": label, "p50_ms": samples[samples.size() / 2],
		"p95_ms": samples[int(samples.size() * .95)], "p99_ms": samples[int(samples.size() * .99)],
		"max_ms": samples.back(), "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"active_bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	results.append(record)
	print("GAMEPLAY PROFILE ", JSON.stringify(record))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	# Synchronous screenshot readback is instrumentation, not gameplay work.
	# Drain it before the following transition sample, which has no warmup.
	await frames(2)

func start_route() -> void:
	create_tween().tween_property(actor, "global_position:x", -20.0, 3.0)

func kill_three(encounter: Node) -> void:
	for index in 3: encounter.get_node("Monster%d" % index).apply_weapon_damage(10000.0)

func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	Engine.max_fps = 0
	root.mode = Window.MODE_WINDOWED
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if output == "res://tools/.local/journal-performance":
		output = "res://tools/.local/order-gameplay-profile"
	DirAccess.make_dir_recursive_absolute(output)
	var base: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await frames(25)
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.survival.debug_invincible = true
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	state.progress_persistence_enabled = false
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 40.0
	state._broadcast_snapshot(snapshot)
	actor.teleport_authoritative(Vector3(-29.9, .1, 6.3), 0)
	await measure("exterior_idle", 120)
	await measure("exterior_camera_travel", 0, start_route)
	actor.teleport_authoritative(Vector3(-29.9, .1, 6.3), 0)
	await frames(60)
	await measure("exterior_camera_travel_repeated", 0, start_route)
	actor.teleport_authoritative(Vector3(0, .1, 5), 0)
	await measure("hub_idle", 120)
	var body: MedicalCorpse = get_nodes_in_group("medical_corpses").filter(func(candidate): return candidate.recoverable)[0]
	while not body.initialized: await process_frame
	actor.teleport_authoritative(body.ragdoll.root_body.global_position + Vector3(0, .1, 1.5), 0)
	await measure("medical_ground", 120)
	body.network_interact(1, actor)
	await create_timer(1.8).timeout
	if body.mode != MedicalCorpse.Mode.CARRIED:
		push_error("Profile did not enter actual shoulder carry")
		quit(1)
		return
	await measure("medical_shoulder")
	body.drop_from_shoulder(1)
	snapshot = state.get_snapshot()
	snapshot.day_index = 5
	snapshot.containment = {}
	state._broadcast_snapshot(snapshot)
	var encounter := base.get_node("ContainmentEncounter")
	var creature: Node3D = encounter.get_node("Monster0")
	actor.teleport_authoritative(creature.global_position + Vector3(0, .1, 8), 0)
	actor.camera.look_at(creature.global_position + Vector3.UP)
	await measure("three_story_creatures", 120)
	await measure("ragdoll_activation", 0, kill_three.bind(encounter))
	await create_timer(7).timeout
	await measure("ragdolls_settled")
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"resolution": str(size), "gpu": RenderingServer.get_video_adapter_name(), "results": results}, "\t"))
	file.close()
	current_scene = null
	base.queue_free()
	await frames(4)
	print("GAMEPLAY PROFILE COMPLETE")
	quit()
