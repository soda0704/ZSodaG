extends SceneTree

const SAVE := "user://journal_ui_test.cfg"
var failed := false
var visual := false

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, SAVE)
	visual = OS.get_cmdline_user_args().has("visual")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("JOURNAL_UI_TEST: " + message)

func capture(name_value: String) -> void:
	if not visual:
		return
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-" + name_value + ".png"))

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	change_scene_to_file("res://scenes/ui/main_menu.tscn")
	await scene_changed
	if visual:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
	var main := current_scene
	check(not main.delete_save_button.visible, "Delete action hidden when no save exists")
	await capture("Menu-NoSave")
	var config := ConfigFile.new()
	config.set_value("save", "version", 1)
	config.set_value("base", "day_index", 2)
	config.save(SAVE)
	main.refresh_save_ui()
	check(main.delete_save_button.visible and not main.delete_save_button.disabled, "Existing save exposes deletion")
	check(main.delete_save_button.custom_minimum_size.y == main.single_player_button.custom_minimum_size.y, "Delete action has a full-sized hit target")
	await capture("Menu-WithSave")
	BaseGameplayController.delete_progress_save()
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player: Node3D = world.get_node("Players/1")
	player.set_physics_process(false)
	var state: BaseGameplayController = world.get_node("V3Level/BaseGameplayController")
	state._apply_snapshot({"day_index": 2, "fuel_delivered": true, "main_breaker_on": true, "quest_stage": 3})
	player.apply_inventory_snapshot({"has_flashlight": true, "held_item": &"fuel_can", "battery_charge": 0.42, "spare_batteries": [1.0, 0.6], "revision": 50})
	var journal := root.get_node("QuestJournal")
	journal.open_journal()
	check(not journal.replace_button.visible, "Replacement hidden before battery depletion")
	check(not journal.help_panel.visible, "Controls hidden until requested")
	check(journal._cards[&"battery"].detail.text == "×2", "Battery card shows a count, not an always-visible charge dump")
	check(journal.inventory_label.text.is_empty(), "Unselected inventory has no status paragraphs")
	await capture("Journal-Photos")
	if visual:
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		await capture("Journal-1080p")
		DisplayServer.window_set_size(Vector2i(1280, 720))
	if visual:
		for card: JournalPhotoCard in journal._cards.values():
			check(card.picture.texture != null, "Every equipment photo must be available")
		check(journal._quest_card.picture.texture != null, "Quest photo must be available")
	journal._select_item(&"battery")
	check(journal.inventory_label.text.contains("60%"), "Individual charges are available on selection")
	var total_before := total_charge(player.get_inventory_snapshot())
	check(player.perform_inventory_action_authoritative(&"replace_battery"), "Early replacement is still allowed by explicit input")
	var after: Dictionary = player.get_inventory_snapshot()
	check(after.spare_batteries.size() == 2 and after.spare_batteries.has(0.42), "Nonempty old battery returns to inventory")
	check(is_equal_approx(total_before, total_charge(after)), "Replacement preserves total usable charge")
	for index in 5:
		player.perform_inventory_action_authoritative(&"replace_battery")
	check(player.get_inventory_snapshot().spare_batteries.size() == 2, "Repeated replacement cannot eat spare cells")
	var depleted: Dictionary = player.get_inventory_snapshot()
	depleted.battery_charge = 0.0
	player.apply_inventory_snapshot(depleted)
	journal._refresh_inventory()
	check(journal.replace_button.visible, "Replacement appears when battery is empty and spares exist")
	await capture("Journal-Depleted")
	journal.replace_button.grab_focus()
	journal._inventory_action(&"replace_battery")
	check(not journal.replace_button.visible, "Successful replacement removes the action")
	check(player.get_inventory_snapshot().spare_batteries.size() == 1, "Empty spent cell is not returned")
	check(root.gui_get_focus_owner() != null and root.gui_get_focus_owner().is_visible_in_tree(), "Focus recovers when contextual action disappears")
	var full: Dictionary = player.get_inventory_snapshot()
	full.spare_batteries = []
	for index in 20:
		full.spare_batteries.append(1.0 - index * 0.025)
	full.battery_charge = 0.1
	player.apply_inventory_snapshot(full)
	check(player.perform_inventory_action_authoritative(&"replace_battery"), "Replacement works with a full pocket")
	check(player.get_inventory_snapshot().spare_batteries.size() == 20, "Returning old cell does not overflow or truncate a full pocket")
	journal._select_item(&"battery")
	await capture("Journal-FullPocket")
	journal._toggle_help()
	await capture("Journal-Help")
	journal.close_journal()
	check(journal.is_journal_open() and not journal.help_panel.visible, "Back closes help without closing the book")
	journal.force_close()
	world.free()
	BaseGameplayController.delete_progress_save()
	print("JOURNAL_UI_TEST: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)

func total_charge(data: Dictionary) -> float:
	var result := float(data.battery_charge)
	for cell: Variant in data.spare_batteries:
		result += float(cell)
	return result
