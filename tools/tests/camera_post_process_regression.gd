extends SceneTree
## Render through the actual player, including the separate viewmodel and HUD.
const OUTPUT := "res://tools/.local/feedback-fixes-2026-10-30/"
var checks := 0
var failures := 0
var actor: GamePlayer
var output := OUTPUT

func _initialize() -> void:
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	var prefix := "user://camera_post_process_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	create_timer(75).timeout.connect(func():quit(2))
	run.call_deferred()

func _process(delta: float) -> bool:
	if is_instance_valid(actor): actor.update_character_animation(delta)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func picture(label: String = "") -> Image:
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var result := root.get_texture().get_image()
	if not label.is_empty(): result.save_png(output+label+".png")
	return result

func difference(a: Image, b: Image, area: Rect2i) -> float:
	var sum := 0.0
	var count := 0
	for y in range(area.position.y,area.end.y,3):
		for x in range(area.position.x,area.end.x,3):
			var before := a.get_pixel(x,y); var after := b.get_pixel(x,y)
			sum += (absf(before.r-after.r)+absf(before.g-after.g)+absf(before.b-after.b))/3.0
			count += 1
	return sum/count

func marker(parent: Node, position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position=position;rect.size=size;rect.color=color;rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect

func mean_luminance(picture: Image, area: Rect2i) -> float:
	var total := 0.0
	var count := 0
	for y in range(area.position.y,area.end.y,4):
		for x in range(area.position.x,area.end.x,4):
			total += picture.get_pixel(x,y).get_luminance()
			count += 1
	return total / count

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Graphical renderer required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	Engine.max_fps=60;root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	root.get_node("GameMenu/GraphicsQuality").set_process(false)
	var base:Node3D=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene=base
	for frame in 25:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	actor=get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false)
	base.get_node("BaseGameplayController").set_process(false)
	actor.teleport_authoritative(Vector3(-53.7224,2.02075,37.8333),0)
	actor.camera.look_at(Vector3(-17,2.5,1))
	actor.apply_held_item_inventory(&"flashlight",{"battery_charge":1.0},true)
	for frame in 30:await process_frame
	var effect:=actor.get_node("PlayerUI/CameraPostProcess")
	await picture()
	check(effect.visible,"local active camera enables the effect automatically")
	check(effect.get_node("Effect").material.shader.resource_path.ends_with("realistic_photography_camera.gdshader"),"Realistic Photography Camera replaces the previous shader")
	check(effect.get_node("Effect").size==root.get_visible_rect().size,"effect covers the player viewport")
	effect.effect_enabled=false
	var before:=await picture("camera-shader-before")
	effect.effect_enabled=true
	var after:=await picture("camera-shader-after")
	var world_difference:=difference(before,after,Rect2i(320,200,700,270))
	print("CAMERA SHADER WORLD DIFFERENCE ",world_difference)
	check(world_difference>.008,"published shader visibly changes the rendered world")
	# A solid patch in each existing layer makes draw ordering measurable.
	var hands:=actor.body_animator.first_person.overlay
	check(hands.visible,"real equipped flashlight keeps the viewmodel composite visible")
	var hand_patch:=marker(hands,Vector2(400,500),Vector2(220,140),Color(.7,.7,.7))
	var hud_patch:=marker(actor.get_node("PlayerUI"),Vector2(60,550),Vector2(150,85),Color(.8,.1,.6))
	effect.effect_enabled=false
	var plain:=await picture()
	check(absf(plain.get_pixel(500,560).r-.7)<.01,"control patch is actually rendered in the viewmodel before processing")
	effect.effect_enabled=true
	var processed:=await picture()
	check(difference(plain,processed,Rect2i(420,520,170,90))>.008,"effect includes the existing viewmodel composite")
	var hud_difference:=difference(plain,processed,Rect2i(80,570,100,40))
	print("CAMERA SHADER HUD DIFFERENCE ",hud_difference)
	check(hud_difference<.001,"HUD drawn after the effect retains exact colours")
	# Measure visible grain on a genuinely flat rendered patch, excluding grade
	# and lens distortion by comparing the same pass with grain disabled.
	var grain_material: ShaderMaterial = effect.get_node("Effect").material
	var original_grain: float = grain_material.get_shader_parameter("sensor_grain")
	var original_noise: float = grain_material.get_shader_parameter("noise_intensity")
	grain_material.set_shader_parameter("sensor_grain", 0.0)
	grain_material.set_shader_parameter("noise_intensity", 0.0)
	var grain_control := await picture()
	grain_material.set_shader_parameter("sensor_grain", original_grain)
	grain_material.set_shader_parameter("noise_intensity", original_noise)
	var grain_a := await picture("camera-film-grain-a")
	var grain_b := await picture("camera-film-grain-b")
	var grain_area := Rect2i(440,545,130,50)
	var grain_difference := difference(grain_control, grain_a, grain_area)
	var grain_temporal := difference(grain_a, grain_b, grain_area)
	print("FILM GRAIN visible=",grain_difference," temporal=",grain_temporal)
	check(grain_difference > .012 and grain_difference < .028,"stronger fine grain remains visible with a bounded amplitude")
	check(grain_temporal > .014,"film grain changes between rendered frames")
	var chroma_error := 0.0
	var chroma_count := 0
	for y in range(grain_area.position.y,grain_area.end.y,3):
		for x in range(grain_area.position.x,grain_area.end.x,3):
			var delta_color := grain_a.get_pixel(x,y) - grain_control.get_pixel(x,y)
			chroma_error += maxf(absf(delta_color.r-delta_color.g),absf(delta_color.g-delta_color.b))
			chroma_count += 1
	print("FILM GRAIN CHROMA ERROR ",chroma_error/chroma_count)
	check(chroma_error/chroma_count < .004,"rendered grain changes luminance without adding coloured speckles")
	var black_patch := marker(hands,Vector2(830,500),Vector2(220,140),Color.BLACK)
	var black_frame := await picture()
	check(black_frame.get_pixel(900,560).get_luminance()<.001,"stronger grain never lifts a completely black surface")
	black_patch.queue_free()
	hand_patch.queue_free();hud_patch.queue_free()
	var vignette_patch := marker(hands,Vector2.ZERO,Vector2(root.size),Color(0.5,0.5,0.5))
	grain_material.set_shader_parameter("sensor_grain",0.0)
	grain_material.set_shader_parameter("noise_intensity",0.0)
	var vignette_frame := await picture()
	var centre_level := mean_luminance(vignette_frame,Rect2i(680,340,50,50))
	var sides_clear := true
	for area in [Rect2i(610,4,50,12),Rect2i(610,704,50,12),Rect2i(4,310,12,50),Rect2i(1264,310,12,50),Rect2i(1190,80,30,30)]:
		sides_clear = sides_clear and absf(mean_luminance(vignette_frame,area)-centre_level)<.015
	var corners_dark := true
	for area in [Rect2i(4,4,12,12),Rect2i(1264,4,12,12),Rect2i(4,704,12,12),Rect2i(1264,704,12,12)]:
		corners_dark = corners_dark and mean_luminance(vignette_frame,area)<.001
	check(centre_level > .25 and sides_clear,"corner vignette leaves the centre and middles of all four screen edges clear")
	check(corners_dark,"all four small lens corners are black with no grain bleeding through")
	var soft_pixels := 0
	for x in range(0,220):
		var level := vignette_frame.get_pixel(x,12).get_luminance()
		if level > centre_level * .05 and level < centre_level * .95: soft_pixels += 1
	check(soft_pixels >= 12 and soft_pixels < 85,"corner boundary has a narrow soft transition while its core stays black")
	actor.set_process_unhandled_input(false)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for frame in 14:
		var motion := InputEventMouseMotion.new()
		motion.position=Vector2(640,360);motion.relative=Vector2(24,-12)
		Input.parse_input_event(motion)
		await process_frame
	var offset: Vector2 = grain_material.get_shader_parameter("vignette_offset")
	check(offset.x > .001 and offset.y < -.0005 and offset.length() <= .01201,"real mouse input moves the corners slightly in the cursor direction with blur disabled")
	var moved_rim := await picture()
	check(difference(vignette_frame,moved_rim,Rect2i(1120,0,160,110))>.003,"parallax visibly moves the rendered corner boundary")
	await create_timer(1.0).timeout
	check(Vector2(grain_material.get_shader_parameter("vignette_offset")).length()<.00015,"corner parallax smoothly returns to centre after mouse motion stops")
	grain_material.set_shader_parameter("sensor_grain",original_grain)
	grain_material.set_shader_parameter("noise_intensity",original_noise)
	vignette_patch.queue_free()
	var guest:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
	guest.name="2";guest.setup(2,"Guest",Vector3(50,0,50),Color.WHITE,0,1)
	base.add_child(guest);guest.set_physics_process(false);guest.survival.set_physics_process(false)
	await picture()
	var remote_effect:=guest.get_node("PlayerUI/CameraPostProcess")
	check(not remote_effect.visible and effect.visible,"second player never adds a second full-screen pass")
	var local_material:ShaderMaterial=effect.get_node("Effect").material
	var remote_material:ShaderMaterial=remote_effect.get_node("Effect").material
	local_material.set_shader_parameter("noise_intensity",.02)
	check(local_material!=remote_material and remote_material.get_shader_parameter("noise_intensity")!=.02,"material tuning remains local to each player instance")
	local_material.set_shader_parameter("noise_intensity",.08)
	actor.debug_free_camera.set_enabled(true)
	await picture()
	check(not effect.visible,"switching away from player camera disables its screen effect")
	actor.debug_free_camera.set_enabled(false)
	await picture()
	check(effect.visible,"returning to player camera restores the effect")
	actor.get_node("PlayerUI/SleepEyelids").set_openness(0.0)
	var asleep:=await picture()
	check(asleep.get_pixel(640,360).get_luminance()<.001,"closed eyelids remain black above the noisy camera image")
	actor.get_node("PlayerUI/SleepEyelids").set_openness(1.0)
	root.size=Vector2i(960,540)
	await picture()
	check(effect.get_node("Effect").size==root.get_visible_rect().size,"screen effect follows viewport resizing")
	check(local_material.get_shader_parameter("resolution")==Vector2(root.get_texture().get_size()),"grain resolution tracks the actual screen texture")
	actor=null;current_scene=null;base.queue_free()
	for frame in 4:await process_frame
	check(get_nodes_in_group("local_player").is_empty(),"removing the player releases the effect with the level")
	print("CAMERA POST PROCESS CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
