class_name QuestJournalUI
extends CanvasLayer

@onready var journal_root: Control = %JournalRoot
@onready var notebook_pivot: Control = %NotebookPivot
@onready var day_label: Label = %DayLabel
@onready var objective_label: Label = %ObjectiveLabel
@onready var tasks_label: Label = %TasksLabel
@onready var coop_status_label: Label = %CoopStatusLabel

var _controller: BaseGameplayController
var _animation: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	journal_root.visible = false
	call_deferred("_bind_controller")


func _process(_delta: float) -> void:
	if not is_instance_valid(_controller):
		_bind_controller()


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
	journal_root.visible = false
	notebook_pivot.modulate.a = 1.0
	notebook_pivot.scale = Vector2.ONE


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
	else:
		objective_label.text = "Открыть путь в лабораторию"
		tasks_label.text = "\n".join([
			_task_line(true, "Восстановить питание базы"),
			_task_line(true, "Пережить первую ночь"),
			_task_line(false, "Спуститься на уровень −1"),
			_task_line(false, "Осмотреть пост управления"),
		])
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
