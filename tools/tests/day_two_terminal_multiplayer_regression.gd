extends Node
var host := false
var port := 28768
var failures := 0
var checks := 0
var world: Node
var state: BaseGameplayController
var hub: DayTwoTerminal
var vault: DayTwoTerminal
var client_id := 0
var reports: Dictionary = {}
func _ready() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
func _process(_delta: float) -> void:
	if world == null: return
	for player in world.players.get_children():
		player.set_physics_process(false)
		player.survival.set_physics_process(false)
func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()
func bind_terminals() -> void:
	state = world.get_node("V3Level/BaseGameplayController")
	hub = world.get_node("V3Level/Floor_0_Base_Blockout/DayTwoTaskTerminal")
	vault = world.get_node("V3Level/Floor_Minus1_Control_Security_Blockout/Secure_Data_Vault/Encryption_Key_Terminal")
func visit(player: GamePlayer, terminal: DayTwoTerminal) -> void:
	var facing := terminal.screen.global_basis.z
	facing.y = 0
	player.teleport_authoritative(terminal.global_position + facing.normalized() * 2, terminal.global_rotation.y)
	for frame in 4: await get_tree().physics_frame
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	if host: ExpeditionSaveStore.clear("coop")
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real ENet connection")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not host:
		check(await until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client connected")
		world._on_session_ready(false)
		check(await until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "late client loads authored terminals")
		bind_terminals()
		check(await until(func(): return state.quest_stage == BaseGameplayController.QuestStage.OFFERED), "late client can find key without a preliminary hub mission")
		check(vault.key_visual.visible and not vault.animation_player.is_playing(), "late client sees key without replaying extraction")
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		vault.network_interact(local.owner_peer_id, local)
		check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "client cannot mutate quest locally")
		var lighting := get_tree().get_first_node_in_group("world_lighting") as WorldLighting
		get_tree().root.get_node("DeveloperConsole").execute("/fullbright on")
		check(lighting.debug_darkness == 0.0, "guest can enable local fullbright without a host command")
		report.rpc_id(1, "initial", failures)
		return
	world._on_session_ready(true)
	world._enter_v3_level.rpc()
	check(await until(func(): return world._v3_items_spawned), "host loads real base")
	bind_terminals()
	var snapshot := state.get_snapshot()
	snapshot.day_index = 2
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20
	snapshot.quest_stage = BaseGameplayController.QuestStage.OFFERED
	state._broadcast_snapshot(snapshot)
	print("HOST_READY_FOR_TERMINAL_CLIENT")
	check(await until(func(): return reports.has("initial")), "late client confirms initial quest")
	check((get_tree().get_first_node_in_group("world_lighting") as WorldLighting).debug_darkness == 1.0, "guest debug light does not affect host visibility")
	if client_id == 0: get_tree().quit(1); return
	var client_actor: GamePlayer = world.players.get_node(str(client_id))
	await visit(client_actor, vault)
	check(client_actor.get_interaction_target() == vault, "host ray for guest targets vault terminal")
	client_actor.try_authoritative_interaction()
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "host confirms collection by guest")
	await get_tree().create_timer(0.5).timeout
	verify_phase.rpc_id(client_id, "collected")
	check(await until(func(): return reports.has("collected")), "guest receives key removal and updated UI")
	snapshot = state.get_snapshot()
	snapshot.main_breaker_on = false
	state._broadcast_snapshot(snapshot)
	verify_phase.rpc_id(client_id, "blackout")
	check(await until(func(): return reports.has("blackout")), "guest sees blackout on both devices")
	await visit(world.players.get_node("1"), hub)
	hub.network_interact(1, world.players.get_node("1"))
	check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED, "host delivery blocked during blackout")
	snapshot.main_breaker_on = true
	state._broadcast_snapshot(snapshot)
	world.players.get_node("1").try_authoritative_interaction()
	check(state.quest_stage == BaseGameplayController.QuestStage.DELIVERED, "host can deliver key collected by guest")
	await get_tree().create_timer(0.5).timeout
	verify_phase.rpc_id(client_id, "delivered")
	check(await until(func(): return reports.has("delivered")), "guest sees completed mission and hub key")
	finish.rpc_id(client_id, failures)
	await get_tree().create_timer(0.5).timeout
	print("TERMINAL COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
@rpc("authority", "call_remote", "reliable")
func verify_phase(phase: String) -> void:
	if phase == "collected":
		check(state.quest_stage == BaseGameplayController.QuestStage.COLLECTED and not vault.key_visual.visible, "collected key synchronized to guest")
		check(hub.ui.get_node("%Progress").text.contains("У КОМАНДЫ"), "guest screen shows shared key")
	elif phase == "blackout":
		check(not hub._screen_material.get_shader_parameter("powered") and not vault._screen_material.get_shader_parameter("powered"), "guest screens off on blackout")
		check(not hub._screen_material.get_shader_parameter("powered") and not vault._screen_material.get_shader_parameter("powered"), "guest screen shaders off on blackout")
	elif phase == "delivered":
		check(state.quest_stage == BaseGameplayController.QuestStage.DELIVERED and hub.key_visual.visible and not vault.key_visual.visible, "guest sees delivered key once")
		check(hub.ui.get_node("%Progress").text.contains("ПЕРЕДАН"), "guest UI reflects mission completion")
	report.rpc_id(1, phase, failures)
@rpc("any_peer", "call_remote", "reliable")
func report(phase: String, client_failures: int) -> void:
	if multiplayer.is_server():
		client_id = multiplayer.get_remote_sender_id()
		reports[phase] = client_failures
		if client_failures > 0: failures = client_failures
@rpc("authority", "call_remote", "reliable")
func finish(host_failures: int) -> void:
	check(host_failures == 0, "host and guest terminal route passed")
	print("TERMINAL COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
