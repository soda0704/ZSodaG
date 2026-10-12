extends SceneTree
func _initialize():run.call_deferred()
func run():
 for variant in ["a","b"]:
  for fp in [false,true]:
   var path:String="res://scenes/characters/visuals/tactical_%s/%s.tscn"%[variant,"first_person" if fp else "body"]
   var model:Node3D=load(path).instantiate();root.add_child(model);model.get_node("AnimationTree").active=false
   var sk:Skeleton3D=model.get_node("Skeleton3D")
   for modifier in sk.get_children():
    if modifier is SkeletonModifier3D:modifier.active=false
   var ap:AnimationPlayer=model.get_node("AnimationPlayer")
   for library_name in ap.get_animation_library_list():
    var library:AnimationLibrary=ap.get_animation_library(library_name).duplicate(true)
    ap.remove_animation_library(library_name);ap.add_animation_library(library_name,library)
   ap.play("KnifeIdle" if fp else "KnifeAim0");ap.advance(0);ap.pause();sk.force_update_all_bone_transforms()
   var rotations:Array[Quaternion]=[]
   for bone in sk.get_bone_count():rotations.append(sk.get_bone_pose_rotation(bone))
   var hand:int=sk.find_bone("RightHand")
   var home:Vector3=sk.get_bone_global_pose(hand).origin
   var home_basis:Basis=sk.get_bone_global_pose(hand).basis
   var sockets:Node3D=sk.get_node("RightHand/Equipment")
   var knife:Node3D=sockets.get_node("kitchen_knife")
   var grip:Vector3=knife.get_node("RightHandGrip").position
   var tip:=grip;var farthest:=0.
   for mesh:MeshInstance3D in knife.find_children("*","MeshInstance3D",true,false):
    var local:Transform3D=knife.global_transform.affine_inverse()*mesh.global_transform
    for surface in mesh.mesh.get_surface_count():
     for vertex in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
      var point:Vector3=local*vertex
      if point.distance_squared_to(grip)>farthest:tip=point;farthest=point.distance_squared_to(grip)
   var blade_direction:Vector3=(home_basis*sockets.basis*knife.basis*(tip-grip)).normalized()
   var thrust_turn:=Quaternion(blade_direction,Vector3.FORWARD)
   print("KNIFE BLADE DIRECTION ",variant," FP ",fp," ",blade_direction)
   var author=load("res://tools/authoring/rifle_grip_study_author.gd").new();author.initialize(sk,{"meshes":[]},{})
   var clip:=Animation.new();clip.length=.48
   for bone in sk.get_bone_count():
    var track:=clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(track,NodePath("Skeleton3D:"+sk.get_bone_name(bone)))
   for frame in 49:
    var t:float=frame*.01
    var thrust:float=smoothstep(.055,.17,t)*(1.-smoothstep(.23,.48,t))
    var windup:float=smoothstep(0.,.035,t)*(1.-smoothstep(.035,.08,t))
    for bone in sk.get_bone_count():sk.set_bone_pose_rotation(bone,rotations[bone])
    sk.force_update_all_bone_transforms()
    author.fit_rifle_arm("Right",home+Vector3(0,.035*thrust,-.16*thrust+.025*windup),Basis(Quaternion.IDENTITY.slerp(thrust_turn,thrust))*home_basis)
    if not fp:author.seat_elbow_shells()
    for bone in sk.get_bone_count():clip.rotation_track_insert_key(bone,t,sk.get_bone_pose_rotation(bone))
   ap.get_animation_library("").remove_animation("KnifeAttack");ap.get_animation_library("").add_animation("KnifeAttack",clip)
   ap.stop();sk.reset_bone_poses()
   for modifier in sk.get_children():
    if modifier is SkeletonModifier3D:modifier.active=true
   model.get_node("AnimationTree").active=true
   var packed:=PackedScene.new();assert(packed.pack(model)==OK)
   var result:=ResourceSaver.save(packed,path)
   for retry in 10:
    if result==OK:break
    OS.delay_msec(200);result=ResourceSaver.save(packed,path)
   assert(result==OK);print("BAKED KNIFE THRUST ",path)
   model.queue_free();await process_frame
 quit()

