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
func _draw() -> void:
	if _hover <= 0.0 or disabled: return
	if theme_type_variation == &"MenuStepperPart":
		draw_rect(Rect2(Vector2.ZERO, size), Color(.83, .89, .93, .025 * _hover))
		return
	var accented := theme_type_variation in [&"MenuSection", &"MenuPrimary"] or bool(get_meta("priority_accent", false))
	if not accented:
		# Secondary actions receive a quiet hover, without a decorative stroke.
		draw_rect(Rect2(Vector2.ZERO, size), Color(.83, .89, .93, .025 * _hover + .025 * _press))
		return
	# Fixed UI length, independent of the label and the button's layout width.
	for index in 32:
		var fraction := index / 32.0
		draw_rect(Rect2(Vector2(1 + index * 3, 0), Vector2(3, size.y)), Color(.012, .018, .024, .28 * _hover * (1.0 - fraction) * (1.0 - fraction)))
	# Categories share one moving marker owned by NorthernSettingsMenu.
	if theme_type_variation == &"MenuSection": return
	var ink := NorthernMenuStyle.ACCENT
	ink.a = _hover * .78
	draw_line(Vector2(.5, 12), Vector2(.5, size.y - 12), ink, 1.0)
