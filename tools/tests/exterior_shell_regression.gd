extends SceneTree
var checks:=0
var failures:=0
var output:="res://tools/.local/blizzard-review/shell-review/"
func _initialize():
 var prefix:="user://shell_%d"%OS.get_process_id()
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
 ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
 ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
 if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
 create_timer(90).timeout.connect(func():quit(2))
 run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func settle():
 await create_timer(1.0).timeout
 await RenderingServer.frame_post_draw
func capture(label:String):
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+label+".png")
func run():
 DirAccess.make_dir_recursive_absolute(output)
 Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for frame in 25:await physics_frame
 root.get_node("GameMenu").force_close_menu()
 var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false)
 base.get_node("BaseGameplayController").set_process(false)
 var shell=base.get_node("Floor_0_Base_Blockout/ArcticBase_ExteriorShell")
 var body=shell.get_node("ShellBody")
 check(body.get_node("CollisionShape3D").shape is ConcavePolygonShape3D,"static shell collision preserves concave doorway apertures")
 var space=base.get_world_3d().direct_space_state
 for ray in [[Vector3(-25,1.7,-14),Vector3(-25,1.7,-7)],[Vector3(-25,1.7,14),Vector3(-25,1.7,7)],[Vector3(23,1.7,-14),Vector3(23,1.7,-7)],[Vector3(23,1.7,14),Vector3(23,1.7,7)],[Vector3(-14,1.7,-20),Vector3(-7,1.7,-20)],[Vector3(14,1.7,20),Vector3(7,1.7,20)]]:
  var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(ray[0],ray[1],1,[actor.get_rid()]))
  check(not hit.is_empty() and hit.collider==body,"outer hull blocks approach at "+str(ray[0]))
 actor.teleport_authoritative(Vector3(-25,.1,-12),0)
 await physics_frame
 var collision:=KinematicCollision3D.new()
 check(actor.test_move(actor.global_transform,Vector3(0,0,5),collision) and collision.get_collider()==body,"actual player capsule cannot walk through north side of west wing")
 # Isolate the shell, so existing door leaves do not invalidate aperture tests.
 var other_layers:Dictionary={}
 for candidate in base.find_children("*","CollisionObject3D",true,false):
  if candidate!=body:other_layers[candidate]=candidate.collision_layer;candidate.collision_layer=0
 await physics_frame
 for z in [3.0,-2.5]:
  var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-42,1.7,z),Vector3(-37,1.7,z),1))
  check(hit.is_empty(),"shell leaves real entry aperture open at z="+str(z))
 for candidate in other_layers:candidate.collision_layer=other_layers[candidate]
 await physics_frame
 var weather=base.get_node("SnowExterior/Blizzard")
 actor.teleport_authoritative(Vector3(-41,.1,-11.7),-PI/2);actor.camera.rotation=Vector3.ZERO
 weather.gust_period=1000000;weather._elapsed=0
 await settle()
 var new_min=weather.fog_material.get_shader_parameter("clear_min")
 var new_max=weather.fog_material.get_shader_parameter("clear_max")
 var old_min=PackedVector3Array([Vector3(-38,-3,-13),Vector3(-12,-2,-31),Vector3(8,-3,-14)])
 var old_max=PackedVector3Array([Vector3(-8,9,13),Vector3(12,10,31),Vector3(38,9,18)])
 old_min.resize(9);old_max.resize(9)
 weather.fog_material.set_shader_parameter("clear_min",old_min);weather.fog_material.set_shader_parameter("clear_max",old_max)
 await settle();await capture("side-old-clear-box")
 weather.fog_material.set_shader_parameter("clear_min",new_min);weather.fog_material.set_shader_parameter("clear_max",new_max)
 await settle();await capture("side-fitted-clear-box")
 var outside:=Vector3(-25,1.7,-12)
 var inside:=Vector3(-25,1.7,-5)
 var outside_excluded:=false;var inside_excluded:=false
 for i in 9:
  var box:=AABB(new_min[i],new_max[i]-new_min[i])
  outside_excluded=outside_excluded or box.has_point(outside)
  inside_excluded=inside_excluded or box.has_point(inside)
 check(not outside_excluded and inside_excluded,"clear-air footprint excludes exterior stripe but preserves room air")
 weather.enabled=false;await settle();await capture("side-no-storm")
 actor=null;current_scene=null;base.queue_free()
 for frame in 4:await process_frame
 print("EXTERIOR SHELL CHECKS ",checks," FAILURES ",failures)
 quit(1 if failures else 0)
