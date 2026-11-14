extends SceneTree
## Graphical test; also runs against an exported --main-pack. All saves are isolated.
var failures := 0

func _initialize() -> void:
	var prefix := "user://render_lifecycle_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefix))
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root", prefix + "/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "/controls.cfg")
	ProjectSettings.set_setting("northern_lab/testing/base_save_path", prefix + "/base.cfg")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func frames(count: int) -> void:
	for i in count:
		await process_frame
		await RenderingServer.frame_post_draw

func wait_for_menu() -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.is_in_group("main_menu"):
			return true
		await process_frame
	return false

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rendering lifecycle requires a graphical driver")
		quit(1)
		return
	var menu := root.get_node("GameMenu")
	var main = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for cycle in 3:
		print("RENDER CYCLE ", cycle)
		await frames(50)
		main = current_scene
		main.show_character()
		var deadline := Time.get_ticks_msec() + 30000
		while not main.selector._picking_ready and Time.get_ticks_msec() < deadline:
			await process_frame
		check(main.selector._picking_ready and main.selector.models.size() == 2, "both character previews render in cycle %d" % cycle)
		await frames(5)
		await menu.start_standalone_flow()
		await frames(30)
		var players := get_nodes_in_group("local_player")
		check(players.size() == 1, "exactly one local player after load %d" % cycle)
		check(get_nodes_in_group("local_blizzard").size() == 1, "exactly one exterior after load %d" % cycle)
		if players.size() == 1:
			check(players[0].is_inside_tree() and players[0].camera.current, "player camera is active after load %d" % cycle)
		menu.return_to_main_menu()
		check(await wait_for_menu(), "return to main menu completes in cycle %d" % cycle)
		await frames(30)
		check(get_nodes_in_group("local_player").is_empty() and get_nodes_in_group("local_blizzard").is_empty(), "gameplay nodes leave the tree after cycle %d" % cycle)
		if current_scene == null or not current_scene.is_in_group("main_menu"): break
	print("RENDER LIFECYCLE FAILURES ", failures)
	if current_scene != null: current_scene.queue_free()
	current_scene = null
	await frames(5)
	quit(1 if failures else 0)
