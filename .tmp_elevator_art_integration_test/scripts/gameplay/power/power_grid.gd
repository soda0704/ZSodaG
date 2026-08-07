class_name PowerGrid
extends Node

signal source_power_changed(is_powered: bool)

@export var generator_path: NodePath
@export var powered_device_paths: Array[NodePath] = []
@export var powered_light_paths: Array[NodePath] = []

var is_source_powered: bool = false
var _generator: GeneratorPanel
var _powered_devices: Array[Node] = []
var _powered_lights: Array[Light3D] = []


func _ready() -> void:
	_generator = get_node_or_null(generator_path) as GeneratorPanel
	for device_path in powered_device_paths:
		var device := get_node_or_null(device_path)
		if device == null or not device.has_method("set_source_powered"):
			push_warning("PowerGrid consumer is missing set_source_powered: %s" % device_path)
			continue
		_powered_devices.append(device)
	for light_path in powered_light_paths:
		var light := get_node_or_null(light_path) as Light3D
		if light == null:
			push_warning("PowerGrid light was not found: %s" % light_path)
			continue
		_powered_lights.append(light)

	if _generator == null:
		push_warning("PowerGrid generator was not found: %s" % generator_path)
		apply_source_power(false, true)
		return
	_generator.power_state_changed.connect(_on_generator_power_state_changed)
	apply_source_power(_generator.is_powered, true)


func apply_source_power(value: bool, instant: bool = false) -> void:
	var state_changed := is_source_powered != value
	is_source_powered = value
	for device in _powered_devices:
		device.call("set_source_powered", is_source_powered, instant)
	for light in _powered_lights:
		light.visible = is_source_powered
	if state_changed:
		source_power_changed.emit(is_source_powered)


func _on_generator_power_state_changed(value: bool) -> void:
	apply_source_power(value)
