extends Button
## A selectable save entry; loading belongs to the page's explicit action.
var _hover_motion: Tween

func _ready() -> void:
	mouse_entered.connect(_animate_tint)
	mouse_exited.connect(_animate_tint)
	focus_entered.connect(_animate_tint)
	focus_exited.connect(_animate_tint)

func configure(index: int, title: String, point: Dictionary, is_latest: bool, empty_reason: String) -> void:
	%Number.text = "%02d" % (index + 1)
	%Kind.text = title
	%Latest.text = "ПОСЛЕДНЯЯ" if is_latest else ""
	disabled = point.is_empty()
	if disabled:
		%Day.text = empty_reason
		%Time.text = ""
	else:
		%Day.text = "ДЕНЬ %d" % int(point.day_index)
		%Time.text = saved_time(int(point.get("saved_at", 0)))
		%Power.text = "Питание базы включено" if point.main_breaker_on else "Питание базы отключено"
	%Power.visible = not disabled
	set_selected(false)

func set_selected(value: bool) -> void:
	set_pressed_no_signal(value)
	%Marker.visible = value
	var ink := Color("e0ddd3") if value else Color("c6c5bd")
	if disabled: ink = Color("919995")
	%Day.add_theme_color_override("font_color", ink)
	%Number.add_theme_color_override("font_color", Color("cfb598") if value else Color("777d7c"))
	%Power.add_theme_color_override("font_color", Color("a6aca8") if not disabled else Color("919995"))

	_animate_tint()

func _animate_tint() -> void:
	var target := .12 if button_pressed else .055 if not disabled and (is_hovered() or has_focus()) else 0.0
	if _hover_motion != null and _hover_motion.is_valid(): _hover_motion.kill()
	if is_equal_approx(%Tint.color.a, target): return
	_hover_motion = create_tween()
	_hover_motion.tween_property(%Tint, "color:a", target, .18).set_custom_interpolator(NorthernMenuStyle.ease)

static func saved_time(timestamp: int) -> String:
	if timestamp <= 0: return "Время не указано"
	var local := Time.get_datetime_dict_from_unix_time(timestamp + int(Time.get_time_zone_from_system().bias) * 60)
	return "%02d.%02d.%04d · %02d:%02d" % [local.day, local.month, local.year, local.hour, local.minute]
