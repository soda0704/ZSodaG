class_name BasePowerLightingController
extends Node

signal lighting_state_changed(is_standard_powered: bool)

@export var gameplay_controller_path := NodePath("../BaseGameplayController")
@export var standard_lighting_path := NodePath(
	"../Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
	+ "Standard_Lighting_Blockout"
)
@export var emergency_lighting_path := NodePath(
	"../Floor_0_Base_Blockout/Power_State_Lighting_Blockout/"
	+ "Day1_Emergency_Lighting_Blockout"
)

var is_standard_powered: bool = false
var _gameplay_controller: BaseGameplayController
var _standard_lighting: Node3D
var _emergency_lighting: Node3D


func _ready() -> void:
	_gameplay_controller = get_node_or_null(
		gameplay_controller_path
	) as BaseGameplayController
	_standard_lighting = get_node_or_null(standard_lighting_path) as Node3D
	_emergency_lighting = get_node_or_null(emergency_lighting_path) as Node3D

	if _standard_lighting == null:
		push_warning("Base standard lighting layer was not found")
	if _emergency_lighting == null:
		push_warning("Base emergency lighting layer was not found")
	if _gameplay_controller == null:
		push_warning("BasePowerLightingController could not find gameplay state")
		apply_power_state(false, true)
		return

	if not _gameplay_controller.power_state_changed.is_connected(
		_on_power_state_changed
	):
		_gameplay_controller.power_state_changed.connect(
			_on_power_state_changed
		)
	apply_power_state(_gameplay_controller.main_breaker_on, true)


func apply_power_state(is_powered: bool, force: bool = false) -> void:
	var changed := is_standard_powered != is_powered
	is_standard_powered = is_powered
	if _standard_lighting != null:
		_standard_lighting.visible = is_standard_powered
	if _emergency_lighting != null:
		_emergency_lighting.visible = not is_standard_powered
	if changed or force:
		lighting_state_changed.emit(is_standard_powered)


func _on_power_state_changed(is_powered: bool) -> void:
	apply_power_state(is_powered)
