extends SceneTree
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
func luminance(image:Image)->float:
 var total:=0.0;var n:=0
 # Lower wall/floor away from the visible sky and HUD.
 for y in range(430,600,3):
  for x in range(300,900,3):total+=image.get_pixel(x,y).get_luminance();n+=1
 return total/n
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
 var lamp:SpotLight3D=lighting.get_node("ExteriorDaylight/EntranceSky")
 var camera:=Camera3D.new();base.add_child(camera);camera.current=true;camera.position=Vector3(-35.6,1.7,3);camera.look_at(Vector3(-37.5,.4,3));camera.fov=85
 manager.debug_set_door_open(door,true);await create_timer(1.2).timeout
 for advanced in [false,true]:
  var mode:="advanced" if advanced else "basic"
  root.get_node("GameMenu/GraphicsQuality").set_advanced_lighting_enabled(advanced)
  for frame in 60:lighting._process(1.0/60);await process_frame
  var opened:=luminance(await shot("entrance-"+mode+"-open"))
  check(lamp.light_energy>1 and lamp.shadow_enabled,"open entrance receives shadowed daylight without base power in "+mode)
  lighting.set_lamp_modulation(lamp,0)
  var control:=luminance(await shot("entrance-"+mode+"-no-daylight-control"))
  print("ENTRANCE LUMINANCE ",mode," daylight=",opened," control=",control)
  check(opened>control+.01,"real doorway fill visibly lights vestibule geometry in "+mode)
  manager.debug_set_door_open(door,false);await create_timer(1.2).timeout
  for frame in 60:lighting._process(1.0/60);await process_frame
  await shot("entrance-"+mode+"-closed")
  check(lamp.light_energy<.001,"closed real door removes entrance daylight in "+mode)
  manager.debug_set_door_open(door,true);await create_timer(1.2).timeout
 current_scene=null;base.queue_free()
 for frame in 8:await process_frame
 print("ENTRANCE DAYLIGHT CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
