extends SceneTree
var failures:=0
func _initialize(): run.call_deferred()
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok: failures+=1
func settle():
 for i in 5: await physics_frame
func run():
 var world:=Node3D.new()
 root.add_child(world)
 var door=load("res://scenes/art/doors/fitted/medical_hermetic_door_visual_blockout.tscn").instantiate()
 world.add_child(door)
 var player=load("res://scenes/characters/player.tscn").instantiate()
 world.add_child(player)
 player.set_physics_process(false)
 player.survival.set_physics_process(false)
 var weapon=player.weapon
 weapon.set_process(false)
 weapon.set_physics_process(false)
 await settle()
 check(weapon.metal_mark_textures.size()==16 and weapon.concrete_mark_textures.size()==20 and weapon.glass_mark_textures.size()==5,"atlases split into 16 metal, 20 concrete and 5 glass variants")
 check(weapon.snow_mark_textures.size()==1 and weapon.glass_impact_sound!=null,"snow crater and glass audio assigned through scene resources")
 var glass=door.get_node("DoorAssembly/ClosedPreview/LeftLeaf/SafetyGlass/BulletSurface")
 var metal=door.get_node("DoorAssembly/ClosedPreview/LeftLeaf/LeftLeaf/BulletSurface")
 check(ContactSurface.classify(glass,true)==&"glass" and ContactSurface.classify(metal,true)==&"metal","precise medical door surfaces distinguish glass and metal")
 var center:Vector3=glass.global_position
 var query:=PhysicsRayQueryParameters3D.create(center+Vector3(0,0,2),center-Vector3(0,0,2),16)
 var hit=world.get_world_3d().direct_space_state.intersect_ray(query)
 check(not hit.is_empty() and hit.collider==glass,"ray passes through metal aperture and hits actual safety glass")
 var blocker:=StaticBody3D.new()
 blocker.set_script(load("res://scripts/gameplay/base/pry_door_interaction.gd"))
 world.add_child(blocker)
 blocker.set("door",{"visual":door})
 var fallback={"collider":blocker,"position":center+Vector3(0,0,0.12),"normal":Vector3.BACK}
 var precise=blocker.resolve_bullet_hit(center+Vector3(0,0,2),center-Vector3(0,0,2),fallback)
 check(precise.collider==glass,"door passage blocker resolves shot onto actual glass")
 weapon._impact(hit.position,hit.normal,glass.get_path(),glass.to_local(hit.position),&"glass",glass.global_basis.inverse()*hit.normal)
 var marks=get_nodes_in_group("weapon_impacts")
 check(marks.size()==1 and marks[0].get_parent()==glass,"glass mark follows authored moving glass surface")
 check(root.get_children().any(func(node): return node is AudioStreamPlayer3D and node.stream==weapon.glass_impact_sound),"glass hit selects provided glass sound instead of concrete")
 var mark:Node3D=marks[0]
 check(mark.global_basis.z.dot(hit.normal)>0.999,"mark plane faces collision normal")
 var before:=mark.global_position
 glass.get_parent().get_parent().position.x-=0.5
 check(mark.global_position.distance_to(before-Vector3(0.5,0,0))<0.001,"mark moves with sliding door leaf")
 weapon.max_surface_marks=3
 for i in 8: weapon._impact(Vector3.ZERO,Vector3.UP,metal.get_path(),Vector3.ZERO,&"metal",Vector3.UP)
 await settle()
 check(get_nodes_in_group("weapon_impacts").size()==3,"global mark limit removes oldest marks under automatic fire")
 var count=get_nodes_in_group("weapon_impacts").size()
 weapon._impact(Vector3.ZERO,Vector3.UP,metal.get_path(),Vector3.ZERO,&"")
 check(get_nodes_in_group("weapon_impacts").size()==count,"knife and living targets do not receive bullet holes")
 weapon.mark_lifetime=0.2
 weapon.mark_fade_seconds=0.1
 weapon._impact(Vector3.ZERO,Vector3.UP,metal.get_path(),Vector3.ZERO,&"snow",Vector3.UP)
 var newest=get_nodes_in_group("weapon_impacts").filter(func(node): return not node.is_queued_for_deletion() and node.get_node("Mark").texture==weapon.snow_mark_textures[0])[0]
 check(newest.get_node("Mark").texture==weapon.snow_mark_textures[0],"snow uses crater image instead of procedural sphere")
 await create_timer(0.4).timeout
 check(not is_instance_valid(newest),"mark fades and frees itself after configured lifetime")
 world.queue_free()
 await settle()
 print("RESULT FAILURES ",failures)
 quit(1 if failures else 0)
