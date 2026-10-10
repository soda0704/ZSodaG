extends CanvasLayer

const TargetCommands = preload("res://scripts/ui/developer_target_commands.gd")
const FREECAM_COMMANDS := ["/freecam", "/freecam on", "/freecam off", "/freecam speed 5", "/freecam speed reset"]
const COMMANDS := ["/help", "/clear", "/target", "/open", "/close", "/kill", "/fly", "/across", "/speed 3", "/speed reset", "/god", "/heal", "/where", "/level 0", "/level 1", "/level 2", "/level 3", "/level 4", "/day 1", "/day 2", "/day 3", "/day 4", "/ammo", "/weapon pistol", "/weapon m4a1", "/weapon kitchen_knife", "/tape", "/crowbar", "/flashlight", "/fuel full", "/fuel empty", "/item tape", "/item crowbar", "/item fuel_can", "/item flashlight", "/item battery", "/item fuse", "/item pistol", "/item m4a1", "/item kitchen_knife", "/item pistol_ammo", "/item rifle_magazine", "/spawn tail", "/spawn slasher", "/spawn smily", "/monsters reset", "/monsters kill", "/despawn", "/wiring", "/lightfault", "/testroom", "/outside"]
@onready var panel: PanelContainer = $Panel
@onready var output: RichTextLabel = $Panel/Box/Output
@onready var entry: LineEdit = $Panel/Box/Entry
@onready var target_label: Label = $Panel/Box/Target
var opened := false
var history: Array[String] = []
var history_index := 0
var previous_mouse: int
var _resizing := false
var target_path := NodePath()
var target_point := Vector3.ZERO
var _completion_options: Array[String] = []
var _completion_index := -1
var _completion_prefix := ""
var _completion_suffix := ""
var _completion_editing := false
var _completion_text := ""
var _completion_caret := -1

const DESCRIPTIONS := {"/help": "Справка", "/clear": "Очистить", "/target": "ID цели", "/open": "Открыть цель", "/close": "Закрыть цель", "/kill": "Убить цель", "/fly": "Полёт", "/across": "Сквозь стены", "/speed": "Скорость ходьбы и полёта (0.1–20 или reset)", "/god": "Бессмертие", "/heal": "Восстановить здоровье", "/where": "Координаты", "/level": "Телепорт", "/day": "День", "/ammo": "Патроны и магазины", "/weapon": "Оружие", "/tape": "Скотч", "/crowbar": "Монтировка", "/flashlight": "Фонарик", "/fuel": "Канистра", "/item": "Предмет в точке прицела", "/spawn": "Монстр в точке прицела", "/monsters": "Сюжетные монстры", "/despawn": "Удалить тестовых монстров", "/wiring": "Авария проводки", "/lightfault": "Сбой освещения", "/testroom": "Тестовая комната", "/outside": "Улица"}

const COMMAND_DETAILS := {"/level 0": "Телепортироваться: поверхность базы", "/level 1": "Телепортироваться: управление и охрана", "/level 2": "Телепортироваться: жизнеобеспечение", "/level 3": "Телепортироваться: биологические лаборатории", "/level 4": "Телепортироваться: экспедиционная шахта", "/day 1": "Переключить сюжет на день 1", "/day 2": "Переключить сюжет на день 2", "/day 3": "Переключить сюжет на день 3", "/day 4": "Переключить сюжет на день 4", "/item tape": "Создать скотч в точке прицела", "/item crowbar": "Создать монтировку в точке прицела", "/item fuel_can": "Создать канистру в точке прицела", "/item flashlight": "Создать фонарик в точке прицела", "/item battery": "Создать батарейку в точке прицела", "/item fuse": "Создать предохранитель в точке прицела", "/item pistol": "Создать пистолет в точке прицела", "/item m4a1": "Создать автомат M4A1 в точке прицела", "/item kitchen_knife": "Создать кухонный нож в точке прицела", "/item pistol_ammo": "Создать патроны для пистолета в точке прицела", "/item rifle_magazine": "Создать магазин M4A1 в точке прицела", "/weapon pistol": "Выдать пистолет", "/weapon m4a1": "Выдать автомат M4A1", "/weapon kitchen_knife": "Выдать кухонный нож", "/fuel full": "Выдать полную канистру бензина", "/fuel empty": "Выдать пустую канистру", "/spawn tail": "Создать хвостатого в точке прицела", "/spawn slasher": "Создать зомби в точке прицела", "/spawn smily": "Создать смайли в точке прицела", "/monsters reset": "Восстановить сюжетных монстров", "/monsters kill": "Убить всех сюжетных монстров"}

func _help_text() -> String:
	var lines: PackedStringArray = []
	lines.append("[url=/freecam]/freecam[/url] — Выйти из тела / вернуться; WASD, мышь, Space/Ctrl, Shift ×3")
	lines.append("[url=/freecam speed 5]/freecam speed 5[/url] — Скорость камеры (0.1–100 м/с); /freecam speed reset — сброс")
	for command in COMMANDS:
		lines.append("[url=%s]%s[/url] — %s" % [command, command, COMMAND_DETAILS.get(command, DESCRIPTIONS.get(command.split(" ")[0], ""))])
	return "\n".join(lines)

func _ready() -> void:
	entry.text_submitted.connect(_submit)
	entry.gui_input.connect(_entry_input)
	entry.text_changed.connect(func(_text):
		if not _completion_editing:
			_completion_options.clear()
	)
	output.meta_clicked.connect(func(command): insert_command(str(command)))
	$Panel/Box/Commands.meta_clicked.connect(func(command): insert_command(str(command)))
	var spawn_names := {"SpawnTail": "/spawn tail", "SpawnSlasher": "/spawn slasher", "SpawnSmily": "/spawn smily"}
	for button_name in spawn_names:
		$Panel/Box/SpawnBar.get_node(button_name).pressed.connect(func(): insert_command(spawn_names[button_name]))
	output.text = _help_text()
	$Panel/Box/Grip.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			_resizing = event.pressed
	)

func _input(event: InputEvent) -> void:
	if _resizing and opened:
		if event is InputEventMouseMotion:
			panel.offset_bottom = clampf(event.position.y, 220.0, get_viewport().get_visible_rect().size.y - 20.0)
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and not event.pressed:
			_resizing = false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_QUOTELEFT or event.keycode == KEY_QUOTELEFT or event.unicode in [96, 126, 1105, 1025]:
			set_open(not opened)
			get_viewport().set_input_as_handled()
		elif opened and event.keycode == KEY_ESCAPE:
			set_open(false)
			get_viewport().set_input_as_handled()
		elif opened and event.keycode == KEY_TAB:
			complete_command()
			get_viewport().set_input_as_handled()

func set_open(value: bool) -> void:
	_resizing = false
	opened = value
	panel.visible = value
	if value:
		capture_target()
		if entry.text.is_empty():
			entry.text = "/"
		entry.caret_column = entry.text.length()
		previous_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		entry.grab_focus()
	else:
		entry.release_focus()
		Input.mouse_mode = previous_mouse as Input.MouseMode

func _entry_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		complete_command()
		entry.accept_event()
		return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN] and not history.is_empty():
		history_index = clampi(history_index + (-1 if event.keycode == KEY_UP else 1), 0, history.size())
		entry.text = history[history_index] if history_index < history.size() else "/"
		_completion_options.clear()
		entry.caret_column = entry.text.length()
		entry.accept_event()

func _segment_bounds() -> Vector2i:
	var caret := entry.caret_column
	var left := entry.text.rfind(";", maxi(0, caret - 1)) + 1 if caret > 0 else 0
	var right := entry.text.find(";", caret)
	return Vector2i(left, entry.text.length() if right < 0 else right)

func insert_command(command: String) -> void:
	var bounds := _segment_bounds()
	var prefix := entry.text.left(bounds.x)
	var suffix := entry.text.substr(bounds.y)
	entry.text = prefix + (" " if bounds.x > 0 else "") + command + suffix
	entry.caret_column = entry.text.length() - suffix.length()
	_completion_options.clear()
	entry.grab_focus()

func complete_command() -> void:
	if entry.text != _completion_text or entry.caret_column != _completion_caret:
		_completion_options.clear()
	if _completion_options.is_empty():
		var bounds := _segment_bounds()
		var partial := entry.text.substr(bounds.x, entry.caret_column - bounds.x).strip_edges().to_lower()
		if not partial.begins_with("/"):
			partial = "/" + partial
		_completion_prefix = entry.text.left(bounds.x) + (" " if bounds.x > 0 else "")
		_completion_suffix = entry.text.substr(bounds.y)
		for command in FREECAM_COMMANDS + COMMANDS:
			if command.begins_with(partial):
				_completion_options.append(command)
		_completion_index = -1
	if _completion_options.is_empty():
		return
	_completion_index = (_completion_index + 1) % _completion_options.size()
	_completion_editing = true
	entry.text = _completion_prefix + _completion_options[_completion_index] + _completion_suffix
	entry.caret_column = entry.text.length() - _completion_suffix.length()
	_completion_editing = false
	_completion_text = entry.text
	_completion_caret = entry.caret_column

func capture_target() -> void:
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	target_path = NodePath()
	if player == null:
		target_label.text = "Цель: нет игрока"
		return
	var view: Camera3D = player.debug_free_camera if player.is_debug_free_camera_active() else player.camera
	var ray := PhysicsRayQueryParameters3D.create(view.global_position, view.global_position - view.global_basis.z * 60.0, 7, [player.get_rid()])
	ray.collide_with_areas = true
	var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
	target_point = hit.get("position", view.global_position - view.global_basis.z * 3.0)
	if not hit.is_empty():
		var target: Node = TargetCommands.resolve(hit.collider, get_tree())
		if target != null:
			target_path = target.get_path()
	target_label.text = "Цель: %s\nТочка: %s" % [str(target_path) if not target_path.is_empty() else "нет объекта", target_point]

func _submit(line: String) -> void:
	entry.text = "/"
	entry.caret_column = 1
	_completion_options.clear()
	if line.strip_edges() in ["", "/"]:
		return
	history.append(line)
	history_index = history.size()
	output.add_text("\n> " + line + "\n" + execute(line) + "\n")

func execute(line: String) -> String:
	var results: PackedStringArray = []
	for command in line.split(";", false):
		command = command.strip_edges()
		if command in ["", "/"]:
			continue
		if not command.begins_with("/"):
			command = "/" + command
		results.append(_execute_one(command))
	return "\n".join(results)

func _execute_one(line: String) -> String:
	var args := line.strip_edges().split(" ", false)
	if args.is_empty():
		return ""
	if args[0] == "/help":
		output.append_text("\n" + _help_text())
		return ""
	if args[0] == "/clear":
		output.text = _help_text()
		return ""
	# Camera inspection is local even for a co-op client: never send it to the host.
	if args[0] == "/freecam":
		return _execute_freecam(args)
	var state := get_tree().get_first_node_in_group("base_gameplay_controller")
	if not multiplayer.is_server():
		_request_command.rpc_id(1, line.left(1024), target_path, target_point)
		return "Команда отправлена серверу..."
	return _execute_authoritative(args, state, multiplayer.get_unique_id(), target_path, target_point)


func _execute_freecam(args: PackedStringArray) -> String:
	var player := get_tree().get_first_node_in_group("local_player") as GamePlayer
	if player == null:
		return "Сначала загрузите игру и войдите на карту."
	var freecam = player.debug_free_camera
	if args.size() == 3 and args[1] == "speed":
		if args[2] != "reset" and not args[2].is_valid_float():
			return "Использование: /freecam speed 5 или /freecam speed reset (0.1–100 м/с)."
		var speed := 5.0 if args[2] == "reset" else args[2].to_float()
		if not is_finite(speed) or speed < 0.1 or speed > 100.0:
			return "Скорость камеры должна быть от 0.1 до 100 м/с."
		freecam.speed = speed
		return "Скорость свободной камеры: %.2f м/с. Shift — ×3." % speed
	if args.size() > 2 or (args.size() == 2 and args[1] not in ["on", "off"]):
		return "Использование: /freecam [on|off] или /freecam speed 5."
	var enable: bool = not freecam.enabled if args.size() == 1 else args[1] == "on"
	if enable and (player.survival.dead or player.is_sleeping_in_bunk()):
		return "Свободная камера доступна живому игроку вне сна."
	if enable and player._is_journal_open():
		return "Закройте журнал или панель проводки перед включением свободной камеры."
	freecam.set_enabled(enable)
	return "Свободная камера включена. Закройте консоль: WASD + мышь, Space — вверх, Ctrl — вниз, Shift — ×3. /freecam — вернуться в тело." if enable else "Камера возвращена в тело."


@rpc("any_peer", "call_remote", "reliable")
func _request_command(line: String, selected: NodePath = NodePath(), point: Vector3 = Vector3.ZERO) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 1 or not multiplayer.get_peers().has(sender_id):
		return
	var args := line.left(1024).strip_edges().split(" ", false)
	var state := get_tree().get_first_node_in_group("base_gameplay_controller")
	var result := "Сначала загрузите игру и войдите на карту."
	if not args.is_empty():
		result = _execute_authoritative(args, state, sender_id, selected, point)
	_receive_command_result.rpc_id(sender_id, result)


@rpc("authority", "call_remote", "reliable")
func _receive_command_result(result: String) -> void:
	output.add_text("[сервер] %s\n" % result)


func _execute_authoritative(args: PackedStringArray, state: Node, peer_id: int, selected: NodePath = NodePath(), point: Vector3 = Vector3.ZERO) -> String:
	var player: GamePlayer
	if state != null:
		player = state.get_player_node(peer_id)
	else:
		var session := get_tree().get_first_node_in_group("network_gameplay_controller")
		if session != null:
			player = session.players.get_node_or_null(str(peer_id)) as GamePlayer
	if player == null:
		return "Игрок, вызвавший команду, не найден."
	if state == null and args[0] in ["/outside", "/testroom", "/level", "/day", "/wiring", "/lightfault", "/spawn", "/monsters", "/despawn"]:
		return "Эта команда доступна после посадки: база ещё не загружена."
	var encounter := get_tree().get_first_node_in_group("containment_encounter")
	if args[0] in ["/target", "/open", "/close", "/kill", "/item"]:
		return TargetCommands.execute(args, player, selected, point)
	match args[0]:
		"/speed":
			if args.size() != 2 or (args[1] != "reset" and not args[1].is_valid_float()):
				return "Использование: /speed 3 — скорость ×3; /speed reset — обычная скорость. Диапазон: 0.1–20."
			var multiplier := 1.0 if args[1] == "reset" else args[1].to_float()
			if not is_finite(multiplier) or multiplier < 0.1 or multiplier > 20.0:
				return "Множитель скорости должен быть от 0.1 до 20."
			player.debug_speed_multiplier = multiplier
			player._publish_inventory()
			return "Скорость ходьбы и полёта: ×%.2f. Shift ускоряет полёт; /speed reset — сброс." % multiplier
		"/outside":
			player.teleport_authoritative(Vector3(-48, 1.0, 10), -PI / 2)
			return "Снежная территория. /level 0 — вернуться на базу."
		"/testroom":
			var level := state.get_parent()
			if not level.has_method("toggle_developer_test_room") or not level.toggle_developer_test_room(player):
				return "Тестовая комната недоступна."
			return "Телепорт выполнен. Повторите /testroom, чтобы вернуться."
		"/flashlight":
			if not player.pickup_world_item_authoritative(&"flashlight", {"battery_charge": 1.0}):
				player.spawn_dropped_item_authoritative(&"flashlight", {"battery_charge": 1.0})
				return "Заряженный фонарик выдан рядом с игроком."
			return "Заряженный фонарик добавлен в инвентарь."
		"/fuel":
			if args.size() != 2 or args[1] not in ["full", "empty"]:
				return "Использование: /fuel full — 20 л; /fuel empty — 0 л."
			var liters := 20.0 if args[1] == "full" else 0.0
			if not player.pickup_world_item_authoritative(&"fuel_can", {"fuel_liters": liters}):
				return "Сейчас нельзя получить канистру."
			return "Канистра в руках: %.0f / 20 л. Фонарик сохранён в инвентаре или на выброшенном оружии." % liters
		"/tape", "/crowbar":
			var kind := StringName(args[0].trim_prefix("/"))
			return "Выдано: " + str(kind) if player.pickup_world_item_authoritative(kind, {"uses": 3}) else "Не удалось выдать предмет."
		"/wiring":
			var snapshot: Dictionary = state.get_snapshot()
			var order := [0, 1, 2, 3]
			order.shuffle()
			snapshot.maintenance["wires_required"] = true
			snapshot.maintenance["wire_order"] = order
			snapshot.maintenance["wire_links"] = []
			snapshot.maintenance["alarm"] = true
			snapshot.main_breaker_on = false
			snapshot.phase = BaseGameplayController.BasePhase.RESTORING_POWER
			state._broadcast_snapshot(snapshot)
			return "Авария проводки. Отремонтируйте провода в генераторной, затем включите щит."
		"/fly", "/across":
			if args[0] == "/fly":
				player.debug_fly = not player.debug_fly
				player.debug_across = false
			else:
				player.debug_across = not player.debug_across
				player.debug_fly = player.debug_across
			player.velocity = Vector3.ZERO
			player.survival.reset_fall()
			player._publish_inventory()
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
			var level_point := Vector3(-16.0 + index * 3.5, -18.0 * index + 0.2, 0)
			var target: Vector3 = state.get_parent().get_day_start_transform(0).origin if index == 0 else state.get_parent().to_global(level_point)
			player.teleport_authoritative(target, PI / 2)
			return "Телепорт: уровень %d. Доступ лифта и задания не изменены." % index
		"/day":
			if args.size() != 2 or not args[1].is_valid_int() or int(args[1]) not in range(1, 5):
				return "Использование: /day 1..4"
			var snapshot: Dictionary = state.get_snapshot()
			snapshot.day_index = int(args[1])
			snapshot.fuel_delivered = true
			snapshot.fuel_liters = 60.0
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
				for index in 3:
					encounter.damage_monster(index, 10000)
			return "Готово. Состояние монстров сохранено."
		"/spawn":
			if encounter == null or args.size() < 2:
				return "Использование: /spawn tail|slasher|smily [число]"
			var aliases := {"tail": 0, "хвостатый": 0, "slasher": 1, "слэшер": 1, "smily": 2, "четвероногий": 2}
			if not aliases.has(args[1]):
				return "Типы: tail, slasher, smily"
			var count := 1
			if args.size() >= 3:
				if not args[2].is_valid_int() or int(args[2]) <= 0:
					return "Количество должно быть целым числом больше нуля."
				count = clampi(int(args[2]), 1, 1000)
			var forward: Vector3 = -player.head.global_basis.z
			forward.y = 0
			forward = forward.normalized()
			if not point.is_finite() or player.global_position.distance_to(point) > 65:
				return "Точка спавна слишком далеко. Снова наведитесь и откройте консоль."
			encounter.debug_spawn(int(aliases[args[1]]), count, point + Vector3.UP * 0.15, forward, true)
			return "Создано: %d. Большие значения могут сильно снизить FPS." % count
		"/despawn":
			if encounter == null:
				return "Контроллер монстров не найден."
			return "Удалено тестовых монстров: %d" % encounter.debug_clear_spawned()
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
