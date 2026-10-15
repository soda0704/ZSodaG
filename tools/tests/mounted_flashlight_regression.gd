extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle(seconds := 0.35) -> void: await create_timer(seconds).timeout
func run() -> void:
	Engine.max_fps = 60
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960,540)
	root.get_node("GameMenu").force_close_menu()
	var input := root.get_node("SteamInput")
	input.set_process(false)
	input.set_process_input(false)
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for variant in [0,1]:
		var player := load("res://scenes/characters/player.tscn").instantiate() as GamePlayer
		player.name = "1"
		player.setup(1,"",Vector3(0,0.1,0),Color.WHITE,0,variant)
		arena.get_node("Players").add_child(player)
		player.survival.set_physics_process(false)
		player._has_flashlight = true
		player._battery_charge = 1.0
		player.tape_count = 2
		for kind in [&"m4a1"]:
			player.apply_held_item_inventory(kind,{})
			player.weapon.apply_state(kind,12,0)
			check(player.perform_inventory_action_authoritative(&"mount_light"), "mount via existing inventory: %d %s" % [variant,kind])
			player._flashlight_enabled = true
			for aim in [false,true]:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if aim: Input.action_press("weapon_aim")
				else: Input.action_release("weapon_aim")
				player._aiming = aim
				await settle(0.65)
				for model in [player.body_animator.model, player.body_animator.first_person_model]:
					var sockets := model.get_node("Skeleton3D/RightHand/Equipment") as Node3D
					var gun := sockets.get_node(String(kind)) as Node3D
					var lamp := sockets.get_node("MountedLamp") as Node3D
					var beam := lamp.get_node("Beam") as SpotLight3D
					var expected := gun.get_node("FlashlightMount") as Node3D
					check((-beam.global_basis.z).normalized().dot((-gun.global_basis.z).normalized()) > 0.999 and lamp.global_position.distance_to(expected.global_position)<0.001, "beam follows authored weapon socket %d %s aim=%s %s" % [variant,kind,aim,model.name])
					check(not lamp.has_node("BridgeBack") and not lamp.has_node("BridgeFront") and lamp.get_node("TapeBack").mesh is ArrayMesh, "attachment uses two saved tape ribbons without blocks")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://tools/.local/mounted-light-%d-%s-%s.png" % [variant,kind,aim])
			check(player.weapon._mounted_beam.visible, "equipped charged mounted light is on")
			check(player.perform_inventory_action_authoritative(&"detach_light"), "detach uses existing inventory")
			await settle()
		player.queue_free()
		await process_frame
		await process_frame
	arena.queue_free()
	await process_frame
	print("MOUNTED FLASHLIGHT CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)
