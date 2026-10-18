class_name GlobalGameMenu
extends CanvasLayer
## Stable gameplay API; native views share one settings and network service.

enum MenuView { MAIN, SESSION, JOIN, SETTINGS, FEEDBACK }
@export_range(0.0, 1.0, 0.01) var lobby_background_opacity := 0.864
@export_range(0.0, 1.0, 0.01) var escape_background_opacity := 0.576
const MECHANICS_TEST_ROOM_SCENE := "res://scenes/levels/base_session.tscn"
const SETTINGS_DIRECTORY := "NorthernLab"
const SETTINGS_FILE := "launcher_settings.json"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const WINDOW_MODES := ["fullscreen", "windowed", "maximized"]
const AUDIO_OPTIONS := ["EffectsVolume", "WeaponsVolume", "VehiclesVolume", "MachineryVolume", "AmbienceVolume", "BreathingVolume", "RoomReverb"]

@onready var audio_mix: AudioMixController = $AudioMix
var menu_root: Control
var shell: NorthernMenuShell
var main_panel: NorthernEscapeMenu
var session_panel: NorthernLobbyMenu
var join_panel: VBoxContainer
var settings_panel: NorthernSettingsMenu
var tester_feedback: NorthernTesterFeedback
var _feedback_origin: MenuView = MenuView.MAIN
var _feedback_return_to_scene := false
var _feedback_capture_busy := false
var _feedback_epoch := 0
var feedback_label: Label
var session_status_label: Label
var lobby_id_value: LineEdit
var lobby_id_input: LineEdit
var ready_button: Button
var start_game_button: Button
var dialog: NorthernMenuDialog
var _current_view: MenuView = MenuView.MAIN
var _settings_origin: MenuView = MenuView.MAIN
var _settings_return_to_main_scene := false
var _transition_in_progress := false
var _settings_data: Dictionary = {}
var _mouse_sensitivity_multiplier := 1.0
var _applied_display: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	ensure_music_bus()
	_settings_data = load_settings_data()
	apply_settings_data()
	NorthernMenuStyle.install_cursor()
	menu_root = $MenuRoot
	shell = $MenuRoot/Shell
	main_panel = $MenuRoot/Shell/Content/ESC_MENU
	NorthernMenuStyle.fill(main_panel)
	main_panel.configure(self)
	tester_feedback = $MenuRoot/Shell/Content/TesterFeedback
	tester_feedback.back_requested.connect(close_feedback)
	session_panel = $MenuRoot/Shell/Content/LOBBY_MENU
	NorthernMenuStyle.fill(session_panel)
	session_panel.anchor_right = 0
	session_panel.offset_right = 1350
	session_panel.offset_top = 21
	session_panel.configure(self)
	session_status_label = session_panel.session_status_label
	lobby_id_value = session_panel.lobby_id_value
	ready_button = session_panel.ready_button
	start_game_button = session_panel.start_button
	join_panel = $MenuRoot/Shell/Content/JoinPage
	NorthernMenuStyle.fill(join_panel)
	lobby_id_input = $MenuRoot/Shell/Content/JoinPage/LobbyInput
	lobby_id_input.text_submitted.connect(connect_to_lobby_from_text)
	join_panel.get_node("Connect").pressed.connect(func(): connect_to_lobby_from_text(lobby_id_input.text))
	feedback_label = NorthernMenuStyle.label("", 20, NorthernMenuStyle.MUTED)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu_root.add_child(feedback_label)
	feedback_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	feedback_label.offset_left = 90
	feedback_label.offset_top = -152
	feedback_label.offset_right = -90
	feedback_label.offset_bottom = -90
	connect_network_signals()
	show_view(MenuView.MAIN)
	menu_root.hide()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_with_save()

func quit_with_save(save_before_exit: bool = true) -> void:
	var base := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if save_before_exit and base != null and multiplayer.is_server() and base.progress_persistence_enabled:
		if not base.save_progress_authoritative():
			confirm("Не удалось сохранить", "Последняя запись сохранена, но новые изменения не записались. Остаться в игре или выйти без них?", [{"label": "Выйти без сохранения", "action": quit_with_save.bind(false)}])
			return
	get_tree().quit()

func connect_network_signals() -> void:
	SteamNetwork.state_changed.connect(_on_network_state_changed)
	SteamNetwork.lobby_entered.connect(_on_lobby_entered)
	SteamNetwork.lobby_members_changed.connect(_on_lobby_members_changed)
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	SteamNetwork.invite_join_requested.connect(_on_invite_join_requested)
	CoopLobby.ready_state_changed.connect(_on_ready_state_changed)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)

func is_rebinding_controls() -> bool:
	return is_instance_valid(settings_panel) and settings_panel.is_visible_in_tree() and not settings_panel.waiting.is_empty()

func is_capturing_feedback_screenshot() -> bool:
	return _feedback_capture_busy

func _input(event: InputEvent) -> void:
	_handle_feedback_shortcut(event)

func _handle_feedback_shortcut(event: InputEvent) -> bool:
	if not event.is_action_pressed("tester_feedback") or event.is_echo(): return false
	if _transition_in_progress or dialog != null or shell.busy or _feedback_capture_busy: return false
	if menu_root.visible and _current_view in [MenuView.SETTINGS, MenuView.FEEDBACK]: return false
	# A rebound letter must remain usable in console/text fields. Function
	# keys still open feedback, and journal focus cannot swallow the shortcut.
	var focused := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and (focused is TextEdit or focused is LineEdit):
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if code < KEY_F1 or code > KEY_F35: return false
	open_feedback()
	get_viewport().set_input_as_handled()
	return true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or _transition_in_progress or dialog != null or shell.busy or _feedback_capture_busy:
		return
	if event.is_action_pressed("tester_feedback"):
		_handle_feedback_shortcut(event)
		return
	if not event.is_action_pressed("pause") and not (menu_root.visible and event.is_action_pressed("ui_cancel")):
		return
	var terminal := get_tree().get_first_node_in_group("terminal_ui")
	if terminal != null and not menu_root.visible:
		terminal.close_terminal()
		get_viewport().set_input_as_handled()
		return
	var journal := get_node_or_null("/root/QuestJournal")
	if journal != null and journal.is_journal_open():
		journal.close_journal()
	elif menu_root.visible:
		if _current_view == MenuView.FEEDBACK:
			tester_feedback.request_back()
		elif _current_view == MenuView.SETTINGS:
			settings_panel.request_back()
		else:
			close_menu()
	elif not _in_main_scene():
		var world := get_tree().get_first_node_in_group("network_gameplay_controller")
		var waiting: bool = world != null and world.has_method("is_waiting_for_arrival") and world.is_waiting_for_arrival()
		open_menu(MenuView.SESSION if waiting else MenuView.MAIN)
	else:
		return
	get_viewport().set_input_as_handled()

func _in_main_scene() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.is_in_group("main_menu")

func _sync_main_overlay() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("set_overlay_visible"):
		scene.set_overlay_visible(menu_root.visible)

func open_menu(view: MenuView = MenuView.MAIN) -> void:
	var journal := get_node_or_null("/root/QuestJournal")
	if journal != null:
		journal.force_close()
	menu_root.show()
	shell.show()
	show_view(view)
	shell.appear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_main_overlay()

func show_view(view: MenuView) -> void:
	_current_view = view
	main_panel.visible = view == MenuView.MAIN
	session_panel.visible = view == MenuView.SESSION
	join_panel.visible = view == MenuView.JOIN
	if is_instance_valid(settings_panel):
		settings_panel.visible = view == MenuView.SETTINGS
	tester_feedback.visible = view == MenuView.FEEDBACK
	feedback_label.text = ""
	shell.rails(view != MenuView.MAIN)
	var lobby_context := view == MenuView.SESSION or (view == MenuView.SETTINGS and _settings_origin == MenuView.SESSION and not _settings_return_to_main_scene)
	var escape_context := not _in_main_scene() and (view == MenuView.MAIN or view == MenuView.SETTINGS or view == MenuView.FEEDBACK)
	shell.shade.color.a = lobby_background_opacity if lobby_context else (escape_background_opacity if escape_context else 0.18)
	shell.content.offset_right = -72 if view == MenuView.FEEDBACK else 0
	shell.top_rail.color.a = 1.0 if _in_main_scene() else 0.0
	shell.bottom_rail.color.a = 1.0 if _in_main_scene() else 0.0
	if view != MenuView.SETTINGS:
		shell.clear(shell.header)
		shell.clear(shell.footer)
		if view != MenuView.MAIN and view != MenuView.FEEDBACK:
			var world := get_tree().get_first_node_in_group("network_gameplay_controller")
			var solo: bool = world != null and world.has_method("is_solo_arrival") and world.is_solo_arrival()
			var expedition := "ОДИНОЧНАЯ ЭКСПЕДИЦИЯ" if solo else "КООПЕРАТИВНАЯ ЭКСПЕДИЦИЯ"
			shell.header.add_child(NorthernMenuStyle.label("NORTHERNLAB  /  " + expedition, 18, NorthernMenuStyle.MUTED))
			shell.footer.add_child(NorthernMenuStyle.label("CH-47 · ПОДГОТОВКА К ВЫСАДКЕ", 18, NorthernMenuStyle.MUTED))
			var spacer := Control.new()
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			shell.footer.add_child(spacer)
			if view == MenuView.SESSION:
				shell.footer.add_child(NorthernMenuStyle.button("Настройки", open_settings, 21))
			shell.footer.add_child(NorthernMenuStyle.button("ESC  Назад", close_menu, 21))
	match view:
		MenuView.MAIN:
			main_panel.refresh()
			main_panel.continue_button.grab_focus()
		MenuView.SESSION:
			refresh_session_ui()
			ready_button.grab_focus()
		MenuView.JOIN:
			lobby_id_input.grab_focus()
		MenuView.SETTINGS:
			pass
		MenuView.FEEDBACK:
			tester_feedback.title_input.grab_focus()

func open_feedback() -> void:
	if shell.busy or _transition_in_progress or dialog != null or _feedback_capture_busy:
		return
	if menu_root.visible and _current_view == MenuView.FEEDBACK: return
	_feedback_origin = _current_view if menu_root.visible else MenuView.MAIN
	_feedback_return_to_scene = not menu_root.visible
	var journal := get_node_or_null("/root/QuestJournal")
	var console := get_node_or_null("/root/DeveloperConsole")
	if console != null and console.opened: console.set_open(false)
	if not tester_feedback.has_draft():
		# A saved report starts a fresh form. Unsaved drafts survive Escape/reopening.
		tester_feedback.free()
		tester_feedback = preload("res://scenes/ui/tester_feedback.tscn").instantiate()
		shell.content.add_child(tester_feedback)
		tester_feedback.back_requested.connect(close_feedback)
		_feedback_capture_busy = true
		var epoch := _feedback_epoch
		var context := TesterFeedbackStore.collect_context(get_tree())
		var image := await _capture_feedback_image()
		_feedback_capture_busy = false
		if epoch != _feedback_epoch: return
		tester_feedback.begin(context, image)
	# Capture the actual journal before handing its input/view to the form.
	if journal != null: journal.force_close()
	menu_root.show()
	shell.show()
	show_view(MenuView.FEEDBACK)
	shell.appear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_main_overlay()

func _capture_feedback_image() -> Image:
	if DisplayServer.get_name() == "headless": return null
	var epoch := _feedback_epoch
	var was_visible := menu_root.visible
	menu_root.hide()
	# Keep gameplay input blocked while the menu is absent from the render.
	await RenderingServer.frame_post_draw
	if epoch != _feedback_epoch: return null
	var image := get_viewport().get_texture().get_image()
	menu_root.visible = was_visible
	return TesterFeedbackStore.prepare_image(image)

func capture_feedback_screenshot() -> void:
	if _feedback_capture_busy or _current_view != MenuView.FEEDBACK: return
	_feedback_capture_busy = true
	tester_feedback.set_busy(true)
	var epoch := _feedback_epoch
	var context := TesterFeedbackStore.collect_context(get_tree())
	var image := await _capture_feedback_image()
	_feedback_capture_busy = false
	if epoch != _feedback_epoch: return
	if image != null:
		tester_feedback.begin(context, image)
		tester_feedback.set_screenshot(image, true)
	else:
		tester_feedback.status.text = "Не удалось снять игру. Можно выбрать изображение с компьютера."
	tester_feedback.set_busy(false)

func close_feedback() -> void:
	if _feedback_capture_busy or tester_feedback._busy: return
	if _feedback_return_to_scene:
		force_close_menu()
	else:
		show_view(_feedback_origin)

func open_settings() -> void:
	if shell.busy or _transition_in_progress:
		return
	_settings_origin = _current_view
	_settings_return_to_main_scene = _in_main_scene() and not menu_root.visible
	var display := func():
		if is_instance_valid(settings_panel):
			settings_panel.free()
		settings_panel = NorthernSettingsMenu.new()
		shell.content.add_child(settings_panel)
		NorthernMenuStyle.fill(settings_panel)
		settings_panel.anchor_right = 0
		settings_panel.offset_right = minf(1020, shell.content.size.x * 0.75)
		settings_panel.configure(self, shell)
		settings_panel.back_requested.connect(close_settings)
		menu_root.show()
		show_view(MenuView.SETTINGS)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_sync_main_overlay()
	if menu_root.visible:
		shell.transition(display)
	else:
		display.call()
		shell.appear()

func close_settings() -> void:
	shell.transition(func():
		if _settings_return_to_main_scene:
			force_close_menu()
		else:
			show_view(_settings_origin)
	)

func close_menu() -> void:
	if _transition_in_progress or shell.busy:
		return
	if is_lobby_gate_active():
		feedback_label.text = "Дождитесь завершения подключения к Steam-лобби."
		return
	if _in_main_scene():
		force_close_menu()
		return
	shell.transition(force_close_menu)

func force_close_menu() -> void:
	_feedback_epoch += 1
	_feedback_capture_busy = false
	if is_instance_valid(tester_feedback):
		if not tester_feedback._sending: tester_feedback.set_busy(false)
		tester_feedback.file_dialog.hide()
		tester_feedback.get_node("ReportDialog").hide()
	shell.cancel_transition()
	if is_instance_valid(dialog):
		dialog.queue_free()
		dialog = null
	menu_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if get_tree().get_first_node_in_group("local_player") != null else Input.MOUSE_MODE_VISIBLE
	_sync_main_overlay()

func is_menu_open() -> bool:
	return _feedback_capture_busy or (menu_root != null and menu_root.visible)

func is_lobby_gate_active() -> bool:
	return SteamNetwork.state in [SteamNetworkService.SessionState.CREATING_LOBBY, SteamNetworkService.SessionState.JOINING_LOBBY, SteamNetworkService.SessionState.CONNECTING]

func confirm(title: String, message: String, choices: Array) -> void:
	if is_instance_valid(dialog):
		return
	var was_open := menu_root.visible
	var previous_mouse_mode := Input.mouse_mode
	menu_root.show()
	if not was_open:
		shell.hide()
		feedback_label.hide()
	dialog = preload("res://scenes/ui/menu_dialog.tscn").instantiate()
	menu_root.add_child(dialog)
	var typed_choices: Array[Dictionary] = []
	for choice in choices:
		typed_choices.append(choice)
	dialog.closed.connect(func():
		dialog = null
		shell.show()
		feedback_label.show()
		if not was_open:
			menu_root.hide()
			Input.mouse_mode = previous_mouse_mode
		_sync_main_overlay()
	)
	dialog.present(title, message, typed_choices)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_main_overlay()

func start_host_flow() -> void:
	if _transition_in_progress or not SteamNetwork.steam_available:
		return
	ExpeditionSaveStore.select_existing("coop")
	var previous_scope := BaseGameplayController.save_scope
	BaseGameplayController.save_scope = "coop"
	var summary := BaseGameplayController.get_saved_progress_summary()
	var has_save := BaseGameplayController.has_progress_save_file()
	BaseGameplayController.save_scope = previous_scope
	if not has_save:
		_begin_host_session(false)
		return
	confirm("Кооперативная экспедиция", "Продолжить сохранённую экспедицию или начать новую? Одиночный прогресс хранится отдельно.", [
		{"label": "Продолжить", "disabled": summary.is_empty(), "action": _begin_host_session.bind(true)},
		{"label": "Новая экспедиция", "action": _confirm_new_coop_game},
	])

func _confirm_new_coop_game() -> void:
	confirm("Новая кооп-игра", "Заменить сохранение кооперативной экспедиции?", [{"label": "Начать заново", "action": _begin_host_session.bind(false)}])

func _begin_host_session(resume_checkpoint: bool) -> void:
	if _transition_in_progress:
		return
	BaseGameplayController.save_scope = "coop"
	if not resume_checkpoint and not BaseGameplayController.delete_progress_save():
		confirm("Не удалось начать игру", "Не удалось очистить кооперативное сохранение.", [])
		return
	_transition_in_progress = true
	var scene_ready := await ensure_network_scene()
	_transition_in_progress = false
	open_menu(MenuView.SESSION)
	if not scene_ready:
		session_status_label.text = "Не удалось открыть базу."
		return
	get_tree().current_scene.set("resume_base_on_start", resume_checkpoint)
	session_status_label.text = "Создаём Steam-лобби…"
	if not SteamNetwork.create_friends_lobby():
		session_status_label.text = "Steam не смог начать создание лобби."

func connect_to_lobby_from_text(value: String) -> void:
	var clean := value.strip_edges()
	if not clean.is_valid_int() or clean.length() < 16 or clean.length() > 19 or int(clean) <= 0:
		feedback_label.text = "Проверьте ID лобби: требуется числовой идентификатор Steam."
		lobby_id_input.grab_focus()
		return
	start_join_flow(int(clean))

func start_join_flow(target_lobby_id: int) -> void:
	if _transition_in_progress or not SteamNetwork.steam_available:
		return
	_transition_in_progress = true
	var scene_ready := await ensure_network_scene()
	_transition_in_progress = false
	open_menu(MenuView.SESSION)
	if not scene_ready:
		session_status_label.text = "Не удалось открыть базу."
		return
	if not SteamNetwork.join_lobby(target_lobby_id):
		session_status_label.text = "Не удалось начать подключение к лобби."

func _on_copy_lobby_id_pressed() -> void:
	if SteamNetwork.lobby_id > 0:
		DisplayServer.clipboard_set(str(SteamNetwork.lobby_id))
		feedback_label.text = "ID лобби скопирован."

func _on_invite_pressed() -> void:
	if not SteamNetwork.is_overlay_enabled():
		feedback_label.text = "Приглашения доступны при запуске через Steam. Можно отправить другу ID лобби."
	elif not SteamNetwork.open_invite_overlay():
		feedback_label.text = "Не удалось открыть приглашение Steam."

func _on_ready_pressed() -> void:
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	if world != null and world.has_method("is_solo_arrival") and world.is_solo_arrival():
		world.begin_solo_arrival()
		return
	if CoopLobby.game_has_started:
		close_menu()
		return
	if not CoopLobby.set_local_ready(not CoopLobby.is_local_ready()):
		feedback_label.text = "Сетевая сессия ещё не готова."
	refresh_ready_ui()

func _on_start_game_pressed() -> void:
	if not CoopLobby.start_game():
		feedback_label.text = "Все подключённые игроки должны подтвердить готовность."
	refresh_ready_ui()

func _on_leave_lobby_pressed() -> void:
	confirm("Покинуть экспедицию?", "Текущая сессия будет закрыта.", [{"label": "Покинуть", "action": return_to_main_menu.bind("Вы покинули экспедицию.")}])

func _on_return_to_main_menu_pressed() -> void:
	confirm("Вернуться в главное меню?", "Прогресс будет сохранён по правилам экспедиции. Текущая сессия будет закрыта.", [{"label": "Главное меню", "action": return_to_main_menu.bind("Возврат из экспедиции.")}])

func refresh_network_ui() -> void:
	main_panel.refresh()
	refresh_session_ui()

func refresh_session_ui() -> void:
	session_panel.refresh()

func refresh_ready_ui() -> void:
	session_panel.refresh()

func _on_network_state_changed(state: SteamNetworkService.SessionState, message: String) -> void:
	if session_status_label != null:
		session_status_label.text = get_localized_state_message(state, message)
	refresh_network_ui()

func _on_lobby_entered(_lobby_id: int, _as_host: bool) -> void:
	refresh_session_ui()

func _on_lobby_members_changed(_members: Array[Dictionary]) -> void:
	refresh_session_ui()

func _on_session_ready(_as_host: bool) -> void:
	refresh_session_ui()
	force_close_menu()

func _on_session_closed(reason: String) -> void:
	_transition_in_progress = true
	call_deferred("_finish_return_to_main_menu", reason)

func _on_invite_join_requested(requested_lobby_id: int) -> void:
	lobby_id_input.text = str(requested_lobby_id)
	start_join_flow(requested_lobby_id)

func _on_ready_state_changed(_ready_states: Dictionary) -> void:
	refresh_ready_ui()

func _on_gameplay_started() -> void:
	force_close_menu()


func get_settings_path() -> String:
	if ProjectSettings.has_setting("northern_lab/testing/settings_path"):
		return str(ProjectSettings.get_setting("northern_lab/testing/settings_path"))
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	if local_app_data.is_empty():
		return "user://%s" % SETTINGS_FILE
	return local_app_data.path_join(SETTINGS_DIRECTORY).path_join(SETTINGS_FILE)

func get_character_variant_id() -> int:
	return clampi(int(_settings_data.get("CharacterVariant", 0)), 0, 1)

func set_character_variant_id(variant_id: int) -> void:
	if variant_id not in [0, 1]:
		return
	_settings_data["CharacterVariant"] = variant_id
	save_settings_data()

func load_settings_data() -> Dictionary:
	var defaults := default_settings_data()
	defaults["GraphicsPresetRevision"] = preload("res://scripts/ui/graphics_quality.gd").PRESET_REVISION
	var path := get_settings_path()
	if not FileAccess.file_exists(path):
		return defaults
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return defaults
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key in (parsed as Dictionary):
			defaults[key] = (parsed as Dictionary)[key]
	var quality_script = preload("res://scripts/ui/graphics_quality.gd")
	if defaults.get("Graphics", {}) is Dictionary:
		defaults["Graphics"] = quality_script.migrate_saved(defaults.get("Graphics", {}), int((parsed as Dictionary).get("GraphicsPresetRevision", 0)) if parsed is Dictionary else quality_script.PRESET_REVISION)
	defaults["GraphicsPresetRevision"] = quality_script.PRESET_REVISION
	return defaults

func save_settings_data() -> bool:
	var path := get_settings_path()
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			push_warning("Could not create settings directory: %s" % directory)
			return false
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save settings to %s" % path)
		return false
	file.store_string(JSON.stringify(_settings_data, "  "))
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK: result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		push_warning("Could not publish settings: %s" % path)
	return result == OK

func apply_settings_data() -> void:
	$GraphicsQuality.apply(_settings_data.get("Graphics", {}))
	var resolution := parse_resolution(
		str(_settings_data.get("Resolution", "1920x1080"))
	)
	var window_mode := str(
		_settings_data.get("WindowMode", "fullscreen")
	)
	var screen := clampi(
		int(_settings_data.get("Screen", 0)),
		0,
		maxi(DisplayServer.get_screen_count() - 1, 0)
	)
	var vsync_enabled := bool(_settings_data.get("VSync", true))

	var display := {"resolution": resolution, "mode": window_mode, "screen": screen, "vsync": vsync_enabled}
	if DisplayServer.get_name() != "headless" and display != _applied_display:
		if _applied_display.get("screen") != screen: DisplayServer.window_set_current_screen(screen)
		if _applied_display.get("mode") != window_mode or _applied_display.get("resolution") != resolution or _applied_display.get("screen") != screen:
			match window_mode:
				"windowed":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					DisplayServer.window_set_size(resolution)
				"maximized":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
				_:
					# Borderless fullscreen always uses the desktop resolution. Switch
					# through a sized window so exclusive fullscreen applies the value
					# selected in the menu, including after a freshly exported build.
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					DisplayServer.window_set_size(resolution)
					DisplayServer.window_set_mode(
						DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
					)
		if _applied_display.get("vsync") != vsync_enabled:
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED
				if vsync_enabled
				else DisplayServer.VSYNC_DISABLED
			)
	_applied_display = display

	var volume_percent := clampf(
		float(_settings_data.get("MasterVolume", 80.0)),
		0.0,
		100.0
	)
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, volume_percent <= 0.0)
		AudioServer.set_bus_volume_db(
			master_bus,
			linear_to_db(maxf(volume_percent / 100.0, 0.0001))
		)
	var music_percent := clampf(
		float(_settings_data.get("MusicVolume", 70.0)),
		0.0,
		100.0
	)
	var music_bus := AudioServer.get_bus_index("Music")
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, music_percent <= 0.0)
		AudioServer.set_bus_volume_db(
			music_bus,
			linear_to_db(maxf(music_percent / 100.0, 0.0001))
		)
	_mouse_sensitivity_multiplier = clampf(
		float(_settings_data.get("MouseSensitivity", 1.0)),
		0.25,
		2.5
	)
	audio_mix.apply_settings(_settings_data)

func parse_resolution(value: String) -> Vector2i:
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		return Vector2i(1920, 1080)
	return Vector2i(maxi(int(parts[0]), 640), maxi(int(parts[1]), 360))

func resolution_to_text(value: Vector2i) -> String:
	return "%dx%d" % [value.x, value.y]

func ensure_music_bus() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	AudioServer.add_bus()
	var music_bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(music_bus, "Music")
	AudioServer.set_bus_send(music_bus, "Master")

func get_mouse_sensitivity_multiplier() -> float:
	return _mouse_sensitivity_multiplier

func start_standalone_flow(resume_checkpoint: bool = false) -> void:
	BaseGameplayController.save_scope = "solo"
	if not resume_checkpoint and not BaseGameplayController.delete_progress_save():
		open_menu(MenuView.MAIN)
		feedback_label.text = "Не удалось очистить одиночное сохранение."
		return
	_transition_in_progress = true
	menu_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var change_result := get_tree().change_scene_to_file(
		MECHANICS_TEST_ROOM_SCENE
	)
	if change_result != OK:
		_transition_in_progress = false
		open_menu(MenuView.MAIN)
		feedback_label.text = "Не удалось открыть базу."
		return

	await get_tree().scene_changed
	var gameplay_controller := get_tree().current_scene
	if gameplay_controller != null and gameplay_controller.has_method(
		"start_standalone_game"
	):
		gameplay_controller.set("resume_base_on_start", resume_checkpoint)
		gameplay_controller.call("start_standalone_game")
		if resume_checkpoint:
			await gameplay_controller.call("_enter_v3_level")
	_transition_in_progress = false

func ensure_network_scene() -> bool:
	var current_scene := get_tree().current_scene
	if (
		current_scene != null
		and current_scene.scene_file_path == MECHANICS_TEST_ROOM_SCENE
	):
		# A running standalone world or previous Steam session must not be reused.
		if get_tree().get_first_node_in_group("local_player") == null:
			return true

	menu_root.visible = false
	get_tree().paused = false
	var change_result := get_tree().change_scene_to_file(
		MECHANICS_TEST_ROOM_SCENE
	)
	if change_result != OK:
		return false

	await get_tree().scene_changed
	return true

func return_to_main_menu(reason: String = "", save_before_exit: bool = true) -> void:
	if _transition_in_progress:
		return
	var base := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if save_before_exit and base != null and multiplayer.is_server() and base.progress_persistence_enabled:
		if not base.save_progress_authoritative():
			confirm("Не удалось сохранить", "Новые изменения не записались. Предыдущая запись сохранена. Остаться в игре или закрыть сессию?", [{"label": "Выйти без сохранения", "action": return_to_main_menu.bind(reason, false)}])
			return
	_transition_in_progress = true
	menu_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if SteamNetwork.has_active_session():
		SteamNetwork.leave_session(reason)
		return
	call_deferred("_finish_return_to_main_menu", reason)

func manual_save() -> void:
	var base := get_tree().get_first_node_in_group("base_gameplay_controller") as BaseGameplayController
	if base == null or not multiplayer.is_server():
		feedback_label.text = "Сохранение доступно хосту на базе."
		return
	feedback_label.text = "Экспедиция сохранена." if base.save_progress_authoritative(false, "manual") else "Не удалось сохранить экспедицию. Предыдущая запись сохранена."

func _finish_return_to_main_menu(reason: String) -> void:
	var current_scene := get_tree().current_scene
	if current_scene != null and not current_scene.is_in_group("main_menu"):
		var main_scene := str(
			ProjectSettings.get_setting("application/run/main_scene", "")
		)
		if not main_scene.is_empty():
			var change_result := get_tree().change_scene_to_file(main_scene)
			if change_result == OK:
				await get_tree().scene_changed

	_transition_in_progress = false
	force_close_menu()
	current_scene = get_tree().current_scene
	if current_scene != null and current_scene.has_method("show_status"):
		current_scene.call("show_status", reason)

func get_localized_state_message(
	state: SteamNetworkService.SessionState,
	fallback: String
) -> String:
	match state:
		SteamNetworkService.SessionState.STARTING_STEAM:
			return "Запускаем Steam..."
		SteamNetworkService.SessionState.STEAM_UNAVAILABLE:
			return "Steam недоступен: %s" % fallback
		SteamNetworkService.SessionState.READY:
			return "Steam подключён. Можно создать лобби."
		SteamNetworkService.SessionState.CREATING_LOBBY:
			return "Создаём Steam-лобби..."
		SteamNetworkService.SessionState.JOINING_LOBBY:
			return "Входим в Steam-лобби..."
		SteamNetworkService.SessionState.HOSTING:
			return "Лобби готово. Передайте Lobby ID другу."
		SteamNetworkService.SessionState.CONNECTING:
			return "Подключаемся к хосту через Steam..."
		SteamNetworkService.SessionState.CONNECTED:
			return "Подключено к хосту через Steam."
		SteamNetworkService.SessionState.LEAVING:
			return "Покидаем Steam-лобби..."
	return fallback

func default_settings_data() -> Dictionary:
	var defaults := {
		"Resolution": "1920x1080",
		"WindowMode": "fullscreen",
		"Screen": 0,
		"VSync": true,
		"MasterVolume": 80.0,
		"MusicVolume": 70.0,
		"EffectsVolume": 100.0,
		"WeaponsVolume": 100.0,
		"VehiclesVolume": 100.0,
		"MachineryVolume": 100.0,
		"AmbienceVolume": 100.0,
		"BreathingVolume": 100.0,
		"RoomReverb": 50.0,
		"MouseSensitivity": 1.0,
		"CharacterVariant": 0,
	}
	return defaults
