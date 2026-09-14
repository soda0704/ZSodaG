extends SceneTree

const TEST_FUEL_ITEM := &"fuel_can"
const TEST_FUSE_ITEM := &"fuse"
const LONG_PLAYER_NAME := "ОченьДлинныйНикИгрока"
const TEST_SAVE_PATH := "user://base_gameplay_state_test.cfg"

class FakePlayer:
	extends Node

	var owner_peer_id: int
	var player_display_name: String

	func _init(peer_id: int, display_name: String = "") -> void:
		owner_peer_id = peer_id
		player_display_name = (
			display_name if not display_name.is_empty() else "Игрок %d" % peer_id
		)


var _failed: bool = false


func _initialize() -> void:
	_run()


func _run() -> void:
	ProjectSettings.set_setting(
		BaseGameplayController.TEST_SAVE_PATH_SETTING,
		TEST_SAVE_PATH
	)
	_cleanup_test_save()
	await process_frame
	for action in [
		&"move_forward",
		&"look_right",
		&"jump",
		&"interact",
		&"flashlight",
		&"drop_item",
		&"journal",
		&"sprint",
		&"crouch",
		&"pause",
		&"ui_accept",
		&"ui_cancel",
	]:
		_assert(
			_has_joypad_event(action),
			"Gamepad fallback must bind action %s" % action
		)
	_assert(
		FileAccess.file_exists("res://game_actions_480.vdf"),
		"Steam Input action manifest must be packaged with the project"
	)
	var game_menu := root.get_node_or_null("GameMenu")
	_assert(game_menu != null, "Global game menu must be available")
	game_menu.call("force_close_menu")
	var gamepad_crouch := InputEventJoypadButton.new()
	gamepad_crouch.button_index = JOY_BUTTON_B
	gamepad_crouch.pressed = true
	game_menu.call("_unhandled_input", gamepad_crouch)
	_assert(
		not bool(game_menu.call("is_menu_open")),
		"Gameplay crouch button must not open the pause menu"
	)
	var gamepad_pause := InputEventJoypadButton.new()
	gamepad_pause.button_index = JOY_BUTTON_START
	gamepad_pause.pressed = true
	game_menu.call("_unhandled_input", gamepad_pause)
	_assert(
		bool(game_menu.call("is_menu_open")),
		"Gamepad Start must open the pause menu"
	)
	game_menu.call("_unhandled_input", gamepad_crouch)
	_assert(
		not bool(game_menu.call("is_menu_open")),
		"Gamepad B must close an already open pause menu"
	)
	var main_menu_scene := load(
		"res://scenes/ui/main_menu.tscn"
	) as PackedScene
	_assert(main_menu_scene != null, "Main menu scene must load")
	var empty_save_menu := main_menu_scene.instantiate()
	root.add_child(empty_save_menu)
	await process_frame
	_assert(
		empty_save_menu.get_node("MenuButtons/ContinueGameButton").disabled,
		"Continue must be disabled when no checkpoint exists"
	)
	_assert(
		empty_save_menu.get_node("MenuButtons/DeleteSaveButton").disabled,
		"Delete save must be disabled when no checkpoint exists"
	)
	_assert(
		empty_save_menu.get_node("MenuButtons/SinglePlayerButton").text
		== "НОВАЯ ИГРА",
		"Main menu must expose an explicit new-game action"
	)
	empty_save_menu.free()
	await process_frame
	var incompatible_save := ConfigFile.new()
	incompatible_save.set_value("save", "version", 999)
	_assert(
		incompatible_save.save(TEST_SAVE_PATH) == OK,
		"Test must be able to create an incompatible checkpoint"
	)
	var incompatible_save_menu := main_menu_scene.instantiate()
	root.add_child(incompatible_save_menu)
	await process_frame
	_assert(
		incompatible_save_menu.get_node(
			"MenuButtons/ContinueGameButton"
		).disabled,
		"Continue must reject an incompatible checkpoint"
	)
	_assert(
		not incompatible_save_menu.get_node(
			"MenuButtons/DeleteSaveButton"
		).disabled
		and str(incompatible_save_menu.get_node(
			"ProfileCard/ProfileContent/SaveStatusLabel"
		).text).contains("НЕСОВМЕСТИМ"),
		"Incompatible checkpoint must remain visible and deletable"
	)
	incompatible_save_menu.call("_delete_save_confirmed")
	_assert(
		not FileAccess.file_exists(TEST_SAVE_PATH),
		"Deleting an incompatible checkpoint must remove its file"
	)
	incompatible_save_menu.free()
	await process_frame
	var gameplay_controller := Node.new()
	gameplay_controller.name = "TestGameplayController"
	gameplay_controller.add_to_group("network_gameplay_controller")
	var players := Node.new()
	players.name = "Players"
	gameplay_controller.add_child(players)
	players.add_child(FakePlayer.new(1, "Одиночка"))
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
		"Production base must expose two arrival spawns"
	)
	var used_spawn_positions: Array[Vector3] = []
	for spawn_index in BaseGameplayController.MAX_PLAYERS:
		_assert(
			is_equal_approx(
				float(base_level.call("get_player_spawn_yaw", spawn_index)),
				PI * 0.5
			),
			"Arrival spawn %d must look into the west entrance" % spawn_index
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
			spawn_position + Vector3.UP,
			spawn_position + Vector3.DOWN * 2.0
		)
		_assert(
			not base_level.get_world_3d().direct_space_state.intersect_ray(
				floor_query
			).is_empty(),
			"Arrival spawn %d must stand above collision" % spawn_index
		)
	var standalone_player := base_level.get_node_or_null(
		"RuntimePlayers/1"
	) as Node3D
	_assert(standalone_player != null, "Standalone player must spawn")
	var first_spawn := base_level.call("get_player_spawn_position", 0) as Vector3
	_assert(
		standalone_player.global_position.distance_to(
			first_spawn
		) < 0.2,
		"Standalone player must use the first production spawn: %s vs %s"
		% [standalone_player.global_position, first_spawn]
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
	var quest_journal := root.get_node_or_null("QuestJournal")
	_assert(quest_journal != null, "Shared quest journal must be autoloaded")
	quest_journal.call("open_journal")
	_assert(
		bool(quest_journal.call("is_journal_open"))
		and str(quest_journal.objective_label.text) == "Вернуть базу к жизни"
		and str(quest_journal.tasks_label.text).contains("Заправить бак"),
		"Journal must show the shared Day 1 base objective"
	)
	var journal_escape := InputEventAction.new()
	journal_escape.action = &"pause"
	journal_escape.pressed = true
	game_menu.call("_unhandled_input", journal_escape)
	await create_timer(0.2).timeout
	_assert(
		not bool(quest_journal.call("is_journal_open"))
		and not bool(game_menu.call("is_menu_open")),
		"Escape must close the journal without opening the pause menu"
	)
	var day_one_collision_root := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Doors/Day1_Door_Collisions"
	) as Node3D
	var automatic_doors := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Doors/AutomaticDoors"
	)
	var production_elevator := base_level.get_node_or_null(
		"Elevator_Functional_Blockout"
	) as FunctionalElevatorController
	_assert(
		day_one_collision_root != null,
		"Production base must expose its Day 1 passage blockers"
	)
	_assert(production_elevator != null, "Production elevator must exist")
	var day_one_collision_shapes := day_one_collision_root.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	)
	_assert(
		day_one_collision_shapes.size() == 4,
		"Legacy Day 1 blockers remain available for scene migration"
	)
	for collision_shape in day_one_collision_shapes:
		_assert(
			(collision_shape as CollisionShape3D).disabled,
			"Automatic doors must replace every temporary passage blocker"
		)
	_assert(
		automatic_doors != null
		and int(automatic_doors.call("get_door_count")) == 16
		and int(automatic_doors.call("get_open_door_count")) == 8,
		"All 16 doors must be managed directly; the full spawn-to-generator route opens without power while the garage gate stays locked"
	)
	var garage_gate := base_level.get_node(
		"Floor_0_Base_Blockout/Doors/West_Vehicle_Exterior_Gate_Visual_Prototype"
	) as Node3D
	var garage_room_door := base_level.get_node(
		"Floor_0_Base_Blockout/Doors/West_Equipment_Garage_Door_Visual_Prototype"
	) as Node3D
	_assert(
		not bool(automatic_doors.call("is_door_open_at", garage_gate))
		and bool(automatic_doors.call("is_door_open_at", garage_room_door)),
		"The vehicle garage gate stays locked while the pedestrian route through the garage room opens fully"
	)
	var unpowered_science_door := base_level.get_node(
		"Floor_0_Base_Blockout/Doors/Science_Entrance_Door_Visual_Prototype"
	) as Node3D
	_assert(
		(automatic_doors.call("get_door_indicator_color_at", unpowered_science_door) as Color).r > 0.9,
		"All closed-door indicators must glow red"
	)
	_assert(
		production_elevator.unlocked_floor_index == 0,
		"Day 1 elevator must expose only the surface floor"
	)
	_assert(
		production_elevator.get_button_prompt(1, false)
		== "Уровень 1 закрыт",
		"First underground floor must be locked before the first sleep"
	)
	var lighting_controller := base_level.get_node_or_null(
		"BasePowerLightingController"
	)
	var standard_lighting := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
		+ "Standard_Lighting_Blockout"
	) as Node3D
	var emergency_lighting := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
		+ "Day1_Emergency_Lighting_Blockout"
	) as Node3D
	_assert(lighting_controller != null, "Base lighting controller must exist")
	_assert(standard_lighting != null, "Standard lighting layer must exist")
	_assert(emergency_lighting != null, "Emergency lighting layer must exist")
	_assert(
		not standard_lighting.visible and emergency_lighting.visible,
		"Unpowered Day 1 must expose only emergency lighting"
	)
	var bunk_one := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01"
	)
	var bunk_two := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable02"
	)
	_assert(bunk_one != null, "First production end-day bunk must exist")
	_assert(bunk_two != null, "Second production end-day bunk must exist")
	var bunk_one_name_tag := bunk_one.get_node_or_null(
		"NameTagPivot/NameTagLabel"
	) as Label3D
	var bunk_two_name_tag := bunk_two.get_node_or_null(
		"NameTagPivot/NameTagLabel"
	) as Label3D
	_assert(bunk_one_name_tag != null, "First bunk must expose a name tag")
	_assert(bunk_two_name_tag != null, "Second bunk must expose a name tag")
	_assert(
		bunk_one_name_tag.text == "Одиночка",
		"Occupied solo bunk must display the player's nickname"
	)
	_assert(
		bunk_two_name_tag.text == "—",
		"Vacant co-op bunk must display an empty name tag"
	)
	for bunk in [bunk_one, bunk_two]:
		_assert(
			(bunk.get_node("StatusLabel") as Label3D).position.z > 0.0
			and (bunk.get_node("NameTagPivot") as Node3D).position.z > 0.0,
			"Bunk labels must sit on the aisle side of the bed frame"
		)
	for bunk in [bunk_one, bunk_two]:
		var bunk_ray := PhysicsRayQueryParameters3D.create(
			bunk.global_position + Vector3.BACK * 2.0,
			bunk.global_position,
			4
		)
		_assert(
			bunk.get_world_3d().direct_space_state.intersect_ray(
				bunk_ray
			).get("collider") == bunk,
			"End-day bunk must be reachable by the player's interaction ray"
		)
	var fuel_socket := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/FuelFillInteractable"
	) as BaseFuelSocket
	var main_breaker := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/MainBreakerInteractable"
	) as BaseMainBreaker
	_assert(fuel_socket != null, "Production fuel socket must exist")
	_assert(main_breaker != null, "Production main breaker must exist")
	var breaker_status := main_breaker.get_node("StatusLabel") as Label3D
	_assert(
		breaker_status.global_basis.z.dot(Vector3.LEFT) > 0.99,
		"Main breaker label must face its interaction approach"
	)
	var fuel_header := fuel_socket.get_node_or_null("HeaderLabel") as Label3D
	var fuel_status := fuel_socket.get_node_or_null("StatusLabel") as Label3D
	var tank_header := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/South_Technical/Art/GeneratorRoomArt/"
		+ "Blockout/Generator_Room/"
		+ "Fuel_And_Cooling/Technical_Fuel_Tank_Header"
	) as Label3D
	_assert(
		fuel_header != null and fuel_header.text == "ТОПЛИВНЫЙ БАК",
		"Fuel socket must clearly identify the production tank"
	)
	_assert(
		tank_header != null and tank_header.text.contains("ЗАПРАВКА"),
		"Production tank must expose a visible refueling sign"
	)
	var production_tank := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/South_Technical/Art/GeneratorRoomArt/"
		+ "Blockout/Generator_Room/"
		+ "Fuel_And_Cooling/Technical_Fuel_Tank_Blockout"
	) as Node3D
	var production_generator := base_level.get_node_or_null(
		"Floor_0_Base_Blockout/South_Technical/Art/GeneratorRoomArt/"
		+ "Blockout/Generator_Room/"
		+ "Power_Generation/Technical_Main_Generator_Blockout"
	) as Node3D
	_assert(
		production_tank != null
		and production_generator != null
		and base_level.get_node("Floor_0_Base_Blockout").to_local(production_tank.global_position).distance_to(
			Vector3(-5.5, 1.25, 25.25)
		) < 0.01,
		"Production fuel tank must remain at its established room position"
	)
	_assert(
		fuel_header.global_basis.z.dot(Vector3.FORWARD) > 0.99
		and fuel_status.global_basis.z.dot(Vector3.FORWARD) > 0.99
		and tank_header.global_basis.z.dot(Vector3.FORWARD) > 0.99,
		"Fuel labels must face the player instead of showing mirrored backs"
	)
	var fuel_socket_ray := PhysicsRayQueryParameters3D.create(
		fuel_socket.global_position + Vector3.FORWARD * 2.0,
		fuel_socket.global_position,
		4
	)
	_assert(
		fuel_socket.get_world_3d().direct_space_state.intersect_ray(
			fuel_socket_ray
		).get("collider") == fuel_socket,
		"Fuel socket must be reachable by the player's interaction ray"
	)
	var breaker_ray := PhysicsRayQueryParameters3D.create(
		main_breaker.global_position + Vector3.LEFT * 2.0,
		main_breaker.global_position,
		4
	)
	_assert(
		main_breaker.get_world_3d().direct_space_state.intersect_ray(
			breaker_ray
		).get("collider") == main_breaker,
		"Main breaker must be reachable by the player's interaction ray"
	)
	var standalone_fuel_can := base_level.get_node_or_null(
		"StandaloneFuelCan"
	) as WorldItemPickup
	_assert(standalone_fuel_can != null, "Standalone Day 1 fuel can must spawn")
	var fuel_marker_position: Vector3 = base_level.call(
		"get_fuel_can_spawn_transform"
	).origin
	_assert(
		production_generator != null
		and Vector2(
			fuel_marker_position.x,
			fuel_marker_position.z
		).distance_to(Vector2(
			production_generator.global_position.x,
			production_generator.global_position.z
		)) < 6.0,
		"Day 1 fuel can must temporarily spawn in the generator room"
	)
	_assert(
		Vector2(
			standalone_fuel_can.global_position.x,
			standalone_fuel_can.global_position.z
		).distance_to(Vector2(fuel_marker_position.x, fuel_marker_position.z))
		< 0.05,
		"Standalone fuel can must use its production marker"
	)
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
		fuel_socket.get_interaction_prompt().contains("0.0 / 60"),
		"Empty production fuel socket must request the fuel can"
	)
	fuel_socket.network_interact(1, standalone_player)
	_assert(
		not controller.fuel_delivered,
		"Production fuel socket must reject an empty hand"
	)
	main_breaker.network_interact(1, standalone_player)
	_assert(
		not controller.main_breaker_on,
		"Production breaker interaction must reject an empty fuel tank"
	)
	_assert(
		not controller.deliver_fuel_authoritative(99),
		"Unknown peer must not mutate base state"
	)
	var before_fuel_pickup: Vector3 = standalone_player.global_position
	standalone_player.global_position = standalone_fuel_can.global_position + Vector3.UP
	standalone_fuel_can.network_interact(1, standalone_player)
	standalone_player.global_position = before_fuel_pickup
	_assert(
		bool(standalone_player.call("has_held_item", TEST_FUEL_ITEM)),
		"Player must be able to carry the fuel can"
	)
	fuel_socket.network_interact(1, standalone_player)
	_assert(controller.fuel_delivered, "Fuel state must become true")
	fuel_socket.network_interact(1, standalone_player)
	_assert(is_equal_approx(controller.fuel_liters, 20.0), "Empty can must not add fuel")
	_assert(
		fuel_socket.get_interaction_prompt().contains("20.0 / 60"),
		"Fueled production socket must expose its synchronized state"
	)
	_assert(
		bool(standalone_player.call("has_held_item", TEST_FUEL_ITEM)) and is_zero_approx(standalone_player.fuel_liters),
		"Successful production refueling must retain the empty fuel can"
	)
	_assert(
		controller.phase == BaseGameplayController.BasePhase.RESTORING_POWER,
		"Fuel delivery must enter RESTORING_POWER"
	)
	main_breaker.network_interact(1, standalone_player)
	_assert(controller.main_breaker_on, "Breaker state must become true")
	await create_timer(0.85).timeout
	var west_hub_door := base_level.get_node(
		"Floor_0_Base_Blockout/Doors/West_Hub_Decon_Door_Visual_Prototype"
	) as Node3D
	_assert(
		not bool(automatic_doors.call("is_door_open_at", west_hub_door)),
		"After power restoration, startup-route doors must return to proximity control"
	)
	var science_door := base_level.get_node(
		"Floor_0_Base_Blockout/Doors/Science_Entrance_Door_Visual_Prototype"
	) as Node3D
	var position_before_door_test := standalone_player.global_position
	var single_doors_tested := 0
	for door: Dictionary in automatic_doors.get("_doors"):
		if door.leaf_pairs.size() != 1 or door.leaf_pairs[0].leaf.name != &"Leaf":
			continue
		single_doors_tested += 1
		standalone_player.global_position = door.anchor.global_position + Vector3(0, 0, 1.5)
		await create_timer(0.9).timeout
		_assert(door.blocker.disabled and door.leaf_pairs[0].leaf.position.is_equal_approx(door.leaf_pairs[0].open_position), "Single door slides fully aside and frees passage")
		standalone_player.global_position = door.anchor.global_position + Vector3(10, 0, 10)
		await create_timer(0.9).timeout
		_assert(not door.blocker.disabled and door.leaf_pairs[0].leaf.position.is_equal_approx(door.leaf_pairs[0].closed_position), "Closed single door is solid")
	_assert(single_doors_tested == 2, "Both initial pedestrian doors must be covered")
	standalone_player.global_position = science_door.global_position + Vector3(0, 0, 1.5)
	await create_timer(0.85).timeout
	_assert(
		bool(automatic_doors.call("is_door_open_at", science_door)),
		"A powered authored door must open when a player approaches"
	)
	_assert(
		float(automatic_doors.call("get_door_leaf_aperture_at", science_door)) > 3.0,
		"A living-side door must move both leaves to the fully open sockets"
	)
	_assert(
		(automatic_doors.call("get_door_indicator_color_at", science_door) as Color).g > 0.9,
		"All open-door indicators must glow green"
	)
	standalone_player.global_position = position_before_door_test
	await create_timer(0.85).timeout
	_assert(
		not bool(automatic_doors.call("is_door_open_at", science_door)),
		"A powered authored door must close after the player walks away"
	)
	_assert(
		standard_lighting.visible and not emergency_lighting.visible,
		"Main breaker must replace emergency lighting with standard lighting"
	)
	_assert(
		bool(lighting_controller.get("is_standard_powered")),
		"Lighting controller must mirror the authoritative breaker state"
	)
	_assert(
		main_breaker.get_interaction_prompt() == "Главный щит включён",
		"Production breaker prompt must expose its synchronized state"
	)
	_assert(
		controller.phase == BaseGameplayController.BasePhase.ACTIVE_DAY,
		"Breaker activation must enter ACTIVE_DAY"
	)
	_assert(
		str(bunk_one.call("get_interaction_prompt"))
		== "Подготовить койку",
		"Powered first bunk must allow the solo player to prepare it"
	)
	_assert(
		bunk_one.get_node_or_null("BedPivot/Pillow") != null,
		"End-day bunk must include a pillow"
	)
	bunk_one.call("network_interact", 1, standalone_player)
	await process_frame
	_assert(
		controller.is_peer_ready_to_end_day(1)
		and not controller.is_peer_sleeping(1)
		and str(bunk_one.call("get_interaction_prompt")) == "Убрать готовность"
		and str(bunk_one.call("get_sleep_interaction_prompt")) == "Лечь спать",
		"Prepared bunk must offer sleep separately from readiness cancellation"
	)
	bunk_one.call("network_interact", 1, standalone_player)
	_assert(
		not controller.is_peer_ready_to_end_day(1),
		"Prepared player must be able to cancel readiness from the panel"
	)
	bunk_one.call("network_interact", 1, standalone_player)
	bunk_one.call("network_sleep_interact", 1, standalone_player)
	_assert(
		controller.is_peer_sleeping(1)
		and bool(standalone_player.call("is_sleeping_in_bunk")),
		"Solo player must enter the bunk sleep pose"
	)
	var flashlight_serial_before_sleep_input := int(
		standalone_player.get("_flashlight_serial")
	)
	var sleeping_flashlight_input := InputEventAction.new()
	sleeping_flashlight_input.action = &"flashlight"
	sleeping_flashlight_input.pressed = true
	standalone_player.call("_unhandled_input", sleeping_flashlight_input)
	_assert(
		int(standalone_player.get("_flashlight_serial"))
		== flashlight_serial_before_sleep_input,
		"Sleeping player must ignore flashlight input instead of buffering it"
	)
	var leave_bunk_input := InputEventAction.new()
	leave_bunk_input.action = &"interact"
	leave_bunk_input.pressed = true
	standalone_player.call("_unhandled_input", leave_bunk_input)
	await process_frame
	_assert(
		not controller.is_peer_sleeping(1)
		and not controller.is_peer_ready_to_end_day(1)
		and not bool(standalone_player.call("is_sleeping_in_bunk"))
		and is_equal_approx(bunk_one.get_node("BedPivot").rotation.x, -PI * 0.5),
		"Interact must immediately leave network sleep and fold the bunk"
	)
	bunk_one.call("network_interact", 1, standalone_player)
	bunk_one.call("network_sleep_interact", 1, standalone_player)
	await create_timer(1.25).timeout
	_assert(
		controller.day_index == 2
		and controller.phase == BaseGameplayController.BasePhase.RESTORING_POWER
		and controller.maintenance.get("wires_required", false)
		and controller.end_day_ready_peer_ids.is_empty()
		and controller.sleeping_peer_ids.is_empty()
		and not bool(standalone_player.call("is_sleeping_in_bunk")),
		"Solo sleep must finish, wake the player and begin Day 2"
	)
	for collision_shape in day_one_collision_shapes:
		_assert(
			(collision_shape as CollisionShape3D).disabled,
			"First sleep must disable every temporary Day 1 blocker"
		)
	_assert(
		production_elevator.unlocked_floor_index == 1,
		"Day 2 must unlock elevator floor -1"
	)
	_assert(
		FileAccess.file_exists(TEST_SAVE_PATH),
		"Day transition must create the host progress save"
	)
	var saved_snapshot := controller.load_saved_snapshot()
	_assert(
		int(saved_snapshot.get("day_index", 0)) == 2
		and int(saved_snapshot.get("phase", -1))
		== int(BaseGameplayController.BasePhase.RESTORING_POWER)
		and bool(saved_snapshot.get("fuel_delivered", false))
		and not bool(saved_snapshot.get("main_breaker_on", false))
		and saved_snapshot.maintenance.get("wires_required", false)
		and (saved_snapshot.get("end_day_ready_peer_ids", []) as Array).is_empty()
		and (saved_snapshot.get("sleeping_peer_ids", []) as Array).is_empty(),
		"Saved checkpoint must restore Day 2 without transient ready flags"
	)
	var reload_host := Node.new()
	var reloaded_controller := BaseGameplayController.new()
	reload_host.add_child(reloaded_controller)
	root.add_child(reload_host)
	await process_frame
	_assert(
		reloaded_controller.day_index == 2
		and reloaded_controller.phase
		== BaseGameplayController.BasePhase.RESTORING_POWER
		and not reloaded_controller.main_breaker_on
		and reloaded_controller.maintenance.get("wires_required", false),
		"A fresh host controller must automatically load the checkpoint"
	)
	reload_host.free()
	await process_frame
	var saved_game_menu := main_menu_scene.instantiate()
	root.add_child(saved_game_menu)
	await process_frame
	_assert(
		not saved_game_menu.get_node(
			"MenuButtons/ContinueGameButton"
		).disabled,
		"Continue must be enabled for a valid checkpoint"
	)
	_assert(
		str(saved_game_menu.get_node(
			"ProfileCard/ProfileContent/SaveStatusLabel"
		).text).contains("DAY 2"),
		"Main menu must show the saved day"
	)
	saved_game_menu.call("_delete_save_confirmed")
	_assert(
		not FileAccess.file_exists(TEST_SAVE_PATH)
		and saved_game_menu.get_node(
			"MenuButtons/ContinueGameButton"
		).disabled,
		"Delete save action must remove the checkpoint and disable Continue"
	)
	saved_game_menu.free()
	await process_frame
	_assert(
		controller.reset_day_one_authoritative(),
		"Host must be able to reset Day 1 after a solo sleep"
	)
	await process_frame
	await physics_frame
	for collision_shape in day_one_collision_shapes:
		_assert(
			(collision_shape as CollisionShape3D).disabled,
			"Day 1 reset must keep legacy blockers replaced by automatic doors"
		)
	_assert(
		production_elevator.unlocked_floor_index == 0,
		"Day 1 reset must lock the first underground floor again"
	)
	_assert(
		controller.deliver_fuel_authoritative(1)
		and controller.activate_main_breaker_authoritative(1),
		"Day 1 reset must remain replayable for the co-op test"
	)
	var second_interactor := FakePlayer.new(2, LONG_PLAYER_NAME)
	players.add_child(second_interactor)
	controller.call("_on_peer_joined", 2)
	await process_frame
	_assert(
		str(bunk_two.get_node("StatusLabel").text).contains("ОЖИДАНИЕ"),
		"Second bunk must react when a co-op player joins"
	)
	_assert(
		bunk_two_name_tag.text.length()
		<= BaseEndDayBunk.MAX_NAME_TAG_CHARACTERS
		and bunk_two_name_tag.text.ends_with("…"),
		"Long nickname must be shortened with an ellipsis on the bunk tag"
	)
	_assert(
		str(bunk_two_name_tag.get_meta("full_player_name"))
		== LONG_PLAYER_NAME,
		"Bunk tag must retain the complete nickname in metadata"
	)
	bunk_two.call("network_interact", 1, standalone_player)
	_assert(
		not controller.is_peer_ready_to_end_day(1),
		"Player must not confirm through the other player's bunk"
	)
	bunk_one.call("network_interact", 1, standalone_player)
	_assert(
		not controller.are_all_connected_players_ready(),
		"One confirmation must not satisfy a two-player ready gate"
	)
	bunk_two.call("network_interact", 2, second_interactor)
	bunk_one.call("network_sleep_interact", 1, standalone_player)
	bunk_two.call("network_sleep_interact", 2, second_interactor)
	_assert(
		controller.are_all_connected_players_sleeping(),
		"Both prepared co-op players must be able to lie down"
	)
	await create_timer(1.25).timeout
	_assert(
		controller.day_index == 2
		and controller.end_day_ready_peer_ids.is_empty()
		and controller.sleeping_peer_ids.is_empty(),
		"Both connected players must finish the co-op sleep"
	)
	_assert(
		production_elevator.unlocked_floor_index == 1,
		"Co-op sleep must unlock floor -1 through the shared day state"
	)
	_assert(
		controller.reset_day_one_authoritative(),
		"Host must be able to reset Day 1"
	)
	_assert(
		controller.get_snapshot() == {
			"day_index": 1,
			"containment": {},
			"maintenance": {},
			"phase": int(BaseGameplayController.BasePhase.ARRIVAL),
			"fuel_delivered": false,
			"fuel_liters": 0.0,
			"main_breaker_on": false,
			"end_day_ready_peer_ids": [],
			"sleeping_peer_ids": [],
			"quest_stage": 0,
		},
		"Reset snapshot must be canonical"
	)
	_assert(
		not standard_lighting.visible and emergency_lighting.visible,
		"Reset must restore the emergency-only lighting state"
	)

	_assert(is_equal_approx(controller.refill_authoritative(1, 55.0), 55.0), "Tank accepts measured fuel")
	standalone_player.fuel_liters = 20.0
	fuel_socket.network_interact(1, standalone_player)
	_assert(is_equal_approx(controller.fuel_liters, 60.0) and is_equal_approx(standalone_player.fuel_liters, 15.0), "Partial refill preserves surplus in can")
	controller.activate_main_breaker_authoritative(1)
	controller._process(100.0)
	_assert(is_equal_approx(controller.fuel_liters, 59.0), "Running generator consumes fuel slowly")
	controller._process(6000.0)
	_assert(is_zero_approx(controller.fuel_liters) and not controller.main_breaker_on, "Empty generator shuts power down")
	controller.reset_day_one_authoritative()
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
	mechanics_controller.call("spawn_player_for_peer", 3)
	await process_frame
	_assert(
		int(mechanics_controller.call("get_peer_spawn_index", 3)) == -1,
		"A third peer must not receive a gameplay slot"
	)
	var departing_player := mechanics_controller.get_node_or_null(
		"Players/2"
	)
	departing_player.call("apply_held_item_inventory", TEST_FUEL_ITEM, {})
	mechanics_controller.call("_on_peer_left", 2)
	await process_frame
	var disconnected_fuel_was_dropped := false
	for pickup in mechanics_controller.get_node(
		"Gameplay/WorldItems"
	).get_children():
		if StringName(pickup.get("item_type")) == TEST_FUEL_ITEM:
			disconnected_fuel_was_dropped = true
			break
	_assert(
		disconnected_fuel_was_dropped,
		"Disconnecting fuel carrier must drop the required item"
	)
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
	for peer_id in [1, 5]:
		var spawn_index := int(
			mechanics_controller.call("get_peer_spawn_index", peer_id)
		)
		var transitioned_player := mechanics_controller.get_node_or_null(
			"Players/%d" % peer_id
		) as Node3D
		_assert(transitioned_player != null, "Transitioned player must exist")
		var transitioned_spawn := v3_level.call(
			"get_player_spawn_position",
			spawn_index
		) as Vector3
		_assert(
			transitioned_player.global_position.distance_to(
				transitioned_spawn
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

	var network_world_items := mechanics_controller.get_node_or_null(
		"Gameplay/WorldItems"
	)
	var network_fuel_can: WorldItemPickup
	for pickup in network_world_items.get_children():
		if StringName(pickup.get("item_type")) == TEST_FUEL_ITEM:
			network_fuel_can = pickup as WorldItemPickup
			break
	_assert(network_fuel_can != null, "Network-managed V3 must spawn one fuel can")
	var network_player := mechanics_controller.get_node_or_null(
		"Players/1"
	)
	_assert(network_player != null, "Network host player must exist in V3")
	var before_network_pickup: Vector3 = network_player.global_position
	network_player.global_position = network_fuel_can.global_position + Vector3.UP
	network_fuel_can.network_interact(1, network_player)
	network_player.global_position = before_network_pickup
	_assert(
		bool(network_player.call("has_held_item", TEST_FUEL_ITEM)),
		"Host-authoritative pickup must put fuel in the player's hand"
	)
	var network_fuel_socket := v3_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/FuelFillInteractable"
	) as BaseFuelSocket
	var network_breaker := v3_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/MainBreakerInteractable"
	) as BaseMainBreaker
	var network_base_controller := v3_level.get_node_or_null(
		"BaseGameplayController"
	) as BaseGameplayController
	var network_elevator := v3_level.get_node_or_null(
		"Elevator_Functional_Blockout"
	) as FunctionalElevatorController
	var network_day_one_collision_root := v3_level.get_node_or_null(
		"Floor_0_Base_Blockout/Doors/Day1_Door_Collisions"
	) as Node3D
	_assert(
		network_elevator.unlocked_floor_index == 0,
		"Network-managed V3 must start with floor -1 locked"
	)
	var network_lighting_controller := v3_level.get_node_or_null(
		"BasePowerLightingController"
	)
	network_fuel_socket.network_interact(1, network_player)
	_assert(
		network_base_controller.fuel_delivered,
		"Network-managed production socket must deliver fuel on the host"
	)
	network_breaker.network_interact(1, network_player)
	_assert(
		network_base_controller.main_breaker_on,
		"Network-managed production breaker must activate on the host"
	)
	_assert(
		bool(network_lighting_controller.get("is_standard_powered")),
		"Network-managed lighting must follow the synchronized breaker state"
	)
	_assert(
		v3_level.get_node(
			"Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
			+ "Standard_Lighting_Blockout"
		).visible
		and not v3_level.get_node(
			"Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
			+ "Day1_Emergency_Lighting_Blockout"
		).visible,
		"Network-managed V3 must expose only standard lighting after power"
	)
	var network_bunk_one := v3_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01"
	)
	var network_bunk_two := v3_level.get_node_or_null(
		"Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable02"
	)
	var second_network_player := mechanics_controller.get_node_or_null(
		"Players/5"
	)
	network_bunk_one.call("network_interact", 1, network_player)
	_assert(
		not network_base_controller.are_all_connected_players_ready(),
		"Network host readiness must wait for the second connected player"
	)
	network_bunk_two.call("network_interact", 5, second_network_player)
	network_bunk_one.call("network_sleep_interact", 1, network_player)
	network_bunk_two.call("network_sleep_interact", 5, second_network_player)
	_assert(
		network_base_controller.are_all_connected_players_sleeping(),
		"Network sleep must wait until both prepared players lie down"
	)
	await create_timer(1.25).timeout
	_assert(
		network_base_controller.day_index == 2
		and network_base_controller.end_day_ready_peer_ids.is_empty()
		and network_base_controller.sleeping_peer_ids.is_empty(),
		"Both network players must advance the authoritative state to Day 2"
	)
	_assert(
		network_elevator.unlocked_floor_index == 1,
		"Network Day 2 must unlock elevator floor -1"
	)
	for collision_shape in network_day_one_collision_root.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	):
		_assert(
			(collision_shape as CollisionShape3D).disabled,
			"Network Day 2 must disable temporary passage blockers"
		)
	network_elevator.door_animation_duration = 0.01
	network_elevator.arrival_alignment_duration = 0.01
	network_elevator.travel_speed = 90.0
	network_elevator.travel_start_stop_time = 0.0
	network_elevator.cabin_door.animation_duration = 0.01
	_assert(
		network_elevator.request_floor(1),
		"Unlocked production elevator must begin a trip to floor -1"
	)
	for wait_step in 30:
		if network_elevator.state == FunctionalElevatorController.ElevatorState.MOVING:
			break
		await create_timer(0.01).timeout
	_assert(
		network_elevator.state == FunctionalElevatorController.ElevatorState.MOVING,
		"Elevator must enter MOVING before the late-join snapshot"
	)
	var moving_elevator_snapshot := network_elevator.get_network_snapshot()
	_assert(
		int(moving_elevator_snapshot.get(
			"active_destination_floor_index",
			-1
		)) == 1
		and float(moving_elevator_snapshot.get(
			"motion_remaining_seconds",
			0.0
		)) > 0.0,
		"Moving snapshot must include destination and remaining travel time"
	)
	var elevator_scene := load(
		"res://scenes/objects/elevator/elevator_functional_blockout.tscn"
	) as PackedScene
	var late_join_elevator := (
		elevator_scene.instantiate() as FunctionalElevatorController
	)
	late_join_elevator.name = "LateJoinElevatorReplica"
	late_join_elevator.door_animation_duration = 0.01
	late_join_elevator.arrival_alignment_duration = 0.01
	late_join_elevator.use_built_in_surface_platform = false
	root.add_child(late_join_elevator)
	await process_frame
	late_join_elevator.call(
		"_receive_network_snapshot",
		moving_elevator_snapshot
	)
	_assert(
		late_join_elevator.state
		== FunctionalElevatorController.ElevatorState.MOVING,
		"Late-join replica must resume the in-progress elevator state"
	)
	await create_timer(0.35).timeout
	_assert(
		late_join_elevator.current_floor_index == 1
		and late_join_elevator.state
		== FunctionalElevatorController.ElevatorState.IDLE_OPEN
		and is_equal_approx(
			late_join_elevator.cabin.position.y,
			-late_join_elevator.floor_spacing
		),
		"Late-join replica must finish at floor -1 with open doors"
	)
	late_join_elevator.free()
	second_network_player.call(
		"apply_held_item_inventory",
		TEST_FUSE_ITEM,
		{}
	)
	var expected_bunk_drop_transform: Transform3D = v3_level.call(
		"get_bunk_item_drop_transform",
		1
	)
	mechanics_controller.call("_on_peer_left", 5)
	await process_frame
	await physics_frame
	var disconnected_fuse: Node3D
	for pickup in network_world_items.get_children():
		if StringName(pickup.get("item_type")) == TEST_FUSE_ITEM:
			disconnected_fuse = pickup as Node3D
			break
	_assert(
		disconnected_fuse != null,
		"Disconnecting player must drop the carried item in V3"
	)
	if disconnected_fuse != null:
		_assert(
			Vector2(
				disconnected_fuse.global_position.x,
				disconnected_fuse.global_position.z
			).distance_to(Vector2(
				expected_bunk_drop_transform.origin.x,
				expected_bunk_drop_transform.origin.z
			)) < 0.2,
			"Disconnected player's item must appear beside their bunk"
		)
	_assert(
		mechanics_controller.get_node_or_null("Players/5") == null,
		"Disconnected player must be despawned after dropping the item"
	)

	if _failed:
		_cleanup_test_save()
		quit(1)
		return
	_cleanup_test_save()
	print("BASE_GAMEPLAY_CONTROLLER_TEST: PASS")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("BASE_GAMEPLAY_CONTROLLER_TEST: %s" % message)


func _cleanup_test_save() -> void:
	var absolute_path := ProjectSettings.globalize_path(TEST_SAVE_PATH)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)


func _has_joypad_event(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton or event is InputEventJoypadMotion:
			return true
	return false
