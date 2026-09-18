extends Window

const ACTIONS := {"move_forward": "Вперёд", "move_backward": "Назад", "move_left": "Влево", "move_right": "Вправо", "jump": "Прыжок", "sprint": "Бег", "crouch": "Приседание", "interact": "Взаимодействие / перенос", "weapon_attack": "Атака", "flashlight": "Фонарик", "replace_battery": "Перезарядка / батарейка", "drop_item": "Бросить предмет", "journal": "Журнал", "pause": "Меню"}
var defaults: Dictionary = {}
var bindings: Dictionary = {}
var waiting := ""

func _ready() -> void:
	close_requested.connect(hide)
	$Margin/Box/Close.pressed.connect(hide)
	$Margin/Box/Bind.pressed.connect(func():
		var selection: PackedInt32Array = $Margin/Box/List.get_selected_items()
		if not selection.is_empty():
			waiting = ACTIONS.keys()[selection[0]]
			$Margin/Box/Bind.text = "Новая клавиша…"
	)
	$Margin/Box/Reset.pressed.connect(reset_bindings)
	visibility_changed.connect(func(): waiting = "")
	_initialize.call_deferred()

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
	if config.load("user://controls.cfg") == OK:
		bindings = config.get_value("input", "bindings", {})
		for action in bindings:
			if ACTIONS.has(action):
				apply_binding(action, event_from_data(bindings[action]))
	refresh()

func show_settings() -> void:
	refresh()
	popup_centered()

func refresh() -> void:
	$Margin/Box/List.clear()
	for action in ACTIONS:
		var keys: PackedStringArray = []
		for event in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				keys.append(event.as_text().replace(" (Physical)", ""))
		$Margin/Box/List.add_item("%s — %s" % [ACTIONS[action], " / ".join(keys)])
	$Margin/Box/Controller.text = get_node("/root/SteamInput").get_controls_hint()
	$Margin/Box/Bind.text = "Назначить клавишу"

func _input(event: InputEvent) -> void:
	if not visible or waiting.is_empty() or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		waiting = ""
		refresh()
		set_input_as_handled()
		return
	if not event is InputEventKey and not event is InputEventMouseButton:
		return
	var data := {"key": int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)} if event is InputEventKey else {"mouse": int(event.button_index)}
	# Swap conflicting bindings, keeping every action accessible.
	var previous: InputEvent
	for old in InputMap.action_get_events(waiting):
		if old is InputEventKey or old is InputEventMouseButton:
			previous = old
			break
	for action in ACTIONS:
		if action != waiting and InputMap.action_has_event(action, event) and previous != null:
			var old_data := {"key": int(previous.physical_keycode if previous.physical_keycode != 0 else previous.keycode)} if previous is InputEventKey else {"mouse": int(previous.button_index)}
			bindings[action] = old_data
			apply_binding(action, event_from_data(old_data))
	bindings[waiting] = data
	apply_binding(waiting, event_from_data(data))
	waiting = ""
	save()
	refresh()
	set_input_as_handled()

func event_from_data(data: Dictionary) -> InputEvent:
	if data.has("key"):
		var event := InputEventKey.new()
		event.physical_keycode = int(data.key)
		return event
	var event := InputEventMouseButton.new()
	event.button_index = int(data.get("mouse", MOUSE_BUTTON_LEFT))
	return event

func apply_binding(action: String, event: InputEvent) -> void:
	for old in InputMap.action_get_events(action):
		if old is InputEventKey or old is InputEventMouseButton:
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)

func reset_bindings() -> void:
	for action in defaults:
		InputMap.action_erase_events(action)
		for event in defaults[action]:
			InputMap.action_add_event(action, event)
	bindings.clear()
	save()
	refresh()

func save() -> void:
	var config := ConfigFile.new()
	config.set_value("input", "bindings", bindings)
	config.save("user://controls.cfg")
