class_name NorthernLabMainMenu
extends Control

var shell: NorthernMenuShell
var background_video: VideoStreamPlayer
var continue_game_button: Button
var single_player_button: Button
var settings_button: Button
var exit_button: Button
var skin_option: OptionButton
var status_label: Label
var selector: NorthernCharacterSelection
var current_view := "home"
var _transition_in_progress := false
var _character_flow := "solo"
var _last_focus: Control
var _expedition_scope := "solo"
var _history_points: Array[Dictionary] = []

func _ready() -> void:
	BaseGameplayController.save_scope = "solo"
	GameMenu.force_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shell = $Shell
	background_video = $BackgroundVideo
	shell.video = background_video
	background_video.bus = &"Music"
	background_video.finished.connect(background_video.play)
	if not background_video.is_playing():
		background_video.play()
	SteamNetwork.state_changed.connect(_on_steam_state_changed)
	_show_home()
	shell.appear()

func _page(template: String) -> VBoxContainer:
	if is_instance_valid(selector):
		selector.queue_free()
		selector = null
		skin_option = null
	var page: VBoxContainer = load(template).instantiate()
	shell.replace(page)
	if current_view == "home":
		page.offset_left = 27
	shell.content.clip_contents = true
	shell.clear(shell.header)
	shell.clear(shell.footer)
	shell.footer.add_child(NorthernMenuStyle.label("NORTHERNLAB · ВЕРСИЯ %s" % str(ProjectSettings.get_setting("application/config/version", "1.00")), 18, NorthernMenuStyle.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.footer.add_child(spacer)
	var steam := "STEAM ONLINE · " + SteamNetwork.local_user_name if SteamNetwork.steam_available else "STEAM OFFLINE · ОДИНОЧНАЯ ИГРА ДОСТУПНА"
	shell.footer.add_child(NorthernMenuStyle.label(steam, 18, NorthernMenuStyle.MUTED))
	if current_view != "home":
		shell.footer.add_child(NorthernMenuStyle.button("ESC  Назад", back, 15))
	status_label = page.get_node_or_null("Status")
	return page

func _show_home() -> void:
	BaseGameplayController.save_scope = "solo"
	current_view = "home"
	var page := _page("res://scenes/ui/menu_home.tscn")
	continue_game_button = page.get_node("Navigation/Continue")
	single_player_button = page.get_node("Navigation/NewGame")
	settings_button = page.get_node("Navigation/Settings")
	exit_button = page.get_node("Navigation/Exit")
	continue_game_button.disabled = not ExpeditionSaveStore.has_any_save("solo")
	continue_game_button.pressed.connect(func(): _navigate(_show_checkpoint))
	single_player_button.pressed.connect(_on_single_player_pressed)
	page.get_node("Navigation/Coop").pressed.connect(func(): _navigate(_show_coop))
	settings_button.pressed.connect(func(): _navigate(func(): GameMenu.open_settings()))
	page.get_node("Navigation/Feedback").pressed.connect(func(): GameMenu.open_feedback())
	exit_button.pressed.connect(_on_exit_pressed)
	(single_player_button if continue_game_button.disabled else continue_game_button).grab_focus()

func _navigate(callback: Callable) -> void:
	if _transition_in_progress or shell.busy or GameMenu.is_menu_open():
		return
	shell.transition(callback)

func _on_single_player_pressed() -> void:
	_navigate(show_expeditions.bind("solo"))

func show_character(flow: String = "solo") -> void:
	current_view = "character"
	_character_flow = flow
	_page("res://scenes/ui/menu_character.tscn")
	selector = preload("res://scenes/ui/character_selection.tscn").instantiate()
	selector.name = "SkinCard"
	shell.add_child(selector)
	shell.move_child(selector, shell.content.get_index() + 1)
	NorthernMenuStyle.fill(selector)
	skin_option = selector.option
	shell.footer.get_child(shell.footer.get_child_count() - 1).queue_free()
	shell.footer.add_child(NorthernMenuStyle.button("Начать экспедицию" if flow == "solo" else "Выбрать", _confirm_character, 23))
	shell.footer.add_child(NorthernMenuStyle.button("ESC  Назад", back, 21))
	skin_option.grab_focus()

func _confirm_character() -> void:
	if _character_flow == "coop":
		_navigate(_show_coop)
	else:
		_start_solo(false)

func _show_checkpoint() -> void:
	show_expeditions("solo")

func show_expeditions(scope: String = "solo") -> void:
	_expedition_scope = scope
	BaseGameplayController.save_scope = scope
	current_view = "checkpoint"
	var page := _page("res://scenes/ui/menu_checkpoint.tscn")
	page.get_node("Mode").text = "Кооператив · сохранения на этом компьютере хоста" if scope == "coop" else "Одиночная игра"
	var slots: OptionButton = page.get_node("Slots")
	var chosen := ExpeditionSaveStore.slot(scope)
	for index in ExpeditionSaveStore.SLOT_COUNT:
		ExpeditionSaveStore.select(scope, index + 1)
		var item := BaseGameplayController.get_saved_progress_summary()
		slots.add_item("%d · %s · %s" % [index + 1, ExpeditionSaveStore.slot_name(scope), "пусто" if item.is_empty() else "день %d" % int(item.day_index)])
	ExpeditionSaveStore.select(scope, chosen)
	slots.select(chosen - 1)
	slots.item_selected.connect(func(index: int):
		ExpeditionSaveStore.select(scope, index + 1)
		show_expeditions(scope))
	var body := page.get_node("Scroll/Body")
	var name_input: LineEdit = body.get_node("Naming/Name")
	name_input.text = ExpeditionSaveStore.slot_name(scope)
	body.get_node("Naming/Rename").pressed.connect(func():
		if ExpeditionSaveStore.rename_slot(scope, name_input.text):
			show_expeditions(scope)
		else:
			show_status("Не удалось сохранить имя. Введите от 1 до 48 символов."))
	var summary := BaseGameplayController.get_saved_progress_summary()
	body.get_node("Day").text = "ПУСТОЙ СЛОТ" if summary.is_empty() else "ДЕНЬ %d" % int(summary.day_index)
	body.get_node("Power").text = "" if summary.is_empty() else "%s · %s" % ["Питание включено" if bool(summary.main_breaker_on) else "Питание отключено", _save_time(summary)]
	body.get_node("Continue").disabled = summary.is_empty() or (scope == "coop" and not SteamNetwork.steam_available)
	body.get_node("Continue").pressed.connect(_continue_expedition)
	body.get_node("New").disabled = scope == "coop" and not SteamNetwork.steam_available
	body.get_node("New").pressed.connect(_new_expedition)
	body.get_node("Delete").disabled = not BaseGameplayController.has_progress_save_file()
	body.get_node("Delete").pressed.connect(func(): GameMenu.confirm("Очистить слот?", "Текущий прогресс и контрольные точки этой экспедиции будут удалены. Другие слоты сохранятся.", [{"label": "Очистить", "action": _delete_save}]))
	_history_points = ExpeditionSaveStore.history(scope)
	var history_option: OptionButton = body.get_node("History")
	for point in _history_points:
		var point_label := str(point.get("label", ""))
		if point_label.is_empty():
			point_label = "День %d · %s" % [int(point.day_index), "после сна" if point.kind == "sleep" else "перед событием" if point.kind == "event" else "начало"]
		history_option.add_item("%s · %s" % [point_label, _save_time(point)])
	if _history_points.is_empty():
		history_option.add_item("Предыдущих контрольных точек пока нет")
	history_option.disabled = _history_points.is_empty()
	body.get_node("Rollback").disabled = _history_points.is_empty()
	body.get_node("Rollback").pressed.connect(func():
		var point := _history_points[history_option.selected]
		GameMenu.confirm("Откатить экспедицию?", "Текущий прогресс будет заменён точкой дня %d. Более поздние точки станут недоступны. Откат применяется ко всей команде." % int(point.day_index), [{"label": "Откатить", "action": _rollback.bind(str(point.name))}]))
	if bool(summary.get("recovered", false)):
		show_status("Повреждён последний сейв. Доступна проверенная резервная копия.")

func _save_time(summary: Dictionary) -> String:
	var stamp := int(summary.get("saved_at", 0))
	var local_stamp := stamp + int(Time.get_time_zone_from_system().bias) * 60
	return Time.get_datetime_string_from_unix_time(local_stamp).replace("T", " ") if stamp > 0 else "старое сохранение"

func _continue_expedition() -> void:
	if _expedition_scope == "coop":
		GameMenu._begin_host_session(true)
	else:
		_start_solo(true)

func _new_expedition() -> void:
	var action := func():
		if _expedition_scope == "coop":
			GameMenu._begin_host_session(false)
		else:
			show_character("solo")
	if BaseGameplayController.has_progress_save_file():
		GameMenu.confirm("Заменить экспедицию?", "Будут заменены только текущий слот и его контрольные точки.", [{"label": "Начать новую", "action": action}])
	else:
		action.call()

func _rollback(name: String) -> void:
	if ExpeditionSaveStore.rollback(_expedition_scope, name):
		show_expeditions(_expedition_scope)
	else:
		show_status("Не удалось загрузить контрольную точку. Текущий прогресс сохранён.")

func _delete_save() -> void:
	if BaseGameplayController.delete_progress_save():
		show_expeditions(_expedition_scope)
	else:
		show_status("Не удалось удалить сохранение.")

func _show_coop() -> void:
	current_view = "coop"
	var page := _page("res://scenes/ui/menu_coop.tscn")
	var host: Button = page.get_node("Host")
	var join: Button = page.get_node("Join")
	host.disabled = not SteamNetwork.steam_available
	join.disabled = not SteamNetwork.steam_available
	host.pressed.connect(func(): _navigate(show_expeditions.bind("coop")))
	join.pressed.connect(func(): _navigate(func(): GameMenu.open_menu(GlobalGameMenu.MenuView.JOIN)))
	page.get_node("Character").pressed.connect(func(): _navigate(show_character.bind("coop")))
	page.get_node("OfflineHint").visible = not SteamNetwork.steam_available

func _start_solo(resume_checkpoint: bool) -> void:
	if _transition_in_progress or shell.busy:
		return
	_transition_in_progress = true
	set_menu_enabled(false)
	await shell.transition(func(): GameMenu.start_standalone_flow(resume_checkpoint))
	if is_inside_tree():
		_transition_in_progress = false
		set_menu_enabled(true)

func _on_exit_pressed() -> void:
	if shell.busy or _transition_in_progress or GameMenu.is_menu_open():
		return
	shell.busy = true
	await create_tween().tween_property(exit_button, "modulate:a", 0.55, 0.17).set_custom_interpolator(NorthernMenuStyle.ease).finished
	shell.busy = false
	exit_button.modulate.a = 1
	GameMenu.confirm("Выход из игры", "Завершить игру?", [{"label": "Выйти", "action": func(): get_tree().quit()}])

func set_menu_enabled(value: bool) -> void:
	_set_controls_enabled(shell.content, value)
	_set_controls_enabled(shell.footer, value)
	if is_instance_valid(selector):
		_set_controls_enabled(selector, value)

func _set_controls_enabled(node: Node, enabled: bool) -> void:
	if node is BaseButton:
		node.disabled = not enabled
	for child in node.get_children():
		_set_controls_enabled(child, enabled)
	if enabled and current_view == "home":
		continue_game_button.disabled = not ExpeditionSaveStore.has_any_save("solo")

func set_overlay_visible(value: bool) -> void:
	if shell == null:
		return
	if value:
		_last_focus = get_viewport().gui_get_focus_owner()
	shell.content.visible = not value or GameMenu.dialog != null
	if is_instance_valid(selector):
		selector.visible = shell.content.visible
	if not value and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus()

func show_status(message: String) -> void:
	if status_label != null:
		status_label.text = message

func back() -> void:
	if shell.busy or _transition_in_progress:
		return
	_navigate(_show_coop if (current_view == "character" and _character_flow == "coop") or (current_view == "checkpoint" and _expedition_scope == "coop") else _show_home)

func _unhandled_input(event: InputEvent) -> void:
	if GameMenu.is_menu_open() or event.is_echo():
		return
	if current_view != "home" and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		back()
		get_viewport().set_input_as_handled()

func _on_steam_state_changed(_state: int, _message: String) -> void:
	if current_view == "home":
		_show_home()
	elif current_view == "coop":
		_show_coop()
