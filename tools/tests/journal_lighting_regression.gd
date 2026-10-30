extends SceneTree
## Same model, camera and environment; only the single lamp changes.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("A graphical renderer is required"); quit(2); return
	root.get_node("GameMenu").force_close_menu()
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	Engine.max_fps = 60; root.size = Vector2i(720,720)
	var world := Node3D.new(); root.add_child(world)
	var zone := WorldEnvironment.new(); zone.environment = Environment.new()
	zone.environment.background_mode = Environment.BG_COLOR
	zone.environment.background_color = Color.BLACK
	zone.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	zone.environment.ambient_light_energy = 0; world.add_child(zone)
	world.add_child(load("res://scenes/ui/journal/book/articulated_journal.tscn").instantiate())
	var camera := Camera3D.new(); world.add_child(camera)
	camera.position = Vector3(0,0,.8); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = .4; camera.make_current()
	var lamp := DirectionalLight3D.new(); world.add_child(lamp)
	var brightness: Array[float] = []
	for enabled in [false,true]:
		lamp.light_energy = 1 if enabled else 0
		for i in 20: await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		var sum := 0.0; var count := 0
		for y in range(int(picture.get_height()*.2),int(picture.get_height()*.8),2):
			for x in range(int(picture.get_width()*.25),int(picture.get_width()*.75),2):
				sum += picture.get_pixel(x,y).get_luminance(); count += 1
		brightness.append(sum/count)
	var dark := brightness[0] < .001
	var lit := brightness[1] > .02
	print("JOURNAL LIGHT BRIGHTNESS dark=",brightness[0]," lit=",brightness[1])
	print("PASS " if dark else "FAIL ","journal adds no visible brightness without light")
	print("PASS " if lit else "FAIL ","same journal remains visible under real illumination")
	world.queue_free(); await process_frame
	print("JOURNAL LIGHT CHECKS 2 FAILURES ",int(not dark)+int(not lit)); quit(0 if dark and lit else 1)
