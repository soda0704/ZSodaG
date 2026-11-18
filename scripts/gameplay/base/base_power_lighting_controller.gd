class_name BasePowerLightingController
extends Node

signal lighting_state_changed(is_standard_powered: bool)
@export var gameplay_controller_path := NodePath("../BaseGameplayController")
@export var standard_lighting_path := NodePath("../WorldLighting/Standard")
@export var emergency_lighting_path := NodePath("../WorldLighting/Emergency")
var is_standard_powered := false
var _standard_lighting: Node3D
var _emergency_lighting: Node3D
var _state: BaseGameplayController

func _ready() -> void:
	_standard_lighting = get_node_or_null(standard_lighting_path) as Node3D
	_emergency_lighting = get_node_or_null(emergency_lighting_path) as Node3D
	_state = get_node_or_null(gameplay_controller_path) as BaseGameplayController
	if _state != null:
		_state.power_state_changed.connect(_on_power_state_changed)
		_state.snapshot_changed.connect(_on_snapshot_changed)
	apply_power_state(_state.main_breaker_on if _state != null else false, true)

func apply_power_state(is_powered: bool, force: bool = false) -> void:
	# A containment fault trips the lighting circuit even while the breaker is on.
	var available := is_powered and not (_state != null and bool(_state.containment.get("fault", false)))
	var changed := available != is_standard_powered
	is_standard_powered = available
	if _standard_lighting != null: _standard_lighting.visible = available
	if _emergency_lighting != null: _emergency_lighting.visible = not available
	if changed or force: lighting_state_changed.emit(available)

func _on_power_state_changed(is_powered: bool) -> void:
	apply_power_state(is_powered)

func _on_snapshot_changed(_snapshot: Dictionary) -> void:
	apply_power_state(_state.main_breaker_on)
