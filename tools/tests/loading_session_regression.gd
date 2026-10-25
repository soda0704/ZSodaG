extends SceneTree
## Real solo arrival, isolated campaign; graphical mode measures the visible cover.
var failures: Array[String] = []
var frames: Array[float] = []
var measuring := false
var previous := 0

func _initialize() -> void:
	var prefix := "user://loading_session_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefix))
	ProjectSettings.set_setting("northern_lab/testing/save_slots_root", prefix + "/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + "/settings.json")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + "/campaign.cfg")
	run.call_deferred()

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if measuring and previous > 0:
		var ms := (now - previous) / 1000.0
		frames.append(ms)
		if ms > 80.0: print("TRANSITION LONG FRAME MS ", ms)
	previous = now
	return false

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures.append(label)

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	var menu = root.get_node("GameMenu")
	menu.get_node("GraphicsQuality").set_advanced_lighting_enabled(true)
	await menu.start_standalone_flow()
	await create_timer(1.0).timeout
	var session = current_scene
	check(session != null and session.has_method("_enter_v3_level"), "real solo session started")
	if not failures.is_empty(): quit(1); return
	measuring = true
	await session._enter_v3_level()
	measuring = false
	check(not session._v3_transition_in_progress, "arrival finishes")
	check(not session.lobby_hud.flight_transition.visible, "cover fades after readiness")
	var level = session.get_node_or_null("V3Level")
	check(level != null, "authored level attached")
	check(session.world_items.get_child_count() > 0, "loot restored before reveal")
	var gi = level.get_node("WorldIndirectLighting")
	check(not gi._loading and gi.get_active_probe_count() > 0, "authored arrival lighting restored")
	check(not gi._loading_data.size(), "temporary lighting references released")
	var state = level.get_node("BaseGameplayController")
	check(state.day_index == 1, "arrival does not advance the campaign")
	for path in ["Floor_0_Base_Blockout", "Floor_Minus1_Control_Security_Blockout", "Floor_Minus2_Life_Support_Blockout", "Floor_Minus3_Trials_Observation_Blockout", "Floor_Minus4_Biocontainment_Blockout", "Floor_Minus5_Expedition_Shaft_Blockout", "Cave_Day7"]:
		check(level.get_node(path).is_inside_tree(), "floor remains attached: " + path)
	frames.sort()
	print("TRANSITION FRAME MS p50 ", frames[frames.size()/2], " p99 ", frames[mini(frames.size()-1, int(frames.size()*.99))], " max ", frames.back())
	current_scene = null
	session.queue_free()
	for frame in 3: await process_frame
	print("RESULT FAILURES ", failures.size())
	quit(0 if failures.is_empty() else 1)
