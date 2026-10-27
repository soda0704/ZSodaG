extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Production session: late-join carry pose, second carrier and real disconnect.
var corpse: MedicalCorpse
var guest_id := 0
var guest_checked := false

func _ready() -> void:
	var prefix := "user://medical_network_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+"_controls.cfg")
	super._ready()

func body_ready() -> bool:
	for body in get_tree().get_nodes_in_group("medical_corpses"):
		if body.recoverable and body.initialized:
			corpse = body
			return true
	return false

func lift(actor: GamePlayer) -> bool:
	actor.drop_current_item_authoritative()
	actor.teleport_authoritative(corpse.ragdoll.root_body.global_position+Vector3(0,.1,1),0)
	for frame in 6: await get_tree().physics_frame
	corpse.network_interact(actor.owner_peer_id,actor)
	return await wait_until(func(): return corpse.mode==MedicalCorpse.Mode.CARRIED and corpse.carrier_peer==actor.owner_peer_id)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--host": host=true
		elif argument.begins_with("--port="): port=int(argument.trim_prefix("--port="))
		elif argument.begins_with("--save-root="): ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,argument.trim_prefix("--save-root="))
	BaseGameplayController.save_scope="coop"
	if host:
		ExpeditionSaveStore.clear("coop")
		seed_expedition()
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4))==OK,"real medical ENet transport")
	multiplayer.multiplayer_peer=peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world=load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.resume_base_on_start=true
	get_tree().root.add_child(world)
	get_tree().current_scene=world
	if not host:
		check(await wait_until(func(): return peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"medical guest connects")
		world._on_session_ready(false)
		check(await wait_until(func(): return not world._v3_transition_in_progress and world.has_node("V3Level") and world.players.get_child_count()==2),"late guest loads production base")
		check(await wait_until(body_ready),"guest initializes the existing skeletal body")
		check(await wait_until(func(): return corpse.mode==MedicalCorpse.Mode.CARRIED and corpse.carrier_peer==1),"late join restores the host's current carried-body state")
		check(await wait_until(func(): return world.players.get_node("1").is_carrying_corpse()),"late join restores the remote carrier's occupied hands")
		medical_ready.rpc_id(1)
		return
	world._on_session_ready(true)
	check(await wait_until(func(): return world._v3_items_spawned and not world._v3_transition_in_progress),"medical host loads production base")
	check(await wait_until(body_ready),"host initializes recoverable medical body")
	var actor: GamePlayer=world.players.get_node("1")
	check(await lift(actor),"host uses the existing lift animation and shoulder anchor")
	print("HOST_READY_MEDICAL_CLIENT")
	check(await wait_until(func(): return guest_id>0),"late guest confirms carried-body synchronization")
	if guest_id==0:
		get_tree().quit(1)
		return
	check(actor.drop_current_item_authoritative() and corpse.mode==MedicalCorpse.Mode.GROUND,"host releases body through ordinary G action")
	var guest: GamePlayer=world.players.get_node(str(guest_id))
	check(await lift(guest),"second participant can pick up the released body")
	verify_guest_carry.rpc_id(guest_id)
	check(await wait_until(func(): return guest_checked),"guest sees its own shoulder carry before disconnection")
	disconnect_carrier.rpc_id(guest_id,failures)
	check(await wait_until(func(): return not world.players.has_node(str(guest_id))),"real disconnect removes the guest through production session cleanup")
	check(await wait_until(func(): return corpse.mode==MedicalCorpse.Mode.GROUND and corpse.carrier_peer==0),"disconnected carrier leaves a free physical body")
	check(corpse.ragdoll.bodies.all(func(body): return is_instance_valid(body) and not body.freeze),"body returns to ordinary ground physics after disconnect")
	check(await lift(actor),"remaining player can recover the body after partner disconnects")
	actor.drop_current_item_authoritative()
	check(corpse.state.save_progress_authoritative(false, "manual"), "explicit save captures released corpse")
	var snapshot: Dictionary=corpse.state.load_saved_snapshot()
	check(int(snapshot.maintenance.corpse_recovery.bodies[str(corpse.corpse_id)].mode)==MedicalCorpse.Mode.GROUND,"checkpoint keeps the released body without a stale carrier")
	print("MEDICAL COOP CHECKS ",checks," FAILURES ",failures)
	set_process(false)
	get_tree().current_scene=null
	world.queue_free()
	for frame in 4: await get_tree().process_frame
	get_tree().quit(1 if failures else 0)

@rpc("any_peer","call_remote","reliable")
func medical_ready() -> void:
	if host: guest_id=multiplayer.get_remote_sender_id()

@rpc("authority","call_remote","reliable")
func verify_guest_carry() -> void:
	var actor: GamePlayer=get_tree().get_first_node_in_group("local_player")
	check(await wait_until(func(): return actor.is_carrying_corpse() and corpse.carrier_peer==actor.owner_peer_id),"guest receives its own carried-body state")
	medical_checked.rpc_id(1,failures)

@rpc("any_peer","call_remote","reliable")
func medical_checked(client_failures: int) -> void:
	if host:
		failures+=client_failures
		guest_checked=true

@rpc("authority","call_remote","reliable")
func disconnect_carrier(host_failures: int) -> void:
	check(host_failures==0,"medical checks before disconnection passed")
	set_process(false)
	multiplayer.multiplayer_peer.close()
	get_tree().current_scene=null
	world.queue_free()
	for frame in 4: await get_tree().process_frame
	print("MEDICAL COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)
