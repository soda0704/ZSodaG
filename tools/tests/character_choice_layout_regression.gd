extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:
	ProjectSettings.set_setting("northern_lab/testing/settings_path","user://character_choice_layout_%d.json"%OS.get_process_id())
	run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func settle(selector:Control) -> void:
	for frame in 24:await process_frame
	var limit:=Time.get_ticks_msec()+5000
	while not selector._picking_ready and Time.get_ticks_msec()<limit:await process_frame
func check_shader(material:ShaderMaterial) -> void:
	var view:=SubViewport.new()
	view.size=Vector2i(64,64);view.transparent_bg=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var image:=Image.create(64,64,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(16,16,32,32),Color.WHITE)
	var card:=TextureRect.new()
	card.texture=ImageTexture.create_from_image(image);card.size=Vector2(64,64)
	card.material=material.duplicate()
	card.material.set_shader_parameter("entrance",1.0)
	card.material.set_shader_parameter("highlight",0.0)
	view.add_child(card)
	for frame in 3:await RenderingServer.frame_post_draw
	var dark:=view.get_texture().get_image()
	dark.save_png("res://tools/.local/feedback-fixes-2026-10-30/silhouette-shader-probe.png")
	print("SILHOUETTE PIXELS source=",image.get_pixel(14,32)," bounds=",dark.get_used_rect()," body=",dark.get_pixel(32,32)," outline=",dark.get_pixel(14,32))
	check(absf(dark.get_pixel(32,32).a-.85)<.02 and dark.get_pixel(32,32).r<.04,"inactive body is nearly black with slight transparency")
	check(absf(dark.get_pixel(14,32).a-.85)<.02 and dark.get_pixel(14,32).r<.01,"inactive outer contour is black with slight transparency")
	card.material.set_shader_parameter("highlight",1.0)
	for frame in 2:await RenderingServer.frame_post_draw
	var active:=view.get_texture().get_image()
	check(active.get_pixel(32,32).r>.99 and active.get_pixel(14,32).r>.99,"highlight reveals body colour and turns contour white")
	card.material.set_shader_parameter("entrance",.5)
	for frame in 2:await RenderingServer.frame_post_draw
	check(absf(view.get_texture().get_image().get_pixel(32,32).a-.5)<.02,"entrance fades body and outline together")
	view.queue_free()
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(1);return
	Engine.max_fps=60
	var main=load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main);current_scene=main;main.show_character("coop")
	var selector=main.selector
	var load_limit:=Time.get_ticks_msec()+5000
	while selector.models.size()<2 and Time.get_ticks_msec()<load_limit:await process_frame
	check(not selector._picking_ready,"characters cannot be chosen during their entrance")
	selector.select_variant(0)
	check(not selector._committed and main.current_view=="character","early activation does not interrupt appearance")
	await create_timer(.2).timeout
	check(float(selector.choices[0].material.get_shader_parameter("entrance"))>0 and float(selector.choices[0].material.get_shader_parameter("entrance"))<1 and selector.models[0].position.x>0,"entry progressively fades and slides characters inward")
	await settle(selector)
	check(selector._picking_ready and selector.models[0].position.is_zero_approx() and selector.models[1].position.is_zero_approx(),"entry finishes before enabling character activation")
	await check_shader(selector.choices[0].material)
	for resolution:Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1080),Vector2i(1024,768)]:
		root.size=resolution;root.content_scale_size=resolution
		await settle(selector)
		check(selector._picking_ready,"silhouette input is ready at "+str(resolution))
		var torso_framing:=true
		for index in 2:
			var view:SubViewport=selector.previews[index]
			var picture:=view.get_texture().get_image()
			var used:=picture.get_used_rect()
			var camera:Camera3D=view.get_node("Camera")
			var skeleton:Skeleton3D=selector.models[index].get_node("Skeleton3D")
			var head:=camera.unproject_position(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("HeadTop_End")).origin))
			var hips:=camera.unproject_position(skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Hips")).origin))
			torso_framing=torso_framing and used.position.y>12 and head.y>12 and head.y<picture.get_height()*.5 and hips.y>picture.get_height()*.85
			torso_framing=torso_framing and float(used.position.y)/view.size.y*selector.choices[index].size.y>main.shell.top_rail.size.y+4
			var point:Vector2=Vector2(head.x,head.y)/Vector2(view.size)*selector.choices[index].size
			torso_framing=torso_framing and selector.choices[index]._has_point(point) and not selector.choices[index]._has_point(Vector2(4,4))
			print("CHOICE BOUNDS ",resolution," index=",index," image=",picture.get_size()," body=",used," head=",head," hips=",hips," keep=",camera.keep_aspect," projection_y=",camera.get_camera_projection().y.y)
		check(torso_framing,"both heads and torsos are close, with working body picking at "+str(resolution))
		await RenderingServer.frame_post_draw
		var screen:=root.get_texture().get_image()
		check(screen.get_pixel(screen.get_width()/2,4).is_equal_approx(Color.BLACK) and screen.get_pixel(screen.get_width()/2,screen.get_height()-5).is_equal_approx(Color.BLACK),"top and bottom bars stay black at "+str(resolution))
		root.get_texture().get_image().save_png("res://tools/.local/feedback-fixes-2026-10-30/character-choice-%dx%d.png"%[resolution.x,resolution.y])
	selector.hide();root.size=Vector2i(1366,768);root.content_scale_size=root.size
	for frame in 12:await process_frame
	selector.show();await settle(selector)
	check(selector._picking_ready,"body picking stays available after a hidden resize")
	selector.choices[1].grab_focus()
	check(selector._highlighted==1,"keyboard focus highlights the second character")
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/feedback-fixes-2026-10-30/character-close-hover.png")
	var back_button:Button=main.shell.footer.get_node("CharacterBack")
	check(back_button.is_visible_in_tree() and back_button.get_global_rect().get_center().y>root.size.y-87,"Back is visible in the bottom black bar")
	var point:=back_button.get_global_rect().get_center()
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.position=point
		click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed
		root.push_input(click,true)
	await create_timer(.15).timeout
	check(main.current_view=="character" and selector._exiting and not selector._picking_ready,"Back starts an exit and locks selection before replacing the page")
	check(float(selector.choices[1].material.get_shader_parameter("entrance"))>0.0 and float(selector.choices[1].material.get_shader_parameter("entrance"))<1.0,"characters visibly fade during exit rather than disappearing at once")
	await create_timer(1.2).timeout
	check(main.current_view=="coop" and main.selector==null,"native Back click returns from character selection to coop")
	check(main.shell.header.visible and main.shell.footer.visible,"regular menu restores its rail captions")
	main.show_character("solo");await settle(main.selector)
	var event:=InputEventAction.new();event.action=&"ui_cancel";event.pressed=true
	root.push_input(event,true)
	await create_timer(1.4).timeout
	check(main.current_view=="home" and main.selector==null,"Escape still returns from solo selection to the main menu")
	main.queue_free();current_scene=null
	for frame in 6:await process_frame
	print("CHARACTER LAYOUT CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
