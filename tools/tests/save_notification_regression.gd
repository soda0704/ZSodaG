extends SceneTree
var checks := 0
var failures := 0
var notices: Array[String] = []
var output := "res://tools/.local/save-notification-review"

func _initialize() -> void:
	var prefix := "user://save_notice_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "_controls.cfg")
	create_timer(50).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(output)
	var base: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 25: await physics_frame
	var menu := root.get_node("GameMenu")
	menu.force_close_menu()
	var actor := get_first_node_in_group("local_player") as GamePlayer
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var notice := menu.get_node("SaveNotification")
	notice._bind_controller()
	state.save_notice_started.connect(func(kind): notices.append(kind))
	state._last_checkpoint_msec = -5001
	check(state.save_progress_authoritative(true), "background five-second save succeeds")
	check(not notice.visible and notices.is_empty(), "periodic saves stay silent")
	state.save_progress_authoritative(false, "progress")
	check(not notice.visible and notices.is_empty(), "ordinary gameplay commits stay silent too")
	menu.manual_save()
	check(notice.visible and notice.title.text == "Сохранение…" and notice.icon.is_playing(), "actual manual-save command shows saving text and supplied animation")
	check(notices == ["manual"], "one manual save produces exactly one notice")
	var first_frame: int = notice.icon.frame
	await create_timer(.2).timeout
	check(notice.icon.frame != first_frame and notice.icon.sprite_frames.get_frame_count(&"save") == 180, "original six-second SVG plays as native animated frames")
	await capture("saving")
	await create_timer(.65).timeout
	check(notice.title.text == "Игра сохранена" and not notice.icon.visible, "successful disk write transitions to confirmation")
	await capture("saved")
	await create_timer(2.5).timeout
	check(not notice.visible, "confirmation disappears automatically")
	var original_path: String = ProjectSettings.get_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING)
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, original_path + "/missing/fail.cfg")
	menu.manual_save()
	await create_timer(.8).timeout
	check(notice.title.text == "Не удалось сохранить игру", "failed real write cannot display a success message")
	check(FileAccess.file_exists(original_path), "write failure preserves previous save")
	await capture("failed")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, original_path)
	await create_timer(2.5).timeout
	var snapshot := state.get_snapshot()
	snapshot.day_index = 3
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 30.0
	snapshot.main_breaker_on = true
	snapshot.elevator_backup_installed = true
	snapshot.containment = {"level2": true}
	state._broadcast_snapshot(snapshot)
	var bunk: BaseEndDayBunk = base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	actor.teleport_authoritative(bunk.wake_pose.global_position, 0)
	bunk.network_sleep_interact(1, actor)
	await create_timer(.5).timeout
	bunk.cancel_sleep_authoritative(1, actor)
	check(not notices.has("sleep"), "cancelled sleep does not pretend to save a morning checkpoint")
	actor.teleport_authoritative(bunk.wake_pose.global_position, 0)
	bunk.network_sleep_interact(1, actor)
	await create_timer(5.25).timeout
	check(state.day_index == 4 and notices.count("sleep") == 1 and notice.visible, "actual successful night displays one morning-save notice")
	await create_timer(.8).timeout
	check(notice.title.text == "Игра сохранена", "morning checkpoint confirms successful saving")
	current_scene = null
	base.queue_free()
	for frame in 4: await process_frame
	print("SAVE NOTICE CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
