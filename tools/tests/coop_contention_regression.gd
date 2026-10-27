extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Competing requests and a real disconnect, using the production session.
var guest_id := 0
var request_pending := false
var rejected_stale_accept := false

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	var prefix := "user://contention_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path", prefix + ".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", prefix + ".cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, prefix)
	BaseGameplayController.save_scope = "coop"
	if host:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real ENet contention transport")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.resume_base_on_start = true
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not host:
		check(await wait_until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "guest connects")
		world._on_session_ready(false)
		check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "guest loads real expedition")
		ready_for_contention.rpc_id(1)
		return
	world._on_session_ready(true)
	check(await wait_until(func(): return world._v3_items_spawned and not world._v3_transition_in_progress), "host loads real expedition")
	world.set_process(false)
	world._base_gameplay_controller.set_process(false)
	print("HOST_READY_CONTENTION_CLIENT")
	check(await wait_until(func(): return guest_id != 0), "both participants ready")
	if guest_id == 0: get_tree().quit(1); return
	var actor: GamePlayer = world.players.get_node("1")
	var guest: GamePlayer = world.players.get_node(str(guest_id))
	for player in [actor, guest]:
		player.handoff.set_physics_process(false)
		clean(player)
	for guest_first in [false, true]:
		for player in [actor, guest]: clean(player)
		var pickup: WorldItemPickup = spawn_pickup(&"fuse", {})
		for player in [actor, guest]: player.teleport_authoritative(pickup.global_position + Vector3(0, 0, 1), 0)
		await competing_request()
		var order: Array = [guest, actor] if guest_first else [actor, guest]
		for player in order: pickup.network_interact(player.owner_peer_id, player)
		check(order[0].has_held_item(&"fuse") and not order[1].has_held_item(&"fuse"), "same-frame fuse contention has one winner; guest first=%s" % guest_first)
		check(pickup._collected, "winning pickup is consumed before the next request")
		world._base_gameplay_controller.inventory_checkpoint = world.capture_inventory_checkpoint()
		var checkpoint: Dictionary = world._base_gameplay_controller.inventory_checkpoint
		var owners := 0
		for equipment: Dictionary in checkpoint.players.values():
			if equipment.held_item == &"fuse": owners += 1
		check(owners == 1 and checkpoint.pickups.all(func(data): return data.item_type != &"fuse"), "checkpoint contains one fuse owner and no duplicate world fuse")
		await get_tree().process_frame
	for player in [actor, guest]: clean(player)
	actor.weapon.pistol_ammo = 236
	guest.weapon.pistol_ammo = 230
	var ammo: WorldItemPickup = spawn_pickup(&"pistol_ammo", {"amount": 12})
	for player in [actor, guest]: player.teleport_authoritative(ammo.global_position + Vector3(0, 0, 1), 0)
	await competing_request()
	ammo.network_interact(1, actor)
	check(actor.weapon.pistol_ammo == 240 and ammo.item_state.amount == 8, "partial pickup leaves the exact remainder for the next request")
	ammo.network_interact(guest_id, guest)
	check(guest.weapon.pistol_ammo == 238 and ammo._collected, "competing ammo pickup preserves total ammunition")
	for player in [actor, guest]: clean(player)
	var bodies := get_tree().get_nodes_in_group("medical_corpses")
	check(await wait_until(func(): return bodies.size() == 2 and bodies.all(func(body): return body.initialized)), "both existing skeletal bodies initialized")
	var first: MedicalCorpse = bodies[0]
	var second: MedicalCorpse = bodies[1]
	# The second story body is normally unrecoverable. Enable it only in this
	# isolated fixture to stress two-carrier reservation of one existing bed.
	first.recoverable = true
	second.recoverable = true
	for player in [actor, guest]: player.teleport_authoritative(first.ragdoll.root_body.global_position + Vector3(0, .1, 1), 0)
	await competing_request()
	first.network_interact(1, actor)
	first.network_interact(guest_id, guest)
	check(first.carrier_peer == 1 and actor.is_carrying_corpse() and not guest.is_carrying_corpse(), "contested corpse pickup has one carrier throughout lifting")
	check(await wait_until(func(): return first.mode == MedicalCorpse.Mode.CARRIED), "first lifting animation completes")
	guest.teleport_authoritative(second.ragdoll.root_body.global_position + Vector3(0, .1, 1), 0)
	second.network_interact(guest_id, guest)
	check(await wait_until(func(): return second.mode == MedicalCorpse.Mode.CARRIED), "second carrier ready for bed contention")
	var bed: Node3D = get_tree().get_nodes_in_group("medical_corpse_beds")[0]
	actor.teleport_authoritative(bed.global_position + Vector3(0, 0, 1.5), 0)
	guest.teleport_authoritative(bed.global_position + Vector3(0, 0, -1.5), PI)
	await competing_request()
	bed.network_interact(1, actor)
	bed.network_interact(guest_id, guest)
	check(first.mode == MedicalCorpse.Mode.PLACING and second.mode == MedicalCorpse.Mode.CARRIED and bed.is_occupied(), "first placement reserves bed synchronously against second carrier")
	bed.network_interact(1, actor)
	check(first.mode == MedicalCorpse.Mode.PLACING, "duplicate placement request does not restart or steal the bed")
	actor.survival.dead = true
	check(await wait_until(func(): return first.mode == MedicalCorpse.Mode.GROUND), "death during placement releases body and carrier")
	check(not bed.is_occupied() and not actor.corpse_action_busy, "interrupted placement releases bed reservation and busy state")
	bed.network_interact(guest_id, guest)
	check(await wait_until(func(): return second.mode == MedicalCorpse.Mode.DELIVERED), "other carrier can finish placement after reservation is released")
	actor.survival.dead = false
	actor.survival.health = 100
	clean(guest)
	guest.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 5.5})
	check(guest.handoff.start_authoritative(&"fuel_can", false), "departing guest starts a real held-item offer")
	var serial: int = guest.handoff.token
	multiplayer.peer_disconnected.connect(func(id):
		if id == guest_id and is_instance_valid(guest):
			rejected_stale_accept = not guest.handoff.accept_authoritative(actor, serial))
	close_guest.rpc_id(guest_id, failures)
	check(await wait_until(func(): return not world.players.has_node(str(guest_id))), "real connection loss runs production departure cleanup")
	check(rejected_stale_accept, "late acceptance cannot take an item after departure cleanup")
	world._base_gameplay_controller.inventory_checkpoint = world.capture_inventory_checkpoint()
	var saved: Dictionary = world._base_gameplay_controller.inventory_checkpoint
	var cans: Array = saved.pickups.filter(func(data): return data.item_type == &"fuel_can" and data.item_state.get("fuel_liters", 0.0) == 5.5)
	check(cans.size() == 1 and saved.players["test:guest"].held_item == &"", "interrupted offer saves one dropped can and no duplicate account ownership")
	set_process(false)
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	get_tree().current_scene = null
	world.queue_free()
	for frame in 4: await get_tree().process_frame
	print("CONTENTION COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

func clean(player: GamePlayer) -> void:
	player.handoff.cancel_authoritative()
	player.apply_inventory_snapshot({"held_item": &"", "revision": player._inventory_revision + 1})
	player._journal_phase = 0

func spawn_pickup(type: StringName, data: Dictionary) -> WorldItemPickup:
	world.spawn_world_item(type, Transform3D(Basis.IDENTITY, Vector3(0, 1, 0)), data)
	var pickup: WorldItemPickup = world.world_items.get_child(-1)
	pickup.freeze = true
	return pickup

func competing_request() -> void:
	request_pending = false
	request_competition.rpc_id(guest_id)
	check(await wait_until(func(): return request_pending), "guest request reaches same authoritative interaction batch")

@rpc("authority", "call_remote", "reliable")
func request_competition() -> void:
	compete.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func compete() -> void:
	if host and multiplayer.get_remote_sender_id() == guest_id: request_pending = true

@rpc("any_peer", "call_remote", "reliable")
func ready_for_contention() -> void:
	if host: guest_id = multiplayer.get_remote_sender_id()

@rpc("authority", "call_remote", "reliable")
func close_guest(count: int) -> void:
	check(count == 0, "host contention checks passed before connection loss")
	set_process(false)
	multiplayer.multiplayer_peer.close()
	get_tree().current_scene = null
	world.queue_free()
	for frame in 4: await get_tree().process_frame
	print("CONTENTION COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
