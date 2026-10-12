extends SceneTree
## Bake approved review poses into the production clips, retaining clip motion.
const ITEMS = {"Pistol":["pistol","b","pistol"],"Rifle":["rifle","a","m4a1"],"Knife":["knife","a","kitchen_knife"],"Flashlight":["flashlight","a","FlashlightStudy"],"Fuse":["fuse","a","FuseStudy"],"Fuel":["fuel","a","FuelCanStudy"],"Journal":["journal","a",""]}
func _initialize(): run.call_deferred()
func upper(name:String)->bool:
 return name.begins_with("Spine") or name in ["Head","Neck","LeftShoulder","RightShoulder"] or name.begins_with("LeftArm") or name.begins_with("RightArm") or name.begins_with("LeftForeArm") or name.begins_with("RightForeArm") or name.begins_with("LeftHand") or name.begins_with("RightHand") or "Elbow_Pads" in name
func run():
 for variant in ["a","b"]:
  for fp in [false,true]:
   var path:String="res://scenes/characters/visuals/tactical_%s/%s.tscn"%[variant,"first_person" if fp else "body"]
   var model:Node3D=load(path).instantiate();root.add_child(model)
   assert(not model.get_meta("approved_grips_integrated",false),"Already integrated: restore the original scene before rebaking corrections")
   model.get_node("AnimationTree").active=false
   var sk:Skeleton3D=model.get_node("Skeleton3D")
   for modifier in sk.get_children():
    if modifier is SkeletonModifier3D:modifier.active=false
   var ap:AnimationPlayer=model.get_node("AnimationPlayer")
   for lib_name in ap.get_animation_library_list():
    var lib:AnimationLibrary=ap.get_animation_library(lib_name).duplicate(true)
    ap.remove_animation_library(lib_name);ap.add_animation_library(lib_name,lib)
   var sockets:Node3D=sk.get_node("RightHand/Equipment")
   for kind in ITEMS:
    var spec:Array=ITEMS[kind]
    var study_path:String="res://scenes/characters/grip_studies/"+("tactical_a/" if variant=="a" else "")+spec[0]+"/"+("fp_" if fp else "")+spec[1]+".tscn"
    var study:Node3D=load(study_path).instantiate();root.add_child(study)
    study.get_node("AnimationTree").active=false
    var study_ap:AnimationPlayer=study.get_node("AnimationPlayer");study_ap.play("Grip");study_ap.advance(0)
    var reference:Skeleton3D=study.get_node("Skeleton3D");reference.force_update_all_bone_transforms()
    if kind=="Rifle" and variant=="b" and not fp:
     model.get_node("Skeleton3D/Body").mesh=study.get_node("Skeleton3D/Body").mesh
    var base:String="JournalReading" if kind=="Journal" else kind+("Idle" if fp else "Aim0")
    ap.play(base);ap.advance(0);ap.pause();sk.force_update_all_bone_transforms()
    var corrections:Dictionary={}
    for bone in sk.get_bone_count():
     var name:String=sk.get_bone_name(bone)
     if upper(name):corrections[name]=reference.get_bone_pose_rotation(reference.find_bone(name))*sk.get_bone_pose_rotation(bone).inverse()
    for clip_name in ap.get_animation_list():
     if not String(clip_name).begins_with(kind):continue
     if String(clip_name).ends_with("Recoil"):continue # Additive clips must stay relative to the identity pose.
     var clip:Animation=ap.get_animation(clip_name)
     for track in clip.get_track_count():
      var bone:String=String(clip.track_get_path(track)).get_slice(":",1)
      if clip.track_get_type(track)!=Animation.TYPE_ROTATION_3D or not corrections.has(bone):continue
      for key in clip.track_get_key_count(track):
       var t:float=clip.track_get_key_time(track,key)
       var weight:float=1.0
       if clip_name=="JournalOpen":weight=smoothstep(0.0,0.8,t/clip.length)
       elif clip_name=="JournalClose":weight=1.0-smoothstep(0.2,1.0,t/clip.length)
       var delta:Quaternion=Quaternion.IDENTITY.slerp(corrections[bone],weight)
       clip.track_set_key_value(track,key,(delta*clip.track_get_key_value(track,key)).normalized())
    if kind=="Journal":
     var book:Node3D=model.get_node("Journal")
     for side in ["Left","Right"]:
      book.get_node(side+"Grip").transform=book.transform.affine_inverse()*reference.get_bone_global_pose(reference.find_bone(side+"Hand"))
    else:
     var source_sockets:Node3D=reference.get_node("RightHand/Equipment")
     var source:Node3D=source_sockets.get_node(spec[2])
     var fitted:Transform3D=source_sockets.transform*source.transform
     var destination:String={"Flashlight":"FlashlightGrip","Fuse":"FuseGrip","Fuel":"FuelGrip"}.get(kind,spec[2])
     if kind=="Flashlight":fitted=fitted*Transform3D(Basis.IDENTITY,Vector3(0,0,.22))
     sockets.get_node(destination).transform=fitted
     if kind in ["Rifle","Pistol","Knife"]:
      for marker in ["RightHandGrip","LeftHandGrip","SupportHand"]:
       if source.has_node(marker):sockets.get_node(destination+"/"+marker).transform=source.get_node(marker).transform
    study.queue_free();await process_frame
   sockets.transform=Transform3D.IDENTITY
   model.set_meta("approved_grips_integrated",true)
   for modifier in sk.get_children():
    if modifier is SkeletonModifier3D:modifier.active=true
   ap.stop();sk.reset_bone_poses()
   model.get_node("AnimationTree").active=true
   var packed:=PackedScene.new();assert(packed.pack(model)==OK);assert(ResourceSaver.save(packed,path)==OK)
   print("INTEGRATED ",path)
   model.queue_free();await process_frame
 quit()

