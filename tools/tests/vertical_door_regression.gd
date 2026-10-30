extends SceneTree
var checks := 0
var failures := 0
var output := "res://tools/.local/feedback-fixes-2026-10-30"
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://vertical_doors_%d.cfg" % OS.get_process_id())
	create_timer(60).timeout.connect(func(): quit(2)); run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func capture(base: Node3D, door: Node3D, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	var camera := Camera3D.new(); base.add_child(camera)
	camera.global_position = door.to_global(Vector3(.5,1.7,3))
	camera.look_at(door.to_global(Vector3(0,1.5,0))); camera.make_current()
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	camera.queue_free(); await process_frame
func run() -> void:
	Engine.max_fps = 60
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate(); root.add_child(base); current_scene = base
	for i in 15: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false); player.teleport_authoritative(Vector3(24,0,-5),0)
	var state: BaseGameplayController = base.get_node("BaseGameplayController"); state.set_process(false)
	var manager: BaseAutoDoorManager = base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
	manager.set_process(false)
	for name in ["West_Hub_Decon_Door_Visual_Prototype","West_Pedestrian_Exterior_Door_Visual_Prototype"]:
		var found := false
		for door in manager._doors:
			if str(door.anchor.name) != name: continue
			found = true
			check(not door.leaf_pairs.is_empty(),name+" has authored moving leaves")
			for pair in door.leaf_pairs:
				var travel: Vector3 = pair.open_position - pair.closed_position
				check(travel.y > 2.3 and absf(travel.x) < .001 and absf(travel.z) < .001,name+" opens upwards without entering adjacent glass")
			manager._apply_door_state(door,false,true)
			await capture(base,door.anchor,name+"-closed")
			manager._apply_door_state(door,true,false)
			await create_timer(.25).timeout
			for pair in door.leaf_pairs:
				check(absf(pair.leaf.position.x - pair.closed_position.x) < .001,name+" moving leaf stays within its original lateral span")
			await create_timer(1).timeout
			check(door.blocker.disabled,name+" releases passage after opening")
			for pair in door.leaf_pairs:
				check(pair.leaf.position.is_equal_approx(pair.open_position),name+" reaches authored raised position")
			await capture(base,door.anchor,name+"-open")
			manager._apply_door_state(door,false,false); await create_timer(1.2).timeout
			check(not door.blocker.disabled,name+" restores passage collision after closing")
			for pair in door.leaf_pairs: check(pair.leaf.position.is_equal_approx(pair.closed_position),name+" returns without sideways offset")
		check(found,name+" exists in actual level")
	current_scene = null; base.queue_free(); await process_frame
	print("VERTICAL DOOR CHECKS ",checks," FAILURES ",failures); quit(0 if failures == 0 else 1)
