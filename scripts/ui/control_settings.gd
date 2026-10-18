class_name NorthernControlSettings
extends Node
## Input persistence, independent of the menu presentation.

const ACTIONS := {"move_forward": "Вперёд", "move_backward": "Назад", "move_left": "Влево", "move_right": "Вправо", "jump": "Прыжок", "sprint": "Бег", "crouch": "Приседание", "interact": "Взаимодействие / перенос", "weapon_attack": "Атака", "weapon_aim": "Прицеливание", "flashlight": "Фонарик", "replace_battery": "Перезарядка / батарейка", "drop_item": "Бросить предмет", "journal": "Журнал", "pause": "Меню", "tester_feedback": "Отчёт об ошибке"}
const FIXED_BINDINGS := {"pause": {"key": KEY_ESCAPE}}
var repaired_on_load := false
var defaults: Dictionary = {}
var bindings: Dictionary = {}

func _ready() -> void:
	_initialize.call_deferred()

func path() -> String:
	return str(ProjectSettings.get_setting("northern_lab/testing/controls_path", "user://controls.cfg"))

func _initialize() -> void:
	repaired_on_load = false
	if defaults.is_empty():
		for action in ACTIONS:
			defaults[action] = InputMap.action_get_events(action)
	var config := ConfigFile.new()
	if config.load(path()) == OK:
		var saved: Variant = config.get_value("input", "bindings", {})
		if saved is Dictionary:
			bindings = normalized_saved_bindings(saved)
			if repaired_on_load: _store_bindings(bindings)
			for action in ACTIONS:
				apply_binding(action, event_from_data(bindings[action]))

func binding_error(action: String, data: Dictionary) -> String:
	if not ACTIONS.has(action): return "Неизвестное действие."
	if data.size() != 1: return "Выберите клавишу или кнопку мыши."
	if data.has("key"):
		if not data.key is int or int(data.key) <= 0: return "Некорректная клавиша."
		if int(data.key) in [KEY_QUOTELEFT, 126, 1105, 1025]: return "Эта клавиша зарезервирована для консоли."
		if int(data.key) == KEY_ESCAPE and action != "pause": return "Esc зарезервирован для меню и отмены."
	elif data.has("mouse"):
		if not data.mouse is int or int(data.mouse) < MOUSE_BUTTON_LEFT or int(data.mouse) > MOUSE_BUTTON_XBUTTON2: return "Некорректная кнопка мыши."
		if action == "tester_feedback": return "Для отчёта об ошибке выберите клавишу клавиатуры."
	else: return "Выберите клавишу или кнопку мыши."
	if FIXED_BINDINGS.has(action) and data != FIXED_BINDINGS[action]: return "Esc всегда открывает меню."
	return ""

func conflicting_action(action: String, data: Dictionary, candidate: Dictionary) -> String:
	for other in ACTIONS:
		if other != action and candidate.get(other, {}) == data: return other
	return ""

func validation_error(candidate: Dictionary) -> String:
	for action in ACTIONS:
		if not candidate.get(action) is Dictionary: return "Не назначена кнопка: " + ACTIONS[action]
		var error := binding_error(action, candidate[action])
		if not error.is_empty(): return error
		var conflict := conflicting_action(action, candidate[action], candidate)
		if not conflict.is_empty(): return "Кнопка уже назначена: " + ACTIONS[conflict]
	return ""

func normalized_saved_bindings(saved: Dictionary) -> Dictionary:
	var result := default_bindings()
	for action in ACTIONS:
		if not saved.has(action): continue
		if saved[action] is Dictionary and binding_error(action, saved[action]).is_empty(): result[action] = saved[action].duplicate()
		else: repaired_on_load = true
	# Reset only conflicting actions. Repeat because a restored default may
	# expose another old collision. Valid custom bindings and swaps survive.
	var original := default_bindings()
	for iteration in ACTIONS.size():
		var conflicts := {}
		for action in ACTIONS:
			var other := conflicting_action(action, result[action], result)
			if not other.is_empty(): conflicts[action] = true; conflicts[other] = true
		if conflicts.is_empty(): break
		repaired_on_load = true
		for action in conflicts: result[action] = original[action].duplicate()
	return result

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
	if not binding_error(action, data_from_event(event)).is_empty(): return
	for old in InputMap.action_get_events(action):
		if old is InputEventKey or old is InputEventMouseButton:
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)

func replace_bindings(next: Dictionary) -> bool:
	if not validation_error(next).is_empty(): return false
	if next == current_bindings(): return true
	if not _store_bindings(next): return false
	bindings = next.duplicate(true)
	for action in bindings:
		if ACTIONS.has(action):
			apply_binding(action, event_from_data(bindings[action]))
	return true

func _store_bindings(next: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.set_value("input", "bindings", next)
	var temporary := path() + ".tmp"
	var result := config.save(temporary)
	if result == OK: result = DirAccess.rename_absolute(temporary, path())
	if result != OK:
		DirAccess.remove_absolute(temporary)
		push_warning("Could not save input bindings")
		return false
	return true
