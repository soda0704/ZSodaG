extends Control
## The main menu is not instantiated until first-run calibration is committed.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameMenu.force_close_menu()
	if GameMenu.needs_display_calibration():
		GameMenu.open_display_calibration(true, _completed)
	else:
		_open_menu.call_deferred()

func _completed(accepted: bool) -> void:
	if accepted: _open_menu()

func _open_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
