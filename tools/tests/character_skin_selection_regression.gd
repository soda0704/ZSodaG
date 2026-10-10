extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)


func ticks(count: int = 6) -> void:
	for i in count:
		await physics_frame


func run() -> void:
	Engine.max_fps = 60
	var menu = root.get_node("GameMenu")
	# Only this process sees the test settings directory; real preferences and
	# expedition checkpoints are never written by the test.
	var original_local_app_data := OS.get_environment("LOCALAPPDATA")
	OS.set_environment("LOCALAPPDATA", ProjectSettings.globalize_path("res://tools/.local/skin-test-settings"))
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://skin_selection_regression_%d.cfg" % OS.get_process_id())
	for variant_id in [0, 1]:
		if current_scene != null:
			current_scene.queue_free()
			current_scene = null
			await process_frame
		menu._settings_data["CharacterVariant"] = 1 - variant_id
		var main = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(main)
		current_scene = main
		var selector = main.get_node("SkinCard")
		check(selector.option.item_count == 2 and selector.option.get_selected_id() == 1 - variant_id, "main menu displays both skins and restores preference")
		selector.option.select(variant_id)
		selector.option.item_selected.emit(variant_id)
		check(menu.get_character_variant_id() == variant_id and int(menu.load_settings_data().get("CharacterVariant", -1)) == variant_id, "UI selection persists variant %d in settings" % variant_id)
		check(selector.model.scene_file_path.contains("tactical_a" if variant_id == 0 else "tactical_b"), "preview uses actual selected world character")
		check(selector.preview.world_3d != root.world_3d, "preview is isolated from gameplay world")
		main.set_menu_enabled(false)
		check(main.skin_option.disabled, "starting a game locks skin selection with other menu actions")
		main.set_menu_enabled(true)
		if DisplayServer.get_name() != "headless":
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/skin-menu-%d.png" % variant_id)
		await menu.start_standalone_flow()
		await ticks()
		var session = current_scene
		var player: GamePlayer = get_first_node_in_group("local_player")
		player.survival.debug_invincible = true
		check(session.is_solo_arrival() and player.character_variant_id == variant_id, "new solo game spawns selected variant %d in helicopter" % variant_id)
		check(player.body_animator.variant.variant_id == variant_id and player.body_animator.first_person_model.scene_file_path.contains("tactical_a" if variant_id == 0 else "tactical_b"), "body and first-person arms both use selected variant")
		await session._enter_v3_level()
		check(player.character_variant_id == variant_id and int(session._player_roster[1].character_variant) == variant_id, "landing preserves selected skin in player and network roster")
		player.survival._respawn()
		await ticks()
		check(player.character_variant_id == variant_id and player.body_animator.variant.variant_id == variant_id, "respawning preserves selected skin")
		var state: BaseGameplayController = get_first_node_in_group("base_gameplay_controller")
		state.save_progress_authoritative()
		await menu.start_standalone_flow(true)
		await ticks()
		player = get_first_node_in_group("local_player")
		check(current_scene.resume_base_on_start and player.character_variant_id == variant_id, "continue expedition also uses selected skin")
		player.survival.debug_invincible = true
	# Server-side spawn also validates peer choices and allows matching skins.
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
		await process_frame
	var session = load("res://tools/tests/fixtures/character_network_session.tscn").instantiate()
	root.add_child(session)
	menu._settings_data["CharacterVariant"] = 1
	session.spawn_player_for_peer(1)
	session.spawn_player_for_peer(2, 1)
	check(session.players.get_node("1").character_variant_id == 1 and session.players.get_node("2").character_variant_id == 1, "co-op players can choose the same skin")
	session.spawn_player_for_peer(2, 0)
	check(session.players.get_node("2").character_variant_id == 1, "duplicate spawn request cannot replace an existing character")
	menu._settings_data["CharacterVariant"] = 99
	check(menu.get_character_variant_id() == 1, "out-of-range saved preference cannot select nonexistent resources")
	OS.set_environment("LOCALAPPDATA", original_local_app_data)
	print("SKIN SELECTION CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
