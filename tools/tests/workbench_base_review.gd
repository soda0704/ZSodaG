extends SceneTree
var failures := 0
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://workbench_base_%d.cfg" % OS.get_process_id())
	create_timer(100).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func run() -> void:
	Engine.max_fps = 60
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 120: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor: GamePlayer = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.get_node("ItemDrag").set_physics_process(false)
	var table: HeavyCarryProp = base.get_node("FlamethrowerWorkbench")
	print("RESTING WORKBENCH ", table.global_transform)
	check(table.freeze and table.global_basis.y.dot(Vector3.UP) < .98, "authored leaning placement remains until the first grip")
	var query := PhysicsRayQueryParameters3D.create(table.global_position + Vector3.UP * .1, table.global_position + Vector3.DOWN * .5, 1, [table.get_rid()])
	var floor_hit: Dictionary = base.get_world_3d().direct_space_state.intersect_ray(query)
	check(not floor_hit.is_empty(), "actual base floor supports the placed workbench")
	var doors = base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
	var anchor = base.get_node("Floor_0_Base_Blockout/Doors/West_Decon_Equipment_Door_Visual_Prototype")
	check(not doors.is_door_open_at(anchor), "door behind workbench starts closed in the complete base")
	var capture := DisplayServer.get_name() != "headless"
	if capture:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1440, 900)
		DirAccess.make_dir_recursive_absolute("res://tools/.local/workbench-review")
		var lighting = get_first_node_in_group("world_lighting")
		lighting.set_debug_darkness(0.0)
		var camera := Camera3D.new()
		base.add_child(camera)
		camera.global_position = table.global_position + Vector3(-3.0, 1.6, 2.0)
		camera.look_at(table.global_position + Vector3.UP * .85)
		camera.make_current()
		for frame in 10: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://tools/.local/workbench-review/initial-placement.png")
		camera.queue_free()
		actor.camera.make_current()
		lighting.set_debug_darkness(1.0)
	for side in [0, 1]:
		var direction := table.global_basis.x.normalized() * (-1 if side == 0 else 1)
		var approach := table.grip_point(side) + direction * .65
		approach.y = .04
		actor.teleport_authoritative(approach, 0)
		for frame in 3: await physics_frame
		var look := table.grip_point(side) - direction * .12 - actor.head.global_position
		actor.rotation.y = atan2(-look.x, -look.z)
		actor.head.rotation.x = atan2(look.y, Vector2(look.x, look.z).length())
		check(actor.get_interaction_target() == table, "native E reaches end %d in the actual equipment room" % side)
		var drag = actor.get_node("ItemDrag")
		drag._hold(table.get_path())
		check(table.grips.has(actor.owner_peer_id), "real room allows solo grip at end %d" % side)
		for frame in 150:
			drag._hold(table.get_path())
			actor.update_character_animation(1.0 / 60)
			await physics_frame
		check(table.global_basis.y.dot(Vector3.UP) > .98, "held workbench stands upright in the actual room")
		if capture:
			actor.refresh_interaction_prompt()
			for frame in 5: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/workbench-review/end-%d.png" % side)
		drag.cancel()
	base.queue_free()
	await process_frame
	await process_frame
	print("WORKBENCH BASE REVIEW FAILURES ", failures)
	quit(1 if failures else 0)
