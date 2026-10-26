extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://polish_test_%d.cfg" % OS.get_process_id())
 BaseGameplayController.save_scope="solo"
 run.call_deferred()
func check(value:bool,label:String) -> void:
 checks+=1
 if not value: failures+=1
 print("PASS " if value else "FAIL ",label)
func settle() -> void:
 for i in 8: await physics_frame
func run() -> void:
 Engine.max_fps=120
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
 root.add_child(base);current_scene=base
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 state.progress_persistence_enabled=false;state.set_process(false)
 await settle()
 root.get_node("GameMenu").force_close_menu()
 var player:GamePlayer=get_first_node_in_group("local_player")
 player.set_physics_process(false);player.survival.set_physics_process(false)
 var bunk:BaseEndDayBunk=base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
 check(bunk.get_interaction_hint_for(player).begins_with("Вы не можете сейчас спать"),"unfinished day explains sleep without a false E action")
 check(absf(bunk.global_basis.z.x)>0.99,"bed length runs along wall")
 state.main_breaker_on=true;state.elevator_backup_installed=true;state.phase=BaseGameplayController.BasePhase.ACTIVE_DAY
 player.teleport_authoritative(bunk.wake_pose.global_position,0)
 bunk.network_interact(1,player)
 check(state.is_peer_sleeping(1) and player.is_sleeping_in_bunk(),"one interaction lies down without separate readiness")
 check(bunk.cancel_sleep_authoritative(1,player) and not state.is_peer_sleeping(1),"waiting sleeper can get out and withdraw sleep vote")
 print("WAKE ",player.global_position," marker ",bunk.wake_pose.global_position," bunk ",bunk.global_position)
 check(bunk.wake_pose.global_position.z>bunk.global_position.z,"wake marker is inside room")
 var gate:Node
 for n in base.find_children("*","Node3D",true,false):
  if n.get_script()!=null and n.get_script().resource_path.ends_with("garage_gate.gd"): gate=n;break
 check(gate!=null and gate.required_operators()==1,"solo gate accepts one operator")
 gate.set_physics_process(false)
 gate.opening_seconds=0.2
 player.teleport_authoritative(gate.handles[0].global_position+Vector3(0,0,1),0)
 await settle()
 check(gate._valid_operator(1,0),"gate handle accepts nearby actual player")
 for i in 3:
  gate._hold(1,0);gate._physics_process(0.1)
 check(gate.progress==1.0 and state.maintenance.garage_open,"holding opens gate in solo")
 gate.animation.advance(gate.animation.current_animation_length+0.1)
 await settle()
 gate._holds.clear();gate._physics_process(0.4)
 for i in 3:
  gate._hold(1,0);gate._physics_process(0.1)
 check(gate.progress==0.0 and not state.maintenance.garage_open,"second hold closes gate")
 BaseGameplayController.save_scope="coop"
 check(gate.required_operators()==2,"coop still requires two different operators")
 BaseGameplayController.save_scope="solo"
 player._has_flashlight=true;player._battery_charge=0.22
 check(player.pickup_world_item_authoritative(&"flashlight",{"battery_charge":0.82}),"new flashlight swaps existing loose flashlight")
 check(is_equal_approx(player._battery_charge,0.82),"swap restores picked-up lamp charge")
 player.apply_held_item_inventory(&"m4a1",{})
 player.weapon.apply_state(&"m4a1",12,0)
 player.weapon.rifle_magazines.assign([30])
 player._spare_batteries.assign([1.0])
 player.weapon_light_mounted=true;player._battery_charge=0.4
 player._begin_inventory_action(&"reload_or_battery")
 check(player.weapon.reload_left>0 and not player._battery_action_busy,"charged mounted light gives R priority to rifle magazine")
 player.weapon.reload_left=0;player._battery_charge=0.0
 player._begin_inventory_action(&"reload_or_battery")
 check(player._battery_action_busy,"empty mounted light gives R priority to battery")
 var encounter=base.get_node("ContainmentEncounter")
 check(encounter.navigation_ready and encounter.region.navigation_mesh.get_polygon_count()>0,"encounter uses pre-baked navigation")
 var console=root.get_node("DeveloperConsole")
 console._submit("/help");console._submit("/clear")
 check(console.output.text.is_empty() and console.history.is_empty(),"clear removes submitted commands and output")
 check(not console.get_node("Panel/Box/Commands").text.is_empty(),"clear retains command suggestions")
 var graphics=load("res://scripts/ui/graphics_quality.gd")
 var low:Dictionary=graphics.recommended("Intel UHD Graphics",2073600)
 var dedicated:Dictionary=graphics.recommended("NVIDIA RTX",8294400)
 check(low.Scale==75 and low.FPS==60,"integrated GPU gets conservative 60 FPS recommendation")
 check(dedicated.Scale<=67,"4K recommendation reduces rendering resolution")
 check(is_equal_approx(state.FUEL_PER_SECOND,0.015),"generator consumes 1.5 times previous fuel rate")
 base.queue_free();await process_frame
 print("GAMEPLAY POLISH CHECKS ",checks," FAILURES ",failures)
 quit(0 if failures==0 else 1)
