extends SceneTree
## Production pickups, real wall/floor, native elevator cargo and full scene resume.
var checks := 0
var failures := 0
var world: Node
var actor: GamePlayer
const TYPES := [&"fuel_can", &"fuse", &"seed_packet"]

func _initialize() -> void:
	var prefix := "user://critical_continuity_%d" % OS.get_process_id()
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, prefix)
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix + "/journal")
	create_timer(100).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func until(test: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 12000
	while not test.call() and Time.get_ticks_msec() < deadline: await process_frame
	return test.call()

func freeze_player() -> void:
	actor = world.players.get_node("1")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	world.set_process(false)
	world._base_gameplay_controller.set_process(false)

func pickups(type: StringName) -> Array:
	return world.world_items.get_children().filter(func(item): return not item.is_queued_for_deletion() and item.item_type == type)

func collect(item: WorldItemPickup) -> bool:
	actor.teleport_authoritative(item.global_position + Vector3(0, .1, 1), 0)
	item.network_interact(1, actor)
	await process_frame
	return actor.has_held_item(item.item_type) if is_instance_valid(item) else actor._held_item_type != &""

func run() -> void:
	if DisplayServer.get_name() != "headless":
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow(false)
	world = current_scene
	await world._enter_v3_level()
	freeze_player()
	var state: BaseGameplayController = world._base_gameplay_controller
	var snapshot: Dictionary = state.get_snapshot()
	snapshot.day_index = 3
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 30.0
	snapshot.main_breaker_on = true
	snapshot.elevator_backup_installed = false
	state._broadcast_snapshot(snapshot)
	var elevator: FunctionalElevatorController = world._v3_elevator_controller
	elevator.restore_checkpoint_floor(0)
	# Isolate one original instance of each critical type; discard unrelated
	# fixture loot only, so any later duplicate is unambiguous.
	var selected := {}
	for item in world.world_items.get_children():
		if item.item_type in TYPES and not selected.has(item.item_type): selected[item.item_type] = item
		else: item.queue_free()
	await process_frame
	check(selected.size() == 3, "new expedition contains original fuel, reserve fuse and seeds")
	if selected.size() != 3: quit(1); return
	selected[&"fuel_can"].item_state["fuel_liters"] = 8.25
	var cargo: Array[WorldItemPickup] = []
	for index in TYPES.size():
		var type: StringName = TYPES[index]
		check(await collect(selected[type]), "original item can be picked up: " + str(type))
		actor.teleport_authoritative(Vector3(6.7, .1, 22), -PI / 2)
		actor.head.rotation.x = -1.0
		check(actor.drop_current_item_authoritative(), "ordinary G drop next to generator-room wall: " + str(type))
		await create_timer(1.2).timeout
		var remaining := pickups(type)
		check(remaining.size() == 1, "drop leaves exactly one instance: " + str(type))
		if remaining.size() != 1: continue
		var item: WorldItemPickup = remaining[0]
		check(item.global_position.is_finite() and item.global_position.y > -.5 and item.global_position.distance_to(actor.global_position) < 3.5, "item stays above floor and within recovery reach: " + str(type))
		actor.head.rotation.x = 0
		actor.teleport_authoritative(item.global_position + Vector3(0, .1, 1), 0)
		actor.camera.look_at(item.global_position)
		for frame in 3: await physics_frame
		var target := actor.get_interaction_target()
		if target != item:
			var shape: CollisionShape3D = item.get_node("CollisionShape3D")
			var bounds: AABB = shape.global_transform * shape.shape.get_debug_mesh().get_aabb()
			print("DROP TARGET DEBUG ", type, " pos=", item.global_position, " bounds=", bounds, " target=", target.get_path() if target != null else "none")
		check(target == item, "actual interaction ray can recover dropped item: " + str(type))
		if type == &"seed_packet" and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/critical-seed-after-drop.png")
		check(await collect(item), "dropped item can be picked up again: " + str(type))
		actor.camera.rotation = Vector3.ZERO
		var cargo_pose := Transform3D(Basis.IDENTITY, elevator.cabin.to_global(Vector3(-.7 + index * .7, 1, 0)))
		check(actor.drop_current_item_at_authoritative(cargo_pose), "put existing item onto native cabin floor: " + str(type))
		await process_frame
		cargo.append(pickups(type)[0])
	await create_timer(1.2).timeout
	check(cargo.size() == 3 and cargo.all(func(item): return item._cargo_cabin == elevator.cabin), "all critical items attach to native elevator cargo support")
	actor.teleport_authoritative(elevator.cabin.to_global(Vector3(0, .1, .8)), 0)
	check(elevator.request_floor(2), "start a real elevator trip with critical cargo")
	check(await until(func(): return elevator.state == FunctionalElevatorController.ElevatorState.MOVING), "native trip reaches movement phase")
	await create_timer(.25).timeout
	menu.manual_save()
	var disk := ExpeditionSaveStore.read("solo")
	var checkpoint: Dictionary = disk.config.get_value("inventory", "checkpoint")
	check(checkpoint.pickups.size() == 3 and checkpoint.pickups.all(func(item): return item.in_cabin and item.cabin_id == "elevator_floor"), "moving-trip save records every item once relative to the correct transport")
	var saved_items: Array = checkpoint.pickups.duplicate(true)
	state.progress_persistence_enabled = false
	menu.return_to_main_menu()
	while menu._transition_in_progress: await process_frame
	await menu.start_standalone_flow(true)
	world = current_scene
	freeze_player()
	elevator = world._v3_elevator_controller
	for frame in 8: await physics_frame
	check(elevator.current_floor_index == 0 and elevator.state == FunctionalElevatorController.ElevatorState.IDLE_OPEN, "resume parks the transport safely at its saved departure stop")
	check(world.world_items.get_child_count() == 3, "resume restores critical cargo without default-loot duplication")
	for type in TYPES:
		var items := pickups(type)
		check(items.size() == 1, "resume retains one critical item: " + str(type))
		if items.size() != 1: continue
		var expected: Dictionary = saved_items.filter(func(data): return data.item_type == type)[0]
		check(elevator.cabin.to_local(items[0].global_position).distance_to(expected.transform.origin) < .15, "saved cabin-relative item position is preserved: " + str(type))
		check(await collect(items[0]), "restored item remains recoverable: " + str(type))
		if type == &"fuel_can": check(is_equal_approx(actor.fuel_liters, 8.25), "restored fuel can retains exact remaining liters")
		actor.drop_current_item_at_authoritative(Transform3D(Basis.IDENTITY, elevator.cabin.to_global(Vector3(0, 1, 0))))
		await process_frame
	check(not world._base_gameplay_controller.elevator_backup_installed and world._base_gameplay_controller.quest_stage == BaseGameplayController.QuestStage.OFFERED, "item round-trip neither installs reserve nor advances shared story unexpectedly")
	world._base_gameplay_controller.progress_persistence_enabled = false
	current_scene = null
	world.queue_free()
	for frame in 4: await process_frame
	print("CRITICAL ITEM CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
