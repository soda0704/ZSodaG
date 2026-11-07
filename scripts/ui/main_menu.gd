class_name NorthernLabMainMenu
extends Control

var shell: NorthernMenuShell
var background_video: VideoStreamPlayer
var continue_game_button: Button
var single_player_button: Button
var settings_button: Button
var exit_button: Button
var status_label: Label
var selector: NorthernCharacterSelection
var current_view := "home"
var _transition_in_progress := false
var _character_flow := "solo"
var _character_resume := false
var _last_focus: Control
var _checkpoint_scope := "solo"

func _ready() -> void:
	NorthernCharacterSelection.prepare_previews()
	ExpeditionSaveStore.select_existing("solo")
	BaseGameplayController.save_scope = "solo"
	GameMenu.force_close_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shell = $Shell
	background_video = $BackgroundVideo
	resized.connect(_fit_background_video)
	_fit_background_video.call_deferred()
	shell.video = background_video
	background_video.bus = &"Music"
	background_video.finished.connect(background_video.play)
	if not background_video.is_playing():
		background_video.play()
	SteamNetwork.state_changed.connect(_on_steam_state_changed)
	$FeedbackCorner.pressed.connect(func(): GameMenu.open_feedback())
	_show_home()
	shell.appear()

func _fit_background_video() -> void:
	var frame_size := background_video.get_video_texture().get_size()
	if frame_size.x <= 0.0 or frame_size.y <= 0.0: return
	var factor := maxf(size.x / frame_size.x, size.y / frame_size.y)
	background_video.set_anchors_preset(Control.PRESET_TOP_LEFT)
	background_video.size = frame_size * factor
	background_video.position = (size - background_video.size) * 0.5

func _page(template: String) -> VBoxContainer:
	if is_instance_valid(selector):
		selector.queue_free()
		selector = null
	shell.presentation = null
	shell.top_rail.show()
	shell.bottom_rail.show()
	shell.header.show()
	shell.footer.show()
	shell.top_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.bottom_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$FeedbackCorner.visible = current_view == "home"
	var page: VBoxContainer = load(template).instantiate()
	shell.replace(page)
	if current_view == "home": page.offset_left = 11
	shell.content.clip_contents = true
	shell.clear(shell.header)
	shell.clear(shell.footer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.footer.add_child(spacer)
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
	exit_button.pressed.connect(_on_exit_pressed)

func _navigate(callback: Callable) -> void:
	if _transition_in_progress or GameMenu.is_menu_open():
		return
	if shell.busy: shell.cancel_transition()
	shell.transition(callback)

func _on_single_player_pressed() -> void:
	_navigate(show_character.bind("solo"))

func show_character(flow: String = "solo", resume_checkpoint: bool = false) -> void:
	current_view = "character"
	_character_flow = flow
	_character_resume = resume_checkpoint
	_page("res://scenes/ui/menu_character.tscn")
	selector = preload("res://scenes/ui/character_selection.tscn").instantiate()
	selector.name = "SkinCard"
	selector.activation_allowed = func(): return not _transition_in_progress and not shell.busy and not GameMenu.is_menu_open()
	selector.character_selected.connect(_on_character_selected)
	shell.add_child(selector)
	shell.presentation = selector
	shell.move_child(selector, shell.content.get_index() + 1)
	NorthernMenuStyle.fill(selector)
	shell.header.hide()
	shell.clear(shell.footer)
	var back_button := NorthernMenuStyle.button("ESC  Назад", back, 18)
	back_button.name = "CharacterBack"
	shell.footer.add_child(back_button)
	shell.top_rail.mouse_filter = Control.MOUSE_FILTER_STOP
	shell.bottom_rail.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_character_selected(_variant_id: int) -> void:
	_confirm_character()

func _confirm_character() -> void:
	if _character_flow == "coop":
		_navigate(_show_coop)
	elif _character_flow == "host":
		_transition_in_progress = true
		set_menu_enabled(false)
		await shell.transition(func(): GameMenu._begin_host_session(_character_resume, true))
	else:
		_start_solo(false)

func _show_checkpoint(scope: String = "solo") -> void:
	_checkpoint_scope = scope
	BaseGameplayController.save_scope = scope
	current_view = "checkpoint"
	var page := _page("res://scenes/ui/menu_checkpoint.tscn")
	var current := ExpeditionSaveStore.read(scope)
	var summary := ExpeditionSaveStore.summary(scope, current)
	var points := ExpeditionSaveStore.checkpoints(scope)
	var latest_name := str(current.get("path", "")).get_file()
	var used := not current.is_empty() and int(current.config.get_value("base", "manual_save_day", 0)) == int(summary.get("day_index", 1))
	page.call("configure", scope, summary, points, latest_name, used)
	page.call("animate_in")
	page.connect("continue_requested", func(name: String): _choose_checkpoint(scope, name))
	if scope == "coop":
		page.get_node("%Delete").text = "НОВАЯ ЭКСПЕДИЦИЯ"
		page.get_node("%Delete").pressed.connect(GameMenu._confirm_new_coop_game)
	else:
		page.get_node("%Delete").pressed.connect(func(): GameMenu.confirm("Удалить экспедицию?", "Все три записи этой экспедиции будут удалены.", [{"label": "Удалить", "action": _delete_save}]))
	page.get_node("%Continue").grab_focus()

func _resume_expedition(scope: String) -> void:
	if scope == "coop": GameMenu._begin_host_session(true)
	else: _start_solo(true)

func _choose_checkpoint(scope: String, name: String) -> void:
	var current := ExpeditionSaveStore.read(scope)
	if str(current.get("path", "")).get_file() == name:
		_resume_expedition(scope)
		return
	GameMenu.confirm("Вернуться к этому утру?", "Более поздний прогресс и ручная запись будут удалены. Использованная ручная запись этого дня повторно не выдаётся.", [{"label": "Загрузить утро", "action": _load_checkpoint.bind(scope, name)}])

func _load_checkpoint(scope: String, name: String) -> void:
	if not ExpeditionSaveStore.rollback(scope, name):
		show_status("Не удалось загрузить запись. Текущий прогресс сохранён.")
		return
	_resume_expedition(scope)

func _delete_save() -> void:
	if BaseGameplayController.delete_progress_save():
		if _checkpoint_scope == "coop": _show_coop()
		else: _show_home()
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
	GameMenu.confirm("Выход из игры", "Завершить игру?", [{"label": "Выйти", "action": GameMenu.quit_with_save}])

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
	$FeedbackCorner.visible = not value and current_view == "home"
	var was_visible := shell.content.visible
	if value:
		_last_focus = get_viewport().gui_get_focus_owner()
	shell.content.visible = not value or GameMenu.dialog != null
	shell.header.visible = shell.content.visible
	shell.footer.visible = shell.content.visible
	if is_instance_valid(selector):
		selector.visible = shell.content.visible
	if not value and is_instance_valid(_last_focus) and _last_focus.is_visible_in_tree():
		_last_focus.grab_focus()
	if not value and not was_visible:
		shell.appear()

func show_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
		status_label.visible = not message.is_empty()

func back() -> void:
	if _transition_in_progress:
		return
	_navigate(_show_coop if (current_view == "character" and _character_flow in ["coop", "host"]) or (current_view == "checkpoint" and _checkpoint_scope == "coop") else _show_home)

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
