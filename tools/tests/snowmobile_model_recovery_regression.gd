extends SceneTree
var failures=0
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures+=1
func run():
 var world=Node3D.new()
 root.add_child(world)
 world.add_to_group("expedition_level")
 world.position.y=300
 var vehicle=load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
 vehicle.position=Vector3(0,5,0)
 vehicle.set_physics_process(false)
 world.add_child(vehicle)
 await physics_frame
 vehicle.position.y=-20
 vehicle._physics_process(0.016)
 check(vehicle.position.y < -19,"valid negative terrain heights do not recover vehicle")
 vehicle.position.y=-170
 vehicle._physics_process(0.016)
 check(vehicle.position.y>4.9,"fall-through recovery uses expedition coordinates, even in shifted world")
 check(vehicle.velocity==Vector3.ZERO,"recovery clears motion")
 var art=vehicle.get_node("Visual/SkiPatrol")
 var triangles=0
 for n in art.find_children("*","MeshInstance3D",true,false):
  triangles+=n.mesh.get_faces().size()/3
 check(triangles==30976,"lightly reduced model: 30976 triangles")
 check(art.find_children("*","MeshInstance3D",true,false).size()==9,"all nine original model sections retained")
 check(vehicle.has_node("Seat") and vehicle.has_node("ExitLeft") and vehicle.has_node("ExitRight"),"existing interaction markers retained")
 print("RESULT FAILURES ",failures)
 quit(0 if failures==0 else 1)
