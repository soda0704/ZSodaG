class_name NorthernMenuSettingRow
extends HBoxContainer

var _hover := 0.0
var _flash := 0.0

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	var focus := get_viewport().gui_get_focus_owner()
	var selected := get_global_rect().has_point(get_global_mouse_position()) or (focus != null and is_ancestor_of(focus))
	var previous_hover := _hover
	var previous_flash := _flash
	var target := 1.0 if selected else 0.0
	_hover = lerpf(_hover, target, 1.0 - exp(-delta * 14))
	if absf(_hover - target) < 0.001: _hover = target
	_flash = maxf(0, _flash - delta * 3)
	if pivot_offset != size * 0.5: pivot_offset = size * 0.5
	if not is_equal_approx(previous_hover, _hover): scale = Vector2.ONE * (1 + _hover * 0.012)
	if not is_equal_approx(previous_hover, _hover) or not is_equal_approx(previous_flash, _flash): queue_redraw()

func pulse() -> void:
	_flash = 1

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.075, 0.065, 0.12 + _hover * 0.10 + _flash * 0.08))
	draw_line(Vector2(0, size.y - 1), Vector2(size.x, size.y - 1), Color(0.72, 0.71, 0.65, 0.10 + _hover * 0.16), 1)
