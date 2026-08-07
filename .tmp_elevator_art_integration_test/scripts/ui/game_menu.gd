class_name GlobalGameMenu
extends CanvasLayer

enum MenuView {
	MAIN,
	SESSION,
	JOIN,
}

const MECHANICS_TEST_ROOM_SCENE := (
	"res://scenes/tests/mechanics_test_room.tscn"
)

@onready var menu_root: Control = %MenuRoot
@onready var main_panel: VBoxContainer = %MainPanel
@onready var session_panel: VBoxContainer = %SessionPanel
@onready var join_panel: VBoxContainer = %JoinPanel

@onready var steam_status_label: Label = %SteamStatusLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var continue_button: Button = %ContinueButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
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

var _current_view: MenuView = MenuView.MAIN
var _transition_in_progress: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_root.visible = false
	connect_ui_signals()
	connect_network_signals()
	refresh_network_ui()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed("pause")
		and not (event is InputEventKey and event.echo)
		and not _transition_in_progress
	):
		if menu_root.visible:
			close_menu()
		else:
			open_menu(MenuView.MAIN)
		get_viewport().set_input_as_handled()


func connect_ui_signals() -> void:
	continue_button.pressed.connect(close_menu)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

	copy_lobby_id_button.pressed.connect(_on_copy_lobby_id_pressed)
	invite_button.pressed.connect(_on_invite_pressed)
	ready_button.pressed.connect(_on_ready_pressed)
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	session_back_button.pressed.connect(show_view.bind(MenuView.MAIN))

	connect_button.pressed.connect(_on_connect_pressed)
	lobby_id_input.text_submitted.connect(_on_lobby_id_submitted)
	join_back_button.pressed.connect(show_view.bind(MenuView.MAIN))


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


func show_view(view: MenuView) -> void:
	_current_view = view
	main_panel.visible = view == MenuView.MAIN
	session_panel.visible = view == MenuView.SESSION
	join_panel.visible = view == MenuView.JOIN
	feedback_label.text = ""

	if view == MenuView.JOIN:
		lobby_id_input.grab_focus()
		lobby_id_input.select_all()
	elif view == MenuView.SESSION:
		refresh_session_ui()


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
	SteamNetwork.leave_session("Вы покинули Steam-лобби.")
	show_view(MenuView.MAIN)
	refresh_network_ui()


func _on_exit_pressed() -> void:
	if SteamNetwork.has_active_session():
		SteamNetwork.leave_session("Игра закрывается.")
	get_tree().paused = false
	get_tree().quit()


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
	_transition_in_progress = false
	refresh_network_ui()
	call_deferred("_recover_after_session_closed", reason)


func _recover_after_session_closed(reason: String) -> void:
	var current_scene := get_tree().current_scene
	if (
		current_scene != null
		and current_scene.scene_file_path == MECHANICS_TEST_ROOM_SCENE
	):
		menu_root.visible = false
		get_tree().paused = false
		var main_scene := str(
			ProjectSettings.get_setting("application/run/main_scene", "")
		)
		if not main_scene.is_empty():
			var change_result := get_tree().change_scene_to_file(main_scene)
			if change_result == OK:
				await get_tree().scene_changed

	open_menu(MenuView.MAIN)
	feedback_label.text = reason


func _on_invite_join_requested(requested_lobby_id: int) -> void:
	lobby_id_input.text = str(requested_lobby_id)
	open_menu(MenuView.JOIN)
	start_join_flow(requested_lobby_id)


func _on_ready_state_changed(_ready_states: Dictionary) -> void:
	refresh_ready_ui()


func _on_gameplay_started() -> void:
	feedback_label.text = "Игра началась. Друг сможет подключиться позже."
	force_close_menu()
