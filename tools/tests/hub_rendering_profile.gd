extends "res://tools/tests/gameplay_performance_profile.gd"
## Fixed production cameras, including views through opened room entrances.
## Output is selected with -- --output=res://tools/.local/<directory>.
func run() -> void:
 if DisplayServer.get_name() == "headless":
  push_error("Hub profile requires a graphical renderer")
  quit(1)
  return
 Engine.max_fps = 0
 root.mode = Window.MODE_WINDOWED
 root.size = size
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 if output == "res://tools/.local/journal-performance":
  output = "res://tools/.local/hub_rendering_profile"
 DirAccess.make_dir_recursive_absolute(output)
 var base: Node3D = load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
 root.add_child(base)
 current_scene = base
 await frames(30)
 root.get_node("GameMenu").force_close_menu()
 actor = get_first_node_in_group("local_player")
 actor.set_physics_process(false)
 actor.survival.set_physics_process(false)
 actor.set_process_input(false)
 actor.set_process_unhandled_input(false)
 var state: BaseGameplayController = base.get_node("BaseGameplayController")
 state.set_process(false)
 state.progress_persistence_enabled = false
 var snapshot := state.get_snapshot()
 snapshot.main_breaker_on = true
 snapshot.fuel_delivered = true
 snapshot.fuel_liters = 40.0
 state._broadcast_snapshot(snapshot)
 var views := [
  ["hub_corner", Vector3(5, .1, 5), 0.0],
  ["west_approach", Vector3(-10, .1, 0), -PI / 2],
  ["east_approach", Vector3(10, .1, 0), PI / 2],
  ["north_approach", Vector3(0, .1, -11), PI],
 ]
 for view in views:
  actor.teleport_authoritative(view[1], view[2])
  await measure(view[0], 120)
 # Exercise real authored open poses without changing the production door rules.
 # These overrides exist only in the isolated, unsaved test scene.
 var open_doors := 0
 for manager: BaseAutoDoorManager in get_nodes_in_group("base_auto_door_managers"):
  manager.set_process(false)
  for door in manager._doors:
   manager._apply_door_state(door, true, true)
  open_doors += manager.get_open_door_count()
 if open_doors == 0:
  push_error("Hub profile could not open any production doors")
  quit(1)
  return
 print("HUB PROFILE OPEN DOORS ", open_doors)
 for view in views:
  actor.teleport_authoritative(view[1], view[2])
  await measure(view[0] + "_open", 120)
 var file := FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
 file.store_string(JSON.stringify({"resolution": str(size), "gpu": RenderingServer.get_video_adapter_name(),
  "tighter_shadow_caster_culling": ProjectSettings.get_setting("rendering/lights_and_shadows/tighter_shadow_caster_culling"),
  "results": results}, "\t"))
 file.close()
 current_scene = null
 base.queue_free()
 await frames(4)
 print("HUB PROFILE COMPLETE")
 quit()
