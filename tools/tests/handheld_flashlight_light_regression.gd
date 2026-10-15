extends SceneTree
var failures := 0
var checks := 0
var owner: GamePlayer
func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://handheld_light_test_settings.json")
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func sample(label: String) -> float:
	await create_timer(0.30).timeout
	# Measure world illumination independently of the journal's bright pages
	# and the viewmodel. This keeps gameplay lights in the world scenario.
	owner.body_animator.first_person.set_external_view(true)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	owner.body_animator.first_person.set_external_view(false)
	img.save_png("res://tools/.local/handheld-light-%s.png" % label)
	var total := 0.0
	var count := 0
	# World wall only; no hand geometry, battery HUD or crosshair.
	for y in range(130, 260, 2):
		for x in range(340, 620, 2):
			var c := img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
			count += 1
	return total / count
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Graphical renderer required"); quit(1); return
	Engine.max_fps = 60; root.size = Vector2i(960, 540)
	root.get_node("GameMenu").force_close_menu()
	var input := root.get_node("SteamInput"); input.set_process(false); input.set_process_input(false)
	var room = load("res://tools/tests/fixtures/flashlight_light_room.tscn").instantiate()
	root.add_child(room); current_scene = room
	for variant in [0, 1]:
		var player := load("res://scenes/characters/player.tscn").instantiate() as GamePlayer
		owner = player
		player.name = "1"; player.setup(1, "", Vector3.ZERO, Color.WHITE, 0, variant)
		room.get_node("Players").add_child(player)
		player.survival.set_physics_process(false)
		player.flashlight.malfunction_enabled = false
		var dark := await sample("%d-dark" % variant)
		player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 1.0})
		var socket := player.flashlight.get_parent()
		var solo := await sample("%d-solo" % variant)
		check(solo > dark + 0.04, "solo torch illuminates actual world wall variant %d" % variant)
		check(String(socket.get_path()).contains("/LeftHand/"), "solo torch stays in left hand")
		player.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 7.0})
		var can := await sample("%d-can" % variant)
		print("WALL LUMA variant=", variant, " off=", dark, " solo=", solo, " can=", can, " beam=", player.flashlight.beam.is_visible_in_tree())
		check(can > dark + 0.04 and can > solo * 0.65, "canister transition keeps real world illumination")
		check(player.flashlight.get_parent() == socket, "picking up canister never reparents the torch")
		var charge := player._battery_charge
		root.get_node("QuestJournal").open_journal()
		await create_timer(0.2).timeout
		var book_dark := await sample("%d-journal" % variant)
		print("JOURNAL LIGHT variant=",variant," wall=",book_dark," charge=",charge," -> ",player._battery_charge," phase=",player._journal_phase)
		check(book_dark < solo * 0.10 and is_equal_approx(player._battery_charge, charge), "stowed journal light neither illuminates nor consumes battery")
		root.get_node("QuestJournal").close_journal()
		await create_timer(0.85).timeout
		var restored := await sample("%d-restored" % variant)
		check(restored > solo * 0.65, "closing journal restores real illumination")
		# Reproduce the old renderer failure independently of inventory: native
		# Light3D can retain its RID while leaving/re-entering a World3D.
		var right := player.body_animator.equipment_socket("FlashlightGrip")
		player.flashlight.reparent(right, false)
		player.flashlight.reparent(socket, false)
		var rebound := await sample("%d-reentered" % variant)
		check(rebound > solo * 0.65, "light re-entry invalidates the renderer scenario cache")
		player.consume_held_item_authoritative(&"fuel_can")
		var empty_right := await sample("%d-empty-right" % variant)
		check(player.flashlight.get_parent() == socket and empty_right > solo * 0.65, "using the main item leaves the same working left-hand torch")
		check(player._battery_charge < charge, "charge drains while the wall really receives light")
		player.queue_free(); await process_frame; await process_frame
	room.queue_free(); await process_frame
	print("HANDHELD LIGHT CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
