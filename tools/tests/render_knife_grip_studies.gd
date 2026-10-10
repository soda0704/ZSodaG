extends SceneTree
const OUT:="res://tools/.local/knife-grip-review-r5/"
func _initialize():run.call_deferred()
func run():
	if DisplayServer.get_name()=="headless":quit(1);return
	Engine.max_fps=60;root.size=Vector2i(1200,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.get_node("GameMenu").force_close_menu()
	var world=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(world)
	var env:Environment=world.get_node("Environment").environment;env.background_color=Color(.18,.21,.25);env.ambient_light_energy=1.1
	var camera:Camera3D=world.get_node("ReviewCamera");camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.38;camera.cull_mask=1|(1<<18);camera.near=.01
	for style in ["a"]:
		var model=load("res://scenes/characters/grip_studies/knife/"+style+".tscn").instantiate();world.add_child(model)
		model.get_node("AnimationTree").active=false;model.get_node("AnimationPlayer").play("Grip")
		for i in 12:await process_frame
		var focus:=Vector3(.22,1.21,-.39)
		for view in ["right","left","front","top","body"]:
			camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.38
			if view=="right":camera.position=focus+Vector3(.7,.04,0)
			elif view=="left":camera.position=focus+Vector3(-.7,.04,0)
			elif view=="front":camera.position=focus+Vector3(.15,.04,-.7)
			elif view=="top":camera.position=focus+Vector3(.03,.7,.04)
			else:camera.size=.95;camera.position=Vector3(.9,1.7,-1.1)
			camera.look_at(focus if view!="body" else Vector3(.02,1.32,-.12))
			for i in 4:await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT+style+"-"+view+".png")
		model.queue_free();await process_frame
		# Use the actual Player camera and its separate FP render pass.
		root.size=Vector2i(1280,720)
		var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3(0,.1,0),Color.WHITE,0,1);world.get_node("Players").add_child(actor)
		actor.survival.set_physics_process(false);actor.set_physics_process(false);actor.set_process_unhandled_input(false);actor.body_animator.set_process(false)
		actor.camera.current=true
		var fp:GameFirstPersonPresentation=actor.body_animator.first_person;fp.set_process(false);fp.model.hide()
		var study:Node3D=load("res://scenes/characters/grip_studies/knife/fp_"+style+".tscn").instantiate();fp.add_child(study)
		study.get_node("AnimationTree").active=false;study.get_node("AnimationPlayer").play("Grip")
		fp.overlay.visible=true;fp.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		fp.view_camera.global_transform=actor.camera.global_transform;fp.view_camera.fov=actor.camera.fov;fp._sync_environment()
		for i in 15:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUT+style+"-fp.png")
		print("KNIFE FP STUDY ",style," actual camera FOV ",actor.camera.fov)
		actor.queue_free();await process_frame
		root.size=Vector2i(1200,900);camera.current=true
	print("KNIFE GRIP PREVIEW RENDERED");quit()
