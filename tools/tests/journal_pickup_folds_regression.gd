extends SceneTree
var checks := 0
var failures := 0
var actor: GamePlayer
var journal: QuestJournalUI
var capture := false
var capture_dir := "res://tools/.local/journal-fold-review/"
var final_hand_pose := Transform3D.IDENTITY
var final_fingers: Dictionary = {}
var world_fingers: Dictionary = {}
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://journal_pickup_%d.cfg" % OS.get_process_id())
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,"user://journal_pickup_reader_%d" % OS.get_process_id())
	capture = DisplayServer.get_name() != "headless"
	if OS.get_cmdline_user_args().has("--variant=1"): capture_dir = "res://tools/.local/journal-fold-review-b/"
	create_timer(110).timeout.connect(func(): quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func ticks(count: int) -> void:
	for i in count:
		if is_instance_valid(actor): actor.update_character_animation(1.0/60)
		await physics_frame
	await process_frame
func screenshot(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(capture_dir + name + ".png")
func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await ticks(70)
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	if OS.get_cmdline_user_args().has("--variant=1"):
		var parent := actor.get_parent()
		var at := actor.global_position
		parent.remove_child(actor)
		actor.free()
		actor = load("res://scenes/characters/player.tscn").instantiate()
		actor.name = "1"
		actor.setup(1,"Variant B",at,Color.WHITE,0,1)
		parent.add_child(actor)
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
	var final_skeleton: Skeleton3D = actor.body_animator.first_person_model.get_node("Skeleton3D")
	final_skeleton.skeleton_updated.connect(func():
		final_hand_pose = final_skeleton.get_bone_global_pose(final_skeleton.find_bone("RightHand"))
		for name in ["RightHandIndex2","RightHandIndex3","RightHandMiddle1","RightHandMiddle2","RightHandMiddle3","RightHandPinky2","RightHandThumb3"]:
			final_fingers[name] = final_skeleton.get_bone_global_pose(final_skeleton.find_bone(name)).origin)
	var world_skeleton: Skeleton3D = actor.body_animator.model.get_node("Skeleton3D")
	world_skeleton.skeleton_updated.connect(func():
		for name in ["RightHandMiddle1","RightHandMiddle3"]: world_fingers[name] = world_skeleton.get_bone_global_pose(world_skeleton.find_bone(name)).origin)
	journal = root.get_node("QuestJournal")
	var state: BaseGameplayController = base.get_node("BaseGameplayController")
	state.set_process(false)
	var arrival := actor.global_position
	var first = base.get_node("JournalPickups/Journal1")
	var second = base.get_node("JournalPickups/Journal2")
	check(not actor.has_journal and not actor.get_inventory_snapshot().has_journal,"fresh player does not own a journal")
	journal.open_journal()
	check(not journal.is_journal_open(),"J cannot open a journal before pickup")
	check(not journal._map_tab.visible,"map tab is absent before entering the base")
	check(journal._map_sheet._buttons[6].text=="???","undiscovered shaft has no name or level label")
	first.network_interact(1,actor)
	check(not actor.has_journal and not first._collected,"distant pickup request is rejected")
	actor.teleport_authoritative(Vector3(-30.45,.04,6.2),0)
	await ticks(15)
	var look: Vector3 = first.get_interaction_position()-actor.head.global_position
	actor.rotation.y = atan2(-look.x,-look.z)
	actor.head.rotation.x = atan2(look.y,Vector2(look.x,look.z).length())
	await ticks(3)
	check(actor.get_interaction_target()==first,"native E ray reaches the journal beside the pistol")
	first.network_interact(2,actor)
	check(not first._collected,"wrong owner cannot claim the journal")
	actor.try_authoritative_interaction()
	check(actor.has_journal and first._collected and not first.visible,"real E pickup grants one journal and hides its world copy")
	second.network_interact(1,actor)
	check(not second._collected and second.visible,"one owner cannot consume the second copy")
	check(second.get_interaction_hint_for(actor)=="Журнал уже есть","duplicate pickup explains ownership")
	check(not actor.pickup_world_item_authoritative(&"journal",{}),"repeated direct grant is rejected")
	actor.survival.dead = true
	actor.drop_all_items_at_authoritative(Transform3D.IDENTITY)
	check(actor.has_journal,"journal stays with its owner when other equipment drops on death")
	actor.survival.dead = false
	check(not actor.handoff.available(&"journal",true),"journal cannot be offered or removed through pocket handoff")
	state.save_progress_authoritative()
	var saved := state.load_saved_snapshot()
	check(saved.maintenance.journal_claims.has("journal_1") and not saved.maintenance.journal_claims.has("journal_2"),"disk checkpoint saves exact pickup claims")
	actor.has_journal = false
	state._apply_snapshot(saved,true)
	check(actor.has_journal and first._collected and not second._collected,"restoring claims restores ownership without respawning the taken copy")
	var open_started := Time.get_ticks_usec()
	journal.open_journal()
	check(Time.get_ticks_usec()-open_started<100000,"opening does not synchronously read back the GPU")
	await ticks(65)
	check(journal._ink_viewport.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,"static pages are cached rather than redrawn each frame")
	var inserts = journal._inserts
	check(not inserts.has_node("MapFold") and not inserts.animation.has_animation("fold") and not inserts.animation.has_animation("unfold"),"folding hierarchy and clips are removed")
	var center: MeshInstance3D = inserts.get_node("MapSheet/Paper")
	check(center.mesh is ArrayMesh and inserts.has_node("MapSheet/ContactShadow"),"map uses one authored curved sheet and a contact shadow")
	check(center.mesh.get_aabb().size.z > .001,"pasted paper has a small physical bend")
	var center_pose := center.transform
	actor.teleport_authoritative(arrival,0)
	actor.head.rotation.x = 0
	await ticks(5)
	journal._show_section(true)
	await ticks(2)
	inserts.animation.pause()
	inserts.animation.seek(.20,true)
	check(journal._section_busy and inserts.get_node("TurnPivot").visible,"switch to map starts a physical page turn")
	check(journal._previous_ink_viewport != null and journal._previous_ink_viewport != journal._ink_viewport,"turn retains the previous spread in a separate cached target")
	check(journal._previous_ink_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"old printed page is frozen during the turn")
	await screenshot("page-turn")
	inserts.animation.play("page_to_map")
	inserts.animation.seek(.43,true)
	inserts.animation.advance(.03)
	await ticks(3)
	check(center.transform.is_equal_approx(center_pose),"pasted sheet stays fixed while the journal page turns")
	check(journal._map_open and not journal._section_busy and inserts.displaying_map,"one short page turn reveals the complete map and restores input")
	actor.teleport_authoritative(arrival,0)
	actor.head.rotation.x = 0
	await ticks(5)
	await screenshot("map-open")
	journal._on_loupe_requested(true)
	await ticks(105)
	check(inserts.loupe_active and inserts.get_node("LoupeAim").visible,"magnification raises a physical magnifier")
	check(is_equal_approx(float(inserts.magnifier.get_node("Lens").material_override.get_shader_parameter("magnification")),2.0),"lens magnifies by two without resizing the map")
	var optical_at: Vector3 = inserts.to_local(inserts.magnifier.global_position)
	var optical_eye: Vector3 = inserts.to_local(actor.body_animator.first_person.view_camera.global_position)
	var optical_ray := optical_at-optical_eye
	optical_at = optical_eye+optical_ray*((inserts.get_node("MapSheet").position.z-optical_eye.z)/optical_ray.z)
	var expected_uv := Vector2((optical_at.x/inserts.sheet_width+1)*700,(.5-optical_at.y/inserts.sheet_height)*986)/Vector2(1400,986)
	check((inserts.magnifier.get_node("Lens").material_override.get_shader_parameter("focus_atlas") as Vector2).distance_to(expected_uv)<.002,"lens enlarges the paper directly beneath its actual attached position")
	var skeleton: Skeleton3D = actor.body_animator.first_person_model.get_node("Skeleton3D")
	var wrist: Vector3 = skeleton.to_global(final_hand_pose.origin)
	var grip: Node3D = inserts.get_node("LoupeAim/Lift/RightGrip")
	print("LOUPE WRIST ERROR ",wrist.distance_to(grip.global_position))
	for bone_name in final_fingers:
		print("LOUPE ANATOMY ",bone_name," ",inserts.magnifier.to_local(skeleton.to_global(final_fingers[bone_name])))
	if capture: check(wrist.distance_to(grip.global_position)<.04,"right hand actually holds the magnifier handle")
	var lift: Node3D = inserts.magnifier
	var grasp := lift.to_local(skeleton.to_global((final_fingers["RightHandMiddle1"]+final_fingers["RightHandMiddle3"])*.5))
	# FP modifiers use the rendered viewmodel viewport; validate contact with a real renderer.
	if capture: check(grasp.distance_to(lift.get_node("Handle").position)<.015,"handle lies inside the closed palm rather than beside the fist")
	var world_lift: Node3D = actor.body_animator.model.get_node("Skeleton3D/RightHand/Equipment/JournalMagnifier")
	if world_fingers.has("RightHandMiddle1"):
		print("WORLD LOUPE GRASP ",world_lift.to_local(world_skeleton.to_global((world_fingers["RightHandMiddle1"]+world_fingers["RightHandMiddle3"])*.5)))
		check(world_lift.to_local(world_skeleton.to_global((world_fingers["RightHandMiddle1"]+world_fingers["RightHandMiddle3"])*.5)).distance_to(world_lift.get_node("Handle").position)<.015,"teammate model also grips the handle with its closed palm")

	await screenshot("loupe-in-hand")
	inserts.set_loupe_focus(Vector2(450,400))
	await ticks(12)
	await screenshot("loupe-detail")
	journal._on_loupe_requested(false)
	await ticks(20)
	journal._show_section(false)
	await ticks(8)
	check(journal._section_busy and inserts.animation.current_animation=="page_to_notes","return to notes immediately plays the reverse page turn")
	await screenshot("page-turn-back")
	await ticks(35)
	check(not journal._map_open and not journal._section_busy and not inserts.displaying_map,"reverse page turn restores notes without folding delay")
	journal._show_section(true)
	await ticks(60)
	journal.close_journal()
	check(journal._phase==journal.PresentationState.CLOSING and journal._map_open,"close starts immediately from the map without returning to notes")
	await ticks(50)
	check(not journal.is_journal_open() and not inserts.busy,"stowing has no extra paper-return delay")
	journal.open_journal()
	await ticks(65)
	check(journal._map_open and inserts.displaying_map,"reopening retains the map spread")
	journal._show_section(false)
	await ticks(15)
	actor.survival.dead = true
	await ticks(3)
	check(not journal.is_journal_open() and not inserts.busy and not inserts.get_node("MapSheet").visible,"death cancels a page transition without leaving floating paper")
	actor.survival.dead = false
	journal._page_surfaces[0].queue_free()
	await ticks(2)
	journal.open_journal()
	check(journal.is_journal_open() and is_instance_valid(journal._page_surfaces[0]),"reopening rebuilds a replaced player page without stale mesh references")
	journal.force_close()
	base.queue_free()
	await ticks(2)
	print("JOURNAL PICKUP AND FOLDS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
