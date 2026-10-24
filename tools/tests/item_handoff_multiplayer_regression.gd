extends Node
var host := false
var port := 0
var guest_id := 0
var ready_guest := false
var acknowledged := false
var checks := 0
var failures := 0
var actors := {}
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func wait_until(test: Callable) -> bool:
	var end := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < end:
		if test.call(): return true
		await get_tree().process_frame
	return false
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real ENet handoff connection")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("GameMenu").force_close_menu()
	get_tree().root.get_node("SteamInput").set_process(false)
	if host:
		multiplayer.peer_connected.connect(func(id: int): configure.rpc(id))
		print("HOST_READY_HANDOFF")
		await run_host()

@rpc("authority", "call_local", "reliable")
func configure(id: int) -> void:
	guest_id = id
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	arena.name = "HandoffArena"
	get_tree().root.add_child(arena)
	for owner in [1, guest_id]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(owner, "Peer", Vector3(0, 0.1, 0 if owner == 1 else -1.7), Color.WHITE, 0 if owner == 1 else PI)
		actor.name = str(owner)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.handoff.set_physics_process(false)
		actors[owner] = actor
	for frame in 4: await get_tree().physics_frame
	if not host: guest_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func guest_ready() -> void:
	if host and multiplayer.get_remote_sender_id() == guest_id: ready_guest = true

func _process(_delta: float) -> void:
	if host and actors.has(guest_id):
		actors[guest_id].simulate_authoritative_movement(0)
		actors[guest_id].handoff._physics_process(0)

func run_host() -> void:
	check(await wait_until(func(): return ready_guest), "both native player scenes ready")
	if not ready_guest: get_tree().quit(1); return
	var giver: GamePlayer = actors[guest_id]
	var receiver: GamePlayer = actors[1]
	giver.tape_count = 2
	giver._spare_batteries.assign([0.36])
	giver._publish_inventory()
	pocket_offer.rpc_id(guest_id)
	check(await wait_until(func(): return giver.handoff.mode == 2), "guest offer request reaches host")
	check(giver.tape_count == 2, "guest still owns offered tape")
	receiver.camera.look_at(giver.handoff.global_position)
	for frame in 3: await get_tree().physics_frame
	check(receiver.get_interaction_target() == giver.handoff, "host E ray sees guest hand")
	check(giver.handoff.accept_authoritative(receiver, giver.handoff.token), "host accepts guest pocket item")
	check(receiver.tape_count == 1 and giver.tape_count == 1, "host moves exactly one tape")
	forged_offer.rpc_id(guest_id)
	await get_tree().create_timer(0.2).timeout
	check(not receiver.handoff.is_offering(), "guest cannot offer host-owned inventory")
	receiver.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 4.6})
	check(receiver.handoff.start_authoritative(&"fuel_can", false), "host extends held canister")
	var serial: int = receiver.handoff.token
	accept_host_canister.rpc_id(guest_id)
	check(await wait_until(func(): return giver.has_held_item(&"fuel_can")), "guest E accepts host held item through production RPC")
	if not giver.has_held_item(&"fuel_can"):
		print("HANDOFF DEBUG host offer=", receiver.handoff.mode, " token=", receiver.handoff.token, " target=", giver.get_interaction_target(), " head=", giver.head.global_position, " direction=", -giver.camera.global_basis.z, " source=", receiver.handoff.global_position, " usable=", receiver.handoff.usable(giver), " receiver_offer=", giver.handoff.mode)
	check(is_equal_approx(giver.fuel_liters, 4.6) and receiver._held_item_type == &"", "canister fuel and ownership preserved")
	await get_tree().create_timer(0.15).timeout
	check(not receiver.handoff.accept_authoritative(giver, serial), "duplicate token cannot transfer twice")
	cancel_battery.rpc_id(guest_id)
	check(await wait_until(func(): return giver.handoff.mode == 2), "guest proposes spare battery")
	cancel_now.rpc_id(guest_id)
	check(await wait_until(func(): return giver.handoff.mode == 0), "guest cancel is replicated")
	check(giver._spare_batteries == [0.36] and receiver._spare_batteries.is_empty(), "cancel preserves charged battery")
	lease_offer.rpc_id(guest_id)
	check(await wait_until(func(): return giver.handoff.mode == 1), "guest starts held offer")
	await get_tree().create_timer(1.2).timeout
	check(not giver.handoff.is_offering() and giver.has_held_item(&"fuel_can"), "missing hold heartbeat cancels without dropping item")
	verify_guest.rpc_id(guest_id)
	check(await wait_until(func(): return acknowledged), "guest confirms final replicated inventory")
	finish.rpc_id(guest_id, failures)
	await get_tree().create_timer(0.3).timeout
	print("HANDOFF NETWORK CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

@rpc("authority", "call_remote", "reliable")
func pocket_offer() -> void:
	var actor: GamePlayer = actors[guest_id]
	check(await wait_until(func(): return actor.tape_count == 2), "guest receives authoritative tape inventory")
	actor.handoff.request_offer(&"tape", true)

@rpc("authority", "call_remote", "reliable")
func forged_offer() -> void:
	actors[1].handoff._submit_offer.rpc_id(1, &"tape", true)

@rpc("authority", "call_remote", "reliable")
func accept_host_canister() -> void:
	var source: GamePlayer = actors[1]
	var actor: GamePlayer = actors[guest_id]
	check(await wait_until(func(): return source.handoff.mode == 1), "client sees host hand offer")
	var offset: Vector3 = source.handoff.global_position - actor.head.global_position
	var yaw := atan2(-offset.x, -offset.z)
	var pitch := atan2(offset.y, Vector2(offset.x, offset.z).length())
	actor.rotation.y = yaw
	actor.head.rotation.x = pitch
	actor._submit_input.rpc_id(1, 100, Vector2.ZERO, false, false, 0, 0, 0, 0, yaw, pitch)
	for frame in 5: await get_tree().physics_frame
	check(actor.get_interaction_target() == source.handoff, "client E targets the host's actual extended hand")
	var accepted_token: int = source.handoff.token
	source.handoff.begin_item_handoff()
	for attempt in 50:
		source.handoff._accept.rpc_id(1, accepted_token, yaw, pitch)

@rpc("authority", "call_remote", "reliable")
func cancel_battery() -> void:
	actors[guest_id].handoff.request_offer(&"battery", true)
@rpc("authority", "call_remote", "reliable")
func cancel_now() -> void:
	actors[guest_id].handoff.request_cancel()
@rpc("authority", "call_remote", "reliable")
func lease_offer() -> void:
	actors[guest_id].handoff.request_offer(&"fuel_can", false)
@rpc("authority", "call_remote", "reliable")
func verify_guest() -> void:
	var actor: GamePlayer = actors[guest_id]
	check(await wait_until(func(): return actor.tape_count == 1 and actor.has_held_item(&"fuel_can") and not actor.handoff.is_offering()), "client sees final ownership and cleared offer")
	check(is_equal_approx(actor.fuel_liters, 4.6), "client sees preserved canister fuel")
	verified.rpc_id(1, failures)
@rpc("any_peer", "call_remote", "reliable")
func verified(count: int) -> void:
	if host and multiplayer.get_remote_sender_id() == guest_id:
		failures += count
		acknowledged = true
@rpc("authority", "call_remote", "reliable")
func finish(count: int) -> void:
	print("HANDOFF NETWORK CHECKS ", checks, " FAILURES ", failures + count)
	get_tree().quit(1 if failures + count else 0)
