extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	var prefix := "user://journal_maintenance_%d" % OS.get_process_id()
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

func run() -> void:
	Engine.max_fps = 60
	var base: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 25: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor := get_first_node_in_group("local_player") as GamePlayer
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var journal := root.get_node("QuestJournal") as QuestJournalUI
	var snapshot := state.get_snapshot()
	snapshot.day_index = 2
	snapshot.phase = BaseGameplayController.BasePhase.RESTORING_POWER
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 30.0
	snapshot.elevator_backup_installed = true
	snapshot.maintenance = {"base_entered": true, "wires_required": true, "wire_links": []}
	actor.teleport_authoritative(Vector3(0, 1, 0), 0)
	state._broadcast_snapshot(snapshot)
	journal._bind_controller()
	await create_timer(.4).timeout
	check(journal.tasks_label.text == "Проверить что со светом", "old day-two save reveals no repair instructions before visiting the room")
	actor.teleport_authoritative(Vector3(-3.5, 0.5, 17), 0)
	await create_timer(.5).timeout
	check(not state.maintenance.get("generator_fault_discovered", false), "storage side of the doorway does not discover the fault")
	actor.teleport_authoritative(Vector3(-3.5, 0.5, 19), 0)
	await create_timer(.5).timeout
	check(state.maintenance.get("generator_fault_discovered", false), "crossing into the real generator room reveals the shared objective")
	check(journal.tasks_label.text == "Перезапустить работу генератора", "journal updates after arrival without spoiling the wire puzzle")
	actor.teleport_authoritative(Vector3(0, 1, 0), 0)
	var saved := state._make_persistent_snapshot()
	state._broadcast_snapshot(saved)
	check(state.maintenance.get("generator_fault_discovered", false), "discovery survives checkpoint capture and restoration")
	snapshot = state.get_snapshot()
	snapshot.maintenance["wires_required"] = false
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.quest_stage = BaseGameplayController.QuestStage.DELIVERED
	snapshot.maintenance["corpse_recovery"] = {"picked_up": true, "delivered": [0]}
	state._broadcast_snapshot(snapshot)
	check(journal.tasks_label.text.contains("Обследовать тело (в разработке)"), "body inspection is explicitly marked in development")
	check(not state.maintenance.corpse_recovery.get("examined", false), "delivery alone does not finish inspection")
	var bunk: BaseEndDayBunk = base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	actor.teleport_authoritative(bunk.wake_pose.global_position, 0)
	bunk.network_sleep_interact(1, actor)
	check(actor.is_sleeping_in_bunk(), "repaired day-two state permits real bunk sleep")
	await create_timer(.6).timeout
	bunk.cancel_sleep_authoritative(1, actor)
	check(not state.maintenance.corpse_recovery.get("examined", false), "cancelled sleep leaves inspection pending")
	actor.teleport_authoritative(bunk.wake_pose.global_position, 0)
	bunk.network_sleep_interact(1, actor)
	await create_timer(5.5).timeout
	check(state.day_index == 3 and state.maintenance.corpse_recovery.get("examined", false), "completed real five-second night finishes inspection")
	check(journal.tasks_label.text.contains("✓  Обследовать тело (в разработке)"), "morning journal shows completed inspection")
	check(state._make_persistent_snapshot().maintenance.corpse_recovery.get("examined", false), "inspection completion is persisted")
	current_scene = null
	base.queue_free()
	for frame in 4: await process_frame
	print("JOURNAL MAINTENANCE CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
