extends Node

var host := false
var port := 28771
var checks := 0
var failures := 0
var world: Node
var state: BaseGameplayController
var button: PlantWateringButton
var client_id := 0
var reports := {}
var cycles := 0
var input_active := false
var sequence := 100000
var serial := 90000

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
	if input_active and not host:
		var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
		sequence += 1
		local._submit_input.rpc_id(1, sequence, Vector2.ZERO, false, false, 0, 0, serial, 0, local.rotation.y, local.head.rotation.x)

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return predicate.call()

func bind() -> void:
	state = world.get_node("V3Level/BaseGameplayController")
	state.set_process(false)
	button = get_tree().get_first_node_in_group("plant_watering_button")
	button.animation.animation_started.connect(func(name: StringName):
		if name == &"water": cycles += 1)
	get_tree().root.get_node("GameMenu").force_close_menu()

func aim(player: GamePlayer) -> void:
	player.rotation.y = 0
	player.head.rotation.x = 0
	player.camera.rotation = Vector3.ZERO
	var delta := button.interaction_point.global_position - player.camera.global_position
	player.head.rotation.x = atan2(delta.y, -delta.z)

func visit(player: GamePlayer) -> void:
	player.teleport_authoritative(Vector3(button.global_position.x, 0.04, button.global_position.z + 1.05), 0)
	aim(player)
	for frame in 6: await get_tree().physics_frame

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING, arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	if host: ExpeditionSaveStore.clear("coop")
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port, 1, 4) if host else peer.create_client("127.0.0.1", port, 4)) == OK, "real ENet peer")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	if not host:
		check(await until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED), "client connected")
		world._on_session_ready(false)
		check(await until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2), "late client enters production base")
		bind()
		check(await until(func(): return state.plant_last_watered_day == 1), "late client receives host daily watering state")
		for frame in 6: await get_tree().physics_frame
		check(cycles == 0 and not button.get_parent().get_node("SprayLeft").emitting, "late join does not replay historical water")
		check(not state.water_plant_authoritative(multiplayer.get_unique_id()), "client cannot mutate plant state locally")
		check(ExpeditionSaveStore.read("coop").is_empty(), "client does not write a separate expedition save")
		report.rpc_id(1, "initial", failures)
		return
	world._on_session_ready(true)
	world._enter_v3_level.rpc()
	check(await until(func(): return world._v3_items_spawned), "host loads production base")
	bind()
	var snapshot := state.get_snapshot()
	snapshot.day_index = 1
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 20
	snapshot.maintenance = {}
	state._broadcast_snapshot(snapshot)
	var local := world.players.get_node("1") as GamePlayer
	await visit(local)
	check(local.get_interaction_target() == button, "host physical E ray reaches watering control")
	local.try_authoritative_interaction()
	check(state.plant_last_watered_day == 1, "host waters before late join")
	print("HOST_READY_FOR_PLANT_CLIENT")
	check(await until(func(): return reports.has("initial")), "late client confirms daily state")
	if client_id == 0: get_tree().quit(1); return
	var guest := world.players.get_node(str(client_id)) as GamePlayer
	snapshot = state.get_snapshot()
	snapshot.day_index = 2
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.maintenance = {}
	state._broadcast_snapshot(snapshot)
	await visit(local)
	await visit(guest)
	command.rpc_id(client_id, "water")
	check(await until(func(): return guest._server_interact_serial == serial), "guest sends production E input")
	var cycles_before := cycles
	guest.simulate_authoritative_movement(0.0)
	check(state.plant_last_watered_day == 2, "host confirms guest watering on next day")
	local.try_authoritative_interaction()
	check(not state.water_plant_authoritative(1), "simultaneous host attempt cannot water a second time")
	for frame in 6: await get_tree().physics_frame
	check(cycles == cycles_before + 1, "host presents one confirmed watering cycle")
	command.rpc_id(client_id, "confirmed")
	check(await until(func(): return reports.has("confirmed")), "guest sees synchronized presentation and daily limit")
	serial += 1
	command.rpc_id(client_id, "repeat")
	check(await until(func(): return guest._server_interact_serial == serial), "guest repeats production E input")
	guest.simulate_authoritative_movement(0.0)
	check(state.plant_last_watered_day == 2 and cycles == cycles_before + 1, "repeated guest input cannot restart shared cycle")
	var saved: ConfigFile = ExpeditionSaveStore.read("coop").config
	check(int(saved.get_value("base", "plant_last_watered_day", 0)) == 2, "host save includes guest daily watering")
	finish.rpc_id(client_id, failures)
	await get_tree().create_timer(0.5).timeout
	print("PLANT COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)

@rpc("authority", "call_remote", "reliable")
func command(action: String) -> void:
	var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if action == "water":
		check(await until(func(): return state.day_index == 2 and state.main_breaker_on), "client receives new available day")
		aim(local)
		for frame in 6: await get_tree().physics_frame
		check(local.get_interaction_target() == button, "client ray reaches original button")
		input_active = true
	elif action == "confirmed":
		check(await until(func(): return state.plant_last_watered_day == 2), "guest receives confirmed use")
		check(cycles == 1 and button.animation.current_animation == &"water", "guest plays one native animation")
		check(button.get_interaction_hint_for(local) == "Сегодня уже полито", "guest shares host daily guard")
	elif action == "repeat":
		serial += 1
	report.rpc_id(1, action, failures)

@rpc("any_peer", "call_remote", "reliable")
func report(action: String, client_failures: int) -> void:
	if not multiplayer.is_server(): return
	client_id = multiplayer.get_remote_sender_id()
	reports[action] = client_failures
	if client_failures: failures += client_failures

@rpc("authority", "call_remote", "reliable")
func finish(host_failures: int) -> void:
	check(host_failures == 0, "host watering checks passed")
	print("PLANT COOP CHECKS ", checks, " FAILURES ", failures)
	get_tree().quit(1 if failures else 0)
