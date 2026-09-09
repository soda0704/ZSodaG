extends SceneTree

var failed := false
var visual := false
func _initialize() -> void:
	visual = OS.get_cmdline_user_args().has("visual")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://survival_test.cfg")
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error("SURVIVAL_TEST: " + message)

func _run() -> void:
	BaseGameplayController.delete_progress_save()
	await root.get_node("GameMenu").start_standalone_flow()
	var world := current_scene
	await world._enter_v3_level()
	var player: Node3D = world.get_node("Players/1")
	player.set_physics_process(false)
	var life: Node = player.survival
	life.set_physics_process(false)
	life.observe_motion(-5.0, true, 0.0)
	check(life.health == 100.0, "Small landing is safe")
	life.observe_motion(-16.0, true, 0.0)
	check(life.health < 100.0 and not life.dead, "Medium fall injures")
	life.health = 100.0
	life.observe_motion(0.0, true, 6.0)
	check(life.health == 100.0, "Elevator movement alone is safe")
	player.apply_inventory_snapshot({"has_flashlight": true, "held_item": &"flashlight", "battery_charge": 0.2, "spare_batteries": [1.0], "revision": 100})
	player.request_inventory_action(&"replace_battery")
	life.observe_motion(-24.0, true, 0.0)
	check(life.dead and life.health == 0.0, "Large fall kills")
	if visual:
		await create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Death.png"))
	check(not player.perform_inventory_action_authoritative(&"drop_battery"), "Dead player cannot mutate inventory")
	root.get_node("QuestJournal").open_journal()
	check(not root.get_node("QuestJournal").is_journal_open(), "Dead player cannot reopen journal")
	await create_timer(1.15).timeout
	check(is_equal_approx(player.get_inventory_snapshot().battery_charge, 0.2), "Death cancels pending battery replacement")
	life._physics_process(4.1)
	check(not life.dead and life.health == 100.0 and player.global_position.y > -1.0, "Respawn returns to base")
	check(player.get_inventory_snapshot().spare_batteries.size() == 1, "Equipment is retained without duplication")
	player.global_position.y = -170.0
	life._physics_process(0.1)
	check(life.dead, "Below deepest authored floor kills")
	life._respawn()
	player.global_position.x = 300.0
	life._physics_process(0.1)
	check(life.dead, "Horizontal escape kills")
	life._respawn()
	player.velocity.y = -30.0
	player.global_position += Vector3.UP * 10.0
	player.move_and_slide()
	life._physics_process(3.1)
	check(life.dead, "Unbounded freefall kills before waiting for a landing")
	life._respawn()
	var zone: RadiationZone = get_first_node_in_group("radiation_zones")
	check(zone != null and zone.global_position.y < -35.0, "Reservoir source exists on minus two")
	check(zone.intensity_at(zone.global_position + Vector3.UP) > 0.9, "Source core is hazardous")
	check(zone.intensity_at(zone.global_position + Vector3.UP * 18.0) == 0.0, "Radiation does not leak onto other floors")
	if visual:
		var preview_camera := Camera3D.new()
		world.add_child(preview_camera)
		preview_camera.global_position = zone.global_position + Vector3(10, 5, 10)
		preview_camera.look_at(zone.global_position + Vector3.UP * 2.0)
		preview_camera.current = true
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-Radiation.png"))
		preview_camera.queue_free()
	player.global_position = zone.global_position + Vector3.UP
	for index in 70:
		life._physics_process(0.1)
	check(life.radiation > 90.0 and life.health < 100.0, "Exposure accumulates and damages")
	var dose: float = life.radiation
	player.global_position = zone.global_position + Vector3.RIGHT * 15.0
	life._physics_process(1.0)
	check(life.radiation < dose, "Dose decays outside source")
	player.global_position = zone.global_position + Vector3.UP
	for index in 100:
		if life.dead:
			break
		life._physics_process(0.1)
	check(life.dead and life.reason == "Радиационное поражение", "Extended exposure kills")
	world.free()
	BaseGameplayController.delete_progress_save()
	print("SURVIVAL_TEST: " + ("FAIL" if failed else "PASS"))
	quit(1 if failed else 0)
