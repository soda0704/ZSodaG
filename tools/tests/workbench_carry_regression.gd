extends SceneTree
var checks := 0
var failures := 0
var actors: Array[GamePlayer] = []
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://workbench_carry_%d.cfg" % OS.get_process_id())
	create_timer(80).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func settle(count := 5) -> void:
	for frame in count: await physics_frame
func aim(actor: GamePlayer, point: Vector3) -> void:
	var offset := point - actor.head.global_position
	actor.rotation.y = atan2(-offset.x, -offset.z)
	actor.head.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())
func run() -> void:
	root.get_node("GameMenu").force_close_menu()
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	var state := BaseGameplayController.new()
	state.name = "BaseGameplayController"
	arena.add_child(state)
	state.set_process(false)
	var table: HeavyCarryProp = load("res://scenes/objects/crafting/flamethrower_workbench.tscn").instantiate()
	arena.add_child(table)
	table.position = Vector3.ZERO
	await settle(20)
	check(not table.pickup_enabled and not table.draggable and table.checkpoint_key != &"", "workbench is persistent furniture, never an inventory pickup")
	check(table.scale.is_equal_approx(Vector3.ONE), "rigid body has unit scale; edited dimensions live in visual and hull resources")
	var checkpoint_session = load("res://scenes/levels/base_session.tscn").instantiate()
	# Keep the native onready dependencies, but not the helicopter's collision
	# at the same origin as this isolated furniture arena.
	for child in checkpoint_session.get_children():
		if child.name not in ["Players", "OverviewCamera", "LobbyHud", "Gameplay"]: child.free()
	checkpoint_session.set_script(load("res://tools/tests/fixtures/heavy_prop_checkpoint_session.gd"))
	root.add_child(checkpoint_session)
	var placed: Dictionary = checkpoint_session.capture_heavy_prop_checkpoint()
	table.freeze = false
	table.position.x += 2
	checkpoint_session.restore_heavy_prop_checkpoint(placed)
	check(table.freeze and table.position.is_equal_approx(Vector3.ZERO), "checkpoint preserves the untouched leaning-placement hold")
	for peer in [1, 2]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(peer, "Carrier", Vector3(-1.6 if peer == 1 else 1.6, .02, 0), Color.WHITE)
		actor.name = str(peer)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.get_node("ItemDrag").set_physics_process(false)
		actors.append(actor)
	await settle()
	# The same solo player must be able to grab either end through the real E path.
	for side in [0, 1]:
		actors[0].position = Vector3(-1.6 if side == 0 else 1.6, .02, 0)
		actors[1].position = Vector3(0, .02, 5)
		aim(actors[0], table.grip_point(side) + Vector3(.1 if side == 0 else -.1, 0, 0))
		await settle()
		check(actors[0].get_interaction_target() == table, "native E ray reaches workbench end " + str(side))
		var drag = actors[0].get_node("ItemDrag")
		check(drag.begin_interaction(), "hold begins at workbench end " + str(side))
		drag._hold(table.get_path())
		check(table.grips.has(1) and int(table.grips[1].slot) == side, "solo player owns the selected end " + str(side))
		drag.cancel()
	check(table.grips.is_empty(), "both solo grips release without lingering owners")
	var moved: Dictionary = checkpoint_session.capture_heavy_prop_checkpoint()
	table.freeze = true
	checkpoint_session.restore_heavy_prop_checkpoint(moved)
	check(not table.freeze, "checkpoint does not anchor a workbench that has already been moved")
	# Start physically tilted, without changing the visual transform at pickup.
	table.position = Vector3(0, .35, 0)
	table.rotation.z = .3
	table.linear_velocity = Vector3.ZERO
	table.angular_velocity = Vector3.ZERO
	actors[0].position = Vector3(-1.6, .02, 0)
	actors[1].position = Vector3(0, .02, 5)
	aim(actors[0], table.grip_point(0) + Vector3(.1, 0, 0))
	await settle(1)
	var held = actors[0].get_node("ItemDrag")
	held._hold(table.get_path())
	check(table.grips.has(1), "tilted workbench can be grabbed")
	for frame in 180:
		held._hold(table.get_path())
		await physics_frame
	print("SOLO TABLE ", table.global_transform, " grips ", table.grips.keys())
	check(table.grips.has(1) and table.global_basis.y.dot(Vector3.UP) > .98, "solo carry physically straightens the workbench")
	check(absf(table.position.y) < .12, "solo workbench remains on the floor")
	var start := table.position
	for frame in 90:
		actors[0].position.z += .006
		held._hold(table.get_path())
		await physics_frame
	print("SOLO DRAG ", start, " -> ", table.position, " grips ", table.grips.keys())
	check(table.position.distance_to(start) > .15, "solo dragging actually moves the workbench")
	held.cancel()
	table.position = Vector3.ZERO
	table.rotation = Vector3.ZERO
	table.linear_velocity = Vector3.ZERO
	table.angular_velocity = Vector3.ZERO
	await settle(5)
	for index in 2:
		actors[index].position = Vector3(-1.6 if index == 0 else 1.6, .02, 0)
		aim(actors[index], table.grip_point(index) + Vector3(.1 if index == 0 else -.1, 0, 0))
		await settle(1)
		actors[index].get_node("ItemDrag")._hold(table.get_path())
	check(table.grips.size() == 2, "two players can take opposite ends")
	for frame in 150:
		for actor in actors: actor.get_node("ItemDrag")._hold(table.get_path())
		await physics_frame
	print("PAIRED TABLE ", table.global_transform, " grips ", table.grips.keys())
	check(table.grips.size() == 2 and table.position.y > .2 and table.position.y < .65 and table.global_basis.y.dot(Vector3.UP) > .98, "paired carry raises a level workbench")
	actors[1].get_node("ItemDrag").cancel()
	for frame in 100:
		actors[0].get_node("ItemDrag")._hold(table.get_path())
		await physics_frame
	check(table.grips.size() == 1 and absf(table.position.y) < .12, "partner release returns the remaining solo carrier to floor dragging")
	actors[0].get_node("ItemDrag").cancel()
	# Real fitted door + the existing automatic/pry manager, without other floors.
	var floor_zero = load("res://scenes/levels/Floor_0_Base_Blockout.tscn").instantiate()
	var doors = floor_zero.get_node("Doors")
	floor_zero.remove_child(doors)
	floor_zero.free()
	arena.add_child(doors)
	await settle(10)
	var manager = doors.get_node("AutomaticDoors")
	var anchor = doors.get_node("West_Decon_Equipment_Door_Visual_Prototype")
	var record: Dictionary
	for door in manager._doors:
		if door.anchor == anchor: record = door
	check(not record.is_empty() and not record.startup_route and not record.open, "equipment door is excluded from the initially open generator route")
	var route = doors.get_node("West_Hub_Decon_Door_Visual_Prototype")
	check(manager.is_door_open_at(route), "remaining generator route stays open without power")
	actors[0].position = anchor.global_position + Vector3(-1.6, .02, 0)
	actors[0].crowbar_uses = 2
	var interaction = record.blocker.get_parent()
	interaction.network_interact(1, actors[0])
	await settle(85)
	check(manager.is_door_pried(record) and record.open and actors[0].crowbar_uses == 1, "native crowbar action opens door and consumes exactly one use")
	for day in [2, 4, 7]:
		for powered in [true, false]:
			var snapshot := state.get_snapshot()
			snapshot.day_index = day
			snapshot.fuel_delivered = true
			snapshot.main_breaker_on = powered
			state._broadcast_snapshot(snapshot)
			manager._process(.1)
			interaction.network_interact(1, actors[0])
			manager._process(.1)
			await settle(48)
			check(not record.open and not record.blocker.disabled and manager.is_door_pried(record), "manual close survives power=" + str(powered) + " day=" + str(day))
			interaction.network_interact(1, actors[0])
			manager._process(.1)
			await settle(48)
			check(record.open and record.blocker.disabled and actors[0].crowbar_uses == 1, "manual reopen never consumes another crowbar use")
	state.save_progress_authoritative()
	var saved := state.load_saved_snapshot()
	state.maintenance = {}
	state._apply_snapshot(saved, true)
	manager._process(.1)
	check(manager.is_door_pried(record) and record.open, "restored snapshot retains permanent manual-door state")
	arena.queue_free()
	checkpoint_session.queue_free()
	actors.clear()
	await settle()
	print("WORKBENCH CARRY CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
