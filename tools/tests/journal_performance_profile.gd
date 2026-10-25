extends SceneTree
## Graphical before/after profile of the production book, with isolated user data.
var actor: GamePlayer
var samples: Array[float] = []
var measuring := false
var previous := 0
var results: Array[Dictionary] = []
var output := "res://tools/.local/journal-performance"
var size := Vector2i(1920, 1080)

func _initialize() -> void:
	var prefix := "user://journal_profile_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + "_controls.cfg")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument == "--4k": size = Vector2i(3840, 2160)
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if measuring and previous > 0: samples.append((now - previous) / 1000.0)
	previous = now
	return false

func _physics_process(delta: float) -> bool:
	if is_instance_valid(actor): actor.update_character_animation(delta)
	return false

func frames(count: int) -> void:
	for index in count: await process_frame

func sample(label: String) -> void:
	await frames(50)
	samples.clear()
	measuring = true
	await frames(180)
	measuring = false
	samples.sort()
	var record := {"state": label, "p50_ms": samples[samples.size()/2],
		"p95_ms": samples[int(samples.size()*.95)], "p99_ms": samples[int(samples.size()*.99)],
		"max_ms": samples.back(), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}
	results.append(record)
	print("JOURNAL PROFILE ", JSON.stringify(record))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Journal performance needs a graphical renderer")
		quit(1)
		return
	Engine.max_fps = 0
	root.mode = Window.MODE_WINDOWED
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DirAccess.make_dir_recursive_absolute(output)
	var base: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await frames(20)
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.has_journal = true
	actor.teleport_authoritative(Vector3(-29.9, .04, 6.3), 0)
	actor.pickup_world_item_authoritative(&"pistol", {"rounds": 8})
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 40.0
	snapshot.maintenance["base_entered"] = true
	state._broadcast_snapshot(snapshot)
	var journal := root.get_node("QuestJournal")
	journal._bind_controller()
	await frames(120)
	await sample("closed")
	journal.open_journal()
	await create_timer(1.5).timeout
	await sample("notes")
	journal._show_section(true)
	await create_timer(2.0).timeout
	await sample("map")
	journal._on_loupe_requested(true)
	await create_timer(.5).timeout
	await sample("loupe")
	journal.close_journal()
	await create_timer(1.0).timeout
	await sample("closed_again")
	var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"resolution": str(size), "gpu": RenderingServer.get_video_adapter_name(), "results": results}, "\t"))
	file.close()
	journal.force_close()
	current_scene = null
	base.queue_free()
	await frames(4)
	print("JOURNAL PROFILE COMPLETE")
	quit()
