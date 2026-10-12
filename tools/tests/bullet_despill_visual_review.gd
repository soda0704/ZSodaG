extends SceneTree
func _initialize():run.call_deferred()
func run():
 root.size=Vector2i(1200,800);root.get_node("GameMenu").force_close_menu()
 var world:=Node3D.new();root.add_child(world)
 var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(.08,.08,.08);env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=1.;world.add_child(env)
 var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,0,2);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=1.5;camera.current=true
 for col in 3:
  var panel:=MeshInstance3D.new();panel.mesh=QuadMesh.new();panel.mesh.size=Vector2(.72,1.45);panel.position=Vector3((col-1)*.75,0,0)
  var mat:=StandardMaterial3D.new();mat.albedo_color=[Color(.45,.45,.45),Color(.32,.20,.12),Color(.11,.16,.23)][col];mat.roughness=1.;panel.material_override=mat;world.add_child(panel)
  for row in 4:
   var texture:Texture2D=load("res://assets/effects/bullet_marks/concrete_%02d.tres"%[row*4])
   for before in [true,false]:
    var mark=load("res://scenes/objects/effects/bullet_surface_mark.tscn").instantiate();world.add_child(mark)
    mark.position=panel.position+Vector3(-.18 if before else .18,.52-row*.34,.003)
    mark.configure(texture,.26,90.,5.)
    if before:mark.get_node("Mark").material_override=null
 for i in 12:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://tools/.local/bullet-despill-surfaces.png")
 print("BULLET DESPILL VISUAL REVIEW COMPLETE");quit()
