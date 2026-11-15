extends SceneTree
## Run graphically with --main-pack <NorthernLab.exe>; do not override cursor focus.
var failures := 0
func _initialize() -> void:
 ProjectSettings.set_setting("northern_lab/testing/settings_path", "user://export_cursor_%d.json" % OS.get_process_id())
 run.call_deferred()
func check(value: bool, label: String) -> void:
 print("PASS " if value else "FAIL ",label)
 if not value: failures += 1
func run() -> void:
 if DisplayServer.get_name()=="headless": quit(2);return
 check(FileAccess.file_exists("res://project.binary"),"cursor test runs against exported package")
 root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720)
 var menu=root.get_node("GameMenu");menu.force_close_menu()
 var scene=load("res://scenes/ui/main_menu.tscn").instantiate()
 root.add_child(scene);current_scene=scene
 Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 root.grab_focus()
 await create_timer(1.0).timeout
 var cursor=menu.get_node("MenuLaserCursor")
 check(root.has_focus(),"real exported window acquired OS focus")
 check(cursor._focused==root.has_focus(),"cursor follows actual Window focus without a test override")
 check(cursor._animated and cursor._light.visible,"exported main menu activates animated cursor at startup")
 check(cursor._light.size.x>=128.0*1.1,"export contains enlarged cursor")
 for i in 8:
  var event=InputEventMouseMotion.new();event.position=Vector2(650+i*12,360)
  root.push_input(event,true)
  await process_frame
 var has_trail=false
 for ghost in cursor._trail:
  has_trail=has_trail or ghost.visible
 check(has_trail,"exported cursor leaves animated light trail")
 check((cursor._light.position+cursor._light.size*0.5).distance_to(cursor._pointer)<0.01,"exported cursor hotspot matches input")
 check(cursor._light.material.get_shader_parameter("energy")>0.0,"exported cursor shader is actively animated")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("D:/Github/ZSodaG/tools/.local/laser-review/exported-cursor-fixed.png")
 # Main menu requests character previews asynchronously; consume those requests
 # before test shutdown so unfinished IO does not masquerade as a cursor leak.
 for path in ["res://scenes/ui/characters/tactical_a.scn", "res://scenes/ui/characters/tactical_b.scn"]:
  while ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
   await process_frame
  if ResourceLoader.load_threaded_get_status(path)==ResourceLoader.THREAD_LOAD_LOADED:
   ResourceLoader.load_threaded_get(path)
 current_scene=null;scene.queue_free()
 for i in 3:await process_frame
 load("res://scripts/ui/menu_style.gd").uninstall_cursor()
 cursor=null
 for i in 3:await process_frame
 print("EXPORT CURSOR FAILURES ",failures)
 quit.call_deferred(1 if failures else 0)

