extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:
 ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://followup_visual_%d.cfg" % OS.get_process_id())
 ProjectSettings.set_setting("northern_lab/testing/settings_path","user://followup_settings_%d.json" % OS.get_process_id())
 run.call_deferred()
func check(value:bool,label:String) -> void:
 checks+=1
 if not value: failures+=1
 print("PASS " if value else "FAIL ",label)
func ray(space:PhysicsDirectSpaceState3D,a:Vector3,b:Vector3) -> Dictionary:
 return space.intersect_ray(PhysicsRayQueryParameters3D.create(a,b,1))
func run() -> void:
 root.get_node("GameMenu/GraphicsQuality").set_process(false)
 var main=load("res://scenes/ui/main_menu.tscn").instantiate();root.add_child(main);current_scene=main
 main.show_character("solo")
 for i in 4:await process_frame
 var selector = main.selector
 selector._update_preview_size()
 check(selector.get_node("Preview") is TextureRect and selector.preview.msaa_3d==Viewport.MSAA_8X,"menu uses supersampled texture with 8x MSAA")
 check(selector.preview.size.y>selector.get_node("Preview").size.y and selector.preview.size.y<=2160,"preview oversamples without unbounded 4K cost")
 var env:Environment=selector.preview.find_children("*","WorldEnvironment",true,false)[0].environment
 check(env.background_color==Color(0,0,0,0),"transparent AA edge has no white clear colour")
 check(selector.get_node("Preview").material.shader.code.contains("blend_premul_alpha"),"preview compositing preserves antialiased alpha edges")
 var style:StyleBoxFlat=selector.option.get_theme_stylebox("normal")
 check(style.bg_color.a>0.9 and style.bg_color.get_luminance()<0.04,"character dropdown has its own opaque dark backdrop")
 main.queue_free();await process_frame
 var base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
 var state:BaseGameplayController=base.get_node("BaseGameplayController");state.progress_persistence_enabled=false;state.set_process(false)
 for i in 8:await physics_frame
 var world:WorldLighting=base.get_node("WorldLighting")
 var sun:DirectionalLight3D=world.get_node("OvercastSun")
 check(is_equal_approx(sun.light_energy,0.42) and is_equal_approx(world.outdoor_ambient,0.13) and is_equal_approx(world.indoor_ambient,0.026),"authored world sun and ambient energies remain unchanged")
 var panel:Node3D=base.get_node("Floor_0_Base_Blockout/West_Entrance/Art/ElevatorBackupSolarPanel")
 var panel_mesh:MeshInstance3D=panel.find_children("*","MeshInstance3D",true,false)[0]
 check((panel_mesh.layers & WorldLighting.EXTERIOR_LAYER)==0,"solar panel does not receive new global directional illumination")
 var solar:StandardMaterial3D=panel_mesh.get_active_material(0)
 check(solar.emission_enabled and solar.emission_energy_multiplier<=0.02 and solar.emission_texture!=null,"solar readability is a dim textured material effect")
 var arrival:Node3D=base.get_node("ArrivalSite")
 var player:GamePlayer=get_first_node_in_group("local_player")
 var missing:=0
 for geometry in arrival.find_children("*","GeometryInstance3D",true,false):
  if geometry.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and (geometry.layers & sun.shadow_caster_mask & player.camera.cull_mask)==0:missing+=1
 check(missing==0,"arrival platform, ramp, stairs and helicopter are eligible sun shadow casters")
 var data=base.get_node("SnowExterior/Terrain3D").data
 check(data.get_height(Vector3(-37,0,8)) < -0.23,"snow under generator room is below the floor")
 check(absf(data.get_height(Vector3(-39,0,9))-0.20941177)<0.0001,"outdoor terrain by the solar panels keeps its original height")
 var shader:Shader=load("res://assets/environments/snow/terrain_cliff_cutout.gdshader")
 check(not shader.code.contains("interior_clearance_bounds"),"no rectangular room discard or outdoor terrain hole remains")
 var bunk:BaseEndDayBunk=base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
 var mesh:MeshInstance3D=bunk.get_node("BedPivot/BedModel/Sketchfab_model/unnamed")
 var bounds:AABB=mesh.global_transform*mesh.get_aabb()
 check(bounds.size.x>player.standing_height*1.1 and bounds.size.x>2.4,"bed scale leaves more than 10% length above standing character height")
 var mat:StandardMaterial3D=mesh.get_active_material(0)
 check(mat.roughness>=0.9 and mat.metallic<=0.05 and mat.metallic_specular<=0.2,"bed fabric and paint use matte material")
 var lift:FunctionalElevatorController=base.get_node("Elevator_Functional_Blockout")
 var space:PhysicsDirectSpaceState3D=lift.get_world_3d().direct_space_state
 for x in [-3.0,3.0]:
  for z in [-3.0,3.0]:
   var hit:=ray(space,Vector3(0,1.72,0),Vector3(x,1.72,z))
   check(not hit.is_empty() and str(hit.collider.get_path()).contains("InteriorCornerCovers"),"inner corner liner blocks view and physical access to guide %s %s" % [x,z])
 var front:=ray(space,Vector3(-0.6,1.72,0.7),Vector3(-3.2,1.72,2.8))
 check(not front.is_empty() and str(front.collider.get_path()).contains("EntryLiner"),"front jamb closes the photographed guide gap")
 lift.set_day(2);lift.restore_checkpoint_floor(1)
 for i in 6:await physics_frame
 var guard:Node3D=lift.get_node("Landings/Floor_0/SurfaceShaftGuard")
 check(lift.cabin.position.y < -17.0 and is_zero_approx(guard.global_position.y),"surface enclosure stays on floor zero when cabin departs")
 for spec in [[Vector3(0,1.2,-4.2),Vector3(0,1.2,-3.0),"North"],[Vector3(0,1.2,4.2),Vector3(0,1.2,3.0),"South"],[Vector3(4.2,1.2,0),Vector3(3.0,1.2,0),"East"]]:
  var hit:=ray(space,spec[0],spec[1])
  check(not hit.is_empty() and guard.is_ancestor_of(hit.collider),"absent cabin cannot be entered through side "+spec[2])
 var capsule:=CapsuleShape3D.new();capsule.radius=0.35;capsule.height=1.8
 for spec in [[Vector3(0,1.2,-4.2),Vector3(0,0,1.5)],[Vector3(0,1.2,4.2),Vector3(0,0,-1.5)],[Vector3(4.2,1.2,0),Vector3(-1.5,0,0)]]:
  var sweep:=PhysicsShapeQueryParameters3D.new();sweep.shape=capsule;sweep.transform=Transform3D(Basis.IDENTITY,spec[0]);sweep.motion=spec[1];sweep.collision_mask=1
  var travel:=space.cast_motion(sweep)
  check(travel[0]<0.9,"player-size capsule is blocked from side of the empty shaft")
 var call:Node3D=lift.get_node("Landings/Floor_0/CallButton")
 var request:=PhysicsRayQueryParameters3D.create(Vector3(-5.5,1.65,0),call.global_position,5)
 var call_hit:=space.intersect_ray(request)
 check(not call_hit.is_empty() and call_hit.collider==call,"surface call button remains reachable through the new guard")
 check(not ray(space,Vector3(-5,1.2,0),Vector3(0,1.2,0)).is_empty(),"landing door seals legitimate entrance when cabin is elsewhere")
 lift.restore_checkpoint_floor(0)
 for i in 6:await physics_frame
 var entry:=ray(space,Vector3(-5,1.2,0),Vector3(-1,1.2,0))
 check(entry.is_empty(),"guard preserves clear entrance when cabin returns")
 base.queue_free();await process_frame
 print("VISUAL FOLLOWUP CHECKS ",checks," FAILURES ",failures)
 quit(0 if failures==0 else 1)
