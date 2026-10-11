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

func selection_line_rect() -> Rect2:
	var style := get_theme_stylebox("normal")
	var left := style.get_content_margin(SIDE_LEFT)
	var right := style.get_content_margin(SIDE_RIGHT)
	var available := maxf(0.0, size.x - left - right)
	var width := minf(available, get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x)
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		left += (available - width) * 0.5
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		left += available - width
	return Rect2(Vector2(left, size.y - 1), Vector2(width * _hover, 1))

func _draw() -> void:
	if _hover > 0.005 and not get_parent().has_method("navigation_indicator"):
		var line := selection_line_rect()
		draw_line(line.position, line.position + Vector2(line.size.x, 0), Color(0.40, 0.25, 0.23, _hover), 1.0)
