extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	var prefix := "user://load_abort_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefix))
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root", prefix + "/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	ProjectSettings.set_setting("northern_lab/testing/base_save_path", prefix + "/base.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	var menu := root.get_node("GameMenu")
	menu.start_standalone_flow()
	var job: RefCounted
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.get("_level_load_job") != null:
			job = current_scene.get("_level_load_job")
			if not job._pending_instances.is_empty(): break
		await process_frame
	check(job != null and not job._pending_instances.is_empty(), "real session reached suspended level construction")
	if job == null or job._pending_instances.is_empty():
		quit(1)
		return
	menu.abort_scene_load("Проверка отмены загрузки")
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and (current_scene == null or not current_scene.is_in_group("main_menu")):
		await process_frame
	for frame in 5: await process_frame
	check(current_scene != null and current_scene.is_in_group("main_menu"), "aborted loading returns to main menu")
	check(job.cancelled and job._pending_instances.is_empty(), "session exit cancels and releases detached construction")
	check(not menu._transition_in_progress, "aborted transition releases the menu lock")
	check(get_nodes_in_group("local_player").is_empty() and get_nodes_in_group("local_blizzard").is_empty(), "aborted world leaves no gameplay nodes in the tree")
	await menu.start_standalone_flow()
	check(get_nodes_in_group("local_player").size() == 1 and not menu._transition_in_progress, "new session starts successfully after cancellation")
	menu.return_to_main_menu()
	deadline = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and (current_scene == null or not current_scene.is_in_group("main_menu")):
		await process_frame
	print("SESSION LOAD ABORT CHECKS ", checks, " FAILURES ", failures)
	if current_scene != null: current_scene.queue_free()
	current_scene = null
	for frame in 5:
		await process_frame
		await RenderingServer.frame_post_draw
	quit(1 if failures else 0)
