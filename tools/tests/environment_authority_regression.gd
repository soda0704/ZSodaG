extends SceneTree
var checks:=0
var failures:=0
func _initialize():
 var prefix:="user://environment_authority_%d"%OS.get_process_id()
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
 ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
 ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
 create_timer(100).timeout.connect(func():quit(2));run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func settle():
 for i in 35:await process_frame
func run():
 Engine.max_fps=60
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for i in 30:await physics_frame
 root.get_node("GameMenu").force_close_menu()
 var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.body_animator.hide()
 base.get_node("BaseGameplayController").set_process(false);base.get_node("SnowExterior/Blizzard").enabled=false
 var node:WorldEnvironment=base.get_node("SnowExterior/OvercastDayEnvironment")
 var source:Environment=node.environment
 var lighting:WorldLighting=base.get_node("WorldLighting")
 var quality=root.get_node("GameMenu/GraphicsQuality");quality.set_process(false)
 var camera:=Camera3D.new();base.add_child(camera);camera.position=Vector3(-55,2,12);camera.current=true
 for i in 90:await process_frame
 check(camera.environment!=source,"camera adjustments do not mutate the node's authored resource")
 check(is_equal_approx(lighting.outdoor_ambient,source.ambient_light_energy) and is_equal_approx(camera.environment.ambient_light_energy,source.ambient_light_energy),"exterior ambient follows the Environment node, without the former 1.0 override")
 var authored_ao:=source.ssao_enabled;var authored_glow:=source.glow_enabled;var authored_fog:=source.volumetric_fog_enabled
 quality.set_advanced_lighting_enabled(false);await settle()
 check(source.ssao_enabled==authored_ao and source.glow_enabled==authored_glow and source.volumetric_fog_enabled==authored_fog,"Basic mode leaves the authored WorldEnvironment untouched")
 check(not camera.environment.ssao_enabled and not camera.environment.glow_enabled and not camera.environment.volumetric_fog_enabled,"Basic mode disables costly effects on the runtime environment")
 quality.set_advanced_lighting_enabled(true);await settle()
 check(camera.environment.ssao_enabled==authored_ao and camera.environment.glow_enabled==authored_glow,"Advanced mode restores only the effects authored in the node")
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 var stable_ambient:=true
 for advanced in [false,true]:
  quality.set_advanced_lighting_enabled(advanced)
  for powered in [true,false]:
   var snapshot=state.get_snapshot();snapshot.main_breaker_on=powered;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.0;state._broadcast_snapshot(snapshot)
   for point in [Vector3(-39,1.7,3),Vector3(-35.6,1.7,3),Vector3(-5,1.75,0),Vector3(-30,-30,0)]:
    camera.position=point
    for frame in 8:lighting._process(.2);await process_frame
    stable_ambient=stable_ambient and is_equal_approx(camera.environment.ambient_light_energy,source.ambient_light_energy) and is_equal_approx(camera.environment.adjustment_contrast,source.adjustment_contrast)
 check(stable_ambient,"entrance, hub, lower floor and power changes never darken the complete image in either quality mode")
 camera.position=Vector3(-55,2,12);await settle()
 source.ssao_enabled=false;source.glow_enabled=false;source.ambient_light_energy=.19
 source.adjustment_enabled=true;source.adjustment_brightness=.8;source.adjustment_contrast=1.12;source.adjustment_saturation=.73
 source.adjustment_color_correction=load("res://assets/environments/calibration/gamma_120.tres")
 source.emit_changed();await settle()
 check(not camera.environment.ssao_enabled and not camera.environment.glow_enabled,"turning effects off in the node takes precedence over Advanced")
 check(is_equal_approx(camera.environment.ambient_light_energy,.19),"live changes to authored ambient reach the active camera")
 check(is_equal_approx(camera.environment.adjustment_brightness,.8) and is_equal_approx(camera.environment.adjustment_contrast,1.12) and is_equal_approx(camera.environment.adjustment_saturation,.73),"neutral graphics settings preserve authored colour grading")
 check(camera.environment.adjustment_color_correction==source.adjustment_color_correction,"neutral gamma retains the node's colour correction")
 var settings:Dictionary=quality.values.duplicate();settings.Brightness=110;quality.apply(settings);await settle()
 check(is_equal_approx(camera.environment.adjustment_brightness,.88) and is_equal_approx(source.adjustment_brightness,.8),"player brightness multiplies the authored brightness without overwriting it")
 var replacement:=source.duplicate() as Environment;replacement.ambient_light_energy=.23;node.environment=replacement;await settle()
 check(is_equal_approx(camera.environment.ambient_light_energy,.23) and camera.environment!=replacement,"replacing the Environment resource rebinds the current camera")
 var optional:=Environment.new();optional.ssr_enabled=true;optional.ssil_enabled=true;optional.sdfgi_enabled=true
 var runtime:Environment=quality.make_environment_copy(optional);quality.apply_environment(runtime)
 check(runtime.ssr_enabled and runtime.ssil_enabled and runtime.sdfgi_enabled,"Advanced honours explicitly authored reflection and GI effects")
 quality.set_advanced_lighting_enabled(false);quality.apply_environment(runtime)
 check(not runtime.ssr_enabled and not runtime.ssil_enabled and not runtime.sdfgi_enabled and optional.ssr_enabled,"Basic suppresses optional GI/reflections only on the runtime copy")
 current_scene=null;base.queue_free()
 for i in 6:await process_frame
 print("ENVIRONMENT AUTHORITY CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
