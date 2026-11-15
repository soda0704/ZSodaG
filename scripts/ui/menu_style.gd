class_name NorthernMenuStyle
extends RefCounted
## Shared native presentation for Menu, ESC_MENU and LOBBY_MENU.

const TEXT := Color("eeeeee")
const MUTED := Color("b5b5b5")
const ACCENT := Color.WHITE
const RULE := Color(0.83, 0.89, 0.93, 0.14)
const SURFACE := Color.BLACK
const ENTER_SECONDS := 0.24
const EXIT_SECONDS := 0.16
const HOVER_SECONDS := 0.12
const PRESS_SECONDS := 0.10
const RELEASE_SECONDS := 0.15
const MARKER_SECONDS := 0.14
const CATEGORY_EXIT_SECONDS := 0.10
const CATEGORY_ENTER_SECONDS := 0.18
const MODAL_SECONDS := 0.25
const STAGGER_SECONDS := 0.035
static var _ease_samples := PackedFloat32Array()
const LASER_CURSOR = preload("res://scripts/ui/cursor/menu_laser_cursor.gd")
static var _cursor: CanvasLayer
static var reduced_motion := false
static var keyboard_navigation := false
static var touch_navigation := false

static func fill(control: Control) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func label(text: String, font_size: int = 23, color: Color = TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return node

static func button(text: String, callback: Callable = Callable(), font_size: int = 18) -> Button:
	var node := Button.new()
	node.text = text.to_upper()
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.add_theme_font_size_override("font_size", font_size)
	node.custom_minimum_size.y = 44
	node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	node.set_script(preload("res://scripts/ui/menu_button.gd"))
	if callback.is_valid():
		node.pressed.connect(callback)
	return node

static func ease(value: float) -> float:
	if _ease_samples.is_empty():
		_ease_samples.resize(257)
		for index in 257: _ease_samples[index] = _bezier_ease(index / 256.0)
	var sample := clampf(value, 0.0, 1.0) * 256.0
	var index := mini(int(sample), 255)
	return lerpf(_ease_samples[index], _ease_samples[index + 1], sample - index)

static func _bezier_ease(value: float) -> float:
	# Emil's strong ease-out: cubic-bezier(.23,1,.32,1).
	if value <= 0.0 or value >= 1.0: return value
	var low := 0.0
	var high := 1.0
	var parameter := value
	for iteration in 12:
		var x := 3 * (1 - parameter) * (1 - parameter) * parameter * 0.23 + 3 * (1 - parameter) * parameter * parameter * 0.32 + parameter * parameter * parameter
		if x < value:
			low = parameter
		else:
			high = parameter
		parameter = (low + high) * 0.5
	return 3 * (1 - parameter) * (1 - parameter) * parameter + 3 * (1 - parameter) * parameter * parameter + parameter * parameter * parameter

static func gap(parent: Node, height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size.y = height
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

static func rule(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = RULE
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

static func install_cursor(parent: Node) -> void:
	if is_instance_valid(_cursor):
		return
	var cursor := LASER_CURSOR.new()
	cursor.reduced_motion = func() -> bool: return reduced_motion
	cursor.touch_navigation = func() -> bool: return touch_navigation
	_cursor = cursor
	parent.add_child(cursor)

static func uninstall_cursor() -> void:
	if not is_instance_valid(_cursor):
		return
	# Restore native shapes and release GPU resources before renderer shutdown.
	_cursor.free()
	_cursor = null

static func cursor_image() -> Image:
	return LASER_CURSOR.fallback_image()
