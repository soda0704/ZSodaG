extends CanvasLayer
## Optical menu pointer. Never changes mouse mode or consumes GUI input.

const LASER_SHADER = preload("res://assets/shaders/ui/cursor/menu_laser_cursor.gdshader")
const CURSOR_SHAPES := [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_HSIZE, Input.CURSOR_IBEAM, Input.CURSOR_DRAG]
const TRAIL_COUNT := 8
const TRAIL_LIFETIME := 0.075
const QUAD_SIZE := Vector2(128, 128)

var reduced_motion: Callable
var touch_navigation: Callable
var _menu: Node
var _light: ColorRect
var _trail: Array[ColorRect] = []
var _history: Array[Vector3] = []
var _blank: ImageTexture
var _fallback: ImageTexture
var _animated := false
var _mouse_inside := true
var _focused := true
var _pointer := Vector2.ZERO
var _elapsed := 0.0
var _hover := 0.0
var _press := 0.0
var _held := false
var _click_age := 10.0
var _fade_in := 0.0
var _visual_scale := 1.0

func _ready() -> void:
	name = "MenuLaserCursor"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Update after normal menu transitions, even while gameplay is paused.
	process_priority = 100
	_menu = get_parent()
	_fallback = ImageTexture.create_from_image(fallback_image())
	var empty := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	empty.fill(Color.TRANSPARENT)
	_blank = ImageTexture.create_from_image(empty)
	for index in TRAIL_COUNT:
		var ghost := _make_light(true)
		ghost.hide()
		_trail.append(ghost)
	_light = _make_light(false)
	_light.hide()
	var window := get_window()
	_focused = window.has_focus()
	window.focus_entered.connect(_on_window_focus_entered)
	window.focus_exited.connect(_on_window_focus_exited)
	window.mouse_entered.connect(_on_mouse_entered)
	window.mouse_exited.connect(_on_mouse_exited)
	get_viewport().size_changed.connect(_resize_visuals)
	_resize_visuals()
	_pointer = get_viewport().get_mouse_position()
	_set_native_cursor(false)

func _make_light(is_trail: bool) -> ColorRect:
	var light := ColorRect.new()
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light.focus_mode = Control.FOCUS_NONE
	light.size = QUAD_SIZE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = LASER_SHADER
	shader_material.set_shader_parameter("afterimage", is_trail)
	light.material = shader_material
	add_child(light)
	return light

func _on_window_focus_exited() -> void:
	_focused = false
	if _animated:
		_set_animated(false)
	else:
		_clear_motion()

func _on_window_focus_entered() -> void:
	_focused = true

func _on_mouse_entered() -> void:
	_mouse_inside = true

func _on_mouse_exited() -> void:
	_mouse_inside = false
	_clear_motion()
	if _animated:
		_set_animated(false)

func _wants_animation() -> bool:
	if not _focused or not _mouse_inside or (touch_navigation.is_valid() and touch_navigation.call()):
		return false
	if Input.mouse_mode not in [Input.MOUSE_MODE_VISIBLE, Input.MOUSE_MODE_CONFINED]:
		return false
	var scene := get_tree().current_scene
	return _menu.is_menu_open() or _menu.is_display_calibration_open() or (scene != null and scene.scene_file_path == "res://scenes/ui/main_menu.tscn")

func _set_native_cursor(animated: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for shape in CURSOR_SHAPES:
		Input.set_custom_mouse_cursor(_blank if animated else _fallback, shape, Vector2.ZERO if animated else Vector2(31.5, 31.5))

func _set_animated(active: bool) -> void:
	if active == _animated:
		return
	_animated = active
	_clear_motion()
	if active:
		# Opening a menu may release/warp a previously captured gameplay mouse.
		_pointer = get_viewport().get_mouse_position()
		_light.position = _pointer - _light.size * 0.5
	_light.visible = active
	_set_native_cursor(active)

func _clear_motion() -> void:
	_history.clear()
	_held = false
	_press = 0.0
	_click_age = 10.0
	_hover = 0.0
	_fade_in = 0.0
	for ghost in _trail:
		ghost.hide()

func _input(event: InputEvent) -> void:
	if not _wants_animation():
		return
	_set_animated(true)
	if event is InputEventMouseMotion:
		# No smoothing of the actual pointer: smoothing applies only to light.
		_pointer = event.position
		if _light != null:
			_light.position = _pointer - _light.size * 0.5
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer = event.position
		_light.position = _pointer - _light.size * 0.5
		if event.pressed:
			_held = true
		elif _held:
			_held = false
			_click_age = 0.0

func _hovering_action() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control is BaseButton:
			return not control.disabled
		if control is Slider or control is ScrollBar:
			return control.editable if control is Slider else true
		if control is LineEdit or control is TextEdit:
			return control.editable
		control = control.get_parent_control()
	return false

func _process(delta: float) -> void:
	_set_animated(_wants_animation())
	if not _animated:
		return
	var quiet: bool = reduced_motion.is_valid() and reduced_motion.call()
	var dt := minf(delta, 0.1)
	_elapsed += delta
	_click_age += delta
	_fade_in = minf(1.0, _fade_in + dt / 0.08)
	_hover = lerpf(_hover, 1.0 if _hovering_action() else 0.0, 1.0 - exp(-dt / 0.13))
	_press = lerpf(_press, 1.0 if _held else 0.0, 1.0 - exp(-dt / (0.09 if _held else 0.12)))
	# MouseMotion is authoritative. Polling the OS here can overwrite a newer
	# viewport event (and breaks transformed or programmatically driven input).
	var current := _pointer
	# Warps and long stalls must not paint a streak across the entire menu.
	if quiet or delta > 0.1 or (not _history.is_empty() and current.distance_to(Vector2(_history[-1].x, _history[-1].y)) > 160.0):
		_history.clear()
	_pointer = current
	_light.position = _pointer - _light.size * 0.5
	_update_trail(quiet)
	var pulse := 0.0 if quiet else sin(_elapsed * TAU / 3.2) * 0.7 + sin(_elapsed * TAU / 1.6) * 0.3
	var click_progress := clampf(_click_age / 0.42, 0.0, 1.0)
	var flash := 0.0 if quiet else smoothstep(0.0, 0.10, click_progress) * (1.0 - smoothstep(0.10, 0.65, click_progress)) * 0.45
	var afterglow := 0.0 if quiet else smoothstep(0.0, 0.16, click_progress) * (1.0 - smoothstep(0.22, 1.0, click_progress))
	var shader_material := _light.material as ShaderMaterial
	shader_material.set_shader_parameter("energy", (0.90 + 0.025 * pulse + _hover * 0.22 + flash * 0.55 - _press * 0.08) * _fade_in)
	shader_material.set_shader_parameter("click_wave", 0.0 if quiet else 1.0 - pow(1.0 - click_progress, 3.0))
	shader_material.set_shader_parameter("click_strength", 0.0 if quiet else afterglow)
	shader_material.set_shader_parameter("spread", 1.0 + _hover * 0.10 + afterglow * 0.12 - _press * 0.12)

func _update_trail(quiet: bool) -> void:
	while not _history.is_empty() and _elapsed - _history[0].z > TRAIL_LIFETIME:
		_history.pop_front()
	for index in TRAIL_COUNT:
		var ghost := _trail[index]
		ghost.hide()
		if quiet or index >= _history.size(): continue
		var sample_index := _history.size() - 1 - index
		var sample := _history[sample_index]
		var start := Vector2(sample.x, sample.y)
		var end := _pointer if sample_index == _history.size() - 1 else Vector2(_history[sample_index + 1].x, _history[sample_index + 1].y)
		var distance := start.distance_to(end)
		if distance < 0.5: continue
		var age := maxf(0.0, _elapsed - sample.z)
		ghost.size = Vector2(distance + 64.0 * _visual_scale, 64.0 * _visual_scale)
		ghost.pivot_offset = ghost.size * 0.5
		ghost.position = (start + end) * 0.5 - ghost.size * 0.5
		ghost.rotation = (end - start).angle()
		var material := ghost.material as ShaderMaterial
		material.set_shader_parameter("trail_extent", ghost.size / _visual_scale)
		material.set_shader_parameter("segment_length", distance / _visual_scale)
		material.set_shader_parameter("energy", pow(maxf(0.0, 1.0 - age / TRAIL_LIFETIME), 1.8) * 0.24 * _fade_in)
		ghost.show()
	if not quiet and (_history.is_empty() or Vector2(_history[-1].x, _history[-1].y).distance_to(_pointer) >= 0.5):
		_history.append(Vector3(_pointer.x, _pointer.y, _elapsed))
		if _history.size() > TRAIL_COUNT: _history.pop_front()

func _resize_visuals() -> void:
	# Draw in viewport coordinates, matching GUI hit testing even with UI scaling.
	_visual_scale = 1.25 * clampf(get_viewport().get_visible_rect().size.x / 1920.0, 0.9, 1.4)
	for light in _trail + [_light]:
		light.size = QUAD_SIZE * _visual_scale
	_pointer = get_viewport().get_mouse_position()
	_clear_motion()
	_light.position = _pointer - _light.size * 0.5

func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless":
		for shape in CURSOR_SHAPES:
			Input.set_custom_mouse_cursor(null, shape)
	_blank = null
	_fallback = null

static func fallback_image() -> Image:
	# Static optical pointer for other visible-mouse screens and native fallback.
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var radius_squared := Vector2(x - 31.5, y - 31.5).length_squared()
			var radius := sqrt(radius_squared)
			var core := 1.0 - smoothstep(1.1, 2.1, radius)
			var halo := exp(-radius_squared / 12.5) * 0.38
			var color := Color(1.0, 0.16, 0.065)
			color = color.lerp(Color(1.0, 0.93, 0.83), core)
			color.a = lerpf(clampf(halo, 0.0, 1.0), 1.0, core)
			image.set_pixel(x, y, color)
	return image

