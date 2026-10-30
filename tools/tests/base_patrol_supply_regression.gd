extends SceneTree
## Real authored rooms, automatic doors, persistent patrols and supply migration.
var checks := 0
var failures := 0

func _initialize() -> void:
	var isolated := "user://base_patrol_supply_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated))
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, isolated + "/slots")
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, isolated + "/campaign.cfg")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", isolated + "/settings.json")
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func frames(count := 3) -> void:
	for i in count: await physics_frame

func run() -> void:
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await frames(8)
	root.get_node("GameMenu").force_close_menu()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false
	state.set_process(false)
	var encounter = base.get_node("ContainmentEncounter")
	var head = encounter.get_node("Monster3")
	var evolution = encounter.get_node("Monster4")
	check(head.visible and evolution.visible and state.day_index == 1, "authored patrol creatures active on first day")
	check(head.ai_profile.weapon_damage_enabled, "minus-one patrol accepts ordinary weapon damage")
	check(is_equal_approx(head.agent.path_height_offset,0.5), "navigation foot height survives scene export through the AI profile")
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	player.global_position = Vector3(1000,500,1000)
	for actor in [head,evolution]:
		actor.ai_profile = actor.ai_profile.duplicate()
		actor.ai_profile.sight_enabled = false
		actor.ai_profile.hearing_enabled = false
		actor.reset_enemy()
	var manager: BaseAutoDoorManager
	for candidate in get_nodes_in_group("base_auto_door_managers"):
		if str(candidate.get_parent().get_path()).ends_with("Floor_Minus1_Control_Security_Blockout/Doors"): manager = candidate
	var evo_marks = base.get_node("PatrolRoutes/Evolution").get_children()
	var seen_evo := {}
	var opened := {}
	var paused_frames := 0
	Engine.time_scale = 6.0
	for powered in [false,true]:
		if powered:
			var snapshot := state.get_snapshot()
			snapshot.main_breaker_on = true
			snapshot.fuel_delivered = true
			snapshot.fuel_liters = 30.0
			state._broadcast_snapshot(snapshot)
		var marks = base.get_node("PatrolRoutes/Head" if powered else "PatrolRoutes/HeadUnpowered").get_children()
		var expected := 0
		var elapsed := 0.0
		var central_only := true
		while expected < marks.size() and elapsed < 45.0:
			await physics_frame
			elapsed += Engine.time_scale / float(Engine.physics_ticks_per_second)
			if head.global_position.x > -13.0: central_only = false
			if not powered and (absf(head.global_position.z)>5.8 or head.global_position.x < -51.0): central_only = false
			if not powered and Vector2(head.velocity.x,head.velocity.z).length()<.05: paused_frames += 1
			for point in evo_marks:
				if evolution.global_position.distance_to(point.global_position) < .9: seen_evo[point.name] = true
			for door in manager._doors:
				if door.open and head.global_position.distance_to(door.anchor.global_position)<4.6: opened[str(door.anchor.name)] = true
			if head.global_position.distance_to(marks[expected].global_position) < .85:
				check(true, ("powered" if powered else "unpowered")+" patrol physically reaches "+str(marks[expected].name))
				expected += 1
				elapsed = 0.0
			if expected < marks.size() and head._patrol_index > expected:
				for index in head.get_slide_collision_count(): print("BLOCKER ",head.get_slide_collision(index).get_collider().get_path())
				check(false,"patrol skipped "+str(marks[expected].name)+" at "+str(head.global_position))
				break
		if expected < marks.size():
			print("INCOMPLETE ",marks[expected].name," position=",head.global_position," goal=",head._patrol_goal," index=",head._patrol_index," power=",state.main_breaker_on," nav=",head.agent.get_current_navigation_path())
			for index in head.get_slide_collision_count(): print("BLOCKER ",head.get_slide_collision(index).get_collider().get_path())
		check(expected == marks.size(), ("powered" if powered else "unpowered")+" patrol completes every waypoint")
		check(central_only,"powered patrol never enters lift checkpoint" if powered else "unpowered patrol stays inside central hall")
	Engine.time_scale = 1.0
	check(head.global_position.y < -17.0,"head exists on minus one, never ground floor")
	check(paused_frames > 30,"unpowered patrol periodically stops")
	check(seen_evo.size() == evo_marks.size(),"evolution physically completes laboratory circle")
	print("OPENED ",opened)
	check(opened.has("l1_surveillance") and opened.has("l1_command_center"),"powered doors open in front of the patrolling head")
	# The checkpoint is excluded from patrol, but is reachable when chasing a seen player.
	head.set_ai_enabled(false)
	head.global_position = Vector3(-16,-17.95,0)
	head.velocity = Vector3.ZERO
	var joist = base.get_node("Floor_Minus1_Control_Security_Blockout/FallenCheckpointJoist")
	joist.global_position += Vector3(0,0,5)
	player.teleport_authoritative(Vector3(-10,-17.95,0),0)
	player.survival.debug_invincible = true
	# Let the player's normal proximity request finish opening the door first.
	await frames(60)
	head.ai_profile.sight_enabled = true
	head._sight_left = 0.0
	head.look_at(player.global_position)
	head._patrol_goal = head.global_position
	head._patrol_left = 2.0
	check(head._can_see(player), "player is actually visible through the opened checkpoint door")
	head.set_ai_enabled(true)
	var chased := false
	for frame in 360:
		await physics_frame
		if head.global_position.x > -12.0: chased = true; break
	check(chased,"head may enter lift checkpoint while chasing a seen player")
	head.set_ai_enabled(false)
	evolution.set_ai_enabled(false)
	# Shoot the actual head collider through the production weapon raycast.
	head.global_position = Vector3(-48,-17.98,0)
	head.velocity = Vector3.ZERO
	player.teleport_authoritative(Vector3(-48,-17.9,3),0)
	player.head.look_at(head.global_position + Vector3.UP*.55)
	player.pickup_world_item_authoritative(&"pistol", {"rounds":12})
	var weapon = player.weapon
	await frames()
	for i in 3:
		weapon._cooldown = 0.0
		player.head.look_at(head.global_position + Vector3.UP*.55)
		weapon.perform_action(&"fire")
		await frames()
	check(encounter.get_monster_health(3) == 0.0, "three real pistol hits kill the authored head")
	check(not state.containment.get("fault",false), "patrol death does not complete or fault the story encounter")
	state.progress_persistence_enabled = true
	check(state.save_progress_authoritative(false,"start"), "patrol death saves through existing expedition store")
	var saved := state.load_saved_snapshot()
	check(float(saved.get("containment",{}).get("patrol_health",{}).get("3",-1)) == 0.0, "patrol death survives disk roundtrip")
	state.progress_persistence_enabled = false
	base.queue_free(); await frames(6)
	print("BASE PATROL SUPPLY CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
