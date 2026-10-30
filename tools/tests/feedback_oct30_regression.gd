extends SceneTree
## Real production scene, isolated saves; screenshots require a graphical renderer.
var checks := 0
var failures := 0
var base: Node3D
var output := "res://tools/.local/feedback-fixes-2026-10-30"
func _initialize() -> void:
	var prefix := "user://feedback_oct30_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	create_timer(100).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func frames(count: int) -> void:
	for i in count: await physics_frame
func capture(label: String, at: Vector3, target: Vector3) -> void:
	if DisplayServer.get_name() == "headless": return
	var camera := Camera3D.new()
	base.add_child(camera)
	camera.global_position = at
	camera.look_at(target)
	camera.make_current()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	camera.queue_free()
	await process_frame
func run() -> void:
	Engine.max_fps = 60
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await frames(20)
	root.get_node("GameMenu").force_close_menu()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	var data := state.get_snapshot()
	data.day_index = 2; data.main_breaker_on = true; data.fuel_delivered = true; data.fuel_liters = 40
	data.maintenance.erase("radio_note_read")
	state._broadcast_snapshot(data)
	check(RadioTowerProgress.tasks(state).is_empty(), "#26 no radio objective before discovering note")
	var note = base.get_node("Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/RadioAccessNote")
	player.teleport_authoritative(note.global_position + note.global_basis.z * 1.3 - Vector3.UP * 1.2)
	await frames(8)
	check(RadioTowerProgress.act(state, &"note", 1, note), "#26 actual note can be read")
	check(RadioTowerProgress.tasks(state).contains(str(state.maintenance.radio_pin)), "#26 reading reveals actual shared code")
	var saved := state.get_snapshot()
	state._apply_snapshot(saved, true)
	check(not RadioTowerProgress.tasks(state).is_empty(), "#26 discovery survives snapshot restore")
	await capture("note-fixed", note.global_position + note.global_basis.z * 1.2, note.global_position)
	data = state.get_snapshot(); data.day_index = 6; data.containment = {}
	state._broadcast_snapshot(data)
	var hives = base.get_node("Cave_Day7/HiveEncounter")
	check(hives.hives.size() == 3 and hives.hives.all(func(h): return h.visible), "#33 three visible hives on reported day six")
	hives.damage_hive(0, 999)
	check(hives.get_health(0) == hives.starting_health and not state.containment.get("cave_hives_found", false), "#33 day gate still rejects damage and premature quest progress")
	player.teleport_authoritative(Vector3(285,-155,-8.7), 0)
	player._flashlight_enabled = true; player._refresh_equipment_visuals()
	await frames(8)
	await capture("hives-day6-fixed", Vector3(285,-153.5,-8.7), Vector3(293,-154.1,-2.6))
	data = state.get_snapshot(); data.day_index = 5
	state._broadcast_snapshot(data)
	var monster = base.get_node("ContainmentEncounter/Monster4")
	player.teleport_authoritative(Vector3(20, .1, 10), 0)
	var initial: Vector3 = monster.global_position
	await frames(600)
	check(absf(monster.global_position.y + 54) < .2, "#29 evolution remains supported on floor three after ten seconds")
	check(monster.global_position.distance_to(initial) > .5, "#29 existing AI actually patrols on floor three")
	var shape: CollisionShape3D = monster.get_node("CollisionShape3D")
	check(absf(shape.position.y - shape.shape.height * .5) < .001, "#29 capsule base matches model root instead of sinking 0.775m")
	await capture("evolution-floor3-fixed", monster.global_position + Vector3(4, 1.8, 3), monster.global_position + Vector3.UP)
	for corpse in get_nodes_in_group("medical_corpses"):
		print("IDLE CORPSE ", corpse.corpse_id, " ", corpse.ragdoll.root_body.global_position)
		check(corpse.ragdoll.root_body.global_position.y > -39, "#25/#27 corpse remains on its original floor while player is elsewhere")
	var notice = root.get_node("GameMenu/SaveNotification")
	notice._bind_controller(); notice._on_save_started("manual"); notice._on_save_finished("manual", true)
	await create_timer(.8).timeout
	check(notice.visible and notice.title.text == "Игра сохранена", "#18 success is visible after real presentation delay")
	var panel: Control = notice.get_node("Notice")
	check(panel.get_global_rect().position.y < 100, "#18 notice moved to top center")
	await capture("save-notice-fixed", Vector3(24,1.7,-3), Vector3(24,1,-6))
	await create_timer(2.5).timeout
	check(notice.visible, "#18 confirmation remains readable beyond former 2.4 second duration")
	await create_timer(1.6).timeout
	check(not notice.visible, "#18 notice still clears automatically")
	current_scene = null; base.queue_free(); await frames(4)
	print("FEEDBACK OCT30 CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
