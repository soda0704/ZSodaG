extends Node

var _host := false
var _world: Node
var _state: BaseGameplayController
var _finished := false
var _flight_verified := false


func _ready() -> void:
	_host = OS.get_cmdline_user_args().has("host")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,
		"user://day_two_network_host_test.cfg" if _host else "user://day_two_network_client_test.cfg")
	BaseGameplayController.delete_progress_save()
	_watchdog()
	_run()


func _watchdog() -> void:
	await get_tree().create_timer(25.0).timeout
	if not _finished:
		_finish(false, "Timed out waiting for network progress")


func _run() -> void:
	_world = load("res://scenes/tests/mechanics_test_room.tscn").instantiate()
	_world.name = "World"
	add_child(_world)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(29473, 2) if _host else peer.create_client("127.0.0.1", 29473)
	if result != OK:
		_finish(false, "Transport failed")
		return
	multiplayer.multiplayer_peer = peer
	if not _host:
		return
	_world._on_session_ready(true)
	await _world._enter_v3_level()
	_state = _world.get_node("V3Level/BaseGameplayController")
	_state._broadcast_snapshot({"day_index": 2, "phase": 2, "fuel_delivered": true, "main_breaker_on": true, "quest_stage": 1})
	_state.advance_quest_authoritative(1, BaseGameplayController.QuestStage.OFFERED)
	_state.advance_quest_authoritative(1, BaseGameplayController.QuestStage.ACCEPTED)
	var host_player := _world.get_node("Players/1")
	host_player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.3})
	host_player.pickup_world_item_authoritative(&"battery", {"charge_amount": 1.0})
	host_player.pickup_world_item_authoritative(&"fuel_can", {})
	print("DAY_TWO_NETWORK_HOST_READY")
	_state.snapshot_changed.connect(_on_host_snapshot)


func _process(_delta: float) -> void:
	if _host or _finished or _state != null or _world == null:
		return
	var state := _world.get_node_or_null("V3Level/BaseGameplayController") as BaseGameplayController
	if state == null or state.quest_stage != BaseGameplayController.QuestStage.COLLECTED:
		return
	_state = state
	var host_player := _world.get_node_or_null("Players/1")
	if host_player == null or not host_player.get_inventory_snapshot().has_flashlight:
		_state = null
		return
	var inventory: Dictionary = host_player.get_inventory_snapshot()
	if inventory.held_item != &"fuel_can" or inventory.spare_batteries.size() != 1 or inventory.flashlight_enabled:
		_finish(false, "Late join lost pocket inventory or enabled the stowed light")
		return
	_state.snapshot_changed.connect(_on_client_snapshot)
	_late_join_confirmed.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _late_join_confirmed() -> void:
	if not _host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := _world.get_node("Players/%d" % sender)
	player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 0.1})
	player.pickup_world_item_authoritative(&"battery", {"charge_amount": 1.0})
	player.pickup_world_item_authoritative(&"battery", {"charge_amount": 0.75})
	var terminal := _world.get_node("V3Level/DayTwoTaskTerminal") as Node3D
	var standing := terminal.global_position + terminal.global_basis.z * 1.8
	standing.y = 0.1
	player.teleport_authoritative(standing, terminal.global_rotation.y)
	_deliver_from_client.rpc_id(sender)


@rpc("authority", "call_remote", "reliable")
func _deliver_from_client() -> void:
	# Give the reliable teleport on the player channel time to arrive.
	await get_tree().create_timer(0.25).timeout
	var player := _world.get_node("Players/%d" % multiplayer.get_unique_id())
	var console := get_node("/root/DeveloperConsole")
	console.execute("/across")
	await get_tree().create_timer(0.35).timeout
	if not player.debug_fly or not player.debug_across:
		_finish(false, "Guest flight flags did not replicate")
		return
	var flight_start: Vector3 = player.global_position
	# Headless DisplayServer cannot capture the mouse. Send the same owner input
	# packet that holding Space produces, and check actual server movement.
	player.set_physics_process(false)
	player._input_sequence += 100
	player._submit_input.rpc_id(1, player._input_sequence, Vector2.ZERO, false, false, 0, 0, 0, 0, 0.0, 0.0, 1.0)
	await get_tree().create_timer(0.4).timeout
	_verify_guest_flight.rpc_id(1, flight_start.y)
	await get_tree().create_timer(0.15).timeout
	player.set_physics_process(true)
	if not _flight_verified:
		_finish(false, "Guest flight input did not move its player on the server")
		return
	console.execute("/across")
	await get_tree().create_timer(0.35).timeout
	_return_test_player.rpc_id(1)
	await get_tree().create_timer(0.25).timeout
	var console_return: Transform3D = player.global_transform
	if "отправлена" not in console.execute("/testroom"):
		_finish(false, "Client console command was not forwarded to server")
		return
	await get_tree().create_timer(0.35).timeout
	var developer_room := _world.get_node("V3Level/DeveloperTestRoom") as DeveloperTestRoom
	if not developer_room.contains(player.global_position):
		_finish(false, "Client console did not teleport its requesting player")
		return
	console.execute("/testroom")
	await get_tree().create_timer(0.35).timeout
	if player.global_position.distance_to(console_return.origin) > 0.1:
		_finish(false, "Client console did not return its requesting player")
		return
	_test_player_death.rpc_id(1)
	await get_tree().create_timer(0.4).timeout
	if not player.survival.dead:
		_finish(false, "Server death did not replicate to owner")
		return
	player.request_inventory_action(&"drop_battery")
	await get_tree().create_timer(4.2).timeout
	if player.survival.dead or player.survival.health != 100.0 or player.get_inventory_snapshot().spare_batteries.size() != 2:
		_finish(false, "Respawn or dead-player inventory lock failed")
		return
	_return_test_player.rpc_id(1)
	await get_tree().create_timer(0.25).timeout
	_arm_test_player.rpc_id(1)
	await get_tree().create_timer(0.25).timeout
	player.weapon.request_action(&"fire")
	await get_tree().create_timer(0.35).timeout
	if player.weapon.rounds != 11:
		_finish(false, "Client weapon shot did not replicate ammo")
		return
	player.weapon.request_action(&"reload")
	await get_tree().create_timer(1.6).timeout
	if player.weapon.rounds != 12 or player.weapon.pistol_ammo != 11:
		_finish(false, "Client finite-ammo reload did not replicate")
		return
	# Attempting an action on somebody else's player must be rejected by host.
	var host_player := _world.get_node("Players/1")
	host_player._request_inventory_action.rpc_id(1, &"drop_flashlight")
	player.request_inventory_action(&"replace_battery")
	await get_tree().create_timer(1.2).timeout
	var equipment: Dictionary = player.get_inventory_snapshot()
	if not host_player.get_inventory_snapshot().has_flashlight:
		_finish(false, "Owner validation allowed discarding another player's flashlight")
		return
	if equipment.spare_batteries.size() != 2 or float(equipment.battery_charge) < 0.95:
		_finish(false, "Client battery replacement did not replicate")
		return
	player.request_inventory_action(&"drop_battery")
	await get_tree().create_timer(0.25).timeout
	if player.get_inventory_snapshot().spare_batteries.size() != 1:
		_finish(false, "Client battery discard did not replicate")
		return
	_setup_wiring_test.rpc_id(1)
	await get_tree().create_timer(0.5).timeout
	player.request_inventory_action(&"mount_light")
	await get_tree().create_timer(0.3).timeout
	if not player.weapon_light_mounted or player.tape_count != 0:
		_finish(false, "Client attachment/tape transaction did not replicate")
		return
	player.request_reload_or_battery()
	await get_tree().create_timer(1.2).timeout
	if player._battery_charge <= 0.0 or player.weapon.reload_left > 0.0:
		_finish(false, "Client R did not prioritize mounted battery")
		return
	var cargo_found := false
	for item in _world.get_node("Gameplay/WorldItems").get_children():
		if item.item_state.get("test_cargo", false):
			cargo_found = is_instance_valid(item._cargo_cabin) and item._cargo_cabin.to_local(item.global_position).distance_to(item._cargo_pose.origin) < 0.02
	if not cargo_found:
		_finish(false, "Cabin-local cargo state did not replicate")
		return
	var wiring := get_tree().get_first_node_in_group("wiring_ui")
	if wiring == null or not _state._siren.playing:
		_finish(false, "Client wiring panel or alarm missing")
		return
	for i in 4:
		wiring._select(i)
		wiring._connect(int(_state.maintenance.wire_order[i]))
		await get_tree().create_timer(0.15).timeout
	if _state.maintenance.wires_required or _state.main_breaker_on:
		_finish(false, "Client wire repair failed or automatically restarted breaker")
		return
	wiring._close()
	_restart_wiring_test.rpc_id(1)
	await get_tree().create_timer(0.3).timeout
	if not _state.main_breaker_on or _state._siren.playing:
		_finish(false, "Restart or alarm silence did not replicate")
		return
	_return_test_player.rpc_id(1)
	await get_tree().create_timer(0.25).timeout
	var terminal := _world.get_node("V3Level/DayTwoTaskTerminal") as Node3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set("_input_yaw", terminal.global_rotation.y)
	player.set("_input_pitch", -atan2(player.head.global_position.y - terminal.global_position.y, 1.8))
	player.set("_interact_serial", int(player.get("_interact_serial")) + 1)


@rpc("any_peer", "call_remote", "reliable")
func _verify_guest_flight(start_y: float) -> void:
	if _host:
		var sender := multiplayer.get_remote_sender_id()
		var player := _state.get_player_node(sender)
		_guest_flight_result.rpc_id(sender, player.global_position.y > start_y + 1.0 and not _state.get_player_node(1).debug_fly)

@rpc("authority", "call_remote", "reliable")
func _guest_flight_result(passed: bool) -> void:
	_flight_verified = passed

func _on_host_snapshot(snapshot: Dictionary) -> void:
	if int(snapshot.get("quest_stage", 0)) == 4:
		print("DAY_TWO_NETWORK_HOST_DELIVERED")


@rpc("any_peer", "call_remote", "reliable")
func _setup_wiring_test() -> void:
	if not _host:
		return
	var sender := multiplayer.get_remote_sender_id()
	var player := _state.get_player_node(sender)
	player.pickup_world_item_authoritative(&"tape", {})
	player._battery_charge = 0.0
	player._publish_inventory()
	var cabin: Node3D = _world.get_node("V3Level/Elevator_Functional_Blockout/CabinMoving")
	var items: Node3D = _world.get_node("Gameplay/WorldItems")
	_world.spawn_world_item(&"fuel_can", items.global_transform.affine_inverse() * Transform3D(Basis.IDENTITY, cabin.to_global(Vector3(0, 0.5, 0))), {"fuel_liters": 0.0, "test_cargo": true})
	var snapshot := _state.get_snapshot()
	snapshot.main_breaker_on = false
	snapshot.maintenance = {"wires_required": true, "wire_order": [2, 0, 3, 1], "wire_links": [], "alarm": true}
	_state._broadcast_snapshot(snapshot)
	var breaker := get_tree().get_first_node_in_group("main_breaker") as Node3D
	player.teleport_authoritative(breaker.global_position + Vector3(0, 0, 1.0), 0)
	breaker.network_interact(sender, player)


@rpc("any_peer", "call_remote", "reliable")
func _restart_wiring_test() -> void:
	if _host:
		_state.activate_main_breaker_authoritative(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func _test_player_death() -> void:
	if not multiplayer.is_server():
		return
	var player := _world.get_node("Players/%d" % multiplayer.get_remote_sender_id())
	player.survival.damage(100.0, "Network test")


@rpc("any_peer", "call_remote", "reliable")
func _return_test_player() -> void:
	if not multiplayer.is_server():
		return
	var player := _world.get_node("Players/%d" % multiplayer.get_remote_sender_id())
	var terminal := _world.get_node("V3Level/DayTwoTaskTerminal") as Node3D
	var standing := terminal.global_position + terminal.global_basis.z * 1.8
	standing.y = 0.1
	player.teleport_authoritative(standing, terminal.global_rotation.y)

@rpc("any_peer", "call_remote", "reliable")
func _arm_test_player() -> void:
	if multiplayer.is_server():
		var player := _world.get_node("Players/%d" % multiplayer.get_remote_sender_id())
		player.pickup_world_item_authoritative(&"pistol", {})
		player.pickup_world_item_authoritative(&"pistol_ammo", {"amount": 12})


func _on_client_snapshot(snapshot: Dictionary) -> void:
	if int(snapshot.get("quest_stage", 0)) == 4:
		_client_complete.rpc_id(1)
		await get_tree().create_timer(0.25).timeout
		_finish(true, "Late join and client-authoritative-input delivery replicated")


@rpc("any_peer", "call_remote", "reliable")
func _client_complete() -> void:
	if _host and _state.quest_stage == BaseGameplayController.QuestStage.DELIVERED:
		await get_tree().create_timer(0.5).timeout
		_finish(true, "Host confirmed the client delivery")


func _finish(success: bool, reason: String) -> void:
	if _finished:
		return
	_finished = true
	print("DAY_TWO_NETWORK_TEST %s: %s — %s" % ["HOST" if _host else "CLIENT", "PASS" if success else "FAIL", reason])
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if _world != null:
		_world.free()
	BaseGameplayController.delete_progress_save()
	get_tree().quit(0 if success else 1)
