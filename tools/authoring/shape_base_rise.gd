extends SceneTree
const DIR:="res://assets/environments/snow/expanded_terrain/"
const BACKUP:="res://tools/.local/base-rise-2026-11-06/"
func _initialize():run.call_deferred()
func run():
 if DirAccess.dir_exists_absolute(BACKUP):push_error("Backup exists; refusing a second application");quit(1);return
 DirAccess.make_dir_recursive_absolute(BACKUP)
 for file in DirAccess.get_files_at(DIR):
  if file.ends_with(".res"):DirAccess.copy_absolute(DIR+file,BACKUP+file)
 DirAccess.copy_absolute("res://scenes/objects/lobby/arrival_site.tscn",BACKUP+"arrival_site.tscn")
 var camera:=Camera3D.new();root.add_child(camera);camera.current=true
 var scene=load("res://scenes/levels/snow_exterior.tscn").instantiate()
 var weather=scene.get_node("Blizzard");scene.remove_child(weather);weather.free();root.add_child(scene)
 var data=scene.get_node("Terrain3D").data
 for p in [Vector3(-125,0,95),Vector3(-92,0,95),Vector3(-60,0,50),Vector3(-41,0,3)]:print("BEFORE ",p," height=",data.get_height(p))
 var count:=0
 for x in range(-300,301):
  for z in range(-300,301):
   var p:=Vector2(x,z);var at:=Vector3(x,0,z)
   var old:float=data.get_height(at)
   if not is_finite(old) or data.get_control_hole(at):continue
   var distance:=Vector2(maxf(absf(x+2.0)-42.0,0),maxf(absf(float(z))-31.0,0)).length()
   var influence:float=smoothstep(3,12,distance)*(1-smoothstep(155,240,distance))
   influence*=smoothstep(18,42,p.distance_to(Vector2(0,-180)))
   influence*=smoothstep(1.2,1.8,Vector2((x-335.0)/60.0,z/100.0).length())
   if influence<=0:continue
   var macro:=8.0*smoothstep(45,160,p.length())
   var target:=old-macro-4.0*smoothstep(3,65,distance)
   var arrival_keep:=1-smoothstep(40,55,p.distance_to(Vector2(-125,95)))
   target=lerpf(target,old-12.0,arrival_keep)
   data.set_height(at,lerpf(old,target,influence));count+=1
 data.update_maps();data.save_directory(DIR)
 for p in [Vector3(-125,0,95),Vector3(-92,0,95),Vector3(-60,0,50),Vector3(-41,0,3)]:print("AFTER ",p," height=",data.get_height(p))
 print("BASE RISE samples=",count);quit()
