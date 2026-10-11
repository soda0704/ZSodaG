class_name NorthernControlSettings
extends Node
## Input persistence, independent of the menu presentation.

const ACTIONS := {"move_forward": "Вперёд", "move_backward": "Назад", "move_left": "Влево", "move_right": "Вправо", "jump": "Прыжок", "sprint": "Бег", "crouch": "Приседание", "interact": "Взаимодействие / перенос", "weapon_attack": "Атака", "flashlight": "Фонарик", "replace_battery": "Перезарядка / батарейка", "drop_item": "Бросить предмет", "journal": "Журнал", "pause": "Меню"}
var defaults: Dictionary = {}
var bindings: Dictionary = {}

func _ready() -> void:
	_initialize.call_deferred()

func path() -> String:
	return str(ProjectSettings.get_setting("northern_lab/testing/controls_path", "user://controls.cfg"))

func _initialize() -> void:
	if not InputMap.has_action("weapon_attack"):
		InputMap.add_action("weapon_attack")
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("weapon_attack", mouse)
		var trigger := InputEventJoypadMotion.new()
		trigger.axis = JOY_AXIS_TRIGGER_RIGHT
		trigger.axis_value = 1.0
		InputMap.action_add_event("weapon_attack", trigger)
	for action in ACTIONS:
		defaults[action] = InputMap.action_get_events(action)
	var config := ConfigFile.new()
	if config.load(path()) == OK:
		var saved: Variant = config.get_value("input", "bindings", {})
		if saved is Dictionary:
			bindings = saved
			for action in bindings:
				if ACTIONS.has(action) and bindings[action] is Dictionary:
					apply_binding(action, event_from_data(bindings[action]))

func event_from_data(data: Dictionary) -> InputEvent:
	if data.has("key"):
		var key_event := InputEventKey.new()
		key_event.physical_keycode = int(data.key) as Key
		return key_event
	var mouse_event := InputEventMouseButton.new()
	mouse_event.button_index = int(data.get("mouse", MOUSE_BUTTON_LEFT)) as MouseButton
	return mouse_event

func data_from_event(event: InputEvent) -> Dictionary:
	return {"key": int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)} if event is InputEventKey else {"mouse": int(event.button_index)}

func current_bindings() -> Dictionary:
	var result := {}
	for action in ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				result[action] = data_from_event(event)
				break
	return result

func default_bindings() -> Dictionary:
	var result := {}
	for action in defaults:
		for event in defaults[action]:
			if event is InputEventKey or event is InputEventMouseButton:
				result[action] = data_from_event(event)
				break
	return result

func apply_binding(action: String, event: InputEvent) -> void:
	for old in InputMap.action_get_events(action):
		if old is InputEventKey or old is InputEventMouseButton:
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)

func replace_bindings(next: Dictionary) -> void:
	bindings = next.duplicate(true)
	for action in bindings:
		if ACTIONS.has(action):
			apply_binding(action, event_from_data(bindings[action]))
	var config := ConfigFile.new()
	config.set_value("input", "bindings", bindings)
	config.save(path())
