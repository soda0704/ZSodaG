extends SceneTree
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1280,720);root.get_node("GameMenu").force_close_menu()
 var input_service=root.get_node("SteamInput");input_service.set_process(false);input_service.native_input_available=false
 var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(arena)
 for variant in [0,1]:
  var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3.ZERO,Color.WHITE,0,variant);arena.get_node("Players").add_child(actor)
  actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.weapon.set_physics_process(false)
  actor.camera.current=true;actor._held_item_type=&"kitchen_knife";actor.weapon.apply_state(&"kitchen_knife",0,0);actor._refresh_equipment_visuals()
  var fp:GameFirstPersonPresentation=actor.body_animator.first_person;fp.set_process(false)
  fp.update_context({"held_item":&"kitchen_knife","grounded":true,"velocity":Vector3.ZERO})
  for i in 70:fp._process(1./60);await process_frame
  var sk:Skeleton3D=fp.model.get_node("Skeleton3D");var hand:=sk.find_bone("RightHand")
  var start:Vector3=sk.get_bone_global_pose(hand).origin
  var min_y:=start.y;var min_z:=start.z
  for strike in 3:
   fp.action("Knife","Attack")
   for i in 40:
    fp._process(1./60);await process_frame
    var point:Vector3=sk.get_bone_global_pose(hand).origin
    min_y=minf(min_y,point.y);min_z=minf(min_z,point.z)
    if strike==0 and i in [0,4,10,18,32]:
     await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png("res://tools/.local/knife-thrust-%d-%d.png"%[variant,i])
  print("KNIFE THRUST ",variant," forward mm ",(start.z-min_z)*1000," downward mm ",(start.y-min_y)*1000)
  assert(start.z-min_z>.035 and start.y-min_y<.02)
  actor.queue_free();await process_frame
 print("KNIFE THRUST SERIES PASS BOTH VARIANTS");quit()
