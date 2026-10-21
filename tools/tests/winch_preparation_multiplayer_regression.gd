extends "res://tools/tests/winch_multiplayer_regression.gd"
var preparation: WinchPreparationController
var client_input := false
var input_sequence := 100000
var interaction_serial := 50000

func _process(_delta: float) -> void:
	if world == null: return
	for actor in world.players.get_children():
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		if host and actor.owner_peer_id != 1: actor.simulate_authoritative_movement(0.0)
	if client_input and not host:
		var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
		input_sequence += 1
		local._submit_input.rpc_id(1,input_sequence,Vector2.ZERO,false,false,0,0,interaction_serial,0,local.rotation.y,local.head.rotation.x)

func seed_expedition() -> void:
	super.seed_expedition()
	var config: ConfigFile = ExpeditionSaveStore.read("coop").config
	config.set_value("base","day_index",6)
	config.set_value("base","maintenance",{"elevator_floor":5,"winch_floor":0,"winch_preparation":{}})
	check(ExpeditionSaveStore.write(config,"coop","sleep"),"seed unprepared day-six expedition")

func visit(actor: GamePlayer, control: WinchPreparationControl) -> void:
	var point := control.global_position + control.global_basis.z * 1.4
	point.y = -89.9
	actor.teleport_authoritative(point,0)
	var offset := control.interaction_point.global_position - actor.camera.global_position
	actor.rotation.y = atan2(-offset.x,-offset.z)
	actor.head.rotation.x = atan2(offset.y,Vector2(offset.x,offset.z).length())
	for frame in 6: await get_tree().physics_frame

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope = "coop"
	if host:
		ExpeditionSaveStore.clear("coop"); seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4)) == OK,"real preparation ENet transport")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.uses_staging_lobby = true
	world.staging_spawns_path = NodePath("ArrivalCabin/Spawns")
	world.resume_base_on_start = true
	get_tree().root.add_child(world); get_tree().current_scene = world
	if not host:
		check(await wait_until(func(): return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED),"client connected")
		world._on_session_ready(false)
		check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count() == 2),"client loads production preparation scene")
		preparation = get_tree().get_first_node_in_group("winch_preparations")
		check(await wait_until(func(): return preparation.gameplay_state.get_winch_preparation().get("pin_removed",false)),"late join receives partial mechanical progress")
		check(not preparation.pin_animation.is_playing() and preparation.get_node("BrakeAssembly/PinRoot").position.y < -0.4,"late join restores removed pin without replay")
		check(not preparation.winch.is_powered and not preparation.gameplay_state.can_end_current_day(),"partial progress cannot unlock descent or sleep")
		preparation_ready.rpc_id(1)
		return
	world._on_session_ready(true)
	check(await wait_until(func(): return world._v3_items_spawned),"host resumes production day-six base")
	preparation = get_tree().get_first_node_in_group("winch_preparations")
	var state: BaseGameplayController = world._base_gameplay_controller
	state.set_process(false)
	var local: GamePlayer = world.players.get_node("1")
	await visit(local,preparation.get_node("Console")); local.try_authoritative_interaction()
	await visit(local,preparation.get_node("BrakeAssembly/PinControl")); local.try_authoritative_interaction()
	await get_tree().create_timer(1.0).timeout
	check(state.get_winch_preparation().get("pin_removed",false),"host inspects console and removes pin using production interaction")
	print("HOST_READY_FOR_PREPARATION_CLIENT")
	check(await wait_until(func(): return guest_id > 0),"late guest acknowledges partial preparation")
	if guest_id == 0: get_tree().quit(1); return
	var guest: GamePlayer = world.players.get_node(str(guest_id))
	await visit(guest,preparation.get_node("BrakeAssembly/BrakeControl"))
	arm_from_client.rpc_id(guest_id)
	check(await wait_until(func(): return state.get_winch_preparation().get("brake_armed",false)),"client input arms shared reserve brake")
	await get_tree().create_timer(0.9).timeout
	await visit(local,preparation.get_node("Console")); local.try_authoritative_interaction()
	check(state.get_winch_preparation().get("testing",false),"host starts shared timed brake test")
	check(await wait_until(func(): return state.is_winch_prepared()),"host finishes test once")
	check(state.can_end_current_day(),"prepared team can end day six")
	check(state.save_progress_authoritative(false,"manual") and state.load_saved_snapshot().maintenance.winch_preparation.tested,"host persists preparation completed across peers")
	preparation_status.rpc_id(guest_id)
	check(await wait_until(func(): return reports.has("prepared")),"guest sees final state and native poses")
	for actor in world.players.get_children():
		state.set_end_day_ready_authoritative(actor.owner_peer_id,true)
		state.set_peer_sleeping_authoritative(actor.owner_peer_id,true)
	check(state.advance_day_authoritative(),"normal team consensus advances preparation day")
	check(state.day_index == 7 and preparation.winch.is_powered,"shared preparation opens next-day descent")
	finish_preparation.rpc_id(guest_id,failures)
	await get_tree().create_timer(0.4).timeout
	print("PREPARATION COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)

@rpc("any_peer","call_remote","reliable")
func preparation_ready() -> void:
	if host: guest_id = multiplayer.get_remote_sender_id()

@rpc("authority","call_remote","reliable")
func arm_from_client() -> void:
	var local: GamePlayer = get_tree().get_first_node_in_group("local_player")
	var control: WinchPreparationControl = preparation.get_node("BrakeAssembly/BrakeControl")
	for frame in 6: await get_tree().physics_frame
	var offset := control.interaction_point.global_position - local.camera.global_position
	local.rotation.y = atan2(-offset.x,-offset.z)
	local.head.rotation.x = atan2(offset.y,Vector2(offset.x,offset.z).length())
	check(local.get_interaction_target() == control,"client aims at physical brake lever")
	client_input = true

@rpc("authority","call_remote","reliable")
func preparation_status() -> void:
	check(await wait_until(func(): return preparation.gameplay_state.is_winch_prepared()),"guest receives successful test")
	check(preparation.gameplay_state.can_end_current_day() and preparation.get_node("Console/StatusGreen").visible,"guest journal and indicator share completion")
	check(preparation.get_node("BrakeAssembly/LeverPivot").rotation.z > 0.5,"guest sees armed lever pose")
	preparation_checked.rpc_id(1,failures)

@rpc("any_peer","call_remote","reliable")
func preparation_checked(client_failures: int) -> void:
	if host:
		failures += client_failures
		reports["prepared"] = true

@rpc("authority","call_remote","reliable")
func finish_preparation(host_failures: int) -> void:
	check(host_failures == 0,"host preparation validation passed")
	print("PREPARATION COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)
