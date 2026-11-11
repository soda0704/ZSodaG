extends SceneTree
var checks:=0
var failures:=0
var console:CanvasLayer
func _initialize():
 ProjectSettings.set_setting("northern_lab/testing/settings_path","user://console_input_%d.json"%OS.get_process_id())
 create_timer(45).timeout.connect(func():quit(2));run.call_deferred()
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func key(code:int,unicode:int=0):
 var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.unicode=unicode;event.pressed=true
 Input.parse_input_event(event);await process_frame
 event=event.duplicate();event.pressed=false;Input.parse_input_event(event);await process_frame
func run():
 Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=root.size
 var scene=Node.new();root.add_child(scene);current_scene=scene
 await process_frame
 root.get_node("GameMenu").force_close_menu()
 console=root.get_node("DeveloperConsole")
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 await key(KEY_QUOTELEFT,96)
 check(console.opened and console.entry.has_focus(),"hotkey opens console with keyboard focus")
 var commands:RichTextLabel=console.get_node("Panel/Box/Commands")
 var all=console._all_commands()
 check(commands.text.contains("/blizzard off") and commands.text.contains("/camera_filters off") and commands.text.contains("/freecam off") and commands.text.contains("/wiring"),"opening lists old and new commands including explicit off variants")
 check(commands.get_parsed_text().split("\n",false).size()==all.size(),"entire registered command list is present")
 console.get_node("Panel/Box/CommandsHeader/SwitchView").pressed.emit()
 await process_frame
 var help:String=console._help_text()
 var complete_help:=true
 for command in all:complete_help=complete_help and help.contains("[url="+command+"]")
 check(complete_help,"help includes every registered completion variant")
 console.entry.text="/bliz";console.entry.caret_column=5
 await key(KEY_Z,122)
 check(commands.text.contains("/blizzard") and not commands.text.contains("/wiring"),"typing filters suggestions")
 console.get_node("Panel/Box/CommandsHeader/ShowAll").pressed.emit()
 await process_frame
 check(commands.text.contains("/wiring") and console.entry.text=="/blizz" and console.entry.has_focus(),"show-all restores entire list without erasing typed input")
 commands.scroll_to_line(999);await process_frame
 check(commands.get_v_scroll_bar().value>0,"full command list can scroll beyond first visible rows")
 console.entry.text="/";console.entry.caret_column=1
 console.output.text="Test log";console.output.show()
 console.output.focus_mode=Control.FOCUS_ALL;console.output.grab_focus()
 await key(KEY_X,120)
 check(console.entry.text=="/x" and console.entry.has_focus(),"typing after clicking log refocuses entry and inserts first character once")
 console.entry.text="/abc";console.entry.caret_column=4;console.entry.release_focus()
 await key(KEY_BACKSPACE)
 check(console.entry.text=="/ab","backspace works after entry loses focus")
 console.entry.release_focus()
 var paste:=InputEventKey.new();paste.keycode=KEY_V;paste.ctrl_pressed=true;paste.pressed=true
 console._input(paste)
 check(console.entry.has_focus(),"paste shortcut targets entry after focus loss without stealing copy from logs")
 console.entry.text="/blizz";console.entry.caret_column=6;console.entry.release_focus()
 await key(KEY_TAB,9)
 check(console.entry.text=="/blizzard" and console.entry.has_focus(),"Tab completion restores entry focus")
 commands.meta_clicked.emit("/camera_filters off");await process_frame
 check(console.entry.text=="/camera_filters off" and console.entry.has_focus(),"clicking command inserts it and keeps entry ready")
 check(commands.text.contains("/camera_filters off") and not commands.text.contains("/wiring"),"command click refreshes matching suggestions")
 console._submit("/help");await process_frame
 check(console.entry.text=="/" and commands.text.contains("/wiring") and commands.text.contains("/blizzard off"),"Enter restores full list instead of leaving previous filtered suggestions")
 await key(KEY_UP)
 check(console.entry.text=="/help" and commands.text.contains("/help") and not commands.text.contains("/wiring"),"history navigation refreshes suggestions to recalled command")
 console.entry.release_focus();console.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN);await process_frame
 check(console.entry.has_focus(),"returning to application restores console input focus")
 console.set_open(true);console.set_open(false)
 check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"repeated open cannot overwrite original mouse mode")
 console.set_open(true);await process_frame
 await key(KEY_ESCAPE)
 check(not console.opened and not console.entry.has_focus(),"Escape closes console without leaked focus")
 console.set_open(true);await process_frame
 check(console.entry.has_focus() and commands.text.contains("/wiring"),"reopening restores focus and full list")
 var output:=OS.get_environment("NORTHERNLAB_EXPORT_CAPTURE_DIR")
 if output.is_empty():output="res://tools/.local/blizzard-review/console-review"
 DirAccess.make_dir_recursive_absolute(output)
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output+"/console-all-commands.png")
 console.set_open(false);scene.queue_free()
 paste=null;console=null;commands=null;scene=null
 for frame in 4:await process_frame
 await create_timer(.3).timeout
 print("CONSOLE INPUT CHECKS ",checks," FAILURES ",failures)
 quit(1 if failures else 0)
