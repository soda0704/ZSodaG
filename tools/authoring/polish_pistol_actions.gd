extends SceneTree
func _initialize():run.call_deferred()
func run():
 for variant in ["a","b"]:
  for fp in [false,true]:
   var path:String="res://scenes/characters/visuals/tactical_%s/%s.tscn"%[variant,"first_person" if fp else "body"]
   var model:Node3D=load(path).instantiate();root.add_child(model);model.get_node("AnimationTree").active=false
   if model.get_meta("pistol_actions_polished",false):
    model.queue_free();await process_frame;continue
   var ap:AnimationPlayer=model.get_node("AnimationPlayer")
   var original:Node3D=load("res://tools/.local/pre-approved-grip-integration/%s-%s.tscn"%[variant,"fp" if fp else "body"]).instantiate()
   var old:AnimationPlayer=original.get_node("AnimationPlayer")
   for library_name in ap.get_animation_library_list():
    var library:AnimationLibrary=ap.get_animation_library(library_name).duplicate(true)
    ap.remove_animation_library(library_name);ap.add_animation_library(library_name,library)
   for kind in ["Pistol","Rifle"]:
    var name:String=kind+"Recoil"
    if not old.has_animation(name):continue
    var recoil:Animation=old.get_animation(name).duplicate(true)
    if kind=="Pistol":
     var factor:float=.22/recoil.length
     for track in recoil.get_track_count():
      for key in recoil.track_get_key_count(track):
       if recoil.track_get_type(track)==Animation.TYPE_ROTATION_3D:recoil.track_set_key_value(track,key,Quaternion.IDENTITY.slerp(recoil.track_get_key_value(track,key),.55))
       recoil.track_set_key_time(track,key,recoil.track_get_key_time(track,key)*factor)
     recoil.length=.22
    ap.get_animation_library("").remove_animation(name);ap.get_animation_library("").add_animation(name,recoil)
   var idle:Animation=ap.get_animation("PistolIdle" if fp else "PistolAim0")
   var reload_clip:Animation=ap.get_animation("PistolReload")
   for track in reload_clip.get_track_count():
    if reload_clip.track_get_type(track)!=Animation.TYPE_ROTATION_3D:continue
    var name:String=String(reload_clip.track_get_path(track)).get_slice(":",1)
    if not (name.begins_with("Right") or name.begins_with("Left") or name.begins_with("Spine")):continue
    var base_track:int=idle.find_track(reload_clip.track_get_path(track),Animation.TYPE_ROTATION_3D)
    if base_track<0:continue
    var base:Quaternion=idle.rotation_track_interpolate(base_track,0.)
    for key in reload_clip.track_get_key_count(track):
     var t:float=reload_clip.track_get_key_time(track,key)
     var ease:float=smoothstep(0.,.18,t)*(1.-smoothstep(reload_clip.length-.22,reload_clip.length,t))
     var amplitude:float=.45 if name.begins_with("Right") else .85
     if name.begins_with("RightHand"):amplitude=0.
     reload_clip.track_set_key_value(track,key,base.slerp(reload_clip.track_get_key_value(track,key),ease*amplitude))
   model.set_meta("pistol_actions_polished",true)
   model.get_node("AnimationTree").active=true
   var packed:=PackedScene.new();assert(packed.pack(model)==OK);var result:=ResourceSaver.save(packed,path)
   for retry in 10:
    if result==OK:break
    OS.delay_msec(200);result=ResourceSaver.save(packed,path)
   assert(result==OK)
   print("POLISHED ",path," reload seconds ",reload_clip.length)
   original.free();model.queue_free();await process_frame
 quit()

