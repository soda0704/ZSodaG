extends Container
## One continuous underline follows selection, as in the approved concept.
var _rect := Rect2()
var _selected: Button

func navigation_indicator() -> void:
	pass

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	for child in get_children():
		if child is Button and not child.disabled and child.is_hovered():
			_selected = child
			break
		if child == focused:
			_selected = child
	if not is_instance_valid(_selected):
		return
	var font := _selected.get_theme_font("font")
	var style := _selected.get_theme_stylebox("normal")
	var width := font.get_string_size(_selected.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _selected.get_theme_font_size("font_size")).x + style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	var target := Rect2(_selected.position.x, _selected.position.y + _selected.size.y - 1, width, 1)
	if _rect.size.x == 0:
		_rect = target
		queue_redraw()
	if _rect.position.distance_to(target.position) < 0.1 and absf(_rect.size.x - target.size.x) < 0.1:
		_rect = target
		return
	_rect.position = _rect.position.lerp(target.position, 1 - exp(-delta * 15))
	_rect.size = _rect.size.lerp(target.size, 1 - exp(-delta * 15))
	queue_redraw()

func _draw() -> void:
	for index in 24:
		var from := _rect.position + Vector2(_rect.size.x * index / 24.0, 0)
		var to := _rect.position + Vector2(_rect.size.x * (index + 1) / 24.0, 0)
		draw_line(from, to, Color(0.396, 0.255, 0.235, 1.0 - index / 24.0), 1)
