extends Node
var host := false
var world: Node3D
var report: Dictionary = {}
var failures := 0
func _ready(): run.call_deferred()
func check(ok: bool, label: String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures += 1
func pause(seconds: float): await get_tree().create_timer(seconds).timeout
func snapshot() -> Dictionary:
 var result := {}
 for item in world.world_items.get_children():
  result[str(item.name)] = {"type":item.item_type,"position":item.global_position,"basis":item.global_basis,"state":item.item_state}
 return result
@rpc("authority","call_remote","reliable")
func request_report(): receive_report.rpc_id(1,snapshot())
@rpc("any_peer","call_remote","reliable")
func receive_report(data: Dictionary):
 if host: report = data
@rpc("authority","call_remote","reliable")
func finish(code: int):
 print("PROP CLIENT COMPLETE ",code)
 get_tree().quit(code)
func run():
 host = OS.get_cmdline_user_args().has("--host")
 Engine.max_fps = 60
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://prop-review-%s-%d.cfg"%["host" if host else "client",Time.get_ticks_usec()])
 get_tree().root.get_node("GameMenu").force_close_menu()
 var input_service = get_tree().root.get_node("SteamInput")
 input_service.set_process(false);input_service.set_process_input(false);input_service.native_input_available=false
 world = load("res://scenes/levels/base_session.tscn").instantiate()
 get_tree().root.add_child(world)
 var peer := ENetMultiplayerPeer.new()
 var result := peer.create_server(28759,1,4) if host else peer.create_client("127.0.0.1",28759,4)
 check(result==OK,"ENet transport")
 multiplayer.multiplayer_peer = peer
 if not host: return
 world._on_session_ready(true)
 var deadline := Time.get_ticks_msec()+25000
 while world.players.get_child_count()<2 and Time.get_ticks_msec()<deadline: await pause(.1)
 check(world.players.get_child_count()==2,"host and client joined actual BaseSession")
 world._enter_v3_level.rpc()
 deadline = Time.get_ticks_msec()+40000
 while (not world._v3_items_spawned or world._v3_ready_peers.is_empty()) and Time.get_ticks_msec()<deadline: await pause(.1)
 check(world._v3_items_spawned and not world._v3_ready_peers.is_empty(),"both clients loaded actual base")
 await pause(4)
 request_report.rpc()
 deadline = Time.get_ticks_msec()+10000
 while report.is_empty() and Time.get_ticks_msec()<deadline: await pause(.1)
 var expected := snapshot()
 check(report.size()==expected.size(),"replicated pickup count: %d / %d"%[report.size(),expected.size()])
 var cans := 0
 var knives := 0
 var good := not report.is_empty()
 for key in expected:
  var item: Dictionary = expected[key]
  if item.type==&"fuel_can":
   cans += 1
   check(item.position.x < -26 and item.position.x > -38 and item.position.z > -8 and item.position.z < 8,"fuel can inside garage")
  if item.type==&"kitchen_knife": knives += 1
  if not report.has(key): good=false;continue
  good = good and item.position.distance_to(report[key].position)<.04 and item.basis.is_equal_approx(report[key].basis) and item.state==report[key].state
 check(cans==3 and knives==2,"three garage cans and two kitchen knives")
 check(good,"client sees host positions, rotations and item states")
 world.set_process(false)
 var controller: BaseGameplayController = world._base_gameplay_controller
 controller.progress_persistence_enabled = false
 var old := {"players":{},"pickups":[],"weapon_layout_version":1,"fuel_layout_version":1,"tools_layout_version":1,"discoverable_layout_version":2,"tape_layout_version":1}
 var old_items := [
  [&"pistol",Vector3(-29.7,1.04,7.05)], [&"m4a1",Vector3(-7.35,1.04,22.5)],
  [&"kitchen_knife",Vector3(11.6,1.03,-7.35)],[&"rifle_magazine",Vector3(-7.35,1.04,23.2)],
  [&"tape",Vector3(-7,1.04,22.8)],[&"flashlight",Vector3(4.6,.03,-4.8)],
  [&"fuel_can",Vector3(-3.2,.3,19.2)],[&"fuel_can",Vector3(-2.2,.3,19.2)],
  [&"fuel_can",Vector3(-2.2,.3,20)],[&"m4a1",Vector3(5,.2,15)]
 ]
 for entry in old_items:
  old.pickups.append({"item_type":entry[0],"transform":Transform3D(Basis.IDENTITY,entry[1]),"item_state":{"review_token":47},"in_cabin":false})
 for item in world.world_items.get_children(): item.queue_free()
 await get_tree().process_frame
 controller.inventory_checkpoint = old
 world._v3_items_spawned = false
 world.spawn_v3_world_items()
 check(world.world_items.get_child_count()==15,"old checkpoint migrated with exactly five extra props")
 var untouched := false
 for item in world.world_items.get_children():
  if item.item_type==&"m4a1" and item.global_position.distance_to(Vector3(5,.2,15))<.001: untouched=true
 check(untouched,"already moved item is preserved")
 var saved: Dictionary = world.capture_inventory_checkpoint()
 check(saved.get("prop_layout_version",0)==1,"new layout version captured")
 for item in world.world_items.get_children(): item.queue_free()
 await get_tree().process_frame
 controller.inventory_checkpoint = saved
 world._v3_items_spawned = false
 world.spawn_v3_world_items()
 check(world.world_items.get_child_count()==15,"second restore does not duplicate added props")
 print("PROP HOST COMPLETE failures ",failures)
 finish.rpc(failures)
 await pause(.2)
 get_tree().quit(failures)
