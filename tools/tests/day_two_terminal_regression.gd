extends SceneTree
var failures := 0
var checks := 0
var capture := false
var state: BaseGameplayController
var base: Node3D
var player: GamePlayer
var hub: DayTwoTerminal
var vault: DayTwoTerminal
var save_path: String
func _initialize() -> void:
	save_path = "user://terminal_regression_%d.cfg" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	capture = "--capture" in OS.get_cmdline_user_args()
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func settle() -> void:
	for frame in 6: await physics_frame
func visit(terminal: DayTwoTerminal) -> void:
	var facing := terminal.screen.global_basis.z
	facing.y = 0.0
	player.teleport_authoritative(terminal.global_position + facing.normalized() * 2.0, terminal.global_rotation.y)
	player.camera.look_at(terminal.screen.global_position)
	await settle()
func screenshot(label: String) -> void:
	if not capture or DisplayServer.get_name() == "headless": return
	root.get_node("GameMenu").force_close_menu()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/terminal-" + label + ".png")
func boot() -> void:
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await settle()
	state = base.get_node("BaseGameplayController")
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	hub = base.get_node("Floor_0_Base_Blockout/DayTwoTaskTerminal")
	vault = base.get_node("Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/Encryption_Key_Terminal")
func run() -> void:
	Engine.max_fps = 60
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		DisplayServer.window_set_position(Vector2i(-1600, 40))
	await boot()
	check(get_nodes_in_group("quest_terminals").size() == 2, "two authored terminals without runtime duplicates")
	check(hub.get_node("Model").scene_file_path.contains("scifi_terminal") and vault.get_node("Model").scene_file_path.contains("scifi_terminal"), "both levels use supplied terminal asset")
	check(vault.key_visual.get_node("KeyPose/KeyModel").scene_file_path.contains("id_key_lanyard"), "pass key uses supplied lanyard asset")
	check(hub._housing_meshes.size() == 5 and vault._housing_meshes.size() == 5, "all imported emissive surfaces controlled")
	check(hub.screen is Marker3D and hub._display_mesh == hub._housing_meshes[1] and hub._display_mesh.material_override == hub._screen_material, "UI replaces the native screen material without covering its frame with extra geometry")
	check(hub._screen_material != vault._screen_material, "screen material independent per terminal")
	check(not hub._screen_material.get_shader_parameter("powered") and hub.screen_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "first-day outage switches off screen and viewport")
	check(hub._housing_meshes[0].material_override == hub.unpowered_housing_material, "outage disables original model emission too")
	await visit(hub)
	await screenshot("hub-off")
	var snapshot := state.get_snapshot()
	snapshot.day_index = 2
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20.0
	snapshot.quest_stage = BaseGameplayController.QuestStage.OFFERED
	snapshot.elevator_backup_installed = true
	state._broadcast_snapshot(snapshot)
	await settle()
	check(hub._screen_material.get_shader_parameter("powered") and vault._screen_material.get_shader_parameter("powered"), "mains power switches on both screens")
	check(hub.ui.get_node("%System").text.contains("20.0") and hub.ui.get_node("%Heading").text.contains("PASS KEY"), "screen displays live expedition state")
	check(vault.key_visual.visible and not hub.key_visual.visible, "key initially available in vault only")
	await screenshot("hub-offered")
	check(player.get_interaction_target() == hub, "actual interaction ray reaches terminal screen")
	hub.network_interact(2, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "reject mismatched peer")
	player.survival.dead = true
	hub.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "dead player cannot use terminal")
	player.survival.dead = false
	player._is_sleeping_in_bunk = true
	hub.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "sleeping player cannot use terminal")
	player._is_sleeping_in_bunk = false
	player.teleport_authoritative(hub.global_position + Vector3(0, 0, 8), 0)
	hub.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "reject distant player")
	await visit(hub)
	var wall := load("res://tools/tests/fixtures/terminal_occluder.tscn").instantiate() as Node3D
	base.add_child(wall)
	wall.global_position = (player.camera.global_position + hub.screen.global_position) * 0.5
	wall.global_rotation.y = hub.global_rotation.y
	await settle()
	hub.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "wall blocks host-side interaction")
	wall.queue_free()
	await settle()
	player.try_authoritative_interaction()
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "hub cannot advance quest before key is retrieved")
	check(not state.can_end_current_day(), "missing key does not allow early sleep")
	await visit(vault)
	await screenshot("vault-accepted")
	check(player.get_interaction_target() == vault, "vault screen reachable by actual interaction ray")
	var equipped := player.get_inventory_snapshot()
	player.try_authoritative_interaction()
	check(state.quest_stage != BaseGameplayController.QuestStage.COLLECTED, "instant interaction cannot bypass key hold")
	vault._open_session(1)
	vault._command(1, 1, &"quest_begin")
	vault._command(1, 2, &"quest")
	check(state.quest_stage != BaseGameplayController.QuestStage.COLLECTED, "short hold cannot extract key")
	vault._command(1, 3, &"quest_begin")
	await create_timer(1.4).timeout
	vault._command(1, 4, &"quest")
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "production interaction collects shared pass key without accepting a hub mission")
	check(player.get_inventory_snapshot() == equipped, "story key does not displace equipment")
	check(vault.animation_player.current_animation == &"extract", "collection plays authored native extraction clip")
	vault.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "repeated extraction does not advance story twice")
	var extraction_deadline := Time.get_ticks_msec() + 3000
	while vault.animation_player.is_playing() and Time.get_ticks_msec() < extraction_deadline:
		await process_frame
	check(not vault.key_visual.visible, "extracted key disappears at end of native clip")
	await screenshot("vault-collected")
	await visit(hub)
	snapshot = state.get_snapshot()
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot)
	hub.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "blackout prevents delivery despite elevator reserve")
	check(not hub._screen_material.get_shader_parameter("powered") and not vault._screen_material.get_shader_parameter("powered") and vault.screen_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "blackout extinguishes both screens and viewport")
	check(vault._display_mesh.material_override == vault._screen_material and not vault._screen_material.get_shader_parameter("powered"), "original screen mesh retains its material with emission switched off")
	await screenshot("blackout")
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	player.try_authoritative_interaction()
	check(state.quest_stage == BaseGameplayController.QuestStage.DELIVERED, "delivery resumes after mains restored")
	check(hub.animation_player.current_animation == &"deliver", "delivery plays authored insertion clip")
	await create_timer(0.45).timeout
	check(hub.key_visual.visible and not vault.key_visual.visible, "one completed key visual in hub")
	check(state.can_end_current_day(), "delivered key permits existing day completion")
	await screenshot("hub-delivered")
	state.save_progress_authoritative()
	base.queue_free()
	await settle()
	await boot()
	check(state.quest_stage == BaseGameplayController.QuestStage.DELIVERED, "story progress survives save and reload")
	check(hub.key_visual.visible and not vault.key_visual.visible and not hub.animation_player.is_playing(), "reload applies final key state without replaying action")
	snapshot = state.get_snapshot()
	snapshot.day_index = 3
	snapshot.containment = {"level2": true}
	state._broadcast_snapshot(snapshot)
	check(hub.ui.get_node("%Objective").text.contains("отдохните") and not hub.get_interaction_prompt().contains("уровень 3"), "day-three completed investigation does not incorrectly send player to locked level three")
	snapshot.day_index = 2
	snapshot.quest_stage = BaseGameplayController.QuestStage.ACCEPTED
	state._broadcast_snapshot(snapshot)
	await visit(vault)
	vault._open_session(1)
	vault._command(1, 1, &"quest_begin")
	await create_timer(1.4).timeout
	vault._command(1, 2, &"quest")
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "legacy accepted-stage save still allows key extraction")
	var journal = root.get_node("QuestJournal")
	journal._bind_controller()
	journal._refresh_content()
	check(not journal.tasks_label.text.contains("Получить задание") and journal.tasks_label.text.contains("Передать ключ"), "journal lists retrieval and delivery without a hub acceptance task")
	base.queue_free()
	await settle()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("TERMINAL CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
