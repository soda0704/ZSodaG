extends SceneTree
var checks:=0
var failures:=0
var output:="res://tools/.local/snow-material-review/tiling/"
func _initialize():
 if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
 run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func capture(label:String)->Image:
 for frame in 30:await process_frame
 await RenderingServer.frame_post_draw
 var image:=root.get_texture().get_image();image.save_png(output+label+".png");return image
func statistics(image:Image)->Vector2:
 var a:Array[float]=[];var b:Array[float]=[];var mean_a:=0.0;var mean_b:=0.0
 # Eight-tile orthographic view at 512 px: exact one-tile offset = 64 pixels.
 for y in range(32,480,2):
  for x in range(32,416,2):
   var first:=image.get_pixel(x,y).get_luminance();var next:=image.get_pixel(x+64,y).get_luminance()
   a.append(first);b.append(next);mean_a+=first;mean_b+=next
 mean_a/=a.size();mean_b/=b.size()
 var covariance:=0.0;var va:=0.0;var vb:=0.0
 for i in a.size():covariance+=(a[i]-mean_a)*(b[i]-mean_b);va+=pow(a[i]-mean_a,2);vb+=pow(b[i]-mean_b,2)
 return Vector2(covariance/sqrt(maxf(va*vb,.0000001)),sqrt(va/a.size()))
func broad_shading(image:Image)->float:
 # Average away the small scanned grooves; retain the unwanted metre-sized light patches.
 var values:Array[float]=[];var mean:=0.0
 for by in range(32,480,32):
  for bx in range(32,480,32):
   var total:=0.0
   for y in range(by,by+32,2):
    for x in range(bx,bx+32,2):total+=image.get_pixel(x,y).get_luminance()
   values.append(total/256.0);mean+=values[-1]
 mean/=values.size()
 var variance:=0.0
 for value in values:variance+=pow(value-mean,2)
 return sqrt(variance/values.size())
func run():
 root.get_node("GameMenu/FPSCounter").set_enabled(false)
 DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(512,512);root.content_scale_size=root.size;Engine.max_fps=60
 var scene:=Node3D.new();root.add_child(scene);current_scene=scene
 var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.3;scene.add_child(environment)
 var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-35,-40,0);sun.light_energy=1.5;scene.add_child(sun)
 var surface:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(18,18);surface.mesh=plane;scene.add_child(surface)
 var material:ShaderMaterial=load("res://assets/environments/snow/meshes/polar_backdrop.res").surface_get_material(0).duplicate();surface.material_override=material
 var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=float(material.get_shader_parameter("entry_snow_tile_size"))*8.0;camera.position=Vector3(0,10,0);scene.add_child(camera);camera.look_at(Vector3.ZERO,Vector3.FORWARD);camera.current=true
 material.set_shader_parameter("entry_snow_variation",false)
 var old_image:=await capture("snow-tiling-periodic-control")
 var old:=statistics(old_image)
 material.set_shader_parameter("entry_snow_variation",true)
 var varied_image:=await capture("snow-tiling-varied")
 var varied:=statistics(varied_image)
 print("TILING correlation/contrast old=",old," varied=",varied)
 check(old.x>.65,"control records strong one-tile image repetition")
 check(varied.x<old.x-.15,"variation reduces one-tile image autocorrelation")
 check(varied.y>old.y*.45,"variation retains visible relief contrast rather than hiding repetition by blur")
 var coarse_old:=broad_shading(old_image);var coarse_new:=broad_shading(varied_image)
 print("SNOW BROAD SHADING old=",coarse_old," varied=",coarse_new)
 check(coarse_new<maxf(coarse_old*1.75,.012),"variation does not introduce metre-sized bright and dark grid patches")
 camera.projection=Camera3D.PROJECTION_PERSPECTIVE;camera.fov=65
 camera.position=Vector3(0,1.0,3);camera.look_at(Vector3(0,0,0))
 material.set_shader_parameter("entry_snow_relief_metres",.006)
 var relief:=await capture("snow-height-near-enabled")
 material.set_shader_parameter("entry_snow_relief_metres",0.0)
 var flat:=await capture("snow-height-near-disabled")
 var difference:=image_difference(relief,flat)
 print("SNOW HEIGHT NEAR DIFFERENCE ",difference)
 check(difference>.0001,"small Height relief visibly affects a grazing view")
 camera.position=Vector3(0,10,25);camera.look_at(Vector3.ZERO)
 material.set_shader_parameter("entry_snow_relief_metres",.006)
 relief=await capture("snow-height-far-enabled")
 material.set_shader_parameter("entry_snow_relief_metres",0.0)
 flat=await capture("snow-height-far-disabled")
 difference=image_difference(relief,flat)
 print("SNOW HEIGHT FAR DIFFERENCE ",difference)
 check(difference<.00005,"Height relief fades out in the distance")
 current_scene=null;scene.queue_free()
 for frame in 8:await process_frame
 print("SNOW TILING CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
func image_difference(a:Image,b:Image)->float:
 var total:=0.0;var count:=0
 for y in range(48,464,2):
  for x in range(48,464,2):total+=absf(a.get_pixel(x,y).get_luminance()-b.get_pixel(x,y).get_luminance());count+=1
 return total/count
