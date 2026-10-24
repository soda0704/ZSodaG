extends SceneTree
var camera:Camera3D
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://heavy_review_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func capture(label:String) -> void:
	for frame in 20: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/heavy-review/"+label+".png")
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(1);return
	Engine.max_fps=60
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute("res://tools/.local/heavy-review")
	root.get_node("GameMenu").force_close_menu()
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
	root.add_child(arena)
	camera=Camera3D.new()
	arena.add_child(camera)
	camera.make_current()
	for kind in ["sofa","bench","concrete_joist_1","concrete_joist_2"]:
		var prop:HeavyCarryProp=load("res://scenes/objects/props/"+kind+".tscn").instantiate()
		arena.add_child(prop)
		prop.freeze=true
		camera.position=Vector3(4,2.6,4.8) if not kind.begins_with("concrete") else Vector3(4,2.5,6)
		camera.look_at(Vector3(0,.6,0))
		await capture(kind)
		prop.queue_free()
		await process_frame
	var carrying_bench:HeavyCarryProp=load("res://scenes/objects/props/bench.tscn").instantiate()
	arena.add_child(carrying_bench)
	carrying_bench.position.y=.4
	carrying_bench.freeze=true
	carrying_bench.set_physics_process(false)
	var actors:Array[GamePlayer]=[]
	for peer in [1,2]:
		var actor:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
		actor.setup(peer,"Carrier",Vector3(-2.13 if peer==1 else 2.13,.02,0),Color.WHITE,-PI/2 if peer==1 else PI/2,peer-1)
		actor.name=str(peer)
		arena.get_node("Players").add_child(actor)
		actor.set_physics_process(false)
		actor.survival.set_physics_process(false)
		actor.get_node("ItemDrag").set_physics_process(false)
		actor.body_animator.set_external_view(true)
		actor.get_node("ItemDrag").heavy_body=carrying_bench
		actors.append(actor)
	var owners:Array[int]=[1,2]
	carrying_bench._receive_grips(owners,{1:0,2:1})
	camera.make_current()
	camera.position=Vector3(3.8,2.0,4)
	camera.look_at(Vector3(0,1,0))
	for frame in 50:
		for actor in actors:
			actor.velocity=Vector3.DOWN
			actor.move_and_slide()
			actor.update_character_animation(1.0/60)
		await process_frame
	await capture("paired-bench-pose")
	actors[0].body_animator.set_external_view(false)
	actors[0].camera.make_current()
	actors[0].head.rotation.x=-.55
	for frame in 30:
		actors[0].update_character_animation(1.0/60)
		await process_frame
	await capture("carry-first-person")
	actors[0].body_animator.set_external_view(true)
	camera.make_current()
	for actor in actors:actor.queue_free()
	carrying_bench.queue_free()
	await process_frame
	var controller:=BaseGameplayController.new()
	controller.name="BaseGameplayController"
	controller.progress_persistence_enabled=false
	controller.set_process(false)
	arena.add_child(controller)
	var bench:StaticBody3D=load("res://scenes/objects/crafting/flamethrower_workbench.tscn").instantiate()
	arena.add_child(bench)
	bench.position=Vector3.ZERO
	camera.position=Vector3(3,2.8,4)
	camera.look_at(Vector3(0,1.3,0))
	await capture("workbench-off")
	controller.power_state_changed.emit(true)
	await capture("workbench-on")
	bench.queue_free()
	controller.queue_free()
	await process_frame
	var floor:Node3D=load("res://scenes/levels/Floor_Minus1_Control_Security_Blockout.tscn").instantiate()
	arena.add_child(floor)
	camera.position=Vector3(-10,1.65,.1)
	camera.look_at(Vector3(-16,.8,0))
	await capture("level1-blocked-door")
	print("HEAVY VISUAL REVIEW READY")
	arena.queue_free()
	await process_frame
	quit()
