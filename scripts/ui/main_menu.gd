class_name NorthernLabMainMenu
extends Control

@onready var continue_game_button: Button = %ContinueGameButton
@onready var single_player_button: Button = %SinglePlayerButton
@onready var delete_save_button: Button = %DeleteSaveButton
@onready var host_button: Button = %HostButton
@onready var join_button: Button = %JoinButton
@onready var settings_button: Button = %SettingsButton
@onready var exit_button: Button = %ExitButton
@onready var background_video: VideoStreamPlayer = %BackgroundVideo
@onready var steam_status_label: Label = %SteamStatusLabel
@onready var status_label: Label = %StatusLabel
@onready var save_status_label: Label = %SaveStatusLabel
@onready var fade: ColorRect = %Fade
@onready var new_game_confirmation: ConfirmationDialog = %NewGameConfirmation
@onready var delete_save_confirmation: ConfirmationDialog = %DeleteSaveConfirmation

var _transition_in_progress: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameMenu.force_close_menu()

	continue_game_button.pressed.connect(_on_continue_game_pressed)
	single_player_button.pressed.connect(_on_single_player_pressed)
	delete_save_button.pressed.connect(_on_delete_save_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	exit_button.pressed.connect(_on_exit_pressed)
	new_game_confirmation.confirmed.connect(_start_new_game)
	delete_save_confirmation.confirmed.connect(_delete_save_confirmed)
	background_video.finished.connect(_on_background_video_finished)
	# Assign after the autoload has created/loaded the Music bus. Otherwise Godot
	# falls back to Master if the scene property resolves before the bus layout.
	background_video.bus = &"Music"

	SteamNetwork.state_changed.connect(_on_steam_state_changed)
	SteamNetwork.steam_initialized.connect(_on_steam_initialized)
	SteamNetwork.steam_initialization_failed.connect(
		_on_steam_initialization_failed
	)

	refresh_steam_status()
	refresh_save_ui()
	if continue_game_button.disabled:
		single_player_button.grab_focus()
	else:
		continue_game_button.grab_focus()
	if not background_video.is_playing():
		background_video.play()


func _on_background_video_finished() -> void:
	background_video.play()


func refresh_steam_status() -> void:
	if SteamNetwork.steam_available:
		steam_status_label.text = "STEAM ONLINE\n%s" % SteamNetwork.local_user_name
		host_button.disabled = false
		join_button.disabled = false
	else:
		steam_status_label.text = "STEAM OFFLINE\nОдиночная игра доступна"
		host_button.disabled = true
		join_button.disabled = true


func set_menu_enabled(value: bool) -> void:
	continue_game_button.disabled = (
		not value
		or BaseGameplayController.get_saved_progress_summary().is_empty()
	)
	single_player_button.disabled = not value
	delete_save_button.disabled = (
		not value or not BaseGameplayController.has_progress_save_file()
	)
	host_button.disabled = not value or not SteamNetwork.steam_available
	join_button.disabled = not value or not SteamNetwork.steam_available
	settings_button.disabled = not value
	exit_button.disabled = not value


func begin_transition(message: String) -> void:
	_transition_in_progress = true
	set_menu_enabled(false)
	status_label.text = message
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, 0.22)
	await tween.finished


func _on_single_player_pressed() -> void:
	if _transition_in_progress:
		return
	if BaseGameplayController.has_progress_save_file():
		new_game_confirmation.popup_centered()
		return
	_start_new_game()


func _on_continue_game_pressed() -> void:
	if (
		_transition_in_progress
		or BaseGameplayController.get_saved_progress_summary().is_empty()
	):
		return
	await begin_transition("ЗАГРУЗКА СОХРАНЁННОЙ ЭКСПЕДИЦИИ...")
	GameMenu.start_standalone_flow()


func _start_new_game() -> void:
	if _transition_in_progress:
		return
	if not BaseGameplayController.delete_progress_save():
		status_label.text = "НЕ УДАЛОСЬ ОЧИСТИТЬ СОХРАНЕНИЕ"
		refresh_save_ui()
		return
	await begin_transition("ЗАПУСК ЛОКАЛЬНОЙ ЭКСПЕДИЦИИ...")
	GameMenu.start_standalone_flow()


func _on_delete_save_pressed() -> void:
	if _transition_in_progress or not BaseGameplayController.has_progress_save_file():
		return
	delete_save_confirmation.popup_centered()


func _delete_save_confirmed() -> void:
	if BaseGameplayController.delete_progress_save():
		status_label.text = "СОХРАНЕНИЕ УДАЛЕНО"
	else:
		status_label.text = "НЕ УДАЛОСЬ УДАЛИТЬ СОХРАНЕНИЕ"
	refresh_save_ui()


func refresh_save_ui() -> void:
	var summary := BaseGameplayController.get_saved_progress_summary()
	var has_file := BaseGameplayController.has_progress_save_file()
	continue_game_button.disabled = summary.is_empty()
	delete_save_button.disabled = not has_file
	if not summary.is_empty():
		var power_text := (
			"ПИТАНИЕ ВКЛЮЧЕНО"
			if bool(summary.get("main_breaker_on", false))
			else "ПИТАНИЕ ОТКЛЮЧЕНО"
		)
		save_status_label.text = "CHECKPOINT: DAY %d  •  %s" % [
			int(summary.get("day_index", 1)),
			power_text,
		]
	elif has_file:
		save_status_label.text = "CHECKPOINT ПОВРЕЖДЁН ИЛИ НЕСОВМЕСТИМ"
	else:
		save_status_label.text = "CHECKPOINT НЕ НАЙДЕН"


func _on_host_pressed() -> void:
	if _transition_in_progress or not SteamNetwork.steam_available:
		return
	status_label.text = "СОЗДАНИЕ STEAM-ЛОББИ..."
	set_menu_enabled(false)
	GameMenu.start_host_flow()


func _on_join_pressed() -> void:
	if _transition_in_progress or not SteamNetwork.steam_available:
		return
	GameMenu.open_menu(GlobalGameMenu.MenuView.JOIN)


func _on_settings_pressed() -> void:
	GameMenu.open_settings()


func _on_exit_pressed() -> void:
	get_tree().quit()


func show_status(message: String) -> void:
	if not message.is_empty():
		status_label.text = message.to_upper()


func _on_steam_state_changed(_state: int, _message: String) -> void:
	refresh_steam_status()


func _on_steam_initialized(_user_name: String) -> void:
	refresh_steam_status()


func _on_steam_initialization_failed(_reason: String) -> void:
	refresh_steam_status()
