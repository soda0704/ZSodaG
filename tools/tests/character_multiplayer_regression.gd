extends Node
## Two real processes using the production session/player RPCs over ENet.
## Steam transport still needs separate signed-in accounts on two devices.

@onready var root: Window = get_tree().root
var host := false
var port := 28741
var order := -1
var world: Node3D
var failures := 0
var stage := "boot"
var reports := {}
var rag_reports := 0
var observed := {}
var clock_time := 0.0
var _jumped := false
var _acted := false
var _journal_opened := false
var _journal_closed := false
var _captured := false

func _ready() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures += 1

func local_player() -> GamePlayer:
	return get_tree().get_first_node_in_group("local_player") as GamePlayer

func players() -> Array:
	return world.get_node("Players").get_children().filter(func(node): return node is GamePlayer)

func _physics_process(delta: float) -> void:
	clock_time += delta
	var player := local_player()
	if player==null: return
	player.set_process_unhandled_input(false)
	root.get_node("GameMenu").force_close_menu()
	root.get_node("SteamInput").using_controller = false
	if not root.get_node("QuestJournal").is_journal_open(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for action in ["move_forward","move_backward","move_right","sprint","crouch"]: Input.action_release(action)
	if stage in ["walk","run","crouch_walk","rifle_walk","rifle_run","rifle_crouch"]: Input.action_press("move_forward")
	if stage in ["run","rifle_run"]: Input.action_press("sprint")
	if stage=="strafe": Input.action_press("move_right")
	if stage=="backward": Input.action_press("move_backward")
	if stage in ["crouch","crouch_walk","rifle_crouch"]: Input.action_press("crouch")
	player._input_pitch = 0.80 if stage in ["look","rifle_up"] else -0.80 if stage in ["look_down","rifle_down"] else 0.0
	player._input_yaw = 0.75 if stage=="look" else 0.0
	if stage in ["jump","rifle_jump"] and not _jumped:
		player._jump_serial += 1
		_jumped = true
	if stage in ["pistol","rifle"] and clock_time>0.35 and not _acted:
		player.weapon.request_action(&"fire")
		_acted = true
	if stage in ["pistol","rifle"] and clock_time>0.70 and _acted and not observed.has(stage+"reload"):
		player.weapon.request_action(&"reload")
		observed[stage+"reload"] = true
	if stage=="torch" and not _acted:
		player._flashlight_serial += 1
		_acted = true
	if stage=="journal" and not _journal_opened:
		root.get_node("QuestJournal").open_journal()
		_journal_opened = true
	if stage=="journal" and clock_time>2.0 and not _journal_closed:
		root.get_node("QuestJournal").close_journal()
		_journal_closed = true
	for actor: GamePlayer in players():
		var key := str(actor.owner_peer_id)
		if not observed.has(key): observed[key] = {}
		var record: Dictionary = observed[key]
		if actor._is_crouching or actor._remote_crouching: record["crouch"] = true
		if actor._sprint_active: record["run"] = true
		if actor._journal_phase>0: record["journal"] = true
		if actor._flashlight_enabled: record["torch"] = true
		if actor.survival.dead: record["death"] = true
		if actor.get_node("PlayerRagdoll").ragdoll!=null: record["ragdoll"] = true
		if actor.weapon.kind in [&"pistol",&"m4a1"]: record[String(actor.weapon.kind)] = true
		if actor.weapon.reload_left>0: record["reload"] = true
		if actor.velocity.y>1.0 or actor._remote_target_velocity.y>1.0: record["jump"] = true
	if not _captured and clock_time>0.55 and stage in ["idle","run","crouch","jump","pistol","rifle","rifle_walk","rifle_run","rifle_crouch","rifle_jump","rifle_up","rifle_down","torch","journal","death_client","death_host"]:
		_captured = true
		capture_remote.call_deferred()

func capture_remote() -> void:
	if DisplayServer.get_name()=="headless": return
	var actor: GamePlayer
	for candidate: GamePlayer in players():
		if not candidate.is_local_player(): actor = candidate
	if actor==null: return
	var camera: Camera3D = world.get_node("OverviewCamera")
	camera.cull_mask = 1 | (1<<18)
	camera.global_position = actor.global_position+actor.global_basis*Vector3(0,1.45,-3.0)
	camera.look_at(actor.global_position+Vector3(0,0.95,0))
	camera.make_current()
	var journal_root: Control = root.get_node("QuestJournal/JournalRoot")
	var journal_visible := journal_root.visible
	journal_root.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://tools/.local/scenery-review/character-network/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	get_viewport().get_texture().get_image().save_png(directory+("host" if host else "client")+"-variant%d-"%actor.character_variant_id+stage+".png")
	journal_root.visible = journal_visible
	var owner := local_player()
	if owner!=null: owner.camera.make_current()

func delay(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

@rpc("authority","call_local","reliable")
func set_stage(value: String) -> void:
	stage = value
	clock_time = 0
	_acted = false
	_jumped = false
	_journal_opened = false
	_journal_closed = false
	_captured = false
	print("STAGE ",stage)

func equip(kind: StringName) -> void:
	for actor: GamePlayer in players():
		actor._held_item_type = kind
		actor.weapon.rounds = 12 if kind==&"pistol" else 30 if kind==&"m4a1" else 0
		actor.weapon.pistol_ammo = 24
		actor.weapon.rifle_magazines.assign([30,30])
		if kind==&"flashlight":
			actor._held_item_type = actor.NO_ITEM
			actor._has_flashlight = true
			actor._battery_charge = 1.0
			actor._flashlight_enabled = false
		actor._publish_inventory()

@rpc("authority","call_remote","reliable")
func request_report() -> void:
	var actors := {}
	for actor: GamePlayer in players():
		actors[str(actor.owner_peer_id)] = {"variant":actor.character_variant_id,"model":actor.body_animator.variant.variant_id,"bones":actor.body_animator.skeleton.get_bone_count(),"scene":actor.body_animator.variant.body_scene.resource_path,"alive":not actor.survival.dead,"observed":observed.get(str(actor.owner_peer_id),{})}
	actors["battery_items"] = battery_snapshot()
	receive_report.rpc_id(1,actors)

func battery_snapshot() -> Dictionary:
	var result := {}
	for item in world.world_items.get_children():
		if item.item_type==&"battery":
			result[String(item.name)] = {"state":item.item_state.duplicate(true),"mesh":item.get_node("Model/Body").mesh.resource_path}
	return result

@rpc("authority","call_remote","reliable")
func request_rag_report(id: int) -> void:
	var actor: GamePlayer = world.get_node("Players").get_node(str(id))
	var rag = actor.get_node("PlayerRagdoll").ragdoll
	if rag!=null:
		var positions: Array[Vector3] = []
		for body in rag.bodies: positions.append(body.global_position)
		receive_rag_report.rpc_id(1,id,positions)

@rpc("any_peer","call_remote","reliable")
func receive_rag_report(id: int, positions: Array) -> void:
	if not host: return
	var actor: GamePlayer = world.get_node("Players").get_node(str(id))
	var rag = actor.get_node("PlayerRagdoll").ragdoll
	if rag==null: return
	var difference := 0.0
	for i in mini(positions.size(),rag.bodies.size()): difference=maxf(difference,positions[i].distance_to(rag.bodies[i].global_position))
	check(positions.size()==17 and difference<0.70,"replicated ragdoll agrees within smoothing delay: %.3f m"%difference)
	rag_reports += 1

@rpc("any_peer","call_remote","reliable")
func receive_report(data: Dictionary) -> void:
	if host: reports[multiplayer.get_remote_sender_id()] = data

@rpc("authority","call_remote","reliable")
func finish(code: int) -> void:
	print("CLIENT NETWORK COMPLETE code ",code)
	get_tree().quit(code)

func run() -> void:
	root.size = Vector2i(640,360)
	root.position = Vector2i(3000,2000)
	for arg in OS.get_cmdline_user_args():
		if arg=="--host": host = true
		elif arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--order="): order = int(arg.trim_prefix("--order="))
	root.get_node("GameMenu").force_close_menu()
	var input_service := root.get_node("SteamInput")
	input_service.set_process(false)
	input_service.set_process_input(false)
	input_service.native_input_available = false
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	world = load("res://tools/tests/fixtures/character_network_session.tscn").instantiate()
	root.add_child(world)
	var peer := ENetMultiplayerPeer.new()
	var result := peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4)
	check(result==OK,"network transport created")
	if result!=OK: get_tree().quit(1); return
	multiplayer.multiplayer_peer = peer
	if host:
		# Test both deterministic permutations; normal sessions use randi_range.
		if order>=0: world._host_character_variant = order
		world._on_session_ready(true)
		# Existing items must keep the host-selected design for a joining peer.
		seed(424242)
		for i in 12:
			world.spawn_world_item(&"battery",Transform3D(Basis.IDENTITY,Vector3(15+i*0.12,0.3,0)),{"charge_amount":0.37})
	else:
		return
	var deadline := Time.get_ticks_msec()+20000
	while players().size()<2 and Time.get_ticks_msec()<deadline: await delay(0.1)
	check(players().size()==2,"actual host and client joined production player roster")
	if players().size()<2: get_tree().quit(1); return
	await delay(0.4)
	var actors := players()
	check(actors[0].character_variant_id!=actors[1].character_variant_id,"host assigns two different variants")
	for actor: GamePlayer in actors:
		print("VISUAL MODEL ",actor.owner_peer_id," variant ",actor.character_variant_id," scene ",actor.body_animator.model.scene_file_path," bones ",actor.body_animator.skeleton.get_bone_count())
		check(actor.body_animator.skeleton.get_bone_count()==(79 if actor.character_variant_id==0 else 88),"host loaded assigned native rig")
	for name in ["idle","walk","run","stop","strafe","backward","look","look_down","crouch","crouch_walk","stand","jump","land"]:
		set_stage.rpc(name)
		await delay(0.85)
	equip(&"pistol")
	set_stage.rpc("pistol")
	await delay(2.3)
	equip(&"m4a1")
	set_stage.rpc("rifle")
	await delay(3.0)
	for name in ["rifle_walk","rifle_run","rifle_crouch","rifle_jump","rifle_up","rifle_down"]:
		set_stage.rpc(name)
		await delay(0.85)
	equip(&"flashlight")
	set_stage.rpc("torch")
	await delay(0.9)
	set_stage.rpc("journal")
	await delay(3.7)
	set_stage.rpc("death_client")
	var client_actor: GamePlayer = actors[1]
	client_actor.survival.damage(999,"Network character regression")
	await delay(2.0)
	request_rag_report.rpc(client_actor.owner_peer_id)
	await delay(2.7)
	check(not client_actor.survival.dead,"client respawns")
	set_stage.rpc("death_host")
	var host_actor: GamePlayer = actors[0]
	host_actor.survival.damage(999,"Network character regression")
	await delay(2.0)
	request_rag_report.rpc(host_actor.owner_peer_id)
	await delay(2.7)
	check(not host_actor.survival.dead,"host respawns")
	set_stage.rpc("final")
	request_report.rpc()
	await delay(0.5)
	check(reports.size()==1,"client returns actual replicated state")
	check(rag_reports==2,"both deaths compared between actual peers")
	for report in reports.values():
		check(battery_snapshot().size()==12 and report.get("battery_items",{})==battery_snapshot(),"joining client sees the host's exact battery designs, charges and meshes")
		for actor: GamePlayer in actors:
			var key := str(actor.owner_peer_id)
			check(report.has(key) and report[key].variant==actor.character_variant_id and report[key].model==actor.character_variant_id,"both peers agree on variant %s"%key)
			check(report.get(key,{}).get("bones",0)==(79 if actor.character_variant_id==0 else 88),"client loaded matching native rig %s"%key)
			for state in ["crouch","run","jump","pistol","m4a1","reload","torch","journal","death","ragdoll"]:
				check(report.get(key,{}).get("observed",{}).get(state,false),"client observes %s for player %s"%[state,key])
				check(observed.get(key,{}).get(state,false),"host observes %s for player %s"%[state,key])
	var code := 1 if failures else 0
	print("HOST NETWORK FAILURES ",failures," ORDER ",order)
	finish.rpc(code)
	await delay(0.15)
	get_tree().quit(code)
