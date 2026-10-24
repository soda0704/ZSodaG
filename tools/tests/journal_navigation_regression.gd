extends SceneTree
var checks := 0
var failures := 0
var player: GamePlayer
var journal: QuestJournalUI
func _initialize() -> void:
	var prefix := "user://journal_navigation_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, prefix + ".cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	create_timer(120).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func ticks(count: int = 12) -> void:
	for frame in count:
		if is_instance_valid(player): player.update_character_animation(1.0/60.0)
		await physics_frame
	await process_frame
func page_click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var side := 0 if point.x < 700 else 1
	var uv := Vector2(fposmod(point.x,700)/700.0, point.y/986.0)
	var page: MeshInstance3D = journal._page_surfaces[side]
	var location := page.to_global(Vector3((uv.x-.5)*.210,(.5-uv.y)*.303,0))
	var screen := player.body_animator.first_person.view_camera.unproject_position(location)
	screen *= Vector2(root.size)/player.body_animator.first_person.viewport.get_visible_rect().size
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = screen
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await process_frame
func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1600,1000)
	var service = root.get_node("SteamInput")
	service.set_process(false)
	service.set_process_input(false)
	service.native_input_available = false
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await ticks(75)
	root.get_node("GameMenu").force_close_menu()
	player = get_first_node_in_group("local_player")
	var arrival := player.global_position
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	journal = root.get_node("QuestJournal")
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var map = journal._map_sheet
	check(not journal.has_unread_entries(), "unowned journal has no unread indicator")
	check(map.visited.is_empty() and map.plan.texture == null, "arrival reveals no plan before the first step")
	for floor_data in map.atlas.floors:
		check(floor_data.plan != null and floor_data.world_rect.has_area(), "baked plan resource has texture and measured bounds: " + floor_data.level_label)
	player.teleport_authoritative(Vector3(-36,.04,3),0)
	await ticks(25)
	check(map.visited.has(0) and map.visited.size()==1, "first base step reveals only the main floor")
	var pickup = base.get_node("JournalPickups/Journal1")
	player.teleport_authoritative(pickup.global_position + Vector3(0, -.99, -.8),0)
	pickup.network_interact(1,player)
	journal.open_journal()
	await ticks(65)
	journal._show_section(true)
	await ticks(140)
	check(journal.has_unread_entries(), "reading the map does not mark quest notes read")
	journal._show_section(false)
	await ticks(200)
	check(not journal.has_unread_entries(), "actual reading time on current notes clears the badge")
	var saved_reader := JournalReadingStore.new()
	saved_reader.bind_campaign(journal._campaign_id)
	check(not saved_reader.unread(journal._live_record), "read indicator persists locally across reload")
	var next := state.get_snapshot()
	next.day_index = 2
	next.main_breaker_on = true
	state._broadcast_snapshot(next)
	check(journal.has_unread_entries(), "a new quest generates a new unread note")
	check(journal._reading.entries.size()==2, "previous actually observed day remains archived")
	journal._turn_history(-1)
	check(journal._history_day==1 and journal.objective_label.text=="Вернуть базу к жизни", "previous day can be read without reconstructing fictional history")
	check(journal.get_hud_summary().day==2 and journal.get_hud_summary().objective=="Ключ шифрования", "archive browsing never replaces the current HUD objective")
	await ticks(65)
	check(journal.has_unread_entries(), "reading the archive does not clear today's unread note")
	journal.force_close()
	journal.open_journal()
	check(journal._history_day==-1 and not journal._map_open and journal.objective_label.text=="Ключ шифрования", "reopening starts on current notes")
	player.teleport_authoritative(Vector3(-8,-17.96,0),0)
	await ticks(30)
	check(map.visited.has(1) and not map.visited.has(2), "real first-floor contact reveals that floor without revealing lower ones")
	await ticks(40)
	journal._show_section(true)
	await ticks(140)
	check(map.selected==1, "map opens on the player's current visited floor")
	check(map.marker.visible, "player position is projected onto the measured plan")
	journal._on_loupe_requested(true)
	await ticks(22)
	check(journal._inserts.loupe_active,"map enlargement uses the physical magnifier")
	check(map.plan.size.x==510,"magnifier leaves the page at its original scale")
	journal._on_loupe_requested(false)
	await ticks(20)
	check(map._buttons[2].disabled and not map._buttons[2].text.contains(map.atlas.floors[2].title), "unvisited floors cannot be selected and do not leak sector names")
	map.select_floor(0)
	check(not map.marker.visible, "player marker does not bleed onto another floor")
	map.select_floor(1)
	var checkpoint := state.load_saved_snapshot()
	check(checkpoint.maintenance.get("journal_visited",[]).has(1), "floor discoveries are present in the saved shared snapshot")
	var other := JournalReadingStore.new()
	other.bind_campaign("different_expedition")
	check(other.entries.is_empty(), "another expedition does not inherit this journal history")
	if DisplayServer.get_name() != "headless":
		await ticks(70)
		await page_click(journal._notes_tab)
		await ticks(140)
		check(not journal._map_open, "projected physical-page click selects Notes")
		await page_click(journal._map_tab)
		await ticks(140)
		check(journal._map_open, "projected physical-page click opens the folded map")
		await page_click(map._buttons[0])
		check(map.selected==0, "physical-page floor selector responds to projected clicks")
		player.teleport_authoritative(arrival,0)
		await ticks(8)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://tools/.local/journal-atlas-review")
		journal._ink_viewport.get_texture().get_image().save_png("res://tools/.local/journal-atlas-review/map-sheet.png")
		root.get_texture().get_image().save_png("res://tools/.local/journal-atlas-review/map-in-book.png")
		for i in [1,2,3,4,5,6]:
			# Review-only fixture: inspect all sheets without changing gameplay discovery.
			map.update_visited([0,1,2,3,4,5,6])
			map.select_floor(i)
			await ticks(3)
			await RenderingServer.frame_post_draw
			journal._ink_viewport.get_texture().get_image().save_png("res://tools/.local/journal-atlas-review/floor-%d.png" % i)
	journal.force_close()
	base.queue_free()
	await ticks(2)
	print("JOURNAL NAVIGATION: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
