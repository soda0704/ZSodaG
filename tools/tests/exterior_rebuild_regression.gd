extends SceneTree
var checks:=0
var failures:=0
var output:="res://tools/.local/exterior-rebuild-2026-11-06/captures/"
func _initialize():
 BaseGameplayController.save_scope="solo"
 var prefix:="user://rebuilt_shell_%d"%OS.get_process_id()
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
 ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
 ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
 if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
 create_timer(110).timeout.connect(func():quit(2));run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func shot(label:String):
 await create_timer(.8).timeout;await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+label+".png")
func run():
 DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1600,900);root.content_scale_size=root.size;Engine.max_fps=60
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for frame in 30:await physics_frame
 root.get_node("GameMenu").force_close_menu()
 var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.body_animator.visible=false;actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
 base.get_node("BaseGameplayController").set_process(false);base.get_node("SnowExterior/Blizzard").enabled=false
 var shell=base.get_node("Floor_0_Base_Blockout/ArcticBase_ExteriorShell")
 var model=shell.get_node("Model");var proxy:MeshInstance3D=model.get_node("ShellCollisionProxy")
 check(not proxy.visible,"simplified collision proxy is not rendered")
 check(shell.get_node("ShellBody/CollisionShape3D").shape.get_faces().size()/3<25000,"collision excludes dense visual details")
 var missing_uv:=[];var textured:=0
 for node in model.get_children():
  if not node is MeshInstance3D or node==proxy:continue
  for surface in node.mesh.get_surface_count():
   var arrays=node.mesh.surface_get_arrays(surface)
   if arrays[Mesh.ARRAY_TEX_UV]==null or arrays[Mesh.ARRAY_TEX_UV].is_empty():missing_uv.append(str(node.name))
   var material=node.get_active_material(surface)
   if material is StandardMaterial3D and material.albedo_texture!=null and material.normal_texture!=null and material.roughness_texture!=null:textured+=1
   if material is ShaderMaterial and material.get_shader_parameter("coating_color")!=null and material.get_shader_parameter("coating_normal")!=null and material.get_shader_parameter("coating_roughness")!=null:textured+=1
 check(missing_uv.is_empty(),"visible meshes retain UV maps: "+str(missing_uv))
 check(textured>=4,"multiple surfaces use complete Albedo/Normal/Roughness PBR maps")
 print("REBUILT RENDER textured surfaces=",textured)
 var wall_mesh:MeshInstance3D=model.get_node("Base_ExteriorShell_Mesh")
 var wear_min:=1.0;var wear_max:=0.0
 for surface in wall_mesh.mesh.get_surface_count():
  var colors=wall_mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
  if colors==null:continue
  for color in colors:wear_min=minf(wear_min,color.r);wear_max=maxf(wear_max,color.r)
 check(wear_max-wear_min>.10,"source vertex colours remain intact in the imported asset")
 check(model.has_node("Entrance_Weather_Hood"),"new entrance canopy is instantiated")
 var reveals:MeshInstance3D=model.get_node("Fitted_Entrance_Reveals")
 var feet:=0;var cap_level:=true
 for point in reveals.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
  if point.y<.0:feet+=1;cap_level=cap_level and point.y>=-.201
 check(feet>=400 and cap_level,"both entrance surrounds extend twenty centimetres below the snow datum")
 var roof_mesh:MeshInstance3D=model.get_node("Arched_Roof_Surface")
 var edges:Dictionary={};var roof_faces:=roof_mesh.mesh.get_faces()
 for tri in range(0,roof_faces.size(),3):
  for k in 3:
   var a:=Vector3i((roof_faces[tri+k]*100000.0).round())
   var b:=Vector3i((roof_faces[tri+(k+1)%3]*100000.0).round())
   var key:=str(a)+":"+str(b) if str(a)<str(b) else str(b)+":"+str(a)
   edges[key]=int(edges.get(key,0))+1
 var boundaries:=0
 for count in edges.values():
  if count!=2:boundaries+=1
 check(boundaries==0,"imported curved roof has no open boundary edges: "+str(boundaries))
 check(model.has_node("Joint_Flashings"),"flush folded perimeter flashings are present")
 check(not model.has_node("Structural_Trims"),"rough structural cage is removed")
 var antenna:MeshInstance3D=model.get_node("Antenna_CentralLattice")
 var antenna_bounds:AABB=antenna.global_transform*antenna.get_aabb()
 check(antenna_bounds.size.y>13.9 and absf(antenna_bounds.position.y-10.25)<.05,"14m central antenna is seated on the roof")
 var equipment:MeshInstance3D=model.get_node("Roof_TechnicalEquipment")
 var indoor_parts:=0;var floating_steps:=0
 for point in equipment.mesh.get_faces():
  point=equipment.global_transform*point
  if point.x> -22.2 and point.x< -21.8 and point.z> -7.2 and point.z< -6.2 and point.y<4.4:indoor_parts+=1
  if point.x> -29.1 and point.x< -25.4 and point.z>.8 and point.z<1.9 and point.y>8.30 and point.y<8.46:floating_steps+=1
 check(indoor_parts==0,"obsolete exterior brackets no longer hang inside the base")
 check(floating_steps==0,"suspended roof walkway has been removed")
 var camera:=Camera3D.new();base.add_child(camera);camera.current=true;camera.far=3000;camera.fov=65
 var indirect=base.get_node("WorldIndirectLighting");var gi_valid:=true
 for zone in ["Entrance","Hub","Living"]:
  var data=load("res://assets/environments/base_gi/"+zone.to_snake_case()+".res") as VoxelGIData
  gi_valid=gi_valid and data!=null and not data.get_octree_cells().is_empty()
 check(gi_valid,"all three rebaked surface GI volumes contain geometry")
 var power_before:bool=base.get_node("BaseGameplayController").main_breaker_on
 indirect.set_quality_enabled(false);indirect.update_floor(2)
 var no_gi:bool=indirect.get_active_probe_count()==0
 indirect.set_quality_enabled(true);indirect.update_floor(2)
 check(no_gi and indirect.get_active_probe_count()==5 and power_before==base.get_node("BaseGameplayController").main_breaker_on,"GI toggles independently of electrical power")
 for view in [["overview",Vector3(-65,23,38),Vector3(-8,4,0)],["entry",Vector3(-46,2.1,6),Vector3(-38.8,2.2,2.8)],["roof",Vector3(-28,12,12),Vector3(-22,8.7,0)],["side",Vector3(-25,2,-15),Vector3(-22,3,-10.5)],["west-corners",Vector3(-44,5.7,16),Vector3(-37,6.5,9)],["east-corners",Vector3(43,5.7,16),Vector3(34,6.5,9)],["north-corners",Vector3(16,5.7,-34),Vector3(9,6.5,-27)],["south-corners",Vector3(16,5.7,34),Vector3(9,6.5,27)]]:
  camera.position=view[1];camera.look_at(view[2]);await shot("rebuilt-"+view[0])
 var state:BaseGameplayController=base.get_node("BaseGameplayController")
 var snapshot=state.get_snapshot();snapshot.main_breaker_on=true;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.0;state._broadcast_snapshot(snapshot)
 camera.position=Vector3(-27,1.7,-2);camera.look_at(Vector3(-22,2,-6.6));await shot("rebuilt-interior-gi")
 indirect.set_debug_disabled(true);indirect.update_floor(2);await shot("rebuilt-interior-direct")
 indirect.set_debug_disabled(false);indirect.update_floor(2)
 snapshot=state.get_snapshot();snapshot.main_breaker_on=power_before;state._broadcast_snapshot(snapshot)
 var gate=base.find_child("West_Vehicle_Exterior_Gate_Visual_Prototype",true,false)
 check(gate!=null,"existing vehicle gate remains in the level")
 if gate!=null:
  var closed:Node3D=gate.get_node("Visual/GateAssembly/GateStates/DoorPivot/ClosedState")
  check(closed.has_node("RebuiltGate/Garage_Insulated_Shutter"),"rebuilt insulated shutter follows existing door state")
  check(not closed.get_node("Panel01").visible,"old blockout leaf is hidden")
  check(gate.has_method("debug_set_open"),"new shutter retains cooperative garage controller")
  if gate.has_method("debug_set_open"):
   gate.debug_set_open(false);await create_timer(4.2).timeout
   var pivot:Node3D=closed.get_parent()
   var blocker:CollisionShape3D=closed.get_node("GateBody/CollisionShape3D")
   var before:Vector3=blocker.global_position
   check(absf(pivot.rotation.x)<.01 and not blocker.disabled,"closed gate retains physical collision")
   camera.position=Vector3(-48,2.5,-2.5);camera.look_at(Vector3(-38,2,-2.5));await shot("rebuilt-gate-closed")
   gate.debug_set_open(true);await create_timer(4.2).timeout
   check(absf(pivot.rotation.x-PI*.5)<.01,"new shutter completes existing AnimationPlayer lift")
   check(blocker.global_position.distance_to(before)>2.0,"collision follows lifted shutter out of passage")
   await shot("rebuilt-gate-open")
   gate.debug_set_open(false);await create_timer(4.2).timeout
   check(absf(pivot.rotation.x)<.01 and blocker.global_position.distance_to(before)<.01,"gate recloses and restores collision")
   gate.set_physics_process(false);gate.opening_seconds=.2
   actor.teleport_authoritative(gate.handles[0].global_position+gate.global_basis.z*1.1,0)
   for frame in 8:await physics_frame
   check(gate._valid_operator(1,0),"existing handle remains reachable by a real player")
   for i in 3:gate._hold(1,0);gate._physics_process(.11)
   check(gate.progress==1.0,"existing hold interaction opens the rebuilt gate")
   gate.animation.advance(4.1)
   for frame in 5:await physics_frame
   gate._holds.clear();gate._physics_process(.4)
   for i in 3:gate._hold(1,0);gate._physics_process(.11)
   check(gate.progress==0.0,"existing hold interaction closes the rebuilt gate")
   gate.animation.advance(4.1)
   BaseGameplayController.save_scope="coop"
   check(gate.required_operators()==2,"cooperative gate still requires two operators")
   BaseGameplayController.save_scope="solo"
 if OS.get_environment("NORTHERNLAB_EXTERIOR_BENCHMARK")=="1":
  camera.position=Vector3(-65,23,38);camera.look_at(Vector3(-8,4,0))
  var original=load("res://assets/models/architecture/arctic_base_exterior/arctic_base_exterior_shell.glb").instantiate();shell.add_child(original)
  for node in original.find_children("*","GeometryInstance3D",true,false):node.layers=327681
  root.get_node("GameMenu/GraphicsQuality").set_process(false)
  DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
  var values:=[]
  for sample in 3:
   for rebuilt in [false,true]:
    model.visible=rebuilt;original.visible=not rebuilt
    for frame in 40:await process_frame
    var started:=Time.get_ticks_usec()
    for frame in 120:await process_frame
    var ms:=(Time.get_ticks_usec()-started)/120000.0
    values.append({"sample":sample,"rebuilt":rebuilt,"frame_ms":ms});print("EXTERIOR FRAME ",values[-1])
  FileAccess.open(output+"exterior-frame-times.json",FileAccess.WRITE).store_string(JSON.stringify(values,"  "))
  original.queue_free();model.visible=true;Engine.max_fps=60
 # Probe the shell only; interior doors and their collision are tested separately.
 var body=shell.get_node("ShellBody");var hidden:Dictionary={}
 for obj in base.find_children("*","CollisionObject3D",true,false):
  if obj!=body:hidden[obj]=obj.collision_layer;obj.collision_layer=0
 await physics_frame
 for pair in [[Vector3(-12,1.7,0),Vector3(0,1.7,0)],[Vector3(0,1.7,-12),Vector3(0,1.7,0)],[Vector3(12,1.7,0),Vector3(0,1.7,0)],[Vector3(0,1.7,12),Vector3(0,1.7,0)]]:
  check(base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pair[0],pair[1],1)).is_empty(),"shell leaves interior module connector open: "+str(pair[0]))
 for z in [-5.20,.20]:
  check(base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(-42,1.8,z),Vector3(-37,1.8,z),1)).is_empty(),"fitted reveal preserves actual gate clearance at z="+str(z))
 for obj in hidden:obj.collision_layer=hidden[obj]
 current_scene=null;base.queue_free()
 for frame in 8:await process_frame
 print("REBUILT SHELL CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
