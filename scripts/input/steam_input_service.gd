class_name SteamInputService
extends Node

signal availability_changed(is_available: bool)

const MANIFEST_PATH := "res://game_actions_480.vdf"
const GAMEPLAY_ACTION_SET := &"Gameplay"
const MENU_ACTION_SET := &"Menu"
const DIGITAL_GAMEPLAY_ACTIONS := {
	&"jump": &"jump",
	&"interact": &"interact",
	&"flashlight": &"flashlight",
	&"drop_item": &"drop_item",
	&"sprint": &"sprint",
	&"crouch": &"crouch",
	&"pause": &"pause",
}
const DIGITAL_MENU_ACTIONS := {
	&"menu_accept": &"ui_accept",
	&"menu_cancel": &"ui_cancel",
	&"menu_up": &"ui_up",
	&"menu_down": &"ui_down",
	&"menu_left": &"ui_left",
	&"menu_right": &"ui_right",
}

var native_input_available: bool = false
var _steam: Object
var _input_initialized: bool = false
var _gameplay_action_set_handle: int = 0
var _menu_action_set_handle: int = 0
var _move_action_handle: int = 0
var _look_action_handle: int = 0
var _digital_action_handles: Dictionary = {}
var _emitted_action_states: Dictionary = {}
var _using_menu_action_set: bool = true
var _known_controller_handles: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_godot_joypad_fallback()
	if DisplayServer.get_name() == "headless":
		return
	var steam_network := get_node_or_null("/root/SteamNetwork")
	if steam_network == null:
		return
	if not steam_network.steam_initialized.is_connected(_on_steam_initialized):
		steam_network.steam_initialized.connect(_on_steam_initialized)
	if not steam_network.steam_initialization_failed.is_connected(
		_on_steam_initialization_failed
	):
		steam_network.steam_initialization_failed.connect(
			_on_steam_initialization_failed
		)
	if bool(steam_network.get("steam_available")):
		initialize_native_input()


func _exit_tree() -> void:
	_release_all_actions()
	if _input_initialized and _steam != null:
		_steam.call("inputShutdown")


func _process(_delta: float) -> void:
	if not native_input_available:
		return
	var current_controllers := _get_connected_controllers()
	if current_controllers != _known_controller_handles:
		_known_controller_handles = current_controllers
		_activate_current_action_set()
	var wants_menu := _should_use_menu_action_set()
	if wants_menu != _using_menu_action_set:
		_using_menu_action_set = wants_menu
		_release_all_actions()
		_activate_current_action_set()
	_poll_digital_actions()


func initialize_native_input() -> bool:
	if _input_initialized:
		return native_input_available
	var steam_network := get_node_or_null("/root/SteamNetwork")
	if (
		not Engine.has_singleton("Steam")
		or steam_network == null
		or not bool(steam_network.get("steam_available"))
	):
		_set_native_input_available(false)
		return false

	_steam = Engine.get_singleton("Steam")
	var manifest_path := _get_manifest_path()
	if not FileAccess.file_exists(manifest_path):
		push_warning("Steam Input manifest is missing: %s" % manifest_path)
		_set_native_input_available(false)
		return false
	if not bool(_steam.call("setInputActionManifestFilePath", manifest_path)):
		push_warning("Steam rejected the NorthernLab Input Action Manifest")
		_set_native_input_available(false)
		return false
	if not bool(_steam.call("inputInit", false)):
		push_warning("Steam Input failed to initialize; Godot joypad fallback remains active")
		_set_native_input_available(false)
		return false
	_input_initialized = true
	_gameplay_action_set_handle = int(
		_steam.call("getActionSetHandle", str(GAMEPLAY_ACTION_SET))
	)
	_menu_action_set_handle = int(
		_steam.call("getActionSetHandle", str(MENU_ACTION_SET))
	)
	_move_action_handle = int(_steam.call("getAnalogActionHandle", "move"))
	_look_action_handle = int(_steam.call("getAnalogActionHandle", "look"))
	for steam_action in DIGITAL_GAMEPLAY_ACTIONS:
		_cache_digital_action_handle(steam_action)
	for steam_action in DIGITAL_MENU_ACTIONS:
		_cache_digital_action_handle(steam_action)

	var handles_are_valid := (
		_gameplay_action_set_handle != 0
		and _menu_action_set_handle != 0
		and _move_action_handle != 0
		and _look_action_handle != 0
	)
	_set_native_input_available(handles_are_valid)
	if not native_input_available:
		push_warning("Steam Input manifest loaded without the required action handles")
		return false
	_using_menu_action_set = _should_use_menu_action_set()
	_activate_current_action_set()
	print("Steam Input initialized with Gameplay and Menu action sets.")
	return true


func get_gameplay_move() -> Vector2:
	return _read_analog_action(_move_action_handle)


func get_gameplay_look() -> Vector2:
	return _read_analog_action(_look_action_handle)


func get_connected_controller_count() -> int:
	return _get_connected_controllers().size()


func _get_manifest_path() -> String:
	var executable_manifest := OS.get_executable_path().get_base_dir().path_join(
		MANIFEST_PATH.get_file()
	)
	if not OS.has_feature("editor") and FileAccess.file_exists(executable_manifest):
		return executable_manifest.replace("\\", "/")
	return ProjectSettings.globalize_path(MANIFEST_PATH).replace("\\", "/")


func _read_analog_action(action_handle: int) -> Vector2:
	if (
		not native_input_available
		or _using_menu_action_set
		or action_handle == 0
	):
		return Vector2.ZERO
	var strongest_value := Vector2.ZERO
	for controller_handle in _get_connected_controllers():
		var data := _steam.call(
			"getAnalogActionData",
			int(controller_handle),
			action_handle
		) as Dictionary
		if not bool(data.get("active", false)):
			continue
		var value := Vector2(
			float(data.get("x", 0.0)),
			float(data.get("y", 0.0))
		)
		if value.length_squared() > strongest_value.length_squared():
			strongest_value = value
	return strongest_value


func _poll_digital_actions() -> void:
	var action_map: Dictionary = (
		DIGITAL_MENU_ACTIONS
		if _using_menu_action_set
		else DIGITAL_GAMEPLAY_ACTIONS
	)
	var controllers := _get_connected_controllers()
	for steam_action in action_map:
		var is_pressed := false
		var action_handle := int(_digital_action_handles.get(steam_action, 0))
		if action_handle != 0:
			for controller_handle in controllers:
				var data := _steam.call(
					"getDigitalActionData",
					int(controller_handle),
					action_handle
				) as Dictionary
				if (
					bool(data.get("active", false))
					and bool(data.get("state", false))
				):
					is_pressed = true
					break
		_emit_action_state(action_map[steam_action], is_pressed)


func _emit_action_state(action: StringName, is_pressed: bool) -> void:
	var was_pressed := bool(_emitted_action_states.get(action, false))
	if was_pressed == is_pressed:
		return
	_emitted_action_states[action] = is_pressed
	var event := InputEventAction.new()
	event.action = action
	event.pressed = is_pressed
	event.strength = 1.0 if is_pressed else 0.0
	Input.parse_input_event(event)


func _release_all_actions() -> void:
	for action in _emitted_action_states.keys():
		if bool(_emitted_action_states[action]):
			_emit_action_state(action, false)
	_emitted_action_states.clear()


func _activate_current_action_set() -> void:
	var action_set_handle := (
		_menu_action_set_handle
		if _using_menu_action_set
		else _gameplay_action_set_handle
	)
	if action_set_handle == 0:
		return
	for controller_handle in _get_connected_controllers():
		_steam.call(
			"activateActionSet",
			int(controller_handle),
			action_set_handle
		)


func _ensure_godot_joypad_fallback() -> void:
	_add_joy_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"move_backward", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis(&"look_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis(&"look_right", JOY_AXIS_RIGHT_X, 1.0)
	_add_joy_axis(&"look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis(&"look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_button(&"jump", JOY_BUTTON_A)
	_add_joy_button(&"crouch", JOY_BUTTON_B)
	_add_joy_button(&"interact", JOY_BUTTON_X)
	_add_joy_button(&"flashlight", JOY_BUTTON_Y)
	_add_joy_button(&"drop_item", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button(&"sprint", JOY_BUTTON_LEFT_STICK)
	_add_joy_button(&"pause", JOY_BUTTON_START)
	_add_joy_button(&"ui_accept", JOY_BUTTON_A)
	_add_joy_button(&"ui_cancel", JOY_BUTTON_B)
	_add_joy_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0)


func _add_joy_button(action: StringName, button_index: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _add_joy_axis(
	action: StringName,
	axis: JoyAxis,
	axis_value: float
) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	if not InputMap.action_has_event(action, event):
		InputMap.action_add_event(action, event)


func _should_use_menu_action_set() -> bool:
	var current_scene := get_tree().current_scene
	var game_menu := get_node_or_null("/root/GameMenu")
	return (
		current_scene == null
		or current_scene.is_in_group("main_menu")
		or (game_menu != null and bool(game_menu.call("is_menu_open")))
		or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	)


func _get_connected_controllers() -> Array:
	if not native_input_available or _steam == null:
		return []
	var controllers: Variant = _steam.call("getConnectedControllers")
	if controllers is Array:
		return controllers
	if controllers is PackedInt64Array:
		return Array(controllers)
	return []


func _cache_digital_action_handle(action_name: StringName) -> void:
	_digital_action_handles[action_name] = int(
		_steam.call("getDigitalActionHandle", str(action_name))
	)


func _set_native_input_available(value: bool) -> void:
	if native_input_available == value:
		return
	native_input_available = value
	availability_changed.emit(value)


func _on_steam_initialized(_user_name: String) -> void:
	initialize_native_input()


func _on_steam_initialization_failed(_reason: String) -> void:
	_set_native_input_available(false)
