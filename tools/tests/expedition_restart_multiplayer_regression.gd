extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Two separate pairs of processes: save a live team, then resume that exact file.
var read_back := false
var done := false
var reported := false

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg == "--read-back": read_back = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="):
			ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	var isolated := str(ProjectSettings.get_setting(ExpeditionSaveStore.ROOT_SETTING))
	ProjectSettings.set_setting("northern_lab/testing/settings_path", isolated + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", isolated + "/controls.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, isolated + "/journal")
	BaseGameplayController.save_scope = "coop"
	ExpeditionSaveStore.select("coop", 3)
	if not read_back:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var local_path := str(ExpeditionSaveStore.read("coop").get("path", ""))
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "create fresh real ENet connection")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.uses_staging_lobby = true
	world.staging_spawns_path = NodePath("ArrivalCabin/Spawns")
	world.resume_base_on_start = true
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not host:
		check(await wait_until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client connects before starting session")
	world._on_session_ready(host)
	check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and (not host or world._v3_items_spawned)), "load production session")
	if host:
		world._base_gameplay_controller.set_process(false)
		world.set_process(false)
		print("RESTART_HOST_READY")
		check(await wait_until(func(): return client_is_ready), "new client loads and reports readiness")
		if not client_is_ready: get_tree().quit(1); return
		if not read_back:
			for actor in world.players.get_children():
				var is_host: bool = actor.owner_peer_id == 1
				actor.survival.restore_checkpoint_authoritative({"health": 61.0 if is_host else 37.0, "radiation": 12.0 if is_host else 23.0})
				if is_host: actor.weapon.rounds = 3
				else: actor.fuel_liters = 5.0
				actor.teleport_authoritative(Vector3(-0.6 if is_host else 0.6, 0.1, 0) + world._v3_elevator_controller.cabin.global_position, 0)
			var state: BaseGameplayController = world._base_gameplay_controller
			var previous_count: int = world.capture_inventory_checkpoint().pickups.size()
			world.spawn_world_item(&"fuel_can", Transform3D(Basis.IDENTITY, Vector3(1, 1, 1)), {"fuel_liters": 4.0, "restart_probe": true})
			var snapshot := state.get_snapshot()
			snapshot.maintenance["restart_probe_pickup_count"] = previous_count + 1
			snapshot.maintenance["generator_fault_discovered"] = true
			snapshot.maintenance["corpse_recovery"] = {"picked_up": true, "examined": true}
			snapshot.plant_seed_planted = true
			snapshot.plant_last_watered_day = 3
			state._broadcast_snapshot(snapshot)
			check(state.save_progress_authoritative(false, "manual"), "write actual live host and guest state to disk")
			var disk := ExpeditionSaveStore.read("coop")
			var inventory: Dictionary = disk.config.get_value("inventory", "checkpoint")
			check(inventory.players["test:guest"].fuel_liters == 5.0 and inventory.participants["test:guest"].survival.health == 37.0, "disk contains guest state under stable account identity")
			check(inventory.pickups.size() == previous_count + 1, "one extra world pickup committed before process shutdown")
		else:
			verify_resume()
			verify_remote.rpc()
			check(await wait_until(func(): return reported), "client independently verifies restored owned state")
		# The first pair closes on the explicitly committed snapshot. The second
		# pair additionally tests a real guest departure while the host stays live.
		if not read_back: world._base_gameplay_controller.progress_persistence_enabled = false
		finish_restart.rpc(failures)
		if read_back:
			check(await wait_until(func(): return world.players.get_child_count() == 1), "guest actually disconnects while host remains in expedition")
			var state: BaseGameplayController = world._base_gameplay_controller
			check(state.save_progress_authoritative(false, "manual"), "host can save after guest departure")
			var disk := ExpeditionSaveStore.read("coop")
			var checkpoint: Dictionary = disk.config.get_value("inventory", "checkpoint")
			check(StringName(checkpoint.players["test:guest"].held_item) == &"", "departed account saves empty hands instead of retaining a duplicate can")
			var dropped: Array = checkpoint.pickups.filter(func(item): return item.item_type == &"fuel_can" and item.item_state.get("fuel_liters", 0.0) == 5.0)
			check(dropped.size() == 1 and checkpoint.pickups.size() == int(state.maintenance.restart_probe_pickup_count) + 1, "guest fuel can is saved in world exactly once without loss or duplication")
		else:
			await get_tree().create_timer(.4).timeout
	else:
		check(await wait_until(func(): return world.players.get_child_count() == 2), "client sees both actors")
		check(not get_tree().root.get_node("GameMenu/SaveNotification").visible, "late join does not replay a previous save notice")
		restart_ready.rpc_id(1)
		check(await wait_until(func(): return done), "host finishes restart phase")
		check(str(ExpeditionSaveStore.read("coop").get("path", "")) == local_path, "client local save is untouched across live session")
	set_process(false)
	world._base_gameplay_controller.progress_persistence_enabled = false
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peer.close()
	get_tree().current_scene = null
	world.queue_free()
	for frame in 4: await get_tree().process_frame
	print("RESTART COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

func verify_resume() -> void:
	var state: BaseGameplayController = world._base_gameplay_controller
	check(state.day_index == 3 and state.containment.get("level2", false), "story survives complete host process restart")
	check(state.maintenance.get("generator_fault_discovered", false) and state.maintenance.get("corpse_recovery", {}).get("examined", false), "new journal task flags survive restart and late join")
	check(state.plant_seed_planted and state.plant_last_watered_day == 3, "plant and daily watering survive restart")
	check(world.world_items.get_child_count() == int(state.maintenance.get("restart_probe_pickup_count", -1)), "world loot is restored without duplication")
	var probes: Array = world.world_items.get_children().filter(func(item): return item.item_state.get("restart_probe", false))
	check(probes.size() == 1 and probes[0].item_type == &"fuel_can" and probes[0].item_state.fuel_liters == 4.0, "unique world pickup retains its remaining fuel")
	for actor in world.players.get_children():
		var is_host: bool = actor.owner_peer_id == 1
		check(actor.survival.health == (61.0 if is_host else 37.0) and absf(actor.survival.radiation - (12.0 if is_host else 23.0)) < 1.0, "HP and radiation restored for account %s" % ("host" if is_host else "guest"))
		check(actor.has_held_item(&"pistol") and actor.weapon.rounds == 3 if is_host else actor.has_held_item(&"fuel_can") and actor.fuel_liters == 5.0, "inventory and consumables restored for account %s" % ("host" if is_host else "guest"))
		check(world._v3_elevator_controller.cabin.to_local(actor.global_position).distance_to(Vector3(-0.6 if is_host else 0.6, .1, 0)) < .1, "account resumes at its saved cabin-relative position")

@rpc("any_peer", "call_remote", "reliable")
func restart_ready() -> void:
	if host: client_is_ready = true

@rpc("authority", "call_remote", "reliable")
func verify_remote() -> void:
	verify_resume()
	restart_report.rpc_id(1, failures)

@rpc("any_peer", "call_remote", "reliable")
func restart_report(count: int) -> void:
	if host:
		failures += count
		reported = true

@rpc("authority", "call_remote", "reliable")
func finish_restart(count: int) -> void:
	check(count == 0, "host verified live restart successfully")
	if not read_back:
		var notice := get_tree().root.get_node("GameMenu/SaveNotification")
		check(notice.visible and notice.title.text == "Сохранение…" and notice.icon.is_playing(), "guest receives host manual-save animation and status")
	done = true
