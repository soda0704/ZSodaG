extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Real ENet, production base/session, late join in motion and client travel input.
var winch: FunctionalElevatorController
var guest_id := 0
var reports := {}
var largest_platform_error := 0.0

func _process(_delta: float) -> void:
	if world == null: return
	get_tree().root.get_node("GameMenu").force_close_menu()
	for player in world.players.get_children():
		player.survival.set_physics_process(false)
		player.survival.debug_invincible = true
	if winch != null and winch.state == winch.ElevatorState.MOVING:
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		if local != null and local.is_on_floor():
			largest_platform_error = maxf(largest_platform_error, absf(local.global_position.y - winch.cabin.global_position.y))

func seed_expedition() -> void:
	super.seed_expedition()
	var config: ConfigFile = ExpeditionSaveStore.read("coop").config
	config.set_value("base", "day_index", 7)
	config.set_value("base", "maintenance", {"elevator_floor": 5, "winch_floor": 0, "winch_preparation": {"inspected":true, "pin_removed":true, "brake_armed":true, "tested":true}})
	var checkpoint: Dictionary = config.get_value("inventory", "checkpoint")
	for key in checkpoint.participants:
		checkpoint.participants[key]["cabin_id"] = "winch_floor"
	config.set_value("inventory", "checkpoint", checkpoint)
	check(ExpeditionSaveStore.write(config, "coop", "sleep"), "seed isolated day-seven winch expedition")

func run() -> void:
	Engine.max_fps = 60
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	if host:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real winch ENet connection")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.uses_staging_lobby = true
	world.staging_spawns_path = NodePath("ArrivalCabin/Spawns")
	world.resume_base_on_start = true
	get_tree().root.add_child(world); get_tree().current_scene = world
	if not host:
		check(await wait_until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client connects before session requests")
		world._on_session_ready(false)
		check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "late client loads production shaft and both players")
		winch = get_tree().get_first_node_in_group("expedition_winches")
		check(await wait_until(func(): return winch._snapshot_received), "session synchronizes the additional transport")
		check(winch.state == winch.ElevatorState.MOVING and winch._active_destination_floor_index == 1, "late join continues existing descent")
		check(not winch.cabin_door.is_open and not winch._get_landing_door(0).is_open and not winch._get_landing_door(1).is_open, "late join sees all moving-cage gates shut")
		check(await wait_until(func(): return winch._cabin_motion_elapsed > 0.1 and winch.cabin.position.y < -0.1), "late join restores original motion progress")
		winch_ready.rpc_id(1)
		return
	world._on_session_ready(true)
	check(await wait_until(func(): return world._v3_items_spawned), "host resumes production winch")
	winch = get_tree().get_first_node_in_group("expedition_winches")
	world._base_gameplay_controller.set_process(false)
	winch.travel_speed = 6.0
	winch.travel_start_stop_time = 0.5
	world.spawn_world_item(&"fuel_can", winch.cabin.global_transform * Transform3D(Basis.IDENTITY, Vector3(1.4,0.5,0.8)), {"amount":10.0})
	for frame in 20: await get_tree().physics_frame
	check(winch.request_floor(1), "host starts descent from restored cage")
	check(await wait_until(func(): return winch.state == winch.ElevatorState.MOVING), "host departs before client starts loading")
	print("HOST_READY_FOR_WINCH_CLIENT")
	check(await wait_until(func(): return guest_id > 0), "late client acknowledges moving winch")
	if guest_id == 0: get_tree().quit(1); return
	check(await wait_until(func(): return winch.current_floor_index == 1 and winch.state == winch.ElevatorState.IDLE_OPEN), "host arrives at cave with joined passenger")
	for player in world.players.get_children():
		check(absf(player.global_position.y - winch.cabin.global_position.y) < 0.4, "host carries passenger %d" % player.owner_peer_id)
	check(world._base_gameplay_controller.containment.get("cave_visited", false), "descent completes shared shaft visit")
	request_winch_report.rpc_id(guest_id, "lower")
	check(await wait_until(func(): return reports.has("lower")), "client reports lower arrival")
	var lower: Dictionary = reports.get("lower", {})
	check(lower.get("floor", -1) == 1 and lower.get("lower_open", false) and not lower.get("upper_open", true), "client opens only the lower landing")
	check(float(lower.get("floor_error", 999)) < 0.5, "client remains supported by moving cage")
	var attached := false
	for item in world.world_items.get_children():
		if item.item_type == &"fuel_can" and item._cargo_cabin == winch.cabin: attached = true
	check(attached, "loose cargo rides winch through existing cabin mechanism")
	check(world._base_gameplay_controller.save_progress_authoritative(false, "manual"), "save lower-stop expedition")
	check(world._base_gameplay_controller.load_saved_snapshot().maintenance.get("winch_floor", -1) == 1, "saved expedition retains independent winch stop")
	var checkpoint: Dictionary = world._base_gameplay_controller.inventory_checkpoint
	check(checkpoint.participants.values().all(func(data): return data.get("cabin_id", "") == "winch_floor"), "save records both passengers relative to correct cabin")
	winch.travel_speed = 4.5
	press_up.rpc_id(guest_id)
	check(await wait_until(func(): return winch.current_floor_index == 0 and winch.state == winch.ElevatorState.IDLE_OPEN), "client input starts synchronized return to level five")
	request_winch_report.rpc_id(guest_id, "upper")
	check(await wait_until(func(): return reports.has("upper")), "client reports upper arrival")
	var upper: Dictionary = reports.get("upper", {})
	check(upper.get("floor", -1) == 0 and upper.get("upper_open", false) and not upper.get("lower_open", true), "client closes lower landing after return")
	check(float(upper.get("floor_error", 999)) < 0.5, "client completes return on platform")
	finish_winch.rpc_id(guest_id, failures)
	await get_tree().create_timer(0.4).timeout
	print("WINCH COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

@rpc("any_peer", "call_remote", "reliable")
func winch_ready() -> void:
	if host: guest_id = multiplayer.get_remote_sender_id()

@rpc("authority", "call_remote", "reliable")
func request_winch_report(label: String) -> void:
	await get_tree().create_timer(0.3).timeout
	var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
	check(absf(local.global_position.y - winch.cabin.global_position.y) < 0.5, "client passenger stands at " + label)
	print("PLATFORM ERROR ", largest_platform_error, " at ", label)
	winch_report.rpc_id(1, label, {"floor":winch.current_floor_index, "lower_open":winch._get_landing_door(1).is_open, "upper_open":winch._get_landing_door(0).is_open, "floor_error":largest_platform_error})

@rpc("any_peer", "call_remote", "reliable")
func winch_report(label: String, data: Dictionary) -> void:
	if host: reports[label] = data

@rpc("authority", "call_remote", "reliable")
func press_up() -> void:
	var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
	var button: Node3D = winch.get_node("CabinMoving/UpButton")
	var offset := button.global_position - local.camera.global_position
	local.rotation.y = atan2(-offset.x, -offset.z)
	local.head.rotation.x = atan2(offset.y, Vector2(offset.x,offset.z).length())
	local._input_yaw = local.rotation.y
	local._input_pitch = local.head.rotation.x
	await get_tree().physics_frame
	check(local.get_interaction_target() == button, "client production interaction ray reaches up button")
	local._interact_serial += 1

@rpc("authority", "call_remote", "reliable")
func finish_winch(host_failures: int) -> void:
	check(host_failures == 0, "host winch validation passed")
	print("WINCH COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
