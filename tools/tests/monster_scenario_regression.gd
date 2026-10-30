extends SceneTree
## Existing creatures and a real player: scenario hooks, stealth, fair attacks and persistent outcomes.
var failures := 0
var checks := 0
var origin := Vector3(1000, 500, 1000)


func _initialize() -> void:
	var isolated := "user://monster_scenarios_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(isolated))
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, isolated + "/slots")
	ProjectSettings.set_setting(
		BaseGameplayController.TEST_SAVE_PATH_SETTING, isolated + "/campaign.cfg"
	)
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths", {})
	ProjectSettings.set_setting("northern_lab/testing/settings_path", isolated + "/settings.json")
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)


func frames(count := 3) -> void:
	for frame in count:
		await physics_frame


func clear_actor(actor) -> void:
	actor.reset_enemy()
	actor.global_position = origin
	actor.rotation = Vector3.ZERO
	actor.set_home_transform(actor.global_transform)
	actor._forget_interest()
	actor._returning_home = false
	actor._sight_left = 0.0
	actor._recovery_left = 0.0
	actor._stun_left = 0.0


func run() -> void:
	var base = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await frames(6)
	root.get_node("GameMenu").force_close_menu()
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	state.progress_persistence_enabled = false
	state.debug_set_day_authoritative(5)
	var encounter = base.get_node("ContainmentEncounter")
	encounter.debug_reset()
	for old in get_nodes_in_group("hostile_monsters"):
		old.set_physics_process(false)
	var player: GamePlayer = get_first_node_in_group("local_player")
	player.set_physics_process(false)
	player.survival.set_physics_process(false)
	player.survival.debug_invincible = false
	player.survival.dead = false
	player.survival.health = 100.0
	player.global_position = origin + Vector3(0, 0, -4)
	var actor = load("res://scenes/characters/monsters/slasher.tscn").instantiate()
	actor.ai_profile = actor.ai_profile.duplicate()
	base.add_child(actor)
	actor.set_physics_process(false)
	clear_actor(actor)
	await frames()
	check(
		actor.encounter == null and actor.health == 160.0,
		"ordinary prefab operates without story encounter or debug-spawn flag"
	)
	actor.ai_profile.sight_confirmation_time = 0.4
	for sample in 3:
		actor._find_target(0.15)
	check(
		not actor._sees_target and actor._candidate_exposure > 0.0,
		"brief exposure accumulates suspicion without immediate identification"
	)
	actor._find_target(0.15)
	check(
		actor._sees_target and actor._alert_target == player, "continuous exposure confirms player"
	)
	actor.ai_profile.sight_confirmation_time = 0.0
	clear_actor(actor)
	player.global_position = origin + Vector3(0, 0, -1.2)
	actor._update_behavior(0.01)
	check(
		actor._windup > 0.0 and Vector2(actor.velocity.x, actor.velocity.z).is_zero_approx(),
		"windup stops movement on the same frame"
	)
	var attack_results: Array = []
	actor.attack_finished.connect(func(_target, hit): attack_results.append(hit))
	check(actor.stun(0.4), "scenario stun accepted by host")
	actor._update_behavior(0.7)
	check(
		actor._windup == 0.0 and player.survival.health == 100.0 and attack_results == [false],
		"stun cancels pending hit exactly once"
	)
	clear_actor(actor)
	actor._update_behavior(0.01)
	player.global_position = origin + Vector3(0, 0, 1.2)
	actor._update_behavior(1.0)
	check(
		player.survival.health == 100.0,
		"committed strike misses a player who circles behind the creature"
	)
	clear_actor(actor)
	player.global_position = origin + Vector3(0, 0, -1.2)
	actor.ai_profile.attacks_enabled = false
	actor._update_behavior(0.1)
	check(
		actor._has_interest and actor._windup == 0.0,
		"attack-disabled creature still perceives and pursues"
	)
	actor.set_ai_enabled(false)
	actor._update_behavior(0.1)
	check(
		actor.awareness_state == actor.AwarenessState.DORMANT and actor.velocity.x == 0.0,
		"scenario can pause AI without killing creature"
	)
	actor.set_ai_enabled(true)
	actor.ai_profile.weapon_damage_enabled = false
	actor.apply_weapon_damage(30.0)
	check(actor.health == 160.0, "weapon immunity is independent from environmental vulnerability")
	actor.apply_environment_damage(20.0)
	check(actor.health == 140.0, "environmental hazard damages standalone creature without weapon")
	actor.ai_profile.environment_damage_enabled = false
	actor.apply_environment_damage(100.0)
	check(actor.health == 140.0, "environmental immunity is independently configurable")
	clear_actor(actor)
	actor.ai_profile.sight_enabled = false
	var noise := Node3D.new()
	base.add_child(noise)
	noise.global_position = origin + Vector3(100, 0, 0)
	var impact := origin + Vector3(0, 0, -3)
	load("res://scripts/gameplay/gameplay_noise.gd").emit_at(noise, impact, 10.0)
	check(
		actor._has_interest and actor._last_seen == impact and actor._alert_target == null,
		"impact noise investigates event position, not remote source transform"
	)
	actor._start_search(origin)
	var remaining: float = actor._search_left
	actor.ai_profile.maximum_path_retries = 1
	actor._search_goal = origin + Vector3(0, 0, -3)
	actor._travel_goal = actor._search_goal
	actor._travel_stop = 0.2
	actor._wants_move = true
	actor._progress_origin = origin
	actor.awareness_state = actor.AwarenessState.SEARCH
	actor._update_blocked(actor.ai_profile.stuck_timeout + 0.1, origin)
	check(
		actor._search_left <= remaining, "blocked search does not restart and extend its lifetime"
	)
	actor._forget_interest()
	check(
		actor.move_to_position(origin + Vector3(0, 0, -5), 2.0),
		"scenario can author a destination independently from players"
	)
	actor._update_behavior(0.1)
	check(
		actor.awareness_state == actor.AwarenessState.SCRIPTED_MOVE and actor.velocity.z < 0.0,
		"scripted move uses existing movement path"
	)
	check(
		actor.cancel_scripted_movement() and not actor._scripted_goal.is_finite(),
		"scenario movement can be cancelled"
	)
	var marker1 := Marker3D.new()
	var marker2 := Marker3D.new()
	base.add_child(marker1)
	base.add_child(marker2)
	marker1.global_position = origin + Vector3(2, 0, 0)
	marker2.global_position = origin + Vector3(-2, 0, 0)
	actor._patrol_markers.assign([marker1, marker2])
	actor._patrol_index = -1
	actor.patrol_ping_pong = true
	check(
		(
			actor._next_patrol_goal() == marker1.global_position
			and actor._next_patrol_goal() == marker2.global_position
			and actor._next_patrol_goal() == marker1.global_position
		),
		"authored patrol markers support ping-pong route"
	)
	actor.ragdoll_scene = null
	actor.ai_profile.environment_damage_enabled = true
	actor.apply_environment_damage(1000.0)
	actor._physics_process(0.1)
	actor._physics_process(0.1)
	check(
		actor.health == 0.0 and actor._corpse_attempted and actor.ragdoll == null,
		"replacement model without a matching ragdoll has safe single-attempt static fallback"
	)
	actor.queue_free()
	noise.queue_free()
	var ground := StaticBody3D.new()
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(14, 1, 14)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	base.add_child(ground)
	ground.global_position = origin - Vector3(0, .5, 0)
	var crowd: Array = []
	for index in 2:
		var runner = load("res://scenes/characters/monsters/head.tscn").instantiate()
		runner.ai_profile = runner.ai_profile.duplicate()
		runner.ai_profile.sight_enabled = false
		runner.ai_profile.hearing_enabled = false
		runner.collision_mask = 1
		base.add_child(runner)
		runner.set_physics_process(false)
		runner.global_position = origin + Vector3(-2.0 if index == 0 else 2.0, .1, 0)
		runner.move_to_position(origin + Vector3(2.0 if index == 0 else -2.0, .1, 0), 1.8)
		crowd.append(runner)
	await frames()
	check(
		crowd[0].agent.avoidance_enabled and crowd[1].agent.avoidance_enabled,
		"head uses native server-side crowd avoidance"
	)
	var closest := 4.0
	for frame in 180:
		for runner in crowd:
			runner._physics_process(1.0 / 60.0)
		closest = minf(closest, crowd[0].global_position.distance_to(crowd[1].global_position))
		await physics_frame
	check(
		closest > .48,
		(
			"native RVO prevents intersecting runners without character collision (minimum %.2f)"
			% closest
		)
	)
	check(
		crowd[0].global_position.distance_to(origin + Vector3(-2, .1, 0)) > .5,
		"fast head physically moves under its AI rather than only animating in place"
	)
	crowd[1].set_ai_enabled(false)
	crowd[1].global_position = origin + Vector3(0, .1, 5)
	crowd[0].global_position = origin + Vector3(-6, .1, -3)
	crowd[0].velocity = Vector3.ZERO
	crowd[0].move_to_position(origin + Vector3(6, .1, -3))
	var peak_speed := 0.0
	for frame in 90:
		crowd[0]._physics_process(1.0 / 60.0)
		peak_speed = maxf(peak_speed, Vector2(crowd[0].velocity.x, crowd[0].velocity.z).length())
		await physics_frame
	check(
		peak_speed > 4.8 and crowd[0].global_position.x > origin.x - 1.0,
		"head accelerates to its configured fast running speed (%.2f m/s)" % peak_speed
	)
	for runner in crowd:
		runner.queue_free()
	crowd.clear()
	ground.queue_free()
	await frames()
	var first = encounter.get_node("Monster0")
	var second = encounter.get_node("Monster1")
	var third = encounter.get_node("Monster2")
	first.global_position += Vector3(1.5, 0, 0)
	var trapped_position: Vector3 = first.global_position
	check(
		first.resolve_without_kill("trapped", false),
		"story creature supports visible nonlethal resolution"
	)
	check(
		(
			first.health > 0.0
			and first.visible
			and first.collision_layer == 0
			and not first.is_in_group("hostile_monsters")
		),
		"trapped creature remains visible but cannot threaten or trigger proximity AI"
	)
	check(second.resolve_without_kill("escaped"), "story creature can leave without death")
	check(
		not second.visible and second.health > 0.0 and not second.resolve_without_kill("again"),
		"resolution is idempotent and preserves health"
	)
	check(
		not state.containment.get("fault", false),
		"partial nonlethal completion does not finish encounter"
	)
	third.apply_environment_damage(1000.0)
	third._physics_process(0.01)
	check(
		encounter.get_monster_health(2) == 0.0 and state.containment.get("fault", false),
		"mixed nonlethal and environmental defeat completes original encounter rule"
	)
	state.progress_persistence_enabled = true
	check(
		state.save_progress_authoritative(false, "start"),
		"new outcome data writes through existing save store"
	)
	var loaded := state.load_saved_snapshot()
	check(
		(
			loaded.get("containment", {}).get("monster_outcomes", {}).get("0", {}).get("reason", "")
			== "trapped"
		),
		"nonlethal outcome survives disk roundtrip"
	)
	encounter.debug_reset()
	check(
		(
			not first.is_encounter_resolved()
			and first.is_in_group("hostile_monsters")
			and first.visible
		),
		"reset restores resolved creature and active group"
	)
	if not loaded.is_empty():
		state._broadcast_snapshot(loaded)
	check(
		first.is_encounter_resolved() and not second.visible and first.health > 0.0,
		"snapshot restores scenario outcome without converting it into death"
	)
	check(
		first.global_position.is_equal_approx(trapped_position),
		"visible resolved actor restores its final position rather than spawn marker"
	)
	state.progress_persistence_enabled = false
	var repair := state.get_snapshot()
	repair.containment.reset_armed = true
	state._broadcast_snapshot(repair)
	encounter.get_node("Monster3").apply_environment_damage(1.0)
	check(state.containment.get("reset_armed", false), "patrol damage cannot disarm the original encounter breaker repair")
	encounter.get_node("Monster4").resolve_without_kill("withdrawn")
	check(state.containment.get("reset_armed", false), "patrol resolution cannot restart the original encounter power fault")
	base.queue_free()
	await frames(4)
	print("MONSTER SCENARIO CHECKS ", checks, " FAILURES ", failures)
	quit(1 if failures else 0)
