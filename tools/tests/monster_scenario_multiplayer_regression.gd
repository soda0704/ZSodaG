extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Real production session: late-join nonlethal outcome, new prefab RPCs and authority guards.
var acknowledged := 0


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			host = true
		elif arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="):
			ProjectSettings.set_setting(
				ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root=")
			)
	var isolated := str(ProjectSettings.get_setting(ExpeditionSaveStore.ROOT_SETTING))
	ProjectSettings.set_setting("northern_lab/testing/settings_path", isolated + "/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path", isolated + "/controls.cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING, isolated + "/journal")
	BaseGameplayController.save_scope = "coop"
	if host:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check(
		(
			(peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4))
			== OK
		),
		"create real ENet transport"
	)
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.resume_base_on_start = true
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if host:
		world._on_session_ready(true)
		check(
			await wait_until(
				func(): return world._v3_items_spawned and not world._v3_transition_in_progress
			),
			"host loads production world"
		)
		var encounter = world._base_gameplay_controller.get_parent().get_node(
			"ContainmentEncounter"
		)
		check(
			encounter.get_node("Monster0").resolve_without_kill("escaped"),
			"host resolves creature before guest joins"
		)
		print("HOST_READY_FOR_MONSTER_CLIENT")
		check(
			await wait_until(func(): return acknowledged >= 1),
			"late guest receives scenario outcome"
		)
		encounter.debug_spawn(3, 1, Vector3(1, 1, 2), Vector3.FORWARD, true)
		encounter.debug_spawn(4, 1, Vector3(-2, 1, 2), Vector3.FORWARD, true)
		check(
			await wait_until(func(): return acknowledged >= 2),
			"both new prefabs instantiated on guest"
		)
		var head = encounter.get_node("DebugMonster0")
		check(head.set_ai_enabled(false), "host pauses new head")
		head.apply_environment_damage(10.0)
		check(
			await wait_until(func(): return acknowledged >= 3),
			"guest receives enabled state and environmental health"
		)
		check(
			head.health == 75.0 and not head.ai_enabled,
			"guest cannot mutate authoritative health or AI state"
		)
		head.resolve_without_kill("withdrawn")
		check(
			await wait_until(func(): return acknowledged >= 4),
			"guest receives standalone scripted withdrawal"
		)
		encounter.debug_clear_spawned()
		check(
			await wait_until(func(): return acknowledged >= 5),
			"guest removes new actors and their visuals"
		)
		finish_monsters.rpc()
		await get_tree().create_timer(.3).timeout
		finish_monsters()
	else:
		check(
			await wait_until(
				func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
			),
			"guest connects"
		)
		world._on_session_ready(false)
		check(
			await wait_until(
				func(): return world._entered_v3_level and not world._v3_transition_in_progress
			),
			"guest loads real resumed world"
		)
		var encounter = world._base_gameplay_controller.get_parent().get_node(
			"ContainmentEncounter"
		)
		check(
			(
				encounter.get_node("Monster0").is_encounter_resolved()
				and not encounter.get_node("Monster0").visible
			),
			"late join restores nonlethal resolution"
		)
		ack_monsters.rpc_id(1, 1)
		check(
			await wait_until(
				func():
					return (
						encounter.has_node("DebugMonster0") and encounter.has_node("DebugMonster1")
					)
			),
			"guest receives head and evolution spawn RPCs"
		)
		if not encounter.has_node("DebugMonster0"):
			get_tree().quit(1)
			return
		var head = encounter.get_node("DebugMonster0")
		check(
			(
				head.visual.skeleton != null
				and encounter.get_node("DebugMonster1").visual.skeleton != null
			),
			"guest uses skinned versions of both models"
		)
		ack_monsters.rpc_id(1, 2)
		check(
			await wait_until(func(): return not head.ai_enabled and head.health == 75.0),
			"guest gets host AI toggle and hazard damage"
		)
		head.apply_environment_damage(30.0)
		check(
			(
				not head.set_ai_enabled(true)
				and not head.resolve_without_kill("spoofed")
				and head.health == 75.0
			),
			"client scenario APIs cannot take authority"
		)
		ack_monsters.rpc_id(1, 3)
		check(
			await wait_until(func(): return head.is_encounter_resolved() and not head.visible),
			"guest observes reliable nonlethal withdrawal"
		)
		ack_monsters.rpc_id(1, 4)
		check(
			await wait_until(
				func():
					return (
						not encounter.has_node("DebugMonster0")
						and not encounter.has_node("DebugMonster1")
					)
			),
			"guest cleanup completes"
		)
		ack_monsters.rpc_id(1, 5)


@rpc("any_peer", "call_remote", "reliable")
func ack_monsters(phase: int) -> void:
	if multiplayer.is_server():
		acknowledged = maxi(acknowledged, phase)


@rpc("authority", "call_remote", "reliable")
func finish_monsters() -> void:
	print("MONSTER COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
