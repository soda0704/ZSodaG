extends SceneTree
var failures=0
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures+=1
func run():
 var v=load("res://scenes/objects/vehicles/snowmobile.tscn").instantiate()
 root.add_child(v)
 v.set_physics_process(false)
 await physics_frame
 v._speed=10.0
 v.velocity=Vector3(0,0,-10)
 v._drive(0.25,Vector2.ZERO,12,true,Vector3.UP)
 check(v._speed>9 and v._speed<10,"release throttle preserves momentum with rolling drag")
 v._speed=10
 v._drive(0.25,Vector2(0,1),12,true,Vector3.UP)
 check(v._speed>0 and v._speed<8,"S brakes instead of instantly reversing")
 for i in 30: v._drive(0.05,Vector2(0,1),12,true,Vector3.UP)
 check(v._speed<0 and v._speed>=-v.reverse_speed,"reverse engages after braking and remains limited")
 v._speed=0
 v._drive(0.5,Vector2(0,-1),12,true,Vector3(0,1,0.3).normalized())
 var uphill:float=v._speed
 v._speed=0
 v._drive(0.5,Vector2(0,-1),12,true,Vector3(0,1,-0.3).normalized())
 check(v._speed>uphill,"slope gravity distinguishes downhill and uphill")
 v._speed=0
 v.velocity=Vector3(4,0,0)
 v.rotation=Vector3.ZERO
 v._drive(0.2,Vector2.ZERO,12,true,Vector3.UP)
 check(v.velocity.x>0 and v.velocity.x<2,"lateral grip damps sliding without snapping momentum")
 var yaw:float=v.rotation.y
 v._drive(0.5,Vector2(1,-1),12,false,Vector3.UP)
 check(is_equal_approx(v.rotation.y,yaw),"airborne vehicle cannot steer as if grounded")
 v.driver_peer=1
 v.velocity=Vector3(0,0,-5)
 check(not v.exit_driver(),"cannot dismount at speed")
 v.driver_peer=0
 v.position=Vector3.ZERO
 v.velocity=Vector3.ZERO
 var surface=StaticBody3D.new()
 root.add_child(surface)
 var shape=CollisionShape3D.new()
 var box=BoxShape3D.new()
 box.size=Vector3(100,1,100)
 shape.shape=box
 shape.position.y=-0.5
 surface.add_child(shape)
 var tracks=load("res://scripts/effects/snow_tracks.gd").new()
 tracks.terrain_path=NodePath("../"+str(surface.name))
 tracks.tread_scene=load("res://scenes/objects/effects/snow_tread.tscn")
 tracks.ski_scene=load("res://scenes/objects/effects/snow_ski.tscn")
 root.add_child(tracks)
 tracks.set_physics_process(false)
 await physics_frame
 v.rotation=Vector3.ZERO
 tracks._sample(v,true)
 v.position=Vector3(0,0,-2)
 tracks._sample(v,true)
 check(tracks._marks.size()==9,"fast travel produces continuous three-contact samples")
 if tracks._marks.size()>=3:
  var left:Decal=tracks._marks[-2].node
  var right:Decal=tracks._marks[-1].node
  check(absf(left.position.x+0.4)<0.02 and absf(right.position.x-0.39)<0.02,"ski trails match new model's actual contact spacing")
  check(is_equal_approx(tracks._marks[-3].node.size.x,0.45),"tread trail matches narrow new track")
 var count:int=tracks._marks.size()
 v.position.y=3
 tracks._sample(v,true)
 v.position.z-=1
 tracks._sample(v,true)
 check(tracks._marks.size()==count,"airborne contacts cannot stamp snow")
 v._steering_input=1.0
 v._align_visual_to_ground(1.0)
 var ski_heading:Vector3=-v.get_snow_contact_markers()[1].global_basis.z.normalized()
 check(ski_heading.x>0.2,"ski contact heading follows physical steering pivots")
 v._steering_input=0
 v._align_visual_to_ground(1.0)
 surface.rotation.x=0.15
 v.position=Vector3(0,1,0)
 v.velocity=Vector3.ZERO
 v._speed=0
 v.set_physics_process(true)
 for i in 90: await physics_frame
 v.set_physics_process(false)
 check(v.is_on_floor(),"vehicle settles on actual inclined collision surface")
 check(absf(v.get_node("Visual").rotation.x-0.15)<0.025,"model follows terrain inclination")
 var contact_error=0.0
 for contact in v.get_snow_contact_markers():
  contact_error=maxf(contact_error,absf(contact.global_position.y+tan(0.15)*contact.global_position.z))
 check(contact_error<0.08,"ski and track contact points remain close to slope surface")
 surface.rotation=Vector3.ZERO
 var wall=StaticBody3D.new()
 root.add_child(wall)
 var wall_shape=CollisionShape3D.new()
 var wall_box=BoxShape3D.new()
 wall_box.size=Vector3(5,3,0.3)
 wall_shape.shape=wall_box
 wall.position=Vector3(0,1,-4)
 wall.add_child(wall_shape)
 v.position=Vector3(0,0.05,0)
 v.velocity=Vector3(0,0,-12)
 v._speed=12
 v.set_physics_process(true)
 for i in 60: await physics_frame
 v.set_physics_process(false)
 check(v.position.z>-2.8 and absf(v._speed)<0.1,"wall collision stops real movement and stored drive momentum")
 print("RESULT FAILURES ",failures)
 quit(0 if failures==0 else 1)
