extends SceneTree
func _initialize():run.call_deferred()
func run():
 root.get_node("GameMenu").force_close_menu()
 var input_service=root.get_node("SteamInput");input_service.set_process(false);input_service.native_input_available=false
 var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(arena)
 for variant in [0,1]:
  var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3.ZERO,Color.WHITE,0,variant);arena.get_node("Players").add_child(actor)
  actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.weapon.set_physics_process(false)
  actor.camera.current=true;actor._held_item_type=&"pistol";actor.weapon.apply_state(&"pistol",12,0);actor._refresh_equipment_visuals()
  var fp:GameFirstPersonPresentation=actor.body_animator.first_person;fp.set_process(false)
  fp.update_context({"held_item":&"pistol","grounded":true,"velocity":Vector3.ZERO,"aiming":true})
  for i in 100:fp._process(1./60);await process_frame
  var baseline_position:Vector3=fp.model.position;var baseline_rotation:Vector3=fp.model.rotation
  var pivot:Node3D=fp.recoil_player.get_parent()
  var peak:=0.;var side:=0.;var returned:=0.
  for shot in 4:
   fp.action("Pistol","Recoil")
   for i in 30:
    fp._process(1./60);await process_frame
    var sk:Skeleton3D=fp.model.get_node("Skeleton3D")
    var wrist:Vector3=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("RightHand")).origin
    var screen:Vector2=fp.view_camera.unproject_position(wrist)
    assert(not fp.view_camera.is_position_behind(wrist))
    assert(screen.x>0 and screen.x<fp.viewport.size.x and screen.y>0 and screen.y<fp.viewport.size.y)
    if shot==0 and i in [0,3,8,18,29]:
     await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png("res://tools/.local/pistol-ads-shot-%d-%d.png"%[variant,i])
    peak=maxf(peak,absf(pivot.rotation.x))
    side=maxf(side,absf(pivot.position.x)+absf(pivot.rotation.y)+absf(pivot.rotation.z))
   returned=fp.model.position.distance_to(baseline_position)+fp.model.rotation.distance_to(baseline_rotation)
  print("RECOIL variant ",variant," pitch degrees ",rad_to_deg(peak)," lateral ",side," settled ",returned)
  assert(peak>deg_to_rad(.3) and peak<deg_to_rad(1.3))
  assert(side<.00001 and returned<.00001)
  actor.queue_free();await process_frame
 print("PISTOL FIRING SERIES PASS BOTH VARIANTS");quit()





