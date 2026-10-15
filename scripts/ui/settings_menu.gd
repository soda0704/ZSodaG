class_name NorthernSettingsMenu
extends VBoxContainer

signal back_requested
const CATEGORIES := ["Экран", "Качество", "Звук", "Управление"]
const QUALITY := [
	["Scale", "Масштаб 3D", 50, 100, 5, "%"],
	["MSAA", "Сглаживание MSAA", ["Выкл.", "×2", "×4", "×8"], [0, 1, 2, 3]],
	["FXAA", "Сглаживание FXAA"], ["FPS", "Ограничение кадров", ["Без ограничения", "30", "60", "90", "120", "144", "165", "240"], [0, 30, 60, 90, 120, 144, 165, 240]],
	["LOD", "Упрощение моделей", 1, 8, 1, ""],
	["ShadowQuality", "Качество теней", ["Низкое", "Среднее", "Высокое"], [1, 2, 3]],
	["ShadowDistance", "Дальность теней солнца", 24, 96, 8, " м"],
	["AOQuality", "Затенение в углах · SSAO", ["Выкл.", "Низкое", "Среднее", "Высокое"], [0, 1, 2, 3]],
	["FogQuality", "Объёмный туман", ["Выкл.", "Низкое", "Среднее", "Высокое"], [0, 1, 2, 3]],
	["GIQuality", "Отражённый свет · VoxelGI", ["Низкое", "Среднее", "Высокое"], [1, 2, 3]],
	["Bloom", "Свечение источников света"],
	["DecalDistance", "Дальность следов и крови", 10, 70, 5, " м"],
	["TrackCount", "Следы на снегу", 32, 512, 32, ""],
	["VegetationDistance", "Дальность деревьев и камней", 150, 750, 50, " м"],
]
const AUDIO := [["MasterVolume", "Общая громкость"], ["MusicVolume", "Музыка"], ["EffectsVolume", "Взаимодействия"], ["WeaponsVolume", "Оружие"], ["VehiclesVolume", "Транспорт"], ["MachineryVolume", "Механизмы"], ["AmbienceVolume", "Окружение"], ["BreathingVolume", "Дыхание"], ["RoomReverb", "Реверберация помещений"]]
var draft: Dictionary = {}
var draft_bindings: Dictionary = {}
var original_bindings: Dictionary = {}
var category := 0
var waiting := ""
var rows: VBoxContainer
var scroll: ScrollContainer
var description: Label
var title: Label
var apply_button: Button
var controls: NorthernControlSettings
var shell: NorthernMenuShell
var _menu: Node
var _persist_failed := false

func configure(menu: Node, owner_shell: NorthernMenuShell) -> void:
	_menu = menu
	shell = owner_shell
	controls = menu.get_node("ControlSettings")
	draft = menu._settings_data.duplicate(true)
	var graphics: Dictionary = preload("res://scripts/ui/graphics_quality.gd").normalized(draft.get("Graphics", {}))
	draft["Graphics"] = graphics
	original_bindings = controls.current_bindings()
	draft_bindings = original_bindings.duplicate(true)
	add_theme_constant_override("separation", 0)
	title = NorthernMenuStyle.label("НАСТРОЙКИ ЭКРАНА", 36)
	title.theme_type_variation = &"MenuTitle"
	add_child(title)
	title.hide()
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	# Keep the centered hover enlargement inside the scroll viewport on both sides.
	var hover_inset := MarginContainer.new()
	hover_inset.name = "HoverInset"
	hover_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		hover_inset.add_theme_constant_override("margin_" + side, 12)
	for side in ["top", "bottom"]:
		hover_inset.add_theme_constant_override("margin_" + side, 4)
	scroll.add_child(hover_inset)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 5)
	hover_inset.add_child(rows)
	NorthernMenuStyle.rule(self)
	description = NorthernMenuStyle.label("Изменения вступят в силу после применения.", 18, NorthernMenuStyle.MUTED)
	description.custom_minimum_size.y = 132
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	_build_navigation()
	select_category(0)

func _build_navigation() -> void:
	shell.clear(shell.header)
	shell.clear(shell.footer)
	for index in CATEGORIES.size():
		shell.header.add_child(NorthernMenuStyle.button(CATEGORIES[index], func(): shell.transition(select_category.bind(index), true), 20))
	shell.footer.add_child(NorthernMenuStyle.label("NORTHERNLAB / НАСТРОЙКИ", 17, NorthernMenuStyle.MUTED))
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.footer.add_child(space)
	shell.footer.add_child(NorthernMenuStyle.button("По умолчанию", reset_category, 15))
	apply_button = NorthernMenuStyle.button("Применить", apply, 15)
	shell.footer.add_child(apply_button)
	shell.footer.add_child(NorthernMenuStyle.button("ESC  Назад", request_back, 15))

func select_category(index: int) -> void:
	waiting = ""
	category = index
	shell.clear(rows)
	scroll.scroll_vertical = 0
	title.text = "НАСТРОЙКИ / " + CATEGORIES[index].to_upper()
	for i in shell.header.get_child_count():
		shell.header.get_child(i).modulate = Color.WHITE if i == index else Color(0.68, 0.68, 0.65)
	match index:
		0:
			var resolutions: Array = []
			var values: Array = []
			for resolution in _menu.RESOLUTIONS:
				resolutions.append("%d × %d" % [resolution.x, resolution.y])
				values.append(_menu.resolution_to_text(resolution))
			_choice("Resolution", "Разрешение", resolutions, values)
			_choice("WindowMode", "Режим экрана", ["Полный экран", "Оконный", "Развёрнутое окно"], ["fullscreen", "windowed", "maximized"])
			var monitors: Array = []
			var monitor_ids: Array = []
			for i in maxi(1, DisplayServer.get_screen_count()):
				monitors.append("Монитор %d" % [i + 1])
				monitor_ids.append(i)
			_choice("Screen", "Монитор", monitors, monitor_ids)
			_toggle("VSync", "Вертикальная синхронизация")
			_numeric("Brightness", "Яркость", 70, 140, 5, "%", true)
			_numeric("Gamma", "Гамма", 70, 150, 10, "%", true)
			_toggle("HDR", "HDR", true, not DisplayServer.window_is_hdr_output_supported())
			_numeric("HDRWhite", "Опорная яркость HDR", 100, 400, 20, " нит", true)
		1:
			_choice("Preset", "Общее качество", ["Свои настройки", "Низкое", "Среднее", "Высокое"], [0, 1, 2, 3], true)
			for spec in QUALITY:
				if spec.size() == 2:
					_toggle(spec[0], spec[1], true)
				elif spec.size() == 4:
					_choice(spec[0], spec[1], spec[2], spec[3], true)
				else:
					_numeric(spec[0], spec[1], spec[2], spec[3], spec[4], spec[5], true)
		2:
			for spec in AUDIO:
				_numeric(spec[0], spec[1], 0, 100, 1, "%")
		3:
			_numeric("MouseSensitivity", "Чувствительность мыши", 0.25, 2.5, 0.05, "×")
			for action in controls.ACTIONS:
				var row := _row(controls.ACTIONS[action])
				var text := controls.event_from_data(draft_bindings.get(action, {"key": 0})).as_text().replace(" (Physical)", "")
				var key_button := NorthernMenuStyle.button(text, func(): _wait_for_key(action), 22)
				key_button.name = action
				key_button.custom_minimum_size.x = 280
				row.add_child(key_button)
			var hint := NorthernMenuStyle.label(get_node("/root/SteamInput").get_controls_hint(), 20, NorthernMenuStyle.MUTED)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rows.add_child(hint)
	_changed()

func _row(text: String) -> HBoxContainer:
	var row := preload("res://scripts/ui/menu_setting_row.gd").new()
	row.custom_minimum_size.y = 62
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 18)
	var label := NorthernMenuStyle.label(text.to_upper(), 18, NorthernMenuStyle.MUTED)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	rows.add_child(row)
	row.mouse_entered.connect(func():
		description.text = text + " · Изменения вступят в силу после применения."
	)
	return row

func _get_value(key: String, graphics: bool) -> Variant:
	if key == "Preset": return preload("res://scripts/ui/graphics_quality.gd").preset_index(draft.Graphics)
	return draft.Graphics.get(key, 0) if graphics else draft.get(key, 0)

func _set_value(key: String, value: Variant, graphics: bool) -> void:
	if graphics:
		draft.Graphics[key] = value
	else:
		draft[key] = value
	_changed()

func _numeric(key: String, text: String, low: float, high: float, increment: float, unit: String, graphics: bool = false) -> void:
	var row := _row(text)
	var value := NorthernMenuValue.new()
	value.minimum = low
	value.maximum = high
	value.step = increment
	value.suffix = unit
	value.decimals = 2 if increment < 1 else 0
	value.value = float(_get_value(key, graphics))
	value.name = key
	row.add_child(value)
	value.value_changed.connect(func(next): _set_value(key, next, graphics); row.pulse())

func _choice(key: String, text: String, labels: Array, values: Array, graphics: bool = false) -> void:
	var row := _row(text)
	var option := OptionButton.new()
	option.name = key
	option.theme_type_variation = &"MenuChoice"
	option.custom_minimum_size.x = 330
	for item in labels:
		option.add_item(str(item).to_upper())
	option.select(maxi(values.find(_get_value(key, graphics)), 0))
	row.add_child(option)
	option.item_selected.connect(func(index):
		row.pulse()
		if key == "Preset":
			_preset(index)
		else:
			_set_value(key, values[index], graphics)
	)

func _toggle(key: String, text: String, graphics: bool = false, disabled: bool = false) -> void:
	var row := _row(text)
	var button := NorthernMenuStyle.button("Вкл." if bool(_get_value(key, graphics)) else "Выкл.", Callable(), 17)
	button.theme_type_variation = &"MenuToggle"
	button.custom_minimum_size.x = 280
	button.disabled = disabled
	button.tooltip_text = "Нужны HDR-дисплей и включённый HDR в Windows." if disabled else ""
	row.add_child(button)
	button.pressed.connect(func():
		row.pulse()
		_set_value(key, not bool(_get_value(key, graphics)), graphics)
		button.text = "ВКЛ." if bool(_get_value(key, graphics)) else "ВЫКЛ."
	)

func _preset(index: int) -> void:
	if index == 0:
		return
	var data: Dictionary = draft.Graphics.duplicate()
	data.merge(preload("res://scripts/ui/graphics_quality.gd").PRESETS[index], true)
	draft.Graphics = preload("res://scripts/ui/graphics_quality.gd").normalized(data)
	select_category(category)

func has_changes() -> bool:
	if _persist_failed: return true
	var applied: Dictionary = _menu._settings_data.duplicate(true)
	var graphics: Dictionary = preload("res://scripts/ui/graphics_quality.gd").normalized(applied.get("Graphics", {}))
	applied.Graphics = graphics
	return draft != applied or draft_bindings != original_bindings

func _changed() -> void:
	if apply_button != null:
		apply_button.disabled = not has_changes()
	if rows != null:
		var preset := rows.find_child("Preset", true, false) as OptionButton
		if preset != null: preset.select(preload("res://scripts/ui/graphics_quality.gd").preset_index(draft.Graphics))

func apply(show_notice: bool = true) -> bool:
	var previous: Dictionary = _menu._settings_data
	_menu._settings_data = draft.duplicate(true)
	var settings_saved: bool = _menu.save_settings_data()
	var controls_saved := false
	if settings_saved:
		_menu.apply_settings_data()
		controls_saved = controls.replace_bindings(draft_bindings)
	else:
		_menu._settings_data = previous
	if controls_saved: original_bindings = draft_bindings.duplicate(true)
	_persist_failed = not settings_saved or not controls_saved
	_changed()
	if _persist_failed:
		_menu.confirm("Не удалось сохранить настройки", "Запись на диск не удалась. Проверьте доступ к папке настроек и повторите «Применить».", [])
		return false
	if show_notice:
		_menu.confirm("Настройки применены", "Изменения сохранены.", [])
	return true

func reset_category() -> void:
	var defaults: Dictionary = _menu.default_settings_data()
	match category:
		0:
			for key in ["Resolution", "WindowMode", "Screen", "VSync"]:
				draft[key] = defaults[key]
			for key in ["Brightness", "Gamma", "HDR", "HDRWhite"]:
				draft.Graphics[key] = preload("res://scripts/ui/graphics_quality.gd").DEFAULTS[key]
		1:
			for spec in QUALITY:
				draft.Graphics[spec[0]] = preload("res://scripts/ui/graphics_quality.gd").DEFAULTS[spec[0]]
		2:
			for spec in AUDIO:
				draft[spec[0]] = defaults[spec[0]]
		3:
			draft.MouseSensitivity = 1.0
			draft_bindings = controls.default_bindings()
	select_category(category)

func request_back() -> void:
	if not waiting.is_empty():
		waiting = ""
		select_category(category)
		return
	if has_changes():
		_menu.confirm("Сохранить изменения?", "Параметры изменены, но ещё не применены.", [
			{"label": "Применить и выйти", "action": func():
				if apply(false): back_requested.emit()},
			{"label": "Не применять", "action": func(): back_requested.emit()},
		])
	else:
		back_requested.emit()

func _wait_for_key(action: String) -> void:
	waiting = action
	description.text = "Нажмите клавишу или кнопку мыши. Esc — отмена."

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _menu.dialog != null or shell.busy or waiting.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		waiting = ""
		select_category(category)
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey and not event is InputEventMouseButton:
		return
	var data := controls.data_from_event(event)
	var previous: Dictionary = draft_bindings.get(waiting, {})
	for action in draft_bindings:
		if action != waiting and draft_bindings[action] == data:
			draft_bindings[action] = previous
	draft_bindings[waiting] = data
	waiting = ""
	select_category(category)
	get_viewport().set_input_as_handled()
