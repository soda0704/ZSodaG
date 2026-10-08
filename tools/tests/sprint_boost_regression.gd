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
	player._update_sprint(4.0)
	check(player._sprint_active and player.sprint_speed == 6.8 and is_equal_approx(player._sprint_remaining,6.0), "four seconds of sprint leave six of the ten-second reserve")
	player._server_move = Vector2.ZERO
	player._server_sprint = false
	player._update_sprint(0.0)
	check(not player._sprint_active and not player._sprint_exhausted and is_equal_approx(player._sprint_remaining,6.0), "stopping preserves remaining sprint with no cooldown")
	player._server_move = Vector2(0,-1)
	player._server_sprint = true
	player._update_sprint(0.0)
	check(player._sprint_active and is_equal_approx(player._sprint_remaining,6.0), "immediate restart can use the remaining six seconds")
	player._server_move = Vector2.ZERO
	player._server_sprint = false
	player._update_sprint(2.0)
	check(is_equal_approx(player._sprint_remaining,8.0), "two seconds of rest restore two seconds of sprint")
	player._server_move = Vector2(0, -1)
	player._server_sprint = true
	player._update_sprint(8.0)
	check(not player._sprint_active and player._sprint_exhausted and player._sprint_remaining==0.0, "only complete exhaustion pauses sprint")
	player._update_sprint(0.5)
	check(not player._sprint_active and player._sprint_exhausted and is_equal_approx(player._sprint_remaining,0.5), "held Shift cannot alternate sprint and walk every tick after exhaustion")
	player._update_sprint(0.5)
	player._update_sprint(0.0)
	check(player._sprint_active and not player._sprint_exhausted and is_equal_approx(player._sprint_remaining,1.0), "one second of recovery permits another sprint without a long lockout")
	player._server_sprint = false
	player._update_sprint(30.0)
	check(player._sprint_remaining==player.sprint_duration, "recovery cannot exceed capacity")
	player._server_crouch = true
	player._server_sprint = true
	player._update_sprint(0.1)
	check(not player._sprint_active and player._sprint_remaining == player.sprint_duration, "crouching does not consume sprint")
	player._receive_authoritative_state(player.position, Vector3.ZERO, 0, 0, false, &"", false, 0, false, false, 0, {}, Vector3(0.4, 1, 0))
	check(is_equal_approx(player._sprint_remaining,0.4) and player._sprint_exhausted, "server snapshot corrects reserve and exhaustion latch")
	check(player.get_node_or_null("PlayerUI/SprintLabel")==null, "sprint and recovery counters are removed from the authored HUD")
	var radiation_zone: Node3D = get_first_node_in_group("radiation_zones")
	var survival := player.survival
	player.global_position = radiation_zone.global_position+Vector3.UP
	survival.health = survival.max_health
	survival.radiation = 0.0
	for tick in 360: survival._physics_process(1.0/60.0)
	check(absf(survival.radiation-27.0)<0.02 and survival.health==survival.max_health, "six seconds at the actual radiation source no longer damage the player")
	player.global_position = radiation_zone.global_position+Vector3(30,1,0)
	for tick in 181: survival._physics_process(1.0/60.0)
	check(survival.radiation<0.02 and survival.health==survival.max_health,"dose still recovers normally after leaving the reservoir")
	var vehicle = load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
	vehicle.set_physics_process(false)
	root.add_child(vehicle)
	await process_frame
	# Speed-limit check needs free space; a wall collision now correctly removes momentum.
	vehicle.global_position = Vector3(0, 100, 0)
	vehicle.velocity = Vector3.ZERO
	vehicle.driver_peer = player.owner_peer_id
	vehicle.fuel_liters = 10.0
	vehicle._advance_ignition(0.0)
	vehicle._advance_ignition(vehicle.ignition_duration())
	vehicle.set_driver_input(player.owner_peer_id, Vector2(0, -1), true)
	vehicle._speed = vehicle.max_speed * vehicle.boost_speed_multiplier
	vehicle._physics_process(0.1)
	check(is_equal_approx(vehicle._speed, 14.4), "Shift permits twenty percent higher forward speed")
	check(vehicle.get_interaction_prompt().is_empty(), "moving vehicle does not show a stop warning")
	player.vehicle = vehicle
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.refresh_interaction_prompt()
	check(not player.interaction_prompt_label.text.contains("Останов"), "driver HUD also removes the stop instruction")
	player.vehicle = null
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
