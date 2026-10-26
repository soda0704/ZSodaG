extends SceneTree
var failures := 0
var checks := 0
var base: Node3D
var state: BaseGameplayController
var preparation: WinchPreparationController
var player: GamePlayer

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://winch_preparation_%d.cfg" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle(frames := 6) -> void:
	for frame in frames: await physics_frame

func visit(control: WinchPreparationControl) -> void:
	var at := control.global_position + control.global_basis.z * 1.4
	at.y = -89.9
	player.teleport_authoritative(at, 0)
	var offset := control.interaction_point.global_position - player.camera.global_position
	player.rotation.y = atan2(-offset.x, -offset.z)
	player.head.rotation.x = atan2(offset.y, Vector2(offset.x,offset.z).length())
	await settle()

func press(control: WinchPreparationControl) -> void:
	await visit(control)
	check(player.get_interaction_target() == control, "production ray reaches " + control.name)
	player.try_authoritative_interaction()

func run() -> void:
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await settle()
	state = base.get_node("BaseGameplayController")
	state.set_process(false)
	preparation = get_first_node_in_group("winch_preparations")
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	root.get_node("GameMenu").force_close_menu()
	for monster in get_nodes_in_group("hostile_monsters"): monster.set_physics_process(false)
	var console: WinchPreparationControl = preparation.get_node("Console")
	var pin: WinchPreparationControl = preparation.get_node("BrakeAssembly/PinControl")
	var brake: WinchPreparationControl = preparation.get_node("BrakeAssembly/BrakeControl")
	state.debug_set_day_authoritative(5)
	await visit(console)
	check(not preparation.use_control(console,1,player), "preparation is unavailable before shaft day")
	state.debug_set_day_authoritative(6)
	player.global_position = base.get_node("Floor_Minus5_Expedition_Shaft_Blockout/InvestigationZone").global_position
	await settle()
	check(state.containment.get("shaft",false) and not state.can_end_current_day(), "visiting hall alone no longer completes day six")
	check(state.get_expedition_objective().tasks.size() == 1 and "пульт" in state.get_expedition_objective().tasks[0].text, "initial objective directs inspection without revealing later steps")
	await visit(pin)
	check(not preparation.use_control(pin,1,player), "pin cannot bypass initial console inspection")
	await press(console)
	check(state.get_winch_preparation().get("inspected",false), "console inspection reveals transport lock")
	check(state.get_expedition_objective().tasks.size() == 2, "inspection reveals pin-removal objective")
	await visit(brake)
	check(not preparation.use_control(brake,1,player), "physical pin prevents premature lever operation")
	await visit(pin)
	player.survival.dead = true
	check(not preparation.use_control(pin,1,player), "dead player cannot remove pin")
	player.survival.dead = false
	check(not preparation.use_control(pin,999,player), "wrong peer cannot use another player's interaction")
	var old_position := player.global_position
	player.global_position += Vector3(10,0,0)
	check(not preparation.use_control(pin,1,player), "remote interaction is rejected")
	player.global_position = old_position
	var wall: Node3D = load("res://tools/tests/fixtures/terminal_occluder.tscn").instantiate()
	root.add_child(wall)
	wall.global_position = player.camera.global_position.lerp(pin.interaction_point.global_position,0.5)
	wall.rotation.y = PI * 0.5
	await settle()
	check(not preparation.use_control(pin,1,player), "wall blocks mechanical interaction")
	wall.queue_free(); await settle()
	await press(pin)
	check(state.get_winch_preparation().get("pin_removed",false) and preparation.pin_animation.is_playing(), "removing pin changes shared state and plays native clip")
	check(not preparation.use_control(pin,1,player), "duplicate peer action cannot repeat extraction")
	await create_timer(1.0).timeout
	check(preparation.get_node("BrakeAssembly/PinRoot").position.distance_to(Vector3(0.48,-0.45,0.2)) < 0.02, "removed pin rests visibly in authored parking clip")
	state.save_progress_authoritative()
	check(state.load_saved_snapshot().maintenance.winch_preparation.get("pin_removed",false), "partial preparation persists")
	await press(brake)
	check(state.get_winch_preparation().get("brake_armed",false) and preparation.brake_animation.is_playing(), "lever arms reserve brake through native animation")
	var lever_audio: AudioStreamPlayer3D = preparation.get_node("BrakeAssembly/LeverAudio")
	check(lever_audio.stream.resource_path.ends_with("winch_brake_lever.ogg") and not lever_audio.stream.loop and lever_audio.playing and lever_audio.bus == &"Machinery", "user lever sound plays once through machinery mixer")
	await create_timer(0.9).timeout
	check(preparation.get_node("BrakeAssembly/LeverPivot").rotation.z > 0.5, "armed lever has distinct visible position")
	await press(console)
	check(state.get_winch_preparation().get("testing",false) and not state.can_end_current_day(), "test is timed and cannot complete day immediately")
	state.save_progress_authoritative()
	var interrupted := state.load_saved_snapshot()
	check(not interrupted.maintenance.winch_preparation.get("testing",true) and not interrupted.maintenance.winch_preparation.get("tested",false), "loading during test requires retry, not automatic completion")
	var snapshot := state.get_snapshot()
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot)
	await settle()
	check(not state.get_winch_preparation().get("testing",true) and not state.is_winch_prepared(), "power failure aborts test without losing mechanical steps")
	snapshot = state.get_snapshot(); snapshot.elevator_backup_installed = true
	state._broadcast_snapshot(snapshot)
	check(not state.main_breaker_on and preparation.service_light.visible,"installed solar reserve powers preparation controls with mains off")
	await press(console)
	await create_timer(preparation.test_duration+0.15).timeout
	check(state.is_winch_prepared(), "solar-powered brake test completes the winch preparation")
	snapshot = state.get_snapshot(); snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	check(state.can_end_current_day(),"normal day-end rules still require the base's main power")
	check(preparation.get_node("Console/StatusGreen").visible and not preparation.get_node("Console/StatusRed").visible, "green indicator confirms successful test")
	check(not preparation.winch.is_powered and not preparation.winch.request_floor(1), "prepared cage still waits until day seven")
	check("отдохнуть" in state.get_expedition_objective().note, "journal sends prepared team back to rest")
	state.save_progress_authoritative()
	check(state.load_saved_snapshot().maintenance.winch_preparation.tested, "successful test is saved")
	state.debug_set_day_authoritative(7)
	check(preparation.winch.is_powered, "prepared day-seven expedition enables descent")
	# Initial snapshot restores final poses without replaying historical actions.
	state.applying_initial_snapshot = true
	preparation._on_snapshot(state.get_snapshot())
	state.applying_initial_snapshot = false
	check(not preparation.pin_animation.is_playing() and not preparation.brake_animation.is_playing(), "initial snapshot restores static completed poses")
	check(not lever_audio.playing, "loading armed lever does not replay one-shot audio")
	check(not base.has_node("Floor_Minus5_Expedition_Shaft_Blockout/Stage_05_Primary_Winch_And_Shaft_Hall/Winch_Operator_Station/CaveAccessSign"), "obsolete cave command sign is removed")
	check(preparation.find_children("*","Label3D",true,false).is_empty(), "mechanism has no floating headings or completion captions")
	check(preparation.get_prompt(WinchPreparationControl.Action.CONSOLE).is_empty(), "completed preparation does not add a redundant interaction status")
	var journal = root.get_node("QuestJournal")
	journal._bind_controller(); journal._refresh_content()
	check(journal.get_hud_summary().objective == "За последним уровнем" and "продолжение шахты" in journal.tasks_label.text, "day-seven narrative uses existing HUD and journal together")
	check(journal.get_hud_summary().tasks.size() == 1 and "пока неизвестно" in journal.tasks_label.text, "journal holds narrative while HUD keeps one actionable objective")
	var legacy := ConfigFile.new()
	legacy.load(ExpeditionSaveStore.test_path())
	legacy.set_value("base","day_index",7)
	var legacy_maintenance: Dictionary = legacy.get_value("base","maintenance",{})
	legacy_maintenance.erase("winch_preparation")
	legacy.set_value("base","maintenance",legacy_maintenance)
	legacy.save(ExpeditionSaveStore.test_path())
	check(state.load_saved_snapshot().maintenance.winch_preparation.tested, "old day-seven saves retain cave access without replaying new preparation")
	if "--capture" in OS.get_cmdline_user_args(): await capture()
	state.progress_persistence_enabled = false
	base.queue_free()
	for frame in 4: await process_frame
	print("PREPARATION CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)

func capture() -> void:
	var camera := Camera3D.new()
	base.add_child(camera); camera.current = true
	# The existing HUD fades text out, resizes the card, then fades it back in.
	await create_timer(0.7).timeout
	for control in [preparation.get_node("Console"),preparation.get_node("BrakeAssembly/PinControl")]:
		var at: Vector3 = control.global_position + control.global_basis.z * 1.4
		at.y = -88.35
		camera.global_position = at
		camera.look_at(control.global_position)
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-preparation-"+control.name+".png"))
