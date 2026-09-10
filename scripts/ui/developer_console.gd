extends CanvasLayer

const HELP := "Консоль разработчика • ~ / ё — открыть/закрыть • Esc — закрыть\n/help — справка   /clear — очистить   ↑/↓ — история\n/fly — полёт с коллизиями   /across — полёт сквозь стены\nВ полёте: WASD, мышь; Space вверх, Ctrl вниз, Shift быстрее\n/god — бессмертие   /heal — здоровье и очистка радиации\n/level 0..4 — телепорт к входу на уровень   /where — координаты\n/day 1..4 — сменить день (меняет сохраняемый прогресс!)\n/ammo — патроны и магазины   /weapon pistol|m4a1|kitchen_knife\n/monsters reset — вернуть трёх монстров, сбросить сбой\n/monsters kill — убить всех   /lightfault — проверить сбой света\nКоманды изменения мира доступны только хосту/в одиночной игре."
var panel: PanelContainer
var output: RichTextLabel
var entry: LineEdit
var opened := false
var history: Array[String] = []
var history_index := 0
var previous_mouse: int

func _ready() -> void:
	layer = 150
	panel = PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 430
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.045, 0.97)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	panel.add_child(box)
	output = RichTextLabel.new()
	output.custom_minimum_size.y = 340
	output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	output.add_theme_font_size_override("normal_font_size", 18)
	output.scroll_following = true
	box.add_child(output)
	entry = LineEdit.new()
	entry.placeholder_text = "/help — команды (Enter — выполнить)"
	entry.add_theme_font_size_override("font_size", 20)
	box.add_child(entry)
	entry.text_submitted.connect(_submit)
	entry.gui_input.connect(_entry_input)
	output.text = HELP + "\n"
	panel.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_QUOTELEFT or event.keycode == KEY_QUOTELEFT or event.unicode in [96, 126, 1105, 1025]:
			set_open(not opened)
			get_viewport().set_input_as_handled()
		elif opened and event.keycode == KEY_ESCAPE:
			set_open(false)
			get_viewport().set_input_as_handled()

func set_open(value: bool) -> void:
	opened = value
	panel.visible = value
	if value:
		previous_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		entry.grab_focus()
	else:
		entry.release_focus()
		Input.mouse_mode = previous_mouse as Input.MouseMode

func _entry_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN] and not history.is_empty():
		history_index = clampi(history_index + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		entry.text = history[history_index] if history_index < history.size() else ""
		entry.caret_column = entry.text.length()
		entry.accept_event()

func _submit(line: String) -> void:
	entry.clear()
	if line.strip_edges().is_empty():
		return
	history.append(line)
	history_index = history.size()
	output.append_text("\n> " + line + "\n" + execute(line) + "\n")

func execute(line: String) -> String:
	var args := line.strip_edges().to_lower().split(" ", false)
	if args.is_empty():
		return ""
	if args[0] == "/help":
		return HELP
	if args[0] == "/clear":
		output.clear()
		return ""
	var state := get_tree().get_first_node_in_group("base_gameplay_controller")
	if state == null:
		return "Сначала загрузите игру и войдите на карту."
	if not multiplayer.is_server():
		return "Команды изменения игры доступны только хосту."
	var player = state.get_player_node(multiplayer.get_unique_id())
	if player == null:
		return "Локальный игрок не найден."
	var encounter := get_tree().get_first_node_in_group("containment_encounter")
	match args[0]:
		"/fly", "/across":
			if args[0] == "/fly":
				player.debug_fly = not player.debug_fly
				player.debug_across = false
			else:
				player.debug_across = not player.debug_across
				player.debug_fly = player.debug_across
			player.velocity = Vector3.ZERO
			player.survival.reset_fall()
			return "Полёт: %s • сквозь стены: %s" % [player.debug_fly, player.debug_across]
		"/god":
			player.survival.debug_invincible = not player.survival.debug_invincible
			return "Бессмертие: %s" % player.survival.debug_invincible
		"/heal":
			if player.survival.dead:
				player.survival._respawn()
			player.survival.health = 100
			player.survival.radiation = 0
			return "Здоровье восстановлено."
		"/where":
			return str(player.global_position)
		"/level":
			if args.size() != 2 or not args[1].is_valid_int() or int(args[1]) not in range(5):
				return "Использование: /level 0..4"
			var index := int(args[1])
			var point := Vector3(-16.0 + index * 3.5, -18.0 * index + 0.2, 0)
			var target: Vector3 = state.get_parent().get_day_start_transform(0).origin if index == 0 else state.get_parent().to_global(point)
			player.teleport_authoritative(target, PI / 2)
			return "Телепорт: уровень %d. Доступ лифта и задания не изменены." % index
		"/day":
			if args.size() != 2 or not args[1].is_valid_int() or int(args[1]) not in range(1, 5):
				return "Использование: /day 1..4"
			var snapshot: Dictionary = state.get_snapshot()
			snapshot.day_index = int(args[1])
			snapshot.fuel_delivered = true
			snapshot.main_breaker_on = true
			snapshot.quest_stage = 4 if int(args[1]) >= 3 else 1
			snapshot.sleeping_peer_ids = []
			snapshot.end_day_ready_peer_ids = []
			state._broadcast_snapshot(snapshot)
			if int(args[1]) < 3 and encounter != null:
				encounter.debug_reset()
			return "День изменён и сохранён."
		"/ammo":
			player.pickup_world_item_authoritative(&"pistol_ammo", {"amount": 120})
			for index in 5:
				player.pickup_world_item_authoritative(&"rifle_magazine", {"rounds": 30})
			return "Добавлены патроны и магазины."
		"/weapon":
			if args.size() != 2 or args[1] not in ["pistol", "m4a1", "kitchen_knife"]:
				return "Использование: /weapon pistol|m4a1|kitchen_knife"
			return "Оружие выдано." if player.pickup_world_item_authoritative(StringName(args[1]), {}) else "Не удалось взять оружие."
		"/monsters":
			if encounter == null or args.size() != 2 or args[1] not in ["reset", "kill"]:
				return "Использование: /monsters reset|kill"
			if args[1] == "reset":
				encounter.debug_reset()
			else:
				if state.day_index < 3:
					return "Сначала /day 3"
				for index in 3:
					encounter.damage_monster(index, 10000)
			return "Готово. Состояние монстров сохранено."
		"/lightfault":
			if encounter == null or state.day_index < 3:
				return "Сначала /day 3"
			var data: Dictionary = state.containment.duplicate(true)
			data.fault = true
			data.reset_armed = false
			data.resolved = false
			encounter._commit(data)
			return "Сбой включён. Выключите и включите главный щит."
	return "Неизвестная команда. /help — справка."
