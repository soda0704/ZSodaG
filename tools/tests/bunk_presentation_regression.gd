extends SceneTree
var checks:=0
var failures:=0
var actors:Array[GamePlayer]=[]
var output:="res://tools/.local/bunk-review"
var base:Node3D
func _initialize():
	var prefix:="user://bunk_motion_%d"%OS.get_process_id()
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,prefix+".cfg")
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,prefix)
	create_timer(55).timeout.connect(func():quit(2))
	run.call_deferred()
func _process(delta:float):
	for actor in actors:
		if is_instance_valid(actor):actor.update_character_animation(delta)
	return false
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func capture(label:String,bunk:BaseEndDayBunk=null):
	if DisplayServer.get_name()=="headless":return
	if bunk==null:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label+".png"));return
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.world_3d=base.get_world_3d();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera)
	camera.global_position=bunk.wake_pose.global_position+Vector3.UP*.65
	camera.look_at(bunk.sleep_pose.global_position+Vector3.UP*.35)
	actors[0].body_animator.set_external_view(true)
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(output.path_join(label+".png"))
	actors[0].body_animator.set_external_view(false);viewport.queue_free()
func run():
	Engine.max_fps=60;root.size=Vector2i(1280,720);DirAccess.make_dir_recursive_absolute(output)
	base=load("res://scenes/levels/base_blockout_v03.tscn").instantiate();root.add_child(base);current_scene=base
	for i in 25:await physics_frame
	root.get_node("GameMenu").force_close_menu()
	var actor:GamePlayer=get_first_node_in_group("local_player");actors.append(actor);actor.set_physics_process(false);actor.survival.set_physics_process(false)
	var state:BaseGameplayController=base.get_node("BaseGameplayController");state.set_process(false)
	base.get_node("BaseDayProgressionController").sleep_duration=30
	await create_timer(.4).timeout
	var notice:=actor.get_node("PlayerUI/NorthernLabHUD/PowerSwitchNotice")
	check(not notice.visible,"binding an already loaded base never replays the switch notice")
	var snapshot:=state.get_snapshot();snapshot.day_index=3;snapshot.phase=BaseGameplayController.BasePhase.ACTIVE_DAY;snapshot.main_breaker_on=true;snapshot.fuel_delivered=true;snapshot.fuel_liters=30.;snapshot.containment={"level2":true};snapshot.maintenance.erase("wires_required");state._broadcast_snapshot(snapshot)
	var bunk:BaseEndDayBunk=base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable01")
	actor.teleport_authoritative(bunk.wake_pose.global_position,0)
	for i in 3:await physics_frame
	actor.camera.look_at(bunk.sleep_pose.global_position)
	var target:=actor.get_interaction_target()
	check(target!=null and target.has_method("network_interact") and (target==bunk or bunk.is_ancestor_of(target)),"the actual bed surface can be selected by the player's interaction ray")
	actor.camera.reset_motion()
	var source:=actor.head.global_transform
	bunk.network_sleep_interact(1,actor)
	check(actor.is_sleeping_in_bunk(),"E on the existing bunk starts its authoritative sleep")
	check(actor.head.global_position.distance_to(source.origin)<.01,"entry preserves the camera position on the first frame")
	await create_timer(.45).timeout
	check(actor.get_node("BunkSleep").pose_time>.2 and actor.get_node("BunkSleep").pose_time<1.0,"lying down passes through an animated intermediate pose")
	check(actor.get_node("BunkSleep").eye_openness>.95,"eyes stay open while sitting onto the mattress")
	await capture("sitting",bunk)
	await create_timer(1.0).timeout
	check(actor.body_animator.global_position.distance_to(bunk.sleep_pose.global_position)<.01,"the body settles on the authored bed marker")
	check(actor.head.position.distance_to(Vector3(0,.3,-1.22))<.02,"sleeping camera rests at the pillow and faces the ceiling")
	check(actor.get_node("PlayerUI/SleepEyelids").visible and actor.get_node("BunkSleep").eye_openness<.001,"eyes close only after the character lies down")
	await capture("lying",bunk)
	var guest:GamePlayer=load("res://scenes/characters/player.tscn").instantiate();guest.name="2";guest.setup(2,"Guest",Vector3.ZERO,Color.WHITE,0,1);base.add_child(guest);guest.set_physics_process(false);guest.survival.set_physics_process(false);actors.append(guest)
	var bunk2:BaseEndDayBunk=base.get_node("Floor_0_Base_Blockout/Gameplay/EndDayBunkInteractable02")
	guest.enter_bunk_sleep_authoritative(bunk2.sleep_pose.global_transform)
	await create_timer(1.4).timeout
	for person in actors:
		var sk:Skeleton3D=person.body_animator.skeleton
		var head:=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("Head")).origin
		var foot:=sk.global_transform*sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin
		check(absf(head.y-foot.y)<.45,"variant %d lies horizontally on its own mattress"%person.character_variant_id)
	check(bunk.cancel_sleep_authoritative(1,actor),"sleep cancellation starts an animated exit from the bed")
	check(actor.is_bunk_busy() and not actor.is_sleeping_in_bunk(),"getting up blocks controls without pretending the player is still asleep")
	await create_timer(.5).timeout
	check(actor.get_node("BunkSleep").eye_openness>.4 and actor.is_bunk_busy(),"waking opens the eyes before standing finishes")
	await capture("waking")
	await capture("getting_up",bunk)
	await create_timer(1.0).timeout
	check(not actor.is_bunk_busy() and not actor.get_node("PlayerUI/SleepEyelids").visible,"standing restores controls and clears the eyelid overlay")
	check(actor.head.position.distance_to(Vector3(0,actor.standing_head_height,0))<.01 and actor.body_animator.transform.origin.length()<.01,"get-up finishes at the normal camera and body offsets")
	var standing_sk:Skeleton3D=actor.body_animator.skeleton
	check((standing_sk.global_transform*standing_sk.get_bone_global_pose(standing_sk.find_bone("Head")).origin).y-actor.global_position.y>1.1,"releasing the bed blend keeps the body standing without a prone-frame snap")
	guest.leave_bunk_sleep_authoritative(bunk2.wake_pose.global_transform)
	# Real state changes drive the UI; repeated snapshots and load do not.
	var off:=state.get_snapshot();off.main_breaker_on=false;state._broadcast_snapshot(off)
	await create_timer(.2).timeout
	check(notice.visible and notice.get_node("Panel/Icon").animation==&"off","power outage shows a native vector switch moving towards OFF")
	await capture("power_off")
	var old_phase:int=20-notice.get_node("Panel/Icon").frame
	var on:=state.get_snapshot();on.main_breaker_on=true;state._broadcast_snapshot(on)
	check(abs(notice.get_node("Panel/Icon").frame-old_phase)<=1,"rapid reversal keeps the physical switch position continuous")
	await create_timer(.7).timeout
	check(notice.get_node("Panel/Icon").frame==20 and notice.get_node("Panel/Title").text=="Питание включено","the ON animation finishes with the correct label")
	await capture("power_on")
	await create_timer(2.0).timeout
	check(not notice.visible,"power notification fades away and does not occupy the HUD permanently")
	state._broadcast_snapshot(state.get_snapshot());await create_timer(.2).timeout
	check(not notice.visible,"unchanged state snapshots never restart the switch animation")
	actor.teleport_authoritative(bunk.wake_pose.global_position,0)
	bunk.network_sleep_interact(1,actor);await create_timer(.12).timeout
	var interrupted_head:=actor.head.global_position
	var interrupted_openness:float=actor.get_node("PlayerUI/SleepEyelids/Cover").material.get_shader_parameter("openness")
	check(bunk.cancel_sleep_authoritative(1,actor),"lying down can be cancelled before the eyes close")
	check(actor.head.global_position.distance_to(interrupted_head)<.01 and absf(float(actor.get_node("PlayerUI/SleepEyelids/Cover").material.get_shader_parameter("openness"))-interrupted_openness)<.01,"early cancellation preserves camera and eyelid continuity")
	await create_timer(1.5).timeout
	check(not actor.is_bunk_busy(),"early cancellation finishes with working controls")
	actors.clear();current_scene=null;base.queue_free()
	for i in 4:await process_frame
	print("BUNK PRESENTATION CHECKS ",checks," FAILURES ",failures);quit(1 if failures else 0)
