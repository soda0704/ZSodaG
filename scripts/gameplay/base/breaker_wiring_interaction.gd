class_name BreakerWiringInteraction
extends Node3D

@export_flags_3d_physics var contact_mask := 2097152
@export var idle_materials: Array[Material]
@export var selected_materials: Array[Material]
@export var connected_materials: Array[Material]
@export var loose_meshes: Array[Mesh]
@export var route_meshes: Array[Mesh]
@export var symbols: PackedStringArray = ["I", "II", "III", "IV"]
# The parent owns this component; a reciprocal script type keeps resource cycles alive.
@onready var breaker: StaticBody3D = get_parent()
@onready var camera: Camera3D = $RepairCamera
@onready var camera_animation: AnimationPlayer = $FocusAnimation
@onready var hud: CanvasLayer = $RepairHUD
@onready var hint: Label = $RepairHUD/Root/Strip/Content/Hint
@onready var status: Label3D = $Board/Status
@onready var connector_audio: AudioStreamPlayer3D = $ConnectorAudio
@onready var error_audio: AudioStreamPlayer3D = $ErrorAudio
@onready var selection_audio: AudioStreamPlayer3D = $SelectionAudio

var active := false
var selected := -1
var _focus: WiringContact
var _previous_camera: Camera3D
var _player: GamePlayer
var _previous_links: Array = []
var _initialized := false
var _opening_day := -1
var _pending_left := -1
var _pending_msec := 0
var _pad_column := 0
var _pad_row := 0
var _pad_mode := false
var _closing := false
var _notice := ""
var _sources: Array[WiringContact] = []
var _outputs: Array[WiringContact] = []
var _cables: Array[MeshInstance3D] = []
var _loose_plugs: Array[Node3D] = []

func _ready() -> void:
	for i in 4:
		_sources.append(get_node("Board/Source%d" % i))
		_outputs.append(get_node("Board/Output%d" % i))
		_cables.append(get_node("Board/Cable%d" % i))
		_loose_plugs.append(get_node("Board/Source%d/Plug" % i))
	$RepairHUD/Root/Strip/Content/Close.pressed.connect(close)
	set_process(false)
	set_process_input(false)

func bind_controller(controller: BaseGameplayController) -> void:
	controller.snapshot_changed.connect(refresh)
	refresh(controller.get_snapshot())

func begin() -> void:
	var controller: BaseGameplayController = breaker.get_controller()
	var local := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if active or controller == null or not controller.maintenance.get("wires_required", false): return
	if controller.maintenance.get("wire_order", []).size() != 4: return
	if get_tree().get_first_node_in_group("wiring_ui") != null or not breaker.can_use(multiplayer.get_unique_id(), local): return
	var menu := get_node_or_null("/root/GameMenu")
	if menu != null and menu.is_menu_open(): return
	var journal := get_node_or_null("/root/QuestJournal")
	if journal != null: journal.force_close()
	_previous_camera = get_viewport().get_camera_3d()
	_player = local
	_opening_day = controller.day_index
	active = true
	breaker.set_local_service_view(true)
	_closing = false
	selected = -1
	_notice = ""
	_pending_left = -1
	_pad_column = 0
	_pad_row = 0
	_pad_mode = false
	add_to_group("wiring_ui")
	_player.refresh_crosshair_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	camera.make_current()
	_player._refresh_equipment_visuals()
	camera_animation.play(&"focus")
	hud.show()
	set_process(true)
	set_process_input(true)
	refresh(controller.get_snapshot())

func _process(_delta: float) -> void:
	$RepairCamera/RepairBeam.visible = active and is_instance_valid(_player) and _player._flashlight_enabled and _player._has_flashlight and _player._battery_charge > 0.0 and not _player._flashlight_malfunctioning
	var controller: BaseGameplayController = breaker.get_controller()
	var menu := get_node_or_null("/root/GameMenu")
	if not is_instance_valid(_player) or controller == null or (menu != null and menu.is_menu_open()):
		close()
		return
	if _player.survival.dead or _player.is_sleeping_in_bunk() or _player.is_driving() or _player.is_carrying_corpse() or _player.is_debug_free_camera_active() or controller.day_index != _opening_day or controller.main_breaker_on or _player.global_position.distance_to(breaker.global_position) > breaker.interaction_distance:
		close()
		return
	# A stale request must not leave the local plug permanently disabled.
	if _pending_left >= 0 and Time.get_ticks_msec() - _pending_msec > 2000:
		_pending_left = -1
		_notice = "Соединение не подтверждено · попробуйте ещё раз"
		refresh(controller.get_snapshot())
	if not _pad_mode: _set_focus(contact_at(get_viewport().get_mouse_position()))

func contact_at(point: Vector2) -> WiringContact:
	var origin := camera.project_ray_origin(point)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(point) * camera.far, contact_mask | 3, [breaker.get_rid()])
	query.collide_with_areas = true
	if is_instance_valid(_player): query.exclude = [breaker.get_rid(), _player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var contact := hit.get("collider") as WiringContact
	return contact if contact != null and is_ancestor_of(contact) else null

func _input(event: InputEvent) -> void:
	if not active or event.is_echo(): return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event is InputEventMouseMotion:
		_pad_mode = false
		_set_focus(contact_at(event.position))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			selected = -1
			_notice = ""
			refresh(breaker.get_controller().get_snapshot())
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var contact := contact_at(event.position)
			# Both click-to-connect and releasing a picked plug over a socket work.
			if event.pressed or (selected >= 0 and contact != null and contact.is_output): choose_contact(contact)
			# Let the authored Close button receive GUI clicks outside the contacts.
			if contact != null: get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		_pad_mode = true
		if event.is_action_pressed("ui_up"): _pad_row = posmod(_pad_row - 1, 4)
		if event.is_action_pressed("ui_down"): _pad_row = posmod(_pad_row + 1, 4)
		if event.is_action_pressed("ui_left"): _pad_column = 0
		if event.is_action_pressed("ui_right"): _pad_column = 1
		_set_focus(_sources[_pad_row] if _pad_column == 0 else _outputs[_pad_row])
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if _focus == null: _set_focus(_sources[_pad_row] if _pad_column == 0 else _outputs[_pad_row])
		choose_contact(_focus)
		get_viewport().set_input_as_handled()

func choose_contact(contact: WiringContact) -> void:
	if not active or contact == null or not is_ancestor_of(contact): return
	var controller: BaseGameplayController = breaker.get_controller()
	if controller == null or not controller.maintenance.get("wires_required", false) or _pending_left >= 0: return
	var links: Array = controller.maintenance.get("wire_links", [])
	var order: Array = controller.maintenance.get("wire_order", [])
	if order.size() != 4: return
	if not contact.is_output:
		if links.has(contact.row): return
		selected = contact.row
		_notice = "Цепь %s · соедините с гнездом того же номера" % symbols[selected]
		selection_audio.play()
		refresh(controller.get_snapshot())
		return
	if selected < 0:
		_notice = "Сначала выберите свободный штекер слева"
	elif int(order[selected]) != contact.row:
		_notice = "Неверный контакт · проверьте номер цепи"
		error_audio.play()
	else:
		var left := selected
		selected = -1
		_pending_left = left
		_pending_msec = Time.get_ticks_msec()
		_notice = "Проверка соединения…"
		if multiplayer.is_server():
			if not controller.connect_wire_authoritative(multiplayer.get_unique_id(), left, contact.row):
				_pending_left = -1
				_notice = "Соединение отклонено · подойдите к щиту"
		else:
			controller.request_wire.rpc_id(1, left, contact.row)
	refresh(controller.get_snapshot())

func refresh(_snapshot: Dictionary) -> void:
	var controller: BaseGameplayController = breaker.get_controller()
	if controller == null: return
	var order: Array = controller.maintenance.get("wire_order", [])
	var links: Array = controller.maintenance.get("wire_links", [])
	if order.size() != 4: return
	if selected >= 0 and links.has(selected):
		selected = -1
		_notice = "Соединение уже выполнено напарником"
	if _pending_left >= 0 and links.has(_pending_left):
		_pending_left = -1
		_notice = "Контакт зафиксирован"
	for i in 4:
		var destination := int(order[i])
		var complete := links.has(i)
		_cables[i].mesh = route_meshes[i*4+destination] if complete else loose_meshes[i]
		_cables[i].material_override = connected_materials[i] if complete else (selected_materials[i] if selected == i else idle_materials[i])
		_loose_plugs[i].visible = not complete
		_sources[i].visible = not complete
		_sources[i].label.text = symbols[i]
		_sources[i].ring.material_override = selected_materials[i] if selected == i else idle_materials[i]
		_sources[i].collision_layer = 0 if complete else contact_mask
		_outputs[destination].label.text = symbols[i]
		_outputs[destination].ring.material_override = connected_materials[i] if complete else idle_materials[i]
		_outputs[destination].collision_layer = 0 if complete else contact_mask
		var animator := _sources[i].get_node("SelectionAnimation") as AnimationPlayer
		if selected == i and not animator.is_playing(): animator.play(&"selected")
		elif selected != i and animator.is_playing():
			animator.play(&"RESET")
			animator.advance(0)
			animator.stop()
		if _initialized and not controller.applying_initial_snapshot and complete and not _previous_links.has(i):
			connector_audio.play()
			(_outputs[destination].get_node("SeatAnimation") as AnimationPlayer).play(&"seat")
		elif not complete or controller.applying_initial_snapshot:
			(_outputs[destination].get_node("SeatAnimation") as AnimationPlayer).stop()
			_outputs[destination].get_node("InsertionTip").hide()
	_previous_links = links.duplicate()
	_initialized = true
	status.text = "ЦЕПИ ВОССТАНОВЛЕНЫ" if links.size() == 4 else "ОБЕСТОЧЕНО / %d ИЗ 4 ЦЕПЕЙ" % links.size()
	_update_hint()

func _set_focus(contact: WiringContact) -> void:
	if _focus == contact: return
	if is_instance_valid(_focus): _focus.set_focus(false)
	_focus = contact
	if is_instance_valid(_focus): _focus.set_focus(true)
	_update_hint()

func _update_hint() -> void:
	var controller: BaseGameplayController = breaker.get_controller()
	if controller == null: return
	if controller.maintenance.get("wire_links", []).size() == 4:
		hint.text = "Цепи восстановлены · выйдите из ремонта и включите рубильник"
	elif not _notice.is_empty(): hint.text = _notice
	else: hint.text = "Выберите штекер, затем гнездо с тем же номером · ЛКМ / × · ПКМ — отменить выбор"

func close() -> void:
	$RepairCamera/RepairBeam.hide()
	if not active or _closing: return
	_closing = true
	active = false
	breaker.set_local_service_view(false)
	selected = -1
	_pending_left = -1
	remove_from_group("wiring_ui")
	_set_focus(null)
	hud.hide()
	set_process(false)
	set_process_input(false)
	camera_animation.stop()
	if get_viewport().get_camera_3d() == camera and is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree(): _previous_camera.make_current()
	var menu := get_node_or_null("/root/GameMenu")
	if is_instance_valid(_player) and _player.is_inside_tree():
		_player._refresh_equipment_visuals()
		if not _player.survival.dead and (menu == null or not menu.is_menu_open()): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_player.refresh_crosshair_visibility()
	var controller: BaseGameplayController = breaker.get_controller()
	if controller != null: refresh(controller.get_snapshot())
	_player = null
	_closing = false

func _exit_tree() -> void:
	if active: close()
