extends SceneTree
## Observe the scene handoff, audio bus and actual rendered frames, not only final state.
var failures:=0
var checks:=0
var observing:=false
var scene_gaps:=0
var uncovered_staging:=0
var white_frames:=0
var checked_frames:=0
var audio_peak:=0.0
var capture:AudioEffectCapture
var vehicles_bus: int
var cabin_seen_playing:=false
var premature_players:=0

func _initialize() -> void:
	var prefix:="user://loading_handoff_%d"%OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(ExpeditionSaveStore.ROOT_SETTING,prefix+"/slots")
	ProjectSettings.set_setting("northern_lab/testing/legacy_save_paths",{})
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	create_timer(150).timeout.connect(func():quit(2))
	run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _process(_delta:float) -> bool:
	if not observing:return false
	if capture.get_frames_available()>0:
		for sample in capture.get_buffer(capture.get_frames_available()):
			audio_peak=maxf(audio_peak,maxf(absf(sample.x),absf(sample.y)))
	var scene:=current_scene
	if scene!=null and scene.has_node("CabinSound/CabinLoop"):
		cabin_seen_playing=cabin_seen_playing or scene.get_node("CabinSound/CabinLoop").playing
	return false
func rendered() -> void:
	if not observing:return
	var scene:=current_scene
	var menu:=root.get_node("GameMenu")
	var persistent_cover:Control=menu.get_node_or_null("SceneLoadCover")
	var guarded:=persistent_cover!=null and persistent_cover.visible
	var phase:="menu"
	if scene==null:
		phase="gap"
		if not guarded:scene_gaps+=1
	elif scene.has_node("CabinSound"):
		var loading:Control=scene.lobby_hud.flight_transition
		if not scene.has_node("V3Level"):phase="staging"
		else:phase="world"
		if phase=="staging" and not guarded and not loading.visible:uncovered_staging+=1
	else:return
	# Readback is confined to the handoff and the first video frames, not all loading.
	if phase in ["gap","staging"] and checked_frames<18:
		checked_frames+=1
		var picture:=root.get_texture().get_image()
		var bright:=0;var total:=0
		for y in range(0,picture.get_height(),16):
			for x in range(0,picture.get_width(),16):
				var pixel:=picture.get_pixel(x,y)
				if minf(pixel.r,minf(pixel.g,pixel.b))>.85:bright+=1
				total+=1
		var ratio:=float(bright)/total
		print("HANDOFF FRAME ",checked_frames," phase=",phase," guard=",guarded," white_ratio=",ratio)
		if ratio>.6:
			white_frames+=1
			picture.save_png("res://tools/.local/feedback-fixes-2026-10-30/loading-white-frame-%d.png"%checked_frames)
func node_entered(node:Node) -> void:
	if observing and node is GamePlayer and (current_scene==null or not current_scene.has_node("V3Level")):premature_players+=1
func run() -> void:
	Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
	var menu:=root.get_node("GameMenu")
	vehicles_bus=AudioServer.get_bus_index("Vehicles")
	capture=AudioEffectCapture.new();capture.buffer_length=1.0
	AudioServer.add_bus_effect(vehicles_bus,capture)
	var main=load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(main);current_scene=main
	await create_timer(.8).timeout
	RenderingServer.frame_post_draw.connect(rendered)
	node_added.connect(node_entered)
	for resume in [false,true]:
		scene_gaps=0;uncovered_staging=0;white_frames=0;checked_frames=0;audio_peak=0.0;cabin_seen_playing=false;premature_players=0
		capture.clear_buffer();observing=true
		await menu.start_standalone_flow(resume)
		observing=false
		print("HANDOFF SUMMARY resume=",resume," gaps=",scene_gaps," uncovered_cabin=",uncovered_staging," white=",white_frames," vehicles_peak=",audio_peak)
		check(not cabin_seen_playing and audio_peak<.000001,"solo loading never starts or mixes helicopter audio, resume="+str(resume))
		check(scene_gaps==0 and uncovered_staging==0,"scene replacement and temporary staging stay covered, resume="+str(resume))
		check(white_frames==0 and checked_frames>0,"real handoff frames contain no full-screen white flash, resume="+str(resume))
		check(premature_players==0,"solo player is first created in the attached world, not the cabin")
		var player:GamePlayer=get_first_node_in_group("local_player")
		check(current_scene.has_node("V3Level") and not current_scene.has_node("ArrivalCabin") and not current_scene.lobby_hud.flight_transition.visible and player.is_physics_processing() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"only the ready world is revealed with active player controls")
		if not resume:
			check(get_first_node_in_group("base_gameplay_controller").save_progress_authoritative(),"new world can be saved before testing Continue")
			menu.return_to_main_menu("",false)
			while menu._transition_in_progress:await process_frame
			await create_timer(.8).timeout
	AudioServer.remove_bus_effect(vehicles_bus,AudioServer.get_bus_effect_count(vehicles_bus)-1)
	current_scene.queue_free();current_scene=null
	for frame in 8:await process_frame
	print("LOADING HANDOFF CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
