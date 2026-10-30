extends SceneTree
## Render through the actual player, including the separate viewmodel and HUD.
const OUTPUT := "res://tools/.local/feedback-fixes-2026-10-30/"
var checks := 0
var failures := 0
var actor: GamePlayer

func _initialize() -> void:
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
	if not label.is_empty(): result.save_png(OUTPUT+label+".png")
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

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Graphical renderer required");quit(2);return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
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
	hand_patch.queue_free();hud_patch.queue_free()
	var guest:GamePlayer=load("res://scenes/characters/player.tscn").instantiate()
	guest.name="2";guest.setup(2,"Guest",Vector3(50,0,50),Color.WHITE,0,1)
	base.add_child(guest);guest.set_physics_process(false);guest.survival.set_physics_process(false)
	await picture()
	var remote_effect:=guest.get_node("PlayerUI/CameraPostProcess")
	check(not remote_effect.visible and effect.visible,"second player never adds a second full-screen pass")
	var local_material:ShaderMaterial=effect.get_node("Effect").material
	var remote_material:ShaderMaterial=remote_effect.get_node("Effect").material
	local_material.set_shader_parameter("noise_strength",.02)
	check(local_material!=remote_material and remote_material.get_shader_parameter("noise_strength")!=.02,"material tuning remains local to each player instance")
	local_material.set_shader_parameter("noise_strength",.048)
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
	actor=null;current_scene=null;base.queue_free()
	for frame in 4:await process_frame
	check(get_nodes_in_group("local_player").is_empty(),"removing the player releases the effect with the level")
	print("CAMERA POST PROCESS CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
