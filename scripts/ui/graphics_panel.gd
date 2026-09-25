extends VBoxContainer
var menu: Node
func configure(owner_menu: Node) -> void:
	menu = owner_menu
	$Rows/Preset.item_selected.connect(_preset)
	var data: Dictionary = menu._settings_data.get("Graphics", {})
	var defaults: Dictionary = preload("res://scripts/ui/graphics_quality.gd").DEFAULTS
	for control in $Rows.get_children():
		var key := str(control.name)
		if not defaults.has(key):
			continue
		var value: Variant = data.get(key, defaults[key])
		if control is CheckButton:
			control.set_pressed_no_signal(bool(value))
			control.toggled.connect(func(v): _change(key, v))
		elif control is HBoxContainer:
			var slider: HSlider = control.get_node("Value")
			slider.set_value_no_signal(float(value))
			control.get_node("Number").text = str(value)
			slider.value_changed.connect(func(v):
				control.get_node("Number").text = str(int(v))
				_change(key, int(v)))

func _change(key: String, value: Variant) -> void:
	$Rows/Preset.select(0)
	var data: Dictionary = menu._settings_data.get("Graphics", {})
	data[key] = value
	menu._settings_data["Graphics"] = data
	menu.get_node("GraphicsQuality").apply(data)
	menu.save_settings_data()

func _preset(index: int) -> void:
	if index == 0: return
	var data: Dictionary = preload("res://scripts/ui/graphics_quality.gd").DEFAULTS.duplicate()
	if index == 1:
		data.merge({"Scale": 70, "SSAO": false, "SSR": false, "Glow": false, "LocalShadows": false, "ShadowDistance": 50, "LOD": 8, "TrackCount": 32, "VegetationDistance": 200}, true)
	elif index == 3:
		data.merge({"MSAA": 2, "FXAA": false, "SSAO": true, "SSR": true, "SSIL": true, "ShadowDistance": 220, "LOD": 1, "TrackCount": 256, "VegetationDistance": 700}, true)
	menu._settings_data["Graphics"] = data
	menu.get_node("GraphicsQuality").apply(data)
	menu.save_settings_data()
	for control in $Rows.get_children():
		var key := str(control.name)
		if not data.has(key): continue
		if control is CheckButton: control.set_pressed_no_signal(bool(data[key]))
		elif control is HBoxContainer:
			control.get_node("Value").set_value_no_signal(float(data[key]))
			control.get_node("Number").text = str(data[key])
