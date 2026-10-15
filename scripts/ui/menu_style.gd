class_name NorthernMenuStyle
extends RefCounted
## Shared native presentation for Menu, ESC_MENU and LOBBY_MENU.

const TEXT := Color("d3d1c9")
const MUTED := Color("a6a69f")
const ACCENT := Color("65413c")
const RULE := Color(0.72, 0.71, 0.65, 0.18)
static var _ease_samples := PackedFloat32Array()
static var _cursor: ImageTexture

static func make_theme() -> Theme:
	return preload("res://scenes/ui/menu_theme.tres")

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
	node.custom_minimum_size.y = 54
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
	# CSS cubic-bezier(.22,.8,.25,1) used by the approved previews.
	if value <= 0.0 or value >= 1.0: return value
	var low := 0.0
	var high := 1.0
	var parameter := value
	for iteration in 12:
		var x := 3 * (1 - parameter) * (1 - parameter) * parameter * 0.22 + 3 * (1 - parameter) * parameter * parameter * 0.25 + parameter * parameter * parameter
		if x < value:
			low = parameter
		else:
			high = parameter
		parameter = (low + high) * 0.5
	return 3 * (1 - parameter) * (1 - parameter) * parameter * 0.8 + 3 * (1 - parameter) * parameter * parameter + parameter * parameter * parameter

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

static func install_cursor() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _cursor == null: _cursor = ImageTexture.create_from_image(cursor_image())
	for shape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_HSIZE, Input.CURSOR_IBEAM, Input.CURSOR_DRAG]:
		Input.set_custom_mouse_cursor(_cursor, shape, Vector2(14, 14))

static func cursor_image() -> Image:
	var image := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var points: Array[Vector2i] = []
	for corner in [Vector2i(4, 4), Vector2i(23, 4), Vector2i(4, 23), Vector2i(23, 23)]:
		var sx := 1 if corner.x < 14 else -1
		var sy := 1 if corner.y < 14 else -1
		for i in 5:
			points.append(Vector2i(corner.x + i * sx, corner.y))
			points.append(Vector2i(corner.x, corner.y + i * sy))
	for x in range(13, 15):
		for y in range(13, 15): points.append(Vector2i(x, y))
	# The dark outline stays visible on paper; the ivory core stays visible at night.
	for point in points:
		for x in range(-1, 2):
			for y in range(-1, 2): image.set_pixelv(point + Vector2i(x, y), Color(0.025, 0.025, 0.022, 1.0))
	for point in points: image.set_pixelv(point, Color(0.94, 0.92, 0.86, 1.0))
	return image
