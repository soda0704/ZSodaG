extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures.append(label)

func run() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://sprint_boost_test.cfg")
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	root.get_node("GameMenu").force_close_menu()
	await process_frame
	var player: GamePlayer = get_first_node_in_group("network_players")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player._server_move = Vector2(0, -1)
	player._server_sprint = true
	player._update_sprint(0.1)
	check(player._sprint_active and player.sprint_speed == 6.8, "slightly faster sprint starts")
	for tick in 61:
		player._update_sprint(0.1)
	check(not player._sprint_active and player._sprint_rest > 0, "held Shift cannot bypass six-second limit")
	var rest := player._sprint_rest
	for tick in 10:
		player._server_sprint = tick % 2 == 0
		player._update_sprint(0.1)
	check(not player._sprint_active and player._sprint_rest < rest, "tapping Shift cannot bypass rest")
	player._server_sprint = true
	player._update_sprint(4.0)
	player._update_sprint(0.1)
	check(player._sprint_active, "sprint available again after rest")
	player._server_move = Vector2.ZERO
	player._update_sprint(0.1)
	check(not player._sprint_active and player._sprint_rest > 0, "ending a short burst also requires rest")
	player._update_sprint(4.0)
	player._server_move = Vector2(0, -1)
	player._server_crouch = true
	player._update_sprint(0.1)
	check(not player._sprint_active and player._sprint_remaining == player.sprint_duration, "crouching does not consume sprint")
	player._receive_authoritative_state(player.position, Vector3.ZERO, 0, 0, false, &"", false, 0, false, false, 0, {}, Vector3(2, 3, 0))
	check(player._sprint_remaining == 2 and player._sprint_rest == 3, "server snapshot corrects predicted sprint budget")
	var vehicle = load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
	vehicle.set_physics_process(false)
	root.add_child(vehicle)
	await process_frame
	vehicle.driver_peer = player.owner_peer_id
	vehicle.fuel_liters = 10.0
	vehicle._advance_ignition(0.0)
	vehicle._advance_ignition(vehicle.ignition_duration())
	vehicle.set_driver_input(player.owner_peer_id, Vector2(0, -1), true)
	vehicle._speed = vehicle.max_speed * vehicle.boost_speed_multiplier
	vehicle._physics_process(0.1)
	check(is_equal_approx(vehicle._speed, 14.4), "Shift permits twenty percent higher forward speed")
	var boosted_fuel: float = 10.0 - vehicle.fuel_liters
	vehicle.fuel_liters = 10.0
	vehicle.set_driver_input(player.owner_peer_id, Vector2(0, -1), false)
	vehicle._physics_process(0.1)
	var normal_fuel: float = 10.0 - vehicle.fuel_liters
	check(absf(boosted_fuel / normal_fuel - 2.0) < 0.002, "boost doubles actual fuel consumption")
	vehicle.set_driver_input(player.owner_peer_id + 100, Vector2(0, -1), true)
	check(not vehicle._input_boost, "other peers cannot enable boost")
	vehicle.set_driver_input(player.owner_peer_id, Vector2(0, 1), true)
	vehicle._speed = -vehicle.reverse_speed
	vehicle._physics_process(0.1)
	check(is_equal_approx(vehicle._speed, -3.0), "reverse speed stays unchanged")
	vehicle.set_driver_input(player.owner_peer_id, Vector2(0, -1), true)
	vehicle._input_age = 1.0
	vehicle.fuel_liters = 10.0
	vehicle._physics_process(0.1)
	check(vehicle.fuel_liters == 10.0, "stale input cannot consume boost fuel")
	vehicle._receive_state(vehicle.global_transform, 2, player.owner_peer_id, 14.4)
	check(is_equal_approx(vehicle._received_speed, 14.4), "boost speed survives vehicle replication")
	print("RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
