class_name QuestJournalUI
extends CanvasLayer

const CRAFT_RECIPE = preload("res://assets/config/flamethrower_recipe.tres")
const ILLUSTRATION_ROOT := "res://assets/ui/journal_sketches/"
enum PresentationState { CLOSED, OPENING, OPEN, CLOSING }
@export_range(0.5, 3.0) var closing_speed := 1.35
@export var screen_margin := Vector2(60, 60)
@onready var journal_root: Control = $JournalRoot
@onready var notebook_pivot: Control = $JournalRoot/NotebookPivot
@onready var day_label: Label = $JournalRoot/NotebookPivot/Reveal/Ink/LeftPage/Day
@onready var objective_label: Label = $JournalRoot/NotebookPivot/Reveal/Ink/LeftPage/Objective
@onready var tasks_label: Label = $JournalRoot/NotebookPivot/Reveal/Ink/LeftPage/TaskScroll/Tasks
@onready var coop_status_label: Label = $JournalRoot/NotebookPivot/Reveal/Ink/LeftPage/CoopStatus
@onready var inventory_label: Label = $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/InventoryNote
@onready var controls_label: Label = $JournalRoot/NotebookPivot/Reveal/Ink/HelpPanel/Content/Controls
@onready var replace_button: Button = $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/Actions/ReplaceBattery
@onready var mount_button: Button = $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/Actions/MountLight
@onready var drop_button: Button = $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/Actions/DropItem
@onready var give_button: Button = $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/Actions/GiveItem
@onready var close_button: Button = $JournalRoot/NotebookPivot/Reveal/Ink/Footer/CloseButton
@onready var close_hint: Label = $JournalRoot/NotebookPivot/Reveal/Ink/Footer/CloseHint
@onready var help_panel: PanelContainer = $JournalRoot/NotebookPivot/Reveal/Ink/HelpPanel
@onready var _quest_card: JournalPhotoCard = $JournalRoot/NotebookPivot/Reveal/Ink/LeftPage/QuestPhotoRow/QuestPhoto
@onready var _blocker: Control = $JournalRoot/TransitionBlocker
var _cards: Dictionary = {}
var _selected_item: StringName = &""
var _controller: BaseGameplayController
var _phase := PresentationState.CLOSED
var _fit_scale := Vector2.ONE
var _character_arms: Node3D
var _arms_variant := -1
var _ink_viewport: SubViewport
var _page_surfaces: Array[MeshInstance3D] = []
var _phase_time := 0.0
var _last_ink_point := Vector2.ZERO
var _inventory_refresh_elapsed := 0.0
var _last_inventory_view: Dictionary = {}
var _reading := JournalReadingStore.new()
var _campaign_id := ""
var _live_record: Dictionary = {}
var _read_elapsed := 0.0
var _history_day := -1
var _map_open := false
var _inserts: Node3D
var _section_busy := false
var _ink_refresh_elapsed := 0.0
var _animation_speed := 1.6
var _pointer_in_map := false
@onready var _history: HBoxContainer = $JournalRoot/NotebookPivot/Reveal/Ink/History
@onready var _map_sheet: Control = $JournalRoot/NotebookPivot/Reveal/Ink/MapSheet
@onready var _notes_tab: Button = $JournalRoot/NotebookPivot/Reveal/Ink/Sections/Notes
@onready var _map_tab: Button = $JournalRoot/NotebookPivot/Reveal/Ink/Sections/Map

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for card: JournalPhotoCard in $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/InventoryScroll/InventoryGrid.get_children():
		_cards[card.item_id] = card
		card.pressed.connect(_select_item.bind(card.item_id))
		card.focus_entered.connect(_select_item.bind(card.item_id))
	replace_button.pressed.connect(_inventory_action.bind(&"replace_battery"))
	drop_button.pressed.connect(_drop_selected)
	give_button.pressed.connect(_offer_selected)
	mount_button.pressed.connect(_mount_light)
	close_button.pressed.connect(close_journal)
	$JournalRoot/NotebookPivot/Reveal/Ink/Footer/HelpButton.pressed.connect(_toggle_help)
	$JournalRoot/NotebookPivot/Reveal/Ink/HelpPanel/Content/Dismiss.pressed.connect(_toggle_help)
	get_viewport().size_changed.connect(_layout_book)
	force_close()
	_layout_book()
	call_deferred("_bind_controller")
	_initialize_book_ui()
	_notes_tab.pressed.connect(_show_section.bind(false))
	_map_tab.pressed.connect(_show_section.bind(true))
	_map_sheet.loupe_requested.connect(_on_loupe_requested)
	_history.get_node("Previous").pressed.connect(_turn_history.bind(-1))
	_history.get_node("Next").pressed.connect(_turn_history.bind(1))

func _initialize_book_ui() -> void:
	_ink_viewport=SubViewport.new(); _ink_viewport.name="JournalInkViewport"
	_ink_viewport.size=Vector2i(1400,986); _ink_viewport.disable_3d=true; _ink_viewport.transparent_bg=true
	_ink_viewport.handle_input_locally=true; _ink_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(_ink_viewport)
	notebook_pivot.reparent(_ink_viewport)
	notebook_pivot.theme=journal_root.theme; notebook_pivot.position=Vector2.ZERO; notebook_pivot.scale=Vector2.ONE; notebook_pivot.pivot_offset=Vector2.ZERO
	var reveal: Control=notebook_pivot.get_node("Reveal")
	reveal.position=Vector2.ZERO; reveal.scale=Vector2.ONE; reveal.rotation=0; reveal.modulate=Color.WHITE
	reveal.get_node("Ink").modulate=Color.WHITE
	journal_root.get_node("Backdrop").modulate.a=0.12

func _process(delta: float) -> void:
	if is_journal_open():
		_ink_refresh_elapsed += delta
		if _ink_refresh_elapsed >= .1:
			_ink_refresh_elapsed = 0.0
			_request_ink_update()
	if _phase in [PresentationState.OPENING,PresentationState.CLOSING]:
		_phase_time+=delta*_animation_speed
		if _phase_time>=(0.88 if _phase==PresentationState.OPENING else 0.72): _animation_finished(&"")
	if not is_instance_valid(_controller):
		_bind_controller()
	if _phase == PresentationState.OPEN:
		if not _map_open and not _section_busy and _history_day < 0 and not help_panel.visible:
			_read_elapsed += delta
			if _read_elapsed >= .8: _reading.mark_read(_live_record)
		_inventory_refresh_elapsed += delta
		if _inventory_refresh_elapsed >= 0.1:
			_inventory_refresh_elapsed = 0.0
			_refresh_inventory()
	if is_journal_open():
		var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
		if player == null or player.survival.dead or player.is_sleeping_in_bunk() or (get_node("/root/GameMenu").is_menu_open() and not get_node("/root/GameMenu").is_capturing_feedback_screenshot()):
			force_close()

func _mount_light() -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	if player != null:
		_inventory_action(&"detach_light" if player.weapon_light_mounted else &"mount_light")

func _toggle_help() -> void:
	if _phase != PresentationState.OPEN: return
	help_panel.visible = not help_panel.visible
	if help_panel.visible:
		notebook_pivot.get_node("Reveal/Ink/HelpPanel/Content/Dismiss").grab_focus()
	else:
		close_button.grab_focus()

func _layout_book() -> void:
	if _ink_viewport!=null: return
	var viewport_size := get_viewport().get_visible_rect().size
	var book_size := notebook_pivot.size
	var fit := minf((viewport_size.x - screen_margin.x) / book_size.x, (viewport_size.y - screen_margin.y) / book_size.y)
	_fit_scale = Vector2.ONE * maxf(fit, 0.1)
	notebook_pivot.position = (viewport_size - book_size) * 0.5
	notebook_pivot.scale = _fit_scale

func _unhandled_input(event: InputEvent) -> void:
	if get_node("/root/GameMenu").is_menu_open(): return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("journal"):
		if _phase in [PresentationState.OPEN, PresentationState.OPENING]: close_journal()
		else: open_journal()
		get_viewport().set_input_as_handled()
	elif is_journal_open() and event.is_action_pressed("ui_cancel"):
		close_journal()
		get_viewport().set_input_as_handled()

func open_journal() -> void:
	if _phase in [PresentationState.OPEN, PresentationState.OPENING]: return
	if get_tree().get_first_node_in_group("wiring_ui") != null or get_tree().get_first_node_in_group("terminal_ui") != null: return
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player == null or player.survival.dead or player.is_debug_free_camera_active() or get_node("/root/GameMenu").is_menu_open() or player.is_sleeping_in_bunk(): return
	if not player.has_journal: return
	_bind_controller()
	_history_day = -1
	_read_elapsed = 0.0
	_apply_section(_map_open)
	_refresh_content()
	journal_root.show()
	help_panel.hide()
	_blocker.show()
	_phase_time=0.88*(1-clampf(_phase_time/0.72,0,1)) if _phase==PresentationState.CLOSING else 0.0
	_phase = PresentationState.OPENING
	_bind_character_arms(player)
	player.request_journal_phase(1)
	_request_ink_update()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout_book()
	_set_player_journal_visuals(true)

func close_journal() -> void:
	if not is_journal_open() or _phase == PresentationState.CLOSING: return
	if help_panel.visible:
		_toggle_help()
		return
	# Stow the book directly from its current spread, without returning to notes.
	if is_instance_valid(_inserts):
		_inserts.animation.pause()
		_inserts.set_loupe(false)
	_map_sheet.loupe_button.set_pressed_no_signal(false)
	_section_busy = false
	_phase_time=0.72*(1-clampf(_phase_time/0.88,0,1)) if _phase==PresentationState.OPENING else 0.0
	_phase = PresentationState.CLOSING
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null: player.request_journal_phase(3)
	_blocker.show()

func _animation_finished(_clip: StringName) -> void:
	if _phase == PresentationState.CLOSING:
		force_close()
	elif _phase == PresentationState.OPENING:
		_phase = PresentationState.OPEN
		var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
		if player != null: player.request_journal_phase(2)
		_blocker.hide()
		close_button.grab_focus()

func force_close() -> void:
	var was_open := is_journal_open()
	_phase = PresentationState.CLOSED
	_section_busy = false
	if is_instance_valid(_inserts): _inserts.reset()
	_set_map_cutout(false)
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null and was_open: player.request_journal_phase(0)
	journal_root.hide()
	help_panel.hide()
	_blocker.hide()
	if _ink_viewport!=null: _ink_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_set_player_journal_visuals(false)
	if was_open and get_tree().get_first_node_in_group("local_player") != null and not get_node("/root/GameMenu").is_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_player_journal_visuals(_open: bool) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null:
		player.refresh_crosshair_visibility()
		player._refresh_equipment_visuals()

func is_journal_open() -> bool:
	return _phase != PresentationState.CLOSED

func _request_ink_update() -> void:
	if _ink_viewport != null: _ink_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _bind_character_arms(player: GamePlayer) -> void:
	_animation_speed = player.journal_animation_speed
	_character_arms=player.body_animator.first_person_model
	_arms_variant=player.character_variant_id
	var book: Node3D=_character_arms.get_node("Journal")
	_inserts = book.get_node("FrontCoverPivot/Inserts")
	_inserts.snap_to_map() if _map_open else _inserts.reset()
	if not _inserts.content_requested.is_connected(_apply_section): _inserts.content_requested.connect(_apply_section)
	if not _inserts.transition_finished.is_connected(_section_finished): _inserts.transition_finished.connect(_section_finished)
	var rect: Rect2 = _map_sheet.scroll.get_global_rect()
	_inserts.bind_ink(_ink_viewport.get_texture(),Rect2(rect.position / Vector2(_ink_viewport.size),rect.size / Vector2(_ink_viewport.size)))
	# Widen the physical spread and its UI surfaces together, once per instance.
	if not book.has_meta("reading_width_fitted"):
		book.scale.x *= 1.04
		book.set_meta("reading_width_fitted",true)
	_page_surfaces.clear()
	for side in ["Left","Right"]:
		var surface: MeshInstance3D=book.get_node_or_null("FrontCoverPivot/InkLeft" if side=="Left" else "InkRight")
		if surface==null:
			surface=MeshInstance3D.new(); surface.name="Ink"+side
			(book.get_node("FrontCoverPivot") if side=="Left" else book).add_child(surface)
			var quad:=QuadMesh.new(); quad.size=Vector2(0.210,0.303); surface.mesh=quad
			surface.position=Vector3(0.105,0,-0.0062) if side=="Left" else Vector3(0,0,0.0122)
			if side=="Left": surface.rotation.y=PI
			surface.layers=1<<19; surface.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material: ShaderMaterial = surface.material_override
		if material == null:
			material = ShaderMaterial.new()
			material.shader=preload("res://assets/shaders/journal_ink.gdshader")
		material.set_shader_parameter("ink_texture",_ink_viewport.get_texture()); material.set_shader_parameter("atlas_offset",0.0 if side=="Left" else 0.5)
		var image: TextureRect = notebook_pivot.get_node("Reveal/BookImage")
		var box := image.get_global_rect()
		var texture_size := image.texture.get_size()
		var drawn := texture_size * minf(box.size.x / texture_size.x,box.size.y / texture_size.y)
		var paper_at := (box.position + (box.size-drawn)*.5) / Vector2(_ink_viewport.size)
		var paper_size := drawn / Vector2(_ink_viewport.size)
		material.set_shader_parameter("paper_texture",image.texture)
		material.set_shader_parameter("paper_rect",Vector4(paper_at.x,paper_at.y,paper_size.x,paper_size.y))
		_inserts.bind_paper(image.texture,Vector4(paper_at.x,paper_at.y,paper_size.x,paper_size.y))
		surface.material_override=material
		_page_surfaces.append(surface)
	_set_map_cutout(_map_open)

func _input(event: InputEvent) -> void:
	if get_node("/root/GameMenu").is_menu_open(): return
	if _phase!=PresentationState.OPEN or _section_busy or _page_surfaces.is_empty(): return
	var player:=get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player==null: return
	if event is InputEventMouse:
		var view_camera: Camera3D=player.body_animator.first_person.view_camera
		# Input is in the stretched UI canvas; the FP render target uses window pixels.
		var canvas_size := get_viewport().get_visible_rect().size
		var render_size := view_camera.get_viewport().get_visible_rect().size
		var render_point: Vector2 = event.position * render_size / canvas_size
		var origin:=view_camera.project_ray_origin(render_point)
		var direction:=view_camera.project_ray_normal(render_point)
		if _map_open and _inserts.loupe_active: _inserts.aim_loupe(origin,direction)
		for i in _page_surfaces.size():
			var page:=_page_surfaces[i]
			var inverse:=page.global_transform.affine_inverse()
			var ray_origin:=inverse*origin; var ray_direction:=inverse.basis*direction
			if absf(ray_direction.z)<0.0001: continue
			var distance: float=-ray_origin.z/ray_direction.z
			if distance<0: continue
			var hit:=ray_origin+ray_direction*distance
			var size: Vector2=page.mesh.size
			if absf(hit.x)>size.x*0.5 or absf(hit.y)>size.y*0.5: continue
			var uv:=Vector2(hit.x/size.x+0.5,0.5-hit.y/size.y)
			var point: Vector2=Vector2((uv.x*0.5+i*0.5)*1400,uv.y*986)
			var inside_map: bool = _map_open and _map_sheet.scroll.get_global_rect().has_point(point)
			if not event is InputEventMouseMotion or not inside_map or not _pointer_in_map: _request_ink_update()
			_pointer_in_map = inside_map
			var forwarded:=event.duplicate() as InputEventMouse
			forwarded.position=point; forwarded.global_position=point
			if forwarded is InputEventMouseMotion: forwarded.relative=point-_last_ink_point
			_last_ink_point=point
			_ink_viewport.push_input(forwarded,true)
			get_viewport().set_input_as_handled()
			return
		# Release/leave events also reach the UI when the cursor leaves a page.
		# Otherwise a card can remain pressed after a drag outside the spread.
		var outside:=event.duplicate() as InputEventMouse
		outside.position=Vector2(-100,-100); outside.global_position=outside.position
		_ink_viewport.push_input(outside,true)
	elif event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventKey:
		_request_ink_update()
		if not event.is_action_pressed("journal") and not event.is_action_pressed("ui_cancel") and not event.is_action_pressed("tester_feedback"): _ink_viewport.push_input(event)

func _bind_controller() -> void:
	var next := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if next == _controller:
		return
	if is_instance_valid(_controller) and _controller.snapshot_changed.is_connected(_on_snapshot_changed):
		_controller.snapshot_changed.disconnect(_on_snapshot_changed)
	_controller = next
	if _controller != null:
		_controller.snapshot_changed.connect(_on_snapshot_changed)
	_refresh_content()

func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	_refresh_content()

func _refresh_content() -> void:
	if not is_instance_valid(_controller) or not _controller.has_entered_base():
		day_label.text = "ПОЛЕВЫЕ ЗАПИСИ"
		objective_label.text = "Выяснить что тут произошло"
		tasks_label.text = ""
		_quest_card.hide()
		coop_status_label.text = ""
	else:
		var day := _controller.day_index
		day_label.text = "ЭКСПЕДИЦИЯ  /  ДЕНЬ %02d" % day
		_quest_card.visible = day <= 2
		if day == 1:
			objective_label.text = "Вернуть базу к жизни"
			tasks_label.text = "\n".join([
				_task_line(_controller.fuel_delivered, "Заправить бак"),
				_task_line(_controller.main_breaker_on, "Включить главный щит"),
				_task_line(_controller.elevator_backup_installed, "Найти предохранитель в медпункте и вставить в резервный блок у входа"),
				_task_line(_controller.are_all_connected_players_sleeping(), "Отдохнуть на базе"),
			])
			_set_quest_photo("fuel_can", "Топливо для базы", "Доставлено" if _controller.fuel_delivered else "Найти в генераторной")
		elif day == 2:
			var stage := int(_controller.quest_stage)
			objective_label.text = "Ключ шифрования"
			tasks_label.text = "\n".join([_task_line(stage >= 3, "Найти ключ на уровне 1"), _task_line(stage >= 4, "Передать ключ в хабе")])
			_set_quest_photo("key", "Ключ шифрования", "У команды · ×1" if stage == 3 else "Передан на базу" if stage == 4 else "Хранилище данных · 1")
		elif day == _controller.LEVEL_TWO_DAY_INDEX:
			objective_label.text = "Обследовать уровень 2"
			tasks_label.text = _task_line(_controller.containment.get("level2", false), "Обследовать уровень 2")
			if _controller.containment.get("level2", false):
				tasks_label.text += "\n\nВернуться на базу и отдохнуть."
		elif day == _controller.TRIALS_DAY_INDEX:
			objective_label.text = "Обследовать испытательную камеру"
			tasks_label.text = _task_line(_controller.containment.get("trials", false), "Войти в испытательную камеру на уровне 3")
			if _controller.containment.get("trials", false):
				tasks_label.text += "\n\nВернуться на базу и отдохнуть."
		else:
			var objective := _controller.get_expedition_objective()
			objective_label.text = objective.title
			var lines: PackedStringArray = []
			for task in objective.tasks:
				lines.append(_task_line(task.done, task.text))
			tasks_label.text = "\n".join(lines)
			if not str(objective.get("description", "")).is_empty(): tasks_label.text = str(objective.description) + "\n\n" + tasks_label.text
			if not objective.note.is_empty(): tasks_label.text += "\n\n" + objective.note
		coop_status_label.text = ""
		if not _controller.sleeping_peer_ids.is_empty():
			coop_status_label.text = "Отдыхают: %d/%d" % [_controller.sleeping_peer_ids.size(), _controller.get_connected_player_peer_ids().size()]
		if _controller.maintenance.get("wires_required", false):
			objective_label.text = "Авария электроснабжения"
			tasks_label.text = "Вернуться в генераторную.\nСоединить провода в главном щите.\nПосле ремонта включить щит."
			_quest_card.hide()
		elif _controller.maintenance.get("alarm", false) and not _controller.main_breaker_on:
			objective_label.text = "Восстановить питание"
			tasks_label.text += "\n\nПитание отключено. Проверить топливо\nв генераторной и включить главный щит."
		elif not _controller.main_breaker_on and day > 1:
			tasks_label.text += "\n\nПитание отключено. Вернуться\nв генераторную и проверить главный щит."
		var recovery: Dictionary = _controller.maintenance.get("corpse_recovery", {})
		if recovery.get("picked_up", false):
			var delivered: Array = recovery.get("delivered", [])
			tasks_label.text += "\n\n" + _task_line(delivered.has(0), "Отнести тело с моста на медицинскую койку · %d/1" % (1 if delivered.has(0) else 0))
			tasks_label.text += "\nПроверить на признаки жизни или узнать причину смерти."
	_refresh_inventory()
	_capture_record()

func has_unread_entries() -> bool:
	var actor := get_tree().get_first_node_in_group("local_player") as GamePlayer
	return actor != null and actor.has_journal and _reading.unread(_live_record)

func _capture_record() -> void:
	var identity := str(_controller.maintenance.get("journal_campaign_id", "")) if is_instance_valid(_controller) else ""
	if identity != _campaign_id:
		_campaign_id = identity
		if not identity.is_empty(): _reading.bind_campaign(identity)
		else: _reading = JournalReadingStore.new()
		_history_day = -1
	_live_record = {"day": _controller.day_index if is_instance_valid(_controller) else 1,
		"objective": objective_label.text, "tasks": tasks_label.text}
	var actor := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if actor != null and actor.has_journal and _reading.capture(_live_record): _read_elapsed = 0.0
	if _history_day >= 0:
		_display_history()
	_history.get_node("Caption").text = "Сегодня · %02d" % int(_live_record.day) if _history_day < 0 else "День %02d · архив" % _history_day
	_history.get_node("Previous").disabled = _reading.entries.size() < 2 or (_history_day >= 0 and _history_day == int(_reading.entries.front().day))
	_history.get_node("Next").disabled = _history_day < 0
	var visited: Array = _controller.maintenance.get("journal_visited", []).duplicate() if is_instance_valid(_controller) else []
	if is_instance_valid(_controller) and _controller.has_entered_base() and not visited.has(0): visited.append(0)
	_map_sheet.update_visited(visited)
	_map_tab.visible = is_instance_valid(_controller) and _controller.has_entered_base()

func _turn_history(direction: int) -> void:
	var index := _reading.entries.size()-1
	if _history_day >= 0:
		for i in _reading.entries.size():
			if int(_reading.entries[i].day) == _history_day: index = i
	index = clampi(index + direction, 0, _reading.entries.size()-1)
	_history_day = -1 if index == _reading.entries.size()-1 else int(_reading.entries[index].day)
	_refresh_content()
	_read_elapsed = 0.0

func _display_history() -> void:
	for record in _reading.entries:
		if int(record.day) != _history_day: continue
		day_label.text = "ЭКСПЕДИЦИЯ / ДЕНЬ %02d / АРХИВ" % _history_day
		objective_label.text = record.objective
		tasks_label.text = record.tasks
		_quest_card.hide()
		coop_status_label.text = ""
		return
	_history_day = -1

func _show_section(show_map: bool) -> void:
	if show_map and (not is_instance_valid(_controller) or not _controller.has_entered_base()): return
	if _section_busy or show_map == _map_open: return
	if _phase != PresentationState.OPEN or not is_instance_valid(_inserts): return
	_inserts.bind_turn_texture(_ink_viewport.get_texture())
	_section_busy = true
	_read_elapsed = 0.0
	_blocker.show()
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null: player.request_journal_map(show_map)
	_inserts.transition_to(show_map)

func _on_loupe_requested(enabled: bool) -> void:
	if not _map_open or _section_busy or _phase != PresentationState.OPEN: return
	_inserts.set_loupe(enabled)
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null: player.request_journal_map(true,enabled)

func _section_finished() -> void:
	_section_busy = false
	if _phase == PresentationState.OPEN: _blocker.hide()

func _set_map_cutout(enabled: bool) -> void:
	if _page_surfaces.is_empty() or not is_instance_valid(_page_surfaces[0]): return
	var material: ShaderMaterial = _page_surfaces[0].material_override
	material.set_shader_parameter("map_cutout",enabled)

func _apply_section(show_map: bool) -> void:
	_map_open = show_map
	_request_ink_update()
	_set_map_cutout(show_map)
	notebook_pivot.get_node("Reveal/Ink/LeftPage").visible = not show_map
	notebook_pivot.get_node("Reveal/Ink/RightPage").visible = not show_map
	_history.visible = not show_map
	_map_sheet.visible = show_map
	_notes_tab.set_pressed_no_signal(not show_map)
	_map_tab.set_pressed_no_signal(show_map)
	help_panel.hide()
	_read_elapsed = 0.0
	if not show_map: _map_sheet.loupe_button.set_pressed_no_signal(false)

func _set_quest_photo(id: String, title: String, note: String) -> void:
	var path := ILLUSTRATION_ROOT + id + ".png"
	_quest_card.picture.texture = load(path) if ResourceLoader.exists(path) else null
	_quest_card.caption.text = title
	_quest_card.set_note(note)

func _task_line(done: bool, text_value: String) -> String:
	return "%s  %s" % ["✓" if done else "○", text_value]

func get_hud_summary() -> Dictionary:
	# Both presentations share the journal's existing story and maintenance rules.
	if not is_instance_valid(_controller) or not _controller.has_entered_base():
		return {"day": 1, "objective": "Выяснить что тут произошло", "tasks": [], "title_only": true}
	var source := str(_live_record.get("tasks", tasks_label.text))
	# Narrative belongs on the journal page, not in the HUD's action checklist.
	var description := str(_controller.get_expedition_objective().get("description", ""))
	if not description.is_empty(): source = source.trim_prefix(description + "\n\n")
	var pending: Array[String] = []
	for paragraph in source.split("\n\n", false):
		var continuation := ""
		for line in paragraph.split("\n", false):
			var task := line.strip_edges()
			if task.is_empty(): continue
			if task.begins_with("✓") or task.begins_with("○"):
				if not continuation.is_empty(): pending.append(continuation)
				continuation = ""
				if task.begins_with("○"): pending.append(task.trim_prefix("○").strip_edges())
			else:
				continuation += (" " if not continuation.is_empty() else "") + task
				if task.ends_with(".") or task.ends_with("!") or task.ends_with("?"):
					pending.append(continuation)
					continuation = ""
		if not continuation.is_empty(): pending.append(continuation)
	return {"day": _controller.day_index,
		"objective": _live_record.get("objective", objective_label.text),
		"tasks": pending, "empty_label": "ЗАДАЧИ ВЫПОЛНЕНЫ"}

func _select_item(id: StringName) -> void:
	_selected_item = id
	for card: JournalPhotoCard in _cards.values():
		card.set_pressed_no_signal(card.item_id == id)
	_refresh_inventory()
	if _cards.has(id) and _cards[id].visible:
		var scroll: ScrollContainer = notebook_pivot.get_node("Reveal/Ink/RightPage/InventoryScroll")
		scroll.call_deferred("ensure_control_visible", _cards[id])

func _refresh_inventory() -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	var data: Dictionary = player.call("get_inventory_snapshot") if player != null else {}
	var batteries: Array = data.get("spare_batteries", [])
	var has_light := bool(data.get("has_flashlight", false))
	var charge := float(data.get("battery_charge", 0.0))
	var hand := StringName(data.get("held_item", &""))
	# Only the displayed values invalidate the cards; battery drain is rounded in UI.
	var input_service := get_node("/root/SteamInput")
	var view := {"hand": hand, "light": has_light, "charge": roundi(charge * 100.0),
		"batteries": batteries, "selected": _selected_item,
		"rounds": data.get("weapon_rounds", 0), "ammo": data.get("pistol_ammo", 0),
		"magazines": data.get("rifle_magazines", []), "mounted": data.get("weapon_light_mounted", false),
		"fuel": roundi(float(data.get("flame_fuel_liters",0.0))*100), "parts": data.get("crafting_parts", {}), "recipe": _controller != null and _controller.containment.get("cave_hives_found",false),
		"tape": data.get("tape_count", 0), "crowbar": data.get("crowbar_uses", 0),
		"controls": input_service.get_controls_hint(),
		"close": [input_service.get_action_hint(&"journal"), input_service.get_action_hint(&"ui_cancel")],
		"depleted": charge <= 0.0}
	if view == _last_inventory_view: return
	_last_inventory_view = view.duplicate(true)
	_cards[&"flashlight"].visible = has_light
	_cards[&"battery"].visible = not batteries.is_empty()
	_cards[&"fuel_can"].visible = hand == &"fuel_can"
	_cards[&"fuse"].visible = hand == &"fuse"
	_cards[&"pistol_ammo"].visible = int(data.get("pistol_ammo", 0)) > 0
	_cards[&"pistol_ammo"].set_note("×%d" % int(data.get("pistol_ammo", 0)))
	_cards[&"rifle_magazine"].visible = not data.get("rifle_magazines", []).is_empty()
	_cards[&"rifle_magazine"].set_note("×%d" % data.get("rifle_magazines", []).size())
	for id: StringName in WeaponController.TYPES:
		_cards[id].visible = hand == id
		var reserve := "%d патр." % int(data.get("pistol_ammo", 0)) if id == &"pistol" else "%d магаз." % data.get("rifle_magazines", []).size()
		_cards[id].set_note("" if id == &"kitchen_knife" else "%d · запас %s" % [int(data.get("weapon_rounds", 0)), reserve])
	_cards[&"flashlight"].set_note("%d%%" % roundi(charge * 100.0))
	_cards[&"battery"].set_note("×%d" % batteries.size())
	var recipe_known: bool = _controller != null and _controller.containment.get("cave_hives_found",false)
	var show_recipe := _selected_item == &"flame_recipe" and recipe_known
	var counts: Dictionary = data.get("crafting_parts", {}).duplicate()
	counts[&"tape"] = int(data.get("tape_count",0))
	_cards[&"flame_recipe"].visible = recipe_known
	_cards[&"flame_recipe"].set_note("По 1 каждой детали")
	_cards[&"flamethrower"].visible = hand == &"flamethrower"
	_cards[&"flamethrower"].set_note("Топливо: %d%%" % roundi(float(data.get("flame_fuel_liters",0.0))/player.weapon.flame.capacity_liters*100) if player!=null else "")
	for type in CRAFT_RECIPE.requirements:
		var count := int(counts.get(type,0))
		_cards[type].visible = show_recipe or count > 0
		_cards[type].set_note("%d / 1" % count if recipe_known else "×%d" % count)
	if _cards.has(_selected_item) and not _cards[_selected_item].visible:
		_cards[_selected_item].set_pressed_no_signal(false)
		_selected_item = &""
	replace_button.visible = has_light and charge <= 0.0 and not batteries.is_empty()
	drop_button.visible = _selected_item != &"" and _selected_item not in [&"pistol_ammo", &"rifle_magazine", &"flame_recipe"]
	drop_button.disabled = CRAFT_RECIPE.requirements.has(_selected_item) and int(counts.get(_selected_item,0)) <= 0
	var offer_player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	give_button.visible = offer_player != null and offer_player.handoff.available(_selected_item, true)
	give_button.disabled = offer_player == null or offer_player.handoff.is_offering()
	mount_button.visible = hand == &"m4a1" and has_light
	mount_button.text = "Снять фонарь" if data.get("weapon_light_mounted", false) else "Примотать"
	mount_button.tooltip_text = "Снять в постоянный инвентарь. Скотч не возвращается." if data.get("weapon_light_mounted", false) else "Закрепить фонарик на M4A1: нужен 1 скотч. Свет включается кнопкой F."
	mount_button.disabled = not data.get("weapon_light_mounted", false) and int(data.get("tape_count", 0)) <= 0
	inventory_label.text = ""
	if _selected_item == &"battery":
		var groups: Dictionary = {}
		for cell: Variant in batteries:
			var percent := roundi(float(cell) * 100.0)
			groups[percent] = int(groups.get(percent, 0)) + 1
		var lines: Array[String] = []
		var charges := groups.keys()
		charges.sort()
		charges.reverse()
		for percent: int in charges:
			lines.append("%d%% ×%d" % [percent, groups[percent]])
		inventory_label.text = " · ".join(lines) if lines.size() <= 3 else "%d батареек · заряд %d–%d%%" % [batteries.size(), charges.back(), charges.front()]
	elif not has_light and batteries.is_empty() and hand == &"":
		inventory_label.text = "Здесь будут фотографии найденных вещей."
	if _selected_item == &"pistol_ammo":
		inventory_label.text = "Патронов в запасе: %d" % int(data.get("pistol_ammo", 0))
	elif _selected_item == &"rifle_magazine":
		var rounds: Array[String] = []
		for magazine in data.get("rifle_magazines", []): rounds.append(str(int(magazine)))
		inventory_label.text = "Патронов в магазинах: " + ", ".join(rounds)
	if _selected_item == &"flame_recipe":
		inventory_label.text = "На один огнемёт — по 1 каждой детали.\nСборка на столе в комнате снаряжения, уровень 0."
	elif _selected_item == &"flamethrower":
		inventory_label.text = "Удерживать атаку — струя огня.\nЗаправка: навести на канистру и нажать %s." % input_service.get_action_hint(&"replace_battery")
	elif CRAFT_RECIPE.requirements.has(_selected_item):
		inventory_label.text = "%s: %d / 1 для сборки" % [CRAFT_RECIPE.titles[_selected_item], int(counts.get(_selected_item,0))]
	controls_label.text = get_node("/root/SteamInput").get_controls_hint()
	if int(data.get("tape_count", 0)) > 0 or int(data.get("crowbar_uses", 0)) > 0:
		inventory_label.text += "\nСкотч: %d · Монтировка: %s" % [int(data.get("tape_count", 0)), "есть" if int(data.get("crowbar_uses", 0)) > 0 else "нет"]
	close_hint.text = "%s / %s · Закрыть журнал" % [get_node("/root/SteamInput").get_action_hint(&"journal"), get_node("/root/SteamInput").get_action_hint(&"ui_cancel")]
	if _phase == PresentationState.OPEN:
		var focused := _ink_viewport.gui_get_focus_owner()
		if focused == null or not focused.is_visible_in_tree():
			close_button.grab_focus()

func _offer_selected() -> void:
	if _phase != PresentationState.OPEN: return
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player == null or not player.handoff.available(_selected_item, true): return
	close_journal()
	player.handoff.request_offer(_selected_item, true)

func _drop_selected() -> void:
	if _selected_item in [&"pistol_ammo", &"rifle_magazine", &"flame_recipe"]: return
	if CRAFT_RECIPE.pickup_scenes.has(_selected_item):
		_inventory_action(StringName("drop_part:" + String(_selected_item)))
	elif _selected_item == &"tape":
		_inventory_action(&"drop_tape")
	elif _selected_item == &"battery":
		_inventory_action(&"drop_battery")
	elif _selected_item == &"flashlight":
		_inventory_action(&"drop_flashlight")
	else:
		_inventory_action(&"drop_hand_item")

func _inventory_action(action: StringName) -> void:
	if _phase != PresentationState.OPEN: return
	var player := get_tree().get_first_node_in_group("local_player")
	if player != null:
		player.call("request_inventory_action", action)
	_refresh_inventory()
