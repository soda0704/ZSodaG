extends Node
var host := false
var port := 28767
var failures := 0
var checks := 0
var client_is_ready := false
var phase_reported_day := 0
var world: Node
var finish_wait := 0.0
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
func wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 25000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()
func seed_expedition() -> void:
	var config := ConfigFile.new()
	config.set_value("save", "version", 1)
	config.set_value("base", "day_index", 3)
	config.set_value("base", "campaign_layout_version", 2)
	config.set_value("base", "phase", 2)
	config.set_value("base", "fuel_delivered", true)
	config.set_value("base", "fuel_liters", 18.0)
	config.set_value("base", "main_breaker_on", true)
	config.set_value("base", "elevator_backup_installed", true)
	config.set_value("base", "maintenance", {"elevator_floor": 2})
	config.set_value("base", "containment", {"level2": true})
	config.set_value("inventory", "checkpoint", {"players": {
		"test:host": {"held_item": &"pistol", "weapon_rounds": 7},
		"test:guest": {"held_item": &"fuel_can", "fuel_liters": 8.0}},
		"participants": {
			"test:host": {"in_cabin": true, "transform": Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.1, 0)), "survival": {"health": 67.0}},
			"test:guest": {"in_cabin": true, "transform": Transform3D(Basis.IDENTITY, Vector3(0.6, 0.1, 0)), "survival": {"health": 42.0}}},
		"pickups": [], "weapon_layout_version": 1, "fuel_layout_version": 1,
		"tools_layout_version": 1, "discoverable_layout_version": 2, "tape_layout_version": 1,
		"prop_layout_version": 1, "elevator_backup_layout_version": 1})
	check(ExpeditionSaveStore.write(config, "coop", "sleep"), "seed isolated saved expedition")
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	ExpeditionSaveStore.select("coop", 3)
	if host:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	else:
		# A client must not read or alter this unrelated local expedition.
		ExpeditionSaveStore.select("coop", 1)
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "create real ENet transport")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.uses_staging_lobby = true
	world.staging_spawns_path = NodePath("ArrivalCabin/Spawns")
	world.resume_base_on_start = true
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if host:
		world._on_session_ready(true)
		check(await wait_until(func(): return world._v3_items_spawned), "host resumed production base")
		print("HOST_READY_FOR_RESUME_CLIENT")
		check(await wait_until(func(): return client_is_ready), "late client receives resumed expedition")
		if not client_is_ready: get_tree().quit(1); return
		var actors: Array = world.players.get_children()
		check(actors.size() == 2, "host sees both restored players")
		for actor in actors:
			check(actor.survival.health == (67.0 if actor.owner_peer_id == 1 else 42.0), "host restored health for peer %d" % actor.owner_peer_id)
		check(world._base_gameplay_controller.save_progress_authoritative(false, "manual"), "host saves joined team")
		var state: BaseGameplayController = world._base_gameplay_controller
		check(not state.save_progress_authoritative(false, "manual"), "host cannot spend a second team manual save today")
		var manual_path: String = ExpeditionSaveStore.read("coop").path
		await get_tree().create_timer(5.3).timeout
		check(ExpeditionSaveStore.read("coop").path == manual_path, "live two-player session does not autosave every five seconds")
		for index in actors.size():
			var bunk: BaseEndDayBunk = state.get_parent().get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable%02d" % (index + 1))
			actors[index].teleport_authoritative(bunk.wake_pose.global_position, 0)
			bunk.network_sleep_interact(actors[index].owner_peer_id, actors[index])
		check(await wait_until(func(): return state.day_index == 4), "both players complete a real shared night")
		var mornings := ExpeditionSaveStore.checkpoints("coop")
		check(mornings[0].is_empty() and mornings[1].day_index == 4 and mornings[2].day_index == 3, "shared morning expires manual and retains exactly days four and three")
		check(state.can_manual_save() and state.save_progress_authoritative(false, "manual"), "next morning grants one new team manual save")
		var snapshot := state.get_snapshot()
		snapshot.day_index = 4
		snapshot.maintenance = {}
		state._broadcast_snapshot(snapshot)
		var trials: Area3D = state.get_parent().get_node("Floor_Minus3_Trials_Observation_Blockout/InvestigationZone")
		for actor in actors:
			if actor.owner_peer_id != 1:
				actor.teleport_authoritative(trials.global_position, 0)
		check(await wait_until(func(): return state.containment.get("trials", false)), "guest entering chamber completes shared trials objective on host")
		for day in [4, 5, 6, 7]:
			snapshot = state.get_snapshot()
			snapshot.day_index = day
			state._broadcast_snapshot(snapshot)
			check_campaign_phase.rpc(day)
			check(await wait_until(func(): return phase_reported_day == day), "guest validates campaign day %d" % day)
		var guest: GamePlayer = actors.filter(func(actor): return actor.owner_peer_id != 1)[0]
		ask_console_sleep.rpc_id(guest.owner_peer_id)
		check(await wait_until(func(): return state.day_index == 8), "guest console sleep is executed by the host")
		var console_save := ExpeditionSaveStore.read("coop")
		check(int(console_save.config.get_value("base", "day_index", 0)) == 8 and str(console_save.config.get_value("save", "kind", "")) == "sleep", "guest console command creates the shared morning file only on host")
		check(state.manual_save_day == 0 and state.can_manual_save(), "console night resets shared daily save allowance")
		verify_console_sleep.rpc_id(guest.owner_peer_id)
		check(await wait_until(func(): return phase_reported_day == 8), "guest verifies debug morning and recovery")
		finish.rpc(failures)
		await get_tree().create_timer(0.5).timeout
		print("COOP SAVE CHECKS ", checks, " FAILURES ", failures)
		get_tree().quit(1 if failures else 0)
	else:
		var local_before: String = ExpeditionSaveStore.read("coop").path
		check(await wait_until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client transport connected before session RPCs")
		world._on_session_ready(false)
		check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "client loaded restored scene and roster")
		await get_tree().create_timer(0.4).timeout
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		check(local != null, "client owns restored player")
		if local != null:
			check(local.has_held_item(&"fuel_can") and local.fuel_liters == 8.0, "client restored own account inventory")
			check(local.survival.health == 42.0, "client restored health instead of healing")
			check(world._v3_elevator_controller.current_floor_index == 2, "client sees saved elevator floor")
			check(world._v3_elevator_controller.cabin.to_local(local.global_position).distance_to(Vector3(0.6, 0.1, 0)) < 0.1, "client owns correct cabin-relative resume pose")
		check(world._base_gameplay_controller.day_index == 3 and world._base_gameplay_controller.containment.get("level2", false), "client receives host story progress")
		check(not world._base_gameplay_controller.save_progress_authoritative(false, "manual"), "client cannot save host world to local slot")
		check(ExpeditionSaveStore.read("coop").path == local_before, "client local expedition untouched")
		client_ready.rpc_id(1, failures)
		if not await wait_until(func(): return finish_wait > 0):
			check(false, "host finished save validation")
			get_tree().quit(1)
@rpc("any_peer", "call_remote", "reliable")
func client_ready(client_failures: int) -> void:
	if multiplayer.is_server():
		failures += client_failures
		client_is_ready = true
@rpc("authority", "call_remote", "reliable")
func check_campaign_phase(day: int) -> void:
	var state: BaseGameplayController = world._base_gameplay_controller
	check(await wait_until(func(): return state.day_index == day), "guest receives day %d without clamping" % day)
	check(state.containment.get("trials", false), "guest retains shared trials completion on day %d" % day)
	if day == 4:
		check(state.manual_save_day == 4, "guest receives the host's consumed daily save allowance")
		var menu := get_tree().root.get_node("GameMenu")
		menu.main_panel.refresh()
		check(menu.main_panel.get_node("Save").disabled and menu.main_panel.get_node("SaveHint").text.contains("использована"), "guest UI shows the shared used allowance")
	# Elevator snapshots deliberately apply on the next physics tick.
	check(await wait_until(func(): return world._v3_elevator_controller.unlocked_floor_index == mini(day - 1, 5)), "guest sees one new floor per day, capped at shaft")
	var encounter = state.get_parent().get_node("ContainmentEncounter")
	check(encounter.get_node("Monster0").visible == (day >= 5), "guest story creatures activate from containment day")
	campaign_phase_checked.rpc_id(1, day, failures)
	failures = 0

@rpc("any_peer", "call_remote", "reliable")
func campaign_phase_checked(day: int, client_failures: int) -> void:
	if multiplayer.is_server():
		failures += client_failures
		phase_reported_day = day

@rpc("authority", "call_remote", "reliable")
func finish(host_failures: int) -> void:
	finish_wait = 1.0
	check(host_failures == 0, "host and guest save validation successful")
	var state: BaseGameplayController = world._base_gameplay_controller
	var local_path: String = ExpeditionSaveStore.read("coop").path
	# A disconnected client's OfflineMultiplayerPeer must not acquire save ownership.
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	check(not state.save_progress_authoritative(false, "manual"), "disconnected client still cannot overwrite a local save")
	check(ExpeditionSaveStore.read("coop").path == local_path, "disconnect preserves unrelated local save")
	print("COOP SAVE CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

@rpc("authority", "call_remote", "reliable")
func ask_console_sleep() -> void:
	var result: String = get_tree().root.get_node("DeveloperConsole").execute("/sleep")
	check(result.contains("серверу"), "guest sleep request uses the existing server command route")

@rpc("authority", "call_remote", "reliable")
func verify_console_sleep() -> void:
	var state: BaseGameplayController = world._base_gameplay_controller
	var actor: GamePlayer = get_tree().get_first_node_in_group("local_player")
	check(await wait_until(func(): return state.day_index == 8 and not actor.is_sleeping_in_bunk() and actor.survival.health == actor.survival.max_health), "guest receives next day and awake healed player")
	check(state.manual_save_day == 0, "guest receives refreshed shared manual allowance")
	check(get_tree().root.get_node("GameMenu/SaveNotification").visible, "guest sees console morning save notification")
	campaign_phase_checked.rpc_id(1, 8, failures)
	failures = 0
