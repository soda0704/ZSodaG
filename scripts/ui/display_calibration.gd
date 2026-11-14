extends Control
## A separate display-calibrated viewport keeps UI text and black reference neutral.
signal finished(accepted: bool)
const GRAPHICS = preload("res://scripts/ui/graphics_quality.gd")
const LOGO = preload("res://assets/ui/branding/releases/northernlab-logo-v1/northernlab-512.png")
const HUD_PREVIEW = preload("res://scripts/ui/calibration_hud_preview.gd")
const KEYS := ["DisplayWhitePoint", "DisplayBlackPoint", "Gamma", "HUDMargin"]
const TITLES := ["СВЕТЛЫЕ УЧАСТКИ", "ТЁМНЫЕ УЧАСТКИ", "ОБЩАЯ ЯРКОСТЬ", "ГРАНИЦЫ ИНТЕРФЕЙСА"]
const LOW := [85, -10, 70, 0]
const HIGH := [115, 10, 150, 10]
var draft: Dictionary = {}
var step := 0
var startup := false
var busy := false
var _menu: Node
var _footer: HBoxContainer
var _content: VBoxContainer
var _heading: Label
var _hint: Label
var _preview_holder: Control
var _preview: TextureRect
var _viewport: SubViewport
var _environment: Environment
var _surface: StandardMaterial3D
var _quad: QuadMesh
var _slider: HSlider
var _back: Button
var _next: Button
var _reset: Button
var _hud_preview: Control
var _patterns: Array[Texture2D] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	NorthernMenuStyle.fill(backdrop)
	add_child(backdrop)
	var margins := MarginContainer.new()
	NorthernMenuStyle.fill(margins)
	for side in ["left", "right"]: margins.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]: margins.add_theme_constant_override("margin_" + side, 36)
	add_child(margins)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margins.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	column.add_child(header)
	var logo := TextureRect.new()
	logo.texture = LOGO
	logo.custom_minimum_size = Vector2(64, 64)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(logo)
	var center := CenterContainer.new()
	center.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(center)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 18)
	center.add_child(_content)
	_heading = NorthernMenuStyle.label("", 34)
	_heading.theme_type_variation = &"MenuTitle"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_heading)
	_preview_holder = Control.new()
	_preview_holder.custom_minimum_size.y = 300
	_content.add_child(_preview_holder)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.mouse_filter = MOUSE_FILTER_IGNORE
	_preview_holder.add_child(_preview)
	_create_viewport()
	_hud_preview = HUD_PREVIEW.new()
	add_child(_hud_preview)
	move_child(_hud_preview, 1)
	NorthernMenuStyle.fill(_hud_preview)
	_hint = NorthernMenuStyle.label("", 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_hint)
	_slider = HSlider.new()
	_slider.theme_type_variation = &"CalibrationSlider"
	_slider.custom_minimum_size.y = 32
	_slider.step = 1
	_slider.value_changed.connect(_changed)
	_content.add_child(_slider)
	var footer := HBoxContainer.new()
	_footer = footer
	column.add_child(footer)
	_back = NorthernMenuStyle.button("Назад", go_back, 18)
	_back.theme_type_variation = &"CalibrationAction"
	footer.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_reset = NorthernMenuStyle.button("Сбросить", reset_current, 18)
	_reset.theme_type_variation = &"CalibrationAction"
	footer.add_child(_reset)
	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	footer.add_child(right_spacer)
	_next = NorthernMenuStyle.button("Далее", advance, 18)
	_next.theme_type_variation = &"CalibrationPrimary"
	_next.set_meta("priority_accent", true)
	_next.custom_minimum_size.x = 160
	footer.add_child(_next)
	_patterns.assign([_make_pattern(true), _make_pattern(false), _make_tonal_pattern()])
	resized.connect(_layout)
	_preview_holder.resized.connect(_layout_preview)
	_layout.call_deferred()

func _create_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.set_meta("ui_presentation", true)
	_viewport.world_3d = World3D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color.BLACK
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = _environment
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position.z = 2.0
	_viewport.add_child(camera)
	var mesh := MeshInstance3D.new()
	_quad = QuadMesh.new()
	mesh.mesh = _quad
	_surface = StandardMaterial3D.new()
	_surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = _surface
	_viewport.add_child(mesh)
	_preview.texture = _viewport.get_texture()

func _make_pattern(light: bool) -> Texture2D:
	var image := Image.create(1536, 512, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE if light else Color.BLACK)
	var logo: Image = LOGO.get_image()
	logo.convert(Image.FORMAT_RGBA8)
	logo.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var contrasts := PackedFloat32Array([0.01, 0.035, 0.16] if light else [0.025, 0.055, 0.18])
	for y in 512:
		for x in 512:
			var mark: Color = logo.get_pixel(x, y)
			if mark.a == 0.0: continue
			var ink := mark.a * mark.get_luminance()
			for index in 3:
				var contrast: float = contrasts[index]
				var shade := 1.0 - contrast * ink if light else contrast * ink
				image.set_pixel(index * 512 + x, y, Color(shade, shade, shade, 1))
	return ImageTexture.create_from_image(image)

func configure(menu: Node, initial: Dictionary, first_launch: bool) -> void:
	_menu = menu
	draft = GRAPHICS.normalized(initial)
	startup = first_launch
	_show_step()
	_set_busy(true)
	_reveal()

func _layout() -> void:
	_content.custom_minimum_size.x = minf(940.0, maxf(320.0, size.x - 128.0))
	_preview_holder.custom_minimum_size.y = clampf(size.y * .38, 180, 380)
	_layout_preview()

func _layout_preview() -> void:
	if _viewport == null: return
	var ratio := 3.0
	var height := minf(_preview_holder.size.y, _preview_holder.size.x / ratio)
	_preview.size = Vector2(height * ratio, height)
	_preview.position = (_preview_holder.size - _preview.size) * .5
	_viewport.size = Vector2i(1536, 512)
	_quad.size = Vector2(2.0 * ratio, 2.0)

func _show_step() -> void:
	_heading.text = TITLES[step]
	_hint.text = ["Левый символ не виден, средний едва заметен, правый хорошо виден.", "Левый символ не виден, средний едва заметен, правый хорошо виден.", "Все оттенки различимы, переходы плавные.", "Углы и элементы интерфейса должны быть полностью видны."][step]
	_slider.set_block_signals(true)
	_slider.step = 10 if step == 2 else 1
	_slider.min_value = LOW[step]
	_slider.max_value = HIGH[step]
	_slider.value = draft[KEYS[step]]
	_slider.set_block_signals(false)
	_back.text = "ОТМЕНА" if step == 0 and not startup else "НАЗАД"
	_back.disabled = step == 0 and startup
	_next.text = "СОХРАНИТЬ" if step == 3 else "ДАЛЕЕ"
	_wire_focus()
	_preview.visible = step != 3
	_hud_preview.visible = step == 3
	if step < 3: _surface.albedo_texture = _patterns[step]
	_surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_refresh_preview()
	_layout_preview()
	_slider.grab_focus()

func _changed(value: float) -> void:
	draft[KEYS[step]] = roundi(value)
	_refresh_preview()

func _refresh_preview() -> void:
	_menu.get_node("GraphicsQuality").apply_display_calibration(_environment, draft)
	_hud_preview.margin_percent = float(draft.HUDMargin)
	_hud_preview.queue_redraw()

func _wire_focus() -> void:
	var first := _reset if _back.disabled else _back
	_slider.focus_next = first.get_path()
	_slider.focus_previous = _next.get_path()
	_slider.focus_neighbor_bottom = _next.get_path()
	_slider.focus_neighbor_top = _next.get_path()
	_back.focus_next = _reset.get_path()
	_back.focus_previous = _slider.get_path()
	_reset.focus_next = _next.get_path()
	_reset.focus_previous = _slider.get_path() if _back.disabled else _back.get_path()
	_next.focus_next = _slider.get_path()
	_next.focus_previous = _reset.get_path()
	_back.focus_neighbor_left = _next.get_path()
	_back.focus_neighbor_right = _reset.get_path()
	_reset.focus_neighbor_left = _next.get_path() if _back.disabled else _back.get_path()
	_reset.focus_neighbor_right = _next.get_path()
	_next.focus_neighbor_left = _reset.get_path()
	_next.focus_neighbor_right = first.get_path()
	for button in [_back, _reset, _next]:
		button.focus_neighbor_top = _slider.get_path()
		button.focus_neighbor_bottom = _slider.get_path()

func _set_busy(value: bool) -> void:
	busy = value
	_slider.editable = not value
	_next.disabled = value
	_reset.disabled = value
	_back.disabled = value or (step == 0 and startup)

func _fade_out() -> void:
	var duration := .10 if NorthernMenuStyle.reduced_motion else .24
	var motion := create_tween().set_parallel(true)
	for node in [_content, _hud_preview, _footer]:
		motion.tween_property(node, "modulate:a", 0.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	await motion.finished

func _reveal() -> void:
	# Keep the opaque backdrop steady. Only presentation layers animate.
	_content.modulate.a = 1.0
	var duration := .10 if NorthernMenuStyle.reduced_motion else .42
	var delay := 0.0 if NorthernMenuStyle.reduced_motion else .05
	var motion := create_tween().set_parallel(true)
	for index in _content.get_child_count():
		var node := _content.get_child(index) as Control
		node.modulate.a = 0.0
		motion.tween_property(node, "modulate:a", 1.0, duration).set_delay(delay * index).set_custom_interpolator(NorthernMenuStyle.ease)
	_hud_preview.modulate.a = 0.0
	_footer.modulate.a = 0.0
	motion.tween_property(_hud_preview, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	motion.tween_property(_footer, "modulate:a", 1.0, duration).set_custom_interpolator(NorthernMenuStyle.ease)
	await motion.finished
	_set_busy(false)
	_slider.grab_focus()

func _change_step(next: int) -> void:
	if busy: return
	_set_busy(true)
	await _fade_out()
	step = next
	_show_step()
	_set_busy(true)
	# Present the new viewport texture before it becomes visible.
	await get_tree().process_frame
	_reveal()

func advance() -> void:
	if busy: return
	if step < 3:
		_change_step(step + 1)
		return
	if not _menu.commit_display_calibration(draft):
		_hint.text = "Не удалось сохранить. Повторите попытку."
		return
	_close(true)

func go_back() -> void:
	if busy: return
	if step > 0: _change_step(step - 1)
	elif not startup: _close(false)

func reset_current() -> void:
	if not busy: _slider.value = GRAPHICS.DEFAULTS[KEYS[step]]

func _close(accepted: bool) -> void:
	_set_busy(true)
	await _fade_out()
	finished.emit(accepted)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo(): return
	if event.is_action_pressed("ui_cancel"):
		go_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		advance()
		get_viewport().set_input_as_handled()

func _make_tonal_pattern() -> Texture2D:
	# Neutral luminance ramp and broad steps reveal clipping without scene exposure.
	var image := Image.create(1536, 512, false, Image.FORMAT_RGBA8)
	for x in 1536:
		var ramp := float(x) / 1535.0
		var band := float(mini(15, x / 96)) / 15.0
		for y in 512:
			var value := ramp if y < 240 else band
			image.set_pixel(x, y, Color(value, value, value))
	return ImageTexture.create_from_image(image)
