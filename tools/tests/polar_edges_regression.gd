extends SceneTree
var checks:=0
var failures:=0
var output:="res://tools/.local/snow-material-review/edge-captures/"
func _initialize():
	var prefix:="user://polar_edges_%d"%OS.get_process_id()
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
	await create_timer(.6).timeout;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output+label+".png")
func run():
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60;root.size=Vector2i(1600,900);root.content_scale_size=root.size
	var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
	for frame in 25:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player");actor.set_physics_process(false);actor.survival.set_physics_process(false)
	actor.get_node("PlayerUI/CameraPostProcess").effect_enabled=false
	base.get_node("BaseGameplayController").set_process(false)
	var exterior=base.get_node("SnowExterior");var terrain=exterior.get_node("Terrain3D")
	var weather=exterior.get_node("Blizzard");weather.enabled=false
	var valley=exterior.get_node("CliffValley")
	check(valley.find_children("*","GPUParticles3D",true,false).is_empty() and valley.find_children("*","FogVolume",true,false).is_empty(),"no obsolete distant weather sheets remain")
	var backdrop:MeshInstance3D=valley.get_node("DistantValleyFloor")
	var fixed_mesh:Mesh=backdrop.mesh;var layers:int=backdrop.layers
	var material:ShaderMaterial=fixed_mesh.surface_get_material(0)
	var same_maps:=true
	for key in ["entry_snow_albedo","entry_snow_normal_rough","entry_snow_height"]:
		var near_map:Texture2D=terrain.material.get_shader_param(key)
		var far_map:Texture2D=material.get_shader_parameter(key)
		same_maps=same_maps and near_map!=null and far_map!=null and near_map.resource_path==far_map.resource_path
	check(same_maps,"Terrain3D and distant background use the same active PBR textures")
	check(material.shader.code.find("ALPHA")<0,"background shader has no alpha or dither output")
	check(fixed_mesh.get_aabb().end.y<12,"old 371 m distant hills replaced by low polar terrain")
	check(float(terrain.material.get_shader_param("entry_snow_normal_strength"))>.9,"active snow normals remain enabled at source strength")
	var positions:PackedVector3Array=fixed_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var seam_vertices:=0;var max_gap:=0.0;var min_gap:=INF
	for p in positions:
		if (is_equal_approx(p.x,-510) or is_equal_approx(p.x,1534)) and absf(p.z)<=766 or (is_equal_approx(absf(p.z),766) and p.x>=-510 and p.x<=1534):
			var h:float=terrain.data.get_height(p)
			if is_finite(h):max_gap=maxf(max_gap,h-p.y);min_gap=minf(min_gap,h-p.y);seam_vertices+=1
	print("BACKDROP SEAM vertices=",seam_vertices," inset range=",min_gap,"..",max_gap)
	check(seam_vertices>=7000 and min_gap>0.0 and max_gap<.1,"full background perimeter stays less than 10 cm below Terrain3D, without coincident faces")
	var views:=[
		["west",Vector3(-490,0,0),Vector3(-850,8,0)],
		["north",Vector3(-100,0,-740),Vector3(-100,8,-1100)],
		["south",Vector3(0,0,735),Vector3(0,8,1100)],
		["east-lower",Vector3(1500,0,50),Vector3(1900,-160,50)],
		["corner-lower",Vector3(1500,0,735),Vector3(1900,-160,1100)],
		["cave-rim",Vector3(200,0,0),Vector3(400,-140,0)]
	]
	for view in views:
		var at:Vector3=view[1];at.y=terrain.data.get_height(at)+.1
		actor.teleport_authoritative(at,0);actor.head.look_at(view[2])
		if view[0]=="west" and ResourceLoader.exists("res://assets/environments/cave/valley_backdrop.res"):
			backdrop.mesh=load("res://assets/environments/cave/valley_backdrop.res");backdrop.layers=262145
			await shot("edge-west-old")
			backdrop.mesh=fixed_mesh;backdrop.layers=layers
		await shot("edge-"+view[0]+"-fixed")
	var at:=Vector3(-60,0,50);at.y=terrain.data.get_height(at)+.1
	actor.teleport_authoritative(at,0);actor.head.look_at(Vector3(-57,terrain.data.get_height(Vector3(-57,0,47)),47))
	await shot("powder-relief-fixed")
	var normal_strength=terrain.material.get_shader_param("entry_snow_normal_strength")
	terrain.material.set_shader_param("entry_snow_normal_strength",0.0)
	await shot("powder-relief-disabled-control")
	terrain.material.set_shader_param("entry_snow_normal_strength",normal_strength)
	var camera:=Camera3D.new();base.add_child(camera);camera.current=true;camera.fov=55;camera.far=3000
	var height:float=terrain.data.get_height(Vector3(-60,0,50))
	camera.position=Vector3(-60,height+1.4,50);camera.look_at(Vector3(-60,height,50),Vector3.FORWARD)
	actor.body_animator.visible=false
	await shot("snow02-final-reference-close")
	actor=null;current_scene=null;base.queue_free()
	for frame in 6:await process_frame
	print("POLAR EDGE CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
