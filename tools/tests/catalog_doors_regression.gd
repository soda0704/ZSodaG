extends SceneTree
var failures:=0
var checks:=0
var output:="res://tools/.local/modular-doors/review"
func _initialize():
 var prefix:="user://catalog_doors_%d"%OS.get_process_id()
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
 ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
 ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
 if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
 create_timer(110).timeout.connect(func():quit(2));run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func settle():
 await create_timer(.9).timeout
 await RenderingServer.frame_post_draw
func shot(label:String):
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/"+label+".png")
func red_at(image:Image,point:Vector2)->float:
 var red:=0.0
 for y in range(-3,4):
  for x in range(-3,4):
   var c:=image.get_pixel(clampi(int(point.x)+x,0,image.get_width()-1),clampi(int(point.y)+y,0,image.get_height()-1))
   red+=c.r-c.b
 return red/49
func peak_red(image:Image)->float:
 var value:=-1.0
 for y in range(220,460,12):
  for x in range(420,850,12):value=maxf(value,red_at(image,Vector2(x,y)))
 return value
func frame_hit(mesh:Mesh,start:Vector3,end:Vector3)->Vector3:
 var faces:=mesh.get_faces();var best:=Vector3.INF;var distance:=INF
 for i in range(0,faces.size(),3):
  var hit=Geometry3D.segment_intersects_triangle(start,end,faces[i],faces[i+1],faces[i+2])
  if hit!=null and start.distance_squared_to(hit)<distance:best=hit;distance=start.distance_squared_to(hit)
 return best
func run():
 DirAccess.make_dir_recursive_absolute(output)
 Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
 var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 for frame in 30:await physics_frame
 root.get_node("GameMenu").force_close_menu()
 var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false)
 var state:BaseGameplayController=base.get_node("BaseGameplayController");state.set_process(false)
 var snapshot=state.get_snapshot();snapshot.main_breaker_on=true;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.0;state._broadcast_snapshot(snapshot)
 var entries:Array=[]
 for manager in get_nodes_in_group("base_auto_door_managers"):
  manager.set_process(false)
  for door in manager._doors:
   if not door.anchor.has_meta("catalog_replacement"):continue
   entries.append({"manager":manager,"door":door})
   manager._apply_door_state(door,false,true)
 check(entries.size()==35,"all 35 ordinary room doors use catalog replacements")
 var aligned:=true;var facing:=true;var filled:=true
 var frames:Array=[]
 for node in base.find_children("*","Node3D",true,false):
  if "/modular_scifi/doors/door_frame_" in node.scene_file_path:frames.append(node)
 for entry in entries:
  var anchor=entry.door.anchor
  var left=anchor.get_node_or_null("ClosedPreview/LeftLeaf/CatalogMesh")
  var right=anchor.get_node_or_null("ClosedPreview/RightLeaf/CatalogMesh")
  if left!=null and right!=null:
   var lb:AABB=left.transform*left.mesh.get_aabb();var rb:AABB=right.transform*right.mesh.get_aabb()
   aligned=aligned and absf(lb.position.z-rb.position.z)<.0001 and absf(lb.size.z-rb.size.z)<.0001 and absf(lb.position.y-rb.position.y)<.0001
   facing=facing and left.basis.determinant()>0 and right.basis.determinant()>0 and left.basis.z.normalized().dot(right.basis.z.normalized())>.999
   var la:PackedVector3Array=left.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL];var ra:PackedVector3Array=right.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
   for i in la.size():facing=facing and absf(la[i].z-ra[i].z)<.0001
  var frame=anchor.get_node_or_null("CatalogFrame")
  if frame==null:
   var distance:=INF
   for candidate in frames:
    if anchor.is_ancestor_of(candidate):continue
    var d:float=candidate.global_position.distance_to(anchor.global_position)
    if d<distance:distance=d;frame=candidate
  var mesh:Mesh=frame.find_child("Mesh0",true,false).mesh
  var size:Vector3=anchor.get_meta("passage_size")
  for z in [-.24,.24]:
   for y in [.5,1.5,2.5]:
    for side in [-1,1]:
     var hit:=frame_hit(mesh,Vector3(0,y,z),Vector3(side*5,y,z))
     if is_finite(hit.x):
      var door_point:Vector3=anchor.to_local(frame.to_global(hit))
      if absf(door_point.x)>=size.x*.5+.02:print("FIT GAP ",anchor.name," x=",door_point.x," half=",size.x*.5," frame=",frame.name)
      filled=filled and absf(door_point.x)<size.x*.5+.02
 check(aligned,"both halves share the same front depth and height on every paired door")
 check(facing,"right halves use correctly wound mirrored meshes with matching front normals")
 check(filled,"leaf pocket covers both front and back bevel openings at several frame heights")
 await physics_frame
 for entry in entries:
  var door:Dictionary=entry.door
  var hidden:=true
  for node in door.anchor.get_node("LegacyFrame").find_children("*","Node3D",true,false):
   if node.name in [&"ClosedPreview",&"OpenPreview",&"ClosedState",&"OpenState"]:hidden=hidden and not node.is_visible_in_tree()
  hidden=hidden and not door.anchor.get_node("LegacyFrame").visible
  check(hidden and door.leaf_pairs.size() in [1,2],"hidden legacy leaves and animated catalog leaves: "+str(door.anchor.name))
  var size:Vector3=door.blocker.shape.size
  var at:Vector3=door.blocker.global_position
  var normal:Vector3=door.blocker.get_parent().global_basis.z.normalized()
  var excluded:Array[RID]=[actor.get_rid()]
  var blocker_found:=false
  for attempt in 24:
   var hit=base.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(at+normal*.5,at-normal*.5,1,excluded))
   if hit.is_empty():break
   if hit.collider==door.blocker.get_parent():blocker_found=true;break
   # Existing workbench/quest barricades may stand in front of a door.
   excluded.append(hit.rid)
  check(blocker_found,"closed collision blocks aperture: "+str(door.anchor.name))
  entry.manager._apply_door_state(door,true)
 await create_timer(.25).timeout
 var moving:=true
 for entry in entries:
  for pair in entry.door.leaf_pairs:
   var travel:float=pair.closed_position.distance_to(pair.open_position)
   var moved:float=pair.leaf.position.distance_to(pair.closed_position)
   moving=moving and moved>.001 and moved<travel-.001
 check(moving,"every catalog leaf actually interpolates during opening")
 await settle()
 var cleared:=true
 for entry in entries:
  cleared=cleared and entry.door.blocker.disabled
  for pair in entry.door.leaf_pairs:cleared=cleared and pair.leaf.position.distance_to(pair.open_position)<.001
 check(cleared,"fully open leaves reach sockets and release every blocker")
 var fitted:=true
 for entry in entries:
  var anchor=entry.door.anchor
  fitted=fitted and (bool(anchor.get_meta("existing_frame"))!=anchor.has_node("CatalogFrame"))
  for body in anchor.get_node("LegacyFrame").find_children("*","CollisionObject3D",true,false):fitted=fitted and body.collision_layer==0
 check(fitted,"legacy frames and square lamps disabled; existing sci-fi recesses never receive duplicate frames")
 var manager=base.get_node("Floor_0_Base_Blockout/Doors/AutomaticDoors")
 var entrance=base.get_node("Floor_0_Base_Blockout/Doors/West_Pedestrian_Exterior_Door_Visual_Prototype")
 actor.teleport_authoritative(Vector3(-42,.1,3),-PI/2);actor.camera.rotation=Vector3.ZERO
 base.get_node("SnowExterior/Blizzard").enabled=false
 for entry in entries:entry.manager._apply_door_state(entry.door,false,true)
 await settle();await shot("entrance-closed")
 for entry in entries:entry.manager._apply_door_state(entry.door,true)
 await settle();await shot("entrance-open")
 actor.teleport_authoritative(Vector3(-13,.1,0),-PI/2);actor.camera.rotation=Vector3.ZERO
 for entry in entries:entry.manager._apply_door_state(entry.door,false,true)
 await settle();await shot("interior-pair-closed")
 for entry in entries:entry.manager._apply_door_state(entry.door,true)
 await settle();await shot("interior-pair-open")
 check(manager.debug_set_door_open(entrance,false),"existing authoritative door command accepts unchanged entrance anchor")
 check(state.maintenance.get("debug_doors",{}).has(str(manager.get_parent().get_path_to(entrance))),"existing saved door identifiers remain stable")
 var manual_door:Dictionary=manager._doors[1]
 var manual_id:=str(manager.get_parent().get_path_to(manual_door.anchor))
 snapshot=state.get_snapshot();snapshot.maintenance["pried_doors"]=[manual_id];snapshot.maintenance["manual_doors"]={manual_id:false};state._broadcast_snapshot(snapshot)
 manager._process(.1);await settle()
 check(not manual_door.open,"saved pried door retains its manual closed state")
 manager.set_pried_door_open(manual_door,true);manager._process(.1);await settle()
 check(manual_door.open and manual_door.blocker.disabled,"existing manual operation opens replacement after power restoration")
 actor.teleport_authoritative(Vector3(-60,3,50),0);actor.camera.rotation=Vector3.ZERO
 actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
 var fixture=load("res://scenes/art/doors/catalog_fitted/west_hub_decon_door_visual_blockout.tscn").instantiate()
 base.add_child(fixture);fixture.global_position=actor.camera.global_position+Vector3(0,-1.3,-5)
 var sample_world:Vector3=fixture.global_position+Vector3(-1.85,1.3,0)
 var sample_pixel:Vector2=actor.camera.unproject_position(sample_world)
 var red_image:=Image.create(1,1,false,Image.FORMAT_RGB8);red_image.fill(Color.RED)
 var red_texture:=ImageTexture.create_from_image(red_image)
 var limits:Vector2=fixture._leaf_materials[0].get_shader_parameter("aperture")
 for material in fixture._leaf_materials:
  var shader:=Shader.new();shader.code=material.shader.code.replace("render_mode cull_disabled;","render_mode unshaded, cull_disabled;")
  material.shader=shader;material.set_shader_parameter("albedo_texture",red_texture);material.set_shader_parameter("albedo",Color.WHITE)
  material.set_shader_parameter("door_world_to_local",fixture.global_transform.affine_inverse())
  material.set_shader_parameter("aperture",Vector2(100,100))
 fixture.get_node("ClosedPreview/LeftLeaf").position.x= -limits.x*.5-.06
 fixture.get_node("ClosedPreview/RightLeaf").position.x=limits.x*.5+.06
 await settle()
 var before:=root.get_texture().get_image();before.save_png(output+"/pocket-no-clipping.png")
 var before_red:=peak_red(before)
 for material in fixture._leaf_materials:material.set_shader_parameter("aperture",limits)
 await settle()
 var after:=root.get_texture().get_image();after.save_png(output+"/pocket-clipped.png")
 var after_red:=peak_red(after)
 print("POCKET RED before=",before_red," after=",after_red)
 check(before_red>.4,"control leaf is genuinely visible outside doorway when clipping is disabled")
 check(after_red<.04,"same leaf is invisible outside doorway pocket when clipping is enabled")
 fixture.queue_free()
 actor=null;entries.clear();current_scene=null;base.queue_free()
 for frame in 6:await process_frame
 print("CATALOG DOORS CHECKS ",checks," FAILURES ",failures)
 quit(1 if failures else 0)
