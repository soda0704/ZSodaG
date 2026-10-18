extends SceneTree
var checks := 0
var failures := 0
var controls: NorthernControlSettings
var control_path: String
func _initialize() -> void:
 control_path = "user://controls_binding_%d.cfg" % OS.get_process_id()
 ProjectSettings.set_setting("northern_lab/testing/controls_path", control_path)
 ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://controls_binding_%d.json" % OS.get_process_id())
 run.call_deferred()
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1
 print("PASS " if ok else "FAIL ", label)
func key(code: int) -> InputEventKey:
 var event := InputEventKey.new()
 event.physical_keycode = code
 event.keycode = code
 event.pressed = true
 return event
func run() -> void:
 await process_frame
 var menu = root.get_node("GameMenu")
 controls = menu.get_node("ControlSettings")
 var initial := controls.current_bindings()
 check(controls.validation_error(initial).is_empty(), "project defaults have no keyboard/mouse collisions")
 check(initial.tester_feedback == {"key": KEY_F8} and initial.weapon_aim == {"mouse": MOUSE_BUTTON_RIGHT}, "feedback and aim participate in settings")
 for action in controls.ACTIONS:
  if action == "pause": continue
  var invalid := initial.duplicate(true)
  invalid[action] = {"key": KEY_ESCAPE}
  check(not controls.replace_bindings(invalid) and controls.current_bindings() == initial, "Escape cannot be stolen by " + action)
 for data in [{"key": KEY_QUOTELEFT}, {"key": 0}, {"mouse": 0}, {"mouse": 15}, {"key": KEY_J, "mouse": 1}]:
  var invalid := initial.duplicate(true)
  invalid.interact = data
  check(not controls.replace_bindings(invalid) and controls.current_bindings() == initial, "invalid/reserved binding rejected before live changes")
 var swap := initial.duplicate(true)
 swap.move_forward = {"key": KEY_S}
 swap.move_backward = {"key": KEY_W}
 check(controls.normalized_saved_bindings(swap) == swap, "valid saved key swaps are preserved")
 var invalid_report := initial.duplicate(true)
 invalid_report.tester_feedback = {"mouse": MOUSE_BUTTON_XBUTTON1}
 check(not controls.replace_bindings(invalid_report), "global report action requires a keyboard key")
 var duplicate := initial.duplicate(true)
 duplicate.interact = duplicate.tester_feedback
 check(not controls.replace_bindings(duplicate) and not FileAccess.file_exists(control_path), "F8 collision is rejected before disk write")
 duplicate = initial.duplicate(true)
 duplicate.weapon_attack = duplicate.weapon_aim
 check(not controls.replace_bindings(duplicate), "LMB/RMB actions cannot duplicate")
 var custom := initial.duplicate(true)
 custom.tester_feedback = {"key": KEY_F9}
 custom.weapon_aim = {"key": KEY_V}
 check(controls.replace_bindings(custom), "feedback and aim can be rebound")
 check(not InputMap.event_is_action(key(KEY_F8), "tester_feedback") and InputMap.event_is_action(key(KEY_F9), "tester_feedback"), "old report key released; new key active")
 check(InputMap.action_get_events("weapon_attack").any(func(event): return event is InputEventJoypadMotion), "keyboard changes preserve controller trigger")
 var fallback = root.get_node("SteamInput")
 var battery := key(KEY_B)
 controls.apply_binding("replace_battery", battery)
 fallback._ensure_godot_joypad_fallback()
 check(not InputMap.event_is_action(key(KEY_R), "replace_battery") and InputMap.event_is_action(battery, "replace_battery"), "controller initialization does not resurrect old R")
 controls.apply_binding("replace_battery", key(KEY_R))
 var broken := custom.duplicate(true)
 broken.interact = {"key": KEY_F9}
 broken.pause = {"key": KEY_K}
 broken.drop_item = {"key": KEY_QUOTELEFT}
 var config := ConfigFile.new()
 config.set_value("input", "bindings", broken)
 config.save(control_path)
 controls._initialize()
 check(controls.repaired_on_load and controls.validation_error(controls.current_bindings()).is_empty(), "old duplicate/reserved config repaired on load")
 check(controls.current_bindings().weapon_aim == {"key": KEY_V}, "unrelated valid customization preserved")
 var loaded := ConfigFile.new()
 loaded.load(control_path)
 check(controls.validation_error(loaded.get_value("input", "bindings")).is_empty(), "repaired bindings stored for next launch")
 controls.replace_bindings(initial)
 var main := Node3D.new()
 root.add_child(main)
 current_scene = main
 menu.open_settings()
 await create_timer(0.45).timeout
 var settings: NorthernSettingsMenu = menu.settings_panel
 settings.select_category(3)
 var before := settings.draft_bindings.duplicate(true)
 settings._wait_for_key("interact")
 settings._input(key(KEY_F8))
 check(settings.waiting == "interact" and settings.draft_bindings == before and settings.description.text.contains("Отчёт"), "UI names occupied action and keeps capture pending")
 settings._input(key(KEY_QUOTELEFT))
 check(settings.waiting == "interact" and settings.description.text.contains("консоли"), "UI explains reserved console key")
 var console = root.get_node("DeveloperConsole")
 console._input(key(KEY_QUOTELEFT))
 check(not console.opened, "trying console key during rebinding cannot open console")
 var chord := key(KEY_K)
 chord.ctrl_pressed = true
 settings._input(chord)
 check(settings.waiting == "interact" and settings.draft_bindings == before, "modified chord is not silently converted to a single key")
 settings._input(key(KEY_ESCAPE))
 check(settings.waiting.is_empty() and settings.draft_bindings == before, "Escape cancels capture without modifying draft")
 settings._wait_for_key("tester_feedback")
 menu._input(key(KEY_F8))
 check(menu._current_view == menu.MenuView.SETTINGS, "report shortcut cannot interrupt rebinding")
 settings._input(key(KEY_F10))
 check(settings.draft_bindings.tester_feedback == {"key": KEY_F10} and controls.current_bindings() == initial, "free report key staged until Apply")
 settings.apply(false)
 check(InputMap.event_is_action(key(KEY_F10), "tester_feedback"), "Apply activates custom report key")
 controls.replace_bindings(initial)
 menu.force_close_menu()
 var letters := initial.duplicate(true)
 letters.tester_feedback = {"key": KEY_K}
 controls.replace_bindings(letters)
 console.set_open(true)
 console.entry.grab_focus()
 menu._input(key(KEY_K))
 check(console.opened and not menu.is_menu_open(), "rebound letter cannot interrupt text entry, even without Unicode in synthetic input")
 letters.tester_feedback = {"key": KEY_F9}
 controls.replace_bindings(letters)
 menu._input(key(KEY_F9))
 check(not console.opened and menu._current_view == menu.MenuView.FEEDBACK, "function-key report shortcut remains available from console")
 menu.close_feedback()
 controls.replace_bindings(initial)
 main.queue_free()
 current_scene = null
 DirAccess.remove_absolute(control_path)
 print("CONTROLS BINDING CHECKS ", checks, " FAILURES ", failures)
 quit(0 if failures == 0 else 1)
