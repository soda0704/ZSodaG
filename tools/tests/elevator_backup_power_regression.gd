extends SceneTree
## Production pickup, socket, first-night gate and checkpoint; isolated user data.

var failures := 0
var checks := 0
var save_path: String


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1


func settle() -> void:
	for frame in 6:
		await physics_frame
	await process_frame


func prepare_player(world: Node) -> GamePlayer:
	var player := world.get_node("Players/1") as GamePlayer
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	return player


func fuses(world: Node) -> Array[Node]:
	return world.get_node("Gameplay/WorldItems").get_children().filter(func(item: Node):
		return item.get("item_type") == GamePlayer.FUSE_ITEM and not item.is_queued_for_deletion()
	)


func run() -> void:
	save_path = "user://elevator_backup_regression_%d.cfg" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, save_path)
	var menu := root.get_node("GameMenu")
	await menu.start_standalone_flow()
	var world = current_scene
	await world._enter_v3_level()
	await settle()
	var base := world.get_node("V3Level") as BaseBlockoutRuntime
	var state := base.get_node("BaseGameplayController") as BaseGameplayController
	var elevator := base.get_node("Elevator_Functional_Blockout") as FunctionalElevatorController
	var socket := base.get_node("Floor_0_Base_Blockout/Gameplay/ElevatorBackupPower") as ElevatorBackupPower
	var player := prepare_player(world)
	var marker := base.get_node(base.elevator_backup_fuse_spawn_path) as Marker3D
	var lighting := base.get_node("BasePowerLightingController") as BasePowerLightingController
	check(not elevator.is_powered and not state.elevator_backup_installed, "new expedition starts without elevator backup")
	check(fuses(world).size() == 1, "exactly one fuse spawns in a new expedition")
	if fuses(world).size() != 1:
		await finish()
		return
	var fuse := fuses(world)[0] as WorldItemPickup
	check(Vector2(fuse.global_position.x, fuse.global_position.z).distance_to(Vector2(marker.global_position.x, marker.global_position.z)) < 0.08, "fuse uses the authored medical-room marker")
	check(state.refill_authoritative(1, 20.0) > 0 and state.activate_main_breaker_authoritative(1), "existing main power can be restored")
	check(elevator.is_powered and not state.can_end_current_day(), "mains power the elevator but first night requires backup")
	player.teleport_authoritative(socket.global_position + Vector3(0, 0, -1), 0)
	socket.network_interact(1, player)
	check(not state.elevator_backup_installed, "empty hands cannot connect backup")
	player.teleport_authoritative(marker.global_position + Vector3(0, -marker.global_position.y + 0.1, -1), 0)
	fuse.network_interact(1, player)
	await settle()
	check(player.has_held_item(GamePlayer.FUSE_ITEM) and fuses(world).is_empty(), "production pickup transfers fuse to inventory")
	check(not state.install_elevator_backup_authoritative(1) and player.has_held_item(GamePlayer.FUSE_ITEM), "distant installation is rejected without consuming fuse")
	player.teleport_authoritative(socket.global_position + Vector3(0, 0, -1), 0)
	socket.network_interact(2, player)
	check(not state.elevator_backup_installed and player.has_held_item(GamePlayer.FUSE_ITEM), "incorrect peer cannot use another player's fuse")
	player.survival.dead = true
	check(not state.install_elevator_backup_authoritative(1), "dead player cannot install fuse")
	player.survival.dead = false
	socket.network_interact(1, player)
	check(state.elevator_backup_installed and not player.has_held_item(GamePlayer.FUSE_ITEM), "installation consumes fuse and connects shared backup")
	check(socket.inserted_fuse.visible and socket.connected_indicator.visible and not socket.disconnected_indicator.visible, "authored socket presents connected state")
	check(state.can_end_current_day(), "first-night gate opens after installation")
	check(not state.install_elevator_backup_authoritative(1), "duplicate installation is rejected")
	check(state.set_end_day_ready_authoritative(1, true) and state.set_peer_sleeping_authoritative(1, true) and state.advance_day_authoritative(), "normal sleep advances from day one")
	await settle()
	check(state.day_index == 2 and state.maintenance.get("wires_required", false), "existing first-night wiring failure remains active")
	check(not state.main_breaker_on and elevator.is_powered and not lighting.is_standard_powered, "backup powers only elevator during wiring failure")
	var snapshot := state.get_snapshot()
	snapshot.maintenance["wires_required"] = false
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 0.01
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	state._process(2.0)
	check(is_zero_approx(state.fuel_liters) and not state.main_breaker_on and elevator.is_powered, "fuel depletion leaves elevator on solar backup")
	check(state.save_progress_authoritative(), "backup checkpoint saves successfully")
	var config := ConfigFile.new()
	check(config.load(save_path) == OK and config.get_value("base", "elevator_backup_installed", false), "checkpoint stores installed backup")
	var inventory: Dictionary = config.get_value("inventory", "checkpoint", {})
	check(inventory.get("elevator_backup_layout_version", 0) == 1 and StringName(inventory.players.solo.held_item) != GamePlayer.FUSE_ITEM, "checkpoint stores layout version and consumed fuse together")
	await menu.start_standalone_flow(true)
	await settle()
	world = current_scene
	base = world.get_node("V3Level") as BaseBlockoutRuntime
	state = base.get_node("BaseGameplayController") as BaseGameplayController
	elevator = base.get_node("Elevator_Functional_Blockout") as FunctionalElevatorController
	socket = base.get_node("Floor_0_Base_Blockout/Gameplay/ElevatorBackupPower") as ElevatorBackupPower
	player = prepare_player(world)
	check(state.day_index == 2 and state.elevator_backup_installed and not state.main_breaker_on and elevator.is_powered, "real continue restores elevator backup during blackout")
	check(fuses(world).is_empty() and not player.has_held_item(GamePlayer.FUSE_ITEM) and socket.inserted_fuse.visible, "continue does not duplicate consumed fuse")
	var copy := state.get_snapshot()
	check(copy.elevator_backup_installed, "shared snapshot includes backup for late clients")
	# An older day-one save gets the new pickup once, using the normal restore flow.
	config.load(save_path)
	config.erase_section_key("base", "elevator_backup_installed")
	config.set_value("base", "day_index", 1)
	config.set_value("base", "maintenance", {})
	var old_inventory: Dictionary = config.get_value("inventory", "checkpoint", {})
	old_inventory.erase("elevator_backup_layout_version")
	config.set_value("inventory", "checkpoint", old_inventory)
	config.save(save_path)
	check(not state.load_saved_snapshot().elevator_backup_installed, "legacy day-one checkpoint still requires fuse")
	await menu.start_standalone_flow(true)
	await settle()
	world = current_scene
	check(fuses(world).size() == 1, "legacy day-one continuation seeds one medical fuse")
	await menu.start_standalone_flow(true)
	await settle()
	world = current_scene
	check(fuses(world).size() == 1, "second continuation restores rather than duplicates the fuse")
	state = world.get_node("V3Level/BaseGameplayController") as BaseGameplayController
	config.load(save_path)
	config.erase_section_key("base", "elevator_backup_installed")
	config.set_value("base", "day_index", 3)
	config.save(save_path)
	check(state.load_saved_snapshot().elevator_backup_installed, "legacy campaigns beyond first night preserve elevator access")
	await finish()


func finish() -> void:
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("CHECKS ", checks, " RESULT FAILURES ", failures)
	quit(0 if failures == 0 else 1)
