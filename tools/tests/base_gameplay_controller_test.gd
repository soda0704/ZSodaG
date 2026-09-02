extends SceneTree

class FakePlayer:
	extends Node

	var owner_peer_id: int

	func _init(peer_id: int) -> void:
		owner_peer_id = peer_id


var _failed: bool = false


func _initialize() -> void:
	_run()


func _run() -> void:
	var gameplay_controller := Node.new()
	gameplay_controller.name = "TestGameplayController"
	gameplay_controller.add_to_group("network_gameplay_controller")
	var players := Node.new()
	players.name = "Players"
	gameplay_controller.add_child(players)
	for peer_id in range(1, BaseGameplayController.MAX_PLAYERS + 1):
		players.add_child(FakePlayer.new(peer_id))
	root.add_child(gameplay_controller)

	var packed_scene := load(
		"res://scenes/levels/Base_Blockout_v03.tscn"
	) as PackedScene
	_assert(packed_scene != null, "Base scene must load")
	var base_level: Node = packed_scene.instantiate()
	root.add_child(base_level)
	await process_frame
	await physics_frame
	_assert(
		int(base_level.call("get_player_spawn_count"))
		== BaseGameplayController.MAX_PLAYERS,
		"Production base must expose four arrival spawns"
	)
	var used_spawn_positions: Array[Vector3] = []
	for spawn_index in BaseGameplayController.MAX_PLAYERS:
		var marker := base_level.call(
			"get_player_spawn_marker",
			spawn_index
		) as Marker3D
		_assert(marker != null, "Arrival marker %d must exist" % spawn_index)
		_assert(
			(marker.global_basis * Vector3.FORWARD).dot(Vector3.RIGHT) > 0.99,
			"Arrival marker %d must look into the west entrance" % spawn_index
		)
		var spawn_position := base_level.call(
			"get_player_spawn_position",
			spawn_index
		) as Vector3
		_assert(
			not used_spawn_positions.has(spawn_position),
			"Arrival spawn positions must be unique"
		)
		used_spawn_positions.append(spawn_position)
		var floor_query := PhysicsRayQueryParameters3D.create(
			marker.global_position + Vector3.UP,
			marker.global_position + Vector3.DOWN * 2.0
		)
		_assert(
			not marker.get_world_3d().direct_space_state.intersect_ray(
				floor_query
			).is_empty(),
			"Arrival marker %d must stand above collision" % spawn_index
		)
	var standalone_player := base_level.get_node_or_null(
		"RuntimePlayers/1"
	) as Node3D
	_assert(standalone_player != null, "Standalone player must spawn")
	var first_marker := base_level.call(
		"get_player_spawn_marker",
		0
	) as Marker3D
	_assert(
		standalone_player.global_position.distance_to(
			first_marker.global_position
		) < 0.2,
		"Standalone player must use the first production marker: %s vs %s"
		% [standalone_player.global_position, first_marker.global_position]
	)
	_assert(
		is_equal_approx(
			standalone_player.rotation.y,
			float(base_level.call("get_player_spawn_yaw", 0))
		),
		"Standalone player must inherit the production marker yaw"
	)

	var controller := base_level.get_node_or_null(
		"BaseGameplayController"
	) as BaseGameplayController
	_assert(controller != null, "BaseGameplayController must exist")
	_assert(controller.day_index == 1, "Day 1 must be the initial day")
	_assert(
		controller.phase == BaseGameplayController.BasePhase.ARRIVAL,
		"Base must start in ARRIVAL"
	)
	_assert(not controller.fuel_delivered, "Fuel must start empty")
	_assert(not controller.main_breaker_on, "Breaker must start off")
	_assert(
		not controller.activate_main_breaker_authoritative(1),
		"Breaker must reject activation before fuel"
	)
	_assert(
		not controller.deliver_fuel_authoritative(99),
		"Unknown peer must not mutate base state"
	)
	_assert(
		controller.deliver_fuel_authoritative(1),
		"Local player must be able to deliver fuel"
	)
	_assert(controller.fuel_delivered, "Fuel state must become true")
	_assert(
		controller.phase == BaseGameplayController.BasePhase.RESTORING_POWER,
		"Fuel delivery must enter RESTORING_POWER"
	)
	_assert(
		controller.activate_main_breaker_authoritative(1),
		"Fueled base must accept breaker activation"
	)
	_assert(controller.main_breaker_on, "Breaker state must become true")
	_assert(
		controller.phase == BaseGameplayController.BasePhase.ACTIVE_DAY,
		"Breaker activation must enter ACTIVE_DAY"
	)
	_assert(
		controller.set_end_day_ready_authoritative(1, true),
		"Local player must be able to confirm end of day"
	)
	_assert(
		not controller.are_all_connected_players_ready(),
		"One confirmation must not satisfy a four-player ready gate"
	)
	for peer_id in range(2, BaseGameplayController.MAX_PLAYERS + 1):
		_assert(
			controller.set_end_day_ready_authoritative(peer_id, true),
			"Connected player %d must be able to confirm" % peer_id
		)
	_assert(
		controller.are_all_connected_players_ready(),
		"All four connected players must satisfy the ready gate"
	)
	_assert(
		controller.reset_day_one_authoritative(),
		"Host must be able to reset Day 1"
	)
	_assert(
		controller.get_snapshot() == {
			"day_index": 1,
			"phase": int(BaseGameplayController.BasePhase.ARRIVAL),
			"fuel_delivered": false,
			"main_breaker_on": false,
			"end_day_ready_peer_ids": [],
		},
		"Reset snapshot must be canonical"
	)

	base_level.free()
	gameplay_controller.free()
	await process_frame
	var mechanics_scene := load(
		"res://scenes/tests/mechanics_test_room.tscn"
	) as PackedScene
	_assert(mechanics_scene != null, "Mechanics scene must load")
	var mechanics_controller: Node = mechanics_scene.instantiate()
	root.add_child(mechanics_controller)
	await process_frame
	mechanics_controller.call("start_standalone_game")
	await process_frame
	for peer_id in range(2, BaseGameplayController.MAX_PLAYERS + 1):
		mechanics_controller.call("spawn_player_for_peer", peer_id)
	await process_frame
	for peer_id in range(1, BaseGameplayController.MAX_PLAYERS + 1):
		_assert(
			int(mechanics_controller.call("get_peer_spawn_index", peer_id))
			== peer_id - 1,
			"Initial peers must receive stable sequential spawn slots"
		)
	mechanics_controller.call("_on_peer_left", 2)
	await process_frame
	mechanics_controller.call("spawn_player_for_peer", 5)
	await process_frame
	_assert(
		int(mechanics_controller.call("get_peer_spawn_index", 5)) == 1,
		"A replacement peer must reuse the free spawn slot"
	)
	mechanics_controller.call("_enter_v3_level")
	await create_timer(0.6).timeout
	var v3_level := mechanics_controller.get_node_or_null("V3Level")
	_assert(v3_level != null, "Standalone transition must create V3")
	for peer_id in [1, 3, 4, 5]:
		var spawn_index := int(
			mechanics_controller.call("get_peer_spawn_index", peer_id)
		)
		var transitioned_player := mechanics_controller.get_node_or_null(
			"Players/%d" % peer_id
		) as Node3D
		_assert(transitioned_player != null, "Transitioned player must exist")
		var transitioned_marker := v3_level.call(
			"get_player_spawn_marker",
			spawn_index
		) as Marker3D
		_assert(transitioned_marker != null, "Transitioned V3 marker must exist")
		_assert(
			transitioned_player.global_position.distance_to(
				transitioned_marker.global_position
			) < 0.2,
			"V3 transition must preserve peer %d spawn slot" % peer_id
		)
		_assert(
			is_equal_approx(
				transitioned_player.rotation.y,
				float(v3_level.call("get_player_spawn_yaw", spawn_index))
			),
			"V3 transition must apply peer %d marker yaw" % peer_id
		)

	if _failed:
		quit(1)
		return
	print("BASE_GAMEPLAY_CONTROLLER_TEST: PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("BASE_GAMEPLAY_CONTROLLER_TEST: %s" % message)
