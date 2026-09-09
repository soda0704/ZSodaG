class_name QuestJournalUI
extends CanvasLayer

@onready var journal_root: Control = %JournalRoot
@onready var notebook_pivot: Control = %NotebookPivot
@onready var day_label: Label = %DayLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var tasks_label: Label = %TasksLabel
@onready var coop_status_label: Label = %CoopStatusLabel
@onready var inventory_label: Label = %InventoryLabel
@onready var controls_label: Label = %ControlsLabel
@onready var replace_button: Button = %ReplaceBatteryButton
@onready var drop_battery_button: Button = %DropBatteryButton
@onready var drop_flashlight_button: Button = %DropFlashlightButton
@onready var close_button: Button = %CloseButton
@onready var close_hint: Label = %CloseHint

var _controller: BaseGameplayController
var _animation: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	journal_root.visible = false
	replace_button.pressed.connect(_inventory_action.bind(&"replace_battery"))
	drop_battery_button.pressed.connect(_inventory_action.bind(&"drop_battery"))
	drop_flashlight_button.pressed.connect(_inventory_action.bind(&"drop_flashlight"))
	close_button.pressed.connect(close_journal)
	call_deferred("_bind_controller")


func _process(_delta: float) -> void:
	if not is_instance_valid(_controller):
		_bind_controller()
	if is_journal_open():
		_refresh_inventory()


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
	if get_tree().get_first_node_in_group("local_player") == null:
		return
	var game_menu := get_node_or_null("/root/GameMenu")
	if game_menu != null and bool(game_menu.call("is_menu_open")):
		return
	var local_player := get_tree().get_first_node_in_group("local_player")
	if (
		local_player.has_method("is_sleeping_in_bunk")
		and bool(local_player.call("is_sleeping_in_bunk"))
	):
		return
	_bind_controller()
	_refresh_content()
	journal_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	close_button.grab_focus()
	if _animation != null and _animation.is_valid():
		_animation.kill()
	notebook_pivot.modulate.a = 0.0
	notebook_pivot.scale = Vector2(0.88, 0.88)
	_animation = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.set_parallel(true)
	_animation.tween_property(notebook_pivot, "modulate:a", 1.0, 0.16)
	_animation.tween_property(
		notebook_pivot,
		"scale",
		Vector2.ONE,
		0.22
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close_journal() -> void:
	if not journal_root.visible:
		return
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_animation = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_animation.set_parallel(true)
	_animation.tween_property(notebook_pivot, "modulate:a", 0.0, 0.12)
	_animation.tween_property(notebook_pivot, "scale", Vector2(0.94, 0.94), 0.12)
	_animation.chain().tween_callback(_hide_journal)


func force_close() -> void:
	if _animation != null and _animation.is_valid():
		_animation.kill()
	_hide_journal()


func is_journal_open() -> bool:
	return journal_root.visible


func _hide_journal() -> void:
	var was_open := journal_root.visible
	journal_root.visible = false
	notebook_pivot.modulate.a = 1.0
	notebook_pivot.scale = Vector2.ONE
	if was_open and get_tree().get_first_node_in_group("local_player") != null and not GameMenu.is_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _bind_controller() -> void:
	var next_controller := get_tree().get_first_node_in_group(
		"base_gameplay_controller"
	) as BaseGameplayController
	if next_controller == _controller:
		return
	_controller = next_controller
	if (
		_controller != null
		and not _controller.snapshot_changed.is_connected(_on_snapshot_changed)
	):
		_controller.snapshot_changed.connect(_on_snapshot_changed)
	_refresh_content()


func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	_refresh_content()


func _refresh_content() -> void:
	_refresh_inventory()
	if _controller == null:
		day_label.text = "ПОЛЕВОЙ ЖУРНАЛ"
		objective_label.text = "Ожидание общей задачи"
		tasks_label.text = "Связь с базой ещё не установлена."
		coop_status_label.text = ""
		return
	var day := _controller.day_index
	day_label.text = "ОБЩАЯ ЗАДАЧА  ·  ДЕНЬ %02d" % day
	if day <= 1:
		objective_label.text = "Вернуть базу к жизни"
		tasks_label.text = "\n".join([
			_task_line(_controller.fuel_delivered, "Заправить топливный бак"),
			_task_line(_controller.main_breaker_on, "Включить главный щит"),
			_task_line(
				_controller.are_all_connected_players_sleeping(),
				"Лечь спать после восстановления питания"
			),
		])
	elif day == 2:
		var stage := int(_controller.quest_stage)
		objective_label.text = "Доставить ключ шифрования"
		tasks_label.text = "\n".join([
			_task_line(stage >= 2, "Получить задание у терминала в центральном хабе"),
			_task_line(stage >= 3, "Забрать ключ в хранилище данных на уровне −1"),
			_task_line(stage >= 4, "Вернуться к терминалу хаба и передать ключ"),
		])
	else:
		objective_label.text = "Экспедиция: прототип завершён"
		tasks_label.text = "Ключ шифрования доставлен.\nСодержимое дней 3–5 пока в разработке."
	var player_count := _controller.get_connected_player_peer_ids().size()
	coop_status_label.text = (
		"Общий прогресс  ·  готовы ко сну %d/%d  ·  легли %d/%d"
		% [
			_controller.end_day_ready_peer_ids.size(),
			player_count,
			_controller.sleeping_peer_ids.size(),
			player_count,
		]
	)


func _task_line(is_complete: bool, task_text: String) -> String:
	return "%s  %s" % ["✓" if is_complete else "○", task_text]


func _refresh_inventory() -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	var data: Dictionary = player.call("get_inventory_snapshot") if player != null else {}
	var quest_text := "нет"
	if is_instance_valid(_controller) and int(_controller.quest_stage) == 3:
		quest_text = "Ключ шифрования ×1 — общий, сдаётся в хабе"
	var has_light := bool(data.get("has_flashlight", false))
	var charge := float(data.get("battery_charge", 0.0))
	var batteries: Array = data.get("spare_batteries", [])
	var hand: String = str(data.get("held_item", ""))
	var hand_name: String = {"": "свободны", "flashlight": "фонарик", "fuel_can": "канистра", "fuse": "предохранитель"}.get(hand, hand)
	var battery_charges: Array[String] = []
	for cell: Variant in batteries:
		battery_charges.append("%d%%" % roundi(float(cell) * 100.0))
	inventory_label.text = "КВЕСТ-ПРЕДМЕТЫ КОМАНДЫ\n%s\nСНАРЯЖЕНИЕ · Фонарик: %s · Батарейки: %d/%d\nРуки: %s%s" % [
		quest_text, "%d%%" % roundi(charge * 100.0) if has_light else "нет",
		batteries.size(), 20, hand_name,
		" · Заряд запасных: " + ", ".join(battery_charges) if not batteries.is_empty() else ""]
	replace_button.disabled = not has_light or batteries.is_empty() or float(batteries.max()) <= charge + 0.001
	drop_battery_button.disabled = batteries.is_empty()
	drop_flashlight_button.disabled = not has_light
	controls_label.text = SteamInput.get_controls_hint()
	close_hint.text = "%s / %s — закрыть · Замена расходует одну запасную батарейку" % [SteamInput.get_action_hint(&"journal"), SteamInput.get_action_hint(&"ui_cancel")]
	if is_journal_open() and get_viewport().gui_get_focus_owner() == null:
		close_button.grab_focus()


func _inventory_action(action: StringName) -> void:
	var player := get_tree().get_first_node_in_group("local_player")
	if player != null:
		player.call("request_inventory_action", action)
	_refresh_inventory()
