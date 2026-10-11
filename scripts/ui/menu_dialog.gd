class_name NorthernMenuDialog
extends Control

signal closed
var panel: PanelContainer
var actions: HBoxContainer
var _closing := false
var _previous_focus: Control
var _entrance: Tween
var _line_progress := 0.0

func present(title: String, message: String, choices: Array[Dictionary]) -> void:
	_previous_focus = get_viewport().gui_get_focus_owner()
	NorthernMenuStyle.fill(self)
	panel = $Center/Panel
	$Center/Panel/Content/Title.text = title.to_upper()
	$Center/Panel/Content/Message.text = message
	actions = $Center/Panel/Content/Actions
	for choice in choices:
		var action: Callable = choice.get("action", Callable())
		var button := NorthernMenuStyle.button(str(choice.label), func(): dismiss(action), 17)
		button.theme_type_variation = &"MenuAction"
		button.disabled = bool(choice.get("disabled", false))
		actions.add_child(button)
	var back := NorthernMenuStyle.button("Назад", dismiss, 17)
	back.theme_type_variation = &"MenuAction"
	actions.add_child(back)
	back.grab_focus()
	modulate.a = 0
	panel.modulate.a = 0
	panel.scale = Vector2.ONE * 0.988
	panel.resized.connect(func(): panel.pivot_offset = panel.size * 0.5)
	await get_tree().process_frame
	if _closing:
		return
	panel.pivot_offset = panel.size * 0.5
	var origin := panel.position
	panel.position.y += 21
	_entrance = create_tween().set_parallel(true)
	_entrance.tween_property(self, "modulate:a", 1.0, 0.26).set_custom_interpolator(NorthernMenuStyle.ease)
	_entrance.tween_property(panel, "modulate:a", 1.0, 0.39).set_custom_interpolator(NorthernMenuStyle.ease)
	_entrance.tween_property(panel, "position", origin, 0.39).set_custom_interpolator(NorthernMenuStyle.ease)
	_entrance.tween_property(panel, "scale", Vector2.ONE, 0.39).set_custom_interpolator(NorthernMenuStyle.ease)
	_entrance.tween_property(self, "_line_progress", 1.0, 0.46).set_custom_interpolator(NorthernMenuStyle.ease)
	for index in $Center/Panel/Content.get_child_count():
		var part: Control = $Center/Panel/Content.get_child(index)
		part.modulate.a = 0
		_entrance.tween_property(part, "modulate:a", 1.0, 0.26).set_delay(0.065 + 0.035 * index).set_custom_interpolator(NorthernMenuStyle.ease)

func _process(_delta: float) -> void:
	if panel != null:
		$AccentLine.position = panel.global_position - global_position - Vector2(0, 1)
		$AccentLine.size = Vector2(panel.size.x, 1)
		$AccentLine.scale.x = _line_progress

func dismiss(action: Callable = Callable()) -> void:
	if _closing:
		return
	_closing = true
	if _entrance != null and _entrance.is_valid():
		_entrance.kill()
	for button in actions.get_children():
		button.disabled = true
	var exit_motion := create_tween().set_parallel(true)
	exit_motion.tween_property(self, "modulate:a", 0.0, 0.19).set_custom_interpolator(NorthernMenuStyle.ease)
	exit_motion.tween_property(panel, "position:y", panel.position.y + 10.5, 0.17).set_custom_interpolator(NorthernMenuStyle.ease)
	exit_motion.tween_property(panel, "scale", Vector2.ONE * 0.995, 0.17).set_custom_interpolator(NorthernMenuStyle.ease)
	await exit_motion.finished
	closed.emit()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree():
		_previous_focus.grab_focus()
	queue_free()
	if action.is_valid():
		action.call()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		dismiss()
