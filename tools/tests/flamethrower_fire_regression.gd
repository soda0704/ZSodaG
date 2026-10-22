extends SceneTree
var checks:=0
var failures:=0
var base: Node3D
var state: BaseGameplayController
var actor: GamePlayer
var flame: Node
var hive: Node3D
var encounter: Node
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://flame_fire_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle(n:=8) -> void:
	for frame in n:
		actor.update_character_animation(.016)
		await physics_frame
func aim(point: Vector3) -> void:
	var offset:=point-actor.head.global_position
	actor.rotation.y=atan2(-offset.x,-offset.z);actor.head.rotation.x=atan2(offset.y,Vector2(offset.x,offset.z).length())
func burst(seconds: float) -> void:
	var left:=seconds
	while left>.00001:
		var dt:=minf(.1,left);left-=dt
		flame.set_trigger_authoritative(true);flame.step_authoritative(dt)
func run() -> void:
	base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
	for frame in 5:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	state=base.get_node("BaseGameplayController");state.set_process(false)
	actor=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.survival.debug_invincible=true
	flame=actor.weapon.flame;flame.set_physics_process(false)
	state.debug_set_day_authoritative(7)
	encounter=base.get_node("Cave_Day7/HiveEncounter");hive=encounter.hives[0]
	actor.teleport_authoritative(hive.global_position+Vector3(0,.05,-4),0)
	await settle();aim(hive.global_position+Vector3(0,.95,0));await settle(15)
	actor.pickup_world_item_authoritative(&"flamethrower",{})
	await settle()
	check(is_equal_approx(flame.fuel_liters,flame.capacity_liters),"new and legacy assembled item begins with full fuel")
	check(flame.physics_jet().distance>3 and not flame.physics_jet().blocked_muzzle,"authored world muzzle produces a valid forward jet")
	var before: float=encounter.get_health(0)
	burst(1.0)
	check(is_equal_approx(encounter.get_health(0),before-flame.damage_per_second),"one second of real jet damage applies configured DPS to existing hive collider")
	check(is_equal_approx(flame.fuel_liters,flame.capacity_liters-flame.consumption_per_second),"one second consumes exact fuel")
	check(encounter.get_health(1)==encounter.starting_health,"nearby off-axis hive is unaffected")
	var health_after: float=encounter.get_health(0)
	flame.set_trigger_authoritative(false);flame.step_authoritative(.1)
	check(not flame.emitting and encounter.get_health(0)==health_after,"release immediately stops damage")
	var wall: Node3D=load("res://tools/tests/fixtures/flame_test_wall.tscn").instantiate();base.add_child(wall)
	wall.global_position=(actor.head.global_position+hive.global_position+Vector3.UP*.95)*.5
	await settle()
	check(flame.physics_jet().hit and float(flame.physics_jet().distance)<3,"wall shortens the visual jet")
	burst(.3)
	check(encounter.get_health(0)==health_after,"continuous fire cannot damage hive behind a wall")
	wall.global_position=actor.head.global_position-actor.head.global_basis.z*.23
	await settle()
	check(flame.physics_jet().blocked_muzzle,"wall between eye and model muzzle is detected")
	burst(.2);check(encounter.get_health(0)==health_after,"weapon model poking through wall cannot start damage behind it")
	wall.queue_free();await settle(2)
	flame.set_trigger_authoritative(true);flame.step_authoritative(.1)
	var fuel_before: float=flame.fuel_liters
	await create_timer(flame.input_lease_seconds+.05).timeout
	flame.step_authoritative(.1)
	check(not flame.emitting and flame.fuel_liters==fuel_before,"missing client heartbeat expires without further fuel or damage")
	for flag in ["journal","death"]:
		if flag=="journal":actor._journal_phase=1
		else:actor.survival.dead=true
		flame.set_trigger_authoritative(true);flame.step_authoritative(.1)
		check(not flame.emitting,"blocked player state stops jet: "+flag)
		actor._journal_phase=0;actor.survival.dead=false
	var saved_fuel: float=flame.fuel_liters
	var inventory:=actor.get_inventory_snapshot();actor.apply_inventory_snapshot(inventory)
	check(flame.fuel_liters==saved_fuel,"inventory snapshot preserves partial tank")
	var held_state:=actor.get_held_item_state()
	check(float(held_state.fuel_liters)==saved_fuel,"dropped item state owns remaining fuel")
	actor.drop_current_item_authoritative();await settle(2)
	check(not flame.emitting,"unequipping stops active jet")
	actor.pickup_world_item_authoritative(&"flamethrower",held_state)
	check(flame.fuel_liters==saved_fuel,"pickup does not refill a previously used flamethrower")
	flame.fuel_liters=.004
	burst(.1)
	check(flame.fuel_liters==0 and not flame.emitting,"final fractional fuel ends firing without negative capacity")
	flame.set_trigger_authoritative(true);flame.step_authoritative(.1)
	check(not flame.emitting,"empty tank cannot start")
	var can: WorldItemPickup=load("res://scenes/objects/items/fuel_can_pickup.tscn").instantiate()
	can.setup_spawn({"item_type":&"fuel_can","item_state":{"fuel_liters":1.25}});base.add_child(can)
	can.freeze=true;can.global_position=actor.global_position-actor.head.global_basis.z*1.3+Vector3.UP*.1
	await settle();aim(can.get_node("CollisionShape3D").global_position);await settle()
	check(actor.get_interaction_target()==can,"existing can is reachable through native R interaction ray")
	check(actor.get_reload_or_battery_action()==&"refuel_flamethrower","native R resolves to refuel for this held item")
	check(actor.perform_inventory_action_authoritative(&"refuel_flamethrower"),"R transfers available world-can fuel")
	check(is_equal_approx(flame.fuel_liters,1.25) and is_zero_approx(float(can.item_state.fuel_liters)),"refill conserves fuel and keeps an empty can")
	check(not actor.perform_inventory_action_authoritative(&"refuel_flamethrower"),"empty can cannot duplicate fuel")
	check(actor.get_inventory_snapshot().flame_fuel_liters==flame.fuel_liters,"refilled state enters ordinary player checkpoint data")
	# Finish an actual hive through the same jet path and preserve quest completion rules.
	can.queue_free();await settle(2);aim(hive.global_position+Vector3.UP*.95);await settle()
	burst(3)
	check(encounter.get_health(0)==0 and state.get_destroyed_cave_hive_count()==1,"fire destroys existing hive through authoritative quest health")
	check(not state.are_cave_hives_destroyed(),"one burning target cannot finish all three hives")
	var audio: AudioStreamWAV=flame.effect.get_node("Roar").stream
	check(audio.loop_mode==AudioStreamWAV.LOOP_FORWARD,"authored roar loops in imported resource")
	print("FLAMETHROWER FIRE CHECKS ",checks," FAILURES ",failures)
	base.queue_free();await process_frame;await process_frame;quit(1 if failures else 0)
