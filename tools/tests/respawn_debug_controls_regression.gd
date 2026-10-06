extends SceneTree
var failures: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ", label)
	if not value: failures.append(label)
func run() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://respawn_debug_controls_test.cfg")
	var world = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(world)
	root.get_node("GameMenu").force_close_menu()
	await physics_frame
	await process_frame
	var player: GamePlayer = get_first_node_in_group("network_players")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.weapon.set_physics_process(false)
	player.get_node("ItemDrag").set_physics_process(false)
	var state: BaseGameplayController = world.get_node("BaseGameplayController")
	state.main_breaker_on = false
	player.survival.dead = true
	player.survival._respawn()
	check(player.global_position.distance_to(world.get_player_spawn_position(0) + Vector3.UP * 0.1) < 0.01, "death with generator off respawns at authored helicopter marker")
	state.main_breaker_on = true
	player.survival.dead = true
	player.survival._respawn()
	check(player.global_position.distance_to(world.get_day_start_transform(0).origin + Vector3.UP * 0.1) < 0.01, "death with generator on retains room respawn")
	state.main_breaker_on = false
	check(world.get_respawn_transform(1).origin == world.get_player_spawn_position(1), "second player retains its own helicopter spawn")
	var console = root.get_node("DeveloperConsole")
	console._execute_authoritative(PackedStringArray(["/speed", "3"]), state, player.owner_peer_id)
	check(player.debug_speed_multiplier == 3, "console changes calling player's movement multiplier")
	console._execute_authoritative(PackedStringArray(["/speed", "oops"]), state, player.owner_peer_id)
	console._execute_authoritative(PackedStringArray(["/speed", "100"]), state, player.owner_peer_id)
	check(player.debug_speed_multiplier == 3, "invalid or out-of-range speed cannot change movement")
	player.debug_fly = true
	player.debug_across = true
	player.simulate_movement(0.1, Vector2(0, -1), false, false, false, 0, 0)
	check(is_equal_approx(player.velocity.length(), 21.0), "flight uses speed multiplier")
	player.simulate_movement(0.1, Vector2(0, -1), true, false, false, 0, 0)
	check(is_equal_approx(player.velocity.length(), 54.0), "Shift retains faster debug flight")
	var inventory := player.get_inventory_snapshot()
	player.debug_speed_multiplier = 1
	player.apply_inventory_snapshot(inventory)
	check(player.debug_speed_multiplier == 3, "authoritative snapshot replicates speed for client prediction")
	console._execute_authoritative(PackedStringArray(["/speed", "reset"]), state, player.owner_peer_id)
	check(player.debug_speed_multiplier == 1, "speed reset restores normal movement")
	# Put a pickup behind a nearby solid wall. Across intentionally ignores the wall.
	player.global_position = Vector3(200, 30, 200)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	var pickup = load("res://scenes/objects/items/battery_pickup.tscn").instantiate()
	world.add_child(pickup)
	pickup.freeze = true
	pickup.global_position = player.camera.global_position + Vector3(0, 0, -2.0)
	var wall := StaticBody3D.new()
	world.add_child(wall)
	wall.global_position = player.camera.global_position + Vector3(0, 0, -1.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2, 3, 0.2)
	collision.shape = shape
	wall.add_child(collision)
	await physics_frame
	await physics_frame
	await process_frame
	player.debug_across = false
	check(player.get_interaction_target() == wall, "normal interaction remains blocked by walls")
	var drag = player.get_node("ItemDrag")
	check(drag._valid_item(pickup.get_path()) == null, "normal pickup enforces line of sight")
	player.debug_across = true
	check(player.get_interaction_target() == pickup, "across ray targets nearby item through wall")
	check(drag.begin_interaction() and drag._valid_item(pickup.get_path()) == pickup, "E interaction and authoritative pickup validate in across")
	player._spare_batteries.clear()
	drag._pickup(pickup.get_path())
	check(player._spare_batteries.size() == 1, "across pickup actually adds item to inventory")
	player.debug_across = false
	check(player.get_interaction_target() == wall and player.interaction_ray.collision_mask == 5, "leaving across restores ordinary interaction ray")
	print("RESULT ", failures)
	quit(0 if failures.is_empty() else 1)
