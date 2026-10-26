extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void:
	var prefix := "user://expedition_resume_%d" % OS.get_process_id()
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,prefix)
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+"/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+"/controls.cfg")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func settle() -> void:
	for frame in 6: await physics_frame
func freeze(world: Node) -> GamePlayer:
	var player: GamePlayer = world.get_node("Players/1")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	return player
func exit_world(menu: Node) -> void:
	menu.return_to_main_menu()
	while menu._transition_in_progress: await process_frame
func run() -> void:
	Engine.max_fps = 60
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow(false)
	var world := current_scene
	await world._enter_v3_level()
	var player := freeze(world)
	await settle()
	var state: BaseGameplayController = world.get_node("V3Level/BaseGameplayController")
	var elevator: FunctionalElevatorController = world._v3_elevator_controller
	var snapshot := state.get_snapshot()
	snapshot.day_index = 3
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 30.0
	snapshot.main_breaker_on = true
	snapshot.elevator_backup_installed = true
	snapshot.containment = {"level2": true}
	state._broadcast_snapshot(snapshot)
	await settle()
	elevator.restore_checkpoint_floor(2)
	player.pickup_world_item_authoritative(&"pistol", {"rounds": 7})
	player.survival.health = 63.0
	player.survival.radiation = 22.0
	player.teleport_authoritative(elevator.cabin.to_global(Vector3(0, 0.1, 0)), 0.6)
	var cargo_pose := Transform3D(Basis.IDENTITY, elevator.cabin.to_global(Vector3(-1, 0.15, 0)))
	world.spawn_world_item(&"fuel_can", world.world_items.global_transform.affine_inverse() * cargo_pose, {"fuel_liters": 11.0})
	await settle()
	check(elevator.request_call(1), "production elevator accepts trip")
	var timeout := Time.get_ticks_msec() + 8000
	while elevator.state != FunctionalElevatorController.ElevatorState.MOVING and Time.get_ticks_msec() < timeout:
		await physics_frame
	check(elevator.state == FunctionalElevatorController.ElevatorState.MOVING, "save during actual elevator trip")
	player.teleport_authoritative(elevator.cabin.to_global(Vector3(0, 0.1, 0)), 0.6)
	check(state.save_progress_authoritative(false, "manual"), "manual save includes complete expedition")
	menu.open_menu(menu.MenuView.MAIN)
	menu.main_panel.get_node("Save").pressed.emit()
	check(ExpeditionSaveStore.summary("solo").kind == "manual" and menu.feedback_label.text == "Экспедиция сохранена.", "authored ESC button saves through existing controller")
	menu.force_close_menu()
	var saved := ExpeditionSaveStore.read("solo")
	var checkpoint: Dictionary = saved.config.get_value("inventory", "checkpoint")
	var count: int = checkpoint.pickups.size()
	check(checkpoint.participants.solo.in_cabin, "player stored relative to moving cabin")
	check(checkpoint.participants.solo.survival.health == 63, "health captured with inventory")
	# Simulate leaving after this exact save, without producing another save.
	state.progress_persistence_enabled = false
	await exit_world(menu)
	await menu.start_standalone_flow(true)
	world = current_scene
	player = freeze(world)
	await settle()
	state = world.get_node("V3Level/BaseGameplayController")
	elevator = world._v3_elevator_controller
	check(state.day_index == 3 and state.elevator_backup_installed and state.containment.get("level2", false), "day story and power restored")
	check(player.has_held_item(&"pistol") and player.weapon.rounds == 7, "held weapon and ammunition restored")
	check(player.survival.health == 63 and absf(player.survival.radiation - 22) < 1.0, "resume preserves health and radiation")
	check(elevator.current_floor_index == 2 and elevator.state == FunctionalElevatorController.ElevatorState.IDLE_OPEN, "moving elevator resumes parked at saved departure floor")
	check(elevator.cabin.to_local(player.global_position).distance_to(Vector3(0, 0.1, 0)) < 0.02, "owner resumes safely in parked cabin")
	check(world.capture_inventory_checkpoint().pickups.size() == count, "resume does not duplicate world loot")
	check(ExpeditionSaveStore.history("solo").size() == 1, "manual save preserved initial checkpoint")
	# Use the existing sleep consensus, not a fabricated save-kind call.
	var bunk: BaseEndDayBunk = world.get_node("V3Level/Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	player.teleport_authoritative(bunk.wake_pose.global_position,0)
	bunk.network_sleep_interact(1,player)
	check(state.is_peer_sleeping(1) and player.is_sleeping_in_bunk(), "existing day-three bunk starts real sleep consensus")
	await create_timer(5.3).timeout
	check(state.day_index == 4, "existing sleep advances the expedition")
	check(ExpeditionSaveStore.history("solo").any(func(point): return point.kind=="sleep" and point.day_index==4), "sleep records a morning checkpoint even if periodic saving follows")
	var morning: Transform3D = world.get_node("V3Level").get_day_start_transform(0)
	check(player.global_position.distance_to(morning.origin) < 0.01 and not player.is_sleeping_in_bunk(), "morning save contains awake safe spawn")
	state.progress_persistence_enabled = false
	await exit_world(menu)
	await menu.start_standalone_flow(true)
	world = current_scene
	player = freeze(world)
	await settle()
	state = world.get_node("V3Level/BaseGameplayController")
	check(state.day_index == 4 and player.global_position.distance_to(morning.origin) < 0.1, "sleep checkpoint resumes at correct morning")
	check(player.survival.health == player.survival.max_health and is_zero_approx(player.survival.radiation), "completed sleep saves restored health and cleared radiation")
	# Persist death countdown; relaunching cannot heal a dying player for free.
	player.survival.dead = true
	player.survival.health = 0
	player.survival.reason = "Проверка сохранения"
	player.survival.respawn_remaining = 3.0
	check(state.save_progress_authoritative(false, "manual"), "death countdown can be saved")
	state.progress_persistence_enabled = false
	await exit_world(menu)
	await menu.start_standalone_flow(true)
	world = current_scene
	player = freeze(world)
	check(player.survival.dead and player.survival.health == 0 and player.survival.respawn_remaining > 2.0, "resume restores death and remaining respawn timer")
	var files := ExpeditionSaveStore._files("solo")
	var next_number := int(files[0].trim_prefix("commit_").trim_suffix(".cfg")) + 1
	var blocked := ExpeditionSaveStore.directory("solo").path_join("commit_%012d.cfg.tmp" % next_number)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocked))
	var before_exit: Node = current_scene
	menu.return_to_main_menu()
	check(current_scene == before_exit and menu.dialog != null, "save failure keeps session open for explicit exit choice")
	check(not menu._transition_in_progress, "failed exit save does not enter transition")
	menu.dialog.dismiss()
	await create_timer(0.25).timeout
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked))
	world._base_gameplay_controller.progress_persistence_enabled = false
	await exit_world(menu)
	print("RESUME CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
