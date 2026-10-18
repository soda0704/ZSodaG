extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void:
 ProjectSettings.set_setting("northern_lab/testing/controls_path", "user://feedback_journal_controls_%d.cfg" % OS.get_process_id())
 ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://feedback_journal_settings_%d.json" % OS.get_process_id())
 run.call_deferred()
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("PASS " if ok else "FAIL ", label)
func shot() -> Image:
 await RenderingServer.frame_post_draw
 return TesterFeedbackStore.prepare_image(root.get_texture().get_image())
func difference(first: Image, second: Image) -> float:
 var total := 0.0
 var count := 0
 for y in range(int(first.get_height()*0.25),int(first.get_height()*0.9),8):
  for x in range(int(first.get_width()*0.2),int(first.get_width()*0.8),8):
   var a := first.get_pixel(x,y)
   var b := second.get_pixel(x,y)
   total += absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)
   count += 1
 return total / count
func press(code: int) -> void:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = true
 root.push_input(event, true)
 event.pressed = false
 root.push_input(event, true)
func run() -> void:
 if DisplayServer.get_name() == "headless": quit(1); return
 Engine.max_fps = 60
 root.mode = Window.MODE_WINDOWED
 root.size = Vector2i(1280,720)
 var menu = root.get_node("GameMenu")
 menu.force_close_menu()
 var steam = root.get_node("SteamInput")
 steam.set_process(false)
 steam.set_process_input(false)
 var world = load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate()
 root.add_child(world)
 current_scene = world
 var journal: QuestJournalUI = root.get_node("QuestJournal")
 for variant in [0,1]:
  var player: GamePlayer = load("res://scenes/characters/player.tscn").instantiate()
  player.name = "1"
  player.setup(1,"",Vector3(0,0.1,0),Color.WHITE,0,variant)
  world.get_node("Players").add_child(player)
  player.survival.set_physics_process(false)
  menu.force_close_menu()
  await create_timer(0.45).timeout
  var closed := await shot()
  journal.open_journal()
  await create_timer(1.25).timeout
  check(journal._phase == journal.PresentationState.OPEN and player._journal_phase == 2, "real journal opened for variant %d" % variant)
  var opened := await shot()
  journal.close_button.grab_focus()
  if variant == 1:
   var changed: Dictionary = menu.get_node("ControlSettings").current_bindings()
   changed.tester_feedback = {"key": KEY_F9}
   check(menu.get_node("ControlSettings").replace_bindings(changed), "feedback rebound for runtime render check")
   press(KEY_F8)
   await process_frame
   check(not menu.is_menu_open() and journal.is_journal_open(), "old F8 no longer opens feedback")
  press(KEY_F8 if variant == 0 else KEY_F9)
  await create_timer(0.5).timeout
  var form: NorthernTesterFeedback = menu.tester_feedback
  check(menu._current_view == menu.MenuView.FEEDBACK and menu.is_menu_open(), "shortcut opens feedback while journal owns GUI focus")
  check(form.screenshot != null, "report contains real rendered image")
  var with_book := difference(form.screenshot,opened)
  var without_book := difference(form.screenshot,closed)
  print("JOURNAL IMAGE DISTANCE ",variant," opened=",with_book," closed=",without_book)
  check(with_book < without_book * 0.5, "captured pixels retain journal, hands and page UI")
  check(not journal.is_journal_open() and not menu._feedback_capture_busy, "journal closes only after screenshot; form owns input")
  form.screenshot.save_png("res://tools/.local/feedback-journal-%d.png" % variant)
  var form_frame := await shot()
  check(difference(form.screenshot,form_frame) > 0.1, "feedback window excluded from attachment")
  await menu.capture_feedback_screenshot()
  check(not form._busy and menu.is_menu_open() and form.screenshot != null, "retake restores form and releases busy state")
  # Screenshot retake marks a draft dirty; clear it before the next fixture.
  form._attachment_dirty = false
  menu.close_feedback()
  player.queue_free()
  await process_frame
 world.queue_free()
 current_scene = null
 await process_frame
 print("FEEDBACK JOURNAL CHECKS ", checks, " FAILURES ", failures)
 quit(0 if failures == 0 else 1)
