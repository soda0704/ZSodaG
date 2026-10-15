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

func _ready() -> void:
	ExpeditionSaveStore.select_existing("solo")
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
	continue_game_button.disabled = BaseGameplayController.get_saved_progress_summary().is_empty()
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
	_navigate(func():
		if BaseGameplayController.has_progress_save_file():
			GameMenu.confirm("Новая экспедиция", "После начала новой игры одиночное сохранение будет заменено.", [{"label": "Выбрать персонажа", "action": show_character.bind("solo")}])
		else:
			show_character("solo")
	)

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
	current_view = "checkpoint"
	var page := _page("res://scenes/ui/menu_checkpoint.tscn")
	var summary := BaseGameplayController.get_saved_progress_summary()
	page.get_node("Day").text = "ДЕНЬ %d" % int(summary.get("day_index", 1))
	page.get_node("Power").text = "Питание включено" if bool(summary.get("main_breaker_on", false)) else "Питание отключено"
	page.get_node("Continue").pressed.connect(_start_solo.bind(true))
	page.get_node("Delete").pressed.connect(func(): GameMenu.confirm("Удалить сохранение?", "Одиночный прогресс будет удалён.", [{"label": "Удалить", "action": _delete_save}]))

func _delete_save() -> void:
	if BaseGameplayController.delete_progress_save():
		_show_home()
	else:
		show_status("Не удалось удалить сохранение.")

func _show_coop() -> void:
	current_view = "coop"
	var page := _page("res://scenes/ui/menu_coop.tscn")
	var host: Button = page.get_node("Host")
	var join: Button = page.get_node("Join")
	host.disabled = not SteamNetwork.steam_available
	join.disabled = not SteamNetwork.steam_available
	host.pressed.connect(func(): _navigate(func(): GameMenu.start_host_flow()))
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
		continue_game_button.disabled = BaseGameplayController.get_saved_progress_summary().is_empty()

func set_overlay_visible(value: bool) -> void:
	if shell == null:
		return
	if value:
		_last_focus = get_viewport().gui_get_focus_owner()
	shell.content.visible = not value or GameMenu.dialog != null
	shell.header.visible = shell.content.visible
	shell.footer.visible = shell.content.visible
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
	_navigate(_show_coop if current_view == "character" and _character_flow == "coop" else _show_home)

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
