extends SceneTree
const SAVE := "user://monster_inspector_ai_regression.cfg"
var failures := 0
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures+=1
func settle(frames:int=4):
 for i in frames: await physics_frame
func park(monster:Node3D,point:Vector3,player:GamePlayer):
 monster.global_position=point
 monster.rotation=Vector3.ZERO
 monster.velocity=Vector3.ZERO
 monster._home=point
 monster._alert_target=null
 monster._awareness=0.0
 monster._sight_left=0.0
 monster._windup=0.0
 monster._attack_left=0.0
 monster._retreat_left=0.0
 player.global_position=point+Vector3(0,0,-4)
func run():
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,SAVE)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
 var base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base)
 await settle(90)
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 var encounter=base.get_node("ContainmentEncounter")
 var player:GamePlayer=get_first_node_in_group("local_player")
 player.set_physics_process(false)
 player.survival.set_physics_process(false)
 var data=state.get_snapshot()
 data.day_index=state.CONTAINMENT_DAY_INDEX
 state._broadcast_snapshot(data)
 encounter.navigation_ready=false
 var monsters:Array=[]
 for index in 3:
  var monster=encounter.get_node("Monster%d"%index)
  monster.set_physics_process(false)
  # Separate fixtures must not physically overlap during isolated AI checks.
  monster.collision_layer=0
  monster.collision_mask=1
  monster.ai_profile=monster.ai_profile.duplicate()
  monsters.append(monster)
  check(monster.get_node("Visual/Model")!=null and monster.get_node("CollisionShape3D").shape!=null,"native creature scene contains authored model and collision %d"%index)
 check(encounter.get_start_health()==[340.0,160.0,75.0],"initial health comes from per-creature Inspector profiles")
 check(monsters[2].ai_profile.chase_speed>monsters[1].ai_profile.chase_speed and monsters[1].ai_profile.chase_speed>monsters[0].ai_profile.chase_speed,"smily fastest, zombie slower, tail slowest")
 var point:=Vector3(1000,500,1000)
 for index in 3:
  var monster=monsters[index]
  park(monster,point,player)
  await settle()
  check(monster._can_see(player),"creature sees forward target %d"%index)
  monster.ai_profile.sight_enabled=false
  check(monster._find_target(0.1)==null,"Inspector disables sight %d"%index)
  monster.ai_profile.hearing_enabled=false
  monster.hear_noise(player,player.global_position,20.0)
  check(monster._alert_target==null,"Inspector disables hearing %d"%index)
  monster.ai_profile.hearing_enabled=true
  monster.hear_noise(player,player.global_position,20.0)
  check(monster._alert_target==player,"noise creates remembered target %d"%index)
  monster.ai_profile.sight_enabled=true
  monster._physics_process(0.1)
  check(is_equal_approx(Vector2(monster.velocity.x,monster.velocity.z).length(),monster.ai_profile.chase_speed),"chase uses configured speed %d"%index)
  park(monster,point,player)
  player.global_position=point+Vector3(0,0,-1.2)
  player.survival.debug_invincible=false
  player.survival.dead=false
  player.survival.health=100.0
  await settle()
  monster._physics_process(0.01)
  check(monster._windup>0.0,"attack windup starts %d"%index)
  monster._physics_process(monster.ai_profile.attack_windup+0.01)
  check(is_equal_approx(player.survival.health,100.0-monster.ai_profile.attack_damage),"attack uses Inspector damage %d"%index)
  if index==2:
   check(monster._retreat_left>0.0,"smily retreats after completed strike")
   monster._physics_process(0.1)
   check(monster.velocity.z>0.0,"smily moves away from victim during retreat")
  else:
   check(monster._retreat_left==0.0,"heavy pursuers do not use skirmisher retreat %d"%index)
 var tail=monsters[0]
 var fast=monsters[2]
 park(fast,point,player)
 fast.ai_profile.chase_speed=4.1
 await settle()
 fast._physics_process(0.1)
 check(is_equal_approx(Vector2(fast.velocity.x,fast.velocity.z).length(),4.1),"editing Inspector chase speed changes runtime movement")
 var wall:=StaticBody3D.new()
 var blocker:=CollisionShape3D.new()
 var box:=BoxShape3D.new()
 box.size=Vector3(4,4,0.2)
 blocker.shape=box
 wall.add_child(blocker)
 root.add_child(wall)
 wall.global_position=point+Vector3(0,1,-2)
 park(fast,point,player)
 await settle()
 check(not fast._can_see(player),"walls still block Inspector-configured sight")
 wall.queue_free()
 await settle()
 park(tail,point,player)
 player.global_position=point+Vector3(0,0,-tail.ai_profile.territory_radius-1)
 tail.ai_profile.sight_distance=50.0
 await settle()
 check(tail._find_target(0.1)==null and tail._patrol_goal==tail._home,"tail disengages beyond its territory and returns home")
 var zombie=monsters[1]
 park(zombie,point,player)
 player.global_position=point+Vector3(0,0,-21)
 await settle()
 check(zombie._find_target(0.1)==player,"zombie keeps pursuing rather than enforcing tail territory")
 encounter.damage_monster(0,40.0)
 check(encounter.get_monster_health(0)==300.0,"profile health is used by authoritative damage")
 var saved=state.get_snapshot()
 state._broadcast_snapshot(saved)
 check(encounter.get_monster_health(0)==300.0,"snapshot preserves damaged HP without resetting to profile maximum")
 for monster in monsters: monster.set_physics_process(false)
 player.survival.debug_invincible=true
 encounter.debug_spawn(2,1,point,Vector3.FORWARD,true)
 await settle()
 var debug_monsters=get_nodes_in_group("debug_spawned_monsters")
 check(debug_monsters.size()==1 and debug_monsters[0].debug_health==75.0 and debug_monsters[0].ai_profile.chase_speed==3.25,"console spawns use the same authored scene and type profile")
 if not debug_monsters.is_empty():
  debug_monsters[0].apply_weapon_damage(1000.0)
  await settle(6)
  check(debug_monsters[0].ragdoll!=null and debug_monsters[0].ragdoll.bodies.size()>0,"native creature scene still transitions to skeletal ragdoll on death")
 encounter.debug_clear_spawned()
 await settle()
 var pickup=load("res://scenes/objects/items/weapon_pickup.tscn").instantiate()
 pickup.item_type=&"pistol_ammo"
 pickup.item_state={"amount":12}
 pickup.push_resistance=7.5
 pickup.pickup_enabled=false
 root.add_child(pickup)
 pickup.global_position=player.global_position
 check(pickup.get_push_resistance()==7.5 and pickup.get_interaction_prompt().is_empty(),"item Inspector controls resistance and pickup availability")
 var ammo_before=player.weapon.pistol_ammo
 pickup.network_interact(player.owner_peer_id,player)
 check(player.weapon.pistol_ammo==ammo_before,"disabled pickup cannot transfer inventory")
 var light=load("res://scenes/objects/equipment/flashlight_pickup.tscn").instantiate()
 light.item_state={"battery_charge":0.37}
 light.setup_spawn({})
 check(is_equal_approx(light.item_state.battery_charge,0.37),"spawn fallback retains Inspector flashlight charge")
 light.free()
 pickup.queue_free()
 base.queue_free()
 await settle()
 DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
 print("RESULT FAILURES ",failures)
 quit(1 if failures else 0)
