extends SceneTree

func _initialize() -> void:
 run.call_deferred()

func run() -> void:
 root.size = Vector2i(1280, 720)
 root.get_node("GameMenu").force_close_menu()
 var input_service = root.get_node("SteamInput")
 input_service.set_process(false)
 input_service.native_input_available = false
 var level = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
 root.add_child(level)
 level.get_node("RuntimePlayers").queue_free()
 var camera = Camera3D.new()
 camera.fov = 65
 level.add_child(camera)
 camera.current = true
 var light = OmniLight3D.new()
 light.omni_range = 8
 light.light_energy = 1.2
 light.shadow_enabled = true
 camera.add_child(light)
 for i in 180: await physics_frame
 for item in get_nodes_in_group("world_items"):
  print("SETTLED ", item.name, " ", item.item_type, " ", item.global_position, " rotation ", item.global_rotation_degrees)
 var views = [
  ["kitchen", Vector3(14.2,1.95,-6.8),Vector3(14.2,1,-7.3)],
  ["generator-corner",Vector3(-6.2,2,19.8),Vector3(-7.15,.15,18.85)],
  ["storage",Vector3(2.5,2.5,15.7),Vector3(2.5,1,17.25)],
  ["equipment",Vector3(-23,2.3,2.3),Vector3(-24.4,.05,3.7)],
  ["pistol",Vector3(-29.5,2.2,5.8),Vector3(-29.5,1,7.1)],
 ]
 for i in 3:
  var can = level.get_node("StandaloneFuelCan" if i == 0 else "ReserveFuelCan%d" % i)
  var offset := Vector3(-1.4,1.5,1.3) if can.global_position.x > -30 else Vector3(1.4,1.5,-1.3)
  views.append(["can%d"%i,can.global_position+offset,can.global_position])
 for view in views:
  camera.position = view[1]
  camera.look_at(view[2])
  for i in 3: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tools/.local/props-%s.png" % view[0])
 var breaker = get_first_node_in_group("main_breaker")
 camera.position = breaker.to_global(Vector3(1, .45,-1.6))
 camera.look_at(breaker.to_global(Vector3(0,0,-.2)))
 var state = level.get_node("BaseGameplayController")
 for enabled in [false,true]:
  var snapshot = state.get_snapshot()
  snapshot.main_breaker_on = enabled
  snapshot.fuel_delivered = true
  snapshot.fuel_liters = 20.0
  snapshot.maintenance = {}
  state._broadcast_snapshot(snapshot, false)
  await create_timer(0.7).timeout
  for i in 3: await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://tools/.local/props-breaker-%s.png"%enabled)
 var lever = breaker.get_node("%Handle")
 breaker.lever_animation.play(&"switch")
 for step in 21:
  breaker.lever_animation.seek(breaker.lever_animation.get_animation(&"switch").length*step/20.0, true)
  var box = lever.get_aabb()
  for x in [box.position.x,box.end.x]:
   for y in [box.position.y,box.end.y]:
    for z in [box.position.z,box.end.z]:
     var p = breaker.to_local(lever.to_global(Vector3(x,y,z)))
     assert(p.z < -.06, "Handle clip intersects cabinet backing")
 print("PROP VISUAL REVIEW COMPLETE; NATIVE HANDLE CLIP PASS")
 quit()
