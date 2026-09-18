class_name QuestJournalUI
extends CanvasLayer

const PHOTO_CARD := preload("res://scripts/ui/journal_photo_card.gd")
const PHOTO_ROOT := "res://assets/ui/journal_photos/"
const BOOK_SIZE := Vector2(1400, 840)
const INK := Color("352e25")

var journal_root: Control
var notebook_pivot: Control
var day_label: Label
var objective_label: Label
var tasks_label: Label
var coop_status_label: Label
var inventory_label: Label
var controls_label: Label
var replace_button: Button
var mount_button: Button
var drop_button: Button
var close_button: Button
var close_hint: Label
var help_panel: PanelContainer
var _quest_card: JournalPhotoCard
var _cards: Dictionary = {}
var _selected_item: StringName = &""
var _controller: BaseGameplayController
var _animation: Tween
var _fit_scale := Vector2.ONE
var _handwritten: SystemFont

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	journal_root.visible = false
	get_viewport().size_changed.connect(_layout_book)
	_layout_book()
	call_deferred("_bind_controller")

func _process(_delta: float) -> void:
	if not is_instance_valid(_controller):
		_bind_controller()
	if is_journal_open():
		_refresh_inventory()

func _build_interface() -> void:
	_handwritten = SystemFont.new()
	_handwritten.font_names = PackedStringArray(["Segoe Print", "Segoe Script", "Comic Sans MS"])
	journal_root = Control.new()
	add_child(journal_root)
	journal_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	journal_root.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.025, 0.02, 0.015, 0.64)
	notebook_pivot = Control.new()
	journal_root.add_child(notebook_pivot)
	notebook_pivot.size = BOOK_SIZE
	notebook_pivot.pivot_offset = BOOK_SIZE * 0.5
	_panel(notebook_pivot, Rect2(Vector2.ZERO, BOOK_SIZE), Color("392c23"), 12)
	_panel(notebook_pivot, Rect2(18, 18, 676, 756), Color("dfd3b7"), 4)
	_panel(notebook_pivot, Rect2(706, 18, 676, 756), Color("e9ddc3"), 4)
	var spine := ColorRect.new()
	notebook_pivot.add_child(spine)
	spine.position = Vector2(694, 18)
	spine.size = Vector2(12, 756)
	spine.color = Color("887557")
	spine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := _column(Rect2(62, 48, 585, 690))
	day_label = _label(left, "ПОЛЕВЫЕ ЗАПИСИ", 18, Color("857354"))
	objective_label = _label(left, "", 31, INK, true)
	objective_label.custom_minimum_size.y = 94
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tasks_label = _label(left, "", 24, INK, true)
	tasks_label.custom_minimum_size.y = 190
	tasks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tasks_label.add_theme_constant_override("line_spacing", 12)
	var photo_row := HBoxContainer.new()
	photo_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(photo_row)
	_quest_card = _make_photo(photo_row, &"key", "Ключ шифрования", -0.022)
	_quest_card.focus_mode = Control.FOCUS_NONE
	_quest_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coop_status_label = _label(left, "", 18, Color("857354"))
	coop_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var right := _column(Rect2(748, 48, 586, 704))
	_label(right, "СНАРЯЖЕНИЕ", 18, Color("857354"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.custom_minimum_size = Vector2(0, 538)
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 18)
	right.add_child(grid)
	for spec in [[&"flashlight", "Фонарик", -0.014], [&"battery", "Батарейки", 0.017], [&"fuel_can", "Канистра", 0.012], [&"fuse", "Предохранитель", -0.017]]:
		var card := _make_photo(grid, spec[0], spec[1], spec[2])
		card.toggle_mode = true
		card.pressed.connect(_select_item.bind(spec[0]))
		card.focus_entered.connect(_select_item.bind(spec[0]))
		_cards[spec[0]] = card
	for id: StringName in WeaponController.TYPES:
		var card := _make_photo(grid, id, WeaponController.TITLES[id], -0.012)
		card.toggle_mode = true
		card.pressed.connect(_select_item.bind(id))
		card.focus_entered.connect(_select_item.bind(id))
		_cards[id] = card
	inventory_label = _label(right, "", 19, Color("79684f"))
	inventory_label.custom_minimum_size.y = 44
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 16)
	right.add_child(actions)
	replace_button = _button(actions, "Заменить батарейку")
	replace_button.pressed.connect(_inventory_action.bind(&"replace_battery"))
	drop_button = _button(actions, "Выбросить")
	drop_button.pressed.connect(_drop_selected)
	mount_button = _button(actions, "Примотать фонарь")
	mount_button.pressed.connect(func():
		var player := get_tree().get_first_node_in_group("local_player")
		if player != null:
			_inventory_action(&"detach_light" if player.weapon_light_mounted else &"mount_light")
	)
	var footer := HBoxContainer.new()
	notebook_pivot.add_child(footer)
	footer.position = Vector2(48, 784)
	footer.size = Vector2(1304, 44)
	footer.add_theme_constant_override("separation", 24)
	close_hint = _label(footer, "", 18, Color("c6b99f"))
	close_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button = _button(footer, "Закрыть")
	close_button.pressed.connect(close_journal)
	help_panel = _panel(notebook_pivot, Rect2(240, 220, 920, 380), Color("f0e5cc"), 5)
	var help_content := VBoxContainer.new()
	help_panel.add_child(help_content)
	_label(help_content, "УПРАВЛЕНИЕ", 24, INK, true)
	controls_label = _label(help_content, "", 22, INK)
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_button(help_content, "Понятно").pressed.connect(_toggle_help)
	help_panel.hide()

func _toggle_help() -> void:
	help_panel.visible = not help_panel.visible
	if help_panel.visible:
		(help_panel.get_child(0).get_child(-1) as Button).grab_focus()
	else:
		close_button.grab_focus()

func _column(rect: Rect2) -> VBoxContainer:
	var column := VBoxContainer.new()
	notebook_pivot.add_child(column)
	column.position = rect.position
	column.size = rect.size
	column.add_theme_constant_override("separation", 16)
	return column

func _panel(parent: Node, rect: Rect2, color: Color, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(parent: Node, text_value: String, font_size: int, color: Color, handwritten: bool = false) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if handwritten:
		label.add_theme_font_override("font", _handwritten)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Node, text_value: String) -> Button:
	var button := Button.new()
	parent.add_child(button)
	button.text = text_value
	button.custom_minimum_size = Vector2(120, 42)
	button.add_theme_font_size_override("font_size", 20)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("61523d") if state == "normal" else Color("8b6845")
		style.set_corner_radius_all(3)
		style.content_margin_left = 16
		style.content_margin_right = 16
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.set_border_width_all(2)
			style.border_color = Color("c9a86b")
		button.add_theme_stylebox_override(state, style)
	return button

func _make_photo(parent: Node, id: StringName, title: String, angle: float) -> JournalPhotoCard:
	var card := PHOTO_CARD.new()
	parent.add_child(card)
	card.setup(id, title, PHOTO_ROOT + str(id) + ".png", _handwritten)
	card.rotation = angle
	return card

func _layout_book() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var fit := minf(1.0, minf((viewport_size.x - 48) / BOOK_SIZE.x, (viewport_size.y - 48) / BOOK_SIZE.y))
	_fit_scale = Vector2.ONE * maxf(fit, 0.1)
	notebook_pivot.position = (viewport_size - BOOK_SIZE) * 0.5
	notebook_pivot.scale = _fit_scale

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("journal"):
		if is_journal_open():
			close_journal()
		else:
			open_journal()
		get_viewport().set_input_as_handled()
	elif is_journal_open() and event.is_action_pressed("ui_cancel"):
		close_journal()
		get_viewport().set_input_as_handled()

func open_journal() -> void:
	if get_tree().get_first_node_in_group("wiring_ui") != null:
		return
	var local_player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if local_player != null and local_player.survival.dead:
		return
	var player := get_tree().get_first_node_in_group("local_player")
	if player == null or GameMenu.is_menu_open() or bool(player.call("is_sleeping_in_bunk")):
		return
	_bind_controller()
	_refresh_content()
	journal_root.show()
	help_panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	close_button.grab_focus()
	_layout_book()
	if _animation != null and _animation.is_valid():
		_animation.kill()
	notebook_pivot.modulate.a = 0.0
	notebook_pivot.scale = _fit_scale * 0.96
	_animation = create_tween().set_parallel(true)
	_animation.tween_property(notebook_pivot, "modulate:a", 1.0, 0.16)
	_animation.tween_property(notebook_pivot, "scale", _fit_scale, 0.2)

func close_journal() -> void:
	if help_panel.visible:
		_toggle_help()
		return
	force_close()

func force_close() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	var was_open := journal_root.visible
	journal_root.hide()
	help_panel.hide()
	if was_open and get_tree().get_first_node_in_group("local_player") != null and not GameMenu.is_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func is_journal_open() -> bool:
	return journal_root.visible

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
		elif day == 3:
			var investigation: Dictionary = _controller.containment
			var defeated := 0
			for hp: Variant in investigation.get("health", [120, 90, 75]):
				if float(hp) <= 0.0:
					defeated += 1
			objective_label.text = "Обследовать уровень 3"
			tasks_label.text = "\n".join([_task_line(investigation.get("level2", false), "Обследовать уровень 2"), _task_line(investigation.get("level3", false), "Изучить уровень 3"), _task_line(defeated == 3, "Устранить угрозу · %d/3" % defeated), _task_line(investigation.get("resolved", false), "Восстановить освещение")])
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
			tasks_label.text = "Проверить топливо в генераторной.\nЗаново включить главный щит."
	_refresh_inventory()

func _set_quest_photo(id: String, title: String, note: String) -> void:
	var path := PHOTO_ROOT + id + ".png"
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
	controls_label.text = SteamInput.get_controls_hint()
	if int(data.get("tape_count", 0)) > 0 or int(data.get("crowbar_uses", 0)) > 0:
		inventory_label.text += "\nСкотч: %d · Монтировка: %d/3" % [int(data.get("tape_count", 0)), int(data.get("crowbar_uses", 0))]
	close_hint.text = ""
	if is_journal_open():
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
	var player := get_tree().get_first_node_in_group("local_player")
	if player != null:
		player.call("request_inventory_action", action)
	_refresh_inventory()
