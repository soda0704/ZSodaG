extends Node
var host := false
var guest := 0
var ready_guest := false
var local_ready := false
var acknowledged := false
var checks := 0
var failures := 0
var actors: Dictionary = {}
var books: Array = []
var state: BaseGameplayController
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",message)
func until(test: Callable) -> bool:
	var end := Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<end:
		if test.call(): return true
		await get_tree().process_frame
	return false
func _ready() -> void:
	Engine.max_fps = 60
	var port := 0
	for arg in OS.get_cmdline_user_args():
		if arg=="--host": host = true
		if arg.begins_with("--port="): port = int(arg.trim_prefix("--port="))
	var peer := ENetMultiplayerPeer.new()
	check((peer.create_server(port,1,4) if host else peer.create_client("127.0.0.1",port,4))==OK,"real journal ENet connection")
	multiplayer.multiplayer_peer = peer
	get_tree().root.get_node("GameMenu").force_close_menu()
	if host:
		multiplayer.peer_connected.connect(func(id: int): configure.rpc(id))
		print("HOST_READY_JOURNAL")
		run_host.call_deferred()
@rpc("authority","call_local","reliable")
func configure(id: int) -> void:
	guest = id
	var arena = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	arena.name = "JournalArena"
	get_tree().root.add_child(arena)
	state = BaseGameplayController.new()
	state.name = "JournalState"
	arena.add_child(state)
	state.set_process(false)
	for owner in [1,id]:
		var actor: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(owner,"Reader",Vector3(-.4 if owner==1 else .4,.02,-.8),Color.WHITE)
		actor.name = str(owner)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actors[owner] = actor
	for i in 2:
		var book = load("res://scenes/objects/items/journal_pickup.tscn").instantiate()
		book.name = "Journal%d" % i
		book.claim_key = "network_journal_%d" % i
		book.position = Vector3(-.4 if i==0 else .4,.4,0)
		arena.add_child(book)
		books.append(book)
	for i in 10: await get_tree().physics_frame
	local_ready = true
	if not host: guest_ready.rpc_id(1)
@rpc("any_peer","call_remote","reliable")
func guest_ready() -> void:
	if host and multiplayer.get_remote_sender_id()==guest: ready_guest = true
func run_host() -> void:
	check(await until(func(): return local_ready and ready_guest),"both production pickup scenes ready")
	if not local_ready: get_tree().quit(1); return
	books[0].network_interact(1,actors[1])
	books[1].network_interact(1,actors[1])
	check(actors[1].has_journal and books[0]._collected and not books[1]._collected,"host cannot consume both journals")
	begin_guest.rpc_id(guest)
	check(await until(func(): return actors[guest].has_journal),"guest's owner-checked pickup RPC grants the second journal")
	check(state.maintenance.journal_claims.size()==2,"exactly two claims survive simultaneous repeated requests")
	check(state.maintenance.journal_claims.values().has(actors[1].journal_owner_key()) and state.maintenance.journal_claims.values().has(actors[guest].journal_owner_key()),"each participant owns a distinct physical copy")
	var revision: int = actors[guest]._inventory_revision
	check(await until(func(): return acknowledged),"guest receives inventory and shared claim state")
	check(actors[guest]._inventory_revision==revision,"replayed pickups do not grant another journal or mutate inventory")
	var next := state.get_snapshot()
	next.maintenance["base_entered"] = true
	state._broadcast_snapshot(next)
	open_guest_map.rpc_id(guest)
	check(await until(func(): return actors[guest]._journal_map),"map presentation request replicates through the owner-checked player RPC")
	actors[guest].update_character_animation(1.0/60)
	check(actors[guest].body_animator.model.get_node("Journal/FrontCoverPivot/Inserts").busy,"remote world model starts the native paper animation")
	actors[guest].has_journal = false
	actors[guest].restore_journal_ownership()
	check(actors[guest].has_journal,"persistent claim restores the correct guest's journal")
	finish.rpc_id(guest)
	await get_tree().create_timer(.3).timeout
	print("JOURNAL NETWORK CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)
@rpc("authority","call_remote","reliable")
func begin_guest() -> void:
	check(await until(func(): return books[0]._collected and actors[1].has_journal),"host pickup and hidden world copy replicate")
	check(not actors[guest].has_journal and not books[1]._collected,"one player's pickup does not grant the other player a journal")
	var drag = actors[guest].get_node("ItemDrag")
	for i in range(1,51): drag._request_pickup.rpc_id(1,books[0].get_path(),i)
	drag._request_pickup.rpc_id(1,books[1].get_path(),51)
	check(await until(func(): return actors[guest].has_journal and books[1]._collected),"guest sees its accepted journal and both claimed copies")
	for i in range(52,102): drag._request_pickup.rpc_id(1,books[1].get_path(),i)
	await get_tree().create_timer(.3).timeout
	acknowledge.rpc_id(1)
@rpc("any_peer","call_remote","reliable")
func acknowledge() -> void:
	if host and multiplayer.get_remote_sender_id()==guest: acknowledged = true
@rpc("authority","call_remote","reliable")
func open_guest_map() -> void:
	await until(func(): return state.has_entered_base())
	actors[guest].request_journal_phase(2)
	actors[guest].request_journal_map(true)
@rpc("authority","call_remote","reliable")
func finish() -> void:
	print("JOURNAL NETWORK CHECKS ",checks," FAILURES ",failures)
	get_tree().quit(1 if failures else 0)
