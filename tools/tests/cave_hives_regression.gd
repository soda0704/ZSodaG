extends SceneTree
var checks := 0
var failures := 0
var base: Node3D
var state: BaseGameplayController
var player: GamePlayer
var encounter: Node3D

func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://cave_hives_%d.cfg" % OS.get_process_id())
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func settle() -> void:
	for frame in 8:
		if is_instance_valid(player): player.update_character_animation(1.0/60)
		await physics_frame

func visit(point: Vector3) -> void:
	player.teleport_authoritative(point, 0)
	await settle()

func active_tasks() -> String:
	return str(root.get_node("QuestJournal").get_hud_summary().tasks)

func shoot(hive: Node3D) -> void:
	await visit(hive.global_position + Vector3(0, 0.05, -2.8))
	var offset := hive.global_position + Vector3.UP - player.head.global_position
	player.rotation.y = atan2(-offset.x, -offset.z)
	player.head.rotation.x = atan2(offset.y, Vector2(offset.x,offset.z).length())
	player.weapon.kind = &"pistol"; player.weapon.rounds = 12
	player.weapon._cooldown = 0.0; player.weapon.reload_left = 0.0
	var before: float = encounter.get_health(hive.hive_index)
	check(player.weapon.perform_action(&"fire"), "native pistol accepts a real shot")
	check(encounter.get_health(hive.hive_index) == before, "pistol ray cannot damage a hive")
	for kind in [&"m4a1",&"kitchen_knife"]:
		if kind == &"kitchen_knife":
			await visit(hive.global_position+Vector3(0,.05,-1))
			offset = hive.global_position+Vector3.UP-player.head.global_position
			player.rotation.y = atan2(-offset.x,-offset.z)
			player.head.rotation.x = atan2(offset.y,Vector2(offset.x,offset.z).length())
		player.weapon.kind = kind
		player.weapon.rounds = 12
		player.weapon.reload_left = 0.0
		player.weapon._cooldown = 0.0
		check(player.weapon.perform_action(&"fire"),"native attack is accepted: "+str(kind))
		check(encounter.get_health(hive.hive_index)==before,"hive rejects ordinary weapon damage: "+str(kind))
	player.pickup_world_item_authoritative(&"flamethrower",{})
	player.weapon.flame.set_physics_process(false)
	await visit(hive.global_position+Vector3(0,.05,-3.7))
	offset = hive.global_position+Vector3.UP*.95-player.head.global_position
	player.rotation.y = atan2(-offset.x,-offset.z)
	player.head.rotation.x = atan2(offset.y,Vector2(offset.x,offset.z).length())
	await settle()
	player.weapon.flame.set_trigger_authoritative(true)
	player.weapon.flame.step_authoritative(.1)
	player.weapon.flame.set_trigger_authoritative(false)
	check(encounter.get_health(hive.hive_index)<before,"real host flame jet damages the hive")

func run() -> void:
	base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await settle()
	root.get_node("GameMenu").force_close_menu()
	state = base.get_node("BaseGameplayController"); state.set_process(false)
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	encounter = base.get_node("Cave_Day7/HiveEncounter")
	var journal = root.get_node("QuestJournal"); journal._bind_controller()
	var data := state.get_snapshot()
	data.day_index = 6; data.main_breaker_on = true; data.fuel_delivered = true; data.fuel_liters = 40
	data.containment = {}; state._broadcast_snapshot(data)
	encounter.get_node("Hive0").apply_weapon_damage(1000)
	check(encounter.get_health(0) == encounter.starting_health and not encounter.get_node("Hive0").visible, "earlier days hide hives and reject damage")
	state.debug_set_day_authoritative(7)
	await visit(base.get_node("Cave_Day7/CaveArrival").global_position)
	check(state.containment.get("cave_visited",false) and not state.can_end_current_day(), "arrival starts cave exploration and cannot finish day seven")
	check("Исследовать пещеру" in active_tasks() and not "уль" in journal.tasks_label.text, "HUD and journal do not reveal hives before discovery")
	await visit(base.get_node("Cave_Day7/ExitThreshold").global_position)
	check(not state.containment.get("cave_exited",false), "early outdoor visit cannot complete destruction route")
	player.survival.dead = true
	await visit(Vector3(289,-155.25,-5))
	check(not state.containment.get("cave_hives_found",false), "dead player cannot discover the chamber")
	await visit(base.get_node("Cave_Day7/CaveArrival").global_position)
	player.survival.dead = false
	await visit(Vector3(289,-155.25,-5))
	check(state.containment.get("cave_hives_found",false), "living player entering end chamber discovers the three hives")
	check("Уничтожить ульи (0/3)" in active_tasks() and not "Выйти наружу" in active_tasks(), "HUD switches to destruction without revealing exit task early")
	var transforms := []; var poses := []
	for hive in encounter.hives:
		transforms.append(hive.transform); poses.append(hive.visual.animator.current_animation_position)
	await create_timer(0.35).timeout
	for index in encounter.hives.size():
		var hive = encounter.hives[index]
		check(hive is StaticBody3D and hive.transform == transforms[index] and is_equal_approx(poses[index],hive.visual.animator.current_animation_position), "placeholder %d holds authored pose without AI or root movement" % index)
	encounter.damage_hive(-1,1000); encounter.damage_hive(0,-5); encounter.damage_hive(0,NAN)
	check(encounter.get_health(0) == encounter.starting_health, "invalid index, negative damage and NaN are rejected")
	await shoot(encounter.hives[0])
	var saved := state.load_saved_snapshot()
	check(saved.containment.cave_hive_health[0] == encounter.get_health(0), "partial weapon damage persists through existing save path")
	state._apply_snapshot(saved,true,false)
	check(encounter.get_health(0) < encounter.starting_health, "snapshot restoration preserves partial damage")
	for index in 2:
		encounter.hives[index].apply_flame_damage(10000)
	await settle()
	check(state.get_destroyed_cave_hive_count() == 2 and not state.are_cave_hives_destroyed(), "two kills do not finish destruction")
	check("Уничтожить ульи (2/3)" in active_tasks() and not "Выйти наружу" in active_tasks(), "journal and HUD share partial count")
	check(encounter.hives[0].collision_layer == 0 and not encounter.hives[0].visual.animator.is_playing(), "destroyed placeholder holds native death pose and stops taking hits")
	var before := state.get_snapshot()
	encounter.hives[0].apply_flame_damage(10000)
	check(state.get_snapshot().containment == before.containment, "repeated damage cannot double-count a destroyed hive")
	await visit(Vector3(292.891,-155.3,-2.63))
	encounter.hives[2].apply_flame_damage(10000)
	await settle()
	check(state.are_cave_hives_destroyed() and "Выйти наружу" in active_tasks(), "last destruction reveals outdoor objective")
	check(not state.can_end_current_day() and not state.containment.get("cave_exited",false), "all hives destroyed still requires a fresh exit")
	check(not journal.tasks_label.text.contains("отдохнуть"), "cave route does not tell player to return to bed")
	await visit(base.get_node("Cave_Day7/ExitThreshold").global_position)
	check(state.containment.get("cave_exited",false) and state.can_end_current_day(), "real living-player exit completes the route after destruction")
	check(state.load_saved_snapshot().containment.get("cave_exited",false), "outdoor completion is persisted")
	var completed := state.get_snapshot()
	data = completed.duplicate(true); data.containment = {"cave_visited":true,"cave_exited":true}
	state._broadcast_snapshot(data)
	check(not state.are_cave_hives_destroyed() and not state.can_end_current_day(), "legacy visit-only checkpoint cannot skip new hive objectives")
	state._broadcast_snapshot(completed)
	check(state.are_cave_hives_destroyed() and encounter.hives.all(func(hive): return hive.collision_layer == 0), "completed snapshot restores all three destruction states")
	data = completed.duplicate(true); data.day_index = 8
	data.containment = {"cave_visited":true,"cave_exited":true}
	state._broadcast_snapshot(data)
	await visit(Vector3(289,-155.25,-5))
	check(state.containment.get("cave_hives_found",false) and not state.containment.get("cave_exited",false), "legacy calendar beyond day seven discovers hives and clears old exit")
	for hive in encounter.hives: hive.apply_flame_damage(10000)
	await visit(base.get_node("Cave_Day7/ExitThreshold").global_position)
	check(state.can_end_current_day() and state.containment.get("cave_exited",false), "older day-eight campaign can complete the new cave route")
	state._broadcast_snapshot(completed)
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		data = completed.duplicate(true); data.containment = {}; state._broadcast_snapshot(data)
		await visit(Vector3(285,-155.0,-8.7))
		await visit(Vector3(280,-154.9,-11))
		var camera := Camera3D.new()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		root.add_child(camera); camera.current = true
		camera.global_position = Vector3(285,-153.5,-8.7); camera.look_at(Vector3(293,-154.1,-2.6))
		player.body_animator.set_external_view(true)
		base.get_node("WorldLighting").set_debug_darkness(0.0)
		DisplayServer.window_set_size(Vector2i(1280,720)); root.size = Vector2i(1280,720)
		await create_timer(0.7).timeout; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-cave-hives-discovery.png"))
		for hive in encounter.hives: hive.apply_flame_damage(10000)
		await create_timer(0.7).timeout; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-cave-hives-cleared.png"))
		camera.queue_free()
	base.queue_free(); await process_frame
	print("CAVE HIVES CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
