class_name QuestJournalUI
extends CanvasLayer

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
@onready var close_button: Button = $JournalRoot/NotebookPivot/Reveal/Ink/Footer/CloseButton
@onready var close_hint: Label = $JournalRoot/NotebookPivot/Reveal/Ink/Footer/CloseHint
@onready var help_panel: PanelContainer = $JournalRoot/NotebookPivot/Reveal/Ink/HelpPanel
@onready var _quest_card: JournalPhotoCard = $JournalRoot/NotebookPivot/Reveal/Ink/LeftPage/QuestPhotoRow/QuestPhoto
@onready var _animation: AnimationPlayer = $PresentationAnimation
@onready var _model_viewport: SubViewport = $JournalRoot/ModelViewport/SubViewport
@onready var _blocker: Control = $JournalRoot/TransitionBlocker
var _cards: Dictionary = {}
var _selected_item: StringName = &""
var _controller: BaseGameplayController
var _phase := PresentationState.CLOSED
var _fit_scale := Vector2.ONE
var _character_arms: Node3D
var _arms_variant := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for card: JournalPhotoCard in $JournalRoot/NotebookPivot/Reveal/Ink/RightPage/InventoryScroll/InventoryGrid.get_children():
		_cards[card.item_id] = card
		card.pressed.connect(_select_item.bind(card.item_id))
		card.focus_entered.connect(_select_item.bind(card.item_id))
	replace_button.pressed.connect(_inventory_action.bind(&"replace_battery"))
	drop_button.pressed.connect(_drop_selected)
	mount_button.pressed.connect(_mount_light)
	close_button.pressed.connect(close_journal)
	$JournalRoot/NotebookPivot/Reveal/Ink/Footer/HelpButton.pressed.connect(_toggle_help)
	$JournalRoot/NotebookPivot/Reveal/Ink/HelpPanel/Content/Dismiss.pressed.connect(_toggle_help)
	_animation.animation_finished.connect(_animation_finished)
	get_viewport().size_changed.connect(_layout_book)
	force_close()
	_layout_book()
	call_deferred("_bind_controller")

func _process(_delta: float) -> void:
	if _character_arms != null and _phase in [PresentationState.OPENING,PresentationState.CLOSING]:
		var arms_animation: AnimationPlayer = _character_arms.get_node("AnimationPlayer")
		arms_animation.seek(_animation.current_animation_position,true)
		arms_animation.advance(0)
	if not is_instance_valid(_controller):
		_bind_controller()
	if _phase == PresentationState.OPEN:
		_refresh_inventory()
	if is_journal_open():
		var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
		if player == null or player.survival.dead or player.is_sleeping_in_bunk() or get_node("/root/GameMenu").is_menu_open():
			force_close()

func _mount_light() -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	if player != null:
		_inventory_action(&"detach_light" if player.weapon_light_mounted else &"mount_light")

func _toggle_help() -> void:
	if _phase != PresentationState.OPEN: return
	help_panel.visible = not help_panel.visible
	if help_panel.visible:
		$JournalRoot/NotebookPivot/Reveal/Ink/HelpPanel/Content/Dismiss.grab_focus()
	else:
		close_button.grab_focus()

func _layout_book() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var book_size := notebook_pivot.size
	var fit := minf((viewport_size.x - screen_margin.x) / book_size.x, (viewport_size.y - screen_margin.y) / book_size.y)
	_fit_scale = Vector2.ONE * maxf(fit, 0.1)
	notebook_pivot.position = (viewport_size - book_size) * 0.5
	notebook_pivot.scale = _fit_scale

func _unhandled_input(event: InputEvent) -> void:
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
	if get_tree().get_first_node_in_group("wiring_ui") != null: return
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player == null or player.survival.dead or get_node("/root/GameMenu").is_menu_open() or player.is_sleeping_in_bunk(): return
	var position := _animation.current_animation_position if _phase == PresentationState.CLOSING else 0.0
	_bind_controller()
	_refresh_content()
	journal_root.show()
	help_panel.hide()
	_blocker.show()
	_phase = PresentationState.OPENING
	_bind_character_arms(player,position)
	player.request_journal_phase(1)
	_model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_layout_book()
	_animation.play("open")
	_animation.seek(position, true)
	_set_player_journal_visuals(true)

func close_journal() -> void:
	if not is_journal_open() or _phase == PresentationState.CLOSING: return
	if help_panel.visible:
		_toggle_help()
		return
	var position := _animation.current_animation_position if _phase == PresentationState.OPENING else _animation.get_animation("open").length
	_phase = PresentationState.CLOSING
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null: player.request_journal_phase(3)
	_blocker.show()
	_model_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_animation.play("open", -1.0, -closing_speed, true)
	_animation.seek(position, true)

func _animation_finished(_clip: StringName) -> void:
	if _phase == PresentationState.CLOSING:
		force_close()
	elif _phase == PresentationState.OPENING:
		_phase = PresentationState.OPEN
		var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
		if player != null: player.request_journal_phase(2)
		_blocker.hide()
		_model_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		close_button.grab_focus()

func force_close() -> void:
	var was_open := is_journal_open()
	_phase = PresentationState.CLOSED
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null and was_open: player.request_journal_phase(0)
	_animation.stop()
	journal_root.hide()
	help_panel.hide()
	_blocker.hide()
	_model_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_set_player_journal_visuals(false)
	if was_open and get_tree().get_first_node_in_group("local_player") != null and not get_node("/root/GameMenu").is_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_player_journal_visuals(open: bool) -> void:
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player != null:
		player.crosshair.visible = not open and not player.survival.dead
		player._refresh_equipment_visuals()

func is_journal_open() -> bool:
	return _phase != PresentationState.CLOSED

func _bind_character_arms(player: GamePlayer, time: float = 0.0) -> void:
	if _arms_variant != player.character_variant_id or not is_instance_valid(_character_arms):
		if is_instance_valid(_character_arms):
			_character_arms.hide()
			_character_arms.queue_free()
		_character_arms = player.body_animator.variant.journal_arms_scene.instantiate()
		_model_viewport.get_node("World/Hands").add_child(_character_arms)
		_arms_variant = player.character_variant_id
	var animation: AnimationPlayer = _character_arms.get_node("AnimationPlayer")
	animation.play("JournalOpen")
	animation.pause()
	animation.seek(time,true)
	animation.advance(0)

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
	if not is_instance_valid(_controller):
		day_label.text = "ПОЛЕВЫЕ ЗАПИСИ"
		objective_label.text = "Подготовка к экспедиции"
		tasks_label.text = "Задание появится на базе."
		_quest_card.hide()
		coop_status_label.text = ""
	else:
		var day := _controller.day_index
		day_label.text = "ЭКСПЕДИЦИЯ  /  ДЕНЬ %02d" % day
		_quest_card.visible = day <= 2
		if day == 1:
			objective_label.text = "Вернуть базу к жизни"
			tasks_label.text = "\n".join([_task_line(_controller.fuel_delivered, "Заправить бак"), _task_line(_controller.main_breaker_on, "Включить главный щит"), _task_line(_controller.are_all_connected_players_sleeping(), "Отдохнуть на базе")])
			_set_quest_photo("fuel_can", "Топливо для базы", "Доставлено" if _controller.fuel_delivered else "Найти в генераторной")
		elif day == 2:
			var stage := int(_controller.quest_stage)
			objective_label.text = "Ключ шифрования"
			tasks_label.text = "\n".join([_task_line(stage >= 2, "Получить задание в хабе"), _task_line(stage >= 3, "Найти ключ на уровне 1"), _task_line(stage >= 4, "Передать ключ в хабе")])
			_set_quest_photo("key", "Ключ шифрования", "У команды · ×1" if stage == 3 else "Передан на базу" if stage == 4 else "Хранилище данных · 1")
		elif day == _controller.LEVEL_TWO_DAY_INDEX:
			objective_label.text = "Обследовать уровень 2"
			tasks_label.text = _task_line(_controller.containment.get("level2", false), "Обследовать уровень 2")
			if _controller.containment.get("level2", false):
				tasks_label.text += "\n\nВернуться на базу и отдохнуть."
		elif day == _controller.CONTAINMENT_DAY_INDEX:
			var investigation: Dictionary = _controller.containment
			var defeated := 0
			for hp: Variant in investigation.get("health", [120, 90, 75]):
				if float(hp) <= 0.0:
					defeated += 1
			objective_label.text = "Зачистить уровень 3"
			tasks_label.text = "\n".join([_task_line(investigation.get("level3", false), "Обследовать уровень 3"), _task_line(defeated == 3, "Зачистить уровень"), _task_line(investigation.get("resolved", false), "Восстановить питание")])
			if investigation.get("fault", false):
				tasks_label.text += "\n\nСбой питания: выключите\nи включите главный щит."
		else:
			objective_label.text = "Задание выполнено"
			tasks_label.text = "Уровень 3 обследован. Освещение восстановлено.\nПродолжение — в следующем этапе прототипа."
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

func _set_quest_photo(id: String, title: String, note: String) -> void:
	var path := ILLUSTRATION_ROOT + id + ".png"
	_quest_card.picture.texture = load(path) if ResourceLoader.exists(path) else null
	_quest_card.caption.text = title
	_quest_card.set_note(note)

func _task_line(done: bool, text_value: String) -> String:
	return "%s  %s" % ["✓" if done else "○", text_value]

func _select_item(id: StringName) -> void:
	_selected_item = id
	for card: JournalPhotoCard in _cards.values():
		card.set_pressed_no_signal(card.item_id == id)
	_refresh_inventory()

func _refresh_inventory() -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	var data: Dictionary = player.call("get_inventory_snapshot") if player != null else {}
	var batteries: Array = data.get("spare_batteries", [])
	var has_light := bool(data.get("has_flashlight", false))
	var charge := float(data.get("battery_charge", 0.0))
	var hand := StringName(data.get("held_item", &""))
	_cards[&"flashlight"].visible = has_light
	_cards[&"battery"].visible = not batteries.is_empty()
	_cards[&"fuel_can"].visible = hand == &"fuel_can"
	_cards[&"fuse"].visible = hand == &"fuse"
	for id: StringName in WeaponController.TYPES:
		_cards[id].visible = hand == id
		var reserve := "%d патр." % int(data.get("pistol_ammo", 0)) if id == &"pistol" else "%d магаз." % data.get("rifle_magazines", []).size()
		_cards[id].set_note("" if id == &"kitchen_knife" else "%d · запас %s" % [int(data.get("weapon_rounds", 0)), reserve])
	_cards[&"flashlight"].set_note("%d%%" % roundi(charge * 100.0))
	_cards[&"battery"].set_note("×%d" % batteries.size())
	if _cards.has(_selected_item) and not _cards[_selected_item].visible:
		_cards[_selected_item].set_pressed_no_signal(false)
		_selected_item = &""
	replace_button.visible = has_light and charge <= 0.0 and not batteries.is_empty()
	drop_button.visible = _selected_item != &""
	mount_button.visible = hand in [&"pistol", &"m4a1"] and has_light
	mount_button.text = "Снять фонарь" if data.get("weapon_light_mounted", false) else "Примотать"
	mount_button.tooltip_text = "Снять в постоянный инвентарь. Скотч не возвращается." if data.get("weapon_light_mounted", false) else "Закрепить фонарик на оружии: нужен 1 скотч. Свет включается кнопкой F."
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
	if _selected_item == &"" and (int(data.get("pistol_ammo", 0)) > 0 or not data.get("rifle_magazines", []).is_empty()):
		inventory_label.text = "Запас: патроны ×%d · магазины ×%d" % [int(data.get("pistol_ammo", 0)), data.get("rifle_magazines", []).size()]
	controls_label.text = get_node("/root/SteamInput").get_controls_hint()
	if int(data.get("tape_count", 0)) > 0 or int(data.get("crowbar_uses", 0)) > 0:
		inventory_label.text += "\nСкотч: %d · Монтировка: %s" % [int(data.get("tape_count", 0)), "есть" if int(data.get("crowbar_uses", 0)) > 0 else "нет"]
	close_hint.text = "%s / %s · Закрыть журнал" % [get_node("/root/SteamInput").get_action_hint(&"journal"), get_node("/root/SteamInput").get_action_hint(&"ui_cancel")]
	if _phase == PresentationState.OPEN:
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not focused.is_visible_in_tree():
			close_button.grab_focus()

func _drop_selected() -> void:
	if _selected_item == &"battery":
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
