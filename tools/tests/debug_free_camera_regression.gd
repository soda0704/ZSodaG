extends SceneTree

var failures := 0
var checks := 0


func _initialize() -> void:
	if "--host" in OS.get_cmdline_user_args() or "--client" in OS.get_cmdline_user_args():
		var probe := NetworkProbe.new()
		probe.name = "FreeCameraNetworkProbe"
		root.add_child.call_deferred(probe)
	else:
		run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)


func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var console = root.get_node("DeveloperConsole")
	check(console.execute("/freecam").contains("загрузите"), "freecam without a loaded player gives a useful message")
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	var remote: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
	remote.setup(2, "Remote", Vector3(3, 0, 0), Color.WHITE)
	arena.get_node("Players").add_child(remote)
	remote.set_physics_process(false)
	remote.survival.set_physics_process(false)
	for variant_id in [0, 1]:
		var player: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		player.setup(1, "Freecam regression", Vector3.ZERO, Color.WHITE, 0.4, variant_id)
		arena.get_node("Players").add_child(player)
		player.survival.set_physics_process(false)
		for i in 6:
			await physics_frame
		player.set_physics_process(false)
		var body_position := player.global_position
		var body_view := Vector2(player._input_yaw, player._input_pitch)
		var freecam = player.debug_free_camera
		console.set_open(true)
		check(console.execute("/freecam").contains("включена"), "variant %d console enables freecam" % variant_id)
		check(freecam.current and not player.camera.current, "freecam becomes the active world camera")
		check(freecam.global_position.is_equal_approx(player.camera.global_position), "camera starts at the player's current view")
		check(not remote.is_debug_free_camera_active(), "another player does not get a free camera")
		check(not freecam._can_control(), "opening console suspends camera control")
		check(not player.body_animator.first_person.overlay.visible, "first-person hands are hidden immediately")
		var visible_body := true
		for mesh: MeshInstance3D in player.body_animator.model.find_children("*", "MeshInstance3D", true, false):
			visible_body = visible_body and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and (mesh.layers & freecam.cull_mask) != 0
		check(visible_body, "variant %d full body and equipment are visible to inspection camera" % variant_id)
		if DisplayServer.get_name() != "headless":
			console.set_open(false)
			freecam.global_position = player.global_position + Vector3(0.6, 1.4, -3.0)
			freecam.look_at(player.global_position + Vector3.UP * 1.0)
			for i in 5:
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/freecam-variant-%d.png" % variant_id)
			console.set_open(true)
		console.execute("/freecam speed 12")
		check(freecam.speed == 12.0, "camera speed is configurable independently of walking")
		for value in ["oops", "0", "101", "nan", "inf"]:
			console.execute("/freecam speed " + value)
		check(freecam.speed == 12.0, "invalid camera speeds cannot change the current speed")
		console.execute("/freecam speed reset")
		check(freecam.speed == 5.0, "speed reset restores five metres per second")
		console.set_open(false)
		# Inject the same actions that feed real gameplay, including weapon polling.
		player.pickup_world_item_authoritative(&"pistol", {})
		# Physics is disabled in this fixture: feed the new held state to the
		# presentation explicitly, as normal player physics does in the game.
		player.update_character_animation(1.0 / 60)
		var ammo_before := player.weapon.rounds
		Input.action_press("move_forward")
		Input.action_press("jump")
		Input.action_press("weapon_attack")
		player.collect_local_input()
		player.collect_local_look(0.1)
		player.weapon._physics_process(0.1)
		var jump_before := player._jump_serial
		var jump_event := InputEventAction.new()
		jump_event.action = "jump"
		jump_event.pressed = true
		player._unhandled_input(jump_event)
		check(player._input_move == Vector2.ZERO and not player._input_sprint and player._jump_serial == jump_before, "flight keys never move or jump the body")
		check(player.weapon.rounds == ammo_before, "weapon polling cannot shoot during inspection")
		root.get_node("QuestJournal").open_journal()
		check(not player._is_journal_open(), "journal cannot take camera controls during inspection")
		Input.action_release("move_forward")
		Input.action_release("jump")
		Input.action_release("weapon_attack")
		freecam.set_process(false)
		var start: Vector3 = freecam.global_position
		freecam.move_camera(1.0, Vector2(0, -1), 0.0, false)
		check(is_equal_approx(freecam.global_position.distance_to(start), 5.0), "camera travels at configured speed without collision constraints")
		start = freecam.global_position
		freecam.move_camera(1.0, Vector2.ZERO, 1.0, true)
		check(is_equal_approx(freecam.global_position.y - start.y, 15.0), "vertical flight and Shift acceleration use world up")
		freecam._look(Vector2(0.6, 0.3))
		check(player.global_position.is_equal_approx(body_position) and Vector2(player._input_yaw, player._input_pitch).is_equal_approx(body_view), "camera translation and rotation leave body position and look unchanged")
		# Console target capture must follow the detached view, including empty space.
		freecam.global_position = Vector3(100, 100, 100)
		freecam.rotation = Vector3.ZERO
		console.capture_target()
		check(console.target_point.is_equal_approx(Vector3(100, 100, 97)), "console target capture uses detached camera origin")
		console.execute("/freecam on")
		check(freecam.global_position.is_equal_approx(Vector3(100, 100, 100)), "explicit on is idempotent and preserves inspection position")
		console.execute("/freecam invalid")
		check(player.is_debug_free_camera_active(), "invalid toggle syntax does not switch cameras")
		console.execute("/freecam off")
		check(player.camera.current and not freecam.current and player.global_position.is_equal_approx(body_position), "off returns to original body without teleporting it")
		var hidden_body := true
		for mesh: MeshInstance3D in player.body_animator.model.find_children("*", "MeshInstance3D", true, false):
			hidden_body = hidden_body and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		check(hidden_body and player.crosshair.visible, "return restores normal owner body visibility and crosshair")
		for i in 3:
			await process_frame
		check(player.body_animator.first_person.overlay.visible, "return restores first-person hand composite")
		console.execute("/freecam on")
		player.survival.dead = true
		freecam._process(0.01)
		check(not player.is_debug_free_camera_active() and not player.crosshair.visible, "death exits camera mode without restoring living HUD")
		check(console.execute("/freecam on").contains("живому"), "dead player cannot enable freecam")
		player.survival.dead = false
		console.execute("/freecam on")
		player._is_sleeping_in_bunk = true
		freecam._process(0.01)
		check(not player.is_debug_free_camera_active(), "sleep exits camera mode")
		player._is_sleeping_in_bunk = false
		console.execute("/freecam on")
		player.queue_free()
		await process_frame
		check(not is_instance_valid(freecam), "scene/player removal frees detached camera too")
	remote.queue_free()
	arena.queue_free()
	await process_frame
	print("FREECAM CHECKS ", checks, " FAILURES ", failures)
	quit(0 if failures == 0 else 1)


class NetworkProbe extends Node:
	var host := false
	var world: Node3D
	var client_report: Dictionary = {}
	var failures := 0

	func _ready() -> void:
		run.call_deferred()

	func check(ok: bool, label: String) -> void:
		print("PASS " if ok else "FAIL ", label)
		if not ok:
			failures += 1

	func run() -> void:
		host = "--host" in OS.get_cmdline_user_args()
		if not host and DisplayServer.get_name() == "headless":
			print("Network client requires a rendered window to test captured mouse input; omit --headless.")
			get_tree().quit(1)
			return
		Engine.max_fps = 60
		get_node("/root/GameMenu").force_close_menu()
		world = load("res://tools/tests/fixtures/character_network_session.tscn").instantiate()
		get_tree().root.add_child(world)
		var peer := ENetMultiplayerPeer.new()
		var error := peer.create_server(28753, 1, 4) if host else peer.create_client("127.0.0.1", 28753, 4)
		check(error == OK, "real ENet transport starts")
		if error != OK:
			get_tree().quit(1)
			return
		multiplayer.multiplayer_peer = peer
		if not host:
			return
		world._on_session_ready(true)
		var deadline := Time.get_ticks_msec() + 15000
		while world.players.get_child_count() < 2 and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		check(world.players.get_child_count() == 2, "two peers join the production player roster")
		if world.players.get_child_count() < 2:
			get_tree().quit(1)
			return
		await get_tree().create_timer(0.4).timeout
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		var remote: GamePlayer = world.players.get_children().filter(func(actor): return not actor.is_local_player())[0]
		var local_start := local.global_position
		var remote_start := remote.global_position
		get_node("/root/DeveloperConsole").execute("/freecam on")
		check(local.is_debug_free_camera_active() and remote.debug_free_camera == null, "host command affects only host camera")
		inspect.rpc_id(remote.owner_peer_id)
		while client_report.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
		check(not client_report.is_empty(), "client completes local camera inspection")
		check(client_report.get("enabled", false), "client console enables its own camera without server command routing")
		check(client_report.get("moved", false), "client camera really flies using gameplay input actions")
		check(client_report.get("body_still", false), "client prediction leaves body position and look unchanged")
		check(client_report.get("returned", false), "client returns to its own first-person camera")
		check(remote.global_position.distance_to(remote_start) < 0.05, "server observes stationary client body during camera flight")
		check(local.global_position.distance_to(local_start) < 0.05 and local.is_debug_free_camera_active(), "client command does not change host body or camera mode")
		get_node("/root/DeveloperConsole").execute("/freecam off")
		print("FREECAM NETWORK FAILURES ", failures)
		finish.rpc_id(remote.owner_peer_id, 0 if failures == 0 else 1)
		await get_tree().create_timer(0.2).timeout
		get_tree().quit(0 if failures == 0 else 1)

	@rpc("authority", "call_remote", "reliable")
	func inspect() -> void:
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		var deadline := Time.get_ticks_msec() + 5000
		while local == null and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.1).timeout
			local = get_tree().get_first_node_in_group("local_player")
		if local == null:
			report.rpc_id(1, {"enabled": false})
			return
		var console := get_node("/root/DeveloperConsole")
		var result: String = console.execute("/freecam on; /freecam speed 8")
		var freecam = local.debug_free_camera
		var enabled: bool = local.is_debug_free_camera_active() and result.contains("включена") and freecam.speed == 8.0
		var body_start := local.global_position
		var look_start := Vector2(local._input_yaw, local._input_pitch)
		var camera_start: Vector3 = freecam.global_position
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.action_press("move_forward")
		Input.action_press("jump")
		await get_tree().create_timer(0.5).timeout
		Input.action_release("move_forward")
		Input.action_release("jump")
		var moved: bool = freecam.global_position.distance_to(camera_start) > 2.0
		print("CLIENT CAMERA TRAVEL ", freecam.global_position.distance_to(camera_start), " m")
		var body_still := local.global_position.distance_to(body_start) < 0.05 and Vector2(local._input_yaw, local._input_pitch).is_equal_approx(look_start)
		console.execute("/freecam off")
		report.rpc_id(1, {"enabled": enabled, "moved": moved, "body_still": body_still, "returned": local.camera.current and not local.is_debug_free_camera_active()})

	@rpc("any_peer", "call_remote", "reliable")
	func report(values: Dictionary) -> void:
		client_report = values

	@rpc("authority", "call_remote", "reliable")
	func finish(code: int) -> void:
		print("FREECAM CLIENT COMPLETE ", code)
		get_tree().quit(code)
