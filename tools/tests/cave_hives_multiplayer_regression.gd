extends "res://tools/tests/expedition_multiplayer_regression.gd"
var encounter: Node3D
var guest_id := 0
var guest_checked := false

func seed_expedition() -> void:
	super.seed_expedition()
	var config: ConfigFile = ExpeditionSaveStore.read("coop").config
	config.set_value("base","day_index",7)
	config.set_value("base","containment",{})
	var inventory: Dictionary = config.get_value("inventory","checkpoint",{})
	inventory.players["test:guest"] = {"held_item": &"pistol", "weapon_rounds":12}
	config.set_value("inventory","checkpoint",inventory)
	check(ExpeditionSaveStore.write(config,"coop","sleep"),"seed isolated day-seven expedition")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	if host:
		ExpeditionSaveStore.clear("coop"); seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4)) == OK,"real hive ENet transport")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.uses_staging_lobby = true; world.staging_spawns_path = NodePath("ArrivalCabin/Spawns")
	world.resume_base_on_start = true
	get_tree().root.add_child(world); get_tree().current_scene = world
	if not host:
		check(await wait_until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED),"client connected")
		world._on_session_ready(false)
		check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2),"late client loads production cave")
		encounter = get_tree().get_first_node_in_group("cave_hive_encounters")
		check(await wait_until(func(): return encounter.state.get_destroyed_cave_hive_count() == 1),"late join restores first destroyed hive")
		check(encounter.get_health(1) == 85 and encounter.hives[0].collision_layer == 0,"late join restores partial health and native death pose")
		encounter.hives[1].apply_weapon_damage(10000)
		check(encounter.get_health(1) == 85,"direct client damage cannot mutate shared progress")
		hives_ready.rpc_id(1)
		return
	world._on_session_ready(true)
	check(await wait_until(func(): return world._v3_items_spawned),"host resumes production cave")
	encounter = get_tree().get_first_node_in_group("cave_hive_encounters")
	encounter.state.set_process(false)
	world.players.get_node("1").teleport_authoritative(Vector3(289,-155.25,-5),0)
	for frame in 8: await get_tree().physics_frame
	encounter.hives[0].apply_weapon_damage(10000)
	encounter.hives[1].apply_weapon_damage(35)
	print("HOST_READY_FOR_HIVES_CLIENT")
	check(await wait_until(func(): return guest_id > 0),"late guest acknowledges partial progress")
	if guest_id == 0: get_tree().quit(1); return
	var guest: GamePlayer = world.players.get_node(str(guest_id))
	var hive: Node3D = encounter.hives[1]
	guest.teleport_authoritative(hive.global_position + Vector3(0,0.05,-2.8),0)
	var offset := hive.global_position + Vector3.UP - guest.head.global_position
	guest.rotation.y = atan2(-offset.x,-offset.z)
	guest.head.rotation.x = atan2(offset.y,Vector2(offset.x,offset.z).length())
	guest.weapon._cooldown = 0
	for frame in 8: await get_tree().physics_frame
	shoot_hive.rpc_id(guest_id)
	check(await wait_until(func(): return encounter.get_health(1) == 50),"native client weapon RPC damages hive through host raycast")
	encounter.hives[1].apply_weapon_damage(10000)
	encounter.hives[2].apply_weapon_damage(10000)
	check(encounter.state.are_cave_hives_destroyed() and not encounter.state.can_end_current_day(),"shared destruction requires actual outdoor exit")
	check_hives.rpc_id(guest_id)
	check(await wait_until(func(): return guest_checked),"guest sees final shared count and exit task")
	var cave := encounter.get_parent()
	guest.teleport_authoritative(cave.get_node("ExitThreshold").global_position,0)
	check(await wait_until(func(): return encounter.state.containment.get("cave_exited",false)),"guest entering outdoor area completes authoritative route")
	check(encounter.state.load_saved_snapshot().containment.get("cave_exited",false),"host saves shared outdoor completion")
	finish_hives.rpc_id(guest_id,failures)
	await get_tree().create_timer(0.4).timeout
	print("HIVES COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)

@rpc("any_peer","call_remote","reliable")
func hives_ready() -> void:
	if host: guest_id = multiplayer.get_remote_sender_id()

@rpc("authority","call_remote","reliable")
func shoot_hive() -> void:
	var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
	check(local.weapon.kind == &"pistol","client holds saved pistol")
	local.weapon.request_action(&"fire")

@rpc("authority","call_remote","reliable")
func check_hives() -> void:
	check(await wait_until(func(): return encounter.state.are_cave_hives_destroyed()),"client receives all three destruction states")
	var journal := get_tree().root.get_node("QuestJournal")
	check("Выйти наружу" in str(journal.get_hud_summary().tasks),"client HUD receives exit objective")
	hives_checked.rpc_id(1,failures)

@rpc("any_peer","call_remote","reliable")
func hives_checked(client_failures: int) -> void:
	if host:
		failures += client_failures; guest_checked = true

@rpc("authority","call_remote","reliable")
func finish_hives(host_failures: int) -> void:
	check(await wait_until(func(): return encounter.state.containment.get("cave_exited",false)),"client receives outdoor completion")
	check(host_failures == 0,"host hive validation passed")
	print("HIVES COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)
