class_name GlobalGameMenu
extends CanvasLayer

enum MenuView {
	MAIN,
	SESSION,
	JOIN,
	SETTINGS,
}

const MECHANICS_TEST_ROOM_SCENE := (
	"res://scenes/tests/mechanics_test_room.tscn"
)
const SETTINGS_DIRECTORY := "NorthernLab"
const SETTINGS_FILE := "launcher_settings.json"
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const WINDOW_MODES := ["fullscreen", "windowed", "maximized"]

@onready var menu_root: Control = %MenuRoot
@onready var main_panel: VBoxContainer = %MainPanel
@onready var session_panel: VBoxContainer = %SessionPanel
@onready var join_panel: VBoxContainer = %JoinPanel
@onready var settings_panel: VBoxContainer = %SettingsPanel

@onready var steam_status_label: Label = %SteamStatusLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var continue_button: Button = %ContinueButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var settings_button: Button = %SettingsButton
@onready var exit_button: Button = %ExitButton

@onready var session_status_label: Label = %SessionStatusLabel
@onready var lobby_id_value: LineEdit = %LobbyIdValue
@onready var copy_lobby_id_button: Button = %CopyLobbyIdButton
@onready var invite_button: Button = %InviteButton
@onready var members_label: Label = %MembersLabel
@onready var ready_status_label: Label = %ReadyStatusLabel
@onready var ready_button: Button = %ReadyButton
@onready var start_game_button: Button = %StartGameButton
@onready var leave_lobby_button: Button = %LeaveLobbyButton
@onready var session_back_button: Button = %SessionBackButton

@onready var lobby_id_input: LineEdit = %LobbyIdInput
@onready var connect_button: Button = %ConnectButton
@onready var join_back_button: Button = %JoinBackButton

@onready var resolution_option: OptionButton = %ResolutionOption
@onready var window_mode_option: OptionButton = %WindowModeOption
@onready var screen_option: OptionButton = %ScreenOption
@onready var vsync_check: CheckButton = %VSyncCheck
@onready var master_volume_slider: HSlider = %MasterVolumeSlider
@onready var master_volume_value: Label = %MasterVolumeValue
@onready var music_volume_slider: HSlider = %MusicVolumeSlider
@onready var music_volume_value: Label = %MusicVolumeValue
@onready var mouse_sensitivity_slider: HSlider = %MouseSensitivitySlider
@onready var mouse_sensitivity_value: Label = %MouseSensitivityValue
@onready var settings_back_button: Button = %SettingsBackButton

var _current_view: MenuView = MenuView.MAIN
var _transition_in_progress: bool = false
var _settings_return_to_main_scene: bool = false
var _settings_data: Dictionary = {}
var _mouse_sensitivity_multiplier: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_root.visible = false
	connect_ui_signals()
	connect_network_signals()
	initialize_settings()
	refresh_network_ui()


func _unhandled_input(event: InputEvent) -> void:
	var current_scene := get_tree().current_scene
	var is_main_scene := (
		current_scene != null and current_scene.is_in_group("main_menu")
	)
	if (
		event.is_action_pressed("pause")
		and not (event is InputEventKey and event.echo)
		and not _transition_in_progress
	):
		if is_main_scene and not menu_root.visible:
			return
		if menu_root.visible:
			if _current_view == MenuView.SETTINGS:
				close_settings()
			else:
				close_menu()
		else:
			open_menu(MenuView.MAIN)
		get_viewport().set_input_as_handled()


func connect_ui_signals() -> void:
	continue_button.pressed.connect(close_menu)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(open_settings)
	exit_button.pressed.connect(_on_return_to_main_menu_pressed)

	copy_lobby_id_button.pressed.connect(_on_copy_lobby_id_pressed)
	invite_button.pressed.connect(_on_invite_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	session_back_button.pressed.connect(show_view.bind(MenuView.MAIN))

	connect_button.pressed.connect(_on_connect_pressed)
	lobby_id_input.text_submitted.connect(_on_lobby_id_submitted)
	join_back_button.pressed.connect(show_view.bind(MenuView.MAIN))

	resolution_option.item_selected.connect(_on_display_setting_changed)
	window_mode_option.item_selected.connect(_on_display_setting_changed)
	screen_option.item_selected.connect(_on_display_setting_changed)
	vsync_check.toggled.connect(_on_vsync_toggled)
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	mouse_sensitivity_slider.value_changed.connect(
		_on_mouse_sensitivity_changed
	)
	settings_back_button.pressed.connect(close_settings)


func connect_network_signals() -> void:
	SteamNetwork.state_changed.connect(_on_network_state_changed)
	SteamNetwork.lobby_entered.connect(_on_lobby_entered)
	SteamNetwork.lobby_members_changed.connect(_on_lobby_members_changed)
	SteamNetwork.session_ready.connect(_on_session_ready)
	SteamNetwork.session_closed.connect(_on_session_closed)
	SteamNetwork.invite_join_requested.connect(_on_invite_join_requested)
	CoopLobby.ready_state_changed.connect(_on_ready_state_changed)
	CoopLobby.gameplay_started.connect(_on_gameplay_started)


func open_menu(view: MenuView = MenuView.MAIN) -> void:
	menu_root.visible = true
	show_view(view)
	refresh_network_ui()
	# The ESC overlay never pauses only one peer. Remote players and world
	# simulation continue, while the local player stops because the mouse is free.
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_settings() -> void:
	var current_scene := get_tree().current_scene
	_settings_return_to_main_scene = (
		current_scene != null and current_scene.is_in_group("main_menu")
	)
	open_menu(MenuView.SETTINGS)
	resolution_option.grab_focus()


func close_settings() -> void:
	if _settings_return_to_main_scene:
		force_close_menu()
		return
	show_view(MenuView.MAIN)
	settings_button.grab_focus()


func close_menu() -> void:
	if _transition_in_progress:
		return

	if is_lobby_gate_active():
		show_view(MenuView.SESSION)
		feedback_label.text = "Дождитесь завершения подключения к Steam-лобби."
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	force_close_menu()


func force_close_menu() -> void:
	menu_root.visible = false
	get_tree().paused = false
	if get_tree().get_first_node_in_group("local_player") != null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_menu_open() -> bool:
	return menu_root.visible


func is_lobby_gate_active() -> bool:
	return SteamNetwork.state in [
		SteamNetworkService.SessionState.CREATING_LOBBY,
		SteamNetworkService.SessionState.JOINING_LOBBY,
		SteamNetworkService.SessionState.CONNECTING,
	]


func start_standalone_flow() -> void:
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
		feedback_label.text = "Не удалось открыть тестовую комнату."
		return

	await get_tree().scene_changed
	var gameplay_controller := get_tree().current_scene
	if gameplay_controller != null and gameplay_controller.has_method(
		"start_standalone_game"
	):
		gameplay_controller.call("start_standalone_game")
	_transition_in_progress = false


func show_view(view: MenuView) -> void:
	_current_view = view
	main_panel.visible = view == MenuView.MAIN
	session_panel.visible = view == MenuView.SESSION
	join_panel.visible = view == MenuView.JOIN
	settings_panel.visible = view == MenuView.SETTINGS
	feedback_label.text = ""

	if view == MenuView.JOIN:
		lobby_id_input.grab_focus()
		lobby_id_input.select_all()
	elif view == MenuView.SESSION:
		refresh_session_ui()
	elif view == MenuView.SETTINGS:
		refresh_settings_ui()


func initialize_settings() -> void:
	ensure_music_bus()
	populate_settings_options()
	_settings_data = load_settings_data()
	apply_settings_data()
	refresh_settings_ui()


func populate_settings_options() -> void:
	resolution_option.clear()
	for resolution in RESOLUTIONS:
		resolution_option.add_item("%d × %d" % [resolution.x, resolution.y])

	window_mode_option.clear()
	for label in ["Полный экран", "Оконный", "Развёрнутое окно"]:
		window_mode_option.add_item(label)

	screen_option.clear()
	var is_headless := DisplayServer.get_name() == "headless"
	var screen_count := (
		1 if is_headless else maxi(DisplayServer.get_screen_count(), 1)
	)
	for screen_index in screen_count:
		var screen_size := (
			Vector2i(1920, 1080)
			if is_headless
			else DisplayServer.screen_get_size(screen_index)
		)
		screen_option.add_item(
			"Монитор %d — %d × %d" % [
				screen_index + 1,
				screen_size.x,
				screen_size.y,
			]
		)


func get_settings_path() -> String:
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	if local_app_data.is_empty():
		return "user://%s" % SETTINGS_FILE
	return local_app_data.path_join(SETTINGS_DIRECTORY).path_join(SETTINGS_FILE)


func load_settings_data() -> Dictionary:
	var defaults := {
		"Resolution": "1920x1080",
		"WindowMode": "fullscreen",
		"Screen": 0,
		"VSync": true,
		"MasterVolume": 80.0,
		"MusicVolume": 70.0,
		"MouseSensitivity": 1.0,
	}
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
	return defaults


func save_settings_data() -> void:
	var path := get_settings_path()
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save settings to %s" % path)
		return
	file.store_string(JSON.stringify(_settings_data, "  "))


func apply_settings_data() -> void:
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

	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_current_screen(screen)
		match window_mode:
			"windowed":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				DisplayServer.window_set_size(resolution)
			"maximized":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			_:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED
			if vsync_enabled
			else DisplayServer.VSYNC_DISABLED
		)

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


func refresh_settings_ui() -> void:
	var resolution_text := str(
		_settings_data.get("Resolution", "1920x1080")
	)
	var resolution_index := 0
	for index in RESOLUTIONS.size():
		if resolution_to_text(RESOLUTIONS[index]) == resolution_text:
			resolution_index = index
			break
	resolution_option.select(resolution_index)

	var window_mode := str(
		_settings_data.get("WindowMode", "fullscreen")
	)
	window_mode_option.select(maxi(WINDOW_MODES.find(window_mode), 0))
	screen_option.select(clampi(
		int(_settings_data.get("Screen", 0)),
		0,
		maxi(screen_option.item_count - 1, 0)
	))
	vsync_check.button_pressed = bool(_settings_data.get("VSync", true))
	master_volume_slider.value = float(
		_settings_data.get("MasterVolume", 80.0)
	)
	music_volume_slider.value = float(
		_settings_data.get("MusicVolume", 70.0)
	)
	mouse_sensitivity_slider.value = float(
		_settings_data.get("MouseSensitivity", 1.0)
	)
	refresh_settings_value_labels()


func parse_resolution(value: String) -> Vector2i:
	var parts := value.to_lower().split("x")
	if parts.size() != 2:
		return Vector2i(1920, 1080)
	return Vector2i(maxi(int(parts[0]), 640), maxi(int(parts[1]), 360))


func resolution_to_text(value: Vector2i) -> String:
	return "%dx%d" % [value.x, value.y]


func refresh_settings_value_labels() -> void:
	master_volume_value.text = "%d%%" % int(master_volume_slider.value)
	music_volume_value.text = "%d%%" % int(music_volume_slider.value)
	mouse_sensitivity_value.text = "%.2f×" % mouse_sensitivity_slider.value


func ensure_music_bus() -> void:
	if AudioServer.get_bus_index("Music") >= 0:
		return
	AudioServer.add_bus()
	var music_bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(music_bus, "Music")
	AudioServer.set_bus_send(music_bus, "Master")


func get_mouse_sensitivity_multiplier() -> float:
	return _mouse_sensitivity_multiplier


func _on_display_setting_changed(_index: int) -> void:
	var resolution: Vector2i = RESOLUTIONS[resolution_option.selected]
	_settings_data["Resolution"] = resolution_to_text(resolution)
	_settings_data["WindowMode"] = WINDOW_MODES[window_mode_option.selected]
	_settings_data["Screen"] = screen_option.selected
	apply_settings_data()
	save_settings_data()


func _on_vsync_toggled(enabled: bool) -> void:
	_settings_data["VSync"] = enabled
	apply_settings_data()
	save_settings_data()


func _on_master_volume_changed(value: float) -> void:
	_settings_data["MasterVolume"] = value
	apply_settings_data()
	refresh_settings_value_labels()
	save_settings_data()


func _on_music_volume_changed(value: float) -> void:
	_settings_data["MusicVolume"] = value
	apply_settings_data()
	refresh_settings_value_labels()
	save_settings_data()


func _on_mouse_sensitivity_changed(value: float) -> void:
	_settings_data["MouseSensitivity"] = value
	_mouse_sensitivity_multiplier = value
	refresh_settings_value_labels()
	save_settings_data()


func refresh_network_ui() -> void:
	if SteamNetwork.steam_available:
		steam_status_label.text = "Steam: %s" % SteamNetwork.local_user_name
	else:
		steam_status_label.text = "Steam недоступен: %s" % SteamNetwork.state_message

	var in_session := SteamNetwork.has_active_session()
	continue_button.disabled = (
		get_tree().get_first_node_in_group("local_player") == null
	)
	host_button.disabled = not SteamNetwork.steam_available
	join_button.disabled = not SteamNetwork.steam_available
	host_button.text = (
		"Показать Steam-лобби"
		if in_session
		else "Играть с друзьями"
	)
	refresh_session_ui()


func refresh_session_ui() -> void:
	var current_lobby_id := SteamNetwork.lobby_id
	lobby_id_value.text = (
		str(current_lobby_id)
		if current_lobby_id > 0
		else "Лобби создаётся..."
	)
	copy_lobby_id_button.disabled = current_lobby_id <= 0
	invite_button.disabled = current_lobby_id <= 0 or not SteamNetwork.is_host
	leave_lobby_button.disabled = not SteamNetwork.has_active_session()
	session_status_label.text = get_localized_state_message(
		SteamNetwork.state,
		SteamNetwork.state_message
	)
	refresh_member_list(SteamNetwork.get_lobby_members())
	refresh_ready_ui()


func refresh_ready_ui() -> void:
	if CoopLobby.game_has_started:
		ready_status_label.text = "Игра запущена."
		ready_button.text = "Продолжить игру"
		ready_button.disabled = false
		start_game_button.visible = false
		return

	if not CoopLobby.session_active:
		ready_status_label.text = "Готовность: ожидаем соединение..."
		ready_button.text = "Готов"
		ready_button.disabled = true
		start_game_button.visible = SteamNetwork.is_host
		start_game_button.disabled = true
		return

	var ready_lines: PackedStringArray = []
	var peer_ids := CoopLobby.ready_states.keys()
	peer_ids.sort()
	for peer_id_variant in peer_ids:
		var peer_id := int(peer_id_variant)
		var player_name := SteamNetwork.get_peer_persona_name(peer_id)
		var state_text := (
			"ГОТОВ"
			if bool(CoopLobby.ready_states.get(peer_id, false))
			else "НЕ ГОТОВ"
		)
		ready_lines.append("• %s — %s" % [player_name, state_text])

	if CoopLobby.get_player_count() < CoopLobby.REQUIRED_PLAYERS:
		ready_lines.append("• Второй игрок сможет подключиться позже.")
	ready_status_label.text = "Готовность:\n%s" % "\n".join(ready_lines)

	ready_button.disabled = false
	ready_button.text = (
		"Отменить готовность"
		if CoopLobby.is_local_ready()
		else "Готов"
	)
	start_game_button.visible = SteamNetwork.is_host
	start_game_button.disabled = not CoopLobby.can_host_start()
	start_game_button.text = "Начать игру"


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


func refresh_member_list(members: Array[Dictionary]) -> void:
	if members.is_empty():
		members_label.text = "Участники: ожидаем данные Steam..."
		return

	var lines: PackedStringArray = []
	for member in members:
		var host_suffix := " — HOST" if bool(member.get("is_host", false)) else ""
		lines.append("• %s%s" % [member.get("name", "Player"), host_suffix])
	members_label.text = "Участники:\n%s" % "\n".join(lines)


func _on_host_pressed() -> void:
	if SteamNetwork.has_active_session():
		show_view(MenuView.SESSION)
		return
	start_host_flow()


func start_host_flow() -> void:
	if _transition_in_progress:
		return

	_transition_in_progress = true
	feedback_label.text = "Открываем сетевую тестовую комнату..."
	var scene_ready := await ensure_network_scene()
	_transition_in_progress = false
	open_menu(MenuView.SESSION)

	if not scene_ready:
		session_status_label.text = "Не удалось открыть сетевую комнату."
		return

	session_status_label.text = "Создаём Steam-лобби..."
	if not SteamNetwork.create_friends_lobby():
		session_status_label.text = "Steam не смог начать создание лобби."


func _on_join_pressed() -> void:
	show_view(MenuView.JOIN)


func _on_connect_pressed() -> void:
	connect_to_lobby_from_text(lobby_id_input.text)


func _on_lobby_id_submitted(value: String) -> void:
	connect_to_lobby_from_text(value)


func connect_to_lobby_from_text(value: String) -> void:
	var clean_value := value.strip_edges()
	if not clean_value.is_valid_int() or int(clean_value) <= 0:
		feedback_label.text = "Введите Lobby ID из меню хоста — только цифры."
		lobby_id_input.grab_focus()
		return
	start_join_flow(int(clean_value))


func start_join_flow(target_lobby_id: int) -> void:
	if _transition_in_progress:
		return

	_transition_in_progress = true
	feedback_label.text = "Открываем сетевую тестовую комнату..."
	var scene_ready := await ensure_network_scene()
	_transition_in_progress = false
	open_menu(MenuView.SESSION)

	if not scene_ready:
		session_status_label.text = "Не удалось открыть сетевую комнату."
		return

	lobby_id_value.text = str(target_lobby_id)
	session_status_label.text = "Подключаемся к Steam-лобби..."
	if not SteamNetwork.join_lobby(target_lobby_id):
		session_status_label.text = "Не удалось начать подключение к лобби."


func ensure_network_scene() -> bool:
	var current_scene := get_tree().current_scene
	if (
		current_scene != null
		and current_scene.scene_file_path == MECHANICS_TEST_ROOM_SCENE
	):
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


func _on_copy_lobby_id_pressed() -> void:
	if SteamNetwork.lobby_id <= 0:
		return
	DisplayServer.clipboard_set(str(SteamNetwork.lobby_id))
	feedback_label.text = "Lobby ID скопирован. Отправьте его другу."


func _on_invite_pressed() -> void:
	if not SteamNetwork.is_overlay_enabled():
		feedback_label.text = (
			"Steam API работает, но Overlay не подключён к процессу игры. "
			+ "Добавьте прямой NorthernLab.lnk в библиотеку Steam и "
			+ "запустите игру оттуда. Пока можно отправить другу Lobby ID."
		)
		return

	if SteamNetwork.open_invite_overlay():
		feedback_label.text = "Открываем окно приглашения Steam..."
	else:
		feedback_label.text = "Сначала создайте Steam-лобби."


func _on_ready_pressed() -> void:
	if CoopLobby.game_has_started:
		close_menu()
		return

	var next_ready_state := not CoopLobby.is_local_ready()
	if CoopLobby.set_local_ready(next_ready_state):
		feedback_label.text = (
			"Готовность подтверждена."
			if next_ready_state
			else "Готовность отменена."
		)
	else:
		feedback_label.text = "Сетевая сессия ещё не готова."
	refresh_ready_ui()


func _on_start_game_pressed() -> void:
	if CoopLobby.start_game():
		start_game_button.disabled = true
		session_status_label.text = "Запускаем игру для всех игроков..."
	else:
		feedback_label.text = (
			"Все подключённые игроки должны подтвердить готовность."
		)
	refresh_ready_ui()


func _on_leave_lobby_pressed() -> void:
	return_to_main_menu("Вы покинули Steam-лобби.")


func _on_return_to_main_menu_pressed() -> void:
	return_to_main_menu("Возврат из экспедиции.")


func return_to_main_menu(reason: String = "") -> void:
	if _transition_in_progress:
		return
	_transition_in_progress = true
	menu_root.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if SteamNetwork.has_active_session():
		SteamNetwork.leave_session(reason)
		return
	call_deferred("_finish_return_to_main_menu", reason)


func _on_network_state_changed(
	state: SteamNetworkService.SessionState,
	message: String
) -> void:
	steam_status_label.text = (
		"Steam: %s" % SteamNetwork.local_user_name
		if SteamNetwork.steam_available
		else "Steam недоступен: %s" % message
	)
	if _current_view == MenuView.SESSION:
		session_status_label.text = get_localized_state_message(state, message)
	refresh_network_ui()


func _on_lobby_entered(_lobby_id: int, _as_host: bool) -> void:
	refresh_session_ui()
	if menu_root.visible:
		show_view(MenuView.SESSION)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_lobby_members_changed(members: Array[Dictionary]) -> void:
	refresh_member_list(members)
	refresh_session_ui()


func _on_session_ready(as_host: bool) -> void:
	refresh_session_ui()
	session_status_label.text = (
		"Лобби готово. Подтвердите готовность или передайте Lobby ID другу."
		if as_host
		else "Подключено к хосту через Steam."
	)
	if menu_root.visible:
		force_close_menu()


func _on_session_closed(reason: String) -> void:
	refresh_network_ui()
	_transition_in_progress = true
	call_deferred("_finish_return_to_main_menu", reason)


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


func _on_invite_join_requested(requested_lobby_id: int) -> void:
	lobby_id_input.text = str(requested_lobby_id)
	open_menu(MenuView.JOIN)
	start_join_flow(requested_lobby_id)


func _on_ready_state_changed(_ready_states: Dictionary) -> void:
	refresh_ready_ui()


func _on_gameplay_started() -> void:
	feedback_label.text = "Игра началась. Друг сможет подключиться позже."
	force_close_menu()
