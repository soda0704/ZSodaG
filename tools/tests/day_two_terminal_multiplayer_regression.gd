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
	check(state.quest_stage == BaseGameplayController.QuestStage.OFFERED, "guest cannot bypass hold through interaction packet")
	vault._open_session(client_id)
	vault._command(client_id, 1, &"quest_begin")
	await get_tree().create_timer(1.4).timeout
	vault._command(client_id, 2, &"quest")
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
	# Host-authoritative gate and sleep rules with two real ENet players.
	var level: Node = world.get_node("V3Level")
	var gate: Node
	for candidate in level.find_children("*", "Node3D", true, false):
		if candidate.get_script() != null and candidate.get_script().resource_path.ends_with("garage_gate.gd"):
			gate = candidate
			break
	check(gate != null and gate.required_operators() == 2, "real coop gate requires both players")
	gate.set_physics_process(false)
	gate.opening_seconds = 0.2
	var host_actor: GamePlayer = world.players.get_node("1")
	host_actor.teleport_authoritative(gate.handles[0].global_position + gate.global_basis.z, 0)
	client_actor.teleport_authoritative(gate.handles[1].global_position + gate.global_basis.z, 0)
	for frame in 8: await get_tree().physics_frame
	for i in 3:
		gate._hold(1, 0)
		gate._physics_process(0.1)
	check(gate.progress == 0.0, "one coop player cannot open gate alone")
	for i in 3:
		gate._hold(1, 0)
		gate._hold(client_id, 1)
		gate._physics_process(0.1)
	check(gate.progress == 1.0, "two distinct handles open coop gate")
	gate.animation.advance(4.1)
	for frame in 8: await get_tree().physics_frame
	gate._holds.clear()
	gate._physics_process(0.4)
	for i in 3:
		gate._hold(1, 0)
		gate._hold(client_id, 1)
		gate._physics_process(0.1)
	check(gate.progress == 0.0, "two players can close open coop gate")
	var bunk: BaseEndDayBunk = level.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	host_actor.teleport_authoritative(bunk.wake_pose.global_position, 0)
	bunk.network_interact(1, host_actor)
	check(state.is_peer_sleeping(1) and not state.are_all_connected_players_sleeping(), "coop sleeper waits for actual connected partner")
	check(bunk.cancel_sleep_authoritative(1, host_actor) and not state.is_peer_sleeping(1), "coop sleeper can get up before partner lies down")
	host_actor.survival.restore_checkpoint_authoritative({"health":43.0,"radiation":17.0})
	client_actor.survival.restore_checkpoint_authoritative({"health":61.0,"radiation":32.0})
	bunk.network_interact(1,host_actor)
	await get_tree().create_timer(.7).timeout
	check(state.day_index==2 and host_actor.survival.health==43,"one sleeping peer cannot start recovery before the partner")
	var guest_bunk: BaseEndDayBunk = level.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable02")
	client_actor.teleport_authoritative(guest_bunk.wake_pose.global_position,0)
	guest_bunk.network_interact(client_id,client_actor)
	await get_tree().create_timer(.7).timeout
	verify_phase.rpc_id(client_id,"sleeping")
	check(await until(func(): return reports.has("sleeping")),"guest closes only its local eyes during shared sleep")
	check(await until(func(): return state.day_index==3),"five-second shared night advances the day once")
	check(host_actor.survival.health==host_actor.survival.max_health and client_actor.survival.health==client_actor.survival.max_health and is_zero_approx(host_actor.survival.radiation) and is_zero_approx(client_actor.survival.radiation),"host restores both peers' HP and clears both radiation doses")
	await get_tree().create_timer(.7).timeout
	verify_phase.rpc_id(client_id,"morning")
	check(await until(func(): return reports.has("morning")),"guest receives morning recovery and opens its eyes")
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
	elif phase in ["sleeping","morning"]:
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		var eyes := local.get_node("PlayerUI/SleepEyelids")
		if phase=="sleeping":
			check(local.is_sleeping_in_bunk() and eyes.visible and is_zero_approx(float(eyes.get_node("Cover").material.get_shader_parameter("openness"))),"guest receives bunk state and fully closed eyelids")
			check(not world.players.get_node("1/PlayerUI/SleepEyelids").visible,"remote sleeper never covers the guest's screen")
		else:
			check(not local.is_sleeping_in_bunk() and not eyes.visible and local.survival.health==local.survival.max_health and is_zero_approx(local.survival.radiation),"guest receives healed morning state and clear screen")
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
