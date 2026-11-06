extends SceneTree
func _initialize():
 run.call_deferred()
func run():
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for i in 20:await physics_frame
 var result:={"meshes":{},"instances":[]}
 for n in base.find_children("*","MeshInstance3D",true,false):
  if not n.is_visible_in_tree() or n.mesh==null:continue
  var path:=str(n.get_path())
  if not "/Visual/Walls/" in path:continue
  var model=n.get_parent().get_parent()
  var key:=str(n.mesh.resource_path)
  if not result.meshes.has(key):
   var mats:=[]
   for s in n.mesh.get_surface_count():
    var m=n.get_active_material(s)
    mats.append({"surface":s,"path":m.resource_path if m!=null else "", "name":m.resource_name if m!=null else ""})
   result.meshes[key]={"bounds":var_to_str(n.mesh.get_aabb()),"materials":mats}
  result.instances.append({"path":path,"model":model.scene_file_path,"bounds":var_to_str(n.global_transform*n.get_aabb()),"transform":var_to_str(n.global_transform)})
 FileAccess.open("res://tools/.local/exterior-rebuild-2026-11-06/wall-inspection.json",FileAccess.WRITE).store_string(JSON.stringify(result," "))
 print("INSPECTED wall meshes ",result.meshes.size()," instances ",result.instances.size())
 base.queue_free()
 for i in 5:await process_frame
 quit()
