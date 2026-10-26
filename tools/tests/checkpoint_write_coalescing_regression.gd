extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	var prefix := "user://checkpoint_io_%d" % OS.get_process_id()
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, prefix)
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
	world.set_process(false)
	var state: BaseGameplayController = world._base_gameplay_controller
	state.set_process(false)
	await flush()
	var before := serial()
	var start := Time.get_ticks_usec()
	for count in [1, 2, 3]:
		actor.tape_count = count
		actor._publish_inventory()
	await flush()
	var writes := serial() - before
	print("CHECKPOINT IO burst_writes=", writes, " elapsed_ms=", float(Time.get_ticks_usec() - start) / 1000.0)
	check(writes == (3 if OS.get_cmdline_user_args().has("--baseline") else 1), "same-frame inventory burst writes the expected number of actual disk commits")
	var config: ConfigFile = ExpeditionSaveStore.read("solo").config
	check(config.get_value("inventory", "checkpoint").players.solo.tape_count == 3, "last inventory state reaches disk")
	if not OS.get_cmdline_user_args().has("--baseline"):
		before = serial()
		for count in [4, 5]:
			actor.tape_count = count
			actor._publish_inventory()
			await flush()
		check(serial() - before == 2, "changes in separate frames are still saved separately")
		before = serial()
		actor.tape_count = 6
		actor._publish_inventory()
		world.save_inventory_checkpoint()
		await flush()
		check(serial() - before == 2, "explicit immediate checkpoint preserves the final queued inventory snapshot")
		before = serial()
		actor.tape_count = 7
		actor._publish_inventory()
		world.save_inventory_checkpoint(true)
		await flush()
		check(serial() - before == 1 and ExpeditionSaveStore.read("solo").config.get_value("inventory", "checkpoint").players.solo.tape_count == 7, "throttled periodic save cannot cancel pending inventory persistence")
		before = serial()
		check(state.save_progress_authoritative(false, "manual"), "manual save remains immediate")
		check(serial() == before + 1, "manual commit is not deferred or suppressed")
	state.progress_persistence_enabled = false
	current_scene = null
	world.queue_free()
	for frame in 4: await process_frame
	print("CHECKPOINT IO CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
