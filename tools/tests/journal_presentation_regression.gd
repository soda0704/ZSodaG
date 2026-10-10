extends SceneTree
## Production base, real viewmodel book and projected mouse input on its pages.
const SAVE := "user://journal_presentation_regression.cfg"
var failures:=0
var checks:=0
var player: GamePlayer
var journal: QuestJournalUI
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func delay(seconds: float): await create_timer(seconds).timeout
func page_click(control: Control):
	var point:=control.get_global_rect().get_center()
	var side:=0 if point.x<700 else 1
	var uv:=Vector2(fposmod(point.x,700)/700.0,point.y/986.0)
	var page:=journal._page_surfaces[side]
	var location:=page.to_global(Vector3((uv.x-.5)*.210,(.5-uv.y)*.303,0))
	var screen:=player.body_animator.first_person.view_camera.unproject_position(location)
	# Injected OS events use window pixels; the game stretches its logical canvas.
	screen*=Vector2(root.size)/root.get_visible_rect().size
	var motion:=InputEventMouseMotion.new(); motion.position=screen; Input.parse_input_event(motion)
	await process_frame
	var down:=InputEventMouseButton.new(); down.position=screen; down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.button_mask=MOUSE_BUTTON_MASK_LEFT; Input.parse_input_event(down)
	await process_frame
	var up:=InputEventMouseButton.new(); up.position=screen; up.button_index=MOUSE_BUTTON_LEFT; up.pressed=false; Input.parse_input_event(up)
	await process_frame
func run():
	if DisplayServer.get_name()=="headless": push_error("This regression needs graphical rendering."); quit(1); return
	Engine.max_fps=60; root.size=Vector2i(1280,720); root.position=Vector2i(120,120)
	ProjectSettings.set_setting(BaseGameplayController.TEST_SAVE_PATH_SETTING,SAVE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	var input:=root.get_node("SteamInput"); input.set_process(false); input.set_process_input(false); input.native_input_available=false
	var base=load("res://scenes/levels/Base_Blockout_v03.tscn").instantiate(); root.add_child(base)
	root.get_node("GameMenu").force_close_menu(); await delay(.4)
	for frame in 30: await process_frame
	player=get_first_node_in_group("local_player"); journal=root.get_node("QuestJournal")
	player.set_process_unhandled_input(false); player.survival.set_physics_process(false)
	for action in InputMap.get_actions(): InputMap.action_erase_events(action)
	player._has_flashlight=true; player._battery_charge=.62; player._spare_batteries.assign([.75,.25]); player._held_item_type=&"flashlight"; player._flashlight_enabled=false; player._refresh_equipment_visuals()
	check(not journal.is_journal_open() and journal._ink_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"closed book stops its ink viewport")
	check(journal._cards.size()==7,"all inventory card IDs retained")
	var font:=journal.tasks_label.get_theme_font("font"); var glyphs:=true
	for c in "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюяABCDEFGHIJKLMNOPQRSTUVWXYZ": glyphs=glyphs and font.has_char(c.unicode_at(0))
	check(glyphs,"journal font contains Cyrillic and Latin")
	journal.open_journal(); await delay(.12)
	check(journal.is_journal_open() and journal._phase==journal.PresentationState.OPENING,"native lift immediately blocks gameplay")
	check(not player.crosshair.visible and not player.flashlight._equipped,"opening stows flashlight and hides reticle")
	check(journal._character_arms==player.body_animator.first_person.model,"book shares owner FP rig, no duplicate arms")
	var book: Node3D=journal._character_arms.get_node("Journal")
	check(book.has_node("LeftGrip") and book.has_node("RightGrip"),"independent book has both wrist markers")
	var low:=book.position; await delay(.40); var raised:=book.position
	print("BOOK LIFT ",low," -> ",raised," FPS ",Engine.get_frames_per_second())
	check(low.distance_to(raised)>.15,"book moves through native lift animation")
	journal.close_journal(); await delay(.10); journal.open_journal(); await delay(1.05)
	check(journal._phase==journal.PresentationState.OPEN and not journal._blocker.visible,"early reversal settles into reading")
	print("BOOK OPEN cover ",book.get_node("FrontCoverPivot").rotation," CONTEXT ",player.body_animator.first_person.context," STATES ",player.body_animator.first_person._journal_phase," tree ",player.body_animator.first_person.tree.get("parameters/Journal/playback").get_current_node())
	print("VIEWPORTS ",root.get_visible_rect().size," FP ",player.body_animator.first_person.viewport.size," INK ",journal._ink_viewport.size)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tools/.local/journal-base.png")
	check(journal._ink_viewport.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"live content remains on physical reading pages")
	check(absf(Quaternion(book.get_node("FrontCoverPivot").basis).dot(Quaternion(Vector3.UP,PI)))>.99,"front cover opens onto left page")
	check(journal.tasks_label.text.length()>0 and journal.day_label.text.length()>0,"production mission text survives UI reparenting")
	check(journal._cards[&"flashlight"].visible and journal._cards[&"battery"].visible and not journal._cards[&"pistol"].visible,"inventory visibility follows gameplay ownership")
	await page_click(journal._cards[&"battery"])
	check(journal._selected_item==&"battery" and journal.inventory_label.text.contains("75%"),"projected mouse selects real battery card")
	await page_click(journal.notebook_pivot.get_node("Reveal/Ink/Footer/HelpButton"))
	check(journal.help_panel.visible and not journal.controls_label.text.is_empty(),"projected page button opens controls")
	journal.close_journal(); check(not journal.help_panel.visible and journal._phase==journal.PresentationState.OPEN,"close first dismisses help")
	await page_click(journal.close_button)
	check(journal._phase==journal.PresentationState.CLOSING,"projected close button starts stowing")
	check(journal.is_journal_open(),"closing keeps movement blocked until stowed")
	await delay(.9)
	check(not journal.is_journal_open() and player.crosshair.visible and player.flashlight._equipped,"stowing restores flashlight and HUD")
	check(player._held_item_type==&"flashlight" and is_equal_approx(player._battery_charge,.62),"book does not change ownership or charge")
	journal.open_journal(); await delay(.2); player.survival.dead=true; await delay(.10)
	check(not journal.is_journal_open() and journal._ink_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"death interrupts book and releases input")
	player.survival.dead=false; journal.open_journal(); journal.force_close()
	check(not journal.is_journal_open(),"scene/menu transition can force a clean close")
	base.queue_free(); await process_frame; DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	print("JOURNAL CHECKS ",checks," FAILURES ",failures); quit(1 if failures else 0)
