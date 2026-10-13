extends Node
var host := false
var port := 28769
var checks := 0
var failures := 0
var world: Node
var state: BaseGameplayController
var breaker: BaseMainBreaker
var client_id := 0
var reports := {}
var tank: BaseFuelSocket
var _fuel_input_active := false
var _fuel_input_sequence := 100000
var _interaction_serial := 100000

func _ready() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _process(_delta: float) -> void:
	if world == null: return
	for player in world.players.get_children():
		player.set_physics_process(false)
		player.survival.set_physics_process(false)
	# Production repeatedly sends the current serial on unreliable input packets.
	# Keep the frozen test actor in that same protocol until the host confirms it.
	if _fuel_input_active and not host:
		var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
		_fuel_input_sequence += 1
		local._submit_input.rpc_id(1, _fuel_input_sequence, Vector2.ZERO, false, false, 0, 0, _interaction_serial, 0, local.rotation.y, local.head.rotation.x)
func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not predicate.call() and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	return predicate.call()
func bind_breaker() -> void:
	state = world.get_node("V3Level/BaseGameplayController")
	breaker = get_tree().get_first_node_in_group("main_breaker")
	tank = world.get_node("V3Level/Floor_0_Base_Blockout/Gameplay/FuelFillInteractable")
	get_tree().root.get_node("GameMenu").force_close_menu()
func visit(player: GamePlayer) -> void:
	var side := -.7 if player.owner_peer_id == 1 else .7
	player.teleport_authoritative(breaker.global_position - breaker.global_basis.z*2 + breaker.global_basis.x*side - Vector3.UP*1.3, breaker.global_rotation.y + PI)
	player.camera.look_at(breaker.interaction_point.global_position)
	for frame in 6: await get_tree().physics_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	if host: ExpeditionSaveStore.clear("coop")
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real ENet peers")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not host:
		check(await until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client connected")
		world._on_session_ready(false)
		check(await until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "late client loads physical breaker")
		bind_breaker()
		check(await until(func(): return state.maintenance.get("wire_links", []) == [0]), "late join restores existing partial repair")
		check(not breaker.wiring.active and breaker.wiring.get_node("Board/Cable0").mesh.resource_path.ends_with("route_0_2.obj"), "late join shows correct cable without taking over camera")
		check(await until(func(): return breaker._cover_open), "late join restores host-opened door without opening local camera")
		var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
		check(not state.connect_wire_authoritative(local.owner_peer_id, 1, 0), "client cannot mutate repair locally")
		report.rpc_id(1, "initial", failures)
		return
	world._on_session_ready(true)
	world._enter_v3_level.rpc()
	check(await until(func(): return world._v3_items_spawned), "host loads production base")
	bind_breaker()
	var snapshot := state.get_snapshot()
	snapshot.day_index = 2
	snapshot.phase = BaseGameplayController.BasePhase.RESTORING_POWER
	snapshot.main_breaker_on = false
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20
	snapshot.maintenance = {"wires_required": true, "wire_order": [2, 0, 3, 1], "wire_links": [0]}
	state._broadcast_snapshot(snapshot)
	var host_player := world.players.get_node("1") as GamePlayer
	await visit(host_player)
	breaker.network_interact(1, host_player)
	check(breaker._cover_open, "host interaction opens shared cover before late join")
	print("HOST_READY_FOR_WIRING_CLIENT")
	check(await until(func(): return reports.has("initial")), "client acknowledges restored repair")
	if client_id == 0: get_tree().quit(1); return
	var guest := world.players.get_node(str(client_id)) as GamePlayer
	await visit(guest)
	breaker.network_interact(client_id, guest)
	verify_phase.rpc_id(client_id, "repair")
	check(await until(func(): return reports.has("repair")), "client connects a cable through production RPC")
	check(state.maintenance.wire_links.size() == 2 and state.maintenance.wire_links.has(1), "host receives only the confirmed client connection")
	check(not state.connect_wire_authoritative(client_id, 1, 0), "repeated client link does not advance twice")
	verify_phase.rpc_id(client_id, "select")
	check(await until(func(): return reports.has("select")), "guest holds the next plug locally")
	var local := world.players.get_node("1") as GamePlayer
	await visit(local)
	breaker.network_interact(1, local)
	check(breaker.wiring.active, "both players may inspect the same repair")
	check(state.connect_wire_authoritative(1, 2, 3), "host completes circuit selected by guest")
	verify_phase.rpc_id(client_id, "concurrent")
	check(await until(func(): return reports.has("concurrent")), "guest clears stale selection after host confirmation")
	check(state.connect_wire_authoritative(1, 3, 1), "host completes fourth circuit")
	verify_phase.rpc_id(client_id, "complete")
	check(await until(func(): return reports.has("complete")), "guest sees completed repair")
	breaker.wiring.close()
	check(breaker._cover_open, "cover stays open while the other player repairs")
	breaker.network_interact(1, local)
	check(state.main_breaker_on, "host switches on repaired base")
	verify_phase.rpc_id(client_id, "powered")
	check(await until(func(): return reports.has("powered")), "power transition closes guest repair safely")
	state.set_process(false)
	snapshot = state.get_snapshot()
	snapshot.elevator_backup_installed = true
	state._broadcast_snapshot(snapshot)
	await visit(guest)
	var fuel_before_off := state.fuel_liters
	verify_phase.rpc_id(client_id, "manual_off")
	check(await until(func(): return guest._server_interact_serial == 50000), "guest sends manual switch-off through production E input")
	guest.simulate_authoritative_movement(0.0)
	check(not state.main_breaker_on and is_equal_approx(state.fuel_liters, fuel_before_off), "guest switches mains off without consuming or losing fuel")
	check(world.get_node("V3Level/Elevator_Functional_Blockout").is_powered and state.maintenance.wire_links.size() == 4, "manual shutdown preserves reserve lift and repaired circuits")
	check(not state.load_saved_snapshot().main_breaker_on, "guest manual shutdown persists in host save")
	verify_phase.rpc_id(client_id, "off_confirmed")
	check(await until(func(): return reports.has("off_confirmed")), "guest confirms replicated manual shutdown")
	verify_phase.rpc_id(client_id, "manual_on")
	check(await until(func(): return guest._server_interact_serial == 50001), "guest sends restart through production E input")
	guest.simulate_authoritative_movement(0.0)
	check(state.main_breaker_on and state.maintenance.wire_links.size() == 4, "guest restarts repaired base without another wiring task")
	verify_phase.rpc_id(client_id, "on_confirmed")
	check(await until(func(): return reports.has("on_confirmed")), "guest confirms restored lighting")
	snapshot = state.get_snapshot()
	snapshot.fuel_liters = 56.5
	state._broadcast_snapshot(snapshot)
	guest.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 20.0})
	guest.teleport_authoritative(tank.global_position + Vector3(0, 0, -2.6), PI)
	guest.camera.look_at(tank.interaction_point.global_position)
	for frame in 6: await get_tree().physics_frame
	check(guest.get_interaction_target() == tank, "host ray for guest reaches supplied fuel tank")
	verify_phase.rpc_id(client_id, "fuel")
	check(await until(func(): return guest._server_interact_serial == 100000), "guest sends production E input RPC")
	guest.simulate_authoritative_movement(0.0)
	check(is_equal_approx(state.fuel_liters, 60.0) and is_equal_approx(guest.fuel_liters, 16.5), "host clamps refill and preserves unused client canister fuel")
	var saved: ConfigFile = ExpeditionSaveStore.read("coop").config
	var equipment: Dictionary = saved.get_value("inventory", "checkpoint", {}).get("players", {}).get(world._inventory_id(client_id), {})
	check(is_equal_approx(saved.get_value("base", "fuel_liters", 0), 60.0) and is_equal_approx(equipment.get("fuel_liters", 0), 16.5), "refill checkpoint atomically records both reservoir and guest canister")
	verify_phase.rpc_id(client_id, "fuel_confirmed")
	check(await until(func(): return reports.has("fuel_confirmed")), "guest sees synchronized tank, needle and remaining canister")
	check(state.save_progress_authoritative(), "refill and guest inventory can be saved together")
	finish.rpc_id(client_id, failures)
	await get_tree().create_timer(.5).timeout
	print("WIRING COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

@rpc("authority", "call_remote", "reliable")
func verify_phase(phase: String) -> void:
	if phase == "repair":
		check(await until(func(): return breaker.wiring.active), "host opens guest 3D repair view")
		check(get_tree().root.get_camera_3d() == breaker.wiring.camera, "guest uses authored repair camera")
		breaker.wiring.choose_contact(breaker.wiring.get_node("Board/Source1"))
		breaker.wiring.choose_contact(breaker.wiring.get_node("Board/Output2"))
		check(state.maintenance.wire_links == [0], "wrong guest contact sends no progress")
		breaker.wiring.choose_contact(breaker.wiring.get_node("Board/Output0"))
		check(await until(func(): return state.maintenance.wire_links.has(1)), "guest request confirmed by host")
	elif phase == "select":
		breaker.wiring.choose_contact(breaker.wiring.get_node("Board/Source2"))
		check(breaker.wiring.selected == 2, "local plug selection")
	elif phase == "concurrent":
		check(await until(func(): return state.maintenance.wire_links.has(2) and breaker.wiring.selected == -1), "concurrent connection clears guest plug selection")
	elif phase == "complete":
		check(await until(func(): return not state.maintenance.wires_required and state.maintenance.wire_links.size() == 4), "four circuits synchronized")
		check(breaker.wiring.active and not state.main_breaker_on, "completion waits for normal main switch")
	elif phase == "powered":
		check(await until(func(): return state.main_breaker_on and not breaker.wiring.active), "mains power exits guest repair")
		var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
		check(get_tree().root.get_camera_3d() == local.camera and get_tree().get_first_node_in_group("wiring_ui") == null, "guest camera and controls restored")
		check(not breaker.get_node("Wiring/Board").visible, "guest sees closed service compartment")
	elif phase == "manual_off":
		check(breaker.get_interaction_prompt() == "Выключить главный щит", "guest sees manual switch-off action")
		_interaction_serial = 50000
		_fuel_input_active = true
	elif phase == "off_confirmed":
		_fuel_input_active = false
		check(await until(func(): return not state.main_breaker_on and not world.get_node("V3Level/BasePowerLightingController").is_standard_powered), "guest mains and lights switch off together")
		check(state.is_elevator_powered() and state.maintenance.wire_links.size() == 4, "guest retains reserve power and repaired circuits")
	elif phase == "manual_on":
		_interaction_serial = 50001
		_fuel_input_active = true
	elif phase == "on_confirmed":
		_fuel_input_active = false
		check(await until(func(): return state.main_breaker_on and world.get_node("V3Level/BasePowerLightingController").is_standard_powered), "guest restart restores normal lighting")
	elif phase == "fuel":
		var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
		check(await until(func(): return is_equal_approx(state.fuel_liters, 56.5) and local.has_held_item(&"fuel_can") and is_equal_approx(local.fuel_liters, 20.0)), "guest receives canister and shared pre-refill state")
		check(not tank.get_interaction_hint_for(local).is_empty(), "guest canister enables only E glyph")
		_interaction_serial = 100000
		_fuel_input_active = true
	elif phase == "fuel_confirmed":
		_fuel_input_active = false
		var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
		check(await until(func(): return is_equal_approx(state.fuel_liters, 60.0) and is_equal_approx(local.fuel_liters, 16.5)), "guest receives exact unused canister fuel")
		check(await until(func(): return is_equal_approx(tank.gauge.current_animation_position, 1.0)), "guest gauge points at full reservoir")
		check(tank.get_interaction_hint_for(local).is_empty(), "guest full tank has no refill prompt")
	report.rpc_id(1, phase, failures)

@rpc("any_peer", "call_remote", "reliable")
func report(phase: String, client_failures: int) -> void:
	if not multiplayer.is_server(): return
	client_id = multiplayer.get_remote_sender_id()
	reports[phase] = client_failures
	if client_failures > 0: failures = client_failures

@rpc("authority", "call_remote", "reliable")
func finish(host_failures: int) -> void:
	check(host_failures == 0, "host repair checks passed")
	print("WIRING COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
