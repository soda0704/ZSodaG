extends SceneTree
## Offline authoring command, never invoked by gameplay.
## godot --headless --path . --script tools/bake_containment_navigation.gd
func _initialize() -> void:
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://navigation_authoring_only.cfg")
 run.call_deferred()
func run() -> void:
 var base:Node3D=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
 root.add_child(base);current_scene=base
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 state.progress_persistence_enabled=false
 state.set_process(false)
 for i in 3: await physics_frame
 var level:Node3D=base.get_node("Floor_Minus4_Biocontainment_Blockout")
 level.add_to_group("containment_navigation_source")
 var region:NavigationRegion3D=base.get_node("ContainmentEncounter/NavigationRegion")
 region.navigation_mesh=region.navigation_mesh.duplicate()
 region.bake_navigation_mesh(true)
 await region.bake_finished
 var mesh:=region.navigation_mesh
 var result:=ERR_INVALID_DATA
 if mesh.get_polygon_count()>0: result=ResourceSaver.save(mesh,"res://assets/navigation/containment.tres")
 print("CONTAINMENT NAVIGATION: ",mesh.get_polygon_count()," polygons, save result ",result)
 base.queue_free();await process_frame
 quit(0 if result==OK else 1)
