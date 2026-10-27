extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	var prefix := "user://explicit_save_io_%d" % OS.get_process_id()
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, prefix)
	ProjectSettings.set_setting(ExpeditionSaveStore.LEGACY_PATHS_SETTING, {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix + "/journal")
	create_timer(70).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func serial() -> int:
	var names := ExpeditionSaveStore._files("solo")
	return int(names[0].trim_prefix("commit_").trim_suffix(".cfg")) if not names.is_empty() else 0
func flush() -> void:
	for frame in 3: await process_frame
func run() -> void:
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow(false)
	var world: Node = current_scene
	await world._enter_v3_level()
	var actor: GamePlayer = world.players.get_node("1")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var state: BaseGameplayController = world._base_gameplay_controller
	await flush()
	var before := serial()
	check(before == 1 and ExpeditionSaveStore.summary("solo").kind == "start", "new expedition has exactly one initial morning")
	for count in [1, 2, 3]:
		actor.tape_count = count
		actor._publish_inventory()
		await flush()
	actor.pickup_world_item_authoritative(&"battery", {"charge_amount": 1.0})
	var snapshot := state.get_snapshot()
	snapshot.maintenance["save_policy_test"] = true
	state._broadcast_snapshot(snapshot)
	await create_timer(5.4).timeout
	check(serial() == before, "inventory, pickups, world changes and five elapsed seconds produce no disk commits")
	check(not state.save_progress_authoritative(true) and not state.save_progress_authoritative(false, "progress"), "periodic and background requests are rejected")
	menu.open_menu(menu.MenuView.MAIN)
	check(not menu.main_panel.get_node("Save").disabled, "ESC offers one manual save")
	menu.main_panel.get_node("Save").pressed.emit()
	check(serial() == before + 1 and state.manual_save_day == 1, "ESC manual command writes once and consumes today's allowance")
	check(menu.main_panel.get_node("Save").disabled and menu.main_panel.get_node("SaveHint").text.contains("использована"), "ESC explains consumed allowance")
	var data := ExpeditionSaveStore.read("solo")
	check(data.config.get_value("inventory", "checkpoint").players.solo.tape_count == 3 and data.config.get_value("base", "maintenance").save_policy_test, "manual save captures complete current inventory and world")
	menu.manual_save()
	check(serial() == before + 1, "second manual command cannot overwrite saved state")
	actor.tape_count = 9
	actor._publish_inventory()
	snapshot = state.get_snapshot()
	snapshot.maintenance["after_save"] = true
	state._broadcast_snapshot(snapshot)
	menu.quit_with_save()
	check(menu.dialog != null and not menu._quitting and serial() == before + 1, "window close warns about loss without creating a save")
	menu.dialog.dismiss()
	await create_timer(.3).timeout
	menu.return_to_main_menu()
	while menu._transition_in_progress: await process_frame
	check(serial() == before + 1, "return to menu does not create an exit save")
	await menu.start_standalone_flow(true)
	world = current_scene
	actor = world.players.get_node("1")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	state = world._base_gameplay_controller
	check(actor.tape_count == 3 and not state.maintenance.has("after_save"), "resume discards unsaved inventory and base changes")
	check(state.manual_save_day == 1 and not state.can_manual_save(), "manual allowance survives full scene reload")
	check(serial() == before + 1, "loading does not itself resave the world")
	current_scene = null
	world.queue_free()
	for frame in 4: await process_frame
	print("CHECKPOINT IO CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
