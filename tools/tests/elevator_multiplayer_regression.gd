extends Node
## Real ENet processes, production session/player RPCs and authored elevator.

var host := false
var port := 28742
var world: Node3D
var elevator: FunctionalElevatorController
var failures := 0
var checks := 0
var ready_peers: Array[int] = []
var reports := {}
var phase := "boot"
var largest_floor_error := 0.0
var observed := {}
var observed_states := {}
var saw_initial_destination := false

func _ready() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1

func delay(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func until(predicate: Callable, seconds: float = 15.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await delay(0.05)
	return predicate.call()

func actors() -> Array:
	return world.get_node("Players").get_children().filter(func(node): return node is GamePlayer)

func _physics_process(_delta: float) -> void:
	if world == null: return
	get_tree().root.get_node("GameMenu").force_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for actor: GamePlayer in actors():
		actor.set_process_unhandled_input(false)
		actor.survival.debug_invincible = true
		if actor.is_local_player():
			for action in ["move_forward", "move_backward", "move_right", "move_left", "jump"]: Input.action_release(action)
			if phase == "ride" and actor.is_on_floor():
				largest_floor_error = maxf(largest_floor_error, absf(actor.global_position.y - elevator.cabin.global_position.y))
	if not host and elevator._snapshot_received:
		observed_states[str(int(elevator.state))] = true
		if elevator.state == elevator.ElevatorState.MOVING and elevator._active_destination_floor_index == 1:
			saw_initial_destination = true
		observed[phase] = {"state": int(elevator.state), "floor": elevator.current_floor_index, "pending": elevator.pending_floor_index}

@rpc("any_peer", "call_remote", "reliable")
func ready_for_elevator() -> void:
	if not host: return
	var peer_id := multiplayer.get_remote_sender_id()
	if not ready_peers.has(peer_id): ready_peers.append(peer_id)

@rpc("authority", "call_local", "reliable")
func set_phase(value: String) -> void:
	phase = value
	print("PHASE ", phase)

@rpc("authority", "call_remote", "reliable")
func request_report(label: String) -> void:
	# Incoming state is applied on the next physics tick, even if a report RPC
	# was delivered in the same network poll as that state snapshot.
	await get_tree().physics_frame
	await get_tree().process_frame
	var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
	var doors := {}
	for floor_index in 5: doors[str(floor_index)] = elevator._get_landing_door(floor_index).is_open
	receive_report.rpc_id(1, label, {
		"state": int(elevator.state), "floor": elevator.current_floor_index,
		"pending": elevator.pending_floor_index, "destination": elevator._active_destination_floor_index,
		"y": elevator.cabin.position.y, "doors": doors,
		"cabin_open": elevator.cabin_door.is_open, "barrier": not elevator.cabin_door_travel_barrier.disabled,
		"passenger_y": local.global_position.y if local != null else -999.0,
		"floor_error": largest_floor_error, "observed": observed.duplicate(true),
		"states": observed_states.duplicate(),
		"saw_initial_destination": saw_initial_destination,
		"cargo": cargo_pose(),
	})

@rpc("any_peer", "call_remote", "reliable")
func receive_report(label: String, data: Dictionary) -> void:
	if host: reports[label] = data

func report(label: String) -> Dictionary:
	reports.erase(label)
	request_report.rpc(label)
	check(await until(func(): return reports.has(label), 4.0), "client reports " + label)
	return reports.get(label, {})

func cargo_pose() -> Vector3:
	for item in world.world_items.get_children():
		if item is WorldItemPickup and item.item_type == &"fuel_can":
			return elevator.cabin.to_local(item.global_position)
	return Vector3(999, 999, 999)

@rpc("authority", "call_remote", "reliable")
func disconnect_client() -> void:
	print("CLIENT NETWORK CHECKS COMPLETE")
	get_tree().quit()

func run() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--fps="): Engine.max_fps = int(arg.trim_prefix("--fps="))
	var root := get_tree().root
	root.get_node("SteamInput").set_process(false)
	root.get_node("SteamInput").set_process_input(false)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://tools/tests/fixtures/elevator_network_session.tscn").instantiate()
	root.add_child(world)
	elevator = world.get_node("Elevator")
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)
	check(result == OK, "ENet transport created")
	if result != OK: get_tree().quit(1); return
	multiplayer.multiplayer_peer = peer
	if not host:
		if not await until(func(): return actors().size() == 2, 20.0):
			check(false, "client player roster loaded"); get_tree().quit(1); return
		ready_for_elevator.rpc_id(1)
		return
	world._on_session_ready(true)
	world.spawn_world_item(&"fuel_can", Transform3D(Basis.IDENTITY, Vector3(1.8, 0.6, 1.5)), {"amount": 10.0})
	# Start empty-cabin call before the client exists. It will join mid-motion.
	elevator.request_call(1)
	print("HOST_READY_FOR_LATE_JOIN")
	check(await until(func(): return ready_peers.size() == 1 and actors().size() == 2, 20.0), "real client joins production player roster")
	if ready_peers.is_empty(): get_tree().quit(1); return
	var client_id := ready_peers[0]
	var host_actor := world.get_node("Players/1") as GamePlayer
	var client_actor := world.get_node("Players/" + str(client_id)) as GamePlayer
	check(elevator.state == elevator.ElevatorState.MOVING, "client joins during active movement")
	elevator.sync_network_state_to_peer(client_id)
	await delay(0.8)
	var data := await report("late_motion")
	check(data.get("saw_initial_destination", false), "late client receives movement phase and destination")
	check(absf(float(data.get("y", 999)) - elevator.cabin.position.y) < 0.5, "late client aligns with host curve")
	check(data.get("barrier", false) and not data.get("cabin_open", true), "late client closes travel barrier")
	check(await until(func(): return elevator.state == elevator.ElevatorState.IDLE_OPEN), "host completes first trip")
	await delay(0.2)
	data = await report("arrived")
	check(data.get("floor", -1) == 1 and data.get("state", -1) == elevator.ElevatorState.IDLE_OPEN and data.get("doors", {}).get("1", false) and not data.get("doors", {}).get("0", true), "client reaches same landing with correct doors")
	# Bring both real players into the cabin using production teleport RPCs.
	host_actor.teleport_authoritative(elevator.cabin.global_position + Vector3(-0.6, 0.08, 0), 0)
	client_actor.teleport_authoritative(elevator.cabin.global_position + Vector3(0.6, 0.08, 0), 0)
	await delay(0.3)
	set_phase.rpc("ride")
	check(elevator.request_floor(0), "both passengers permit cabin departure")
	client_actor.teleport_authoritative(elevator.cabin.global_position + Vector3(-2.85, 0.08, 0), 0)
	check(await until(func(): return elevator.state == elevator.ElevatorState.WAITING_FOR_PLAYERS), "real client obstruction aborts departure")
	await delay(0.2)
	data = await report("obstructed")
	check(data.get("state", -1) == elevator.ElevatorState.WAITING_FOR_PLAYERS and data.get("pending", -1) == 0 and data.get("cabin_open", false) and not data.get("barrier", true), "client retains pending destination and reopened exit")
	client_actor.teleport_authoritative(elevator.cabin.global_position + Vector3(0.6, 0.08, 0), 0)
	check(await until(func(): return elevator.state == elevator.ElevatorState.MOVING), "clearing actual client obstruction resumes trip")
	await delay(1.5)
	elevator.set_powered(false)
	check(await until(func(): return elevator.state == elevator.ElevatorState.UNPOWERED), "power loss finishes current network trip safely")
	await delay(0.3)
	data = await report("power_loss")
	check(data.get("floor", -1) == 0 and data.get("state", -1) == elevator.ElevatorState.UNPOWERED and data.get("cabin_open", false), "client receives unpowered final state with open doors")
	check(absf(float(data.get("passenger_y", 999)) - elevator.cabin.global_position.y) < 0.3 and absf(host_actor.global_position.y - elevator.cabin.global_position.y) < 0.3, "real host and client passengers remain in cabin")
	check(float(data.get("floor_error", 999)) < 0.3, "client prediction stays near moving cabin floor")
	var cargo: Vector3 = data.get("cargo", Vector3(999, 999, 999))
	check(cargo.distance_to(cargo_pose()) < 0.2 and absf(cargo.x - 1.8) < 0.2 and cargo.y > 0.0 and cargo.y < 0.8, "dropped cargo retains cabin-relative pose on both peers")
	print("NETWORK METRICS passenger_floor_error=", data.get("floor_error", -1))
	for observed_state in elevator.ElevatorState.values():
		if observed_state != elevator.ElevatorState.FAULT:
			check(data.get("states", {}).has(str(observed_state)), "client observes authoritative phase %d" % observed_state)
	# Waiting for a missing player must stop waiting once that peer disconnects.
	set_phase.rpc("disconnect")
	elevator.set_powered(true)
	client_actor.teleport_authoritative(Vector3(-6, 0.08, 0), 0)
	await delay(0.3)
	check(not elevator.request_floor(1) and elevator.state == elevator.ElevatorState.WAITING_FOR_PLAYERS, "connected missing passenger blocks departure")
	disconnect_client.rpc()
	# Packet loss can drop the graceful disconnect datagram. Allow the real
	# transport timeout to detect a vanished process before expecting departure.
	check(await until(func(): return elevator.state == elevator.ElevatorState.MOVING, 45.0), "disconnecting missing passenger releases waiting trip")
	check(await until(func(): return elevator.state == elevator.ElevatorState.IDLE_OPEN), "remaining host completes trip after disconnect")
	print("CHECKS ", checks, " RESULT FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
