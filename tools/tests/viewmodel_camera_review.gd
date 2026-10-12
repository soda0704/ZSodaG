extends SceneTree
const OUT:="res://tools/.local/viewmodel-camera-review/"
func _initialize():run.call_deferred()
func run():
 Engine.max_fps=60;root.size=Vector2i(1280,720)
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
 root.get_node("GameMenu").force_close_menu()
 var input_service=root.get_node("SteamInput");input_service.set_process(false);input_service.set_process_input(false);input_service.native_input_available=false
 for action in InputMap.get_actions():InputMap.action_erase_events(action)
 var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(arena)
 for variant in [0,1]:
  var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
  actor.name="1";actor.setup(1,"",Vector3(0,.02,0),Color.WHITE,0,variant);arena.get_node("Players").add_child(actor)
  actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.weapon.set_physics_process(false);actor.set_process_unhandled_input(false)
  actor.camera.current=true
  var fp:GameFirstPersonPresentation=actor.body_animator.first_person
  for kind in [&"pistol",&"m4a1",&"flashlight",&"kitchen_knife"]:
   fp.set_process(true)
   actor._held_item_type=kind;actor.weapon.apply_state(kind,12,0);actor._has_flashlight=true;actor._battery_charge=1;actor._refresh_equipment_visuals()
   for i in 50:
    actor.body_animator.update_context(1./60,{"held_item":kind,"grounded":true,"velocity":Vector3.ZERO,"pitch":0.,"yaw":0.})
    await process_frame
   fp.set_process(false)
   for fov in [75.,60.,55.]:
    fp.view_camera.fov=fov
    fp.view_camera.global_transform=actor.camera.global_transform
    fp.view_camera.global_basis=actor.camera.global_basis*Basis(Vector3.RIGHT,deg_to_rad(0. if fov==75. else -6. if fov==60. else -8.))
    for i in 3:await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(OUT+"%d-%s-%d.png"%[variant,kind,int(fov)])
   print("CAMERA COMPARE ",variant," ",kind," world FOV ",actor.camera.fov)
  actor.queue_free();await process_frame
 print("VIEWMODEL CAMERA REVIEW COMPLETE");quit()
