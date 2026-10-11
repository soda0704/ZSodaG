extends Button

var _hover := 0.0
var _press := 0.0
var _base_position := Vector2.ZERO
var _last_position := Vector2(INF, INF)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if position != _last_position:
		_base_position = position
	var target := 1.0 if not disabled and (is_hovered() or has_focus()) else 0.0
	var previous := _hover
	_hover = lerpf(_hover, target, 1.0 - exp(-delta * 12.0))
	_press = lerpf(_press, 1.0 if is_pressed() else 0.0, 1.0 - exp(-delta * 18.0))
	if not is_pressed() and _press < 0.001:
		_press = 0
	if absf(_hover - target) < 0.001:
		_hover = target
	scale = Vector2.ONE
	position = _base_position + Vector2(4.5 * _hover if theme_type_variation in [&"MenuNav", &"MenuEscapeNav"] else 0.0, _press)
	_last_position = position
	if not is_equal_approx(previous, _hover):
		var color := Color("a6a69f").lerp(Color("e0ddd3"), _hover)
		for state in ["font_color", "font_hover_color", "font_focus_color"]:
			add_theme_color_override(state, color)
		queue_redraw()

func _draw() -> void:
	if _hover > 0.005 and not get_parent().has_method("navigation_indicator"):
		draw_line(Vector2(0, size.y - 1), Vector2(size.x * _hover, size.y - 1), Color(0.40, 0.25, 0.23, _hover), 1.0)
