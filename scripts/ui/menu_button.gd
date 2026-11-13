extends Button
## Feedback never changes layout bounds or delays native activation.
var _hover := 0.0
var _press := 0.0
func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	var pointer_hover := is_hovered() and not NorthernMenuStyle.touch_navigation
	var target := 1.0 if not disabled and (pointer_hover or has_focus() or (toggle_mode and button_pressed)) else 0.0
	var previous := Vector2(_hover, _press)
	var pressed := 1.0 if is_pressed() and not toggle_mode else 0.0
	if NorthernMenuStyle.keyboard_navigation:
		_hover = target
		_press = pressed
	else:
		_hover = lerpf(_hover, target, 1.0 - exp(-delta * 3.0 / NorthernMenuStyle.HOVER_SECONDS))
		var response := NorthernMenuStyle.PRESS_SECONDS if pressed > _press else NorthernMenuStyle.RELEASE_SECONDS
		_press = lerpf(_press, pressed, 1.0 - exp(-delta * 3.0 / response))
	if absf(_hover - target) < .001: _hover = target
	if absf(_press - pressed) < .001: _press = pressed
	self_modulate.a = 1.0 - .15 * _press
	if previous != Vector2(_hover, _press): queue_redraw()
func selection_line_rect() -> Rect2:
	var style := get_theme_stylebox("normal")
	var left := style.get_content_margin(SIDE_LEFT)
	var available := maxf(0.0, size.x - left - style.get_content_margin(SIDE_RIGHT))
	var width := minf(available, get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x)
	if alignment == HORIZONTAL_ALIGNMENT_CENTER: left += (available - width) * 0.5
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT: left += available - width
	return Rect2(Vector2(left, size.y - 2), Vector2(width * _hover, 1))
func _draw() -> void:
	if _hover <= 0.0: return
	var ink := NorthernMenuStyle.ACCENT
	ink.a = _hover * .78
	draw_rect(Rect2(Vector2.ZERO, size), Color(.83, .89, .93, .025 * _hover + .025 * _press))
	if theme_type_variation == &"MenuStepperPart": return
	if theme_type_variation == &"MenuSection":
		if has_focus(): draw_rect(Rect2(Vector2.ZERO, size), Color(.83,.89,.93,.4), false, 1.0)
		return
	if theme_type_variation in [&"MenuNav", &"MenuEscapeNav"]:
		draw_rect(Rect2(Vector2(0, 15), Vector2(1 + _press, maxf(0, size.y - 30))), ink)
	elif theme_type_variation != &"MenuPrimary":
		var line := selection_line_rect()
		draw_line(line.position, line.end, ink, 1.0)
