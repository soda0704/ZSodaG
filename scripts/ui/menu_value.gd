class_name NorthernMenuValue
extends HBoxContainer
## Drag the number with LMB; a click alone never changes it. Arrows step.

signal value_changed(value: float)
var value := 0.0
var minimum := 0.0
var maximum := 100.0
var step := 1.0
var suffix := ""
var decimals := 0
var number: Button
var _dragging := false
var _origin := Vector2.ZERO
var _start := 0.0

func _ready() -> void:
	custom_minimum_size.y = 40
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_theme_constant_override("separation", 0)
	var decrease := _part("‹", func(): set_value(value - step), 20)
	add_child(decrease)
	number = NorthernMenuStyle.button("", Callable(), 17)
	number.theme_type_variation = &"MenuStepperPart"
	number.custom_minimum_size.y = 40
	number.alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	number.gui_input.connect(_number_input)
	add_child(number)
	add_child(_part("›", func(): set_value(value + step), 20))
	for child in get_children():
		child.mouse_entered.connect(queue_redraw)
		child.mouse_exited.connect(queue_redraw)
		child.focus_entered.connect(queue_redraw)
		child.focus_exited.connect(queue_redraw)
	_update_number()

func _part(text: String, action: Callable, font_size: int) -> Button:
	var button := NorthernMenuStyle.button(text, action, font_size)
	button.theme_type_variation = &"MenuStepperPart"
	button.custom_minimum_size = Vector2(36, 40)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button

func _draw() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var focused := focus != null and is_ancestor_of(focus)
	var hovered := get_global_rect().has_point(get_global_mouse_position())
	get_theme_stylebox("hover" if hovered else "normal", "MenuChoice").draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	if focused: get_theme_stylebox("focus", "MenuChoice").draw(get_canvas_item(), Rect2(Vector2.ZERO, size))
	for x in [36.0, size.x - 36.0]:
		draw_line(Vector2(x, 9), Vector2(x, size.y - 9), NorthernMenuStyle.RULE, 1)

func _number_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_origin = number.get_global_transform_with_canvas() * event.position
			_start = value
		number.accept_event()
	elif event.is_action_pressed("ui_left"):
		set_value(value - step)
		number.accept_event()
	elif event.is_action_pressed("ui_right"):
		set_value(value + step)
		number.accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_dragging = false
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
	if _dragging and event is InputEventMouseMotion:
		var distance: float = event.position.x - _origin.x
		if absf(distance) > 4:
			set_value(_start + distance * (maximum - minimum) / 360.0)
		get_viewport().set_input_as_handled()

func set_value(next: float, notify: bool = true) -> void:
	var result := clampf(snappedf(next, step), minimum, maximum)
	var changed := not is_equal_approx(value, result)
	value = result
	_update_number()
	if notify and changed:
		value_changed.emit(value)

func _update_number() -> void:
	if number != null:
		number.text = (str(int(value)) if decimals == 0 else ("%.*f" % [decimals, value])) + suffix

func _exit_tree() -> void:
	_dragging = false
