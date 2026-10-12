extends SceneTree
func _initialize():run.call_deferred()
func run():
 for variant in ["a","b"]:
  var path:String="res://scenes/characters/visuals/tactical_%s/first_person.tscn"%variant
  var model:Node3D=load(path).instantiate();root.add_child(model)
  model.get_node("AnimationTree").active=false
  var ap:AnimationPlayer=model.get_node("AnimationPlayer")
  var library:AnimationLibrary=ap.get_animation_library("").duplicate(true)
  ap.remove_animation_library("");ap.add_animation_library("",library)
  var recoil:=Animation.new();recoil.length=.24
  var rt:=recoil.add_track(Animation.TYPE_ROTATION_3D);recoil.track_set_path(rt,NodePath("."))
  var pt:=recoil.add_track(Animation.TYPE_POSITION_3D);recoil.track_set_path(pt,NodePath("."))
  for i in 25:
   var t:float=i*.01
   var amount:float=smoothstep(0.,.04,t)*(1.-smoothstep(.04,.24,t))
   recoil.rotation_track_insert_key(rt,t,Quaternion(Vector3.RIGHT,deg_to_rad(1.2)*amount))
   recoil.position_track_insert_key(pt,t,Vector3(0,0,.009*amount))
  library.remove_animation("PistolRecoil");library.add_animation("PistolRecoil",recoil)
  var kick:AnimationNodeOneShot=model.get_node("AnimationTree").tree_root.get_node("Kick")
  kick.set_filter_path(NodePath("."),true)
  model.get_node("AnimationTree").active=true
  var packed:=PackedScene.new();assert(packed.pack(model)==OK)
  var result:=ResourceSaver.save(packed,path)
  for retry in 10:
   if result==OK:break
   OS.delay_msec(200);result=ResourceSaver.save(packed,path)
  assert(result==OK);print("PISTOL WHOLE RIG RECOIL ",variant)
  model.queue_free();await process_frame
 quit()
