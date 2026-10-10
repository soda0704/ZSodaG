extends Node3D
## Production character animation inspection, intentionally from the world view.
var actor: GamePlayer
var variant:=0
var item:StringName=&"pistol"
var book:=false
var moving:=false
var crouched:=false
var pitch:=0.0
var orbit:=1.95
var elevation:=0.08
var distance:=1.35
var reload_time:=0.0
var airborne:=0.0
var camera:Camera3D
var status:Label
func _ready():
	get_tree().root.get_node("GameMenu").force_close_menu()
	var input=get_tree().root.get_node("SteamInput");input.set_process(false);input.set_process_input(false)
	camera=$Arena/ReviewCamera;camera.cull_mask=1|(1<<18);camera.fov=38;camera.near=.02
	var canvas:=CanvasLayer.new();add_child(canvas)
	var panel:=VBoxContainer.new();panel.position=Vector2(16,16);canvas.add_child(panel)
	status=Label.new();panel.add_child(status)
	var variants:=Button.new();variants.text="Сменить персонажа (Tab)";variants.focus_mode=Control.FOCUS_NONE;variants.pressed.connect(func():variant=1-variant;spawn());panel.add_child(variants)
	for label in ["Пустые руки","Пистолет","Автомат","Нож","Фонарик","Канистра","Журнал"]:
		var button:=Button.new();button.text=label;button.focus_mode=Control.FOCUS_NONE;panel.add_child(button)
		button.pressed.connect(select.bind(label))
	for label in ["Перезарядка / удар (R)","Ходьба (W)","Приседание (C)","Прыжок (Space)"]:
		var button:=Button.new();button.text=label;button.focus_mode=Control.FOCUS_NONE;panel.add_child(button);button.pressed.connect(control.bind(label))
	var help:=Label.new();help.text="ПКМ: осмотр • колесо: масштаб\n↑ / ↓: прицеливание корпусом\nПроверка настоящего Player и AnimationTree";panel.add_child(help)
	spawn();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func spawn():
	if is_instance_valid(actor):actor.free()
	actor=load("res://scenes/characters/player.tscn").instantiate();actor.name="1";actor.setup(1,"",Vector3.ZERO,Color.WHITE,0,variant);$Arena/Players.add_child(actor)
	actor.set_physics_process(false);actor.survival.set_physics_process(false);actor.weapon.set_physics_process(false);actor.set_process_unhandled_input(false)
	actor.body_animator._local=false;actor.body_animator.set_local_visibility(false);actor.body_animator.first_person.overlay.hide();camera.make_current()
	actor._has_flashlight=true;actor._battery_charge=1;reload_time=0;refresh()
func refresh():
	actor._held_item_type=item;actor.weapon.apply_state(item,12,0);actor._refresh_equipment_visuals()
func select(label:String):
	book=label=="Журнал"
	item={"Пустые руки":&"","Пистолет":&"pistol","Автомат":&"m4a1","Нож":&"kitchen_knife","Фонарик":&"flashlight","Канистра":&"fuel_can","Журнал":&""}[label]
	actor.body_animator.cancel_weapon_action();reload_time=0;refresh()
func control(label:String):
	if label.begins_with("Перезарядка"):
		actor.body_animator.weapon_effect(item,item!=&"kitchen_knife");reload_time=2.1 if item==&"m4a1" else 1.35 if item==&"pistol" else .42
	elif label.begins_with("Ходьба"):moving=not moving
	elif label.begins_with("Приседание"):crouched=not crouched
	else:airborne=.95
func _process(delta):
	if not is_instance_valid(actor):return
	reload_time=maxf(0,reload_time-delta);airborne=maxf(0,airborne-delta)
	var context={"held_item":item,"journal_phase":2 if book else 0,"grounded":airborne<=0,"velocity":Vector3(0,0,-2.2 if crouched else -4.0) if moving else Vector3.ZERO,"pitch":pitch,"yaw":0.0,"crouching":crouched,"reloading":reload_time>0 and item!=&"kitchen_knife"}
	actor.body_animator.update_context(delta,context);actor.body_animator._sync_world_items(item,context.journal_phase)
	camera.position=Vector3(sin(orbit)*distance,1.35+elevation,cos(orbit)*distance)
	camera.look_at(Vector3(0,1.30,-.18))
	status.text="Персонаж %s · вид со стороны"%("A" if variant==0 else "B")
func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):orbit-=event.relative.x*.007;elevation=clampf(elevation-event.relative.y*.003,-.4,.5)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(.55,distance-.1)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(3,distance+.1)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:variant=1-variant;spawn()
			KEY_R:control("Перезарядка")
			KEY_W:control("Ходьба")
			KEY_C:control("Приседание")
			KEY_SPACE:control("Прыжок")
			KEY_UP:pitch=clampf(pitch+.2,-1.48,1.48)
			KEY_DOWN:pitch=clampf(pitch-.2,-1.48,1.48)
