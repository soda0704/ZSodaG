extends SceneTree
var failures=0
const SAVE="user://day_split_checkpoint_regression.cfg"
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures+=1
func settle():
 for i in 5: await physics_frame
func run():
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,SAVE)
 DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
 var base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base)
 root.get_node("GameMenu").force_close_menu()
 await settle()
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 var player:GamePlayer=get_first_node_in_group("network_players")
 player.set_physics_process(false)
 player.survival.set_physics_process(false)
 player.survival.debug_invincible=true
 var encounter=base.get_node("ContainmentEncounter")
 var elevator=base.get_node("Elevator_Functional_Blockout")
 var zone2:Area3D=base.get_node("Floor_Minus2_Life_Support_Blockout/InvestigationZone")
 var zone3:Area3D=base.get_node("Floor_Minus3_Biocontainment_Blockout/InvestigationZone")
 var snapshot=state.get_snapshot()
 snapshot.day_index=3
 snapshot.phase=BaseGameplayController.BasePhase.ACTIVE_DAY
 snapshot.fuel_delivered=true
 snapshot.fuel_liters=20.0
 snapshot.main_breaker_on=true
 snapshot.containment={}
 snapshot.maintenance={}
 state._broadcast_snapshot(snapshot)
 await settle()
 check(elevator.unlocked_floor_index==2,"day 3 unlocks only level 2")
 check(not state.can_end_current_day(),"day 3 requires its own investigation")
 check(not encounter.get_node("Monster0").visible and encounter.get_node("Monster0").collision_layer==0,"story enemies inactive before containment day")
 player.global_position=zone3.global_position
 await settle()
 check(not state.containment.get("level3",false),"wrong-day visit cannot complete level 3")
 player.global_position=zone2.global_position
 await settle()
 check(state.containment.get("level2",false) and state.can_end_current_day(),"editable area completes temporary level 2 visit")
 check(elevator.unlocked_floor_index==2,"visiting level 2 does not unlock level 3 that day")
 check(state.set_end_day_ready_authoritative(1,true) and state.set_peer_sleeping_authoritative(1,true),"level 2 day permits normal sleep consensus")
 check(state.advance_day_authoritative(),"sleep advances to separate containment day")
 check(state.day_index==4 and elevator.unlocked_floor_index==3,"day 4 unlocks level 3")
 check(encounter.get_node("Monster0").visible,"story enemies active on day 4")
 for i in 3: encounter.damage_monster(i,1000)
 check(state.containment.get("fault",false),"clearing level still triggers existing power fault")
 check(encounter.cycle_breaker(1),"power fault accepts breaker off")
 var journal=get_root().get_node("QuestJournal")
 journal._bind_controller()
 journal._refresh_content()
 check(journal.tasks_label.text.contains("Питание отключено"),"journal explains loss of power")
 check(encounter.cycle_breaker(1),"breaker on resolves existing fault")
 check(not state.can_end_current_day(),"resolved fault alone cannot skip visiting level 3")
 player.global_position=zone3.global_position
 await settle()
 check(state.containment.get("level3",false) and state.can_end_current_day(),"day 4 requires visit and resolved clearance")
 journal._refresh_content()
 check(journal.tasks_label.text.contains("Зачистить уровень") and not journal.tasks_label.text.contains("3/3"),"journal uses clearance objective without monster count")
 state.save_progress_authoritative()
 var last:int=state._last_checkpoint_msec
 var before:float=state.fuel_liters
 state._process(5.0)
 check(state.fuel_liters<before and state._last_checkpoint_msec==last,"fuel replication does not write a second regular checkpoint")
 state.save_progress_authoritative(true)
 check(state._last_checkpoint_msec==last,"regular save skips recent important checkpoint")
 state._last_checkpoint_msec-=6000
 state.save_progress_authoritative(true)
 var config=ConfigFile.new()
 config.load(SAVE)
 check(absf(float(config.get_value("base","fuel_liters"))-state.fuel_liters)<0.001,"single periodic checkpoint includes current fuel")
 check(int(config.get_value("base","campaign_layout_version",0))==2,"new saves record split campaign layout")
 config.set_value("base","campaign_layout_version",1)
 config.set_value("base","day_index",3)
 config.set_value("base","containment",{"level3":true,"health":[0.0,0.0,0.0],"resolved":true})
 config.save(SAVE)
 var restored=state.load_saved_snapshot()
 check(restored.day_index==4 and restored.containment.resolved,"old combat checkpoint keeps progress on new day 4")
 config.set_value("base","day_index",4)
 config.save(SAVE)
 check(state.load_saved_snapshot().day_index==5,"old post-combat day moves past split encounter")
 state.progress_persistence_enabled=false
 print("RESULT FAILURES ",failures)
 quit(0 if failures==0 else 1)
