extends SceneTree
var checks := 0
var failures := 0
var heard: Array[StringName] = []

func _initialize() -> void:
	var prefix := "user://interface_audio_%d" % OS.get_process_id()
	ProjectSettings.set_setting("northern_lab/testing/settings_path",prefix+".json")
	ProjectSettings.set_setting("northern_lab/testing/controls_path",prefix+".cfg")
	create_timer(55).timeout.connect(func():quit(2))
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func move_mouse(point: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point
	event.relative=Vector2(1,1);event.velocity=Vector2(60,60)
	root.push_input(event,true)

func press_mouse(point: Vector2, pressed: bool) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	root.push_input(event,true)

func key(code: Key, pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	root.push_input(event,true)

func button(parent: Node, label: String, point: Vector2) -> Button:
	var result:=Button.new();result.text=label;result.position=point;result.size=Vector2(200,55)
	parent.add_child(result)
	return result

func settle() -> void:
	for frame in 3:await process_frame

func run() -> void:
	Engine.max_fps=60;root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	root.gui_embed_subwindows=true
	var menu:=root.get_node("GameMenu")
	menu.force_close_menu()
	var audio:=menu.get_node("InterfaceAudio")
	audio.sound_played.connect(func(kind:StringName):heard.append(kind))
	check(audio.hover.stream is AudioStreamWAV and audio.hover.stream.loop_mode==AudioStreamWAV.LOOP_DISABLED and absf(audio.hover.stream.get_length()-.1)<.001 and audio.hover.stream.resource_path=="res://assets/audio/ui/hover_3088_trimmed.wav","hover uses the trimmed 100 ms non-looping 3088 clip")
	check(audio.click.stream is AudioStreamMP3 and not audio.click.stream.loop and audio.click.stream.resource_path=="res://assets/audio/ui/soft_button_press.mp3","click uses the provided soft button press clip")
	print("UI AUDIO LENGTHS hover=",audio.hover.stream.get_length()," click=",audio.click.stream.get_length())
	var layer:=CanvasLayer.new();layer.layer=200;layer.process_mode=Node.PROCESS_MODE_ALWAYS;root.add_child(layer)
	move_mouse(Vector2(1000,650))
	var active:=button(layer,"Active",Vector2(100,100))
	var disabled:=button(layer,"Disabled",Vector2(350,100));disabled.disabled=true
	var field:=LineEdit.new();field.position=Vector2(100,200);field.size=Vector2(200,55);layer.add_child(field)
	await settle();heard.clear()
	move_mouse(Vector2(180,120));await settle()
	check(heard==[&"hover"] and audio.hover.playing,"actual pointer entry plays 3088 exactly once on a dynamically added button")
	heard.clear();await create_timer(.12).timeout
	check(heard.is_empty(),"stationary pointer never repeats hover audio")
	press_mouse(Vector2(180,120),true)
	var playing_on_press:bool=audio.click.playing
	await settle()
	press_mouse(Vector2(180,120),false);await settle()
	print("UI AUDIO MOUSE EVENTS ",heard," playing at press ",playing_on_press)
	check(heard==[&"click"] and playing_on_press,"native mouse press plays soft button press once without duplicating focus feedback")
	heard.clear();move_mouse(Vector2(430,120));await settle()
	press_mouse(Vector2(430,120),true);press_mouse(Vector2(430,120),false);await settle()
	check(heard.is_empty(),"disabled buttons are silent on hover and click")
	move_mouse(Vector2(180,220));await settle()
	check(heard==[&"hover"],"editable interface fields use 3088")
	heard.clear();press_mouse(Vector2(180,220),true);press_mouse(Vector2(180,220),false);await settle()
	check(heard==[&"click"],"field activation uses soft button press once")
	heard.clear();key(KEY_A,true);key(KEY_A,false);await settle()
	check(heard.is_empty(),"typing does not produce a click sound for each letter")
	active.grab_focus();heard.clear();key(KEY_TAB,true);key(KEY_TAB,false);await settle()
	print("UI AUDIO FOCUS EVENTS ",heard)
	check(heard==[&"hover"],"keyboard focus navigation uses 3088")
	active.grab_focus();heard.clear();key(KEY_SPACE,true);key(KEY_SPACE,false);await settle()
	check(heard==[&"click"],"keyboard button activation uses soft button press exactly once")
	heard.clear()
	var controller_accept:=InputEventAction.new();controller_accept.action=&"ui_accept";controller_accept.pressed=true;controller_accept.strength=1.0
	root.push_input(controller_accept,true);controller_accept=controller_accept.duplicate();controller_accept.pressed=false;controller_accept.strength=0.0;root.push_input(controller_accept,true);await settle()
	check(heard==[&"click"],"controller-style UI accept action plays one click")
	move_mouse(Vector2(1000,650));await settle();heard.clear()
	root.remove_child(layer);root.add_child(layer);await settle()
	move_mouse(Vector2(180,120));await settle()
	check(heard==[&"hover"],"re-entering the tree never doubles signal connections")
	paused=true;heard.clear();press_mouse(Vector2(180,120),true);press_mouse(Vector2(180,120),false)
	playing_on_press=audio.click.playing;await settle()
	check(heard==[&"click"] and playing_on_press,"UI feedback remains active while gameplay is paused")
	paused=false
	var custom:=button(layer,"Specialized",Vector2(350,200));custom.set_meta("ui_click_sound",false)
	await settle();move_mouse(Vector2(430,220));await settle();heard.clear()
	press_mouse(Vector2(430,220),true);press_mouse(Vector2(430,220),false);await settle()
	check(heard.is_empty(),"controls owning a specialized action sound do not add a second generic click")
	var popup:=PopupMenu.new();root.add_child(popup)
	popup.add_item("First");popup.add_item("Second");popup.add_item("Disabled");popup.set_item_disabled(2,true)
	await settle();popup.popup(Rect2i(450,300,200,120));await settle();heard.clear()
	var popup_point:=Vector2(popup.position)+Vector2(20,42)
	move_mouse(popup_point);await settle()
	print("UI POPUP HOVER ",heard," focus ",popup.get_focused_item()," size ",popup.size," position ",popup.position," embedded ",popup.is_embedded())
	check(heard==[&"hover"],"native popup mouse navigation plays 3088 once per item")
	heard.clear()
	press_mouse(popup_point,true);press_mouse(popup_point,false);await settle()
	print("UI POPUP CLICK ",heard)
	check(heard==[&"click"],"native popup selection plays soft button press once")
	popup.queue_free()
	var ui_bus:=AudioServer.get_bus_index("UI")
	check(audio.hover.bus==&"UI" and audio.click.bus==&"UI" and AudioServer.get_bus_send(ui_bus)==&"Master" and AudioServer.get_bus_effect_count(ui_bus)==0,"interface audio bypasses world reverb and filters")
	menu.audio_mix.apply_settings({"EffectsVolume":0.0})
	check(AudioServer.is_bus_mute(ui_bus),"Effects volume zero also mutes interface audio")
	menu.audio_mix.apply_settings({"EffectsVolume":35.0})
	check(not AudioServer.is_bus_mute(ui_bus) and absf(db_to_linear(AudioServer.get_bus_volume_db(ui_bus))-.35)<.001,"interface audio follows the existing Effects volume")
	layer.queue_free();await settle()
	check(is_instance_valid(audio) and audio.get_parent()==menu,"feedback players survive ordinary interface destruction")
	audio.hover.stop();audio.click.stop()
	for frame in 8:await process_frame
	print("INTERFACE AUDIO CHECKS ",checks," FAILURES ",failures)
	quit(1 if failures else 0)
