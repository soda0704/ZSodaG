extends "res://tools/tests/expedition_multiplayer_regression.gd"
## Local ENet, production scene and the real child RPC paths. No client-simulated AI cues.
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
		check(await wait_until(func(): return world._v3_items_spawned and not world._v3_transition_in_progress),"host loads production audio scene")
		var encounter = world._base_gameplay_controller.get_parent().get_node("ContainmentEncounter")
		for creature in get_tree().get_nodes_in_group("hostile_monsters"): creature.set_ai_enabled(false)
		var creature = encounter.get_node("Monster3")
		creature.set_ai_enabled(true); creature.set_physics_process(false)
		var audio = creature.get_node("MonsterAudio")
		audio.countdown = 1000.0
		audio.sound_played.connect(func(kind,_sequence): heard.append(kind))
		var player = get_tree().get_first_node_in_group("local_player")
		player.set_physics_process(false); player.survival.set_physics_process(false)
		player.teleport_authoritative(Vector3(1000,500,1000),0)
		creature.target_spotted.emit(null)
		print("HOST_READY_FOR_MONSTER_AUDIO_CLIENT")
		check(await wait_until(func(): return acknowledged >= 1),"guest late-joins without replaying old warning")
		check(await wait_until(func(): return encounter.get_ready_peers().size()>0),"remote audio actor is ready before RPC emission")
		audio._cooldowns.clear()
		creature.target_spotted.emit(null); creature.target_spotted.emit(null)
		check(await wait_until(func(): return acknowledged >= 2),"guest hears host alert once while host is out of range")
		creature._windup = .5
		creature.attack_started.emit(null,.5)
		check(await wait_until(func(): return acknowledged >= 3),"guest receives authoritative windup")
		creature._cancel_attack()
		check(await wait_until(func(): return acknowledged >= 4),"cancellation reaches guest without a phantom strike")
		creature.attack_finished.emit(null,true)
		check(await wait_until(func(): return acknowledged >= 5),"guest receives actual strike cue")
		check(heard.is_empty(),"host listener never hears distant guest-side threat")
		check(creature.health == 85.0,"audio events do not damage or mutate the creature")
		finish_audio.rpc(); await get_tree().create_timer(.3).timeout; finish_audio()
	else:
		check(await wait_until(func(): return peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"guest connects")
		world._on_session_ready(false)
		check(await wait_until(func(): return world._entered_v3_level and not world._v3_transition_in_progress),"guest loads production audio scene")
		get_tree().root.get_node("GameMenu").force_close_menu()
		var creature = world._base_gameplay_controller.get_parent().get_node("ContainmentEncounter/Monster3")
		var audio = creature.get_node("MonsterAudio")
		audio.countdown = 1000.0
		audio.sound_played.connect(func(kind,_sequence): heard.append(kind))
		var player = get_tree().get_first_node_in_group("local_player")
		player.set_physics_process(false); player.survival.set_physics_process(false)
		# Local listener placement only; gameplay authority stays on the host.
		player.global_position = creature.global_position + Vector3(3,0,0)
		await get_tree().create_timer(.4).timeout
		check(heard.is_empty(),"late join does not manufacture past alert cues")
		ack_audio.rpc_id(1,1)
		check(await wait_until(func(): return heard.has(&"alert")),"nearby guest gets host alert")
		check(heard.count(&"alert")==1,"reacquisition debounce is consistent on guest")
		var serial: int = audio._received
		audio._on_spotted(null)
		check(audio._serial==0 and audio._received==serial,"client cannot publish an authoritative audio event")
		ack_audio.rpc_id(1,2)
		check(await wait_until(func(): return heard.has(&"windup")),"windup is synchronized over real child RPC")
		ack_audio.rpc_id(1,3)
		check(await wait_until(func(): return not audio._cue.playing),"cancel stops guest windup")
		check(not heard.has(&"miss") and not heard.has(&"strike"),"cancel is not presented as a landed or missed strike")
		ack_audio.rpc_id(1,4)
		check(await wait_until(func(): return heard.has(&"strike")),"guest hears committed strike")
		ack_audio.rpc_id(1,5)

@rpc("any_peer","call_remote","reliable")
func ack_audio(phase: int) -> void:
	if multiplayer.is_server(): acknowledged = maxi(acknowledged,phase)

@rpc("authority","call_remote","reliable")
func finish_audio() -> void:
	print("MONSTER AUDIO COOP CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)
