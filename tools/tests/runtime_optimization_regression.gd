extends SceneTree
## Exercise real UI lifecycle and item publication, including elevator movement.
var checks := 0
var failures := 0
class CountedPickup extends WorldItemPickup:
 var publications := 0
 func sync_physics_state() -> void:
  publications += 1
  super.sync_physics_state()
func _initialize():
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://runtime_optimization_regression.cfg")
 ProjectSettings.set_setting("northern_lab/testing/settings_path","user://runtime_optimization_regression.json")
 run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func run():
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for i in 8:await physics_frame
 var state=base.get_node("BaseGameplayController");state.progress_persistence_enabled=false;state.set_process(false)
 var terminal=base.get_node("Floor_0_Base_Blockout/DayTwoTaskTerminal")
 var ui=terminal.ui.get_node("Overlay/LabClicker")
 terminal.ui.select_app(false)
 check(not ui.is_processing() and not ui.get_node("IdleAnimation").is_playing(),"hidden app stops presentation processing and idle animation")
 state.clicker.restore({"samples":1000.0,"owned":{"pipette":3,"assistant":4}})
 state.clicker_changed.emit()
 terminal.ui.select_app(true)
 check(ui.is_processing() and ui.get_node("IdleAnimation").is_playing(),"showing app resumes presentation")
 check(ui.get_node("CounterPanel/Balance").text=="1K","hidden economy changes refresh immediately on reveal")
 var card=ui._cards[&"pipette"]
 check(card.available and card.get_node("Owned").text=="OWNED 3","correct affordability and ownership after reveal")
 check(card.get_node("Buy").text.begins_with(LabClicker.format_number(state.clicker.cost(&"pipette"))),"display price agrees with authoritative economy")
 state.clicker.samples=0;ui.refresh()
 check(not card.available,"cached card invalidates when affordability changes")
 state.clicker.owned["pipette"]=999;ui.refresh()
 check(card.get_node("Buy").text=="MAX" and card.get_node("Buy").disabled,"cached card respects upgrade cap")
 var notifications=[0]
 state.clicker_changed.connect(func():notifications[0]+=1)
 terminal.ui.select_app(false);state.main_breaker_on=true;state.clicker.restore({});state._last_clicker_sync.clear()
 for i in 20:state._process_clicker(0.21)
 check(notifications[0]==1,"idle economy publishes once instead of identical updates at 5 Hz")
 state.clicker.owned["assistant"]=1
 var before=state.clicker.samples
 for i in 20:state._process_clicker(0.21)
 check(is_equal_approx(state.clicker.samples-before,4.2) and notifications[0]==21,"passive income remains delta based and replicated at 5 Hz")
 var item=CountedPickup.new();item.freeze=true;base.add_child(item);item.set_physics_process(false)
 item.global_position=Vector3(50,2,50)
 for i in 100:item._physics_process(0.11)
 check(item.publications >= 5 and item.publications <= 6,"stationary pickup keeps a 2-second packet-loss recovery heartbeat instead of 100 repeated packets")
 var stationary_sent=item.publications
 item.global_position.x+=0.25;item._physics_process(0.11)
 check(item.publications==stationary_sent+1,"moving item still publishes at normal physics cadence")
 item.sync_physics_state()
 check(item.publications==stationary_sent+2,"explicit final/drag publication bypasses deduplication")
 var cabin=Node3D.new();base.add_child(cabin);item._cargo_cabin=cabin;item._cargo_pose=Transform3D.IDENTITY
 item._physics_process(0.11);var sent=item.publications
 cabin.position.x+=1;item._physics_process(0.11)
 check(item.publications==sent+1 and item.global_position==cabin.global_position,"moving cabin still carries and replicates frozen cargo")
 item.queue_free();cabin.queue_free()
 var player=get_first_node_in_group("local_player")
 player._has_flashlight=true;player._battery_charge=0.62;player._spare_batteries.assign([0.8])
 var journal=root.get_node("QuestJournal")
 journal._refresh_inventory();var last=journal._last_inventory_view.duplicate(true)
 player._battery_charge=0.621;journal._refresh_inventory()
 check(journal._last_inventory_view==last,"journal ignores invisible sub-percent battery changes")
 player._battery_charge=0.59;journal._refresh_inventory()
 check(journal._cards[&"flashlight"].get_node("Content/Detail").text=="59%","visible battery percent still updates")
 journal._select_item(&"battery")
 check(journal.inventory_label.text.contains("80%"),"selection refreshes cached journal immediately")
 player.weapon.pistol_ammo=24;player.weapon.rifle_magazines.assign([30,17])
 journal._refresh_inventory()
 check(journal._cards[&"pistol_ammo"].visible and journal._cards[&"pistol_ammo"].detail.text=="×24","ammo artwork card tracks loose reserve")
 check(journal._cards[&"rifle_magazine"].visible and journal._cards[&"rifle_magazine"].detail.text=="×2","magazine artwork card tracks reserve count")
 journal._select_item(&"rifle_magazine")
 check(journal.inventory_label.text.contains("30, 17") and not journal.drop_button.visible,"magazine inspection shows individual rounds without wrong held-item drop action")
 var held=player._held_item_type;journal._drop_selected()
 check(player._held_item_type==held and player.weapon.rifle_magazines.size()==2,"reserve-card drop cannot discard a different held item")
 player.weapon.pistol_ammo=0;player.weapon.rifle_magazines.clear();journal._refresh_inventory()
 check(not journal._cards[&"pistol_ammo"].visible and not journal._cards[&"rifle_magazine"].visible,"empty reserves hide their artwork cards")
 print("OPTIMIZATION CHECKS ",checks," FAILURES ",failures)
 quit(1 if failures else 0)
