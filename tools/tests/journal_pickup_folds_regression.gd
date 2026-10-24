extends SceneTree
var checks := 0
var failures := 0
var actor: GamePlayer
var journal: QuestJournalUI
var capture := false
func _initialize() -> void:
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,"user://journal_pickup_%d.cfg" % OS.get_process_id())
	ProjectSettings.set_setting(JournalReadingStore.ROOT_SETTING,"user://journal_pickup_reader_%d" % OS.get_process_id())
	capture = DisplayServer.get_name() != "headless"
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
	root.get_texture().get_image().save_png("res://tools/.local/journal-fold-review/" + name + ".png")
func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1600,1000)
	DirAccess.make_dir_recursive_absolute("res://tools/.local/journal-fold-review")
	var base = load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate()
	root.add_child(base)
	current_scene = base
	await ticks(70)
	root.get_node("GameMenu").force_close_menu()
	actor = get_first_node_in_group("local_player")
	actor.set_physics_process(false)
	actor.survival.set_physics_process(false)
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
	journal.open_journal()
	await ticks(65)
	var inserts = journal._inserts
	check(inserts.get_node("MapFold").find_children("*","MeshInstance3D",true,false).size()==9,"map consists of nine native paper panels")
	var center: MeshInstance3D = inserts.get_node("MapFold/Column1/Center/Middle")
	var center_pose := center.transform
	actor.teleport_authoritative(arrival,0)
	actor.head.rotation.x = 0
	await ticks(5)
	journal._show_section(true)
	await ticks(20)
	check(journal._section_busy and inserts.get_node("TurnPivot").visible,"switch to map starts a physical page turn")
	await screenshot("page-turn")
	await ticks(30)
	check(journal._map_open and inserts.animation.current_animation=="unfold","page turn reveals the glued folded map before unfolding")
	await screenshot("folded-center")
	await ticks(35)
	check(absf(inserts.get_node("MapFold/Column0").rotation.y)<.1 and absf(inserts.get_node("MapFold/Column2").rotation.y)>.1,"paper columns open in distinct native hinge stages")
	await screenshot("unfolding-columns")
	await ticks(55)
	check(center.transform.is_equal_approx(center_pose),"central square remains fixed throughout unfolding")
	check(not journal._section_busy and inserts.displaying_map,"full unfolding settles and restores page input")
	for column in [0,1,2]:
		for side in ["Top","Bottom"]:
			check(absf(inserts.get_node("MapFold/Column%d/Center/%s" % [column,side]).rotation.x)<.001,"unfolded paper row lies flat")
	actor.teleport_authoritative(arrival,0)
	actor.head.rotation.x = 0
	await ticks(5)
	await screenshot("map-open")
	journal._show_section(false)
	await ticks(35)
	check(journal._section_busy and inserts.animation.current_animation=="fold","return to notes folds the paper first")
	await screenshot("folding-rows")
	await ticks(105)
	check(not journal._map_open and not journal._section_busy and not inserts.displaying_map,"fold and reverse page turn restore notes")
	journal._show_section(true)
	await ticks(60)
	journal.close_journal()
	await ticks(180)
	check(not journal.is_journal_open() and not inserts.busy,"closing during unfold safely reverses the paper before stowing")
	journal.open_journal()
	await ticks(65)
	journal._show_section(true)
	await ticks(15)
	actor.survival.dead = true
	await ticks(3)
	check(not journal.is_journal_open() and not inserts.busy and not inserts.get_node("MapFold").visible,"death cancels a page transition without leaving floating panels")
	actor.survival.dead = false
	base.queue_free()
	await ticks(2)
	print("JOURNAL PICKUP AND FOLDS: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
