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
	custom_minimum_size.x = 280
	add_theme_constant_override("separation", 8)
	add_child(NorthernMenuStyle.button("‹", func(): set_value(value - step), 18))
	number = NorthernMenuStyle.button("", Callable(), 17)
	number.theme_type_variation = &"MenuToggle"
	number.alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	number.gui_input.connect(_number_input)
	add_child(number)
	add_child(NorthernMenuStyle.button("›", func(): set_value(value + step), 18))
	_update_number()

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
