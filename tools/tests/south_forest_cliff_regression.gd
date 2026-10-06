extends SceneTree
var failures:Array[String]=[]
func _initialize(): run.call_deferred()
func check(ok:bool,message:String):
 print("PASS " if ok else "FAIL ",message)
 if not ok: failures.append(message)
func run():
 var world=load("res://scenes/levels/snow_exterior.tscn").instantiate()
 root.add_child(world)
 var camera=Camera3D.new()
 camera.position=Vector3(300,100,0)
 root.add_child(camera)
 camera.current=true
 var terrain=world.get_node("Terrain3D")
 terrain.set_camera(camera)
 for i in 8: await physics_frame
 await RenderingServer.frame_post_draw
 check(not world.get_node("CliffValley").has_node("RockyEastCliff"),"reference scan removed")
 check(terrain.data.get_control_hole(Vector3(290,0,0)),"Terrain section under wall excluded")
 check(terrain.material.is_shader_override_enabled(),"LOD-safe replacement cutout enabled")
 var cutout:Shader=terrain.material.get_shader_override()
 check(cutout != null and cutout.resource_path=="res://assets/environments/snow/terrain_cliff_cutout.gdshader","replacement uses saved Terrain material")
 var rect:Vector4=terrain.material.get_shader_param("cliff_replacement_bounds")
 check(rect==Vector4(258,342,-364,364),"cutout stays inside mesh with two metre overlap")
 check(terrain.data.get_control_hole(Vector3(0,0,0)),"original shaft hole retained")
 var cliff=world.get_node("EastCliffWall")
 var mesh:Mesh=cliff.get_node("LayeredRockFace").mesh
 check(mesh.get_faces().size()/3==5368,"single lightweight cliff: 5368 triangles")
 check(cliff.get_node("CliffCollision").shape.get_faces().size()==mesh.get_faces().size(),"cliff collision uses the same surface")
 var state=world.get_world_3d().direct_space_state
 var missing=0
 var total=0
 for z in [-330.0,-240.0,-100.0,0.0,100.0,240.0,330.0]:
  for x in [254.0,256.0,264.0,266.0,334.0,336.0,344.0,346.0]:
   var q=PhysicsRayQueryParameters3D.create(Vector3(x,240,z),Vector3(x,-140,z),1)
   var hit:Dictionary=state.intersect_ray(q)
   if hit.is_empty(): missing+=1
   total+=1
 for z in [-368.0,-366.0,-360.0,-356.0,356.0,360.0,366.0,368.0]:
  for x in [260.0,275.0,290.0,310.0,340.0]:
   var q=PhysicsRayQueryParameters3D.create(Vector3(x,240,z),Vector3(x,-140,z),1)
   var hit:Dictionary=state.intersect_ray(q)
   if hit.is_empty(): missing+=1
   total+=1
 check(missing==0,"terrain/cliff seams supported: %d rays, %d gaps"%[total,missing])
 cliff.collision_layer=1<<20
 await physics_frame
 await physics_frame
 var wall_hits=0
 for z in [-180.0,0.0,180.0]:
  for y in [-30.0,-70.0]:
   var hit:Dictionary=state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(370,y,z+0.17),Vector3(255,y,z+0.17),1<<20))
   if not hit.is_empty() and hit.collider==cliff: wall_hits+=1
 cliff.collision_layer=1
 check(wall_hits==6,"all six cliff-face rays hit its collider: %d/6"%wall_hits)
 for name in ["SouthPassForest","WestPassForest"]:
  var forest=world.get_node(name)
  var count=0
  var errors=0
  var rows:Dictionary={}
  for f in forest.find_children("Pines_*","MultiMeshInstance3D",false,false):
   for i in f.multimesh.instance_count:
    var p=f.global_transform*f.multimesh.get_instance_transform(i).origin
    var h:float=terrain.data.get_height(p)
    if not p.is_finite() or not is_finite(h) or absf(h-p.y)>0.03: errors+=1
    rows[p.x]=int(rows.get(p.x,0))+1
    count+=1
  var maxrow=0
  for n in rows.values(): maxrow=maxi(maxrow,n)
  check(count==(150 if name=="SouthPassForest" else 100) and errors==0,name+" grounded")
  check(forest.get_node("TreeTrunks").get_child_count()==count and maxrow<=2,name+" colliders and irregular placement")
 var peak_objects=0
 for f in world.get_node("Landscape").get_children():
  if not f is MultiMeshInstance3D: continue
  for i in f.multimesh.instance_count:
   var p=f.global_transform*f.multimesh.get_instance_transform(i).origin
   var h:float=terrain.data.get_height(p)
   if (is_finite(h) and h>55.0) or (p.x>=225 and p.x<=390 and absf(p.z)<365): peak_objects+=1
 for node in world.get_node("BoundaryDressing").get_children():
  var h:float=terrain.data.get_height(node.global_position)
  if is_finite(h) and h>55: peak_objects+=1
 check(peak_objects==0,"upper slopes and cliff edge clear of decoration")
 var forest_errors=0
 for f in world.get_node("CliffValley").find_children("Forest*","MultiMeshInstance3D",false,false):
  for i in f.multimesh.instance_count:
   var p=f.global_transform*f.multimesh.get_instance_transform(i).origin
   if not p.is_finite() or p.y>90.01: forest_errors+=1
 check(forest_errors==0,"background high foothills clear")
 var haze=world.get_node("CliffValley").find_children("StormHaze_*","FogVolume",false,false)
 check(haze.size()==28 and is_equal_approx(haze[0].material.density,0.028),"storm coverage and previous density retained")
 print("RESULT FAILURES ",failures.size())
 quit(0 if failures.is_empty() else 1)

