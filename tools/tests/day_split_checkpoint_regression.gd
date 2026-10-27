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
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
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
 var zone3:Area3D=base.get_node("Floor_Minus4_Biocontainment_Blockout/InvestigationZone")
 var trials:Area3D=base.get_node("Floor_Minus3_Trials_Observation_Blockout/InvestigationZone")
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
 check(state.advance_day_authoritative(),"sleep advances to separate trials day")
 check(state.day_index==4 and elevator.unlocked_floor_index==3,"day 4 opens only trials level 3")
 check(not encounter.get_node("Monster0").visible,"story enemies remain inactive on trials day")
 check(not state.can_end_current_day(),"trials day requires its own investigation")
 player.global_position=zone3.global_position
 await settle()
 check(not state.containment.get("level3",false),"containment visit on trials day cannot skip next objective")
 player.global_position=trials.get_parent().to_global(Vector3(-28,0.1,0))
 await settle()
 check(not state.containment.get("trials",false),"control room behind glass does not complete chamber visit")
 var journal=get_root().get_node("QuestJournal")
 journal._bind_controller()
 journal._refresh_content()
 check(journal.tasks_label.text.contains("испытательную камеру"),"journal directs day 4 to the chamber")
 player.global_position=trials.global_position
 await settle()
 check(state.containment.get("trials",false) and state.can_end_current_day(),"entering authored chamber area completes trials day")
 state.save_progress_authoritative()
 var trial_save=state.load_saved_snapshot()
 check(trial_save.day_index==4 and trial_save.containment.get("trials",false),"new save retains trials progress")
 check(state.set_end_day_ready_authoritative(1,true) and state.set_peer_sleeping_authoritative(1,true),"trials day permits normal sleep consensus")
 check(state.advance_day_authoritative(),"sleep advances to containment day")
 check(state.day_index==5 and elevator.unlocked_floor_index==4,"day 5 opens containment level 4")
 check(encounter.get_node("Monster0").visible,"story enemies active on day 5")
 player.global_position=zone2.global_position
 await settle()
 for i in 3: encounter.damage_monster(i,1000)
 check(state.containment.get("fault",false),"clearing level still triggers existing power fault")
 check(encounter.cycle_breaker(1),"power fault accepts breaker off")
 journal._refresh_content()
 check(journal.tasks_label.text.contains("Питание отключено"),"journal explains loss of power")
 check(encounter.cycle_breaker(1),"breaker on resolves existing fault")
 check(not state.can_end_current_day(),"resolved fault alone cannot skip visiting level 3")
 player.global_position=zone3.global_position
 await settle()
 check(state.containment.get("level3",false) and state.can_end_current_day(),"day 5 requires visit and resolved clearance")
 journal._refresh_content()
 check(journal.tasks_label.text.contains("Зачистить уровень") and not journal.tasks_label.text.contains("3/3"),"journal uses clearance objective without monster count")
 state.save_progress_authoritative()
 var last=FileAccess.get_file_as_string(SAVE)
 var before:float=state.fuel_liters
 state._process(5.0)
 check(state.fuel_liters<before and FileAccess.get_file_as_string(SAVE)==last,"fuel replication does not write the world")
 check(not state.save_progress_authoritative(true),"periodic checkpoint requests are disabled")
 check(FileAccess.get_file_as_string(SAVE)==last,"rejected periodic write preserves the manual save")
 check(state.set_end_day_ready_authoritative(1,true) and state.set_peer_sleeping_authoritative(1,true),"containment day permits normal sleep consensus")
 check(state.advance_day_authoritative(),"sleep after containment advances to shaft day")
 check(state.day_index==6 and elevator.unlocked_floor_index==5,"day 6 opens expedition shaft level 5")
 for floor_index in 6:
  check(not elevator.get_button_prompt(floor_index,false).contains("закрыт"),"day 6 keeps older floor %d accessible" % floor_index)
 check(not state.can_end_current_day() and not state.advance_day_authoritative(),"unfinished shaft day cannot auto-complete the cave story")
 state.save_progress_authoritative()
 check(state.load_saved_snapshot().day_index==6,"new saves support shaft day 6")
 snapshot=state.get_snapshot()
 snapshot.day_index=7
 state._broadcast_snapshot(snapshot)
 await settle()
 check(state.day_index==7 and elevator.unlocked_floor_index==5 and elevator.MAX_FLOOR_INDEX==5,"cave day 7 adds no main elevator stop")
 state.save_progress_authoritative()
 check(state.load_saved_snapshot().day_index==7,"new saves support reserved cave day 7")
 journal._refresh_content()
 check(journal.tasks_label.text.contains("продолжение шахты") and not state.can_end_current_day(),"day seven journal directs exploration beneath the complex")
 state.progress_persistence_enabled=false
 print("RESULT FAILURES ",failures)
 quit(0 if failures==0 else 1)
