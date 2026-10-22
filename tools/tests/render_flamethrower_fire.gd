extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.get_node("GameMenu").force_close_menu();Engine.max_fps=60
	root.size=Vector2i(1400,900)
	var world: Node3D=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();root.add_child(world);current_scene=world
	var env: Environment=world.get_node("Environment").environment
	env.background_color=Color(.018,.023,.03);env.ambient_light_energy=.08
	world.get_node("Key").light_energy=.12;world.get_node("Fill").light_energy=.05
	var actor: GamePlayer=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3(0,.05,0),Color.WHITE,0,0);world.get_node("Players").add_child(actor)
	actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.set_process_unhandled_input(false)
	actor.weapon.flame.set_physics_process(false)
	actor.pickup_world_item_authoritative(&"flamethrower",{})
	var review: Camera3D=world.get_node("ReviewCamera")
	review.projection=Camera3D.PROJECTION_PERSPECTIVE;review.fov=65;review.near=.01
	for view in ["side","first_person"]:
		actor.body_animator.set_external_view(view!="first_person")
		if view=="first_person":actor.camera.current=true
		else:review.current=true;review.position=Vector3(5.3,2.6,1.0);review.look_at(Vector3(0,1.4,-2.7))
		for frame in 90:
			actor.body_animator.update_context(.016,{"held_item":&"flamethrower","grounded":true,"velocity":Vector3.ZERO,"yaw":0.0,"pitch":0.0})
			actor.weapon.flame.set_trigger_authoritative(true);actor.weapon.flame.step_authoritative(.016)
			await process_frame
		await RenderingServer.frame_post_draw
		print("JET ",view," ",actor.weapon.flame.physics_jet()," EFFECT ",actor.weapon.flame.effect.global_transform," AABB ",actor.weapon.flame.effect.get_node("Flames").capture_aabb())
		root.get_texture().get_image().save_png(OS.get_environment("TEMP").path_join("NorthernLab-fire-"+view+".png"))
	actor.weapon.flame.stop_authoritative()
	for frame in 20:await process_frame
	world.queue_free();await process_frame;print("FIRE_PREVIEW_READY");quit()
