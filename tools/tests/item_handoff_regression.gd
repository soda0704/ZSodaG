extends SceneTree
var failures := 0
var checks := 0
var giver: GamePlayer
var receiver: GamePlayer
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle() -> void:
	for frame in 3: await physics_frame
func clean(player: GamePlayer) -> void:
	player.handoff.cancel_authoritative()
	var state := player.get_inventory_snapshot()
	state.merge({"held_item": &"", "has_flashlight": false, "weapon_light_mounted": false, "handheld_flashlight_drawn": false, "flashlight_enabled": false, "battery_charge": 0.0, "spare_batteries": [], "tape_count": 0, "crowbar_uses": 0, "crafting_parts": {}, "pistol_ammo": 0, "rifle_magazines": [], "weapon_reload": 0.0, "revision": player._inventory_revision + 1}, true)
	player.apply_inventory_snapshot(state)
	player._journal_phase = 0
	player.survival.dead = false
func offer(type: StringName, pocket := false) -> int:
	check(giver.handoff.start_authoritative(type, pocket), "offer begins: " + String(type))
	giver.handoff._physics_process(0)
	receiver.camera.look_at(giver.handoff.global_position)
	await settle()
	check(receiver.get_interaction_target() == giver.handoff, "real E ray targets offered hand")
	return giver.handoff.token
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	for peer in [2, 1]:
		var player: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		player.setup(peer, "Handoff", Vector3(0, 0.1, 0 if peer == 2 else -1.7), Color.WHITE, 0 if peer == 2 else PI)
		player.name = str(peer)
		arena.get_node("Players").add_child(player)
		player.set_physics_process(false)
		player.survival.set_physics_process(false)
		player.handoff.set_physics_process(false)
		if peer == 2: giver = player
		else: receiver = player
	await settle()
	for type in [&"pistol", &"m4a1", &"kitchen_knife", &"fuel_can", &"flashlight", &"fuse", &"seed_packet", &"flamethrower"]:
		clean(giver); clean(receiver)
		giver.pickup_world_item_authoritative(type, {"fuel_liters": 1.25, "battery_charge": 0.37, "rounds": 7})
		var original := giver.get_held_item_state()
		var serial: int = await offer(type)
		check(giver._held_item_type == type, "offering does not remove the held item")
		check(not giver.weapon.perform_action(&"fire"), "offered weapon cannot fire")
		check(giver.handoff.accept_authoritative(receiver, serial), "receiver accepts the hand item")
		check(receiver._held_item_type == type and receiver.get_held_item_state() == original, "held item preserves ammunition, fuel and battery state")
		check(giver._held_item_type == &"" and not giver.handoff.is_offering(), "giver releases item and offer")
		check(not giver.handoff.accept_authoritative(receiver, serial), "repeat acceptance cannot duplicate the item")
	clean(giver); clean(receiver)
	giver._spare_batteries.assign([0.22, 0.79])
	var token: int = await offer(&"battery", true)
	check(giver._spare_batteries.size() == 2, "pocket item stays in inventory while offered")
	check(giver.handoff.accept_authoritative(receiver, token), "battery is accepted from an open palm")
	check(receiver._spare_batteries == [0.79] and giver._spare_batteries == [0.22], "battery keeps its actual charge")
	clean(giver); clean(receiver)
	giver.pickup_world_item_authoritative(&"m4a1", {"rounds": 13, "mounted_charge": 0.43, "mounted_malfunctioning": true})
	token = await offer(&"m4a1")
	check(giver.handoff.accept_authoritative(receiver, token), "weapon and attached flashlight transfer together")
	check(receiver.weapon.rounds == 13 and receiver.weapon_light_mounted and is_equal_approx(receiver._battery_charge, 0.43) and receiver._flashlight_malfunctioning and not giver._has_flashlight, "attachment, charge and fault keep exactly one owner")
	clean(giver); clean(receiver)
	giver.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.31})
	giver.toggle_flashlight_authoritative()
	token = await offer(&"flashlight", true)
	check(giver.handoff.accept_authoritative(receiver, token), "pocketed flashlight transfers without dropping the held item")
	check(not giver._has_flashlight and receiver._has_flashlight and is_equal_approx(receiver._battery_charge, 0.31), "pocketed flashlight retains its battery")
	clean(giver); clean(receiver)
	giver._spare_batteries.assign([0.61])
	for i in receiver.MAX_SPARE_BATTERIES: receiver._spare_batteries.append(1.0)
	token = await offer(&"battery", true)
	check(not giver.handoff.accept_authoritative(receiver, token) and giver._spare_batteries == [0.61], "full inventory rejects without losing source battery")
	for type in giver.CRAFT_RECIPE.pickup_scenes.keys() + [&"tape", &"crowbar", &"pistol_ammo", &"rifle_magazine"]:
		clean(giver); clean(receiver)
		giver.pickup_world_item_authoritative(type, {"amount": 9, "rounds": 17, "uses": 2})
		token = await offer(type, true)
		giver.handoff.cancel_authoritative()
		check(giver.handoff.available(type, true), "cancelling preserves " + String(type))
		token = await offer(type, true)
		check(giver.handoff.accept_authoritative(receiver, token), "pocket transfer: " + String(type))
		check(not giver.handoff.available(type, true) and receiver.handoff.available(type, true), "exactly one owner after transfer")
	clean(giver); clean(receiver)
	giver.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 4.2})
	receiver.pickup_world_item_authoritative(&"pistol", {})
	token = await offer(&"fuel_can")
	check(not giver.handoff.accept_authoritative(receiver, token) and giver.has_held_item(&"fuel_can"), "busy hands reject without dropping or consuming anything")
	clean(receiver)
	receiver.camera.look_at(giver.handoff.global_position)
	receiver.position.z = -5
	check(not giver.handoff.accept_authoritative(receiver, token), "distance rejection")
	receiver.position.z = -1.7
	var old_position := receiver.position
	receiver.position.z = 0.8
	receiver.camera.look_at(giver.handoff.global_position)
	await settle()
	check(not giver.handoff.accept_authoritative(receiver, token), "cannot take an offer through the giver's back")
	receiver.position = old_position
	receiver.camera.look_at(giver.handoff.global_position)
	receiver.survival.dead = true
	check(not giver.handoff.accept_authoritative(receiver, token), "dead receiver rejection")
	receiver.survival.dead = false
	var blocker: Node3D = load("res://tools/tests/fixtures/terminal_occluder.tscn").instantiate()
	arena.add_child(blocker)
	blocker.global_position = (receiver.camera.global_position + giver.handoff.global_position) * 0.5
	await settle()
	check(not giver.handoff.accept_authoritative(receiver, token), "wall blocks acceptance")
	blocker.queue_free()
	await settle()
	giver.handoff.cancel_authoritative()
	token = await offer(&"fuel_can")
	check(not giver.handoff.accept_authoritative(receiver, token - 2), "stale offer token is rejected")
	check(not giver.get_inventory_snapshot().has("item_offer"), "offers never enter saved inventory")
	giver.survival.dead = true
	giver.handoff._physics_process(0)
	check(not giver.handoff.is_offering(), "death cancels the offer")
	clean(giver); clean(receiver)
	giver.tape_count = 3
	token = await offer(&"tape", true)
	giver.handoff.network_interact(receiver.owner_peer_id, receiver)
	check(giver.tape_count == 3 and receiver.tape_count == 0, "tokenless delayed E cannot accept any offer")
	giver.handoff.cancel_authoritative()
	check(not giver.handoff.accept_authoritative(receiver, token), "accept after cancel keeps source ownership")
	var old_token := token
	token = await offer(&"tape", true)
	check(not giver.handoff.accept_authoritative(receiver, old_token), "old E cannot consume a replacement offer")
	var observations: Array = []
	var observer := func():
		observations.append(giver.tape_count + receiver.tape_count)
		check(not giver.handoff.start_authoritative(&"tape", true), "inventory signal cannot reopen offer during commit")
		check(not giver.handoff.accept_authoritative(receiver, token), "inventory signal cannot reenter acceptance")
	giver.inventory_changed.connect(observer)
	receiver.inventory_changed.connect(observer)
	check(giver.handoff.accept_authoritative(receiver, token), "atomic transfer commits")
	giver.inventory_changed.disconnect(observer)
	receiver.inventory_changed.disconnect(observer)
	check(observations == [3, 3], "every publication sees conserved total ownership")
	for attempt in 50:
		check(not giver.handoff.accept_authoritative(receiver, token), "replayed acceptance rejected " + str(attempt))
	check(giver.tape_count == 2 and receiver.tape_count == 1, "request flood transfers exactly one unit")
	clean(giver); clean(receiver)
	giver._spare_batteries.assign([0.0])
	token = await offer(&"battery", true)
	var source_before := giver.get_inventory_snapshot()
	var target_before := receiver.get_inventory_snapshot()
	check(not giver.handoff.accept_authoritative(receiver, token), "recipient rejection rolls transaction back")
	check(giver.get_inventory_snapshot() == source_before and receiver.get_inventory_snapshot() == target_before, "rollback preserves both complete inventories and revisions")
	check(not giver._handoff_transaction and not receiver._handoff_transaction, "rollback clears both transaction guards")
	clean(giver); clean(receiver)
	giver.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": 2.8})
	token = await offer(&"fuel_can")
	giver.handoff._lease = Time.get_ticks_msec() - 1
	check(not giver.handoff.accept_authoritative(receiver, token) and giver.has_held_item(&"fuel_can"), "expired lease is rejected before next physics tick")
	giver.handoff.cancel_authoritative()
	token = await offer(&"fuel_can")
	giver.drop_current_item_authoritative()
	check(not giver.handoff.accept_authoritative(receiver, token) and receiver._held_item_type == &"", "drop then accept cannot create another held item")
	clean(giver); clean(receiver)
	giver.tape_count = 1
	token = await offer(&"tape", true)
	giver.tape_count = 0
	check(not giver.handoff.accept_authoritative(receiver, token) and receiver.tape_count == 0, "removed source item cannot be accepted")
	clean(giver); clean(receiver)
	giver.tape_count = 1
	token = await offer(&"tape", true)
	giver.drop_all_items_at_authoritative(giver.get_held_item_drop_transform())
	check(not giver.handoff.is_offering(), "disconnect cleanup immediately invalidates pocket offer")
	check(not giver.handoff.accept_authoritative(receiver, token) and receiver.tape_count == 0 and giver.tape_count == 0, "late acceptance after disconnect cleanup cannot copy dropped loot")
	arena.queue_free()
	await create_timer(0.3).timeout
	print("HANDOFF CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
