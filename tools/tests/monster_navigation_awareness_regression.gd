extends SceneTree
var checks := 0
var failures := 0
var base: Node3D
var actor: CharacterBody3D
var player: GamePlayer
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING, "user://monster_awareness_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func settle(frames := 6) -> void:
	for frame in frames: await physics_frame
func reset_interest() -> void:
	actor._forget_interest()
	actor._search_left = 0.0
	actor._sight_left = 0.0
	player._noise_step_distance = 0.0
func footstep(at: Vector3, crouched: bool, running: bool) -> void:
	reset_interest()
	player.global_position = at
	player._is_crouching = crouched
	player._sprint_active = running
	player._emit_movement_noise(Vector3(1.6, 0, 0), true)
func find_route(region: NavigationRegion3D) -> Dictionary:
	var mesh := region.navigation_mesh
	var vertices := mesh.get_vertices()
	var centers: Array[Vector3] = []
	for index in mesh.get_polygon_count():
		var polygon := mesh.get_polygon(index)
		var center := Vector3.ZERO
		for vertex in polygon: center += vertices[vertex]
		centers.append(region.to_global(center / polygon.size()))
	var space := region.get_world_3d().direct_space_state
	for start in centers:
		for goal in centers:
			var direct := start.distance_to(goal)
			if direct < 5.0 or direct > 12.0: continue
			var ray := PhysicsRayQueryParameters3D.create(start + Vector3.UP, goal + Vector3.UP, 1)
			if space.intersect_ray(ray).is_empty(): continue
			var path := NavigationServer3D.map_get_path(region.get_navigation_map(), start, goal, true)
			if path.size() < 3 or path[-1].distance_to(goal) > 0.5: continue
			var clear := true
			for index in path.size() - 1:
				ray.from = path[index] + Vector3.UP
				ray.to = path[index + 1] + Vector3.UP
				if not space.intersect_ray(ray).is_empty(): clear = false; break
			if clear: return {"start": start, "goal": goal, "path": path}
	return {}
func follow_route(route: Dictionary, shift: Vector3) -> void:
	actor.global_position = route.start + shift + Vector3.UP * 0.1
	actor._home = actor.global_position
	actor.velocity = Vector3.ZERO
	actor._blocked_time = 0.0
	actor._navigation_goal = Vector3.INF
	player.global_position = route.goal + shift + Vector3.UP * 0.1
	player._is_crouching = false
	reset_interest()
	await settle()
	actor.hear_noise(player, player.global_position, 100.0)
	var initial: float = actor.global_position.distance_to(player.global_position)
	var closest := initial
	for frame in 900:
		actor._physics_process(1.0 / 60.0)
		closest = minf(closest, actor.global_position.distance_to(player.global_position))
		if closest < 1.0: break
		await physics_frame
	check(closest < 1.0, "native agent rounds real containment walls at vertical offset %.0f (closest %.2f)" % [shift.y, closest])
func run() -> void:
	base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base); current_scene = base
	await settle()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.progress_persistence_enabled = false; state.set_process(false)
	state.debug_set_day_authoritative(5)
	root.get_node("GameMenu").force_close_menu()
	var encounter = base.get_node("ContainmentEncounter")
	actor = encounter.get_node("Monster1")
	check(actor._patrol_goal == actor._home, "encounter initializes patrol at authored spawn")
	for monster in get_nodes_in_group("hostile_monsters"):
		monster.set_physics_process(false)
		monster.collision_layer = 0
	actor.collision_mask = 1
	actor.ai_profile = actor.ai_profile.duplicate()
	actor.ai_profile.sight_enabled = false
	actor.ai_profile.hearing_memory = 60.0
	player = get_first_node_in_group("local_player")
	player.set_physics_process(false); player.survival.set_physics_process(false)
	player.survival.debug_invincible = true
	await settle(20)
	var region: NavigationRegion3D = encounter.get_node("NavigationRegion")
	var route := find_route(region)
	check(not route.is_empty(), "real baked navigation contains a physical route around a blocked sightline")
	if not route.is_empty():
		await follow_route(route, Vector3.ZERO)
		reset_interest()
		player.global_position.y += 18.0
		actor._returning_home = false
		actor._home = actor.global_position
		actor._patrol_goal = actor.global_position
		actor._patrol_left = 0.0
		var patrol_start := actor.global_position
		for frame in 180:
			actor._physics_process(1.0 / 60.0)
			await physics_frame
		check(actor.global_position.distance_to(patrol_start) > 0.5, "idle patrol physically moves on baked navigation")
		var level: Node3D = base.get_node("Floor_Minus4_Biocontainment_Blockout")
		level.position.y += 300.0
		region.position.y += 300.0
		await settle(12)
		await follow_route(route, Vector3(0,300,0))
		level.position.y -= 300.0; region.position.y -= 300.0
		await settle()
	var origin := Vector3(1000, 500, 1000)
	var monsters := get_nodes_in_group("hostile_monsters")
	player.global_position = origin
	for index in monsters.size():
		monsters[index].global_position = origin + Vector3(index * 2.0 + 2.0, 0, 0)
		monsters[index]._forget_interest()
	load("res://scripts/gameplay/gameplay_noise.gd").emit(player, player.weapon.pistol_noise_radius)
	var heard := 0
	for monster in monsters:
		if monster._alert_target == player: heard += 1
	check(heard == monsters.size(), "gunshot alerts every nearby active monster")
	var doors: BaseAutoDoorManager = get_first_node_in_group("base_auto_door_managers")
	var door: Dictionary = doors._doors[0]
	player.global_position = origin
	actor.global_position = door.anchor.global_position
	doors._refresh_nearby_actors()
	check(doors._has_player_near(door.anchor, 3.2), "automatic door detects nearby living monster")
	actor.global_position.y += 18.0
	doors._refresh_nearby_actors()
	check(not doors._has_player_near(door.anchor, 3.2), "automatic door ignores monster on another level")
	actor.global_position = origin; actor._home = origin; actor.rotation = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	footstep(origin + Vector3(0,0,4), false, false)
	check(actor._alert_target == player, "ordinary steps emit actual AI stimulus nearby")
	footstep(origin + Vector3(0,0,10), false, false)
	check(actor._alert_target == null, "ordinary steps are not heard at running distance")
	footstep(origin + Vector3(0,0,10), false, true)
	check(actor._alert_target == player, "running draws a monster from farther away")
	footstep(origin + Vector3(0,0,2), true, false)
	check(actor._alert_target == null, "crouched steps at two meters remain quiet")
	footstep(origin + Vector3(0,0,0.6), true, false)
	check(actor._alert_target == player, "crouched steps can be heard almost at contact")
	reset_interest(); player._is_crouching = false; player.global_position = origin + Vector3(0,0,4)
	player._emit_movement_noise(Vector3.ZERO, true)
	check(actor._alert_target == null, "stationary player produces no footsteps")
	player._emit_movement_noise(Vector3(1.6,0,0), false)
	check(actor._alert_target == null, "airborne motion produces no footsteps")
	player._emit_movement_noise(Vector3(10,0,0), true)
	check(actor._alert_target == null, "teleport does not create a movement stimulus")
	for height in [-18.0,18.0]:
		reset_interest(); player.global_position = origin + Vector3(0,height,0)
		load("res://scripts/gameplay/gameplay_noise.gd").emit(player, 100.0)
		check(actor._alert_target == null and not actor._has_interest, "loud shots on another level do not attract monster %.0f" % height)
		actor.ai_profile.sight_enabled = true
		check(not actor._can_see(player), "sight cannot select another level %.0f" % height)
		actor.ai_profile.sight_enabled = false
	player.global_position = origin + Vector3(0,0,4)
	actor.hear_noise(player, player.global_position, 10.0)
	var last_heard: Vector3 = actor._last_seen
	player.global_position += Vector3(4,0,0)
	actor._find_target(0.2)
	check(actor._last_seen == last_heard, "unseen silent movement cannot update remembered sound position")
	player.global_position += Vector3(0,18,0)
	actor._victim = player; actor._windup = 0.2
	actor._update_behavior(0.2)
	check(actor._victim == null and actor._windup == 0.0, "changing levels cancels pending melee attack")
	check(actor._alert_target == null and actor._last_seen == last_heard and absf(actor._travel_goal.y-origin.y)<1.0, "leaving level drops live target and investigates only old local position")
	reset_interest(); player.global_position = origin + Vector3(0,0,10)
	var wall = load("res://tools/tests/fixtures/terminal_occluder.tscn").instantiate()
	root.add_child(wall); wall.global_position = origin + Vector3(0,1,5)
	await settle()
	actor.hear_noise(player,player.global_position,player.sprinting_noise_radius)
	check(not actor._has_interest, "wall attenuates distant running")
	actor.hear_noise(player,player.global_position,player.weapon.pistol_noise_radius)
	check(actor._has_interest, "louder gunshot penetrates same-level obstruction")
	wall.queue_free(); await settle()
	reset_interest(); actor._remember(actor.global_position, null, 10.0, false)
	actor._update_behavior(0.1); actor._update_behavior(0.1)
	check(actor.awareness_state == actor.AwarenessState.SEARCH, "reaching last known point starts local search")
	for second in 8: actor._update_behavior(1.0)
	check(not actor._has_interest, "fruitless search ends rather than tracking indefinitely")
	actor._returning_home = false; actor._patrol_goal = actor.global_position; actor._patrol_left = 0.0
	actor._update_behavior(0.1)
	check(actor.awareness_state == actor.AwarenessState.PATROL and actor._patrol_goal != actor.global_position, "idle actor selects a patrol destination")
	base.queue_free(); await process_frame
	print("MONSTER AWARENESS CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
