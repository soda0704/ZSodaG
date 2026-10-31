extends SceneTree
## Compare the native energy clips with the previous visual states in the same real room.
var checks:=0
var failures:=0
var output:="res://tools/.local/frame-spikes/workbench-visual"
var material:StandardMaterial3D
func _initialize():
	var prefix:="user://bench_emission_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	run.call_deferred()
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func settle():
	for i in 8:await process_frame
func capture(label:String)->Image:
	await settle();await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	image.save_png(output.path_join(label+".png"));return image
func difference(a:Image,b:Image)->float:
	var size:=a.get_size();var total:=0.;var count:=0
	for y in range(0,size.y,3):
		for x in range(0,size.x,3):
			var one:=a.get_pixel(x,y);var two:=b.get_pixel(x,y)
			total+=absf(one.r-two.r)+absf(one.g-two.g)+absf(one.b-two.b);count+=3
	return total/maxi(count,1)
func run():
	if DisplayServer.get_name()=="headless":push_error("Graphical comparison required");quit(1);return
	Engine.max_fps=60;root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output)
	var base:Node3D=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
	await settle();root.get_node("GameMenu").force_close_menu()
	var player:GamePlayer=get_first_node_in_group("local_player");player.set_physics_process(false);player.survival.set_physics_process(false)
	var state:BaseGameplayController=base.get_node("BaseGameplayController");state.progress_persistence_enabled=false;state.set_process(false)
	var snapshot:=state.get_snapshot();snapshot.main_breaker_on=true;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.;state._broadcast_snapshot(snapshot)
	var bench:=base.get_node("FlamethrowerWorkbench")
	material=bench.get_node("WorkbenchVisual").material_override
	var identity:=material.get_rid()
	var camera:=Camera3D.new();base.add_child(camera);camera.global_position=bench.global_position+Vector3(-3,1.6,2);camera.look_at(bench.global_position+Vector3.UP*.85);camera.make_current()
	for i in 45:await process_frame
	var lighting:=base.get_node("WorldLighting");lighting.set_process(false)
	for body in base.find_children("*","RigidBody3D",true,false):body.freeze=true
	var animation:AnimationPlayer=bench.get_node("Power")
	check(material.emission_enabled and is_equal_approx(material.emission_energy_multiplier,1.0),"first powered frame already has the original authored emission")
	for enabled in [false,true]:
		bench._on_power_changed(enabled)
		check(material.emission_enabled,"native %s clip keeps the emission shader feature stable"%enabled)
		check(is_equal_approx(material.emission_energy_multiplier,1.0 if enabled else 0.0),"native %s clip sets the authored light output"%enabled)
		check(material.get_rid()==identity,"power change retains the original material instance")
		var image:Image=await capture("new_on" if enabled else "new_off")
		animation.stop(true);material.emission_enabled=enabled;material.emission_energy_multiplier=1.0
		var previous:Image=await capture("legacy_on" if enabled else "legacy_off")
		var error:=difference(image,previous)
		print("WORKBENCH IMAGE DIFFERENCE ",enabled," ",error)
		check(error<.012,"%s output matches the previous rendering within temporal-shadow tolerance"%enabled)
		material.emission_enabled=true
	await settle()
	var before:=int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))
	for i in 8:
		bench._on_power_changed(i%2==0);await settle()
	check(int(Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SURFACE))==before,"eight native power toggles cause no new surface shader compilations")
	bench._on_power_changed(false)
	check(bench.get_node("WorkbenchVisual").visible and bench.collision_layer!=0,"unpowered workbench keeps its existing visible mesh and physics")
	current_scene=null;base.queue_free();await settle()
	print("WORKBENCH EMISSION CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
