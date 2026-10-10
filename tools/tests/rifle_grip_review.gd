extends Node3D
## Isolated, user-reviewable rifle grips. No gameplay state is changed.
var model:Node3D
var fp_model:Node3D
var first_person:=false
var camera:Camera3D
var title:Label
var azimuth:=PI*.5
var elevation:=.10
var focus:=Vector3(.13,1.425,-.32)
func _ready()->void:
	get_node("/root/GameMenu").force_close_menu()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var arena=load("res://tools/tests/fixtures/character_test_arena.tscn").instantiate();add_child(arena)
	for light in arena.find_children("*","Light3D",true,false):light.light_cull_mask|=1<<19
	camera=arena.get_node("ReviewCamera");camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=.60;camera.near=.01;camera.current=true
	var canvas:=CanvasLayer.new();add_child(canvas)
	title=Label.new();title.position=Vector2(20,20);title.add_theme_font_size_override("font_size",22);canvas.add_child(title)
	set_style(0);update_camera()
func set_style(style:int)->void:
	if is_instance_valid(model):remove_child(model);model.queue_free()
	model=load("res://scenes/characters/grip_studies/rifle/"+("a" if style==0 else "b")+".tscn").instantiate();add_child(model)
	model.get_node("AnimationTree").active=false;model.get_node("AnimationPlayer").play("Grip")
	if is_instance_valid(fp_model):camera.remove_child(fp_model);fp_model.queue_free()
	fp_model=load("res://scenes/characters/grip_studies/rifle/fp_"+("a" if style==0 else "b")+".tscn").instantiate();camera.add_child(fp_model)
	fp_model.get_node("AnimationTree").active=false;fp_model.get_node("AnimationPlayer").play("Grip")
	model.visible=not first_person;fp_model.visible=first_person
	title.text=("A — опорная ближе по цевью" if style==0 else "B — опорная дальше по цевью")+"\n1 / 2 — вариант; ПКМ — вращать; колесо — масштаб\n3 — справа; 4 — слева; 5 — сверху; 6 — общий вид; 7 — первое лицо"
func update_camera()->void:
	model.visible=not first_person;fp_model.visible=first_person
	camera.cull_mask=1|(1<<19) if first_person else 1|(1<<18)
	camera.projection=Camera3D.PROJECTION_PERSPECTIVE if first_person else Camera3D.PROJECTION_ORTHOGONAL
	if first_person:
		camera.position=Vector3(0,1.65,0);camera.rotation=Vector3.ZERO;camera.fov=75;return
	camera.position=focus+Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation))*.8
	camera.look_at(focus)
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		azimuth-=event.relative.x*.006;elevation=clampf(elevation+event.relative.y*.006,-1.40,1.40);update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:camera.size=maxf(.20,camera.size*.9)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:camera.size=minf(1.2,camera.size/ .9)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1:set_style(0)
			KEY_2:set_style(1)
			KEY_3:first_person=false;azimuth=PI*.5;elevation=.10;camera.size=.60;focus=Vector3(.13,1.425,-.32)
			KEY_4:first_person=false;azimuth=-PI*.5;elevation=.10;camera.size=.60;focus=Vector3(.13,1.425,-.32)
			KEY_5:first_person=false;azimuth=.3;elevation=1.40;camera.size=.60;focus=Vector3(.13,1.425,-.32)
			KEY_6:first_person=false;azimuth=PI*.75;elevation=.20;camera.size=.95;focus=Vector3(.02,1.32,-.12)
			KEY_7:first_person=not first_person
		update_camera()
