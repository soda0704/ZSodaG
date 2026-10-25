extends SceneTree
## Real-render checks for the page handoff and the magnifier's optical image.
var actor: GamePlayer
var journal: QuestJournalUI
var checks := 0
var failures := 0
var output := "res://tools/.local/journal-page-turn"

func _initialize() -> void:
	var prefix := "user://journal_turn_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+"_controls.cfg")
	create_timer(90).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func ticks(count: int) -> void:
	for index in count:
		if is_instance_valid(actor): actor.update_character_animation(1.0/60)
		await physics_frame
	await process_frame

func capture(label: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(output.path_join(label+".png"))
	return image

func image_delta(a: Image, b: Image, rect: Rect2i) -> float:
	var error := 0.0
	var count := 0
	for y in range(rect.position.y,rect.end.y,3):
		for x in range(rect.position.x,rect.end.x,3):
			var difference := a.get_pixel(x,y)-b.get_pixel(x,y)
			error += (absf(difference.r)+absf(difference.g)+absf(difference.b))/3
			count += 1
	return error/count

func dominant(color: Color) -> int:
	return 0 if color.r>color.g and color.r>color.b else (1 if color.g>color.b else 2)

func page_click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var page := journal._page_surfaces[0]
	var location := page.to_global(Vector3((point.x/700-.5)*.210,(.5-point.y/986)*.303,0))
	var camera: Camera3D = actor.body_animator.first_person.view_camera
	var screen := camera.unproject_position(location)*Vector2(root.size)/camera.get_viewport().get_visible_rect().size
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	Input.parse_input_event(motion)
	await process_frame
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.position = screen
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await process_frame

func verify_optics() -> void:
	var inserts = journal._inserts
	var original: Texture2D = journal._map_sheet.plan.texture
	var pattern := Image.create(800,850,false,Image.FORMAT_RGBA8)
	var colors := [Color.RED,Color.GREEN,Color.BLUE]
	for y in range(0,850,40):
		for x in range(0,800,40):
			pattern.fill_rect(Rect2i(x,y,40,mini(40,850-y)),colors[(x/40+2*(y/40))%3])
	journal._map_sheet.plan.texture = ImageTexture.create_from_image(pattern)
	journal._request_ink_update()
	# Wait rendered frames: several physics ticks may share a single image.
	for frame in 5: await process_frame
	var frame := await capture("lens-calibration")
	var ink := journal._ink_viewport.get_texture().get_image()
	ink.save_png(output.path_join("calibration-atlas.png"))
	var lens: MeshInstance3D = inserts.magnifier.get_node("Lens")
	var size: Vector2 = lens.mesh.size
	var material: ShaderMaterial = lens.material_override
	var center: Vector2 = material.get_shader_parameter("focus_atlas")
	var axis_x: Vector2 = material.get_shader_parameter("window_axis_x")
	var axis_y: Vector2 = material.get_shader_parameter("window_axis_y")
	var camera: Camera3D = actor.body_animator.first_person.view_camera
	var scores := [0.0,0.0,0.0]
	var samples := 0
	for row in range(-4,5):
		for column in range(-4,5):
			var offset := Vector2(column,row)*.08
			if offset.length()>.34: continue
			var screen := camera.unproject_position(lens.to_global(Vector3(offset.x*size.x,-offset.y*size.y,0)))
			screen *= Vector2(root.size)/camera.get_viewport().get_visible_rect().size
			var actual := dominant(frame.get_pixelv(Vector2i(screen)))
			for index in 3:
				var at := center+(axis_x*offset.x+axis_y*offset.y)/float(index+1)
				var expected := dominant(ink.get_pixelv(Vector2i(at*Vector2(ink.get_size()))))
				if actual==expected: scores[index] += 1
			samples += 1
	for index in 3: scores[index] /= samples
	print("OPTICAL IMAGE MATCH 1x/2x/3x ",scores)
	check(scores[1]>.80 and scores[1]>scores[0]+.15 and scores[1]>scores[2]+.10,"rendered glass enlarges the actual map by 2x")
	journal._map_sheet.plan.texture = original
	journal._request_ink_update()

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(output)
	var base: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await ticks(50)
	root.get_node("GameMenu").force_close_menu()
	var steam_input := root.get_node("SteamInput")
	steam_input.set_process(false)
	steam_input.set_process_input(false)
	steam_input.native_input_available = false
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	actor.has_journal = true
	actor.teleport_authoritative(Vector3(-29.9,.04,6.3),0)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var snapshot := state.get_snapshot()
	snapshot.maintenance["base_entered"] = true
	snapshot.main_breaker_on = true
	snapshot.fuel_delivered = true
	snapshot.fuel_liters = 40.0
	state._broadcast_snapshot(snapshot)
	journal = root.get_node("QuestJournal")
	journal.open_journal()
	await ticks(65)
	var inserts = journal._inserts
	if OS.get_cmdline_user_args().has("--shadow-only"):
		journal._show_section(true)
		await ticks(40)
		for frame in 5: await process_frame
		await capture("map-shadow")
		journal.force_close()
		current_scene = null
		base.queue_free()
		await ticks(3)
		quit()
		return
	# Hold the camera/book pose so a pixel comparison isolates the handoff.
	actor.body_animator.first_person.set_process(false)
	var resting := await capture("notes")
	for show_map in [true,false]:
		var previous: Texture2D = journal._ink_viewport.get_texture()
		journal._show_section(show_map)
		for frame in 8:
			await process_frame
			if inserts.busy: break
		inserts.animation.pause()
		var label := "forward" if show_map else "back"
		check(inserts.busy,"turn starts: "+label)
		check(is_equal_approx(inserts.animation.current_animation_position,0.0),"first pose is applied synchronously: "+label)
		var retained := journal._page_surfaces[1 if show_map else 0].material_override.get_shader_parameter("ink_texture") as Texture2D
		check(retained==previous,"opposite page keeps old content until covered: "+label)
		var landing: Image
		for at in [0.0,.04,.11,.22,.33,.40,.439]:
			inserts.animation.seek(at,true)
			await ticks(2)
			var frame := await capture(label+"_%03d" % roundi(at*1000))
			if at==0.0:
				var error := image_delta(resting,frame,Rect2i(200 if show_map else 790,280,590,700))
				print("FIRST POSE IMAGE ERROR ",label," ",error)
				check(error<.02,"leaf matches the resting page on its first frame: "+label)
			if at==.439: landing = frame
		inserts.animation.play("page_to_map" if show_map else "page_to_notes")
		inserts.animation.seek(.439,true)
		inserts.animation.advance(.01)
		await ticks(2)
		resting = await capture(label+"_landed")
		var error := image_delta(landing,resting,Rect2i(790 if show_map else 200,280,590,700))
		print("LANDING IMAGE ERROR ",label," ",error)
		check(error<.02,"leaf matches the resting page at landing: "+label)
		check(not journal._section_busy and not inserts.get_node("TurnPivot").visible,"landing restores input and removes moving leaf: "+label)
		for page in journal._page_surfaces:
			check(page.material_override.get_shader_parameter("ink_texture")==journal._ink_viewport.get_texture(),"landed page uses current atlas: "+page.name)
	journal._show_section(true)
	await ticks(40)
	var shadow: MeshInstance3D = inserts.get_node("MapSheet/ContactShadow")
	var shaded := await capture("map-shadow")
	shadow.hide()
	for frame in 3: await process_frame
	var unshaded := await capture("map-no-shadow")
	var shadow_delta := image_delta(shaded,unshaded,Rect2i(300,410,470,460))
	print("SHADOW IMAGE DELTA ",shadow_delta)
	check(shadow_delta>.0003,"contact shadow changes the rendered pixels around the insert")
	var edge_contrast := 0.0
	var camera: Camera3D = actor.body_animator.first_person.view_camera
	var sheet: Node3D = inserts.get_node("MapSheet")
	for index in 10:
		var at := sheet.to_global(Vector3(.080,lerpf(-.065,.065,index/9.0),-.0007))
		var screen := Vector2i(camera.unproject_position(at)*Vector2(root.size)/camera.get_viewport().get_visible_rect().size)
		var difference := unshaded.get_pixelv(screen)-shaded.get_pixelv(screen)
		edge_contrast += (difference.r+difference.g+difference.b)/30.0
	print("FREE EDGE SHADOW CONTRAST ",edge_contrast)
	check(edge_contrast>.035,"free-edge shadow is visibly darker than the book paper")
	shadow.show()
	actor.body_animator.first_person.set_process(true)
	check(journal._map_sheet.loupe_button.get_global_rect().end.x<700,"magnifier button is on the left page")
	await page_click(journal._map_sheet.loupe_button)
	await ticks(55)
	check(inserts.loupe_active and journal._map_sheet.loupe_button.button_pressed,"projected click on the left-page button raises the magnifier")
	for point in [Vector2(340,420),Vector2(480,560)]:
		inserts.set_loupe_focus(point)
		await ticks(20)
		await capture("loupe_%d" % int(point.x))
		var material: ShaderMaterial = inserts.magnifier.get_node("Lens").material_override
		check(material.get_shader_parameter("ink_texture")==journal._ink_viewport.get_texture(),"lens uses live map after repeated turns")
		var focus: Vector2 = material.get_shader_parameter("focus_atlas")
		check(focus.x>.1 and focus.x<.465 and focus.y>.18 and focus.y<.77,"optical focus lies on map")
		var axis_x: Vector2 = material.get_shader_parameter("window_axis_x")
		check(axis_x.length()>.05 and axis_x.length()<.3,"lens computes a finite projected glass footprint")
		await verify_optics()
	journal.force_close()
	current_scene = null
	base.queue_free()
	await ticks(3)
	print("JOURNAL PAGE TURN: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
