extends Node

var _host := false
var _world: Node
var _state: BaseGameplayController
var _finished := false


func _ready() -> void:
	_host = OS.get_cmdline_user_args().has("host")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,
		"user://day_two_network_host_test.cfg" if _host else "user://day_two_network_client_test.cfg")
	BaseGameplayController.delete_progress_save()
	_watchdog()
	_run()


func _watchdog() -> void:
	await get_tree().create_timer(18.0).timeout
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
	# Attempting an action on somebody else's player must be rejected by host.
	var host_player := _world.get_node("Players/1")
	host_player._request_inventory_action.rpc_id(1, &"drop_flashlight")
	player.request_inventory_action(&"replace_battery")
	await get_tree().create_timer(0.3).timeout
	var equipment: Dictionary = player.get_inventory_snapshot()
	if not host_player.get_inventory_snapshot().has_flashlight:
		_finish(false, "Owner validation allowed discarding another player's flashlight")
		return
	if equipment.spare_batteries.size() != 1 or float(equipment.battery_charge) < 0.95:
		_finish(false, "Client battery replacement did not replicate")
		return
	player.request_inventory_action(&"drop_battery")
	await get_tree().create_timer(0.25).timeout
	if not player.get_inventory_snapshot().spare_batteries.is_empty():
		_finish(false, "Client battery discard did not replicate")
		return
	var terminal := _world.get_node("V3Level/DayTwoTaskTerminal") as Node3D
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.set("_input_yaw", terminal.global_rotation.y)
	player.set("_input_pitch", -atan2(player.head.global_position.y - terminal.global_position.y, 1.8))
	player.set("_interact_serial", int(player.get("_interact_serial")) + 1)


func _on_host_snapshot(snapshot: Dictionary) -> void:
	if int(snapshot.get("quest_stage", 0)) == 4:
		print("DAY_TWO_NETWORK_HOST_DELIVERED")


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
