class_name TerminalScreenUI
extends PanelContainer

@export var ready_background: StyleBox
@export var missing_background: StyleBox

func set_key_present(present: bool) -> void:
	add_theme_stylebox_override("panel", ready_background if present else missing_background)
