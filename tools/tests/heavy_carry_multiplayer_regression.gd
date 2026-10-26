extends Node
var host:=false
var port:=0
var guest:=0
var ready_guest:=false
var guest_joined_ack:=false
var holding:=false
var heartbeat:=0.0
var failures:=0
var checks:=0
var actors:Dictionary={}
var prop:HeavyCarryProp
var workbench_mode := false
var joist_route_mode := false
var route_ack := false
var local_ready := false
func cleanup_arena() -> void:
	holding=false
	set_process(false)
	# Stop delivery before removing RPC targets from either test process.
	var transport := multiplayer.multiplayer_peer
	SteamNetwork.leave_session("Heavy carry test finished")
	transport.close()
	var arena := get_tree().root.get_node_or_null("CarryArena")
	if arena != null: arena.queue_free()
	for frame in 4: await get_tree().process_frame
	actors.clear()
	prop=null
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func wait_until(test:Callable) -> bool:
	var end:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<end:
		if test.call():return true
		await get_tree().process_frame
	return false
func _ready() -> void:
	Engine.max_fps=60
	for arg in OS.get_cmdline_user_args():
		if arg=="--host":host=true
		if arg=="--workbench":workbench_mode=true
		if arg=="--joist-route":joist_route_mode=true
		if arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
	var peer:=ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4))==OK,"real ENet carry connection")
	multiplayer.multiplayer_peer=peer
	get_tree().root.get_node("GameMenu").force_close_menu()
	get_tree().root.get_node("SteamInput").set_process(false)
	if host:
		multiplayer.peer_connected.connect(func(id:int):configure.rpc(id))
		print("HOST_READY_HEAVY")
		await run_host()
@rpc("authority","call_local","reliable")
func configure(id:int) -> void:
	guest=id
	var arena=load("res://scenes/levels/floor_minus1_control_security_blockout.tscn" if joist_route_mode else "res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	arena.name="CarryArena"
	get_tree().root.add_child(arena)
	if joist_route_mode:
		var actors_root := Node3D.new()
		actors_root.name = "Players"
		arena.add_child(actors_root)
	if workbench_mode:
		var state := BaseGameplayController.new()
		state.name = "BaseGameplayController"
		arena.add_child(state)
		state.set_process(false)
	for owner in [1,id]:
		var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(owner,"Carrier",Vector3(-2.15 if owner==1 else 2.15,.02,.15),Color.WHITE,-PI/2 if owner==1 else PI/2)
		actor.name=str(owner)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.get_node("ItemDrag").set_physics_process(false)
		actors[owner]=actor
	if joist_route_mode:
		prop = arena.get_node("FallenCheckpointJoist")
	else:
		prop=load("res://scenes/objects/crafting/flamethrower_workbench.tscn" if workbench_mode else "res://scenes/objects/props/bench.tscn").instantiate()
		prop.name="TestBench"
		prop.position = Vector3.ZERO
		arena.add_child(prop)
	for frame in 15:await get_tree().physics_frame
	for index in 2:
		var actor:GamePlayer=actors[1 if index==0 else id]
		var point:=prop.grip_point(index)
		point.x*=.85
		point.y-=.12
		if joist_route_mode:
			var grip := prop.grip_point(index)
			actor.position = Vector3(prop.position.x + .7, .02, grip.z + (.8 if index == 0 else -.8))
			point = prop.global_transform * Vector3(-2.2 if index == 0 else 2.2, .4, 0)
		var offset:=point-actor.head.global_position
		actor.rotation.y=atan2(-offset.x,-offset.z)
		actor.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
	# Flush relocated character/CSG transforms before either peer starts ray queries.
	for frame in 2: await get_tree().physics_frame
	local_ready = true
	if not host:guest_ready.rpc_id(1)
@rpc("any_peer","call_remote","reliable")
func guest_ready() -> void:
	if host and multiplayer.get_remote_sender_id()==guest:ready_guest=true
func _process(_delta:float) -> void:
	if not host and holding:
		heartbeat-=_delta
		if heartbeat<=0:
			heartbeat=.1
			var actor:GamePlayer=actors[guest]
			actor.get_node("ItemDrag")._request_hold.rpc_id(1,prop.get_path(),1,Vector2(actor.rotation.y,actor.head.rotation.x))
	if host and is_instance_valid(prop) and prop.grips.has(1):prop.acquire_grip(actors[1])
func run_host() -> void:
	check(await wait_until(func():return ready_guest and local_ready),"both carry scenes ready")
	if not ready_guest:get_tree().quit(1);return
	check(prop.acquire_grip(actors[1]),"host claims first end")
	begin_guest.rpc_id(guest)
	var joined := await wait_until(func():return prop.grips.size()==2)
	if not joined:
		var actor:GamePlayer=actors[guest]
		print("CARRY DEBUG valid=",actor.get_node("ItemDrag")._valid_item(prop.get_path())," target=",actor.get_interaction_target()," grip=",prop._nearest_grip(actor)," usable=",prop.can_carry(actor)," occupied=",actor.get_node("ItemDrag").heavy_body," serial=",actor.get_node("ItemDrag")._server_gesture," state=",prop.grips)
	check(joined,"guest owner-checked hold RPC claims second end")
	check(await wait_until(func():return guest_joined_ack),"guest acknowledges its replicated grip before release")
	check(prop.drag_owner_peer!=0,"paired furniture is excluded from elevator cargo capture")
	if joist_route_mode:
		prop.position.z += 1
		check(await wait_until(func():return prop.get_parent().get_node("JoistRouteBlocker").cleared), "host clears the route after physical beam displacement")
		confirm_route.rpc_id(guest)
		check(await wait_until(func():return route_ack), "guest confirms authoritative route clearance")
	await get_tree().create_timer(.15).timeout
	stop_guest.rpc_id(guest)
	check(await wait_until(func():return prop.grips.size()==1),"guest release preserves host grip")
	await get_tree().create_timer(.2).timeout
	check(prop.grips.size()==1 and not actors[guest].get_node("ItemDrag").is_heavy_carrying(),"delayed held packets cannot reclaim released grip")
	prop.release_grip(1)
	check(prop.grips.is_empty(),"all participants can release without orphan occupancy")
	finish.rpc_id(guest,failures)
	await get_tree().create_timer(.25).timeout
	print("HEAVY NETWORK CHECKS ",checks," FAILURES ",failures)
	await cleanup_arena()
	get_tree().quit(1 if failures else 0)
@rpc("authority","call_remote","reliable")
func begin_guest() -> void:
	check(await wait_until(func():return actors[1].get_node("ItemDrag").is_heavy_carrying()),"guest receives host grip state")
	var actor:GamePlayer=actors[guest]
	check(actor.get_interaction_target()==prop,"guest E targets physical bench")
	holding=true
	check(await wait_until(func():return actor.get_node("ItemDrag").is_heavy_carrying()),"guest receives own busy-hand state")
	check(await wait_until(func():return prop.get_node("CarryAudio")._last_received>0),"guest receives host-authoritative physical audio state")
	joined_ack.rpc_id(1)
@rpc("any_peer","call_remote","reliable")
func joined_ack() -> void:
	if host and multiplayer.get_remote_sender_id()==guest:guest_joined_ack=true
@rpc("authority", "call_remote", "reliable")
func confirm_route() -> void:
	check(await wait_until(func():return prop.get_parent().get_node("JoistRouteBlocker/CollisionShape3D").disabled), "client removes the same route collision after host movement")
	ack_route.rpc_id(1)
@rpc("any_peer", "call_remote", "reliable")
func ack_route() -> void:
	if host and multiplayer.get_remote_sender_id() == guest: route_ack = true
@rpc("authority","call_remote","reliable")
func stop_guest() -> void:
	holding=false
	actors[guest].get_node("ItemDrag")._request_release.rpc_id(1,1)
	await get_tree().create_timer(.08).timeout
	for attempt in 10:actors[guest].get_node("ItemDrag")._request_hold.rpc_id(1,prop.get_path(),1)
	actors[1].get_node("ItemDrag")._request_release.rpc_id(1,99)
	check(await wait_until(func():return not actors[guest].get_node("ItemDrag").is_heavy_carrying()),"guest sees release replicated")
@rpc("authority","call_remote","reliable")
func finish(count:int) -> void:
	print("HEAVY NETWORK CHECKS ",checks," FAILURES ",failures+count)
	await cleanup_arena()
	get_tree().quit(1 if failures+count else 0)
