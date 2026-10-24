extends SceneTree
var failures := 0
var checks := 0
var actor: GamePlayer
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://first_entry_%d.cfg" % OS.get_process_id())
	create_timer(100).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func ticks(count: int = 12) -> void:
	for frame in count: await physics_frame
	await process_frame
func run() -> void:
	Engine.max_fps = 60
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await ticks(90)
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var entry = base.get_node("BaseFirstEntry")
	var journal = root.get_node("QuestJournal")
	var hud = actor.get_node("PlayerUI/NorthernLabHUD")
	check(not state.has_entered_base(), "helicopter arrival does not reveal the base")
	check(journal.objective_label.text == "Выяснить что тут произошло", "arrival journal uses requested unknown objective")
	check(journal.tasks_label.text.is_empty() and not journal._quest_card.visible, "arrival journal reveals neither repairs nor fuel photo")
	hud.refresh_state()
	check(hud.view_state.quest.objective == journal.objective_label.text, "HUD and journal share initial objective")
	var layout: Dictionary = hud.objective_layout(journal.get_hud_summary())
	check(not layout.empty and layout.title == "Выяснить что тут произошло" and layout.rows.is_empty(), "title-only objective renders as an active task")
	var arrival: Vector3 = actor.global_position
	actor.teleport_authoritative(Vector3(-39, .04, 3), 0)
	await ticks()
	check(not state.has_entered_base(), "outside the western entrance remains unknown")
	actor.teleport_authoritative(Vector3(-36, .9, 3), 0)
	await ticks()
	check(not state.has_entered_base(), "airborne feet above the base do not count as a step")
	actor.teleport_authoritative(Vector3(-36, .04, 3), 0)
	await ticks()
	check(entry._standing_on_base(actor), "native entrance floor is detected at the player's feet")
	check(state.has_entered_base(), "first actual base-floor step reveals the quest")
	check(journal.objective_label.text == "Вернуть базу к жизни" and not journal.tasks_label.text.is_empty() and journal._quest_card.visible, "existing journal quest and illustration reveal after entry")
	hud.refresh_state()
	check(hud.view_state.quest.objective == "Вернуть базу к жизни", "HUD updates from the same shared snapshot")
	var discovered := state.get_snapshot()
	check(bool(discovered.maintenance.get("base_entered", false)), "discovery travels in persistent shared snapshot")
	actor.teleport_authoritative(arrival, 0)
	await ticks()
	check(state.has_entered_base(), "returning to helicopter does not hide a discovered quest")
	state.save_progress_authoritative()
	var saved := state.load_saved_snapshot()
	check(bool(saved.get("maintenance", {}).get("base_entered", false)), "disk save retains the discovery flag")
	state.maintenance.clear()
	state._apply_snapshot(saved)
	check(state.has_entered_base(), "restoring discovery snapshot keeps the revealed state")
	state.maintenance.clear()
	state.day_index = 2
	check(state.has_entered_base(), "legacy later-day saves remain revealed")
	state.day_index = 1
	state.fuel_delivered = true
	check(state.has_entered_base(), "legacy progressed first-day saves remain revealed")
	state.fuel_delivered = false
	check(not state.has_entered_base(), "new first-day reset returns to unknown objective")
	actor.teleport_authoritative(Vector3(-36, .04, 3), 0)
	await ticks()
	check(state.has_entered_base(), "entry detection still works after resetting the expedition")
	base.queue_free()
	await ticks(2)
	print("BASE FIRST ENTRY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
