extends SceneTree
var phase := "idle"
var samples: Dictionary = {}
var _last := 0
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://loading_profile_%d.cfg" % OS.get_process_id())
	run.call_deferred()
func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _last > 0:
		if not samples.has(phase): samples[phase]=[]
		samples[phase].append((now-_last)/1000.0)
		if now - _last > 80000: print("LONG FRAME ", phase, " ", (now-_last)/1000.0)
	_last = now
	return false
func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280,720)
	root.get_node("GameMenu").force_close_menu()
	var cover = load("res://scenes/ui/loading_screen.tscn").instantiate()
	root.add_child(cover)
	cover.show_cover("ПОДГОТОВКА…")
	phase = "cover"
	await create_timer(1).timeout
	phase = "resources"
	var before := Time.get_ticks_usec()
	ResourceLoader.load_threaded_request("res://scenes/levels/Base_Blockout_v03.tscn")
	while ResourceLoader.load_threaded_get_status("res://scenes/levels/Base_Blockout_v03.tscn")==ResourceLoader.THREAD_LOAD_IN_PROGRESS: await process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get("res://scenes/levels/Base_Blockout_v03.tscn")
	print("LOAD RESOURCES MS ",(Time.get_ticks_usec()-before)/1000.0)
	phase = "instantiate"
	before = Time.get_ticks_usec()
	var world
	if "--staged" in OS.get_cmdline_user_args():
		world = await load("res://scripts/network/level_load_job.gd").new().instantiate(packed, self)
	else:
		world = packed.instantiate()
	print("INSTANTIATE MS ",(Time.get_ticks_usec()-before)/1000.0)
	world.network_runtime_managed = true
	if "--staged" in OS.get_cmdline_user_args():
		world.get_node("WorldIndirectLighting").prepare_loading()
	phase = "enter_tree"
	before = Time.get_ticks_usec()
	root.add_child(world)
	print("ENTER TREE MS ",(Time.get_ticks_usec()-before)/1000.0)
	print("NODES ",world.find_children("*","",true,false).size()," CSG ",world.find_children("*","CSGShape3D",true,false).size())
	print("GPU ",RenderingServer.get_video_adapter_name(),"; GRAPHICS ",DisplayServer.get_name(),"; CPU THREADS ", OS.get_processor_count())
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(-124,13,90)
	camera.look_at(Vector3(-35,2,0))
	camera.make_current()
	phase = "warmup"
	if "--staged" in OS.get_cmdline_user_args():
		for frame in 4: await process_frame
		phase = "lighting"
		await world.get_node("WorldIndirectLighting").finish_loading(camera.global_position.y)
		phase = "settle"
	for i in 160: await process_frame
	for key in samples:
		var values: Array = samples[key]
		values.sort()
		print("FRAME PROFILE ",key," count ",values.size()," p50 ",values[values.size()/2]," p99 ",values[mini(values.size()-1,int(values.size()*.99))]," MAX ",values.back())
	world.queue_free()
	await process_frame
	quit()
