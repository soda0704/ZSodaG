extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void:
	var prefix := "user://character_choices_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+"_controls.cfg")
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,prefix+"/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	create_timer(180).timeout.connect(func():quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func wait_until(predicate: Callable, seconds: float = 60.0) -> bool:
	var deadline := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()

func mouse(point: Vector2, click: bool = false) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position=point;motion.global_position=point;motion.relative=Vector2.ONE
	root.push_input(motion,true)
	if click:
		var event := InputEventMouseButton.new()
		event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
		root.push_input(event,true)
		event=event.duplicate();event.pressed=false;root.push_input(event,true)

func hit_point(choice: TextureButton) -> Vector2:
	# Sample the chest center, not the first capsule edge that Idle can move past.
	var skeleton:Skeleton3D=choice._skeleton
	var camera:Camera3D=choice._camera
	if is_instance_valid(skeleton):
		var chest:=skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("Spine2")).origin)
		var point:=camera.unproject_position(chest)/Vector2(camera.get_viewport().size)*choice.size
		if choice._has_point(point):return choice.get_global_transform_with_canvas()*point
	for y in range(int(choice.size.y*.35),int(choice.size.y*.65),4):
		for x in range(int(choice.size.x*.4),int(choice.size.x*.6),4):
			if choice._has_point(Vector2(x,y)): return choice.global_position+Vector2(x,y)
	return Vector2(-1,-1)

func run() -> void:
	Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
	var menu := root.get_node("GameMenu")
	for variant_id in [0,1]:
		if current_scene!=null:
			current_scene.queue_free();current_scene=null;await process_frame
		menu._settings_data.CharacterVariant=1-variant_id
		var main = load("res://scenes/ui/main_menu.tscn").instantiate()
		root.add_child(main);current_scene=main
		main.show_character()
		var selector=main.selector
		if not await wait_until(func():return selector._picking_ready and not main.shell.busy,15):
			check(false,"both silhouettes finish rendering");quit(1);return
		check(selector.choices.size()==2 and selector.models.size()==2,"both production characters are present at the same time")
		check(selector.choices[0].get_global_rect().get_center().x<root.size.x*.5 and selector.choices[1].get_global_rect().get_center().x>root.size.x*.5,"character one is left and character two is right")
		check(selector.models[0].scene_file_path.contains("tactical_a") and selector.models[1].scene_file_path.contains("tactical_b") and selector.models[0].get_child_count()==2 and selector.models[1].get_child_count()==2,"both previews use the production bodies with only skeleton and Idle player")
		check(selector.previews[0].world_3d!=root.world_3d and selector.previews[0].world_3d!=selector.previews[1].world_3d,"character lighting is isolated from the game and from the other preview")
		var visible_labels:=0
		for label:Label in main.find_children("*","Label",true,false):
			if label.is_visible_in_tree() and not label.text.is_empty():visible_labels+=1
		check(visible_labels==0 and selector.find_children("*","OptionButton",true,false).is_empty(),"selection screen has no captions, dropdown or separate start button")
		main.set_menu_enabled(false)
		check(selector.choices.all(func(choice):return choice.disabled),"transition locks both choices")
		main.set_menu_enabled(true)
		if DisplayServer.get_name()!="headless":
			mouse(Vector2(12,12),true);await create_timer(.12).timeout
			check(current_scene==main and not selector._committed,"clicking empty background never selects a character")
		var point:=hit_point(selector.choices[variant_id])
		selector.choices[1-variant_id].grab_focus()
		mouse(Vector2(12,12));await create_timer(.12).timeout
		check(selector._highlighted==-1,"moving from keyboard focus to empty background clears the highlight")
		mouse(hit_point(selector.choices[1-variant_id]));await create_timer(.12).timeout
		check(selector._highlighted==1-variant_id,"pointer can switch to the other body")
		mouse(point);await create_timer(.3).timeout
		check(selector._highlighted==variant_id and menu.get_character_variant_id()==1-variant_id,"hover highlights the body without saving or starting a game")
		var material:ShaderMaterial=selector.choices[variant_id].material
		check(float(material.get_shader_parameter("highlight"))>.95 and float(selector.choices[1-variant_id].material.get_shader_parameter("highlight"))<.05,"only the hovered character has a visible outline")
		mouse(Vector2(12,12));await create_timer(.3).timeout
		check(selector._highlighted==-1 and float(material.get_shader_parameter("highlight"))<.05,"leaving a body clears its outline without sticky mouse focus")
		mouse(point);await create_timer(.25).timeout
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://tools/.local/feedback-fixes-2026-10-30/character-choice-hover-%d.png"%variant_id)
		var source_scene_id:int=main.get_instance_id()
		mouse(point,true)
		check(selector._committed and selector.choices.all(func(choice):return choice.disabled),"one native body click commits the choice and locks repeated activation")
		selector.select_variant(1-variant_id)
		if not await wait_until(func():return current_scene!=null and current_scene.get_instance_id()!=source_scene_id and not menu._transition_in_progress):
			check(false,"body click finishes direct solo loading");quit(1);return
		var session:=current_scene
		var player:GamePlayer=get_first_node_in_group("local_player")
		check(session.has_node("V3Level") and not session.is_solo_arrival() and player.character_variant_id==variant_id,"clicked character starts directly in the world")
		check(menu.get_character_variant_id()==variant_id and int(menu.load_settings_data().get("CharacterVariant",-1))==variant_id,"only the clicked character is persisted")
		check(player.body_animator.variant.variant_id==variant_id and int(session._player_roster[1].character_variant)==variant_id,"body, arms and network roster preserve the choice")
		player.survival._respawn()
		check(player.character_variant_id==variant_id,"respawn preserves the clicked character")
		if variant_id==1:
			var state:BaseGameplayController=get_first_node_in_group("base_gameplay_controller")
			check(state.save_progress_authoritative(),"selected character expedition can be saved")
			await menu.start_standalone_flow(true)
			player=get_first_node_in_group("local_player")
			check(current_scene.has_node("V3Level") and player.character_variant_id==variant_id,"Continue preserves the clicked character")
	# Use the real menu creation route with a local Steam stub, never a real lobby.
	current_scene.queue_free();current_scene=null;await process_frame
	var steam:=root.get_node("SteamNetwork")
	steam.set_script(load("res://tools/tests/fixtures/character_choice_steam_stub.gd"))
	steam.steam_available=true
	var main=load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main);current_scene=main
	main._show_coop()
	check(not main.shell.content.find_child("Character",true,false) and main.shell.content.find_child("Host",true,false)!=null and main.shell.content.find_child("Join",true,false)!=null,"coop menu contains Create and Join without a separate character button")
	menu._begin_host_session(false)
	check(main.current_view=="character" and main._character_flow=="host" and steam.created_lobbies==0,"Create Lobby first opens the two characters without creating a Steam lobby")
	if not await wait_until(func():return main.selector._picking_ready and not main.shell.busy,15):
		check(false,"coop silhouettes finish rendering");quit(1);return
	var source_scene_id:int=main.get_instance_id()
	mouse(hit_point(main.selector.choices[0]),true)
	if not await wait_until(func():return current_scene!=null and current_scene.get_instance_id()!=source_scene_id and steam.created_lobbies==1,20):
		check(false,"coop body click reaches creation");quit(1);return
	var session:=current_scene
	check(session.has_node("ArrivalCabin") and not session.has_node("V3Level") and session.is_waiting_for_arrival(),"coop body click creates one lobby and enters the aircraft")
	check(session.players.get_child_count()==1 and session.players.get_node("1").character_variant_id==0,"coop cabin player uses the clicked character exactly once")
	check(session.get_node("CabinSound/CabinLoop").playing and not session.get_node("CabinSound/CabinLoop").autoplay,"cooperative host explicitly starts cabin audio after the session exists")
	session.queue_free();current_scene=null
	for frame in 8:await process_frame
	print("SKIN SELECTION CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
