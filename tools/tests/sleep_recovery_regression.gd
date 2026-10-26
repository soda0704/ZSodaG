extends SceneTree
var checks := 0
var failures := 0
var actor: GamePlayer
var output := "res://tools/.local/sleep-review"

func _initialize() -> void:
	var prefix := "user://sleep_recovery_%d" % OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+"_controls.cfg")
	create_timer(45).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(output)
	var base: Node3D = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	for frame in 25: await physics_frame
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var snapshot := state.get_snapshot()
	snapshot.day_index = 3
	snapshot.phase = BaseGameplayController.BasePhase.ACTIVE_DAY
	snapshot.main_breaker_on = true
	snapshot.elevator_backup_installed = true
	snapshot.fuel_liters = 30.0
	snapshot.fuel_delivered = true
	snapshot.containment = {"level2":true}
	state._broadcast_snapshot(snapshot)
	var bunk: BaseEndDayBunk = base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	var eyes := actor.get_node("PlayerUI/SleepEyelids")
	check(is_instance_valid(actor.body_animator.first_person_model.get_node("Journal/FrontCoverPivot/Inserts")),"journal imports and character initialization are intact")
	check(not eyes.visible,"awake player has no eyelid overlay")
	actor.survival.health = 43.0
	actor.survival.radiation = 27.0
	actor.teleport_authoritative(bunk.wake_pose.global_position,0)
	bunk.network_sleep_interact(1,actor)
	check(actor.is_sleeping_in_bunk() and eyes.visible,"actual bunk starts local eyelid animation")
	await create_timer(.2).timeout
	await capture("closing")
	await create_timer(.5).timeout
	check(is_zero_approx(float(eyes.get_node("Cover").material.get_shader_parameter("openness"))),"eyes close fully during the night")
	await capture("closed")
	check(state.day_index==3 and actor.survival.health==43 and actor.survival.radiation==27,"early sleep neither skips the timer nor grants recovery")
	check(bunk.cancel_sleep_authoritative(1,actor),"sleep can be cancelled")
	await create_timer(.6).timeout
	check(not eyes.visible and actor.survival.health==43 and actor.survival.radiation==27,"cancellation reopens eyes without healing or clearing radiation")
	actor.teleport_authoritative(bunk.wake_pose.global_position,0)
	var started := Time.get_ticks_msec()
	bunk.network_sleep_interact(1,actor)
	await create_timer(4.1).timeout
	check(state.day_index==3 and actor.is_sleeping_in_bunk(),"old cancelled timer cannot finish a new five-second night")
	while state.day_index==3 and Time.get_ticks_msec()-started<6500: await process_frame
	var duration := Time.get_ticks_msec()-started
	check(duration>=4900 and duration<6000,"successful night lasts five seconds")
	check(state.day_index==4 and not actor.is_sleeping_in_bunk(),"morning advances the existing day and wakes the player")
	check(actor.survival.health==actor.survival.max_health and is_zero_approx(actor.survival.radiation),"successful night restores full HP and clears accumulated radiation")
	await create_timer(.15).timeout
	await capture("opening")
	await create_timer(.5).timeout
	check(not eyes.visible,"eyelid presentation finishes after waking")
	var loading = load("res://scenes/ui/loading_screen.tscn").instantiate()
	check(loading.tips.any(func(tip): return tip.body=="Не забывайте поливать растение"),"plant watering reminder is in the existing loading tips")
	loading.free()
	current_scene = null
	base.queue_free()
	for frame in 4: await process_frame
	print("SLEEP RECOVERY CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
