extends SceneTree
# Regression for the requested removal of the synthetic doorway fill.
var failures:=0
var checks:=0
var output:="res://tools/.local/snow-material-review/entrance/"
func _initialize():
 var prefix:="user://entrance_daylight_%d"%OS.get_process_id()
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
 ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
 ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
 if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
 create_timer(110).timeout.connect(func():quit(2));run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func shot(label:String)->Image:
 await create_timer(.6).timeout;await RenderingServer.frame_post_draw
 var image:=root.get_texture().get_image();image.save_png(output+label+".png");return image
func run():
 DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,720);Engine.max_fps=60
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for frame in 25:await physics_frame
 root.get_node("GameMenu").force_close_menu()
 var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false)
 actor.body_animator.visible=false;actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
 var state:BaseGameplayController=base.get_node("BaseGameplayController");state.set_process(false)
 var snapshot=state.get_snapshot();snapshot.main_breaker_on=false;state._broadcast_snapshot(snapshot)
 var lighting:WorldLighting=base.get_node("WorldLighting");lighting.set_process(false)
 lighting.get_node("Emergency").hide()
 base.get_node("SnowExterior/Blizzard").enabled=false
 var manager=base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
 var door=base.get_node("Floor_0_Base_Blockout/Doors/West_Pedestrian_Exterior_Door_Visual_Prototype")
 check(not lighting.has_node("ExteriorDaylight"),"synthetic vestibule daylight source has been removed")
 check(lighting.get_node("Standard").get_child_count()==143 and lighting.get_node("Emergency").get_child_count()==121,"both circuits contain the rebuilt source layout")
 var world_suns:=0
 for source in root.find_children("*","DirectionalLight3D",true,false):
  if source.get_world_3d()==base.get_world_3d() and source.is_visible_in_tree() and source.light_energy>0:
   world_suns+=1
 check(world_suns==1,"only one active directional source illuminates the game world")
 var camera:=Camera3D.new();base.add_child(camera);camera.current=true;camera.position=Vector3(-35.6,1.7,3);camera.look_at(Vector3(-37.5,.4,3));camera.fov=85
 manager.debug_set_door_open(door,true);await create_timer(1.2).timeout
 for advanced in [false,true]:
  var mode:="advanced" if advanced else "basic"
  root.get_node("GameMenu/GraphicsQuality").set_advanced_lighting_enabled(advanced)
  for frame in 60:lighting._process(1.0/60);await process_frame
  await shot("entrance-"+mode+"-open")
  check(manager.is_door_open_at(door) and not lighting.has_node("ExteriorDaylight/EntranceSky"),"opening real door does not recreate synthetic light in "+mode)
  manager.debug_set_door_open(door,false);await create_timer(1.2).timeout
  for frame in 60:lighting._process(1.0/60);await process_frame
  await shot("entrance-"+mode+"-closed")
  check(not manager.is_door_open_at(door) and not state.main_breaker_on,"door and unpowered circuit still function in "+mode)
  manager.debug_set_door_open(door,true);await create_timer(1.2).timeout
 current_scene=null;base.queue_free()
 for frame in 8:await process_frame
 print("ENTRANCE DAYLIGHT CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
