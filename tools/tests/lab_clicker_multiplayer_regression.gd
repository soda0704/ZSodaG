extends "res://tools/tests/day_two_terminal_multiplayer_regression.gd"
var events_seen := 0
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://clicker_coop_%d.cfg" % OS.get_process_id())
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real ENet peer")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not host:
		check(await until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client connected")
		world._on_session_ready(false)
		check(await until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "client loads existing base")
		bind_terminals()
		check(await until(func(): return is_instance_valid(hub) and hub.ui.app_open and hub.operator_peer == 1), "late guest sees occupied physical app without opening it")
		hub.clicker_result.connect(func(_id, _accepted, _amount): events_seen += 1)
		report.rpc_id(1, "initial", failures)
		return
	world._on_session_ready(true)
	world._enter_v3_level.rpc()
	check(await until(func(): return world._v3_items_spawned), "host loads real base")
	bind_terminals()
	state.progress_persistence_enabled = false
	var snapshot := state.get_snapshot()
	snapshot.day_index = 2
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 60
	state._broadcast_snapshot(snapshot, false)
	await visit(world.players.get_node("1"), hub)
	get_tree().root.get_node("GameMenu").force_close_menu()
	hub.begin_terminal_interaction()
	hub.request_app(true)
	for frame in 4: await get_tree().process_frame
	hub.ui.get_node("Overlay/LabClicker/Scroll").scroll_vertical = 1900
	await get_tree().create_timer(0.2).timeout
	check(hub.app_scroll == 1900, "host scroll recorded after container layout")
	print("HOST_READY_FOR_CLICKER_CLIENT")
	check(await until(func(): return reports.has("initial")), "late client confirms shared screen")
	if client_id == 0: get_tree().quit(1); return
	var guest: GamePlayer = world.players.get_node(str(client_id))
	await visit(guest, hub)
	for i in 20: hub.request_clicker_action(&"click")
	hub.request_clicker_action(&"pipette")
	check(state.clicker.samples == 11.5 and state.clicker.count(&"pipette") == 1, "host purchases exact economy")
	verify_clicker.rpc_id(client_id, "observe")
	check(await until(func(): return reports.has("observe")), "guest receives clicks purchases and view-only access")
	check(state.clicker.samples == 11.5, "guest cannot inject commands while host owns terminal")
	state.clicker.activity = 0.0
	hub.close_terminal()
	verify_clicker.rpc_id(client_id, "takeover")
	check(await until(func(): return reports.has("takeover")), "guest can take over released terminal")
	check(state.clicker.samples == 13.5 and hub.operator_peer == client_id, "host sees guest click on same stored economy")
	check(hub.ui.app_open and hub.screen_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "non-operating host sees live physical app")
	state.clicker.bacteria_id = 91
	state.clicker.bacteria_slot = 2
	state.clicker.bacteria_remaining = 9.0
	verify_clicker.rpc_id(client_id, "microbe")
	check(await until(func(): return reports.has("microbe")), "guest captures same one-use microbe")
	check(state.clicker.samples == 29.5 and state.clicker.bacteria_remaining == 0, "host confirms scaled reward exactly once")
	snapshot = state.get_snapshot()
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot, false)
	verify_clicker.rpc_id(client_id, "blackout")
	check(await until(func(): return reports.has("blackout")), "outage closes operator on both peers")
	check(hub.operator_peer == 0, "power loss releases ownership")
	finish.rpc_id(client_id, failures)
	await get_tree().create_timer(0.4).timeout
	print("CLICKER COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

@rpc("authority", "call_remote", "reliable")
func verify_clicker(phase: String) -> void:
	if phase == "observe":
		check(await until(func(): return state.clicker.count(&"pipette") == 1), "guest receives purchase counts")
		check(state.clicker.samples == 11.5 and events_seen == 21, "spectator sees same samples and every visual event")
		check(state.clicker.click_multiplier() == 1.5, "spectator sees shared rhythm boost")
		print("SHARED SCROLL ", hub.app_scroll, " / ", hub.ui.get_node("Overlay/LabClicker/Scroll").scroll_vertical)
		check(hub.app_scroll == 1900 and hub.ui.get_node("Overlay/LabClicker/Scroll").scroll_vertical == 1900, "late spectator sees operator scroll position in extended upgrades")
		get_tree().root.get_node("GameMenu").force_close_menu()
		hub.begin_terminal_interaction()
		check(await until(func(): return hub.active), "spectator opens authored view camera")
		check(not hub.can_operate() and not hub.request_clicker_action(&"click"), "occupied terminal is view-only")
		hub._request_command.rpc_id(1, 100, &"click")
		check(hub.ui.app_open, "spectator does not reset shared selected tab")
		hub.close_terminal()
	elif phase == "takeover":
		check(await until(func(): return hub.operator_peer == 0), "previous operator released")
		get_tree().root.get_node("GameMenu").force_close_menu()
		hub.begin_terminal_interaction()
		check(await until(func(): return hub.can_operate()), "guest becomes operator")
		hub.request_clicker_action(&"click")
		check(await until(func(): return state.clicker.samples == 13.5), "guest click confirmed by host")
		check(not state.progress_persistence_enabled or not state._owns_saved_progress, "guest never owns world save")
	elif phase == "microbe":
		check(await until(func(): return state.clicker.bacteria_id == 91 and state.clicker.bacteria_remaining > 0), "guest receives timed microbe and shared position")
		check(state.clicker.bacteria_slot == 2, "shared microbe position remains deterministic")
		hub.request_clicker_action(&"bacteria", 91)
		check(await until(func(): return state.clicker.samples == 29.5), "guest bonus validated by host")
		hub.request_clicker_action(&"bacteria", 91)
		await get_tree().create_timer(0.2).timeout
		check(state.clicker.samples == 29.5, "duplicate bonus claim cannot double pay across network")
	elif phase == "blackout":
		check(await until(func(): return not hub.active and not state.main_breaker_on), "client exits on outage")
		check(hub.operator_peer == 0 and not hub._screen_material.get_shader_parameter("powered"), "client display off and lock cleared")
	report.rpc_id(1, phase, failures)
