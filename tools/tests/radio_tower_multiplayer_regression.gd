extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Actual shared story state, keypad RPC and climbing snapshots over local ENet.
var acknowledged := 0
var heard: Array[StringName] = []

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,arg.trim_prefix("--save-root="))
	var isolated := str(ProjectSettings.get_setting(ExpeditionSaveStore.ROOT_SETTING))
	ProjectSettings.set_setting("northern_lab/testing/settings_path",isolated+"/settings.json")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	BaseGameplayController.save_scope = "coop"
	if host:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4)) == OK,"real ENet audio transport")
	multiplayer.multiplayer_peer = peer
	world = load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.resume_base_on_start = true
	get_tree().root.add_child(world); get_tree().current_scene = world

	if host:
		world._on_session_ready(true)
		check(await wait_until(func(): return world._v3_items_spawned and not world._v3_transition_in_progress),"host loads production tower")
		print("HOST_READY_FOR_RADIO_CLIENT")
		check(await wait_until(func():return acknowledged>=1),"late guest receives the same campaign code")
		var peer_id: int=multiplayer.get_peers()[0]
		var player: GamePlayer=world._base_gameplay_controller.get_player_node(peer_id)
		var level=world._base_gameplay_controller.get_parent()
		var tower=level.get_node("SnowExterior/RadioTower")
		player.teleport_authoritative(tower.get_node("Keypad").global_position+Vector3(-1.2,-1.3,0))
		check(await wait_until(func():return acknowledged>=2),"guest opens original gate using authenticated keypad RPC")
		var route=tower.get_node("Ladder")
		player.teleport_authoritative(route.bottom_exit.global_position)
		await get_tree().create_timer(.15).timeout
		player.get_node("LadderClimb").enter(route)
		player.send_snapshot_if_due(1.)
		var checkpoint: Dictionary=world.capture_inventory_checkpoint()
		var safe: Transform3D=checkpoint.participants[world._inventory_id(peer_id)].transform
		check(safe.origin.distance_to(route.bottom_exit.global_position)<.1,"checkpoint during climbing uses a safe landing instead of midair")
		check(await wait_until(func():return acknowledged>=3),"guest receives authoritative ladder attachment")
		for i in 120:
			player.simulate_movement(1./60,Vector2(0,-1),false,false,false,0,0)
			player.send_snapshot_if_due(.1)
			if i%10==0:await get_tree().process_frame
		check(await wait_until(func():return acknowledged>=4),"guest receives climb height and animation phase through real snapshots")
		player.get_node("LadderClimb").simulate(.016,Vector2.ZERO,true,0,0)
		var module=level.get_node("Floor_Minus3_Trials_Observation_Blockout/Props/ObservationConsole1/RadioModule")
		player.teleport_authoritative(module.global_position+Vector3(0,-.9,1.2))
		check(await wait_until(func():return acknowledged>=5),"guest pickup enters the host's durable shared inventory")
		check(world._base_gameplay_controller.maintenance.get("radio_module",false),"host and guest share exactly one spare")
		var socket=tower.get_node("ServiceSocket")
		player.teleport_authoritative(socket.global_position+Vector3(-1,-.8,0))
		socket.network_interact(peer_id,player)
		check(await wait_until(func():return acknowledged>=6),"guest sees confirmed replacement feedback from host snapshot")

		_finish.rpc()
		await get_tree().create_timer(.3).timeout
		print("RADIO COOP CHECKS ",checks," FAILURES ",failures)
		get_tree().quit(0 if failures==0 else 1)
	else:
		check(await wait_until(func():return world._entered_v3_level and not world._v3_transition_in_progress and world._base_gameplay_controller!=null and world._base_gameplay_controller.has_authoritative_snapshot),"late guest loads tower snapshot")
		var state=world._base_gameplay_controller
		check(str(state.maintenance.get("radio_pin","")).length()==4,"guest has host-generated PIN")
		_ack.rpc_id(1,1,str(state.maintenance.radio_pin))
		var player: GamePlayer=get_tree().get_first_node_in_group("local_player")
		var tower=state.get_parent().get_node("SnowExterior/RadioTower")
		var gate=tower.get_node("Keypad")
		check(await wait_until(func():return player.global_position.distance_to(gate.global_position)<2.5),"host positions guest outside actual lock")
		gate.request_action("xxxx");await get_tree().create_timer(.5).timeout
		check(not state.maintenance.get("radio_unlocked",false),"guest cannot bypass wrong code")
		gate.request_action(str(state.maintenance.radio_pin))
		check(await wait_until(func():return state.maintenance.get("radio_unlocked",false)),"valid code updates guest and host")
		_ack.rpc_id(1,2,"")
		check(await wait_until(func():return player.is_climbing()),"guest attaches to host-approved route")
		var y:float=player.global_position.y
		_ack.rpc_id(1,3,"")
		check(await wait_until(func():return player.global_position.y>y+1),"guest sees real climbing movement")
		_ack.rpc_id(1,4,"")
		var module=state.get_parent().get_node("Floor_Minus3_Trials_Observation_Blockout/Props/ObservationConsole1/RadioModule")
		check(await wait_until(func():return not player.is_climbing() and player.global_position.distance_to(module.global_position)<2),"detach and teleport clear climbing state")
		module.request_action()
		check(await wait_until(func():return state.maintenance.get("radio_module",false)),"guest pickup replicates shared cartridge")
		_ack.rpc_id(1,5,"")
		check(await wait_until(func():return state.maintenance.get("radio_repaired",false)),"replacement completion reaches guest")
		var animation:AnimationPlayer=tower.get_node("ServiceSocket/Replacement/AnimationPlayer")
		check(animation.is_playing(),"guest plays native extraction and insertion after confirmation")
		_ack.rpc_id(1,6,"")


@rpc("any_peer","call_remote","reliable",2)
func _ack(stage: int,pin: String) -> void:
	if not host:return
	if stage==1:check(pin==str(world._base_gameplay_controller.maintenance.radio_pin),"host confirms identical random code")
	acknowledged=maxi(acknowledged,stage)
@rpc("authority","call_remote","reliable",2)
func _finish() -> void:
	print("RADIO COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(0 if failures==0 else 1)

