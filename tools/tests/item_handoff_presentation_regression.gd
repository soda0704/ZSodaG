extends SceneTree
var actor: GamePlayer
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle(frames := 25) -> void:
	for frame in frames:
		if not actor.is_on_floor():
			actor.velocity = Vector3.DOWN
			actor.move_and_slide()
		actor.update_character_animation(1.0 / 60.0)
		actor.refresh_interaction_prompt()
		await physics_frame
func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/handoff-review/" + label + ".png")
func page_click(journal: QuestJournalUI, control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var side := 0 if point.x < 700 else 1
	var uv := Vector2(fposmod(point.x, 700) / 700.0, point.y / 986.0)
	var page := journal._page_surfaces[side]
	var size: Vector2 = page.mesh.size
	var location := page.to_global(Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0))
	var screen := actor.body_animator.first_person.view_camera.unproject_position(location)
	screen *= Vector2(root.size) / actor.body_animator.first_person.viewport.get_visible_rect().size
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	Input.parse_input_event(motion)
	await process_frame
	var click := InputEventMouseButton.new()
	click.position = screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(click)
	await process_frame
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	Engine.max_fps = 60
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	get_root().get_node("GameMenu").force_close_menu()
	get_root().get_node("SteamInput").set_process(false)
	DirAccess.make_dir_recursive_absolute("res://tools/.local/handoff-review")
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for variant in [0, 1]:
		actor = load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(1, "Offer", Vector3(0, 0.1, 0), Color.WHITE, 0, variant)
		actor.name = "1"
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.handoff.set_physics_process(false)
		for item in [&"tape", &"fuel_can", &"pistol", &"m4a1", &"flashlight", &"flamethrower"]:
			actor.handoff.cancel_authoritative()
			actor.release_held_item_authoritative()
			actor.pickup_world_item_authoritative(item, {})
			check(actor.handoff.start_authoritative(item, item == &"tape"), "presentation offer " + String(item))
			actor.camera.make_current()
			actor.body_animator.set_external_view(false)
			await settle()
			var tree: AnimationTree = actor.body_animator.first_person.tree
			check(float(tree.get("parameters/OfferBlend/blend_amount")) > 0.99, "native first-person offer blend settles")
			check(actor.body_animator.first_person.model.visible, "offered hand remains visible")
			await capture("%d-%s-fp" % [variant, item])
			var camera := Camera3D.new()
			arena.add_child(camera)
			camera.global_position = Vector3(1.7, 1.45, -2.3)
			camera.look_at(Vector3(0, 1.2, -0.2))
			camera.make_current()
			actor.body_animator.set_external_view(true)
			await settle()
			await capture("%d-%s-world" % [variant, item])
			camera.queue_free()
			await process_frame
		actor.handoff.cancel_authoritative()
		actor.release_held_item_authoritative()
		actor.pickup_world_item_authoritative(&"fuel_can", {})
		actor.camera.make_current()
		actor.body_animator.set_external_view(false)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		actor.handoff.set_physics_process(true)
		var middle := InputEventMouseButton.new()
		middle.button_index = MOUSE_BUTTON_MIDDLE
		middle.pressed = true
		Input.parse_input_event(middle)
		await settle(5)
		check(actor.handoff.mode == 1, "actual middle-button press begins a held offer")
		middle.pressed = false
		Input.parse_input_event(middle)
		await settle(2)
		actor.handoff._physics_process(0)
		check(not actor.handoff.is_offering(), "middle-button release retracts the held offer")
		var stick := InputEventJoypadButton.new()
		stick.button_index = JOY_BUTTON_RIGHT_STICK
		stick.pressed = true
		Input.parse_input_event(stick)
		await settle(5)
		check(actor.handoff.mode == 1, "native R3 fallback starts the same held offer")
		stick.pressed = false
		Input.parse_input_event(stick)
		await settle(3)
		check(not actor.handoff.is_offering(), "native R3 release retracts the offer")
		actor.tape_count = 2
		var journal := root.get_node("QuestJournal")
		journal.open_journal()
		await settle(80)
		journal._select_item(&"tape")
		journal._refresh_inventory()
		check(journal.give_button.visible and not journal.give_button.disabled, "native journal exposes Give for a selected pocket item")
		await capture("%d-journal-give-button" % variant)
		await page_click(journal, journal.give_button)
		await settle(70)
		check(actor.handoff.pocket_pose() and not journal.is_journal_open(), "journal closes before the open-palm offer")
		check(actor.tape_count == 2, "journal offer does not consume the item")
		await capture("%d-journal-to-palm" % variant)
		middle.pressed = true
		Input.parse_input_event(middle)
		await settle(2)
		check(not actor.handoff.is_offering() and actor.tape_count == 2, "single middle click cancels pocket offer without losing item")
		middle.pressed = false
		Input.parse_input_event(middle)
		actor.queue_free()
		await create_timer(0.2).timeout
	arena.queue_free()
	await create_timer(0.3).timeout
	print("HANDOFF PRESENTATION CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
