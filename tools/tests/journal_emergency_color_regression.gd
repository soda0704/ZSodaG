extends SceneTree
var actor:GamePlayer
var checks:=0
var failures:=0
var output:="res://tools/.local/feedback-fixes-2026-10-30/"
func _initialize() -> void:
	if not OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR").is_empty():output=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")+"/"
	var prefix:="user://journal_red_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	run.call_deferred()
func _process(delta:float) -> bool:
	if is_instance_valid(actor):actor.update_character_animation(delta)
	return false
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
	var base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate()
	root.add_child(base);current_scene=base
	for frame in 20:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	actor=get_first_node_in_group("local_player")
	actor.set_physics_process(false);actor.survival.set_physics_process(false)
	actor.teleport_authoritative(Vector3(-5,.1,3),0)
	actor.camera.look_at(Vector3(-10,2,0))
	var state:BaseGameplayController=base.get_node("BaseGameplayController")
	state.set_process(false)
	var snapshot:=state.get_snapshot();snapshot.main_breaker_on=false
	state._broadcast_snapshot(snapshot)
	var lighting:WorldLighting=base.get_node("WorldLighting")
	lighting.set_process(false);lighting._indoor_mix=1.0
	lighting.get_node("EmergencyAlarm").stop()
	actor.has_journal=true
	var journal:=root.get_node("QuestJournal")
	journal.open_journal()
	await create_timer(1.0).timeout
	var fp:GameFirstPersonPresentation=actor.body_animator.first_person
	var fill:DirectionalLight3D=fp._lighting_fill
	check(journal.is_journal_open() and fp.model.visible,"real 3D journal is open in the player viewmodel")
	var dark_ok:=true;var red_ok:=true;var observed_red:=false
	for mode in [false,true]:
		root.get_node("GameMenu/GraphicsQuality").set_gi_quality(2 if mode else 0)
		for cycle in 3:
			for pulse in [1.0,.5,.02,0.0,0.0,.001,.1,1.0]:
				lighting.emergency_intensity=pulse
				lighting.emergency_intensity_changed.emit(pulse)
				lighting._update_lamps(actor.camera.global_position,1.0)
				var target:=lighting.sample_view_light(actor.camera)
				fp._update_lighting(1.0/60.0)
				if maxf(target.r,maxf(target.g,target.b))<=.0001:
					dark_ok=dark_ok and fill.light_energy==0.0
				elif target.r>maxf(target.g,target.b)*4.0:
					observed_red=true
					red_ok=red_ok and fill.light_color.r>fill.light_color.g*4.0 and fill.light_color.r>fill.light_color.b*4.0
				await RenderingServer.frame_post_draw
		check(dark_ok,"journal lighting reaches black without white residual energy, advanced="+str(mode))
		check(observed_red and red_ok,"every red-only lighting sample stays red before and during each burst, advanced="+str(mode))
		lighting.emergency_intensity=1.0
		lighting.emergency_intensity_changed.emit(1.0)
		lighting._update_lamps(actor.camera.global_position,1.0)
		for frame in 12:await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"journal-red-"+str(mode)+".png")
	journal.force_close();actor=null;current_scene=null;base.queue_free()
	for frame in 6:await process_frame
	print("JOURNAL RED CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
