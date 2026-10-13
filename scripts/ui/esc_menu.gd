class_name NorthernEscapeMenu
extends VBoxContainer

var context: Label
var continue_button: Button
var settings_button: Button
var return_button: Button
var _menu: Node

func configure(menu: Node) -> void:
	_menu = menu
	continue_button = $Navigation/Continue
	settings_button = $Navigation/Settings
	return_button = $Navigation/MainMenu
	context = $Context
	continue_button.pressed.connect(func(): _menu.close_menu())
	settings_button.pressed.connect(func(): _menu.open_settings())
	return_button.pressed.connect(func(): _menu._on_return_to_main_menu_pressed())
	$Save.pressed.connect(func(): _menu.manual_save())
	$Feedback.pressed.connect(func(): _menu.open_feedback())

func refresh() -> void:
	var world := get_tree().get_first_node_in_group("network_gameplay_controller")
	var waiting: bool = world != null and world.has_method("is_waiting_for_arrival") and world.is_waiting_for_arrival()
	var base := get_tree().get_first_node_in_group("base_gameplay_controller")
	var day: int = int(base.get("day_index")) if base != null else 1
	var mode := "Одиночная игра"
	if SteamNetwork.has_active_session():
		mode = "Кооператив · %d участника" % maxi(1, CoopLobby.get_player_count())
	context.text = "День %d · %s\n%s" % [day, "На борту CH-47" if waiting else "Северная база", mode]
	continue_button.disabled = get_tree().get_first_node_in_group("local_player") == null
	$Save.disabled = base == null or not multiplayer.is_server() or not bool(base.get("progress_persistence_enabled"))
	$Save.text = "СОХРАНИТЬ ЭКСПЕДИЦИЮ" if multiplayer.is_server() else "СОХРАНЯЕТ ХОСТ"
