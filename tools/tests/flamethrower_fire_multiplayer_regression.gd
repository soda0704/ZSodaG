extends "res://tools/tests/flamethrower_multiplayer_regression.gd"
var fire_ack:=false
var test_fire_held:=false
var test_heartbeat:=0.0
func _process(delta: float) -> void:
	super._process(delta)
	if world!=null and not host and test_fire_held:
		test_heartbeat+=delta
		if test_heartbeat>=.1:
			test_heartbeat=0
			get_tree().get_first_node_in_group("local_player").weapon.flame.request_trigger(true)

func exercise_equipment(guest: GamePlayer) -> void:
	var encounter: Node=get_tree().get_first_node_in_group("cave_hive_encounters")
	var hive: Node3D=encounter.hives[0]
	guest.teleport_authoritative(hive.global_position+Vector3(0,.05,-3.7),0)
	for frame in 8:await get_tree().physics_frame
	var before: float=encounter.get_health(0)
	var actor: GamePlayer=world.players.get_node("1")
	var host_fuel: float=actor.weapon.flame.fuel_liters
	start_client_fire.rpc_id(guest_id)
	check(await wait_until(func():return encounter.get_health(0)<before),"client held attack produces real host-authoritative flame damage")
	check(guest.weapon.flame.emitting and guest.weapon.flame.fuel_liters<guest.weapon.flame.capacity_liters,"host consumes guest fuel while leased trigger is held")
	check(not actor.weapon.flame.emitting and actor.weapon.flame.fuel_liters==host_fuel,"forged client trigger cannot operate host-owned flamethrower")
	stop_client_fire.rpc_id(guest_id)
	check(await wait_until(func():return not guest.weapon.flame.emitting),"client release stops replicated jet")
	var stopped: float=encounter.get_health(0)
	await get_tree().create_timer(.25).timeout
	check(encounter.get_health(0)==stopped,"released jet cannot continue applying hidden damage")
	one_packet_fire.rpc_id(guest_id)
	check(await wait_until(func():return guest.weapon.flame.emitting),"single valid trigger request starts on host")
	await get_tree().create_timer(.65).timeout
	check(not guest.weapon.flame.emitting,"expired input lease stops a silent or disconnected client")
	verify_client_fire.rpc_id(guest_id)
	check(await wait_until(func():return fire_ack),"guest receives final fuel and stopped effect state")
	world.save_inventory_checkpoint()
	var saved: Dictionary=ExpeditionSaveStore.read("coop").config.get_value("inventory","checkpoint",{})
	check(float(saved.players["test:guest"].flame_fuel_liters)<guest.weapon.flame.capacity_liters and not saved.players["test:guest"].flame_active,"production save keeps spent fuel and a stopped trigger")
@rpc("authority","call_remote","reliable")
func start_client_fire() -> void:
	var actor: GamePlayer=get_tree().get_first_node_in_group("local_player")
	get_tree().root.get_node("GameMenu").force_close_menu()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var hive: Node3D=get_tree().get_first_node_in_group("cave_hive_encounters").hives[0]
	var offset: Vector3=hive.global_position+Vector3.UP*.95-actor.head.global_position
	actor.rotation.y=atan2(-offset.x,-offset.z);actor.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
	world.players.get_node("1").weapon.flame._request_trigger.rpc_id(1,true)
	actor.weapon.flame.set_physics_process(false)
	test_fire_held=true
	actor.weapon.flame.request_trigger(true)
@rpc("authority","call_remote","reliable")
func stop_client_fire() -> void:
	test_fire_held=false
	get_tree().get_first_node_in_group("local_player").weapon.flame.request_trigger(false)
@rpc("authority","call_remote","reliable")
func one_packet_fire() -> void:
	var actor: GamePlayer=get_tree().get_first_node_in_group("local_player")
	actor.weapon.flame.set_physics_process(false)
	actor.weapon.flame._request_trigger.rpc_id(1,true)
@rpc("authority","call_remote","reliable")
func verify_client_fire() -> void:
	var actor: GamePlayer=get_tree().get_first_node_in_group("local_player")
	check(await wait_until(func():return not actor.weapon.flame.emitting and actor.weapon.flame.fuel_liters<actor.weapon.flame.capacity_liters),"client sees stopped flame and its own reduced fuel")
	check(not world.players.get_node("1").weapon.flame.emitting,"remote host weapon remains inactive after forged request")
	actor.weapon.flame.set_physics_process(true)
	Input.action_release(&"weapon_attack")
	fire_verified.rpc_id(1,failures)
@rpc("any_peer","call_remote","reliable")
func fire_verified(client_failures:int) -> void:
	if host:failures+=client_failures;fire_ack=true
