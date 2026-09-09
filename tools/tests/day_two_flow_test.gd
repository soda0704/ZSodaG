extends SceneTree

const SAVE := "user://day_two_flow_test.cfg"
var failed := false


func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, SAVE)
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("DAY_TWO_FLOW_TEST: " + message)


func _run() -> void:
	BaseGameplayController.delete_progress_save()
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var base: Node3D = world.get_node("V3Level")
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	var player: Node3D = world.get_node("Players/1")
	var task: Node3D = base.get_node("DayTwoTaskTerminal")
	var key: Node3D = base.get_node("DayTwoKeyTerminal")
	state._on_peer_left(99)
	check(state.phase == BaseGameplayController.BasePhase.ARRIVAL, "Disconnect must preserve unpowered phase")
	check(not state.set_end_day_ready_authoritative(1, true), "Cannot sleep before power")
	check(not state.advance_quest_authoritative(1, BaseGameplayController.QuestStage.OFFERED), "Cannot accept quest in Day 1")
	state.deliver_fuel_authoritative(1)
	state.activate_main_breaker_authoritative(1)
	state.set_end_day_ready_authoritative(1, true)
	state.set_peer_sleeping_authoritative(1, true)
	await create_timer(1.3).timeout
	check(state.day_index == 2, "Day 1 must advance to Day 2")
	check(not state.set_end_day_ready_authoritative(1, true), "Day 2 cannot be skipped before the quest")
	check(not state.advance_quest_authoritative(99, BaseGameplayController.QuestStage.OFFERED), "Unknown peer must be rejected")
	player.apply_held_item_inventory(&"flashlight", {"battery_charge": 0.6})
	key.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "Remote interaction must be rejected")
	await interact_through_ray(player, task)
	check(state.quest_stage == BaseGameplayController.QuestStage.ACCEPTED, "Task terminal must accept the quest through player ray")
	check(int(state.load_saved_snapshot().get("quest_stage", -1)) == 2, "Accepted quest must be saved")
	await interact_through_ray(player, key)
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "Key terminal must place key into shared quest slot")
	key.network_interact(1, player)
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "Repeated pickup must not duplicate or deliver the key")
	check(player.has_held_item(&"flashlight"), "Quest key must not replace the flashlight")
	check(int(state.load_saved_snapshot().get("quest_stage", -1)) == 3, "Collected key must be saved")
	world.spawn_player_for_peer(2)
	await process_frame
	state._on_peer_left(2)
	world._on_peer_left(2)
	await process_frame
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "Shared key must survive a disconnect")
	var journal := root.get_node("QuestJournal")
	journal.open_journal()
	check(str(journal.inventory_label.text).contains("Ключ шифрования ×1"), "Journal must show the saved shared inventory")
	journal.force_close()
	await menu.return_to_main_menu()
	await create_timer(0.3).timeout
	await menu.start_standalone_flow(true)
	world = current_scene
	base = world.get_node_or_null("V3Level")
	check(base != null, "Continue must enter V3 without replaying the test room")
	state = base.get_node("BaseGameplayController")
	player = world.get_node("Players/1")
	check(state.day_index == 2 and state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "Continue must restore day and key")
	check(player.global_position.distance_to(base.get_day_start_transform(0).origin) < 0.3, "Continue must use morning spawn")
	for item in world.get_node("Gameplay/WorldItems").get_children():
		check(item.item_type != &"fuel_can", "Restored fueled base must not respawn a fuel can")
	task = base.get_node("DayTwoTaskTerminal")
	await interact_through_ray(player, task)
	check(state.quest_stage == BaseGameplayController.QuestStage.DELIVERED, "Returning to hub must deliver the key")
	check(state.can_end_current_day(), "Completed quest must unlock sleep")
	check(int(state.load_saved_snapshot().get("quest_stage", -1)) == 4, "Delivery must be persistent")
	var clone := BaseGameplayController.new()
	world.add_child(clone)
	check(clone.quest_stage == BaseGameplayController.QuestStage.DELIVERED, "Fresh controller must restore completed objective")
	clone.free()
	state.reset_day_one_authoritative()
	check(state.quest_stage == 0, "New expedition must clear the quest")
	var network := root.get_node("SteamNetwork")
	check(network.is_compatible_lobby(network.get_lobby_tag(), SteamNetworkService.NETWORK_VERSION, network.get_build_identity()), "Same source must be compatible")
	check(not network.is_compatible_lobby(network.get_lobby_tag(), "1", network.get_build_identity()), "Old protocol must be rejected")
	check(not network.is_compatible_lobby(network.get_lobby_tag(), SteamNetworkService.NETWORK_VERSION, "different"), "Different build must be rejected")
	ProjectSettings.clear(BaseGameplayController.TEST_SAVE_PATH_SETTING)
	BaseGameplayController.save_scope = "solo"
	var solo_path := BaseGameplayController.get_progress_save_path()
	BaseGameplayController.save_scope = "coop"
	check(solo_path != BaseGameplayController.get_progress_save_path(), "Solo and co-op must use separate checkpoints")
	BaseGameplayController.save_scope = "solo"
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, SAVE)
	world.free()
	BaseGameplayController.delete_progress_save()
	print("DAY_TWO_FLOW_TEST: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)


func interact_through_ray(player: Node3D, terminal: Node3D) -> void:
	var front := terminal.global_basis.z
	var standing := terminal.global_position + front * 1.8
	standing.y = 0.1 if not terminal.is_key_terminal else -17.9
	player.teleport_authoritative(standing, terminal.global_rotation.y)
	await physics_frame
	# Aim the same ray that production input uses; test the actual mounted collider.
	player.head.look_at(terminal.global_position, Vector3.UP)
	player.try_authoritative_interaction()
