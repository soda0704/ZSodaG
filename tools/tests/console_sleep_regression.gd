extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
	var prefix := "user://console_sleep_%d" % OS.get_process_id()
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, prefix)
	ProjectSettings.set_setting(ExpeditionSaveStore.LEGACY_PATHS_SETTING, {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix + "/journal")
	create_timer(65).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func run() -> void:
	Engine.max_fps = 60
	var menu := root.get_node("GameMenu")
	var console := root.get_node("DeveloperConsole")
	await menu.start_standalone_flow(false)
	var world: Node = current_scene
	check(console.execute("/sleep").contains("база ещё не загружена"), "sleep rejected before base arrival")
	await world._enter_v3_level()
	var state: BaseGameplayController = world._base_gameplay_controller
	var actor: GamePlayer = world.players.get_node("1")
	state.set_process(false)
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var initial: String = ExpeditionSaveStore.read("solo").path
	check(console._help_text().contains("/sleep") and console._help_text().contains("/next day") and console._help_text().contains("/last day"), "help includes three new commands")
	console.entry.text = "/sl"
	console.entry.caret_column = 3
	console.complete_command()
	check(console.entry.text == "/sleep", "Tab completes sleep")
	check(console.execute("/last day").contains("первый") and state.day_index == 1, "previous day cannot go below one")
	check(console.execute("/next day").contains("без сохранения") and state.day_index == 2, "next day advances without claiming to save")
	check(console.execute("/last day").contains("без сохранения") and state.day_index == 1, "last day means previous day")
	check(ExpeditionSaveStore.read("solo").path == initial, "relative day commands do not write to disk")
	check(console.execute("/sleep extra").contains("Использование") and state.day_index == 1, "invalid sleep arguments do not change the world")
	var snapshot := state.get_snapshot()
	snapshot.plant_seed_planted = true
	snapshot.plant_last_watered_day = 1
	state._broadcast_snapshot(snapshot)
	actor.survival.health = 43.0
	actor.survival.radiation = 23.0
	check(state.save_progress_authoritative(false, "manual"), "seed today's consumed manual save")
	check(not state.can_end_current_day(), "day task is still incomplete before debug sleep")
	check(console.execute("/sleep").contains("автосейв записан"), "console sleep actually writes the morning")
	check(state.day_index == 2 and state.manual_save_day == 0 and state.can_manual_save(), "sleep grants next day's manual allowance")
	check(actor.survival.health == actor.survival.max_health and is_zero_approx(actor.survival.radiation), "debug night uses ordinary sleep recovery")
	check(state.plant_growth_stage == 1 and not state.plant_withered, "debug night uses ordinary plant aging")
	check(state.maintenance.get("wires_required", false) and not state.main_breaker_on, "first night keeps the ordinary wiring outage")
	var morning: Transform3D = state.get_parent().get_day_start_transform(0)
	check(not actor.is_sleeping_in_bunk() and actor.global_position.distance_to(morning.origin) < .01, "morning is captured after waking at the correct bunk")
	var points := ExpeditionSaveStore.checkpoints("solo")
	check(points[0].is_empty() and points[1].day_index == 2 and points[2].day_index == 1, "manual expires and both morning entries are correct")
	var disk: ConfigFile = ExpeditionSaveStore.read("solo").config
	check(disk.get_value("inventory", "checkpoint").participants.solo.survival.health == actor.survival.max_health, "actual disk snapshot contains healed player")
	# Complete an already pending real night once, cancelling its delayed timer.
	console.execute("/day 3")
	snapshot = state.get_snapshot()
	snapshot.elevator_backup_installed = true
	snapshot.maintenance["wires_required"] = false
	snapshot.main_breaker_on = true
	snapshot.containment["level2"] = true
	state._broadcast_snapshot(snapshot)
	var bunk: BaseEndDayBunk = state.get_parent().get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	actor.teleport_authoritative(bunk.wake_pose.global_position, 0)
	bunk.network_sleep_interact(1, actor)
	check(actor.is_sleeping_in_bunk(), "real bunk night was pending")
	check(console.execute("/sleep").contains("автосейв записан") and state.day_index == 4, "command finishes a pending night exactly once")
	var after_sleep: String = ExpeditionSaveStore.read("solo").path
	await create_timer(5.4).timeout
	check(state.day_index == 4 and ExpeditionSaveStore.read("solo").path == after_sleep, "old timer cannot advance or autosave a second night")
	console.execute("/day 2")
	check(console.execute("/sleep").contains("автосейв записан") and state.day_index == 3, "sleep after debug rewind can record a replacement morning")
	check(ExpeditionSaveStore.summary("solo").day_index == 3 and ExpeditionSaveStore.checkpoints("solo")[0].is_empty(), "debug replacement discards future saves only after successful publication")
	after_sleep = ExpeditionSaveStore.read("solo").path
	console.execute("/next day")
	actor.survival.dead = true
	check(console.execute("/sleep").contains("живы") and state.day_index == 4, "dead participant prevents an unsafe forced night")
	actor.survival.dead = false
	var files := ExpeditionSaveStore._files("solo")
	var serial := int(files[0].trim_prefix("commit_").trim_suffix(".cfg")) + 1
	var blocker := ExpeditionSaveStore.directory("solo").path_join("commit_%012d.cfg.tmp" % serial)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(blocker))
	check(console.execute("/sleep").contains("не удалось") and state.day_index == 5, "console reports failed autosave instead of claiming success")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocker))
	check(ExpeditionSaveStore.read("solo").path == after_sleep, "failed morning write preserves previous file")
	state.progress_persistence_enabled = false
	check(console.execute("/sleep").contains("F6") and state.day_index == 6, "preview mode keeps disk persistence disabled")
	check(ExpeditionSaveStore.read("solo").path == after_sleep, "preview sleep cannot alter real checkpoint")
	console.execute("/day 999")
	check(console.execute("/next day").contains("последний") and console.execute("/sleep").contains("последний") and state.day_index == 999, "relative commands and sleep respect maximum day")
	current_scene = null
	world.queue_free()
	for frame in 4: await process_frame
	print("CONSOLE SLEEP CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
