extends "res://tools/tests/expedition_multiplayer_regression.gd"
const RECIPE = preload("res://assets/config/flamethrower_recipe.tres")
var bench: Node
var guest_id:=0
var guest_done:=false
var input_sequence:=100000
var interaction_serial:=50000
var client_input:=false
func _process(_delta: float) -> void:
	if world==null:return
	for actor in world.players.get_children():
		actor.set_physics_process(false);actor.survival.set_physics_process(false)
		actor.get_node("PlayerUI/NorthernLabHUD").set_process(false)
		actor.get_node("PlayerUI/NorthernLabHUD").hide()
		if host and actor.owner_peer_id!=1:actor.simulate_authoritative_movement(0.0)
	if client_input and not host:
		var local: GamePlayer=get_tree().get_first_node_in_group("local_player")
		input_sequence+=1
		local._submit_input.rpc_id(1,input_sequence,Vector2.ZERO,false,false,0,0,interaction_serial,0,local.rotation.y,local.head.rotation.x)

func seed_expedition() -> void:
	super.seed_expedition()
	var config: ConfigFile=ExpeditionSaveStore.read("coop").config
	config.set_value("base","day_index",7)
	config.set_value("base","containment",{"cave_visited":true,"cave_hives_found":true})
	var inventory: Dictionary=config.get_value("inventory","checkpoint",{})
	var parts := {}
	for type in RECIPE.pickup_scenes: parts[type]=2
	for id in ["test:host","test:guest"]:
		inventory.players[id]={"held_item":&"", "crafting_parts":parts.duplicate(), "tape_count":2}
	config.set_value("inventory","checkpoint",inventory)
	check(ExpeditionSaveStore.write(config,"coop","sleep"),"seed shared crafting expedition")
func at_bench(actor: GamePlayer,side: float) -> void:
	var approach: Vector3 = bench.global_position+bench.global_basis.x.normalized()*side*1.6
	approach.y = .04
	actor.teleport_authoritative(approach,0)
	for frame in 4: await get_tree().physics_frame
	var offset: Vector3=bench.get_interaction_position()-actor.head.global_position
	actor.rotation.y=atan2(-offset.x,-offset.z)
	actor.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
	check(actor.get_interaction_target()==bench,"native table ray for peer "+str(actor.owner_peer_id))
func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg=="--host": host=true
		elif arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="):ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,arg.trim_prefix("--save-root="))
	BaseGameplayController.save_scope="coop"
	if host: ExpeditionSaveStore.clear("coop");seed_expedition()
	var peer:=ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4))==OK,"real ENet crafting transport")
	multiplayer.multiplayer_peer=peer
	get_tree().root.get_node("SteamInput").set_process(false)
	world=load("res://scenes/levels/base_session.tscn").instantiate()
	world.set_script(load("res://tools/tests/fixtures/expedition_identity_session.gd"))
	world.uses_staging_lobby=true;world.staging_spawns_path=NodePath("ArrivalCabin/Spawns");world.resume_base_on_start=true
	get_tree().root.add_child(world);get_tree().current_scene=world
	if not host:
		check(await wait_until(func():return peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED),"crafting client connected")
		world._on_session_ready(false)
		check(await wait_until(func():return world._entered_v3_level and not world._v3_transition_in_progress and world.players.get_child_count()==2),"late client loads production crafting scene")
		bench=get_tree().get_first_node_in_group("flamethrower_workbenches")
		var local: GamePlayer=get_tree().get_first_node_in_group("local_player")
		check(await wait_until(func():return RECIPE.can_craft(local)),"client receives saved component inventory")
		check(bench.crafted_count()==0,"late client sees uncrafted shared recipe")
		craft_ready.rpc_id(1)
		return
	world._on_session_ready(true)
	check(await wait_until(func():return world._v3_items_spawned),"host resumes production scene")
	bench=get_tree().get_first_node_in_group("flamethrower_workbenches");bench.state.set_process(false)
	check(world.world_items.get_child_count()==18,"old checkpoint migrates two part sets exactly once")
	check(int(ExpeditionSaveStore.read("coop").config.get_value("inventory","checkpoint",{}).get("flamethrower_parts_layout_version",0))==0,"layout preparation does not automatically write to disk")
	print("HOST_READY_FOR_CRAFT_CLIENT")
	check(await wait_until(func():return guest_id>0),"late guest acknowledges restored components")
	if guest_id==0:get_tree().quit(1);return
	var actor: GamePlayer=world.players.get_node("1")
	var guest: GamePlayer=world.players.get_node(str(guest_id))
	await at_bench(actor,-1);await at_bench(guest,1)
	actor.try_authoritative_interaction()
	check(actor.has_held_item(&"flamethrower") and bench.crafted_count()==1,"host E consumes one recipe and awards one item")
	craft_now.rpc_id(guest_id)
	check(await wait_until(func():return bench.crafted_count()==2),"client native E RPC assembles second item on host")
	check(guest.has_held_item(&"flamethrower") and int(guest.crafting_parts.get(&"flame_valve",0))==1,"client gets finished item with one recipe consumed")
	actor.try_authoritative_interaction();craft_now.rpc_id(guest_id)
	for frame in 15: await get_tree().process_frame
	check(bench.crafted_count()==2 and int(actor.crafting_parts.get(&"flame_valve",0))==1 and int(guest.crafting_parts.get(&"flame_valve",0))==1,"repeated requests cannot exceed shared limit or consume leftovers")
	await exercise_equipment(guest)
	# A genuinely collected native pickup must stay absent on resume.
	var pickup: WorldItemPickup=world.world_items.get_child(0)
	actor.teleport_authoritative(pickup.global_position+Vector3(0,.1,1),0)
	pickup.network_interact(1,actor)
	for frame in 3:await get_tree().process_frame
	check(world.world_items.get_child_count()==17,"collecting a component removes its physical pickup before save")
	check(bench.state.save_progress_authoritative(false, "manual"), "explicit team save captures assembled equipment")
	var saved: Dictionary=ExpeditionSaveStore.read("coop").config.get_value("inventory","checkpoint",{})
	check(saved.players["test:host"].held_item==&"flamethrower" and saved.players["test:guest"].held_item==&"flamethrower","both players finished equipment persists by account")
	check(int(saved.players["test:guest"].crafting_parts.get(&"flame_valve",0))==1,"guest remaining components persist")
	# Replay the production restoration path with a migrated checkpoint.
	var count: int=world.world_items.get_child_count()
	for item in world.world_items.get_children(): item.queue_free()
	for frame in 3:await get_tree().process_frame
	bench.state.inventory_checkpoint=saved;world._v3_items_spawned=false;world.spawn_v3_world_items()
	check(world.world_items.get_child_count()==count,"checkpoint resume restores pickups without adding a second layout")
	check(bench.crafted_count()==2,"restoration preserves shared two-item limit")
	check_craft.rpc_id(guest_id)
	check(await wait_until(func():return guest_done),"guest confirms replicated held item and quest progress")
	finish_craft.rpc_id(guest_id,failures)
	await get_tree().create_timer(.4).timeout
	print("CRAFT COOP CHECKS ",checks," FAILURES ",failures);get_tree().quit(1 if failures else 0)
@rpc("any_peer","call_remote","reliable")
func craft_ready() -> void:
	if host:guest_id=multiplayer.get_remote_sender_id()
@rpc("authority","call_remote","reliable")
func craft_now() -> void:
	var actor: GamePlayer=get_tree().get_first_node_in_group("local_player")
	var offset: Vector3=bench.get_interaction_position()-actor.head.global_position
	actor.rotation.y=atan2(-offset.x,-offset.z)
	actor.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
	interaction_serial+=1;client_input=true
@rpc("authority","call_remote","reliable")
func check_craft() -> void:
	var actor: GamePlayer=get_tree().get_first_node_in_group("local_player")
	check(await wait_until(func():return actor.has_held_item(&"flamethrower") and bench.crafted_count()==2),"guest sees authoritative finished item and shared limit")
	check(not actor.weapon.perform_action(&"fire"),"guest generic bullet entry point cannot bypass the continuous-jet protocol")
	check(int(actor.crafting_parts.get(&"flame_valve",0))==1,"guest receives leftover inventory")
	craft_checked.rpc_id(1,failures)
@rpc("any_peer","call_remote","reliable")
func craft_checked(client_failures:int) -> void:
	if host:failures+=client_failures;guest_done=true
@rpc("authority","call_remote","reliable")
func finish_craft(host_failures:int) -> void:
	check(host_failures==0,"host crafting validation passed")
	print("CRAFT COOP CHECKS ",checks," FAILURES ",failures);get_tree().quit(1 if failures else 0)


func exercise_equipment(_guest: GamePlayer) -> void:
	pass
